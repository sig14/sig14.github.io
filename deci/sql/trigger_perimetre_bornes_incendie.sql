---------------
-- mise en place tables refs initiales
----------------
CREATE TABLE IF NOT EXISTS sdis.points_eau_incendie
(
    objectid integer ,
    num character varying(200) COLLATE pg_catalog."default",
    famille_id character varying(200) COLLATE pg_catalog."default",
    type_cod character varying(200) COLLATE pg_catalog."default",
    dept_cod character varying(200) COLLATE pg_catalog."default",
    comm_cod character varying(200) COLLATE pg_catalog."default",
    etat_cod character varying(200) COLLATE pg_catalog."default",
    debit_1_bar character varying(200) COLLATE pg_catalog."default",
    capacite character varying(200) COLLATE pg_catalog."default",
    date_ct character varying(200) COLLATE pg_catalog."default",
    date_ro character varying(200) COLLATE pg_catalog."default",
    geom geometry(Point,2154),
    CONSTRAINT points_eau_incendie_pkey PRIMARY KEY (objectid));


CREATE INDEX IF NOT EXISTS points_eau_incendie_geom
    ON sdis.points_eau_incendie USING gist
    (geom);

CREATE SEQUENCE IF NOT EXISTS sdis.points_eau_incendie_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 2147483647
    CACHE 1
    OWNED BY sdis.points_eau_incendie.objectid;

ALTER TABLE sdis.points_eau_incendie ALTER objectid SET DEFAULT NEXTVAL('sdis.points_eau_incendie_id_seq');



CREATE TABLE sdis.deci_p400m (
id integer NOT NULL ,
id_pei integer    ,
    cat integer,
	geom geometry(MultiPolygon,2154),
    CONSTRAINT deci_p400m_pkey PRIMARY KEY (id)
);

CREATE TABLE sdis.deci_p200m (
id integer NOT NULL ,
id_pei integer    ,
    cat integer,
	geom geometry(MultiPolygon,2154),
    CONSTRAINT deci_p200m_pkey PRIMARY KEY (id)
);

CREATE SEQUENCE IF NOT EXISTS sdis.deci_p200m_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 2147483647
    CACHE 1
    OWNED BY sdis.deci_p200m.id;

ALTER TABLE sdis.deci_p200m ALTER id SET DEFAULT NEXTVAL('sdis.deci_p200m_id_seq');

create unique index on sdis.deci_p200m (id);
	create index on sdis.deci_p200m using gist(geom);

ALTER SEQUENCE sdis.deci_p200m_id_seq
    OWNER TO lizmap;

CREATE SEQUENCE IF NOT EXISTS sdis.deci_p400m_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 2147483647
    CACHE 1
    OWNED BY sdis.deci_p400m.id;

ALTER TABLE sdis.deci_p400m ALTER id SET DEFAULT NEXTVAL('sdis.deci_p400m_id_seq');

ALTER SEQUENCE sdis.deci_p400m_id_seq
    OWNER TO lizmap;



create unique index on sdis.deci_p400m (id);
	create index on sdis.deci_p400m using gist(geom);


------------------------
-- Fonction trigger perimètre borne incendie
------------------------

CREATE OR REPLACE FUNCTION sdis.perimetre_bornes_incendie()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE 
geom_buffer_400 geometry;
geom_buffer_200 geometry;
BEGIN

CREATE UNLOGGED TABLE IF NOT EXISTS route_deci --- création d'une table temporaire qui sélectionne les segments_deci dans un buffer de 500 mètre autour du nouveau point créé
as 
select r.* 
from sdis.route_deci_segments r
where st_intersects(r.geom, st_buffer(NEW.geom, 500, 'quad_segs=8')) ;

CREATE  INDEX route_deci_idx ON route_deci (id);---création d'un indexe sur l'id de la table

CREATE INDEX route_deci_geom --- création d'un indexe sur la geom de la table
        ON route_deci USING gist (geom)
        TABLESPACE pg_default;

with resultat as (-- lancement réursive
	with recursive search_graph (id, _n1, _n2, meters,  path_id, geom_initiale)  as (-- paramètres récursive
		with premier_troncon as (
			-- On cherche le segment le plus proche de la borne de départ
			-- Attention, il faut prendre en compte la courbe s'il y en a une 
			-- d'où l'utilisation de ST_LineLocatePoint (un st_distance aurait été imprécis)
			select r.*, st_length(r.geom) * ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom)) as longueur_depart, ---fraction de la longeur du segment de départ au niveau du point projeté sur le segment le plus proche
				ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom))  as fraction --- fraction du segment de départ au niveau du point projeté sur le segment le plus proche
			from route_deci r
			where st_intersects(st_buffer(r.geom, 40),NEW.geom) -- segment de départ à 40 mètre du point créé
			order by st_distance (NEW.geom, r.geom) limit 1-- On garde seulement un segment (le plus proche)
		),
		n1_distance as (
			-- on récupère pour le premier segement, juste une fraction (car la borne n'est pas située
			-- pile à une extrémité
			select longueur_depart  as dist_n1, st_linesubstring(p.geom, 0, fraction) as n1_geom -- ici on stocke la fraction de geom à parcourir
			from premier_troncon p
		),
		n2_distance as (
			-- idem pour le deuxième noeud
			select st_length(geom) - longueur_depart as dist_n2, st_linesubstring(p.geom, fraction, 1) as n2_geom -- On calcul la longeur 2e fraction du segement en soustrayant la longeur de la 1ere fraction à la longeur du segment . On stocke également la geom à parcourir
			from premier_troncon p
		)
		-- Enfin, on prépare la requête initiale
		select id,   n1 , null as n2 , dist_n1 as meters, ARRAY[p.id] as path_id,  n1_geom as geom_initiale -- on récupérer la valeur du noeud 1, null pour noeud 2 pour ne pas associer des segment du mauvais coté dans la recursive. On stocke également l'id (array)
		from n1_distance, premier_troncon p 
		union -- pour partir dans les deux direction (noeud 1 et noeud 2)
		select id,  null as n1, n2 ,  dist_n2 as meters, ARRAY[p.id] as path_id, n2_geom as geom_initiale-- idem que pour la première direction. null au n1 pour ne pas associer des segments de ce coté.
		from n2_distance, premier_troncon p 

		UNION -- union pour la recursivité

			select distinct on (ng.id)
				ng.id,
				ng._n1, 
				ng._n2, 
				ng.meters + st_length(ng.geom),-- on ajoute la longeur du nouveau segment associé à la distance cumulée
				ng.path_id || ng.id,
				ng.geom_initiale
			from 
			(
				select r.id,
					 r.n1
					 as _n1,
					 r.n2  as _n2,
					sg.meters, -- distance cumulée
					sg.path_id,
					r.geom, -- geométrie du segment en cours de parcours
					sg.geom_initiale -- géométrie de départ (fraction du premie rsegement, en fonction de la projection de la borne dessus)
				from search_graph sg, route_deci r
				where (
					sg._n2 = r.n1 or sg._n1 = r.n2  -- on cherche tout n1 ou n2 qui correspond à la fin de notre segment courant 
					or sg._n1 = r.n1 or sg._n2 = r.n2
				) 
			) ng	

			where 
				ng.meters < 360  -- filtre sur la distance max 
	)  
	select sg.id, sg._n1, sg._n2, sg.meters,  r.geom, sg.geom_initiale
	from search_graph sg
	join route_deci r on r.id = sg.id
),
troncons_valides as (
	-- on prend tous les segments dont on est sûr qu'ils seront dans la sélection
	select * from resultat where meters <= 360
),
troncons_a_fractionner as (
	-- on isole les segments qui "dépassent"
	select * from resultat where meters > 360
),
fractions as (
	-- traitement sur les segments qui "dépassent" les 400m
	select t.id, 
					case 
			-- on vérifie le sens du segement pour faire la bonne fraction
			when t._n1 = r._n1 or t._n1 = r._n2 and (t._n1 is not null or t._n2 is not null) then --- si le segement n'est pas le segment initial (pas de noeuds null)
				st_linesubstring(t.geom, 0, (st_length(t.geom)-(t.meters - 360)) / st_length(t.geom))

	        when t._n2 = r._n2 or t._n2 = r._n1 and (t._n1 is not null or t._n2 is not null) then
	            st_linesubstring(st_reverse(t.geom), 0,   (st_length(t.geom) - (t.meters - 360)) / st_length(t.geom)) --- si le segement n'est pas le segment initial  (pas de noeuds null)
		    when t._n2 is null then --- si le segement initial fraction 1 (noeud 2 est null)
						st_linesubstring(st_reverse(t.geom_initiale), 0,   (st_length(t.geom_initiale) - (t.meters - 360)) / st_length(t.geom_initiale)) 

			when t._n1 is null then --- si le segement initial fraction 2 (noeud 1 est null)
            st_linesubstring(t.geom_initiale, 0, (st_length(t.geom_initiale)-(t.meters - 360)) / st_length(t.geom_initiale))

    end as geom
	from troncons_a_fractionner t
	left join troncons_valides r on t._n2 = r._n1 or t._n1 = r._n2  
					or t._n1 = r._n1 or t._n2 = r._n2 
),
final as (
	select id ,  st_buffer(geom_initiale, 40) as geom  from troncons_valides -- on récupere le buffer 40m de la geom des fraction de segments initiale 
		union
		select id ,  st_buffer(geom, 40) as geom  from troncons_valides where st_length(geom) <= 360 -- on récupere le buffer 40m  de la geom des segments qui font moins de 400 mètres
		union
	select id ,  st_buffer(geom, 40) as geom   from fractions -- on récupère le buffer 40m des geom des fractions de segments qui dépassent 400 mètres
)
select ST_Multi(st_union(geom)) into geom_buffer_400 -- on unie les geom buffer en MULTI* geometry collection
from final;

----------------------------------------------------------------------------------------------
---perimètre 200 mètres-- idem que pour 400 mètres
----------------------------------------------------------------------------------------------
with resultat as (
	with recursive search_graph (id, _n1, _n2, meters, path_id,  geom_initiale)  as (
		with premier_troncon as (
						select r.*, st_length(r.geom) * ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom)) as longueur_depart, 
				ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom))  as fraction
			from route_deci r
			where st_intersects(st_buffer(r.geom, 40),NEW.geom)
			order by st_distance (NEW.geom, r.geom) limit 1
		),
		n1_distance as (
			
			select longueur_depart  as dist_n1, st_linesubstring(p.geom, 0, fraction) as n1_geom 
			from premier_troncon p
		),
		n2_distance as (
			select st_length(geom) - longueur_depart as dist_n2, st_linesubstring(p.geom, fraction, 1) as n2_geom
			from premier_troncon p
		)
		select id,  n1, null as n2, dist_n1 as meters, ARRAY[p.id] as path_id,  n1_geom as geom_initiale
		from n1_distance, premier_troncon p 
		union 
		select id,   null as n1, n2,  dist_n2 as meters, ARRAY[p.id] as path_id, n2_geom as geom_initiale
		from n2_distance, premier_troncon p 

		UNION 

			select distinct on (ng.id)
				ng.id,
				ng._n1, 
				ng._n2, 
				ng.meters + st_length(ng.geom),
				ng.path_id || ng.id,
				ng.geom_initiale
			from 
			(
				select r.id,
					
					 r.n1
					 as _n1,
					 r.n2
					 as _n2,
					sg.meters, 
					sg.path_id,
					r.geom, 
					sg.geom_initiale 
				from search_graph sg, route_deci r
				where (
					sg._n2 = r.n1 or sg._n1 = r.n2  
					or sg._n1 = r.n1 or sg._n2 = r.n2   
				) 
			) ng	

			
			where 
				ng.meters < 160 and not (ng.id = ANY(ng.path_id))
	)
	select sg.id, sg._n1, sg._n2, sg.meters, r.geom, sg.geom_initiale
	from search_graph sg
	join route_deci r on r.id = sg.id
),
troncons_valides as (
	
	select * from resultat where meters <= 160
),
troncons_a_fractionner as (
	
	select * from resultat where meters > 160
),
fractions as (
	-- traitement sur les segments qui "dépassent" les 200m
	select t.id, 
					case 
			-- on vérifie le sens du segement pour faire la bonne fraction
			when t._n1 = r._n1 or t._n1 = r._n2 and (t._n1 is not null or t._n2 is not null) then
				st_linesubstring(t.geom, 0, (st_length(t.geom)-(t.meters - 160)) / st_length(t.geom))
	        when t._n2 = r._n2 or t._n2 = r._n1 and (t._n1 is not null or t._n2 is not null) then
	            st_linesubstring(st_reverse(t.geom), 0,   (st_length(t.geom) - (t.meters - 160)) / st_length(t.geom)) 
		     when t._n2 is null then
			 			st_linesubstring(st_reverse(t.geom_initiale), 0,   (st_length(t.geom_initiale) - (t.meters - 160)) / st_length(t.geom_initiale)) 

			when t._n1 is null then
			            st_linesubstring(t.geom_initiale, 0, (st_length(t.geom_initiale)-(t.meters - 160)) / st_length(t.geom_initiale))

    end as geom
	from troncons_a_fractionner t
	left join troncons_valides r on t._n2 = r._n1 or t._n1 = r._n2  
					or t._n1 = r._n1 or t._n2 = r._n2 	
),
final as (
	select id ,  st_buffer(geom_initiale, 40) as geom  from troncons_valides
	union
		select id ,  st_buffer(geom, 40) as geom  from troncons_valides where st_length(geom) <= 160
	union
	select id ,  st_buffer(geom, 40) as geom   from fractions
)
select ST_Multi(st_union(geom)) into geom_buffer_200
from final;

IF TG_OP = 'INSERT' THEN -- si insertion d'un point borne incendie

INSERT into sdis.deci_p400m(id_pei, geom) VALUES(NEW.objectid, geom_buffer_400);

INSERT into sdis.deci_p200m(id_pei, geom) VALUES(NEW.objectid, geom_buffer_200);
DROP TABLE route_deci;

RETURN NEW;
END IF;

IF TG_OP = 'UPDATE' THEN -- si MAJ d'un point borne incendie

update sdis.deci_p400m set geom = geom_buffer_400 where deci_p400m.id_pei = NEW.objectid;
update sdis.deci_p200m set geom = geom_buffer_200 where deci_p200m.id_pei = NEW.objectid;
DROP TABLE route_deci;

RETURN NEW;
END IF;

IF TG_OP = 'DELETE' THEN -- si supression d'un point borne incendie

DELETE  FROM sdis.deci_p400m  where deci_p400m.id_pei = OLD.objectid;
DELETE  FROM sdis.deci_p200m  where deci_p200m.id_pei = OLD.objectid;
DROP TABLE route_deci;

RETURN OLD;
END IF;

END;
$BODY$;

CREATE TRIGGER perimetre_borne
    AFTER INSERT OR UPDATE OF geom OR DELETE
    ON sdis.points_eau_incendie
    FOR EACH ROW
    EXECUTE FUNCTION sdis.perimetre_bornes_incendie();





create table sdis.type_pei(
	id integer not null,
    id_famille                       VARCHAR (50) ,
	desc_famille                       VARCHAR (50) ,
	id_type                   VARCHAR (100) ,
	desc_type                     VARCHAR (255) ,
	CONSTRAINT type_pei_PK PRIMARY KEY (id)
); 

CREATE SEQUENCE sdis.type_pei_id_seq
    START WITH 243
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE sdis.type_pei ALTER id SET DEFAULT NEXTVAL('sdis.type_pei_id_seq');

insert into sdis.type_pei(id_famille, desc_famille, id_type, desc_type) VALUES
(1, 'Poteau', 'P00', 'Poteau de xx m3 / 1 prise'),
(1, 'Poteau', 'P01', 'Poteau de xx m3 / 2 prise'),
(1, 'Poteau', 'P02', 'Poteau de xx m3 / 3 prise'),
(1, 'Poteau', 'P03', 'Poteau de xx m3 / 4 prise'),
(1, 'Poteau', 'P04', 'Poteau de xx m3 / 5 prise'),
(1, 'Poteau', 'P05', 'Poteau de xx m3 / 6 prise'),
(1, 'Poteau', 'P06', 'Poteau de xx m3 / 7 prise'),
(1, 'Poteau', 'P07', 'Poteau de xx m3 / 8 prise'),
(1, 'Poteau', 'P08', 'Poteau de xx m3 / 9 prise'),
(1, 'Poteau', 'P09', 'Poteau de xx m3 / 10 prise'),
(1, 'Poteau', 'P10', 'Poteau de xx m3 / 11 prise'),
(1, 'Poteau', 'P11', 'Poteau de xx m3 / 12 prise'),

(2, 'Bouche','B00','Bouche de xx m3 / 1 prise'),
(2, 'Bouche','B01','Bouche de xx m3 / 2 prises'),
(2, 'Bouche','B02','Bouche de xx m3 / 3 prise'),
(2, 'Bouche','B03','Bouche de xx m3 / 4 prise'),
(2, 'Bouche','B04','Bouche de xx m3 / 5 prise'),
(2, 'Bouche','B05','Bouche de xx m3 / 6 prise'),

(3, 'Aspiration','A01','Réserve non-renseignée'),
(3, 'Aspiration','A02','Réserve de xx m3 / 1 prise'),
 (3, 'Aspiration','A03','Réserve de xx m3 / 2 prises')

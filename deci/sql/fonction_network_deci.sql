--- Fonction créant les segments bdtopo avec numero de noeuds segments n1 et n2


CREATE OR REPLACE FUNCTION create_network_deci()
 RETURNS void
 LANGUAGE plpgsql
AS $$
DECLARE
	n int := 1;
	_n1 int;
	_n2 int;
	pt geometry;
	rec record;
	points geometry[];
	indexe int[];
	pos int;
BEGIN
	drop table if exists sdis.route_deci_segments;
	create table sdis.route_deci_segments as
	select
	  row_number() over () as id,
	  a.id as oid,
	  dump.geom
	from
	  sdis."2d_deci_bdtopo" a,
	  st_dump(geom) as dump
	 
	  ; 
	  
RAISE NOTICE 'table segment créé';
	create unique index on sdis.route_deci_segments (id);
	create index on sdis.route_deci_segments using gist(geom);
RAISE NOTICE 'indexes créés';
	alter table sdis.route_deci_segments add n1 int;
	alter table sdis.route_deci_segments add n2 int;
RAISE NOTICE 'champs n2, n1 créés'	;
	for rec in select * from sdis.route_deci_segments loop
		-- Première extrémité
		pt = st_startpoint(rec.geom);
		-- On cherche si ce point a déjà un numéro de noeud
		pos := array_position(points, pt);
		if pos is NULL then -- le point n'est pas encore indexé
			-- on crée un numéro et on l'insère
			update sdis.route_deci_segments set n1 = n where id = rec.id;
			points = array_append(points, pt);
			indexe = array_append(indexe, n);
			n := n + 1;
		else
			-- on prend le numéro existant
			pos := array_position(points, pt);
			update sdis.route_deci_segments set n1 = indexe[pos] where id = rec.id;
		end if;

		-- Seconde extrémité
		pt = st_endpoint(rec.geom);
		pos := array_position(points, pt);
		-- On cherche si ce point a déjà un numéro de noeud
		if pos is NULL then -- le point n'est pas encore indexé
			-- on crée un numéro et on l'insère
			update sdis.route_deci_segments set n2 = n where id = rec.id;
			points = array_append(points, pt);
			indexe = array_append(indexe, n);
			n := n + 1;
		else
			-- on prend le numéro existant
			pos := array_position(points, pt);
			update sdis.route_deci_segments set n2 = indexe[pos] where id = rec.id;
		end if;
	end loop;
	
END;
$$
;



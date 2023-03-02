BEGIN;

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch ;
--
-- Début FONCTIONS
--


--------------------------------------------------------------------------------------
--- C1 T2: Identifier les	points adresse pair ou impair du mauvais coté de la voie
------------------------------------------------------------------------------------------


--  Fonction qui projete le point sur sa voix de rattachement (elle retourne une valeur correspondant au geom du point projeté) -------------

Create or replace function  adresse.point_proj(pgeom geometry, idv integer)
RETURNS TEXT
AS $BODY$
DECLARE 
locate_point DOUBLE PRECISION;
geom_pt_proj TEXT;
BEGIN
/* Cette requête créer un point à partir de la localisation du point le proche du point adresse d’entré, sur la ligne possédant le même id_voie que ce point d’entré
*/

SELECT st_linelocatepoint(voie.geom, pgeom) into locate_point
   FROM adresse.voie
  WHERE  voie.id_voie = idv;

IF locate_point >1 OR locate_point <0

THEN

SELECT ST_AsText(ST_ClosestPoint(voie.geom, pgeom)) into geom_pt_proj
FROM adresse.voie
WHERE voie.id_voie = idv;

ELSE

SELECT ST_AsText(ST_LineInterpolatePoint(voie.geom, locate_point)) into geom_pt_proj
FROM adresse.voie
WHERE voie.id_voie = idv;

END IF ;

RETURN geom_pt_proj; -- Retourne la géométrie du point projeté sur la voie
END;
$BODY$ LANGUAGE 'plpgsql';



--- FONCTION qui dessine un sgement du point adresse à un point projeté au 50/49e de la distance entre le point adresse et son point projeté 

Create or replace function  adresse.segment_prolong(ptgeom geometry, ptgeom_proj TEXT)
RETURNS TEXT
AS $BODY$
DECLARE 
geom_segment_prolong TEXT;
BEGIN
/* Cette requête dessine un segment du point adresse à un point projeté au 50/49e de la distance entre le point adresse et son point projeté.
*/
SELECT 
ST_AsText(ST_MakeLine(ptgeom,  
(ST_TRANSLATE(ptgeom, sin(ST_AZIMUTH(ptgeom, ST_GeomFromText(ptgeom_proj, 2154))) * (ST_DISTANCE(ptgeom,ST_GeomFromText(ptgeom_proj, 2154))
+ (ST_DISTANCE(ptgeom,ST_GeomFromText(ptgeom_proj, 2154)) * (50/49))), cos(ST_AZIMUTH(ptgeom,ST_GeomFromText(ptgeom_proj, 2154))) * (ST_DISTANCE(ptgeom,ST_GeomFromText(ptgeom_proj, 2154))
+ (ST_DISTANCE(ptgeom,ST_GeomFromText(ptgeom_proj, 2154)) * (50/49))))))) into geom_segment_prolong ;

RETURN geom_segment_prolong; -- Retourne la géométrie du segement prolongé
END;
$BODY$ LANGUAGE 'plpgsql';





--- Fonction qui trouve les points à droites et à gauche

Create or replace function  adresse.f_cote_voie(idv integer, geom_segment TEXT)
RETURNS TEXT
AS $BODY$
DECLARE 
cote_voie TEXT;
BEGIN

/* Cette requête identifie si le segment prolongé crée à partir du point projeté sur la voie de rattachement du point adresse, 
croise la ligne à gauche, à droite, ne croise pas ou croise plusieurs fois.
*/
SELECT case 
WHEN ST_LineCrossingDirection(ST_GeomFromText(geom_segment, 2154), v.geom) = -1 then 'gauche'
WHEN ST_LineCrossingDirection(ST_GeomFromText(geom_segment, 2154), v.geom ) = 1 then 'droite'
WHEN ST_LineCrossingDirection(ST_GeomFromText(geom_segment, 2154), v.geom ) = 0 then 'indefini'
ELSE 'probleme' 
end into cote_voie
from adresse.voie v
WHERE idv = v.id_voie;

RETURN  cote_voie; -- Retourne le text définissant le coté de la voie duquel se trouve le point
END;
$BODY$ LANGUAGE 'plpgsql';



--- Fonction qui identifie les	points adresse pair ou impair du mauvais coté de la voie
     

Create or replace function  adresse.c_erreur_cote_parite(numero integer, cote_voie text)
RETURNS TEXT
AS $BODY$
DECLARE erreur_cote_parite text;

BEGIN
/* identifie si le côté duquel se trouve le point adresse correspond à la parité de son numéro
*/
SELECT case 
WHEN cote_voie = 'gauche' AND numero % 2=0 then 'true'
WHEN cote_voie = 'droite' AND numero % 2!=0 then 'true'
WHEN cote_voie = 'droite' AND numero % 2=0 then 'false'
WHEN cote_voie = 'gauche' AND numero % 2!=0 then 'false'
WHEN cote_voie = 'indefini' then 'indefini'
ELSE 'probleme' 
end into erreur_cote_parite;

RETURN  erreur_cote_parite; -- Retourne True si le point adresse est du mauvais coté de la voie. Sinon false ou indefini. Si problème, cela signifie une erreur de tracé sur la voie
END;
$BODY$ LANGUAGE 'plpgsql';



 




------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Contrôle 2 : Détecter les erreurs de tracé de voies _ A complèter avec la vue v_c2_line_cross pour identifier les portions problèmatiques
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--  EXTRAIRE LES SEGMENTS DE POLYLIGNE
Create or replace function  adresse.segment_extract(table_name varchar, id_line varchar, geom_line varchar)
RETURNS TABLE ( id bigint,  id_voie integer, geom_segment geometry ) -- retourne une table avec les id segment, leur id_voie et leurs géométries
AS $BODY$
BEGIN

/* Cette requête sélectionne les nœuds des voies. Puis trace des lignes entre les différents nœuds crées en leur attibuant des identifiants uniques et en conservant les id_voies de la voie d'origine.
*/
Return query execute
'SELECT * from (SELECT ROW_NUMBER() OVER() as id, dumps.id_voie, ST_MakeLine(lag((pt).geom, 1, NULL) OVER (PARTITION BY dumps.id_voie ORDER BY dumps.id_voie, (pt).path), (pt).geom) AS geom_segment
  FROM (SELECT '||id_line||' as id_voie, '||geom_line||' as geom, ST_DumpPoints('||geom_line||') AS pt from '||table_name||') dumps)s WHERE s.geom_segment IS NOT NULL';

END;
$BODY$ LANGUAGE 'plpgsql';





--  CREER CENTROID  1/3 DES SEGMENTS, ROTATIONS 

Create or replace function  adresse.line_rotation(lgeom geometry)
RETURNS GEOMETRY
AS $BODY$
DECLARE 
geom_rotate GEOMETRY; 
BEGIN
/* Cette requête effectue une rotation à 80,1 degrès d’1/3 du segment au niveau de son centroide
*/
SELECT ST_CollectionExtract(st_rotate(ST_LineSubstring(lgeom, 0.333 ::real, 0.666::real), 80.1, st_centroid(lgeom)), 2) into geom_rotate; 

RETURN geom_rotate; -- retourne la géométrie du segment retourné
END;
$BODY$ LANGUAGE 'plpgsql';





--
-- Début TABLE_sequence
--


------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TABLE adresse.point_adresse
-------------------------------------------------------------------------------------------------------------------------------------------------------

-- point_adresse.c_erreur_voie


ALTER TABLE adresse.point_adresse
ADD COLUMN c_erreur_dist_voie BOOLEAN  ;


--- point_adresse.c_dist_voie

ALTER TABLE adresse.point_adresse
ADD COLUMN c_dist_voie  integer ;


-- point_adresse.geom_pt_proj


ALTER TABLE adresse.point_adresse
ADD COLUMN geom_pt_proj TEXT  ;




-- point_adresse.geom_segment_prolong

ALTER TABLE adresse.point_adresse
ADD COLUMN geom_segment_prolong TEXT  ;




-- point_adresse.cote_voie

ALTER TABLE adresse.point_adresse
ADD COLUMN cote_voie TEXT ;


-- point_adresse.c_erreur_cote_parite

ALTER TABLE adresse.point_adresse
ADD COLUMN c_erreur_cote_parite TEXT ;







------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  TABLE adresse.voie
------------------------------------------------------------------------------------------------------------------------------------------------------------------------


--- voie.c_erreur_trace

ALTER TABLE adresse.voie
ADD COLUMN c_erreur_trace  BOOLEAN   ;



---voie.c_repet_nom_voie

ALTER TABLE adresse.voie
ADD COLUMN c_repet_nom_voie BOOLEAN   ;



---voie.c_long_nom

  ALTER TABLE adresse.voie
ADD COLUMN  c_long_nom  BOOLEAN  ; 



---voie.c_saisie_double

ALTER TABLE adresse.voie
ADD COLUMN c_saisie_double BOOLEAN  ; 




-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TABLE adresse.parcelle
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- parcelle.nb_pt_adresse 

ALTER TABLE adresse.parcelle
ADD COLUMN nb_pt_adresse  INTEGER  ;


--- parcelle.date_pt_modif 


ALTER TABLE adresse.parcelle
ADD COLUMN date_pt_modif  DATE  ; 




------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TABLE adresse.commune
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- commune.pt_hors_parcelle 

ALTER TABLE adresse.commune
ADD COLUMN pt_hors_parcelle  INTEGER  ;

--- commune.pt_hors_parcelle_valid
ALTER TABLE adresse.commune
ADD COLUMN pt_hors_parcelle_valid INTEGER  ;

--- commune.nb_pt_valide 
ALTER TABLE adresse.commune
ADD COLUMN nb_pt_valide      INTEGER  ; 

--- commune.nb_pt_erreur 
ALTER TABLE adresse.commune
ADD COLUMN nb_pt_erreur      INTEGER  ;

--- commune.nb_a_verif
ALTER TABLE adresse.commune
ADD COLUMN nb_a_verif        INTEGER  ;

--- commune.nb_pt_no_valid
ALTER TABLE adresse.commune
ADD COLUMN nb_pt_no_valid    INTEGER  ;

--- commune.pt_total 
ALTER TABLE adresse.commune
ADD COLUMN pt_total          INTEGER  ;

--- commune.pct_pt_reel_valid 
ALTER TABLE adresse.commune
ADD COLUMN pct_pt_reel_valid INTEGER  ;

---commune.voie_non_valid

ALTER TABLE adresse.commune
ADD COLUMN voie_non_valid INTEGER ;

---commune.voie_valid
ALTER TABLE adresse.commune
ADD COLUMN voie_valid INTEGER  ;

---commune.pct_voie_valid
ALTER TABLE adresse.commune
ADD COLUMN pct_voie_valid      INTEGER ;

---commune.voie_total 
ALTER TABLE adresse.commune
ADD COLUMN voie_total INTEGER ;

--
-- Fin TABLE_SEQUENCE
--

--
-- Début VIEW
--

-- VUE Contrôle : Détecter les erreurs de tracé de voies ----- Faire tourner en PGCRON

drop materialized view if exists adresse.v_controle_voie;
create materialized view adresse.v_controle_voie as
Select r.id, r.id_voie, r.geom_segment, r.geom_rotate, r.erreur_voie
from
(select id, segment_extract.id_voie, geom_segment, adresse.line_rotation(geom_segment) as geom_rotate,
ST_LineCrossingDirection(adresse.line_rotation(geom_segment), voie.geom) = '-2' or  ST_LineCrossingDirection(adresse.line_rotation(geom_segment), voie.geom) = '2'
or ST_LineCrossingDirection(adresse.line_rotation(geom_segment), voie.geom) = '3' or ST_LineCrossingDirection(adresse.line_rotation(geom_segment), voie.geom) = '-3' as erreur_voie
from adresse.segment_extract('adresse.voie', 'voie.id_voie', 'voie.geom'), adresse.voie
where voie.id_voie =  segment_extract.id_voie)r
where r.erreur_voie = true;


-- VUE lien points adresse voies rattachement :

create view adresse.v_lien_pa_voie as select p.id_point, p.id_voie, c_dist_voie, ST_MakeLine(p.geom, ST_GeomFromText(p.geom_pt_proj, 2154)) as geom
from adresse.point_adresse p ;
--
-- Fin VIEW
--




--
-- Début COMMENT
--


-- point_adresse.c_erreur_dist_voie
COMMENT ON COLUMN adresse.point_adresse.c_erreur_dist_voie IS 'identifie les points adresse plus près d’une autre voie que celle à laquelle il appartient';

-- point_adresse.c_point_voie_distant
COMMENT ON COLUMN adresse.point_adresse.c_dist_voie IS 'Calcul la distance entre le point adresse et sa voie de rattachement';

-- point_adresse.geom_pt_proj

COMMENT ON COLUMN adresse.point_adresse.geom_pt_proj IS 'geometrie du point adressse projeté sur sa voie de ratachement';


-- point_adresse.geom_segment_prolong

COMMENT ON COLUMN adresse.point_adresse.geom_segment_prolong IS 'géometrie du segment tracé entre le point adresse et le point projeté sur sa voie de ratachement. Prolongé de son 50/49e';

-- point_adresse.cote_voie

COMMENT ON COLUMN adresse.point_adresse.cote_voie IS 'indique la position du point par rapport à sa voie de ratachement : droite, gauche, indéfinie. Sinon problème (voie mal tracée, point non rattaché à une voie, ...)';


-- point_adresse.c_erreur_cote_parite
COMMENT ON COLUMN adresse.point_adresse.c_erreur_cote_parite IS 'identifie les points adresse pair ou impair du mauvais coté de la voie à laquelle il est rattaché : true (erreur coté), false (pas derreur) ou indefini. Sinon problème (voie mal tracée, point non rattaché à une voie, ...)';


-- voie.c_erreur_trace
COMMENT ON COLUMN adresse.voie.c_erreur_trace IS 'erreur de tracé de voies recourbées sur ou vers elles mêmes';
-- voie.c_repet_nom_voie
COMMENT ON COLUMN adresse.voie.c_repet_nom_voie IS 'voie portant le même nom qu1 autre voie de la même commune';

-- voie.c_long_nom
COMMENT ON COLUMN adresse.voie.c_long_nom IS 'voie portant un nom de plus de 24 charactères';

-- voie.c_saisie_double
COMMENT ON COLUMN adresse.voie.c_saisie_double IS 'Voies à moins de 50 mètres de distance portant le même nom';

-- parcelle. nb_pt_adresse
COMMENT ON COLUMN adresse.parcelle.nb_pt_adresse IS 'nombre de points adresse par parcelle';

-- parcelle.date_pt_modif
COMMENT ON COLUMN adresse.parcelle.date_pt_modif IS 'derniere modification des points adresse par parcelle';

-- commune.pt_hors_parcelle
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle IS 'nombre de point adresse hors parcelle/commune';

-- commune.pt_hors_parcelle_valid
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle_valid IS 'nombre de point adresse hors parcelle validés/commune';
-- commune.nb_pt_valide
COMMENT ON COLUMN adresse.commune.nb_pt_valide IS 'nombre de point adresse marqués comme validés par les users/commune';

-- commune.nb_pt_erreur 
COMMENT ON COLUMN adresse.commune.nb_pt_erreur IS 'nombre de point adresse en erreur/commune';

-- commune.nb_a_verif
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle_valid IS 'nombre de point adresse à vérifier sur le terrain/commune';

-- commune.nb_pt_no_valid
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle_valid IS 'nombre de point adresse non validés/commune';

-- commune.pt_total
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle_valid IS 'nombre de point adresse total/commune';

-- commune.pct_pt_reel_valid 
COMMENT ON COLUMN adresse.commune.pt_hors_parcelle_valid IS 'nombre de point  adresse réellement validés/commune';


-- commune.voie_non_valid
COMMENT ON COLUMN adresse.commune.voie_non_valid IS 'nombre de voies non validées/commune';

-- commune.voie_valid
COMMENT ON COLUMN adresse.commune.voie_valid IS 'nombre de voies  validées/commune';

-- commune.voie_total
COMMENT ON COLUMN adresse.commune.voie_total IS 'nombre de voies total/commune';

-- commune.pct_voie_valid
COMMENT ON COLUMN adresse.commune.pct_voie_valid IS 'pourcentage de voie validé/commune';

--
-- FIN COMMENT
--

COMMIT;
BEGIN;

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch ;
--
-- Début FONCTIONS
--


--------------------------------------------------------------------------------------
--- C1 T2: Identifier les	points adresse pair ou impair du mauvais coté de la voie
------------------------------------------------------------------------------------------

--- C1 T1: Identifier les points adresse plus près d’une autre voie que celle à laquelle il appartient et retourne la distance entre le point et sa voie de ratachement

CREATE OR REPLACE FUNCTION adresse.f_point_voie_distant()
  RETURNS "trigger" AS
$fct$
DECLARE 
voie_rat  integer ;
dist_ratach      integer;

BEGIN 

/* Cette requête retourne l'id_voie le plus proche du nouveau point adresse crée
*/
select g.voie into voie_rat from (select v.id_voie as voie , ST_Distance(NEW.geom, v.geom) as dist
from adresse.voie v
where ST_DWithin(v.geom, NEW.geom, 10000) 
ORDER BY dist LIMIT 1) g ;

/* Cette requête calcul la distance entre le point et sa voie de ratachement
*/
select ST_Distance(NEW.geom, v.geom) into dist_ratach
from adresse.voie v
where v.id_voie = NEW.id_voie;

/* si erreur True, sinon false
*/
    IF voie_rat = NEW.id_voie THEN
        NEW.c_erreur_dist_voie = FALSE; -- Faux, si le point adresse est proche de sa voie de ratachement
    ELSE
        NEW.c_erreur_dist_voie = TRUE; -- Sinon vrai
    END IF;

        NEW.c_dist_voie = dist_ratach;

    RETURN NEW; 
	END;


$fct$ LANGUAGE plpgsql;

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




--- C1 T2: FONCTION qui dessine un sgement du point adresse à un point projeté au 50/49e de la distance entre le point adresse et son point projeté 

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






--- C1 T3:--- Fonction qui trouve les points à droites et à gauche

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




--- C1 T4: Fonction qui identifie les	points adresse pair ou impair du mauvais coté de la voie
     

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


--- C2 T1:--  EXTRAIRE LES SEGMENTS DE POLYLIGNE
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






--- C2 T2:--  CREER CENTROID  1/3 DES SEGMENTS, ROTATIONS 

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




--- C2 T3:--  Identifier les voies avec erreur de tracé: qui croisent plusieurs fois un segment retourné

CREATE OR REPLACE FUNCTION adresse.f_voie_erreur_trace()
  RETURNS "trigger" AS
$fct$
DECLARE 
geom_rotate geometry ;
geom_exist geometry;
BEGIN 
/* Cette requête retourne les segments au niveau de leur centroides raccourcies de 2/3
*/
Select adresse.line_rotation(g.geom_segment) into geom_rotate from
/* Cette requête extrait des segments à partir de polylignes _ pas possible d'utiliser la fonction dans ce cas
*/
(SELECT * from (SELECT ROW_NUMBER() OVER() as id, dumps.id_voie, ST_MakeLine(lag((pt).geom, 1, NULL) OVER (PARTITION BY dumps.id_voie ORDER BY dumps.id_voie, (pt).path), (pt).geom) AS geom_segment
  FROM (SELECT NEW.id_voie as id_voie, NEW.geom as geom, ST_DumpPoints(NEW.geom) AS pt ) dumps)s WHERE s.geom_segment IS NOT NULL)g;


/* Cette requête identifie si la voie croise plusieurs fois les segments retournés
*/
Select geom_rotate into geom_exist
WHERE ST_LineCrossingDirection(New.geom, geom_rotate) = '-2' or  ST_LineCrossingDirection(New.geom, geom_rotate) = '2'
or ST_LineCrossingDirection(New.geom, geom_rotate) = '3' or ST_LineCrossingDirection(New.geom, geom_rotate) = '-3';

IF geom_exist is not null THEN
NEW.c_erreur_trace = TRUE ; -- retourne vrai si il y a erreur de tracé
ELSE
NEW.c_erreur_trace = FALSE; -- si pas d'erreur retourne faux

END IF;
RETURN    NEW ; 
END;$fct$
  LANGUAGE plpgsql;


------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Contrôle 3 : problèmes répétitions voies
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--C3.T1 Identifier les voies portant le même nom qu'une autre voie de la même commune


CREATE OR REPLACE FUNCTION adresse.f_commune_repet_nom_voie()
  RETURNS "trigger" AS
$fct$
DECLARE 
repet integer ;
BEGIN 

/* Cette requête retourne 
*/
SELECT count(g.nom) into repet ----------- Séléctionne le nombre de répétition des noms de voies depuis..... 
          FROM (select c.id_com, c.geom, v.nom--------------------------------------------------------------------------------------------------------------------
from adresse.voie v
inner join adresse.commune c on st_intersects(c.geom, v.geom)---------------------- la séléction de l'ensemble des id_com, geom communes et noms de voie regroupés
group by c.id_com, c.geom, v.nom) g----------------------------------------------------------------------------------------------------------------------------------
         WHERE levenshtein(g.nom, NEW.nom) <= 1 ---- fonction comparant les noms proches à 1 caractère près
           AND g.id_com IS NOT DISTINCT FROM ------------------------------------------------------ Contrainte pour n'avoir que les répétion dont l'id commune est lié à l'id commune du nouveau nom de voie saisi
		   (select g.id_com where st_intersects(g.geom,NEW.geom) and g.nom = NEW.nom) ;


    IF repet = 0 THEN
        NEW.c_repet_nom_voie = FALSE; -- retrourne faux si pas de repetition de nom
    ELSE
        NEW.c_repet_nom_voie = TRUE; -- retrourne vrai si repetition de nom
    END IF;
    RETURN NEW; 
END;
$fct$ LANGUAGE plpgsql;




-- C3.T2: Identifier les voies avec un nom trop long


CREATE OR REPLACE FUNCTION adresse.f_controle_longueur_nom() 
RETURNS "trigger" AS
$fct$
BEGIN

/* Cette requête retourne 
*/
       		IF char_length(NEW.nom) < 24
        THEN NEW.c_long_nom = FALSE ; -- retrourne faux si le nom fait moins de 24 caractères
        ELSE
             NEW.c_long_nom = TRUE ; -- retrourne vrai si le nom est trop long
        END IF;
        RETURN NEW; 
        END;
$fct$ LANGUAGE plpgsql;




-- C3.T3: IDENTIFIER LES VOIES SAISIES EN 2 FOIS :



CREATE OR REPLACE FUNCTION adresse.f_voie_double_saisie()
  RETURNS "trigger" AS
$fct$
DECLARE
repet integer;
BEGIN 
/* Cette requête retourne  les voies à moins de 500 mètre de la nouvelle voie crée et dont le nom est proche de celui ci
*/
select v.id_voie into repet
from adresse.voie v
where st_distance(NEW.geom, v.geom) < '500'
AND levenshtein(CONCAT(NEW.typologie, ' ', NEW.nom), CONCAT(v.typologie, ' ', v.nom)) <= 1;

IF repet is not null 
THEN NEW.c_saisie_double = TRUE; -- retrourne vrai si la voie est saisie deux fois
ELSE
NEW.c_saisie_double = FALSE; -- retrourne faux si la voie n'est pas saisie deux fois


END IF;
    RETURN NEW; 

 END;
$fct$ LANGUAGE plpgsql;




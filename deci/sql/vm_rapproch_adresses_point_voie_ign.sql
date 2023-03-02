
--------------------------------------------------------------

------------------------------------------
----- VM rapprochement adresse - SDIS
----------------------------------------


create materialized view adresse.vm_sdis_pts_adresse_bdtopo as
with bdtopo_idvoie as (
      select * from  adresse.id_voie_bdtopo_sdis() --- Fonction donnant la séléction des id_tronçons bdtopo et des id_voies adresse
     ),
     distance_troncon as ( --- Projection des points adresses sur les tronçon ayant le même id_voie et de la distance entre le point et la voie
      select p.id_point, troncon.id_troncon, troncon.id_voie, troncon.geom, p.numero, p.suffixe, p.geom as geom_pt_adresse,
      ST_LineInterpolatePoint(ST_LineMerge(troncon.geom), ST_LineLocatePoint(ST_AsEWKT(ST_LineMerge(troncon.geom)), ST_AsEWKT(p.geom))) as geom_pt_proj, --- Projection des points adresses sur les tronçon ayant le même id_voie 
      st_distance(troncon.geom, p.geom) as dist --- distance entre le point et la voie
      FROM bdtopo_idvoie  troncon
      inner join adresse.point_adresse p on troncon.id_voie = p.id_voie
      inner join adresse.v_communes_publiees l  on st_intersects(p.geom,l.geom)
    ),
    point_proj as( --- Séléction unique des id_points avec id tronçon associés dont la distance est la plus courte (une voie pouvant comprendre plusieurs tronçons bdtopo on associe les points adresses aux tronçon le plus proche)
      select distinct on (distance_troncon.id_point) distance_troncon.id_point, distance_troncon.id_troncon, distance_troncon.id_voie, -- selection distinct d'id_point adresse
      distance_troncon.numero, distance_troncon.suffixe, distance_troncon.geom, geom_pt_adresse, geom_pt_proj
      from distance_troncon
      order by id_point, dist ASC --- ordonner de la plus petite distance à la plus grande pour que distinct sélectionne la première entité avec la plus courte distance
    ),
    line_cross as ( --- tracer une ligne prolongées entre le point adresse et son point projeté sur le tronçon
      select point_proj.id_point, point_proj.id_troncon, point_proj.id_voie, point_proj.numero, point_proj.suffixe, point_proj.geom, geom_pt_adresse, geom_pt_proj, 
      ST_MakeLine(geom_pt_adresse, ST_TRANSLATE(geom_pt_adresse, sin(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
      + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))), cos(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
      + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))))) as geom_segment
      from point_proj
    ), 
    point_cote as (--- Definir le coté de du point adresse par rapport au tronçon grâce à son sens de croisement du segment précédemment crée
      select line_cross.id_point, line_cross.id_troncon, line_cross.id_voie, line_cross.numero, line_cross.suffixe,  
      case WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom)) = -1 then 'gauche'
           WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 1 then 'droite'
           WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 0 then 'indefini' --- Si croise ni à gauche ni à droite 
           ELSE 'probleme' end as cote_voie,  --- croise plusieurs fois, donc problème de tracé du tronçon ou cas particulier (rare)
      geom_segment, geom_pt_adresse, geom_pt_proj
      from line_cross
    ),
    commune_publ as (  ------ selection des communes bd_topo correspondant aux communes publiées adresse
      select bc.geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc
			where a.insee_code = bc.insee_com
    ),
    troncon_com_pub as ( --- selection des tronçon sur les communes bdtopo sléctionnées plus haut
      select b.* from ign.bdtopo_troncon_de_route b, commune_publ
      where st_intersects(b.geom,commune_publ.geom)
    ), 
    point_pair_first as ( ------ selection du point adresse par tronçon à droite le plus proche point de départ du tronçon
      select distinct on (a.id_troncon) a.id_point, a.id_troncon, a.id_voie, a.numero, a.suffixe, a.cote_voie, a.geom_pt_adresse as geom_pt, 
      st_distance(ST_StartPoint(st_linemerge(tc.geom)), a.geom_pt_proj) as dist
      from point_cote a, troncon_com_pub tc
      where cote_voie = 'droite' and a.id_troncon = tc.id
      order by a.id_troncon, dist ASC --- ordonner de la plus petite distance à la plus grande pour que distinct sélectionne la première entité avec la plus courte distance
    ),
    point_pair_der as ( ------ selection du point adresse par tronçon à droite et le plus proche du point de fin du tronçon
      select distinct on (b.id_troncon) b.id_point, b.id_troncon, b.id_voie, b.numero, b.suffixe, b.cote_voie, b.geom_pt_adresse as geom_pt, 
      st_distance(ST_EndPoint(st_linemerge(tc.geom)), b.geom_pt_proj) as dist 
      from point_cote b, troncon_com_pub tc
      where cote_voie = 'droite' and b.id_troncon = tc.id
      order by b.id_troncon, dist ASC
    ),
    point_impair_first as (------ selection du points adresse par tronçon à gauche et le plus proche du  point de départ du tronçon
      select distinct on (c.id_troncon) c.id_point, c.id_troncon, c.id_voie, c.numero, c.suffixe, c.cote_voie, c.geom_pt_adresse as geom_pt,
      st_distance(ST_StartPoint(st_linemerge(tc.geom)), c.geom_pt_proj) as dist
      from point_cote c, troncon_com_pub tc
      where cote_voie = 'gauche' and c.id_troncon = tc.id
      order by c.id_troncon, dist ASC
    ),
    point_impair_der as (------ selection du point adresse par tronçon à gauche et le plus proche du  point de fin du tronçon
      select distinct on (d.id_troncon) d.id_point, d.id_troncon, d.id_voie, d.numero, d.suffixe, d.cote_voie, d.geom_pt_adresse as geom_pt, 
      st_distance(ST_EndPoint(st_linemerge(tc.geom)), d.geom_pt_proj) as dist
      from point_cote d, troncon_com_pub tc
      where cote_voie = 'gauche' and d.id_troncon = tc.id
      order by d.id_troncon, dist ASC)

  Select z.id_troncon, z.id_voie, v.nom_complet, ------ Jointure des précdentes sélection avec les tronçons rapprocher (z), la geom tronçon ign(e) et le nom complet des voies(v)
  CONCAT(point_pair_first.numero,' ', point_pair_first.suffixe)  as prem_num_droite,
  CONCAT(point_pair_der.numero, ' ', point_pair_der.suffixe) as der_num_droite,
  CONCAT(point_impair_first.numero, ' ', point_impair_first.suffixe) as prem_num_gauche,
  CONCAT(point_impair_der.numero, ' ', point_impair_der.suffixe) as der_num_gauche,  
  e.geom as geom_tronçon
  from point_cote z 
  left join point_pair_first on z.id_troncon = point_pair_first.id_troncon
  left join point_pair_der on z.id_troncon = point_pair_der.id_troncon
  left join point_impair_first on z.id_troncon = point_impair_first.id_troncon
  left join point_impair_der on z.id_troncon = point_impair_der.id_troncon
  left join troncon_com_pub e on z.id_troncon = e.id
  left join adresse.voie v on v.id_voie = z.id_voie
  group by z.id_troncon, z.id_voie, point_pair_first.numero, point_pair_der.numero, point_impair_first.numero, point_impair_der.numero,
point_pair_first.suffixe, point_pair_der.suffixe, point_impair_first.suffixe, point_impair_der.suffixe, e.geom, v.nom_complet  ;


--------------------------------------------------------------------------------------------------------------------------------------------------

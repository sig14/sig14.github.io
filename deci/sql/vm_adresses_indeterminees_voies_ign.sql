
------------------------------------------------
------- VM liste points_adresse_indetermine_sdis
------------------------------------------------

create materialized view adresse.vm_sdis_pts_adresse_indetermine as
  with bdtopo_idvoie as (--- Fonction donnant la séléction des id_tronçons bdtopo et des id_voies adresse
        select * from  adresse.id_voie_bdtopo_sdis()
      ),

      distance_troncon as (--- Projection des points adresses sur les tronçon ayant le même id_voie et de la distance entre le point et la voie
        select p.id_point, troncon.id_troncon, troncon.id_voie, troncon.geom, p.numero, p.suffixe, p.geom as geom_pt_adresse,
        ST_LineInterpolatePoint(ST_LineMerge(troncon.geom), 
        ST_LineLocatePoint(ST_AsEWKT(ST_LineMerge(troncon.geom)), ST_AsEWKT(p.geom))) as geom_pt_proj,
        st_distance(troncon.geom, p.geom) as dist
        FROM bdtopo_idvoie  troncon
        inner join adresse.point_adresse p on troncon.id_voie = p.id_voie
        inner join adresse.v_communes_publiees l  on st_intersects(p.geom,l.geom)
      ),
      point_proj as (--- Séléction des unique des id_points avec id tronçon associés dont la distance est la plus courte (une voie pouvant comprendre plusieurs tronçons bdtopo on associe les points adresses aux tronçon le plus proche)
        select distinct on (distance_troncon.id_point) distance_troncon.id_point, distance_troncon.id_troncon, 
        distance_troncon.id_voie, distance_troncon.numero, distance_troncon.suffixe, distance_troncon.geom, geom_pt_adresse, geom_pt_proj
        from distance_troncon
        order by id_point, dist ASC),
      line_cross as ( --- tracer une ligne prolongées entre le point adresse et son point projeté sur le tronçon
        select point_proj.id_point, point_proj.id_troncon, point_proj.id_voie, point_proj.numero, point_proj.suffixe, point_proj.geom, geom_pt_adresse, geom_pt_proj,
        ST_MakeLine(geom_pt_adresse,  
        ST_TRANSLATE(geom_pt_adresse, sin(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
        + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))), cos(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
        + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))))) as geom_segment
        from point_proj ), 
      point_cote as (--- Definir le coté de du point adresse par rapport au tronçon grâce à son sens de croisement du segment précédemment crée
        select line_cross.id_point, line_cross.id_troncon, line_cross.id_voie, line_cross.numero, line_cross.suffixe,  
        case WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom)) = -1 then 'gauche'
             WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 1 then 'droite'
             WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 0 then 'indefini'
             ELSE 'probleme' end as cote_voie, 
        geom_segment, geom_pt_adresse, geom_pt_proj
        from line_cross)

  select * from point_cote  where cote_voie = 'indefini' or cote_voie ='probleme' ; --- Sélection des points adresses indéfinis ou à problème par rapport au tronçon de rattachement




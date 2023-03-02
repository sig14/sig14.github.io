------------------------------------------------------------------------------
----- Fonction rapprochant les tronçon de la bdtopo avec les voies adresses
------------------------------------------------------------------------------


CREATE OR REPLACE FUNCTION adresse.id_voie_bdtopo_sdis()
  RETURNS table (id_troncon varchar, id_voie integer, geom geometry)
AS $BODY$
DECLARE 
      req varchar;
BEGIN
---Création d'une table temporaire de noeuds bdtopo

        CREATE UNLOGGED TABLE IF NOT EXISTS node_bd_topo as -- créer une table temporaire que l'on va pouvoir indéxer pour accelerer la requête (ici une unlogged table pour pouvoir réutiliser les données dans une VM)
        with commune_pub as (------ selection des communes bd_topo correspondant aux communes publiées adresse
          select st_buffer(bc.geom, 100) as geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc -- buffer de 100 mètres des communes ign du au décalage ign osm
					where a.insee_code = bc.insee_com
          ), 
        troncon_com_pub as (--- selection des tronçon sur les communes bdtopo sléctionnées plus haut 
          select b.* from ign.bdtopo_troncon_de_route b, commune_pub
          where st_intersects(b.geom,commune_pub.geom)
          ) 
          select ROW_NUMBER() OVER() as id_pt, c.id,  
          (ST_Dump(ST_AsMultiPoint(st_segmentize(ST_Force2D(c.geom) ,10))::geometry(MULTIPOINT,2154))).geom as geom --- création de noeuds multipoints bdtopo à partir de la segmentisation des tronçons(3D)
          from troncon_com_pub  c;

        CREATE INDEX node_bd_topo_geom --- création d'un indexe sur la geom de la table
        ON node_bd_topo USING gist (geom)
        TABLESPACE pg_default;

---Rapprochement des id_voies et tronçon grâce aux noeuds précédemment crées
        req:= $sql$  with commune_pub as ( ------ selection des communes bd_topo correspondant aux communes publiées adresse
                            select st_buffer(bc.geom, 100) as geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc -- buffer de 100 mètres des communes ign du au décalage ign osm
					                  where a.insee_code = bc.insee_com
                            ),
                          voie as ( ------ selection des voies adresses bufferisées sur les communes publiées adresse
                            select v.id_voie, ST_Buffer(ST_Buffer(v.geom, 10, 'endcap=flat join=round'), -5, 'endcap=flat join=round') as geom -- on aura besoin du buffer pour collecter les noeuds (on créé un buffer de 10 mètres et on raccourci les bords de 5 mètres)
                            from adresse.voie v, commune_pub a
                            where st_intersects(a.geom,v.geom)
                            ),
                          pt_count_troncon as (------ Compte le nombre de noeuds par tronçon
                            select id, count(id_pt) as ct 
                            from node_bd_topo 
                            group by id),
                          f as (------ rapprochement des id_voies et des noeuds à l'intérieur du buffer des voies précédemment créé
                            select b.id_pt, b.id, voie.id_voie 
                            from node_bd_topo  b
                            inner join voie
                            ON ST_Within(b.geom, voie.geom)
                            ),
                          l as ( ------ Compte le nombre de noeud pour chque id_voie
                            select f.id, f.id_voie, count(f.id_voie) as ct 
                            from f
                            group by f.id, f.id_voie
                            ),
                          troncon_node as ( ------ Séléctionne les id_tronçon dont la majorité des noeuds intersecte le buffer des voies 
                            select distinct on (l.id) l.id, l.id_voie, l.ct 
                            from l , pt_count_troncon
                            where pt_count_troncon.id = l.id and (pt_count_troncon.ct/l.ct)<= 2 -- division du total des noeuds tronçon/le nombre de noeuds pour un même id_voie, si moins de 2, on conserve l'id-tronçon et l'id_voie associé
                            order by l.id, l.ct DESC)

                    select troncon_node.id, troncon_node.id_voie, k.geom ------ Rapprochement des géométrie de la bd_topo grâce à l'id tronçon des noeuds précédemment sélectionnés
                    from  troncon_node, ign.bdtopo_troncon_de_route k 
                    where k.id = troncon_node.id ;$sql$;


Return query execute req;


DROP TABLE node_bd_topo;

END
$BODY$
LANGUAGE plpgsql;



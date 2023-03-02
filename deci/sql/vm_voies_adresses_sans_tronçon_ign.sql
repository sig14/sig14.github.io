-----------------------------------------------------------------------------------------------------------

------------------------------------
----- VM voie sans tronçon bd_topo
------------------------------------



create materialized view adresse.vm_troncon_no_voie_bd_topo as
  with bdtopo_idvoie as (--- Fonction donnant la séléction des id_tronçons bdtopo et des id_voies adresse
        select * from  adresse.id_voie_bdtopo_sdis()
      ),
       commune_pub as (------ selection des communes bd_topo correspondant aux communes publiées adresse
         select st_buffer(bc.geom, 100) as geom 
         from adresse.v_communes_publiees a, ign.bdtopo_commune bc
				 where a.insee_code = bc.insee_com
      ),
       troncon_com_pub as (--- selection des tronçon sur les communes bdtopo sléctionnées plus haut
         select b.* from ign.bdtopo_troncon_de_route b, commune_pub
         where st_intersects(b.geom,commune_pub.geom)
      )
    select p.id, p.geom --- selection des tronçon qui n'ont pas d'id_voie associé
    from troncon_com_pub p
    left join bdtopo_idvoie a
    on p.id = a.id_troncon
    group by p.id, p.geom, a.id_voie
    having a.id_voie is null

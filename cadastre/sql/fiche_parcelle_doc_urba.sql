
-- Transformer les géometries invalides du GPU en géométries valides

update ref_urbanisme.gpu_api_zonages set geom = ST_MakeValid(geom);


update ref_urbanisme.gpu_api_secteur_cc set geom = ST_MakeValid(geom);

update ref_urbanisme.gpu_api_prescription_surf set geom = ST_MakeValid(geom);

update ref_urbanisme.gpu_api_prescription_lin set geom = ST_MakeValid(geom);


update ref_urbanisme.gpu_api_info_prescription_surf set geom = ST_MakeValid(geom);
update ref_urbanisme.gpu_api_info_prescription_lin set geom = ST_MakeValid(geom);

---- Ajout des champs HTML fiches docs urba à la table parcelle_info 
ALTER TABLE cadastre.parcelle_info
ADD tab_doc_urba varchar;

ALTER TABLE cadastre.parcelle_info
ADD deroulant_zonage varchar;

ALTER TABLE cadastre.parcelle_info
ADD deroulant_secteur varchar;

ALTER TABLE cadastre.parcelle_info
ADD deroulant_prescription varchar;

ALTER TABLE cadastre.parcelle_info
ADD deroulant_info varchar;
--


--- Fonction alimentant les champs HTML fiches docs urba de la table parcelle_info


CREATE OR REPLACE FUNCTION ref_urbanisme.fiches_parcelles_lizmap()
RETURNS 
text
  AS $BODY$
DECLARE 

BEGIN


RAISE NOTICE 'creation tables temporaire 1 sur zonage';

-- Création d'une table temporaire des zonages avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_zonage_ref_urbanisme as 
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_zonages z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom;

 -- Indexation de la table temporaire    
      CREATE INDEX index_temp_parcelle_zonage_ref_urbanisme ON temp_parcelle_zonage_ref_urbanisme USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_zonage_ref_urbanisme ON temp_parcelle_zonage_ref_urbanisme USING btree (id);


      CREATE INDEX index_geom_temp_parcelle_zonage_ref_urbanisme ON temp_parcelle_zonage_ref_urbanisme USING gist (geom);


RAISE NOTICE 'Fin de creation tables temporaire 1 sur zonage';
RAISE NOTICE 'creation tables temporaire 2 sur secteur cc';


-- Création d'une table temporaire des secteurs caretes communales avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_secteurs_ref_urbanisme as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_secteur_cc z  
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

    
      CREATE INDEX index_temp_parcelle_secteurs_ref_urbanisme ON temp_parcelle_secteurs_ref_urbanisme USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_secteurs_ref_urbanisme ON temp_parcelle_secteurs_ref_urbanisme USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_secteurs_ref_urbanisme ON temp_parcelle_secteurs_ref_urbanisme USING gist (geom);

 -- Indexation de la table temporaire    

RAISE NOTICE 'Fin de creation tables temporaire 2 sur secteur cc';
RAISE NOTICE 'creation tables temporaire 3 sur prescriptions surface';

-- Création d'une table temporaire des prescriptions surfaciques avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_presc_surf as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_prescription_surf  z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

  -- Indexation de la table temporaire    
   
      CREATE INDEX index_temp_parcelle_presc_surf  ON temp_parcelle_presc_surf  USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_presc_surf  ON temp_parcelle_presc_surf  USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_presc_surf  ON temp_parcelle_presc_surf  USING gist (geom);


RAISE NOTICE 'Fin de creation tables temporaire 3 sur prescriptions surface';
RAISE NOTICE 'creation tables temporaire 4 sur prescriptions linéaires';


-- Création d'une table temporaire des prescriptions linéaires avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_presc_lin as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_prescription_lin  z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

 -- Indexation de la table temporaire    

    
      CREATE INDEX index_temp_parcelle_presc_lin  ON temp_parcelle_presc_lin USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_presc_lin  ON temp_parcelle_presc_lin  USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_presc_lin ON temp_parcelle_presc_lin  USING gist (geom);

RAISE NOTICE 'Fin de creation tables temporaire 4 sur prescriptions linéaires';
RAISE NOTICE 'creation tables temporaire 5 sur prescriptions ponctuels';


-- Création d'une table temporaire des prescriptions ponstcuels avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_presc_pct as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_prescription_pct  z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

   -- Indexation de la table temporaire    
  
      CREATE INDEX index_temp_parcelle_presc_pct  ON temp_parcelle_presc_pct USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_presc_pct  ON temp_parcelle_presc_pct  USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_presc_pct ON temp_parcelle_presc_pct  USING gist (geom);



RAISE NOTICE 'Fin de creation tables temporaire 5 sur prescriptions ponctuels';
RAISE NOTICE 'creation tables temporaire 6 sur infos surfaces ';

-- Création d'une table temporaire des info prescriptions surfaciques avec identifiant parcelle associés

CREATE UNLOGGED TABLE temp_parcelle_info_surf as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_info_prescription_surf z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

 -- Indexation de la table temporaire    
    
      CREATE INDEX index_temp_parcelle_info_surf   ON temp_parcelle_info_surf  USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_info_surf  ON temp_parcelle_info_surf   USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_info_surf  ON temp_parcelle_info_surf   USING gist (geom);


RAISE NOTICE 'Fin de creation tables temporaire 6 sur infos surface';
RAISE NOTICE 'creation tables temporaire 7 sur infos linéairess ';

-- Création d'une table temporaire des prescriptions linéaires avec identifiant parcelle associés


CREATE UNLOGGED TABLE temp_parcelle_info_lin as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_info_prescription_lin z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

 -- Indexation de la table temporaire    
    
      CREATE INDEX index_temp_parcelle_info_lin  ON temp_parcelle_info_lin  USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_info_lin  ON temp_parcelle_info_lin   USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_info_lin  ON temp_parcelle_info_lin   USING gist (geom);

RAISE NOTICE 'Fin de creation tables temporaire 7 sur infos lineaires';
RAISE NOTICE 'creation tables temporaire 8 sur infos pct  ';


-- Création d'une table temporaire des prescriptions ponctuels avec identifiant parcelles associés


CREATE UNLOGGED TABLE temp_parcelle_info_pct as
select  p.geo_parcelle, z.*
    FROM cadastre.parcelle_info p
    inner join ref_urbanisme.gpu_api_info_prescription_pct z 
    on  st_intersects(p.geom, z.geom) and p.geom&&z.geom ;

 -- Indexation de la table temporaire    
    
      CREATE INDEX index_temp_parcelle_info_pct  ON temp_parcelle_info_pct  USING btree (geo_parcelle);
      CREATE INDEX index2_temp_parcelle_info_pct  ON temp_parcelle_info_pct   USING btree (gid);


      CREATE INDEX index_geom_temp_parcelle_info_pct  ON temp_parcelle_info_pct   USING gist (geom);


RAISE NOTICE 'démarrage création fiche à % ', now() ;

--------------------------------------------------------------------------------------------------------

CREATE UNLOGGED TABLE temp_fiche as 
with parcelle_ref_urbanisme as (
    --- selection des infos parcelles et zonages + impact zonage sur parcelle (intersection) + surface zonage total en metres carré
    (select p.geo_parcelle,z.partition, z.nomfic,z.datappro::date, z.destdomi, z.datvalid::date, concat(round(st_area(z.geom)::numeric, 2)::text, ' m²') as surface, 'Zonages' as type_doc, z.libelle as nom, st_area(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
            
            'surf' as impact_txt,
            z.libelong as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_zonage_ref_urbanisme  z 
    on  z.geo_parcelle = p.geo_parcelle
    )
    UNION
    --- selection des infos parcelles et secteurs cartes communales + impact secteur sur parcelle (intersection) + surface secteure total en metres carré
     (select p.geo_parcelle,z.partition, z.nomfic,z.datappro::date, z.destdomi, z.datvalid::date, concat(round(st_area(z.geom)::numeric, 2)::text, ' m²')  as surface, 'Secteurs' as type_doc, z.libelle as nom, st_area(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
                        'surf' as impact_txt,
            z.libelong as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_secteurs_ref_urbanisme z 
    on   z.geo_parcelle = p.geo_parcelle

    )
     UNION
     --- selection des infos parcelles et prescriptions surfaces + impact prescriptions sur parcelle (intersection) + surface zprescription total en metres carré
     (select p.geo_parcelle,z.partition,z.nomfic,z.datappro::date, null as destdomi, z.datvalid::date, concat(round(st_area(z.geom)::numeric, 2)::text, ' m²')  as surface,  'Prescriptions' as type_doc, z.libelle as nom, st_area(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
                        'surf' as impact_txt,
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_presc_surf z 
    on   z.geo_parcelle = p.geo_parcelle

    )
UNION
--- selection des infos parcelles et prescriptions linéaires + impact prescriptions sur parcelle (intersection) + longueur prescription total en metres 
     (select p.geo_parcelle,z.partition,z.nomfic,z.datappro::date, null as destdomi, z.datvalid::date, concat(round(st_length(z.geom)::numeric, 2)::text, ' m')  as surface,  'Prescriptions' as type_doc, z.libelle as nom, st_length(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
           'lin' as impact_txt ,
 
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_presc_lin  z 
    on   z.geo_parcelle = p.geo_parcelle

    )
UNION
--- selection des infos parcelles et prescriptions ponctuel + impact null + surface  null
     (select p.geo_parcelle,z.partition,z.nomfic,z.datappro::date, null as destdomi, z.datvalid::date, null  as surface,  'Prescriptions' as type_doc, z.libelle as nom, null as impact,
            'ponctuel' as impact_txt ,
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_presc_pct z 
    on   z.geo_parcelle = p.geo_parcelle

    )

 UNION
 --- selection des infos parcelles et info prescriptions surfaces + impact prescriptions sur parcelle (intersection) + surface zonage total en metres carré
     (select p.geo_parcelle,z.partition,z.nomfic,z.datappro::date, null as destdomi, z.datvalid::date, concat(round(st_area(z.geom)::numeric, 2)::text, 'm²') as surface,  'Informations' as type_doc, z.libelle as nom, st_area(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
                       'surf' as impact_txt ,
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_info_surf  z 
    on  z.geo_parcelle = p.geo_parcelle

    )
UNION
--- selection des infos parcelles et info prescriptions linéaires + impact prescriptions sur parcelle (intersection) + longueur prescription total en metres 
     (select p.geo_parcelle,z.partition,z.nomfic, z.datappro::date, null as destdomi, z.datvalid::date, concat(round(st_length(z.geom)::numeric, 2)::text, 'm')  as surface, 'Informations' as type_doc, z.libelle as nom, st_length(ST_CollectionExtract(st_intersection(p.geom, z.geom),3)) as impact,
            'lin' as impact_txt ,
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_info_lin z 
    on  z.geo_parcelle = p.geo_parcelle

    )
UNION
--- selection des infos parcelles et infos prescriptions ponctuel + impact null + surface  null
     (select p.geo_parcelle,z.partition,z.nomfic,z.datappro::date, null as destdomi, z.datvalid::date, null  as surface,  'Informations' as type_doc, z.libelle as nom, null as impact,
            'ponctuel' as impact_txt ,
            z.txt as commentaire, st_area(p.geom) as area_parcelle 
    FROM cadastre.parcelle_info p
    join temp_parcelle_info_pct  z 
    on  z.geo_parcelle = p.geo_parcelle

    )

    
    ),
--- Séléction des docs urba par parcelle d'ont l'impact est superieur à 1 ou ponctuel + creation de l'impact en txt + mise en place du lien vers réglement en html
pre_fiche as (select geo_parcelle as parcelle, type_doc, destdomi, nom, datappro, datvalid, surface, impact,
case when impact_txt = 'surf' then 
            concat(round(impact::numeric, 2)::text, ' m²')
            when impact_txt = 'lin' then
            concat(impact::text, 'm')
            else impact_txt end -- creation de l'impact en text avec suffixe m² si surf, m si lineaire, sinon pas de suffixe
             as impact_text ,
case when parcelle_ref_urbanisme.nomfic is not null  then concat('<a href="', 'https://wxs-gpu.mongeoportail.ign.fr/externe/documents/',parcelle_ref_urbanisme.partition,'/',
b.id,'/', parcelle_ref_urbanisme.nomfic, '" target="_blank">Règlement</a>') else 'no data' end as reglement, --- concatenation de blocs html avec  partition, clé dossier pdf emprise, et nom de fichier (accès pdf GPU)

commentaire, round(impact*100/area_parcelle) as taux_inclusion -- création taux d'inclusion : pourcentage de l'impact sur la surface de la parcelle
from parcelle_ref_urbanisme
left join ref_urbanisme.gpu_api_emprise b on parcelle_ref_urbanisme.partition = b.partition -- jointure  de l'emprise pour selection de la clé dossier pdf
where  (parcelle_ref_urbanisme.impact >= 1 or parcelle_ref_urbanisme.impact_txt ='ponctuel')
order by geo_parcelle, type_doc DESC, nom ASC),

deroulant_zonages as (select a.parcelle, -- création d'un déroulant "accordion html" zonage pour détail du zonage par parcelle
        string_agg( -- aggregation des données zonages par parcelle : concatenation de blocs html et des champs d'infromations. Concatène seulement les valeurs non nulles.
    ('<br><details class="accordion_urba"><summary> Zone '||coalesce(a.nom, null, '')||'</summary><b>DestDomi</b>      '||coalesce(a.destdomi,null, '')||'<br><b>Description</b>     '||coalesce(a.commentaire,null, '')||' <br><b>Approbation</b>     '||coalesce(a.datappro::text,null, '')||' <br><b>Validité</b>     '||coalesce(a.datvalid::text,null, '')||' <br><b>Surface </b>     '||coalesce(a.surface::text,null, '')||' </details>'), '' 
        order by a.type_doc DESC, a.nom ASC) as deroulant_zonage -- ordonne par type de document descendant et par nom de document acsendant
             from pre_fiche a
              where a.type_doc = 'Zonages'
             group by a.parcelle),
deroulant_secteurs as (select a.parcelle,-- création d'un déroulant "accordion html" secteur pour détail de la carte communale par parcelle
        string_agg(-- aggregation des données cc par parcelle : concatenation de blocs html et des champs d'infromations. Concatène seulement les valeurs non nulles.
    (    '<br><details class="accordion_urba"><summary>  Secteur '||coalesce(a.nom, null, '')||' </summary><b>DestDomi</b>     '||coalesce(a.destdomi,null, '')||'<br><b>Description</b>    '||coalesce(a.commentaire,null, '')||' <br><b>Approbation</b>     '||coalesce(a.datappro::text,null, '')||' <br><b> Validité</b>     '||coalesce(a.datvalid::text,null, '')||' <br><b>Surface</b>     '||coalesce(a.surface::text,null, '')||' </details>'), ''
    order by a.type_doc DESC, a.nom ASC) as deroulant_secteur -- ordonne par type de document descendant et par nom de document acsendant
             from pre_fiche a
              where a.type_doc = 'Secteurs'
             group by a.parcelle),
deroulant_prescriptions as (select a.parcelle,-- création d'un déroulant "accordion html"  des prescriptions pour détail par parcelle
        string_agg(-- aggregation des données  par parcelle : concatenation de blocs html et des champs d'infromations. Concatène seulement les valeurs non nulles.
    (    '<br><details class="accordion_urba"><summary> '||coalesce(a.nom, null, '')||' </summary><b>Description</b>     '||coalesce(a.commentaire,null, '')||' <br><b> Approbation </b>     '||coalesce(a.datappro::text,null, '')||' <br><b>Validité </b>     '||coalesce(a.datvalid::text,null, '')||' <br><b>Surface</b>     '||coalesce(a.surface::text,null, '')||' </details>'), ''
    order by a.type_doc DESC, a.nom ASC) as deroulant_prescription -- ordonne par type de document descendant et par nom de document acsendant
             from pre_fiche a
              where a.type_doc = 'Prescriptions'
             group by a.parcelle),

             deroulant_infos as (select a.parcelle, -- création d'un déroulant "accordion html" infos prescriptions pour détail par parcelle
        string_agg(-- aggregation des données  par parcelle : concatenation de blocs html et des champs d'infromations. Concatène seulement les valeurs non nulles.
    (    '<br><details class="accordion_urba"><summary>'||coalesce(a.nom, null, '')||'</summary><b>Description</b>     '||coalesce(a.commentaire,null, '')||' <br><b>Approbation</b>     '||coalesce(a.datappro::text,null, '')||'<br><b>Validité</b>    '||coalesce(a.datvalid::text,null, '')||'<br><b>Surface</b>     '||coalesce(a.surface::text,null, '')||'</details>'), ''
    order by a.type_doc DESC, a.nom ASC) as deroulant_info -- ordonne par type de document descendant et par nom de document acsendant
             from pre_fiche a
              where a.type_doc = 'Informations'
             group by a.parcelle)

select a.geo_parcelle::varchar as parcelle, concat(-- creation du tableau HTML principal détaillant le zonage ou carte communale, les prescriptions et les infos prescriptions
        '<table class = "t1" > 
  <tr>
    <th> Types </th>
    <th> Nom </th>
    <th> Règlement </th>
    <th> Impact </th>
    <th> Commentaire </th>
    <th> Taux d''inclusion </th>
  </tr>
  <tr>', string_agg( -- concatenation bloc html + aggregation des champs d'informations 
    ('<td> '  ||coalesce(b.type_doc,null, '')||  '  </td><td> ' ||coalesce(b.nom,null, '')|| '  </td><td> ' ||coalesce(b.reglement,null, '')|| '  </td><td>  ' ||coalesce(impact_text,null, '')|| '  </td><td>  '||coalesce(b.commentaire,null, '')||'  </td><td>  ' ||coalesce(b.taux_inclusion::text,null, '')||  '  </td>' ),'</tr>
        <tr>'order by b.type_doc DESC, b.nom ASC), -- ordonne par type de document descendant et par nom de document acsendant
        '</tr>
        </table>')::varchar as tab_doc_urba, deroulant_zonages.deroulant_zonage::varchar ,deroulant_secteurs.deroulant_secteur::varchar, -- ajout des champs html déroulants
         deroulant_prescriptions.deroulant_prescription::varchar, deroulant_infos.deroulant_info::varchar,
 a.geom
from
cadastre.parcelle_info a
left join pre_fiche b on b.parcelle = a.geo_parcelle
left join deroulant_zonages on deroulant_zonages.parcelle = a.geo_parcelle
left join deroulant_secteurs on deroulant_secteurs.parcelle = a.geo_parcelle
left join deroulant_prescriptions on deroulant_prescriptions.parcelle = a.geo_parcelle
left join deroulant_infos on deroulant_infos.parcelle = a.geo_parcelle
group by a.geo_parcelle, a.geom, deroulant_zonages.deroulant_zonage,deroulant_secteurs.deroulant_secteur,
 deroulant_prescriptions.deroulant_prescription, deroulant_infos.deroulant_info;



-- creation d'un index sur les numéros de parcelle de la table temporaire précédemment créée
CREATE INDEX index_temp_fiche  ON temp_fiche   USING btree (parcelle);

--- update du champ html HTML principal détaillant le zonage ou carte communale, les prescriptions et les infos prescriptions + déraoulants html de détail par parcelle
RAISE NOTICE 'Update parcelle info tab_doc_urba ';

update cadastre.parcelle_info set tab_doc_urba = z.tab_doc_urba from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;

RAISE NOTICE 'Update parcelle info deroulant_zonage ';

update cadastre.parcelle_info set deroulant_zonage = z.deroulant_zonage from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;

RAISE NOTICE 'Update parcelle info deroulant_secteur ';

update cadastre.parcelle_info set deroulant_secteur = z.deroulant_secteur from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;

RAISE NOTICE 'Update parcelle info deroulant_prescription ';

update cadastre.parcelle_info set deroulant_prescription = z.deroulant_prescription from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;

RAISE NOTICE 'Update parcelle info deroulant_info ';

update cadastre.parcelle_info set deroulant_info = z.deroulant_info from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;


RAISE NOTICE 'drop tables temp ';

-- supression des tables temporaires
drop table temp_parcelle_zonage_ref_urbanisme ;
drop table temp_parcelle_secteurs_ref_urbanisme;
drop table temp_parcelle_presc_surf ;
drop table temp_parcelle_presc_lin;
drop table temp_parcelle_presc_pct;
drop table temp_parcelle_info_surf;
drop table temp_parcelle_info_lin;
drop table temp_parcelle_info_pct;
drop table temp_fiche;

-- texte affiché en fin de focntion 
return 'Documents d''urbanismes intégrés';
END
$BODY$
LANGUAGE plpgsql;


-------------
-- moins de 1h30 moy pour l'ensemble du Calvados selon perf serveur
-----------
select ref_urbanisme.fiches_parcelles_lizmap();
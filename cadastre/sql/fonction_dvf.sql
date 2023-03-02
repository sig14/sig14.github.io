ALTER TABLE cadastre.parcelle_info
ADD column deroulant_dvf varchar;



--- Fonction de création/mise à jour d'un champs html de déroulants de mutations foncières des parcelles au format txt dans la table cadastre.parcelle_info

CREATE OR REPLACE FUNCTION ref_foncier.parcelles_valeur_fonciere_lizmap()
RETURNS 
text
  AS $BODY$
DECLARE 

BEGIN

RAISE NOTICE 'creation table temporaire dvf ';

--- créationd 'une table temporaire regroupant les déroulants de mutation par parcelle

CREATE UNLOGGED TABLE temp_dvf as
with parcelles_dvf as (
select  distinct on (
            a.code_ch,
            a.ref_doct,
            a.no_disposition,
            a.date_mutation,
            a.nature_mutation,
            a.valeur_fonciere,
            a.no_voie,
            a.b_t_q,
            a.type_de_voie,
            a.code_voie,
            a.voie,
            a.code_postal,
            a.code_dep,
            a.code_com,
            a.pref_section,
            a.section,
            a.no_plan,
            a.no_volume,
            a.premier_lot,
            a.surf_prem,
            a.deuxieme_lot,
            a.surf_deux,
            a.troisieme_lot,
            a.surf_trois,
            a.quatrieme_lot,
            a.surf_quatre,
            a.cinquieme_lot,
            a.surf_cinq,
            a.nb_lots,
            a.code_type,
            a.type_local,
            a.identifiant_local,
            a.surf_reelle_bati,
            a.nb_piece_princ,
            a.nature_culture,
            a.nature_culture_speciale,
            a.surf_terrain
            ) -- selection distinct de lignes valeur foncière (pour éviter les doublons)
    row_number() over() as id, -- creation d'un id unique
    b.geo_parcelle, b.geom, date_mutation, nature_mutation, valeur_fonciere , concat(no_voie, ' ', type_de_voie,' ', a.voie,' ', code_postal) as adresse ,
     type_local, nb_piece_princ,  surf_reelle_bati, surf_terrain,
      c.libelle as nature_culture, -- ajout de la nature culture 
       d.libelle as nature_culture_speciale -- ajout de la nature culture spéciale 
from cadastre.parcelle_info b --- jointure de la tbale parcelle_info 
inner join  ref_foncier.valeurs_foncieres a
on b.geo_parcelle = concat(concat(code_dep, '0'), code_com, pref_section, section, no_plan) 
left join ref_foncier.valeurs_foncieres_cultures c on a.nature_culture = c.code 
left join ref_foncier.valeurs_foncieres_cultures_speciales d on a.nature_culture_speciale = d.code),

 group_parcelle as (--- creation du champ html : bloc html + info mutation, decomposition type local + nature culture
select a.geo_parcelle, a.date_mutation,
       
       concat('<br><details class="accordion_valeur_fonc"><summary>', nature_mutation,' / ', coalesce(valeur_fonciere,null, 'xx'),' euros <br>', 
        date_mutation,'<br>',coalesce(a.adresse,null, ''), '</summary>',
        string_agg( ('<br> '|| case when a.type_local = 'Maison' then '<img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/house.png" width="20"' 
                                    when a.type_local = 'Appartement' then '<img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/apartment-xxl.png" width="20"' 
                                    when a.type_local = 'Local industriel. commercial ou assimilé' then '<img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/shop.png" width="20"' 
                                    when a.type_local = 'Dépendance' then '<img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/dependance.png" width="20"'
                                    else '' end || '</img>     '||-- decompostion du type de local : ajout d'un lien vers image github associé selon le type
        
                    concat(a.type_local,' <br>     ')
                    ||case when (a.nb_piece_princ = '0' or a.nb_piece_princ is null) then ''
                     else concat(a.nb_piece_princ::text, ' pièces<br>     ') end ||
                    case when (a.surf_reelle_bati = '0' or a.surf_reelle_bati is null) then '' else concat(a.surf_reelle_bati::text, 'm²<br>') end), '' order by date_mutation::date DESC
                    ),--- ajout de la nature terrain si present : surface terrain avec image terrain associé , null si pas de valeur de surface
            nullif(concat( '<br><br><img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/grass.png" width="20" </img> Terrain<br>' , surf_terrain, ' m² <br>'),
            '<br><br><img class="fit-picture" src="https://raw.githubusercontent.com/sig14/sig14.github.io/main/img/grass.png" width="20" </img> Terrain<br> m² <br>'),
            
             nullif(translate(array_agg( DISTINCT nature_culture::text )::text, '{}', '' ), 'NULL'),'<br>' --- aggregation des natures de cultures, null si pas de valeur
            , nullif(replace(translate(array_agg( DISTINCT nature_culture_speciale::text)::text, '{}', ''), 'NULL', ''), ''), '</details>'  --- aggregation des natures de cultures spéciales, null si pas de valeur
            ) as deroulant_dvf
from parcelles_dvf a
group by a.geo_parcelle, a.date_mutation, valeur_fonciere, nature_mutation, adresse,surf_terrain
)

select a.geo_parcelle, string_agg((deroulant_dvf), '' order by date_mutation::date DESC) as deroulant_dvf --- aggreger les déroulants par parcelle et les ordonner par date de mutation
from group_parcelle a
group by a.geo_parcelle;

RAISE NOTICE 'indexation de la table temporaire ';

-- création d'un index sur la table temporaire au niveau du numéro de parcelle

      CREATE INDEX index_temp_dvf  ON temp_dvf  USING btree (geo_parcelle);

RAISE NOTICE 'update de la table parcelle_info';

--- passser les valeurs de deroulant à null

update cadastre.parcelle_info set deroulant_dvf = null;

-- update du champs deroulant html de cadastre.parcelle_info au niveau du numero de parcelle

update cadastre.parcelle_info set deroulant_dvf = b.deroulant_dvf from temp_dvf b where b.geo_parcelle = parcelle_info.geo_parcelle;

RAISE NOTICE 'drop table temp';

-- supprimer la table temporraire
drop table temp_dvf ;

-- retourne le texte en fin de fonction
return 'Déroulants dvf intégrées';
END
$BODY$
LANGUAGE plpgsql;

----
--Lancement de la fonction
----
select ref_foncier.parcelles_valeur_fonciere_lizmap()




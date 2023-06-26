
alter table cadastre.parcelle_info add column tab_filiation text;


---  Fonction de création/maj d'un déroulant HTML de l'historique des filiations de parcelles dans un champs txt de la table cadstre.parcelle_info

CREATE OR REPLACE FUNCTION ref_foncier.tab_filiation_lizmap(
	)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE 

BEGIN

RAISE NOTICE 'creation table temporaire dfi';

----------------------
--- création d'une table temporaire regroupant ligne par ligne les infos dfi, la nature détaillée des dfi, la liste des parcelles mère et la liste des parcelle filles associées (filiation)
---------------------

create UNLOGGED TABLE temp_parcelles_dfi as
 SELECT 
 a.code_com AS code_com,
    a.pref_section AS pref_section,
    a.id_dfi,
    a.num_analyse,
    a.date_valid,
    case when
    a.nature_dfi = '1' then 'arpentage'
    when a.nature_dfi = '2' then 'croquis de conservation'
    when a.nature_dfi = '4' then 'remaniement'
    when a.nature_dfi = '5' then 'arpentage numerique'
        when a.nature_dfi = '6' then 'lotissement numérique'
        when a.nature_dfi = '7' then 'lotissement'
            when a.nature_dfi = '8' then 'rénovation'end as nature_dfi,-- détail de la nature en fonction du code_nature

    a.list_parcelle AS parcelles_meres, -- liste des parcelles mères quand type_ligne = 1
    b.list_parcelle AS parcelles_filles --liste des parcelles filles associées aux parcelles mères quand type_ligne = 2 (jointure sur date, code com, section, id_dfi et numero d'analyse)
   FROM ref_foncier.parcelles_dfi a,
    ref_foncier.parcelles_dfi b
  WHERE a.type_ligne = '1'::text AND b.type_ligne = '2'::text AND concat(a.date_valid, a.code_com, a.pref_section, a.id_dfi, a.num_analyse) = concat(b.date_valid, b.code_com, b.pref_section, b.id_dfi, b.num_analyse);

RAISE NOTICE 'creation des indexes de la table temporaire dfi';

--- création des indexes de la table temporaire
   CREATE INDEX index_temp_parcelles_dfi ON  temp_parcelles_dfi USING btree (code_com);

      CREATE INDEX index2_temp_parcelles_dfi ON  temp_parcelles_dfi USING btree (pref_section);

RAISE NOTICE 'creation table temporaire init';

----------------
-- création d 'une table temporaire listant les premières filiations liées aux parcelles actuelles du cadastre
----------------

create UNLOGGED TABLE temp_parcelles_init as 
with parcelle_init as (	-- liste des parcelles du cadastre qui sont comprises dans les parcelles filles dfi 
			select a.code_com, a.date_valid, a.nature_dfi, a.pref_section, a.id_dfi, a.num_analyse, 
      a.parcelles_meres, -- Conservation des parcelles mères dfi dont les filles comprennent une parcelle du cadastre
      concat('{', b.ccosec, b.dnupla, '}')::text[] as parcelles_filles, -- Parcelle du cadastre associée aux parcelles filles dfi
       replace(a.parcelles_filles::text,concat( b.ccosec, b.dnupla), '')  as parcelles_soeurs -- Supprimer (remplacer par '') la parcelle du cadastre associée de la liste des parcelles filles pour trouver les parcelles soeurs
            from temp_parcelles_dfi a, cadastre.parcelle b
            where  concat(b.ccosec, b.dnupla) = ANY(a.parcelles_filles::text[]) -- jointure sur les num parcelle et section cadastre dans les parcelles filles dfi
            and a.code_com::text = b.ccocom -- et sur une même commune
            and a.pref_section::text = translate(b.ccopre, ' ', '0')  ) -- et sur un même prefixe de séction
    
    select a.code_com, a.date_valid, a.nature_dfi, a.pref_section,  
    a.parcelles_meres::text[], a.parcelles_filles::text[] , replace(translate(parcelles_soeurs::text, '{}', ''), ',', ' ') as parcelles_soeurs, -- transformation en format liste des listes de parcelles
    1 as num_filiation, -- création d'un numéro de filiation
    concat(translate(a.parcelles_filles::text, '{}','') ) as id_filiation ---conserver le numéro de parcelle fille initial en format txt
    from parcelle_init a ; 

RAISE NOTICE 'creation des indexes de la table temporaire dfi';

--- création des indexes de la table temporaire
   CREATE INDEX index_temp_parcelles_init ON  temp_parcelles_init USING btree (code_com);

      CREATE INDEX index2_temp_parcelles_init ON  temp_parcelles_init USING btree (pref_section);

            CREATE INDEX index3_temp_parcelles_init ON  temp_parcelles_init USING btree (parcelles_filles);

RAISE NOTICE 'lancement de la recursive pour temp table filiation';

------------------------------------------------------------
-- création d'une table temporaire contenant le déroulant HTML de l'historique des filiations de parcelles dans un champs txt avec num parcelle associé
---------------------------------------------------------

         CREATE UNLOGGED TABLE temp_parcelle_filiation as

    with recursive search_meres (code_com, date_valid, nature_dfi, pref_section,  parcelles_meres , parcelles_filles, parcelles_soeurs,  num_filiation, id_filiation)  as (-- paramètres récursive
		
		   
    select a.* --selection des filiations initiales au cadastre
    from temp_parcelles_init a
    
		UNION -- union pour la recursivité

            select c.code_com,c.date_valid, c.nature_dfi, c.pref_section,    
            c.parcelles_meres::text[], -- Conservation des parcelles mères dfi dont les filles comprennent d'autres parcelles filles dfi
            array(select unnest(c.parcelles_filles::text[])
            intersect 
            select unnest( d.parcelles_meres::text[])) as parcelles_filles ,---- selectionner les parcelles filles dfi comprises dans les listes de parcelles mères initiales
          
            array(select unnest(c.parcelles_filles::text[])
            except
            select unnest( d.parcelles_meres::text[]))::text as parcelles_soeurs, ---- selectionner les parcelles filles dfi non comprises dans les listes de parcelles mères initiales pour trouver les parcelles soeurs
            
            d.num_filiation + 1 as num_filiation, -- ajout de 1 au numéro de filiation 
            
            d.id_filiation --- conserver le numéro de parcelle cadastre initial en txt

            from temp_parcelles_dfi c, search_meres d
            where d.parcelles_meres::text[]  @> c.parcelles_filles::text[] -- jointure des parcelles dfi aux parcelles initiales quand au moins une parcelle de la liste parcelle mère initiale est comprise dans la liste parcelle fille dfi
            AND concat(d.code_com, d.pref_section) = concat(c.code_com, c.pref_section)), -- et sur le code commune et prefixe de section

 result as (select row_number() over() as fid, a.* from search_meres a ) --- selectionner le resultat de la recursive et ajouter un id unique

select row_number() over() as id, --- creation du html
    concat(-- bloc html creant la table deroulante
    '<table class = "t2">
  <thead>
    <tr>
      <th>date de filiation </th>
      <th>nature de la filiation</th>
    </tr>
  </thead>
  <tbody>',
  string_agg(-- aggregation des infos  dfi filles, meres et soeurs : date, parcelles ordonnées par le numéro de filiation 
    concat('<tr>
      <td><label for="row',fid , '"></label>' ,  date_valid::text::date ,
      '</td>
      <td>', nature_dfi , '</td>
    </tr><tr>
      <td colspan="6">
        <input id="row',fid,'" type="checkbox">
        <table>
          <tr class = "body_blue">
            <th>Nouvelle(s) parcelle(s)</th>
            <th>Parcelle(s) soeur(s)</th>
            <td>Ancienne(s) parcelle(s)</td>
       </tr>
          <tr>
            <th>',translate(parcelles_filles::text, '{}', ''),'</th>
            <th>',translate(parcelles_soeurs::text, '{}', ''),'</th>
            <td>',translate(parcelles_meres::text, '{}', ''),'</td>
          </tr>
        </table>'
       ) , '</td>
    </tr>'
      order by num_filiation asc),'</tbody>
</table>') as tab_filiation, concat('140',code_com, pref_section, id_filiation) as num_parcelle -- creation du num parcelle : cod dep + codcom + pref_section + num_parcelle cadastre initial
    from result a
    group by code_com, pref_section, id_filiation; -- grouper par parcelle, pref section et num parcelle cadastre initial
    
    
    RAISE NOTICE 'creation index de la table temporaire ';

--creation d'un index sur la table temporaire au niveau du num parcelle
    
   CREATE INDEX index_temp_parcelle_filiation ON  temp_parcelle_filiation USING btree (num_parcelle);

    RAISE NOTICE 'update du champs parcelle_info ';

--- update du champ html filiation au niveau du num parcelle

update cadastre.parcelle_info set tab_filiation = a.tab_filiation from temp_parcelle_filiation a where a.num_parcelle = geo_parcelle;

update cadastre.parcelle_info set tab_filiation = 'Pas de données' where tab_filiation is null;

    RAISE NOTICE 'drop tables temporaires ';

--- supression des tables temporaires

drop table temp_parcelles_dfi;

drop table temp_parcelle_filiation;
drop table temp_parcelles_init;

--- texte retourné en fin de fonction
return 'Filiation terminée';
END
$BODY$;
LANGUAGE plpgsql;




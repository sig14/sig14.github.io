Cadastre
#########

I- Mise à jour annuelle
******************************

.. image:: ../images/Cadastre/schema_intro_maj_anuelle.png
   :width: 880

1- Installation du plugin cadastre 
========================

La mise à jour du cadastre s'effectue sur le serveur APW65.

Télécharger la dernière version stable du plugin cadastre Qgis `ici <https://github.com/3liz/QgisCadastrePlugin/releases>`_


Déplacer le zip sur apw65 et installer le depuis le menu **extension** de QGIS.

.. image:: ../images/Cadastre/1_plugin_cadaster.png
   :scale: 50

Une fois le plugin installé, un nouveau menu Cadastre apparaît dans le menu Extensions de QGIS. Il comporte les sous-menus suivants :

    * Importer des données
    * Charger des données
    * Outils de recherche
    * Exporter la vue
    * Configurer le plugin
    * À propos
    * Notes de version
    * Aide


2- Récupération des données cadastre
========================


**Plan Cadastral Informatisé (PCI)**

* Télécharger les données Millésime 1er au 1er janvier du PCI Vecteur au format EDIGEO :  `Site cadastre EDIGEO <https://cadastre.data.gouv.fr/datasets/plan-cadastral-informatise>`_


**Mise A Jour des Informations Cadastrales (MAJIC)**

* Transmission chaque année (juillet/aout) des données MAJIC par la DDFIP. 
* Les données MAJIC transmises correspondent à un état des lieux à janvier de l'année courante.

**Fichier ANnuaire TOpographique Initialisé Réduit (FANTOIR)**
* Télécharger des données à l'échelle de la région Normandie :  `Site fantoir collectivites-locales.gouv.fr <https://www.collectivites-locales.gouv.fr/competences/la-mise-disposition-gratuite-du-fichier-des-voies-et-des-lieux-dits-fantoir>`_

L'ensemble des fichiers sont déposés sur `le serveur APW65 <file:////apw65/_CADASTRE_DONNEES/>`_

3- Recencer les dépendances au schema cadastre
================================================

La mise à jour des données cadastre dans le base de données postgresql nécessite de remplacer l'intégralité des tables de données, des vues et vues matérialisées qui en dépendent.

Il est donc nécéessaire de garder en mémoire les vues et vm dépendantes du schema afin de pouvoir les rejlancer après intégration des donénes cadastre.

Nous allons créer une table listant les vues et  vm dépendantes du schema cadastre et le code sql qui leur est associé.

Pour cela nous lançons la requête suivante :

      .. code-block:: sql

                drop table if exists public.dependances_v_vm_cadastre;
                create table  public.dependances_v_vm_cadastre as                       
                with a as 
                
                (WITH RECURSIVE s(start_schemaname, start_relname, start_relkind, relhasindex, schemaname, relname, relkind, reloid, owneroid, ownername, depth) AS (--recursive sur l'ensemble des données du schema cadastre 
                        SELECT n.nspname AS start_schemaname, -- nom du schema
                            c.relname AS start_relname, -- nom de la table
                            c.relkind AS start_relkind, 
                            c.relhasindex,
                            n2.nspname AS schemaname, -- nom du schema de la table dépendante
                            c2.relname, -- nom de la table dépendante
                            c2.relkind,
                            c2.oid AS reloid,
                            au.oid AS owneroid,
                            au.rolname AS ownername,
                            0 AS depth -- Commencer la dépendance à 0
                        FROM pg_class c
                            JOIN pg_namespace n ON c.relnamespace = n.oid AND (c.relkind = ANY (ARRAY['m', 'v','r','t','f', 'p'])) -- on commence par lister les tables, vues, vm dus chema cadastre
                            JOIN pg_depend d ON c.oid = d.refobjid
                            JOIN pg_rewrite r ON d.objid = r.oid
                            JOIN pg_class c2 ON r.ev_class = c2.oid
                            JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
                            JOIN pg_authid au ON au.oid = c2.relowner
                    where n.nspname = 'cadastre' -- on limite le schema d'origine au cadastre
                        UNION -- union pour la récursivité
                        SELECT s_1.start_schemaname,
                            s_1.start_relname,
                            s_1.start_relkind,
                            s_1.relhasindex,
                            n.nspname AS schemaname,
                            c2.relname,
                            c2.relkind,
                            c2.oid,
                            au.oid AS owneroid,
                            au.rolname AS ownername,
                            s_1.depth + 1 AS depth -- on ajoute 1 pour chaque dépendance trouvée
                        FROM s s_1
                            JOIN pg_depend d ON s_1.reloid = d.refobjid
                            JOIN pg_rewrite r ON d.objid = r.oid
                            JOIN pg_class c2 ON r.ev_class = c2.oid AND (c2.relkind = ANY (ARRAY['m'::"char", 'v'::"char"])) --- on limite les dependances aux vues et vues materialisées
                            JOIN pg_namespace n ON n.oid = c2.relnamespace
                            JOIN pg_authid au ON au.oid = c2.relowner
                        WHERE s_1.reloid <> c2.oid --- on joint les dépendance au niveau de l'oid
                        )
                SELECT -- lancement de la recursive
                    s.schemaname::varchar,
                    s.relname::varchar,
                    s.relkind,
                    sum(s.depth) as depth,
                    case when relkind = 'v' then 'VIEW' else 'MATERIALIZED VIEW' end as kind -- on précise les acronymes view et matview
                    FROM s
                        group by 
                    s.schemaname,
                    s.relname,
                    s.relkind,
                    s.depth
                    order by s.depth),

                z as (select a.*,
                case when a.relkind = 'm' then b.definition -- on ajoute les requêtes sql dans un champs
                ELSE c.view_definition end as query,
                i.indexdef as queryndex -- on ajoute les requêtes d'indexe dans un champs
                from a
                left join  pg_matviews b on b.schemaname = a.schemaname and b.matviewname = a.relname
                left join  information_schema.views c on c.table_schema = a.schemaname and c.table_name = a.relname
                left join  
                    pg_indexes i on a.schemaname = i.schemaname and i.tablename = a.relname 
                order by depth)
                
                
                select z.schemaname::varchar,
                    z.relname::varchar,
                    z.relkind,
                    z.kind,
                    sum(z.depth) as depth, --on somme les dépendances pour ordoner le futur rafraichissemnt en focntion du nume de dépendance
                    z.query, z.queryndex
                from z
                group by 
                    z.schemaname,
                    z.relname,
                    z.relkind,
                    z.kind,
                    z.query,
                z.queryndex
                order by depth;
                ;


Le code de la VM se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/cadastre/_maj_view_annuelle/1_dependances_vues_vms_cadastre.sql>`_

.. image:: ../images/Cadastre/2_table_dependances_cadastre.png
   :scale: 50



4- Import des données cadastre
================================================

* Modifier le nom du schema cadsatre en schema cadastre2 sur pgadmin, aafin, par sécurité, de conserver la précédente version du schema cadsatre.

* Paramètrer le plugin en séléctionnant configuration. Sélectionner les bon noms et types de fichiers.

.. image:: ../images/Cadastre/3_conf_plugin.png
   :scale: 50


.. image:: ../images/Cadastre/4_conf_plugin_2.png
   :scale: 50


* Lancer l'import postgis avec les paramètres suivants :
- Base de données : Postgis, lizmap
- Schémas : taper cadastre et créer
- Fichiers EDIGEO : charger le dossier déposé sur APW65
- scr source : 2154
- scr cible : 2154
- Fichiers MAJIC: charger le dossier déposé sur APW65
- Département  : 14
- Lot : "donner un nom pour l'import"
.. image:: ../images/Cadastre/5_import_plugin.png
   :scale: 50


.. image:: ../images/Cadastre/6_import_plugin_2.png
   :scale: 50


5- Relancer les vues et VM dépendantes du cadastre
================================================

Pour relancer les vues et vm dépendandante, lancer la requête suivante :

      .. code-block:: sql

            select create_v_vm_cadastre()


Cette requête appelle la fonction dont le code se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/cadastre/_maj_view_annuelle/2_refresh_dependances_vues_vm_cadastre.sql>`_

6- Actualiser les données cadastres des autres schémas
=====================================================

Afin de limiter les dépendance au schema cadastre, une copie des données est effectuée dans les schemas suivants :

* **adresse**

Le code à lancer pour la copie des données se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/cadastre/maj_anuelle_parcelle_cadastre.sql>`_


* **fibre_calvados**

Le code à lancer pour la copie des données se trouve `ici <file://file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/fibre/maj_anuelle_parcelle_cadastre.sql>`_


7- Actualiser les fiches HTML de la table parcelle_info
=====================================================

Des champs HTML ont été dévellopés par l'équipe SIG du Départements afin de renseigner des informations complémentaires à la parcelle : Reglementation GPU par parcelle, historique des filiations de parcelle, historique des mutations immobilières.

Les processus de construction des champs est décrit en partie II, III et IV.

A chaque réimport du cadastre il est nécessaire de recréer et mettre à jour ces champs.

7.1 - Documents d'urbanisme 
---------------------------

* Créer le champ contenant l'html de table contenant les informations GPU par parcelle

        .. code-block:: sql

                ALTER TABLE cadastre.parcelle_info
                ADD tab_doc_urba varchar;


* Créer les champs contenant l'html des déroulants détaillant les informations contenues dans le tableau

        .. code-block:: sql

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_zonage varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_secteur varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_prescription varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_info varchar;

* Lancer la fonction méttant à jour les champs (1 heure environ)

        .. code-block:: sql

                select ref_urbanisme.fiches_parcelles_lizmap();


7.2 - Filiations parcellaire
---------------------------

* Créer les champs contenant l'html des déroulants détaillant l'historique de diliation par parcelle

        .. code-block:: sql

            alter table cadastre.parcelle_info add column tab_filiation text;


* Lancer la fonction méttant à jour les champs 

        .. code-block:: sql

            select ref_foncier.tab_filiation_lizmap()


7.3 - Mutations immobilières
---------------------------

* Créer les champs contenant l'html des déroulants détaillant les mutations immobilières

        .. code-block:: sql

            ALTER TABLE cadastre.parcelle_info add column deroulant_dvf varchar;


* Lancer la fonction méttant à jour les champs

        .. code-block:: sql

            select ref_foncier.parcelles_valeur_fonciere_lizmap()






II- Onglet Documents d'urbanisme GPU
************************************

Le service d’interrogation du GPU permet d’obtenir les différentes informations d’urbanisme intersectant une géométrie (ponctuelle ou surfacique). Ces informations sont disponibles en consultation et en téléchargement sur le `Géoportail de l'urbanisme <https://www.geoportail-urbanisme.gouv.fr/>`_

Le dépratement met a disposition des communes l'ensemble de ces informations, ainsi que celles du cadastre sur son portail cartographique.
Afin de faciliter la lecture des informations, l'ensemble des données du GPU sont collectées dans la base de données du Département à chaque mise à jour sur le GPU par les colectivités et agglomérées à l'echelle de la parcelle.

Cela permet aux partenaires du CD14 de pouvoir consulter rapidement les informations du GPU liées à chaque parcelle : impact des zonages sur la parcelle, documents pdf associés, etc.


.. image:: ../images/Cadastre/8_fiches_dosc_urba.gif
   :scale: 50

.. image:: ../images/Cadastre/7_schema_fiches_dosc_urba.png
   :scale: 50



1- Import FME des données GPU
=========================

L'import des données de l'API GPU se fait via le logiciel ETL FME.

Dans un premier les données GPU sont chargées dans la base de données du CD14 à l'échelle du Calvados.

Les données du GPU sont segementées par collectivité via un code partition formé : 

* du prefixe DU_
* du code insee commune ou siren epci (en fonction du type de document : carte communale, PLU, PLUI)
* D'un code optionnel de secteur pour les EPCI (A, B, C, D)

Pour le Calvados, les codes insee des communes correspondent aux codes insee des communes historique (avant loi NOTRE).

Pour finir, certaines communes sont soumises au RNU (Réglement National d'Urbanisme) et n'ont donc pas de documents d'urbanisme enregistrée sur le GPU.

1.1 - Zonages et cartes communales
---------------------------------

Un premier projet FME récupère les données d'emprise de document ainsi que les zonages PLU et secteurs de cartes communales.

Le workbench FME chargeant les données depuis l'API, réalisant le traitement et l'intégration des données en base se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Calvados/1_api_zonage_gpu2postgis.fmw>`_


* Récupération des codes siren EPCI et ajout des potentiels suffixes (code optionnel secteur)

.. image:: ../images/Cadastre/9_siren_epci_dosc_urba.png
   :scale: 50

* Récupération des codes insee des communes historiques

.. image:: ../images/Cadastre/10_insee_communes_doc_urba.png
   :scale: 50

* Intérogation de l'API pour connaitre les communes au RNU ou non

On intérroge l'API avec les paramètres suivants :

URL : http://apicarto.ign.fr/api/gpu/municipality?insee=@Value(insee)

HTPP method : GET

response body : Attribute

.. image:: ../images/Cadastre/11_api_rnu_doc_urba.png
   :scale: 50

* Filtrer les communes qui ne sont pas au RNU et stocker les valeurs (rnu = true/flase) dans une table à part (pour information)

.. image:: ../images/Cadastre/12_filtre_rnu_doc_urba.png
   :scale: 50


* Récupération des données depuis l'API avec les DU_ précédemments créés : données emprise, zonage et secteur carte communale

On intérroge l'API avec les paramètres suivants :

**emprise** :

URL : https://apicarto.ign.fr/api/gpu/document?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

**zonage** :

Intérrogation de l'API avec les DU_partition précédemment créés

URL : https://apicarto.ign.fr/api/gpu/zone-urba?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

**secteur carte communale** :

URL : https://apicarto.ign.fr/api/gpu/secteur-cc?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

.. image:: ../images/Cadastre/13_get_data_doc_urba.png
   :scale: 50


* Filtrer les données à partir de la réponse JSON : Expression régulière conservant le chiffre après 'totalFeatures' et conservation des lignes dont la valeur est différente de 0.

.. image:: ../images/Cadastre/14_numb_feature_filter_doc_urba.png
   :scale: 50

* Extraction des données du JSON : exposer les attributs et la géométrie

.. image:: ../images/Cadastre/15_expose_attributes_doc_urba.png
   :scale: 50

* Retraitement des données : supression des prefixes de champs et reprojection de la géométrie (de 4326 à 2154)

.. image:: ../images/Cadastre/16_reprojection_doc_urba.png
   :scale: 50



1.2 - Prescriptions
-------------------

Un second projet FME récupère les données de prescriptions linéaires, surfaciques et ponctuel sur le même modèle que précédemment, à l'exception de :

Le workbench FME se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Calvados/api_prescriptions_gpu2postgis.fmw>`_

* Récupération des codes insee des communes historiques qui ne sont pas classées au rnu depuis la table crée dans la partie précédente

.. image:: ../images/Cadastre/17_rnu_doc_urba.png
   :scale: 50

* Récupération des données depuis l'API avec les DU_ précédemments créés : données linéaires, surfaces et ponctuels

On intérroge l'API avec les paramètres suivants :

**surface** :

URL : https://apicarto.ign.fr/api/gpu/info-surf?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

**linéaire** :

URL : https://apicarto.ign.fr/api/gpu/info-lin?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute


**ponctuel** :

URL : https://apicarto.ign.fr/api/gpu/info-pct?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute



1.3- Infos prescriptions
-------------------------

Un dernier projet FME récupère les données informations prescriptions linéaires, surfaciques et ponctuel sur le même modèle que précédemment.

Le workbench FME se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Calvados/api_info_prescriptions_gpu2postgis.fmw>`_


* Récupération des données depuis l'API avec les DU_ précédemments créés : données linéaires, surfaces et ponctuels

On intérroge l'API avec les paramètres suivants :

**surfaces** :

URL : https://apicarto.ign.fr/api/gpu/info-surf?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

**linéaires** :

URL : https://apicarto.ign.fr/api/gpu/info-lin?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

**ponctuels** :

URL : https://apicarto.ign.fr/api/gpu/info-pct?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute



2- Champ HTML GPU par parcelle du cadastre
==========================================

L'objectif est ici de pouvoir consulter les données du GPU à l'échelle de la parcelle.

L'utilisateur peut en cliquant sur une parcelle, consulter les données du GPU qui intersectent la parcelle, ouvrir les documents pdf associés sur le portail du GPU et connaitre l'impact des réglements sur la parcelle.

Pour cela on utilise une fonction postgresql/gis pour alimenter la table parcelle_info du cadastre et une mise en forme du formulaire QGIS en HTML pour publication sur le portail cartographique Lizmap.


2.1 - Fonction postgresql/gis
-----------------------------

* En premier lieu, on corrige les géométries invalides des données GPU intégrés à la base de données CD14

        .. code-block:: sql

                update ref_urbanisme.gpu_api_zonages set geom = ST_MakeValid(geom);

                update ref_urbanisme.gpu_api_secteur_cc set geom = ST_MakeValid(geom);

                update ref_urbanisme.gpu_api_prescription_surf set geom = ST_MakeValid(geom);

                update ref_urbanisme.gpu_api_prescription_lin set geom = ST_MakeValid(geom);

                update ref_urbanisme.gpu_api_info_prescription_surf set geom = ST_MakeValid(geom);

                update ref_urbanisme.gpu_api_info_prescription_lin set geom = ST_MakeValid(geom);


* On Créé le champ contenant l'html de table contenant les informations GPU par parcelle

        .. code-block:: sql

                ALTER TABLE cadastre.parcelle_info
                ADD tab_doc_urba varchar;


* On créé ensuite les champs contenant l'html des déroulants détaillant les informations contenues dans le tableau

        .. code-block:: sql

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_zonage varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_secteur varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_prescription varchar;

                ALTER TABLE cadastre.parcelle_info
                ADD deroulant_info varchar;


On lance ensuite une fonction postgrresql/gis dont le code SQL se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/doc_urba/fiche_parcelle_doc_urba.sql>`_

* Dans un premier temps, la fonction met en place des tables temporaires rapprochant les parcelles du cadastre avec les données du GPU. L'objectif est également de pouvoir indexer ces tables temporaires pour accélerer la suite des traitements.

*exemple de rapprochement des zonages PLU*

         .. code-block:: sql

                  CREATE UNLOGGED TABLE temp_parcelle_zonage_ref_urbanisme as 
                     select  p.geo_parcelle, z.*
                     FROM cadastre.parcelle_info p
                     inner join ref_urbanisme.gpu_api_zonages z 
                     on  st_intersects(p.geom, z.geom) and p.geom&&z.geom;

                  -- Indexation de la table temporaire    
                        CREATE INDEX index_temp_parcelle_zonage_ref_urbanisme ON temp_parcelle_zonage_ref_urbanisme USING btree (geo_parcelle);
                        CREATE INDEX index2_temp_parcelle_zonage_ref_urbanisme ON temp_parcelle_zonage_ref_urbanisme USING btree (id);


                  CREATE INDEX index_geom_temp_parcelle_zonage_ref_urbanisme
                  ON temp_parcelle_zonage_ref_urbanisme USING gist (geom);


* Dans un second temps, on réalise l'union des tables temporaires, on calcul l'impact des zonages GPU par parcelle (par intersection) ainsi que la surface totale de chaque zonage. 


*exemple d'UNION des zonages PLU et secteurs cartes communales*

         .. code-block:: sql

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

* On ne conserve que les entités dont l'impact sur la parcelle est supérieure à 1 ou qui sont des ponctuels et on construit les liens html pour consultation des documents pdf sur le GPU (concatenation de blocs html + num partition + clé dossier pdf emprise + nom de fichier)

         .. code-block:: sql
            
                  select geo_parcelle as parcelle, type_doc, destdomi, nom, datappro, datvalid, surface, impact,
                  case when impact_txt = 'surf' then 
                              concat(round(impact::numeric, 2)::text, ' m²')
                              when impact_txt = 'lin' then
                              concat(impact::text, 'm')
                              else impact_txt end -- creation de l'impact en text avec suffixe m² si surf, m si lineaire, sinon pas de suffixe
                              as impact_text ,
                  case when parcelle_ref_urbanisme.nomfic is not null  then concat('<a href="', 'https://wxs-gpu.mongeoportail.ign.fr/externe/documents/',parcelle_ref_urbanisme.partition,'/',
                  b.id,'/', parcelle_ref_urbanisme.nomfic, '" target="_blank">Règlement</a>') else 'no data' end as reglement, 

                  commentaire, round(impact*100/area_parcelle) as taux_inclusion -- création taux d'inclusion : pourcentage de l'impact sur la surface de la parcelle
                  from parcelle_ref_urbanisme
                  left join ref_urbanisme.gpu_api_emprise b on parcelle_ref_urbanisme.partition = b.partition -- jointure  de l'emprise pour selection de la clé dossier pdf
                  where  (parcelle_ref_urbanisme.impact >= 1 or parcelle_ref_urbanisme.impact_txt ='ponctuel')
                  order by geo_parcelle, type_doc DESC, nom ASC


* On construit ensuite les déroulants de détail en html(en accordéon) : concatenation de blocs html et des champs d'informations. On concatène seulement les valeurs non nulles.

*exemple de création de déroulant accordéon zonage PLU*

         .. code-block:: sql

               select a.parcelle, -- création d'un déroulant "accordion html" zonage pour détail du zonage par parcelle
                     string_agg( 
                                 ('<br><details class="accordion_urba"><summary> Zone '||coalesce(a.nom, null, '')||'</summary><b>DestDomi</b>      '||coalesce(a.destdomi,null, '')||'<br><b>Description</b>     '||coalesce(a.commentaire,null, '')||' <br><b>Approbation</b>     '||coalesce(a.datappro::text,null, '')||' <br><b>Validité</b>     '||coalesce(a.datvalid::text,null, '')||' <br><b>Surface </b>     '||coalesce(a.surface::text,null, '')||' </details>'), '' 
                     order by a.type_doc DESC, a.nom ASC) as deroulant_zonage -- ordonne par type de document descendant et par nom de document acsendant
                           from pre_fiche a
                           where a.type_doc = 'Zonages'
                           group by a.parcelle

* creation du tableau HTML principal détaillant le zonage ou carte communale, les prescriptions et les infos prescriptions et ajout des déroulants de détails précédemment crééS

         .. code-block:: sql

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


* création d'un index sur la table temporaire et update des champs html de la table parcelle info 

*exemple de mise à jour du champs tableau html*

         .. code-block:: sql

               update cadastre.parcelle_info set tab_doc_urba = z.tab_doc_urba from temp_fiche z where z.parcelle = parcelle_info.geo_parcelle;


2.2 - Paramètrage Qgis/plugin Lizmap
------------------------------------

* Mise à jour de l'info bulle HTML dans les propriété de la couche QGIS


.. image:: ../images/Cadastre/18_info_bulle_html.png
   :scale: 50


Le code HTML (Onglet Urbanisme + parties tab_doc_urba + deroulant_: secteurs, zonages, prescriptions, info) se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/html/popup_cadastre.html>`_



2.3 - Rendu lizmap
------------------

* Mise à jour du CSS dans le panneau de configuration Lizmap

Le code CSS se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/css/style_docs_urba_cadastre.css>`_


.. image:: ../images/Cadastre/19_config_css.png
   :scale: 50


3- Mise à jour quotidienne des données
======================================

A chaque modification d'un document ou ajout par une collectivité sur le GPU, le pôle SIG du Département met à jour les données issues du GPU dans la base de donnée CD14 et met éhalement à jour les fiches HTML de la table patrcelle info du cadastre.


3.1 - Mailing auto
-----------------------------

Le Géoportail de l'Urbanisme met à disposition un flux ATOM permettant de connaitre les dernières mises à jour de documents sur le GPU.

La documentation suivante décrit comment exploiter ce flux : `<https://www.geoportail-urbanisme.gouv.fr/image/UtilisationATOM_GPU_1-0.pdf>`_

Le pôle SIG utilise un site dédié qui exploite ce flux afin d'envoyer un mail à l'équipe SIG à chaque ajout d'une commmune du Département du calvados.

A la récéption de ce mail, un membre de l'équipe déclenche un fichier batch, permettant d'indiquer le numéro de partition et lançant 3 workbench FME de supresssion, d'intégration des données GPU dans la BD CD14 et de mise à jour des champs HTML des parcelles du cadastre.

            .. code-block:: batch

               set /p siren= " Saisir l'INSEE de la commune ou le Siren de l'EPCI entre guillemets "

               D:/apps/FME2022/fme.exe "D:/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/1_DROP_DATA.fmw" --siren %siren%

               D:/apps/FME2022/fme.exe "D:/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/2_INSERT_DATA.fmw" --siren %siren% 

               D:/apps/FME2022/fme.exe "D:/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/3_FICHE_DOC_URBA_CADASTRE.fmw" --siren %siren% 

               pause

Le fichier batch se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/insertion_new_com_epci.bat>`_


3.2 - FME :Import de l'emprise et supression des données
-------------------------------------------------------

Le premier worbench FME supprime les données GPU de la base sur le périmtre des nouvelles données importées.


Le workbench FME se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/1_DROP_DATA.fmw>`_


* Récupération du code siren EPCI ou insee commune entré dans le batch et ajout des potentiels suffixes (code optionnel secteur)

.. image:: ../images/Cadastre/20_partition_maj_.png
   :scale: 50


* Interrogation de l'API avec code partition pour récupérer l'emprise

.. image:: ../images/Cadastre/21_emprise_maj_.png
   :scale: 50

*Paramètres interrogation API* :

Intérrogation de l'API avec les DU_partition précédemment créés

URL : https://apicarto.ign.fr/api/gpu/document?partition=DU_@Value(siren)

HTPP method : GET

response body : Attribute

* Interrogation de l'API avec code partition pour récupérer l'emprise

.. image:: ../images/Cadastre/21_emprise_maj_.png
   :scale: 50


* Filtrer les données à partir de la réponse JSON : Expression régulière conservant le chiffre après 'totalFeatures' et conservation des lignes dont la valeur est différente de 0.

.. image:: ../images/Cadastre/14_numb_feature_filter_doc_urba.png
   :scale: 50

* Extraction des données du JSON : exposer les attributs et la géométrie

.. image:: ../images/Cadastre/15_expose_attributes_doc_urba.png
   :scale: 50

* Retraitement des données : supression des prefixes de champs et reprojection de la géométrie (de 4326 à 2154)

.. image:: ../images/Cadastre/16_reprojection_doc_urba.png
   :scale: 50

* Insertion des données dans la table historique import données et lancemnt d'une requête SQL suprimant les données GPU dont le DU_ ets égal au DU_ de leur emprise intersectent le centroid de la nouvelle emprise

.. image:: ../images/Cadastre/22_supression_partition_.png
   :scale: 50


*Exemple SQL de supression de zonages PLU*

         .. code-block:: sql

               delete 
               from ref_urbanisme.gpu_api_zonages g 
               where g.partition =  (
                  select b.partition 
                  from ref_urbanisme.historique_imports_du a
                  left join ref_urbanisme.gpu_api_emprise b on st_intersects(b.geom, st_pointonsurface(a.geom))
               where a.date_import = now()::date and a.partition like 'DU_$(siren)%'
               group by b.partition);




3.3 - FME : Import des données en fonction de l'emprise
-------------------------------------------------------

Le second worbench FME insert les nouvelles données GPU au niveau du code partition DU_ entré dans le batch sur le modèle décrit dans la partie 1.

Le workbench FME se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/2_INSERT_DATA.fmw>`_


3.4 - FME/PostgreSQL,GIS : Mise à jour des champs html GPU du cadastre
----------------------------------------------------------------------


Le dernier worbench FME lance une fonction méttant les champs HTML du cadastre au niveau du nouveau DU_ partition éntré dans le batch.

Le workbench FME se trouve `ici <file:////apw65/_FME/DOC_URBA/api_gpu2postgis/Commune_epci/3_FICHE_DOC_URBA_CADASTRE.fmw">`_

Ce workbench fonctionne comme le premier workbench récupérant l'emprise, mais avec une dernière requête qui corrige les géométries invalides des documents GPU et qui lance une fonction postgresql de mise à jour des champs HTML de la table parcelle_info du cadastre.

         .. code-block:: sql

               update ref_urbanisme.gpu_api_zonages set geom = ST_MakeValid(geom) where gpu_api_zonages.partition = @Value(partition);

               update ref_urbanisme.gpu_api_secteur_cc set geom = ST_MakeValid(geom) where gpu_api_secteur_cc.partition = @Value(partition);

               update ref_urbanisme.gpu_api_prescription_surf set geom = ST_MakeValid(geom) where gpu_api_prescription_surf.partition = @Value(partition);

               update ref_urbanisme.gpu_api_prescription_lin set geom = ST_MakeValid(geom) where gpu_api_prescription_lin.partition = @Value(partition);

               update ref_urbanisme.gpu_api_info_prescription_surf set geom = ST_MakeValid(geom) where gpu_api_info_prescription_surf.partition = @Value(partition);
               update ref_urbanisme.gpu_api_info_prescription_lin set geom = ST_MakeValid(geom) where gpu_api_info_prescription_lin.partition = @Value(partition);

               select ref_urbanisme.fiches_parcelles_lizmap(@Value(partition));


Cette dernière fonction fonctionne comme décrit en partie 2, mais uniquement pour les parcelles concernées par les nouveaux documents insérés (au niveau du nouveau DU_ ).




III- Onglet Filiation parcellaire 
*********************************

Les fichiers départementaux des documents de filiation informatisés (DFI) des parcelles permettent de consulter l'historique des parcelles cadastrales.

Ce fichier recense les modifications parcellaires réalisées depuis l'informatisation de leur procédure de mise à jour qui, selon les départements, est intervenue entre les années 1980 à 1990. L'origine des différentes mises à jour (documents d'arpentage, croquis de conservation, remaniement...) ainsi que leurs dates sont renseignées.

Ce fichier sont disponibles sur le site `datagouv.fr <https://www.data.gouv.fr/fr/datasets/documents-de-filiation-informatises-dfi-des-parcelles/>`_

Le fichier est au format txt. Le point-virgule est le caractère séparateur. La taille des champs est fixe.

Chaque lot d’analyse d’un même document de filiation fait l’objet de deux lignes successives :

* celle de type 1 pour toutes ses parcelles mères (il peut n’y en avoir aucune dans
le cas d’extraction du domaine non cadastré) ;

* celle de type 2 pour toutes ses parcelles filles (il peut n’y en avoir aucune dans le
cas de passage au domaine public).

A partir de ce fichier, le pôle SIG du Département du Calvados, propose de consulter la généalogie d'une parcelle.


.. image:: ../images/Cadastre/23_dfi_cadastre.gif
   :scale: 50

.. image:: ../images/Cadastre/schema_dfi_cadastre.png
   :scale: 50

1- Traitement et import FME des données 
=========================================

Le fichier DFI est difficilement exploitable en brut.

Le fichier sépare chaque valeur par un ; .

Le nombre de valeurs de parcelles est variable, ce qui implique un nombre de champ variable.



Le workbench FME se trouve `ici <file:////apw65/_FME/CADASTRE/filiation_parcelles_dfi_txt2postgres.fmw">`_

1.1 Regexp : correction du fichier
------------------------------------

Dans un premier temps, afin de pouvoir correcetement lire le fichier, à l'aide d'expression régulière et de l'ETL FME
, les données parcelles sont réunies en listes dans un seul champs.

* Ramplacer XX par !

140;001;000;0000299;1;19900305;XXXXXREDACTEURDUDOCUMENTXXXX **!** 00001;2;A0297; A0298;

* Remplacer les 6 première ; par des ! à partir de !

         .. code-block:: sql
            
               (?=(;[^;]{0,}){1,6}\!);

140!001!000!0000299!1!19900305!XXXXXREDACTEURDUDOCUMENTXXXX **!** 00001;2;A0297; A0298;

* Remplacer les ;1; par !1!{

140!001!000!0000299!1!19900305!XXXXXREDACTEURDUDOCUMENTXXXX!00001 **!1!{** A0297; A0298;


* Remplacer les ;2; par !2!{

140!001!000!0000299!1!19900305!XXXXXREDACTEURDUDOCUMENTXXXX!00001 **!2!{** A0297; A0298;

* Remplacer les ; restants en fin de ligne par des ,

140!001!000!0000299!1!19900305!XXXXXREDACTEURDUDOCUMENTXXXX!00001 **!2!{** A0297, A0298,


* Remplacer les! précédements créés pour réatblir le séparateur ; pour les champs

140;001;000;0000299;1;19900305;XXXXXREDACTEURDUDOCUMENTXXXX;00001;2;{A0297, A0298,

* On ajoute ensuite une ligne avec la liste des nom de champs

.. image:: ../images/Cadastre/23_add_name_fiel_.png
   :scale: 50

1.2 Lecture du CSV
------------------

Après écrture du fichier, on lit le fichier CSV en exposant la liste des attributs souhaités.

.. image:: ../images/Cadastre/24_expose_attribute.png
   :scale: 50

1.3 Remplacer : seconde correction du fichier
-----------------------------------------

On effectue une dernière correction du fichier avant intégration dans la base de données.

.. image:: ../images/Cadastre/25_retraitement_dfi.png
   :scale: 50

* Ajout des prefixes 0 aux sections et codecom en fonction de la longeur des variables (un 0 si length() = 2,  deux 0 si length() =1 .


* ajout d'un ! en fin de listes de parcelles

{A0297, A0298, **!**

* remplacer les valeurs ,! par } dans le champs list parcelle pour fermer proprement les listes

{A0297, A0298 **}**

* remplacer les valeurs {! par vide pour valeurs vides si pas de parcelle dans la lsite


* suprimmer les espaces dans le champs list parcelle

2- Champ HTML historique déroulant 
==========================================

L'objectif est ici de pouvoir consulter l'historique des filiations à l'échelle de la parcelle.

L'utilisateur peut en cliquant sur une parcelle, consulter la généalogie de sa parcelle, connaitre sa/ses parcelles méres (antérieur), ses parcelles soeurs (issues de la/les  mêmes parcelles mères) et connaitre la nature de la filiation.

Pour cela on utilise une fonction postgresql/gis pour alimenter la table parcelle_info du cadastre et une mise en forme du formulaire QGIS en HTML pour publication sur le portail cartographique Lizmap.

2.1 - Fonction postgresql/gis
-----------------------------


* On créé le champ contenant l'html des déroulants détaillant les filiations du plus récent au plus ancien

        .. code-block:: sql

            alter table cadastre.parcelle_info add column tab_filiation text;



On lance ensuite une fonction postgrresql/gis dont le code SQL se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/foncier/dfi/fonction_filiation_parcelles_cadastre.sql>`_

* Dans un premier temps, la fonction met en place une table temporaire (que l'on va indéxer) regroupant ligne par ligne les infos dfi, la nature détaillée des dfi, la liste des parcelles mère et la liste des parcelle filles associées (filiation)

        .. code-block:: sql

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


* Création d'une table temporaire listant les premières filiations liées aux parcelles actuelles du cadastre

        .. code-block:: sql

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

* Création d'une table temporaire rapprochant les parcelles filles aux listes de parcelles mères (récursive)


        .. code-block:: sql

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




* ... Suite de la table : création du bloc déroulant HTML avec historique des filiations de parcelles dans un champs txt avec num parcelle associé


        .. code-block:: sql

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
               ('<tr>
                  <td><label for="row'||fid || '"></label>' ||  date_valid::text::date || 
                  '</td>
                  <td>'|| nature_dfi || '</td>
               </tr><tr>
                  <td colspan="6">
                  <input id="row'||fid||'" type="checkbox">
                  <table>
                     <tr>
                        <th>Nouvelle(s) parcelle(s)</th>
                        <th>Parcelle(s) soeur(s)</th>
                        <td>Ancienne(s) parcelle(s)</td>
                  </tr>
                     <tr>
                        <th>'||translate(parcelles_filles::text, '{}', '')||'</th>
                        <th>'||translate(parcelles_soeurs::text, '{}', '')||'</th>
                        <td>'||translate(parcelles_meres::text, '{}', '')||'</td>
                     </tr>
                  </table>'
                  ) , '</td>
               </tr>'
                  order by num_filiation asc),'</tbody>
            </table>') as tab_filiation, concat('140',code_com, pref_section, id_filiation) as num_parcelle -- creation du num parcelle : cod dep + codcom + pref_section + num_parcelle cadastre initial
               from result a
               group by code_com, pref_section, id_filiation; -- grouper par parcelle, pref section et num parcelle cadastre initial


* Mise à jour des champs  HTML de la table parcelle info grace aux identifiants parcelles de la tables précédement crééechelle


2.2 - Paramètrage Qgis/plugin Lizmap
------------------------------------

* Mise à jour de l'info bulle HTML dans les propriété de la couche QGIS


.. image:: ../images/Cadastre/18_info_bulle_html.png
   :scale: 50


Le code HTML (Onglet Filiations + partie tab_filiation) se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/html/popup_cadastre.html>`_



2.3 - Rendu lizmap
------------------

* Mise à jour du CSS dans le panneau de configuration Lizmap

Le code CSS se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/css/style_dfi_cadastre.css>`_


.. image:: ../images/Cadastre/19_config_css.png
   :scale: 50

IV- Onglet Mutations immobilières
*********************************

Le jeu de données « Demandes de valeurs foncières », publié et produit par la direction générale des finances publiques, permet de connaître les transactions immobilières intervenues au cours des cinq dernières années. Les données contenues sont issues des actes notariés et des informations cadastrales.

Il es disponible sur le site `datagouv.fr <https://www.data.gouv.fr/fr/datasets/5c4ae55a634f4117716d5656/>`_

Les fichiers correspondant chacun à un millésime sont mis à disposition au format.txt. sur cinq ans.

Les fichiers mis à disposition font l’objet d’une mise à jour **semestrielle, en avril et en octobre**.

A partir de ce fichier, le pôle SIG du Département du Calvados, propose de consulter l'historique des mutations immobilières et leurs valeures foncières à l'échelle d'une parcelle.

.. image:: ../images/Cadastre/mutation_immo.gif
   :scale: 50

.. image:: ../images/Cadastre/schema_dvf_cadastre.png
   :scale: 50



1- Traitement et import FME des données 
=========================================

Un workbench FME récupère les données de valeurs foncières et les intègre dans la base de données du CD14.

Le workbench FME se trouve `ici <file:////apw65/_FME/CADASTRE/valeur_fonciere_txt2postgres.fmw>`_


2- Champ HTML historique déroulant 
==========================================

L'objectif est ici de pouvoir consulter l'historique des mutations immobilières et les valeurs foncières à l'échelle de la parcelle.

L'utilisateur peut en cliquant sur une parcelle, consulter les différentes mutations immobilières opérées sur la parcelle ces 5 dernières années.

Pour cela on utilise une fonction postgresql/gis pour alimenter la table parcelle_info du cadastre et une mise en forme du formulaire QGIS en HTML pour publication sur le portail cartographique Lizmap.

2.1 - Fonction postgresql/gis
-----------------------------


* On créé le champ contenant l'html des déroulants détaillant les filiations du plus récent au plus ancien

        .. code-block:: sql

            ALTER TABLE cadastre.parcelle_info
            ADD column deroulant_dvf varchar;



On lance ensuite une fonction postgrresql/gis dont le code SQL se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/foncier/dvf/fonction_dvf.sql>`_

* Dans un premier temps, on séléctionne des valeurs de champs distincts pour éviter les doublons

        .. code-block:: sql

            select  distinct on (
                        a.code_ch,
                        a.ref_doct,
                        a.no_disposition,...


* On joint les natures de cultures et cultures spéciales (créer une table à partir de la notice descriptive disponible sur le site `datagouv.fr <https://www.data.gouv.fr/fr/datasets/5c4ae55a634f4117716d5656/>`_ , ainsi que les numéros de parcelles du cadastre.

        .. code-block:: sql

            row_number() over() as id, -- creation d'un id unique
               b.geo_parcelle, b.geom, date_mutation, nature_mutation, valeur_fonciere , concat(no_voie, ' ', type_de_voie,' ', a.voie,' ', code_postal) as adresse ,
               type_local, nb_piece_princ,  surf_reelle_bati, surf_terrain,
                  c.libelle as nature_culture, -- ajout de la nature culture 
                  d.libelle as nature_culture_speciale -- ajout de la nature culture spéciale 
            from cadastre.parcelle_info b --- jointure de la tbale parcelle_info 
            inner join  ref_foncier.valeurs_foncieres a
            on b.geo_parcelle = concat(concat(code_dep, '0'), code_com, pref_section, section, no_plan) 
            left join ref_foncier.valeurs_foncieres_cultures c on a.nature_culture = c.code 
            left join ref_foncier.valeurs_foncieres_cultures_speciales d on a.nature_culture_speciale = d.code)


* Creation du champ html : bloc html + info mutation, decomposition type local + nature culture

        .. code-block:: sql

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


* Aggreger les déroulants par parcelle et les ordonner par date de mutation

        .. code-block:: sql

            select a.geo_parcelle, string_agg((deroulant_dvf), '' order by date_mutation::date DESC) as deroulant_dvf
            from group_parcelle a
            group by a.geo_parcelle;


* indexation de la tbale, vider et updater le champs deroulant html de cadastre.parcelle_info au niveau du numero de parcelle

        .. code-block:: sql
         
            CREATE INDEX index_temp_dvf  ON temp_dvf  USING btree (geo_parcelle);

            update cadastre.parcelle_info set deroulant_dvf = null;

            update cadastre.parcelle_info set deroulant_dvf = b.deroulant_dvf from temp_dvf b where b.geo_parcelle = parcelle_info.geo_parcelle;

   

2.2 - Paramètrage Qgis/plugin Lizmap
------------------------------------


* Mise à jour de l'info bulle HTML dans les propriété de la couche QGIS


.. image:: ../images/Cadastre/18_info_bulle_html.png
   :scale: 50


Le code HTML (onglet mutation immobilière + partie deroulant_dvf) se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/html/popup_cadastre.html>`_



2.3 - Rendu lizmap
------------------

* Mise à jour du CSS dans le panneau de configuration Lizmap

Le code CSS se trouve `ici <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/9_lizmap/css/style_dvf_cadastre.css>`_


.. image:: ../images/Cadastre/19_config_css.png
   :scale: 50
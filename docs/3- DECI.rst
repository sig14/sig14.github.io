DECI
#########

I- Périmètres des Bornes incendies
******************************
.. image:: ../images/DECI/Intro.png
   :width: 880

Dans le cadre du partenariat entre le CD14 et les Services Départementaux d'Incendie et de Secours (SDIS), une application a été dévellopée à destination des communes et partenaires afin de répertorier les points d'eau incendie (**PEI**) du Département.

La mise à disposition de ces sources d'eau relève de la responsabilité du maire.

Ainsi, où que les pompiers interviennent en zone habitée, ils devraient disposer d’un accès à l’eau à moins de **200 mètres** et d'une distance maximale de **400 mètres** entre les points d'eaux incendie.

Ainsi, une réfléxion a été menée pour calculer automatiquement ces 2 périmètres le long des routes à chaque création de borne incendie.

L'approche developpée consiste donc à éxploiter la localisation des **PEI**, créer des linéaires d'isodistances et les périmètres de **200** et **400** mètres via la route.


.. image:: ../images/DECI/schema_part_I.png
   :width: 580

1- Référentiels de données
========================

1.1 BD Topo tronçons de routes
------------------------------

**Caractéristiques** :
*	Source : IGN
*	Réseau routier 
*	Format : vecteurs Multilinestring

1.2 Points Eau incendie DECI
------------------------------

**Caractéristiques** :
-	Source : SDIS
-	Poteaux ou des bouches d'incendie, raccordés au réseau d'eau potable
-	Format : vecteur point 


2- Création du linéaire routiers de référence
========================

La première étape consiste à créer une table miroir de données routes, en y indéxant les points de départ et d'arrrivée de chaque tronçon.

Le bornage de ces tronçon permettra par la suite de fixer le parcours de réseau et de mesurer les distances parcourues.

Le code sql de la fonction se trouve ici : `Fonction référentiel bornage routes DECI <file://K:/Pole_SIG/Data/03_TRAITEMENTS_SIG/1_postgres/sdis/fonction_network_deci.sql>`_ 

2.1 Isoler les ségments de route
---------------------------------------------

Dumper la géométrie des routes pour obtenir les segments de routes.

      .. code-block:: sql
               
	               create table sdis.route_deci_segments as
	               select
	               row_number() over () as id,
	               a.id as oid,
	               dump.geom
	               from
	               sdis."2d_deci_bdtopo" a,
	               st_dump(geom) as dump
	 
	                ; 

2.2 Indéxer les startpoints des segments
---------------------------------------------

* On boucle sur les géométrie de segement pour alimenter un champs n1.

* On débute par la valeur 1 et on ajoute 1 à chaque nouvelle géometrie de startpoint dans une liste (indexe).

* On garde également en mémoire la géométrie dans une liste (points). 

* A chaque création d'entité, on vérifie la position du startpoint dans la liste (points).
  Si aucune position dans la liste on ajoute une valeur n1 (n+n1).
  Sinon, on donne la valeur de n de la liste (indexe) selon la postion du startpoint dans la liste (points) au champs n1.


         .. code-block:: sql
                        
                        for rec in select * from sdis.route_deci_segments loop
               -- Première extrémité
                        pt = st_startpoint(rec.geom);
               -- On cherche si ce point a déjà un numéro de noeud
                        pos := array_position(points, pt);
                        if pos is NULL then -- le point n'est pas encore indexé
               -- on crée un numéro et on l'insère
                              update sdis.route_deci_segments set n1 = n where id = rec.id;
                              points = array_append(points, pt);
                              indexe = array_append(indexe, n);
                              n := n + 1;
                         else
                -- on prend le numéro existant
                              pos := array_position(points, pt);
                              update sdis.route_deci_segments set n1 = indexe[pos] where id = rec.id;
                         end if;

.. image:: ../images/DECI/1_start_point.png
   :width: 480



2.3 Indéxer les endpoints des segments
---------------------------------------------

* On applique la même méthode sur les endpoints


         .. code-block:: sql
                        
                       
		   -- Seconde extrémité
		         pt = st_endpoint(rec.geom);
		         pos := array_position(points, pt);
		   -- On cherche si ce point a déjà un numéro de noeud
		         if pos is NULL then -- le point n'est pas encore indexé
			-- on crée un numéro et on l'insère
			         update sdis.route_deci_segments set n2 = n where id = rec.id;
			         points = array_append(points, pt);
			         indexe = array_append(indexe, n);
			         n := n + 1;
		         else
			-- on prend le numéro existant
			         pos := array_position(points, pt);
			         update sdis.route_deci_segments set n2 = indexe[pos] where id = rec.id;
		         end if;
	         end loop;

.. image:: ../images/DECI/2_end_point.png
   :width: 480



3- Automatisation de la création des pèrimètres
================================================

La seconde étape consiste à la mise en place d'une fonction déclenchée par un trigger, pour calcul automatique des périmètres 200 et 400 mètres
à partir de la projection sur le référentiel routier du PEI nouvellement créé. 

Le code sql de la fonction se trouve ici : `Fonction calcul automatique perimètre PEI <file://K:/Pole_SIG/Data/03_TRAITEMENTS_SIG/1_postgres/sdis/trigger_perimetre_bornes_incendie.sql>`_ 


3.1 Restreindre la zone de calcul
---------------------------------------------

Afin d'optimiser le temps de calcul, on selectionne uniquement les routes à 500 mètres du PEI créé.

            .. code-block:: sql
                                    
                                 
               CREATE UNLOGGED TABLE IF NOT EXISTS route_deci --- création d'une table temporaire qui sélectionne les segments_deci dans un buffer de 500 mètre autour du nouveau point créé
               as 
                  select r.* 
                  from sdis.route_deci_segments r
                  where st_intersects(r.geom, st_buffer(NEW.geom, 500, 'quad_segs=8')) ;

               CREATE  INDEX route_deci_idx ON route_deci (id);---création d'un indexe sur l'id de la table


3.2 Récursive : parcourir le linéaire à 400 mètres
--------------------------------------------------

Nous utilserons ici l'expression récursive de postgresql.

* On localise d'abords le segment le plus proche à moins de 40 mètres du nouveau PEI créé.
* On identifie la fraction du segment au niveau du point projeté (ST_LineLocatePoint)
* On calcul la longueur de la fraction du segment (longeur segment X fraction)

            .. code-block:: sql

                     select r.*, st_length(r.geom) * ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom)) as longueur_depart, ---fraction de la longeur du segment de départ au niveau du point projeté sur le segment le plus proche
                     ST_LineLocatePoint(r.geom, st_closestpoint(r.geom, NEW.geom))  as fraction --- fraction du segment de départ au niveau du point projeté sur le segment le plus proche
                     from route_deci r
                     where st_intersects(st_buffer(r.geom, 40),NEW.geom) -- segment de départ à 40 mètre du point créé
                     order by st_distance (NEW.geom, r.geom) limit 1-- On garde seulement un segment (le plus proche)

.. image:: ../images/DECI/3_calcul_dist.png
   :width: 480




* On créé ensuite les géométries correspondantes aux deux fractions du segment


            .. code-block:: sql

                     n1_distance as (
			-- on récupère pour le premier segement, juste une fraction (car la borne n'est pas située
			-- pile à une extrémité
			               select longueur_depart  as dist_n1, st_linesubstring(p.geom, 0, fraction) as n1_geom -- ici on stocke la fraction de geom à parcourir
			               from premier_troncon p
		                              ),
		               n2_distance as (
			-- idem pour le deuxième noeud
			               select st_length(geom) - longueur_depart as dist_n2, st_linesubstring(p.geom, fraction, 1) as n2_geom -- On calcul la longeur 2e fraction du segement en soustrayant la longeur de la 1ere fraction à la longeur du segment . On stocke également la geom à parcourir
			               from premier_troncon p
		                              )


.. image:: ../images/DECI/4_geom_fractions.png
   :width: 480


* On prépare ensuite la requête initiale de la récursive. Union des deux fractions de segment :
         - On récupére l'identifiant du segment
         - La valeur de n1 pour la première fraction de segment (startpoint)
         - La valeur de n2 pour la deuxième fraction de segment (endpoint) 
         - On attribut la valeur null pour le n2 du premier segment et le n1 du deuxième segment. 
         - On récupère la longueur des fractions de segment (dist_n1 et dist_n2)
         - On stocke l'dentifiant dans une liste (array)
         - On récupère la géométrie des fractions de segment (n1_geom et n2_geom)

            .. code-block:: sql

                     n1_distance as (
                           select id,   n1 , null as n2 , dist_n1 as meters, ARRAY[p.id] as path_id,  n1_geom as geom_initiale -- on récupérer la valeur du noeud 1, null pour noeud 2 pour ne pas associer des segment du mauvais coté dans la recursive. On stocke également l'id (array)
		                     from n1_distance, premier_troncon p 
		                  union -- pour partir dans les deux direction (noeud 1 et noeud 2)
		                     select id,  null as n1, n2 ,  dist_n2 as meters, ARRAY[p.id] as path_id, n2_geom as geom_initiale-- idem que pour la première direction. null au n1 pour ne pas associer des segments de ce coté.
		                     from n2_distance, premier_troncon p 

.. image:: ../images/DECI/5_requête_initiale.png
   :width: 680


* On sélectionne les segments de routes qui ont les mêmes noeuds que les segments de la requête initiale:
         - On séléctionne les segments de routes DECI dont le n2 ou le n1 correspond au n2 ou n1 de la requête initiale
         - On récupère leur identifiant 
         - On récupère leur n1
         - On récupère la geom de la fraction de segment associée
         - On récupère la liste d'identifiants gardée en mémoire de la fraction de segment associée

            .. code-block:: sql

              ng as ( select r.id,
					 r.n1
					 as _n1,
					 r.n2  as _n2,
					 sg.meters, -- distance cumulée
					 sg.path_id,
					 r.geom, -- geométrie du segment en cours de parcours
					 sg.geom_initiale -- géométrie de départ (fraction du premie rsegement, en fonction de la projection de la borne dessus)
				    from search_graph sg, route_deci r
				    where (
					         sg._n2 = r.n1 or sg._n1 = r.n2  -- on cherche tout n1 ou n2 qui correspond à la fin de notre segment courant 
					         or sg._n1 = r.n1 or sg._n2 = r.n2))


* On ajoute une UNION entre ces résultats et la requête initiale pour la récursivité:
         - On séléctionne les id, les noeuds et les geometries de segments de routes rapprochés
         - On aditionne la longueur de la geometrie rapprochée à la longueur de fraction du segment
         - On stocke l'id du segment rapproché dans la liste d'identifiants gardé en mémoire

         .. code-block:: sql

            select distinct on (ng.id)
				ng.id,
				ng._n1, 
				ng._n2, 
				ng.meters + st_length(ng.geom),-- on ajoute la longeur du nouveau segment associé à la distance cumulée
				ng.path_id || ng.id,
				ng.geom_initiale
			   from ng

* On termine la recursive :
         - On conditionne l'ajout de segments (arrête de la recursive) à une distance cumulée de 360 mètres
         - On conditionne l'ajout de segments (arrête de la recursive) au fait que son id ne soit pas dans la liste d'identifiants gardé en mémoire
         - On ferme la recursive, on la lance
         - On récupère au passge les géométrie de segments DECI qui ont le même id que l'ensemble des segments rapprochés.

         .. code-block:: sql

            ng	
                  where 
                     ng.meters < 360 and  not (ng.id = ANY(ng.path_id)) -- filtre sur la distance max +secu en cas de maillage, pour éviter de boucler sur les mêmes segments(on ne reprend pas de segemnt qui a été gardé en mémoire)
            )  
            select sg.id, sg._n1, sg._n2, sg.meters,  r.geom, sg.geom_initiale
            from search_graph sg
            join route_deci r on r.id = sg.id
       

.. image:: ../images/DECI/6_recursive.png
   :width: 880


3.3 Fractionner les segments trop longs
----------------------------------------

* Pour la suite du traitement, on conserve les résultats dont la longueur cumulée est égale ou inférieure à 360 mètres.
         .. code-block:: sql

            troncons_valides as (
	         select * from resultat where meters <= 360
                                 ),

* On sélectionne ensuite résultats dont la longueur cumulée est supérieure à 360 mètres, on joint les routes DECI en n1 ou n2.
   
**si le segment joint en n_2 n'est pas un segment initial (pas de noeuds null)**
         
               .. code-block:: sql

                  st_linesubstring(t.geom, 0, (st_length(t.geom)-(t.meters - 360)) / st_length(t.geom))

.. image:: ../images/DECI/7_fraction_cas_1.png
   :width: 880

**si le segment joint en n_2 n'est pas un segment initial  (pas de noeuds null)**

            .. code-block:: sql

                  st_linesubstring(st_reverse(t.geom), 0,   (st_length(t.geom) - (t.meters - 360)) / st_length(t.geom))

.. image:: ../images/DECI/8_fraction_cas_2.png
   :width: 880

**si le segment est le segment initial fraction 1 (noeud 2 est null)**

               .. code-block:: sql

                  st_linesubstring(st_reverse(t.geom_initiale), 0,   (st_length(t.geom_initiale) - (t.meters - 360)) / st_length(t.geom_initiale)) 

.. image:: ../images/DECI/9_fraction_cas_3.png
   :width: 380

**si le segment est le segment initial fraction 2 (noeud 1 est null)**

               .. code-block:: sql

                  st_linesubstring(t.geom_initiale, 0, (st_length(t.geom_initiale)-(t.meters - 360)) / st_length(t.geom_initiale))

.. image:: ../images/DECI/10_fraction_cas_4.png
   :width: 480


* Pour finir, on insére dans la table de données à 400 mètre l'UNION des données suivantes :
            - Buffer de 40 mètres de la géométrie des résultats dont la longueur cumulée est égale ou inférieure à 360 mètres.
            - Buffer de 40 mètres de la géométrie des fractions de segment dont la longueur est égale ou inférieure à 360 mètres.
            - Buffer de 40 mètres de la géométrie des fractions de segment dont la longueur était supérieure à 360 mètres.
         
         .. code-block:: sql
            
            final as (
	                  select id ,  st_buffer(geom_initiale, 40) as geom  from troncons_valides -- on récupere le buffer 40m de la geom des fraction de segments initiale 
		               union
		               select id ,  st_buffer(geom, 40) as geom  from troncons_valides where st_length(geom) <= 360 -- on récupere le buffer 40m  de la geom des segments qui font moins de 400 mètres
		               union
	                  select id ,  st_buffer(geom, 40) as geom   from fractions -- on récupère le buffer 40m des geom des fractions de segments qui dépassent 400 mètres
                     )
                     select ST_Multi(st_union(geom)) into geom_buffer_400 -- on unie les geom buffer en MULTI* geometry collection
                     from final;



II- Rapprochement adresse BDtopo IGN
************************************

Afin de faciliter le travail d'intervention des secours, le pôle SIg à répondu à une demande de rapprochement des adresses BAL dont dispose le Département avec les tronçons de voies IGN.

L'objectif étant de déterminer pour chaque tronçon de BDtopo :
* Le  nom de la voie
* Le premier numéro à droite
* Le premier numéro à gauche
* Le dernier numéro à droite
* Le dernier numéro à gauche

.. image:: ../images/DECI/schema_part_II.png
   :width: 580



1- Rapprochements des voies adresses avec les tronçons routes
=============================================================

Cette première étape vise à associer pour chaque voie tracée et enregistrée par les communes dans la base de données adresse du Département un tronçon BDtopo IGN.

Pour cela nous faisons appel à la fonction *adresse.id_voie_bdtopo_sdis()* qui se trouve ici : `fonction sql <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/sdis/raprochement_adresse_tronçon_sdis/fonction_rapproche_adresses_voie.sql>`_

1.1 Segmenter les tronçons Bdtopo
---------------------------------

Dans un premier temps, la fonction créé une table temporaire des noeuds de BDtopo que l'on va pouvoir indéxer pour accélerer le traitement :

         **1 - Séléction des périmètres communes bdtopo correspondant aux périmètres des communes adresses publiées** (pour circonscrire les tronçons sur les bons périmètres)

            .. code-block:: sql

                          with commune_pub as (
                           select st_buffer(bc.geom, 100) as geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc -- buffer de 100 mètres des communes ign du au décalage ign osm
                                 where a.insee_code = bc.insee_com
                           ),   
                        troncon_com_pub as (--- selection des tronçon sur les communes bdtopo sléctionnées plus haut 
                           select b.* from ign.bdtopo_troncon_de_route b, commune_pub
                           where st_intersects(b.geom,commune_pub.geom)
                           ) 

         **2 - Création de noeuds bdtopo** : segemntation des tronçons tous les 10 mètres, transformation des segments en multipoints, dump pour avoir des géométries uniques.



         .. code-block:: sql

                    select ROW_NUMBER() OVER() as id_pt, c.id,  
                    (ST_Dump(ST_AsMultiPoint(st_segmentize(ST_Force2D(c.geom) ,10))::geometry(MULTIPOINT,2154))).geom as geom --- création de noeuds multipoints bdtopo à partir de la segmentisation des tronçons(3D)
                    from troncon_com_pub  c;

                    CREATE INDEX node_bd_topo_geom --- création d'un indexe sur la geom de la table
                    ON node_bd_topo USING gist (geom)
                    TABLESPACE pg_default;


.. image:: ../images/DECI/II_1_1_segemnt_bdtopo.png
   :width: 380


1.2 Segmenter les tronçons Bdtopo
---------------------------------

Dans un second temps on rapproche les tronçon dont la majorité des noeuds se trouve sur une voie adresse.

         **1 - Buffer des voies adresses**

                  .. code-block:: sql

                           with commune_pub as ( ------ selection des communes bd_topo correspondant aux communes publiées adresse
                            select st_buffer(bc.geom, 100) as geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc -- buffer de 100 mètres des communes ign du au décalage ign osm
					                  where a.insee_code = bc.insee_com
                            ),
                          voie as ( ------ selection des voies adresses bufferisées sur les communes publiées adresse
                            select v.id_voie, ST_Buffer(ST_Buffer(v.geom, 10, 'endcap=flat join=round'), -5, 'endcap=flat join=round') as geom -- on aura besoin du buffer pour collecter les noeuds (on créé un buffer de 10 mètres et on raccourci les bords de 5 mètres)
                            from adresse.voie v, commune_pub a
                            where st_intersects(a.geom,v.geom)
                            ),

         **2 - Compter le nombre de noeuds par tronçon de route**

                  .. code-block:: sql

                          pt_count_troncon as (------ Compte le nombre de noeuds par tronçon
                            select id, count(id_pt) as ct 
                            from node_bd_topo 
                            group by id),

         **4 - Rapprocher les noeuds bdtopo qui intersectent le buffer des voies adresses**


                  .. code-block:: sql

                          f as (------ rapprochement des id_voies et des noeuds à l'intérieur du buffer des voies précédemment créé
                            select b.id_pt, b.id, voie.id_voie 
                            from node_bd_topo  b
                            inner join voie
                            ON ST_Within(b.geom, voie.geom)
                            ),

         **5 - Compter le nombre de noeuds bdtopo par voie adresse**

                  .. code-block:: sql

                          l as ( ------ Compte le nombre de noeud pour chaque id_voie
                            select f.id, f.id_voie, count(f.id_voie) as ct 
                            from f
                            group by f.id, f.id_voie
                            ),

         **6 - Rapprochement des tronçons à une voie adresse si la majorité de ses noeuds sont compris dans son buffer** 

                  .. code-block:: sql

                          troncon_node as ( ------ Séléctionne les id_tronçon dont la majorité des noeuds intersecte le buffer des voies 
                            select distinct on (l.id) l.id, l.id_voie, l.ct 
                            from l , pt_count_troncon
                            where pt_count_troncon.id = l.id and (pt_count_troncon.ct/l.ct)<= 2 -- division du total des noeuds tronçon/le nombre de noeuds pour un même id_voie, si moins de 2, on conserve l'id-tronçon et l'id_voie associé
                            order by l.id, l.ct DESC)

                           select troncon_node.id, troncon_node.id_voie, k.geom ------ Rapprochement des géométrie de la bd_topo grâce à l'id tronçon des noeuds précédemment sélectionnés
                           from  troncon_node, ign.bdtopo_troncon_de_route k 
                           where k.id = troncon_node.id ;




.. image:: ../images/DECI/II_1_2_buffer_voie_adresse.png
   :width: 380

2- Raprochement des adresses
============================

Cette seconde étape vise à associer pour chaque tronçon, les points adresses dépendant de la voie qui lui a été attribué.

Pour cela nous créons une vue materialisée *adresse.vm_sdis_pts_adresse_bdtopo* dont le code se trouve ici : `vm sql <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/sdis/raprochement_adresse_tronçon_sdis/fonction_rapproche_adresses_point.sql>`_


2.1 Projeter les points adresses sur les tronçons
-----------------------------------------------

On projete le point sur le tronçon le plus prohce associé à la voie dont dépend le point adresse.

         **1 - Projection des points adresse sur les tronçon ayant le même id_voie**

             .. code-block:: sql

               with bdtopo_idvoie as (
                     select * from  adresse.id_voie_bdtopo_sdis() --- Fonction donnant la séléction des id_tronçons bdtopo et des id_voies adresse
                  ),
                  distance_troncon as ( 
                     select p.id_point, troncon.id_troncon, troncon.id_voie, troncon.geom, p.numero, p.suffixe, p.geom as geom_pt_adresse,
                     ST_LineInterpolatePoint(ST_LineMerge(troncon.geom), ST_LineLocatePoint(ST_AsEWKT(ST_LineMerge(troncon.geom)), ST_AsEWKT(p.geom))) as geom_pt_proj, --- Projection des points adresses sur les tronçon ayant le même id_voie 
                     st_distance(troncon.geom, p.geom) as dist --- distance entre le point et la voie
                     FROM bdtopo_idvoie  troncon
                     inner join adresse.point_adresse p on troncon.id_voie = p.id_voie
                     inner join adresse.v_communes_publiees l  on st_intersects(p.geom,l.geom)
                  ),


         **2 - Séléction unique des id_points avec id tronçon associés dont la distance est la plus courte** : pour une voie comprenant plusieurs tronçons bdtopo on associe les points adresses aux tronçon le plus proche)


            .. code-block:: sql

               point_proj as( --- 
                  select distinct on (distance_troncon.id_point) distance_troncon.id_point, distance_troncon.id_troncon, distance_troncon.id_voie, -- selection distinct d'id_point adresse
                  distance_troncon.numero, distance_troncon.suffixe, distance_troncon.geom, geom_pt_adresse, geom_pt_proj
                  from distance_troncon
                  order by id_point, dist ASC --- ordonner de la plus petite distance à la plus grande pour que distinct sélectionne la première entité avec la plus courte distance
               ),


.. image:: ../images/DECI/II_2_1_point_proj.png
   :width: 380      

      

2.2 Determiné de quels côtés se trouve les point adresse
-----------------------------------------------------------

Pour identifier le côté du point adresse par rapport au tronçon.

         **1 - Tracer une ligne prolongées entre le point adresse et son point projeté sur le tronçon**

             .. code-block:: sql

                           line_cross as ( --- 
                  select point_proj.id_point, point_proj.id_troncon, point_proj.id_voie, point_proj.numero, point_proj.suffixe, point_proj.geom, geom_pt_adresse, geom_pt_proj, 
                  ST_MakeLine(geom_pt_adresse, ST_TRANSLATE(geom_pt_adresse, sin(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
                  + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))), cos(ST_AZIMUTH(geom_pt_adresse,geom_pt_proj)) * (ST_DISTANCE(geom_pt_adresse,geom_pt_proj)
                  + (ST_DISTANCE(geom_pt_adresse,geom_pt_proj) * (50/49))))) as geom_segment
                  from point_proj
               ), 

         **2 - Definir le coté de du point adresse par rapport au tronçon grâce au sens de croisement du segment précédemment créé**

             .. code-block:: sql 

               point_cote as (--- 
                  select line_cross.id_point, line_cross.id_troncon, line_cross.id_voie, line_cross.numero, line_cross.suffixe,  
                  case WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom)) = -1 then 'gauche'
                     WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 1 then 'droite'
                     WHEN ST_LineCrossingDirection(geom_segment, ST_LineMerge(geom) ) = 0 then 'indefini' --- Si croise ni à gauche ni à droite 
                     ELSE 'probleme' end as cote_voie,  --- croise plusieurs fois, donc problème de tracé du tronçon ou cas particulier (rare)
                  geom_segment, geom_pt_adresse, geom_pt_proj
                  from line_cross
               ),

.. image:: ../images/DECI/II_2_2_sens_croisement.png
   :width: 380      



2.3 Ne conserver que les premier et derniers points adresse
-------------------------------------------------------------

Pour identifier le côté du point adresse par rapport au tronçon.

         **1 - Séléction des tronçons sur les communes dont l'adressage est certifié/publié sur La BAN**

             .. code-block:: sql

                  commune_publ as (  ------ selection des communes bd_topo correspondant aux communes publiées adresse
                        select bc.geom from adresse.v_communes_publiees a, ign.bdtopo_commune bc
                           where a.insee_code = bc.insee_com
                     ),
                     troncon_com_pub as ( --- selection des tronçon sur les communes bdtopo sléctionnées plus haut
                        select b.* from ign.bdtopo_troncon_de_route b, commune_publ
                        where st_intersects(b.geom,commune_publ.geom)
                     ), 

         **2 - Séléction des points adresses droite/gauches les plus proches du point de fin et départ du tronçon**

            .. code-block:: sql

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


         **3 - Jointure des précdentes sélection :** tronçons rapproché (z),  geométrie tronçon ign (e) et  nom complet des voies(v)


            .. code-block:: sql

               Select z.id_troncon, z.id_voie, v.nom_complet, ------ J
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


.. image:: ../images/DECI/II_2_3_start_point_end_point.png
   :width: 380      



3- Liste des points adresses indeterminés
=========================================

On identifie ici les points adresses dont le côté n'a pu être determiné : mauvais traçé d'un tronçon, positionnement particulier du point adresse par rapport au tronçon (à l'extrémité d'un tronçon).

Pour cela nous créons une vue materialisée *adresse.vm_sdis_pts_adresse_indetermine * dont le code se trouve ici : `vm sql <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/sdis/raprochement_adresse_tronçon_sdis/vm_adresses_indeterminees.sql>`_


                   .. code-block:: sql

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




4- Voies adresses non affiliée à un tronçon 
==============================================

On identifie ici les voies adresses pour lesquelles aucun tronçon n'a pu être rapporché : pas de tronçon superposé, une trop petite partie du tronçon superposée.

Pour cela nous créons une vue materialisée *adresse.vm_troncon_no_voie_bd_topo* dont le code se trouve ici : `vm sql <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/sdis/raprochement_adresse_tronçon_sdis/vm_adresses_indeterminees.sql>`_


                  .. code-block:: sql/

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



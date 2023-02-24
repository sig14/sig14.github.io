Adressage
#########


I- Accompagnement des Communes
******************************

L'adressage est une **compétence communale** qui consiste pour une mairie à nommer les rues et numéroter les habitations. Depuis le 21 février 2022 et la promulgation de la loi relative à la différenciation, la déconcentration, la décentralisation et portant diverses mesures de simplification (`Loi 3DS <https://www.legifrance.gouv.fr/jorf/id/JORFTEXT000045197395>`_), il s'agit même d'une **obligation réglementaire**. Les communes doivent :

* Nommer chaque voie
* Numéroter chaque habitation, entreprise et service public
* Certifier et publier les adresses dans la `Base Adresse Nationale <https://adresse.data.gouv.fr/>`_

Disposer d'une base adresse complète et fiable répond à d'importants enjeux du quotidien :

- Efficacité des services de secours
- Délivrance des colis et du courrier
- Déploiement du réseau de fibre optique
- Repérage au quotidien avec les services de GPS
- etc.

Depuis 2019, le Département du Calvados propose aux communes **un accompagnement dans cette démarche d'adressage**. Différents outils ont été développés afin de répondre aux besoins des communes mais aussi pour faciliter et accélerer la production et la certification des adresses dans le Calvados.

1- Rapport d'accompagnement
=======================

Afin de pouvoir présenter aux élus la démarche d'adressage et le dispositif d'accompagnement proposé par le Département du Calvados, le Pôle SIG s'est doté d'un projet de génération de **rapports thématiques automatisés**. Ces rapports pouvant donc être transposés à n'importe quelle autre thématique que l'adressage.

Avec la fonctionnalité d'`Atlas de QGIS <http://www.qgistutorials.com/fr/docs/automating_map_creation.html>`_ il est possible de générer une carte pour chaque entité géographique à partir d'un modèle. Ainsi, cet outil permet de produire une carte par commune (ou par canton, EPCI etc.) à partir d'un modèle unique. Pour l'exemple qui va suivre, la maille choisie est celle du canton de façon à pouvoir présenter aux conseillers départementaux un rapport d'avancement de l'adressage sur les communes composant leur territoire. `Un exemplaire est disponible ici <https://mapeo-calvados.fr/system/files/rapport_adressage_canton_bayeux.pdf>`_.

Dans cet exemple, le choix est de faire apparaître deux types d'informations :

* Une cartographie des communes qui sont engagées dans la démarche ou qui ont terminées leur projet. (**1**)
* Des statistiques à l'échelle du département (**2**) et du canton en question (**3**).

.. image:: ../images/Adressage/rapport_adressage_canton_bayeux.png
   :scale: 50

Les statistiques sont calculées avec des expressions QGIS intégrées dans du code HTML. Dans cet exemple ci-dessous, le nombre de communes accompagnées dans le Calvados est calculé avec le champ ``actif`` de la table ``Communes``. Il indique si la commune a engagé une démarche d'adressage avec le CD14) ::

	Nombre de communes engagées dans l'adressage : 
	[%aggregate(layer:='Communes', aggregate:='count', expression:=id_com, filter:=actif ='Oui' )%] 
	/ [%aggregate(layer:='Communes', aggregate:='count', expression:=id_com)%]</b>, 
	soit [%round(100*aggregate(layer:='Communes', aggregate:='count', expression:=id_com, filter:=actif ='Oui')/aggregate(layer:='Communes', aggregate:='count', expression:=id_com),1)%]%

Ce qui donne ::

	Nombre de communes engagées dans l\'adressage : 326 / 528 soit 61.6%

2- Atlas d'export
=======================





________________________________________________





II- Mise en place de la Base de données
***********************************

1- Plugin adresse
=======================



2- Mise à niveau schema adresse
=======================

Lors de mise à jour par 3liz de la base adresse, il peut s'avérer necessaire de migrer les données de l'ancien modèle vers le nouveau.

Pour cela, un ensemble de scripts sql est constitués.

Les scripts pour migration des données se trouve ici : 

`Dossier script migration données adresse <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/mise_a_niveau_base/migration_nouveau_modele_3liz>`_.
 
Les mises à jours du schema adresse effectuées par le pôle SIG sont également documentées. Elle sont stockées dans un fichier sql *upgrade_to_num_version*

Les scripts se trouve ici : 

`Dossier script upgrade CD14 <file://K:/Pole_SIG/Interne/03_TRAITEMENTS_SIG/1_postgres/adressage/mise_a_niveau_base>`_.


________________________________________________





III- Application de saisie
*************************


1- Triggers et fonctions
=======================

1.1 Module d'aide à la numérotation
-------------------------------

Il existe deux types de numérotation différents :

* La numérotation **classique**

.. image:: ../images/Adressage/numerotation_classique.png

Cette numérotation consiste à numéroter de deux en deux avec les numéros pairs à droite de la voie et les numéros impairs à gauche. C'est le système historique en France utilisé par une majorité des communes, notamment en ville.
L'inconvénient est que ce système n'est pas évolutif. En cas de nouvelles constructions s'intercalant entre deux numéros consécutifs il faut ajouter un numéro à extension (bis puis ter par exemple).

* La numérotation **métrique**

.. image:: ../images/Adressage/numerotation_metrique.png

Ce second système consiste à calculer le numéro en fonction de la distance depuis le début de la voie. Beaucoup plus évolutif car elle permet d'intercaler autant de numéros que l'on souhaite, cette numérotation permet également de donner une information précieuse sur la distance à parcourir jusqu'à la propriété. Cela est notamment très utile pour les secours ou les livreurs. Les numéros pairs et impairs peuvent être séparer de chaque côté de la voie, bien que ce ne soit pas obligatoire.

Quel que soit le type de numérotation choisit par la commune, l'application propose une aide à la numérotation automatique.

Pour la numérotation classique, une fonction soumet le numéro qu'elle considère être le plus juste à l'utilisateur en regardant les numéros déjà présents avant et après sur la voie. Au positionnement d'un premier point adresse à droite de la voie, l'outil proposera le n°2, puis pour un second le n°4 et ainsi de suite. À la création d'un point adresse entre le n°2 et le n°4, l'outil proposera un n°2 bis puis un n°2 ter etc.

		.. code-block:: sql

			DECLARE
				numa integer;
				numb integer;
				numc integer;
				sens boolean;
				s text;
				rec text;
				suff text[];
				idvoie integer;
				isleft boolean;
				test boolean;
				
			BEGIN
				-- Get idvoie
				SELECT adresse.get_id_voie(pgeom) into idvoie;

			-- Aucune voie dévérouillée trouvée
			IF idvoie IS NULL THEN
				return query SELECT numc, s, idvoie;
			END IF;

			SELECT adresse.calcul_point_position(adresse.calcul_segment_proche(geom, pgeom),pgeom ) into isleft
			FROM adresse.voie
			WHERE statut_voie_num IS FALSE AND id_voie=idvoie;

			SELECT v.sens_numerotation into sens
			FROM adresse.voie v WHERE v.id_voie = idvoie;

			SELECT numero into numa
			FROM(
			SELECT ST_Distance(pgeom, p1.geom) as dist, p1.numero as numero
			FROM adresse.point_adresse p1, adresse.voie v
			WHERE statut_voie_num IS FALSE AND p1.id_voie = idvoie AND v.id_voie = idvoie AND
				(ST_LineLocatePoint(v.geom, ST_ClosestPoint(v.geom, pgeom)) - ST_LineLocatePoint(v.geom, ST_ClosestPoint(v.geom, p1.geom))) >0
				AND
				isleft =
				adresse.calcul_point_position(adresse.calcul_segment_proche(v.geom, p1.geom), p1.geom)
			ORDER BY dist LIMIT 1) AS a;

			suff = ARRAY ['bis', 'ter', 'qua', 'qui', 'a', 'b', 'c', 'd', 'e'];

			SELECT numero into numb
			FROM(
			SELECT ST_Distance(pgeom, p1.geom) as dist, p1.numero as numero
			FROM adresse.point_adresse p1, adresse.voie v
			WHERE statut_voie_num IS FALSE AND p1.id_voie = idvoie AND v.id_voie = idvoie AND
				(ST_LineLocatePoint(v.geom, ST_ClosestPoint(v.geom, pgeom)) - ST_LineLocatePoint(v.geom, ST_ClosestPoint(v.geom, p1.geom))) <0
				AND
				isleft =
				adresse.calcul_point_position(adresse.calcul_segment_proche(v.geom, p1.geom), p1.geom)
			ORDER BY dist LIMIT 1) AS b;

			IF numa IS NOT NULL AND numb IS NOT NULL THEN
				test = false;
				IF numb - numa > 2 THEN
				 numc = numa+2;
				ELSE
					FOREACH rec IN ARRAY suff LOOP
						IF (SELECT TRUE FROM adresse.point_adresse p WHERE p.id_voie = idvoie AND p.numero = numa AND p.suffixe = rec) IS NULL AND NOT test THEN
							test = true;
							numc = numa;
							s = rec;
						END IF;
					END LOOP;
				END IF;
			ELSIF numa IS NOT NULL AND numb IS NULL THEN
				numc = numa+2;
			ELSIF numa IS NULL AND numb IS NOT NULL THEN
				IF numb - 2 >0 THEN
					numc =  numb - 2;
				ELSIF numb - 2 <= 0 THEN
					test = false;
					FOREACH rec IN ARRAY suff LOOP
						IF (SELECT TRUE FROM adresse.point_adresse p WHERE p.id_voie = idvoie AND p.numero = numb AND p.suffixe = rec) IS NULL AND NOT test THEN
							test = true;
							numc = numb;
							s = rec;
						END IF;
					END LOOP;
				END IF;
			ELSIF numa IS NULL AND numb IS NULL THEN
				IF isleft AND NOT sens THEN
					numc = 1;
				ELSIF NOT isleft AND NOT sens THEN
					numc = 2;
				ELSIF isleft AND sens THEN
					numc = 2;
				ELSIF NOT isleft AND sens THEN
					numc = 1;
				END IF;
			END IF;

			return query SELECT numc, s, idvoie;
			END;

Pour la numérotation métrique, une fonction calcule la distance avec ``ST_Length`` et répartit aussi automatiquement les numéros pairs à droite et impairs à gauche. Via la variable ``sens``, l'utilisateur peut indiquer la voie qu'il a dessiné est à numéroter en sens inverse. L'application prend en compte cette information et calcule le munéro "à l'envers".

		.. code-block:: sql

			DECLARE
				num integer;
				idvoie integer;
				numc integer;
				sens boolean;
				res text;
				rec text;
				isleft boolean;
				test boolean;
				suff text[];
			BEGIN

			-- Get idvoie
			SELECT adresse.get_id_voie(pgeom) into idvoie;

			-- Aucune voie dévérouillée trouvée
			IF idvoie IS NULL THEN
				return query SELECT numc, res, idvoie;
			END IF;

			SELECT v.sens_numerotation into sens FROM adresse.voie v WHERE v.id_voie = idvoie;

			SELECT adresse.calcul_point_position(adresse.calcul_segment_proche(geom, pgeom),pgeom) into isleft
			FROM adresse.voie
			WHERE statut_voie_num IS FALSE AND id_voie = idvoie;

			SELECT round(ST_Length(v.geom)*ST_LineLocatePoint(v.geom, pgeom))::integer into num
			FROM adresse.voie v
			WHERE id_voie = idvoie;

			suff = ARRAY ['bis', 'ter', 'qua', 'qui', 'a', 'b', 'c', 'd', 'e'];

			IF isleft AND num%2 = 0 AND NOT sens THEN
				num = num +1;
			ELSIF NOT isleft AND num%2 != 0 AND NOT sens THEN
				num = num + 1;
			ELSIF isleft AND num%2 != 0 AND sens THEN
				num = num +1;
			ELSIF NOT isleft AND num%2 = 0 AND sens THEN
				num = num + 1;
			END IF;

			test = false;
			WHILE NOT test LOOP
				IF (SELECT TRUE FROM adresse.point_adresse p WHERE p.id_voie = idvoie AND numero = num) IS NULL THEN
					test = true;
					numc = num;
				ELSE
					FOREACH rec IN ARRAY suff LOOP
						IF (SELECT TRUE FROM adresse.point_adresse p WHERE p.id_voie = idvoie AND p.numero = num AND p.suffixe = rec) IS NULL AND NOT test THEN
							test = true;
							numc = num;
							res = rec;
						END IF;
					END LOOP;
				END IF;
				num = num +2;
			END LOOP;

			RETURN query SELECT numc, res, idvoie;
			END;




2- Outils de contrôles
=======================

Solution SIG permettant d’affiner et de réduire le temps de contrôle de saisie des agents et d’assurer un suivi interactif des données.

Lorsque les communes effectuent la saisie dans l’application cartographique dédiée du Département, elles doivent créer un ensemble de points adresses (numérotés) et de linéaires de voies (dénommés). Cette saisie doit respecter un ensemble de règles et de normes afin d’assurer la cohérence du plan d’adressage de la commune et de ses voisines (même type de numérotation, même sens de numérotation, etc.) et d’optimiser la prise en compte de ces adresses par les organismes remplissant des missions de services aux citoyens (repérage facilité pour les secours, limite de nombre de caractères pris en compte par les GPS, etc.).

De plus, la base de données fournie doit répondre à des normes de qualité sémantiques (nom unique, etc.) et géographiques (pas d’auto intersection de linéaires, points adresses localisés dans une parcelle, etc.).


2.1 - Contrôles postgis
--------------------

Liste de défauts fréquemment rencontrés :

* Points adresses hors parcelles

.. image:: ../images/Adressage/III_saisie/2.1_erreur_hp.png

* Point adresse plus près d’une autre voie que celle à laquelle il est rattaché

.. image:: ../images/Adressage/III_saisie/2.1_erreur_adresse_voie.png

* Point adresse pair ou impair du mauvais côté de la voie

.. image:: ../images/Adressage/III_saisie/2.1_erreur_impair.png

* Erreurs de tracé de voies (ex : auto intersection) 

.. image:: ../images/Adressage/III_saisie/2.1_erreur_trace.png

* Voie portant le même nom qu'une autre voie de la même commune

.. image:: ../images/Adressage/III_saisie/2.1_erreur_meme_nom_voie.png

* Voies avec un nom trop long

.. image:: ../images/Adressage/III_saisie/2.1_erreur_nom_trop_long.png


Sur la base de cette liste, un ensemble de scripts SQL permettant d’identifier automatiquement ces différents cas :

1.	Détecter automatiquement des erreurs de saisie sémantiques dans les données adresses 
2.	Détecter les erreurs de saisie géométrique
3.	Produire un bilan sur l’ensemble des données de référence.

Les scripts listés sont disponibles ici :`Scripts de contrôle <K:\Pole_SIG\Interne\03_TRAITEMENTS_SIG\1_postgres\adressage\mise_a_niveau_base\upgrade_to_0.9.0_with_trigger.sql>`_ 

Description des scripts

**adresse.f_point_voie_distant()**

*Synopsis*

Fonction trigger adresse.f_point_voie_distant()
Identifie les points adresse plus près d’une autre voie que celle à laquelle ils appartiennent et retourne la distance entre le point et sa voie de rattachement.

*Description*

Retourne un BOOLEAN dans le champ c_erreur_dist_voie» de la table point_adresse.
Retourne un Integer dans le champ « c_dist_voie» de la table point_adresse.
Elle identifie ainsi la voie la plus proche dans un rayon de 10 km autour du point. Si la voie identifiée contient un « id_voie » différent de celui du point, la fonction retourne TRUE, sinon FALSE.

Elle calcule également la distance entre le point adresse et sa voie de ratachement.
Cette fonction se déclenche à chaque modification de la table point_adresse au niveau de la ligne modifiée.

.. image:: ../images/Adressage/III_saisie/2.1_f1.png


**adresse.point_proj()**

*Synopsis*

Fonction adresse. point_proj (ptgeom geometry, ptgeom_proj geometry);
Projette un point sur la voix de rattachement du point adresse.

*Description*

Retourne une géométrie point dans un champs nommé « geom_pt_proj».
Elle créer un point à partir de la localisation du point le proche du point adresse d’entré, sur la ligne possédant le même id_voie que ce point d’entré.
Fonctions postgis mobilisées :
•	ST_LineLocatePoint(voie.geom, point_adresse.geom) -> float between 0 and 1
•	ST_LineInterpolatePoint(voie.geom, float between 0 and 1)

.. image:: ../images/Adressage/III_saisie/2.1_f2.png


**adresse.segment_prolong()**

*Synopsis*

Fonction trigger adresse.segment_prolong(pgeom geometry, idv integer);
Dessine un segment prolongé du point adresse au point projeté.

*Description*

Retourne une géométrie ligne dans un champs nommé « geom_segment_prolong».
Dessine un segment du point adresse à un point projeté au 50/49e de la distance entre le point adresse et son point projeté.
Fonctions postgis mobilisées :
•	ST_DISTANCE(ptgeom,ptgeom_proj) as distance_pt
•	ST_AZIMUTH(ptgeom,ptgeom_proj) as azimuth_pt
•	ST_TRANSLATE (ptgeom, sinus(azimuth_pt) * distance_pt + 50/49 distance_pt, cosinus(azimuth_pt)*distance_pt+50/49 distance_pt as translation_pt
•	ST_MakeLine(ptgeom, translation_pt)

.. image:: ../images/Adressage/III_saisie/2.1_f3.png


**adresse.f_cote_voie()**

*Synopsis*

Fonction adresse.f_cote_voie(idv integer, geom_segment geometry);

Indique la position du point par rapport à sa voie de rattachement : droite, gauche, indéfinie. Sinon problème (voie mal tracée, point non rattaché à une voie, ...)

*Description*

Retourne du texte dans un champs nommé « cote_voie».

Elle identifie si le segment prolongé crée à partir du point projeté sur la voie de rattachement du point adresse, croise la ligne à gauche, à droite, ne croise pas ou croise plusieurs fois.

Fonction postgis mobilisées :
•	ST_LineCrossingDirection(geom_segment, voie_geom)

.. image:: ../images/Adressage/III_saisie/2.1_f4.png


**adresse.c_erreur_cote_parite()**

*Synopsis*

Fonction adresse.c_erreur_cote_parite(numero integer, cote_voie  geometry);

Identifie si le point adresse est  pair ou impair et du mauvais coté de la voie à laquelle il est rattaché : true (erreur coté), false (pas derreur) ou indefini. 

Sinon problème (voie mal tracée, point non rattaché à une voie, ...)

*Description*

Retourne du texte dans un champs nommé « erreur_cote_parite».

Elle identifie si le côté duquel se trouve le point adresse correspond à la parité de son numéro.

*Exemple*
Le numéro 5 impair se trouve du coté droit.
•	Erreur_cote_parite = True



**adresse.f_erreur_cote_parite()**

*Synopsis*

Fonction trigger adresse.f_erreur_cote_parite();  Identifie les points adresse pair ou impair du mauvais côté de la voie, à gauche ou à droite.

*Description*

Retourne un BOOLEAN dans le champ « c_erreur_cote_parite» de la table point_adresse.Elle identifie ainsi si le point adresse crée est à gauches ou à droite de la voie.

Si le point adresse est pair, mais à gauche de la voie ou si le point adresse est impair mais à droite de la voie, la fonction retourne TRUE, sinon FALSE.  

Sinon indefini. Sinon problème (voie mal tracée, point non rattaché à une voie, ...)

La fonction se déclenche à chaque modification du « geom » du point et s’effectue 4 étapes :
1-	Projection du point adresse sur sa voie de rattachement 
•	adresse.point_proj(pgeom geometry, idv integer)
2-	Dessin d’un segment prolongé au 50/49 de la taille du segment initial.
•	adresse.point_segment_prolong(pgeom geometry, idv integer)
3-	Identification du sens de croisement du segment prolongé
•	adresse.f_cote_voie(idv integer, geom_segment geometry)
4-	Comparaison avec le numéro du point adresse d’origine.
•	adresse.c_erreur_cote_parite(numero integer, cote_voie  geometry)

.. image:: ../images/Adressage/III_saisie/2.1_f5.png



**adresse.segment_extract()**

*Synopsis*

Fonction adresse.segment_extract(table_name varchar, id_line varchar, geom_line varchar);

Extrait des segments à partir de polylignes.

*Description*

Retourne une table composé de 3 champs ( id bigint,  id_voie integer, geom_segment geometry).

Sélectionne les nœuds des voies. Puis trace des lignes entre les différents nœuds crées.
Fonctions postgis mobilisées :
•	ST_DumpPoints(voie_geom)
•	ST_makeline()

.. image:: ../images/Adressage/III_saisie/2.1_f6.png

**adresse.line_rotation()**

*Synopsis*

Fonction adresse.line_rotation( lgeom geometry);

Retourne les segments au niveau de leur centroides raccourcies de 2/3

*Description*

Retourne une géométrie de ligne dans un champs nommé « geom_rotate».

Elle effectue une rotation à 80,1 degrès d’1/3 du segment au niveau de son centroide.
Fonction postgis mobilisées :
•	ST_LineSubstring(lgeom, 0.333 ::real, 0.666::real) as substring
•	ST_centroid(lgeom) as centroid
•	st_rotate(substring, centroid) as rotate
•	ST_CollectionExtract(rotate) 

.. image:: ../images/Adressage/III_saisie/2.1_f7.png


**adresse.f_voie_erreur_trace()**

*Synopsis*

Fonction adresse.f_voie_erreur_trace();
Identifier les voies avec erreur de tracés (plusieurs passages de lignes, voies recourbées sur elles-mêmes, etc.)

*Description*

Retourne un BOOLEAN dans le champ « c_erreur_trace» de la table adresse.voie.

Elle identifie ainsi si la voie qui croise plusieurs fois un segment retourné. La voie croise plusieurs fois, la fonction retourne TRUE, sinon FALSE.

La fonction se déclenche à chaque modif/ajout du « geom » de la voie et s’effectue 3 étapes :
1-	Extrait des segments à partir de polylignes 
•	adresse.segment_extract(table_name varchar, id_line varchar, geom_line varchar
2-	Retourne les segments au niveau de leur centroides raccourcies de 2/3
•	adresse.line_rotation( lgeom geometry);
3-	Identification du sens de croisement du segment prolongé
•	ST_LineCrossingDirection(New.geom, geom_rotate)

.. image:: ../images/Adressage/III_saisie/2.1_f8.png


**adresse.f_bilan_pt_parcelle()**

*Synopsis*

Fonction adresse.f_bilan_pt_parcelle();
Bilan du nombre de points adresses et dernière date de modification d’un point par parcelle.

*Description*

Retourne un integer dans le champ « nb_pt_adresse» et une DATE dans le champs « date_pt_modif »  de la table adresse.parcelle.

Elle compte d’abords le nombre d’id point adresse par parcelle. Puis ajoute la date de modification associée nulle ou la plus récente.

La fonction se déclenche à chaque modif/ajout du « geom » du point adresse.


.. image:: ../images/Adressage/III_saisie/2.1_f9.png


**adresse.f_commune_repet_nom_voie()**

*Synopsis*

Fonction trigger adresse.f_commune_repet_nom_voie();

Identifie les voies portant le même nom qu'une autre voie de la même commune.

*Description*

Retourne un BOOLEAN dans un champs nommé « c-repet-nom_voie» de la table adresse.voie.

Elle sélectionne le nom des communes, le nom des voies et le nombre d’itération du nom des voies par commune. 

Si aucun nom n’est répertorié elle retournera FALSE sinon TRUE.

Elle se déclenche à chaque création ou modification d’une valeur du champs nom.

.. image:: ../images/Adressage/III_saisie/2.1_f10.png


**adresse.f_controle_longueur_nom()** 

*Synopsis*

Fonction trigger adresse.f_controle_longueur_nom() ;

Identifie les voies portant un nom de plus de 24 caractères.

*Description*

Retourne un BOOLEAN dans un champs nommé « c_long_nom» de la table adresse.voie.

Si le nom de la voie fait plus de 24 caractère la fonction retournera TRUE sinon FALSE

Elle se déclenche à chaque création ou modification d’une valeur du champs nom.

.. image:: ../images/Adressage/III_saisie/2.1_f11.png



**adresse.f_voie_double_saisie()**

*Synopsis*

Fonction trigger adresse.f_voie_double_saisie() ;

Identifie les voies saisies en 2 fois.


*Description*

Retourne un BOOLEAN dans un champs nommé « c_saisie_double» de la table adresse.voie.

Cette requête retourne les voies à moins de 500 mètre de la nouvelle voie crée et dont le nom est proche de celui-ci. Si aucune voie n’est répertoriée elle retournera FALSE sinon TRUE.

Elle se déclenche à chaque création ou modification sur la table voie.

.. image:: ../images/Adressage/III_saisie/2.1_f12.png




2.2 - Dashboard QGis
-----------------

Tableau de bord de suivi des indicateurs clés du projet, intégré aux logiciels SIG utilisés quotidiennement par les équipes et les partenaires.

.. image:: ../images/Adressage/III_saisie/dashboard/intro.png


**Un outil de suivi intégré**

Au sein du pôle SIG, nous souhaitions obtenir une vue d’ensemble des données produites au fur et à mesure de l’avancement du projet. Il fallait donc identifier une solution SIG permettant d’assurer un suivi interactif des données (contrôle des erreurs de saisies et bilan de l'avancement du projet).
Elle devait s’intégrer au logiciel QGIS utilisé par le chargé de mission SIG du Département et sur l’application cartographique Lizmap à disposition des communes et des partenaires.

Nous nous sommes appuyés sur une méthodologie publiée sur le site <https://plugins.QGIS.org/geopackages/5/> (Sutton, 2020) , afin de développer un « Dashboard » par manipulation des étiquettes de couches QGIS.

Cette méthode permet, en créant une couche spécifique de tableau de bord, de paramétrer le style des étiquettes de la couche et via requêtes sql d’agrégation, de produire un tableau interactif de suivi des données présentes dans le projet QGIS.

**Les étapes de construction du Dashboard**

*Etape 1 : création de la couche dashboard*

Créer une couche « dashboard » de polygone composée des champs suivant :

.. image:: ../images/Adressage/III_saisie/dashboard/1_champs_dashboard.png 

*Etape 2 : créer un polygone*

Éditer la couche « dashboard » et créer un polygone suivant l’emprise du projet.

.. image:: ../images/Adressage/III_saisie/dashboard/2_polygon_dashboard.png  


*Etape 3 : symbologie de la couche*

Ouvrir les propriétés de la couche dashboard et dans l’onglet symbologie sélectionner ‘aucun symbole’.

Le polygone doit disparaître à l’écran.

.. image:: ../images/Adressage/III_saisie/dashboard/3_symbologie_dashboard.png


*Etape 4 : paramétrer les étiquettes*

Sélectionner ‘Etiquettes simples’ dans l’onglet Étiquettes. Dans le sous onglet valeur, faites une sélection par expression et inscrivez le code suivant : `eval( "label_expression")`

.. image:: ../images/Adressage/III_saisie/dashboard/4_etiquettes_dashboard.png


Dans le sous-onglet texte cliquer sur l’icône à droite de la police. Aller chercher type de champs et pointer vers le champ **font** de la table « dashboard » créée à l’étape 1.

.. image:: ../images/Adressage/III_saisie/dashboard/5_etiquettes_dashboard.png 



Faire de même avec le **style** et pointer sur le champs style.

.. image:: ../images/Adressage/III_saisie/dashboard/6_etiquettes_dashboard.png 


Faire de même avec la **couleur** et pointer sur le champ _**font_color**_.

.. image:: ../images/Adressage/III_saisie/dashboard/7_etiquettes_dashboard.png


Aller maintenant dans l’onglet **arrière-plan.**

Faire de même que précédemment avec la **taille X** et pointer sur le champ _**width**_.

.. image:: ../images/Adressage/III_saisie/dashboard/8_etiquettes_dashboard.png 


Faire de même que précédemment avec la **taille Y** et pointer sur le champ _**height**_.

.. image:: ../images/Adressage/III_saisie/dashboard/9_etiquettes_dashboard.png 


Faire de même avec la **couleur de remplissage** et pointer sur le champ _**bg_colour**_.

.. image:: ../images/Adressage/III_saisie/dashboard/10_etiquettes_dashboard.png


Aller maintenant dans l’onglet **position**.

Choisir l’option quadrant de l’image ci-dessous.

Cliquer sur l’icône à droite de **décalage X,Y**. Choisissez cette fois ci la sélection par expression.

Dans le constructeur de requête qui s’ouvre, indiquer la variable suivante : `array( "label_offset_x" , "label_offset_y")`  
Appuyer sur ok.

.. image:: ../images/Adressage/III_saisie/dashboard/11_etiquettes_dashboard.png


Pour finir, afin de fixer les étiquettes selon l'emprise de la carte, cocher la case **générateur de géométrie** et inscrire l'expression suivante : start_point( @map_extent )


.. image:: ../images/Adressage/III_saisie/dashboard/last_emprise_carte_expression.png 



*Etape 5 : Remplir les champs de la table attributaire*

Revenir à la table attributaire de « dashboard ».

Donner un nom qui mette en évidence l’action. Ici le titre de la première étiquette que nous appellerons fenêtre dashboard.

Puis indiquer dans le champs label expression l’expression qui s’affichera dans la première fenêtre dashboard, ici, simplement le titre _***'nbr pt total'**_


.. image:: ../images/Adressage/III_saisie/dashboard/12_1rst_fenetre_dashboard.png


Paramétrer ensuite les champs qui vont déterminer la taille, la position, la couleur de fond et la police de la première fenêtre Dashboard.

.. image:: ../images/Adressage/III_saisie/dashboard/12_1rst_fenetre_suite_dashboard.png


Au fur et à mesure des modifications des valeurs de champs, lorsque vous enregistrez, vous devez voir apparaître la 1ere fenêtre Dashboard et les modifications apportées.

.. image:: ../images/Adressage/III_saisie/dashboard/12_1rst_fenetre_vue.png 


Si aucune fenêtre n’apparaît au niveau de votre projet QGIS, jouez avec les différents champs (surtout label_offset x, label_offset y), cela peut être un problème de position de la fenêtre. Si elle n’apparaît toujours pas, reprenez les étapes précédentes.

*Etape 6 : Créer de nouvelles fenêtres dashboard*

Pour créer une nouvelle fenêtre dashboard, passer la table attributaire en mode édition. Copiez la première ligne et coller la dans la partie blanche de la table attributaire. Une deuxième ligne identique apparaît.

.. image:: ../images/Adressage/III_saisie/dashboard/13_2nd_fenetre_dashboard.png

*Etape 7 : Paramétrer des requêtes dans les nouvelles lignes*

Une fois la nouvelle entité crée, modifier les valeurs de champs de la seconde pour positionner la deuxième fenêtre sous la première.  Vous pouvez modifier le champs label_expression avec une requête sql qgis qui vous permettra d’afficher la valeur souhaitée dans cette deuxième fenêtre.


.. image:: ../images/Adressage/III_saisie/dashboard/14_2nd_fenetre_vue.png 


*Exemple de table attributaire Dashboard et rendu*

Ci-dessous, nous avons organisé la table avec une fenêtre par ligne comme suit : une 1ère fenêtre avec valeur « titre » suivie d'une fenêtre affichant une valeur « expression ».

.. image:: ../images/Adressage/III_saisie/dashboard/15_ex_table_attrib.png


.. image:: ../images/Adressage/III_saisie/dashboard/16_ex_table_attrib_suite.png


*Exemple de requêtes utilisées*

1- Total de la somme des valeurs de la colonne pt_total de la couche Infos Communes

		.. code-block:: sql

			aggregate(layer:= 'Infos Communes', aggregate:='sum', expression:=pt_total)

2- Total de la somme des valeurs de la collonne pt_total des entités sélectionnées sur la couche Infos Communes

		.. code-block:: sql

			aggregate(layer:= 'Infos Communes', aggregate:='sum', expression:=pt_total, filter:=is_selected('Infos Communes', $currentfeature )  )

3- Nombre de communes accompagnées (champ : actif, valeur : oui) dans la couche Infos Communes

		.. code-block:: sql

			aggregate(layer:= 'Infos Communes', aggregate:='count', expression:= actif, filter:= actif LIKE 'Oui' )

*Exemple de rendu

Le Dashboard est utilisé par le pôle SIG afin de contrôler les erreurs de saisies en temps réel par les communes et présenter un bilan général de l'avancement du projet.

Ci-dessous, un exemple d'affichage des bilans adresses (en haut à droite) après sélection d'une commune sous QGIS.

.. image:: ../images/Adressage/III_saisie/dashboard/gif_dashboard.gif



________________________________________________





IV- Consultation et exports des données
**************************************


1- Outils d'export
=======================

1.1 Export BAL Qgis
---------------------

Création d’une commande qgis pour exporter les données points adresse et voies par commune avec un simple clik bouton.

**Etape 1 : ouverture de la console action**

Ouvrir la console « action » depuis les propriétés de la couche Commune (ici la couche Accompagnement alias du projet de la table adresse.commune).

**Etape 2 : paramétrer l'action**

Donner un nom à l’action et coller, paramétrer l’action et inscrire le code python dans la console.

.. image:: ../images/Adressage/IV_consultation_export/export_qgis1.png

Les code python pour l’export des points adresse est le suivant :

		.. code-block:: python

			# importer les biblihotèques
			from qgis.utils import iface
			from qgis.core import *
			from qgis.gui import *
			layer = iface.activeLayer() # garde en memoire  la couche active
			selection = layer.selectedFeatures() # garde en memoire  les entités sélectionnées
			for feat in selection:  # boucle sur les couches sélectionnées
				value = feat['Code INSEE'] # garde en memoire  les valeurs du champs code insee
			for feat in selection:
				value2 = feat['Commune'] # garde en memoire  les valeurs du champs commune
			cl = QgsProject.instance().mapLayersByName('v_export_pts')[0] # garde en memoire  la couche dénommée
			iface.setActiveLayer(cl) # active la couche
			cl.selectByExpression( " \"Code INSEE\" = '{}' ".format(value), QgsVectorLayer.SetSelection) # séléctionne les entité dont le champs code INSEE est égal à la valeur du champs code insee de la première couche
			output_path = r'G:\DDTFE\ST\POLE_SIG\01_PROJETS_SIG\12_Adressage_BAN\02_PROJETS_COMMUNES\Export\export_points\%s_Export_points.csv' % value2 # definit le chemin d'export avec la variable value2 dans le nom
			QgsVectorFileWriter.writeAsVectorFormat(cl, output_path, "UTF-8", driverName="CSV", onlySelected=True) # Exporte les entité selectionnées
			iface.messageBar().pushMessage("Export réalisé avec succès vers G/POLE_SIG/12_Adressage_BAN/02_PROJETS_COMMUNES/Export")

Les code python pour l’export des voies est le suivant :

		.. code-block:: python

			from qgis.utils import iface
			from qgis.core import *
			from qgis.gui import *
			layer = iface.activeLayer() 
			selection = layer.selectedFeatures() 
			for feat in selection: 
				value = feat['Code INSEE'] 
			for feat in selection:
				value2 = feat['Commune'] 
			cl = QgsProject.instance().mapLayersByName('v_export_voies')[0]
			iface.setActiveLayer(cl)
			cl.selectByExpression( " \"Code INSEE\" = '{}' ".format(value), QgsVectorLayer.SetSelection)
			output_path = r'G:\DDTFE\ST\POLE_SIG\01_PROJETS_SIG\12_Adressage_BAN\02_PROJETS_COMMUNES\Export\export_voies\%s_Export_voies.csv' % value2 
			QgsVectorFileWriter.writeAsVectorFormat(cl, output_path, "UTF-8", driverName="CSV", onlySelected=True)

			iface.messageBar().pushMessage("Export réalisé avec succès vers G/POLE_SIG/12_Adressage_BAN/02_PROJETS_COMMUNES/Export")


**Etape 3 : test exécution de l’action**

Sélectionner la couche en entrée et la commune pour laquelle vous voulez réaliser l’export. Et utiliser la commande action.

.. image:: ../images/Adressage/IV_consultation_export/export_qgis2.png


Faire un clic droit sur la carte

.. image:: ../images/Adressage/IV_consultation_export/export_qgis3.png

L’export a été réalisé dans le dossier : 'G:\DDTFE\ST\POLE_SIG\01_PROJETS_SIG\12_Adressage_BAN\02_PROJETS_COMMUNES\Export\


2- Le site "Mon adresse, des services"
=======================



**index.html** est un fichier html incluant du javascript, à déployer sur les
serveurs du SIG du CD14.

Il fait appel à la feuille de style **min-style.css** et est également dépendant
du script **getData.php** (dossier "php").

2.1 - Fonction de l'outil
---------------------

Ce code génère une page web, avec un champ permettant à l'utilisateur de
renseigner une adresse. Jusqu'à 5 propositions d'adresses correspondantes sont
affichées et sélectionnables par l'utilisateur.

Quand une est sélectionnée, diverses informations géographiques viennent remplir
la page, par section, pour renseigner l'utilisateur.


2.2 Le HTML
----------

Le corps principal du html est structuré en une div contenant l'élément input et
une autre contenant l'ensemble des sections et sous-sections accueillant les
résultats. À l'élément input est ensuite associé un objet javascript
``autoComplete``, dont le constructeur est importé.

2.3 Questionnement de l'API Adresse
------------------------------


À chaque changement de valeur de ce champ, une requête est envoyée à l'API
Adresse nationale. Elle renvoie les adresses correspondant au mieux à ce qui lui
est envoyé, mais à l'expression saisie par l'utilisateur sont ajoutés les
mots-clés "Normandie", "Calvados" et "14" permettant de favoriser l'apparition
d'adresses du Calvados dans les résultats.

Le nom complet des adresses renvoyées par l'API ainsi que les coordonnées en
longitude et latitude qui y sont associés sont stockées, et chaque adresse
affichée.

2.4 Questionnement de la BD du SIG
-----------------------------


Lorsque l'utilisateur sélectionne une adresse, la longitude et la latitude
relatives à cette adresse, préalablement stockées, sont envoyés à plusieurs
reprises à **getData.php**, avec des valeurs pour le paramètre "res" différentes
à chaque fois. C'est ce paramètre qui renseigne le script php sur la requête à
utiliser.

Pour chaque requête, les données retournées au format json sont alors ajoutées
à la section portant le nom correspondant.




________________________________________________





V- Dépôt BAL
************
.. image:: ../images/Adressage/V_depot_bal/fme_depot_bal.png
   :width: 880

REMPLACER IMAGE par PNG METHODO


Etalab, via sa plateforme adresse.data.gouv.fr met à disposition une **API** permettant de déposer les mise à jour de **Bases Adresses Locales** dans la **Base Adresse Nationale**. 

`Documentation github de l'API de dépot <https://github.com/BaseAdresseNationale/api-depot/wiki/Documentation>`_.

Les communes ou leurs représentants peuvent, avec un justificatif, obtenir une habilitation à déposer les fichiers adresses BAL sur un périmètre donné.

Ainsi, le Département du Calvados, dans le cadre de sa mission d'accompagnement à l'adressage des Communes, téléverse chaque nuit les fichiers BAL communaux certifiés par les Communes partenaires.



Boite à outils
=======================

La méthodologie développée ici s'appuie sur les travaux réalisés et publiés par **l'Agglomération de la Région de Compiègne** : `github de l'ARC <https://github.com/sigagglocompiegne/rva/blob/master/api/doc_api_balc_fme.md>`_.

Elle repose sur le système de gestion de **base de données PostgreSQL** sous licence BSD et le logiciel **ETL** propriétaire **FME** développé par SAFE Software.

Ces développements ont été réalisés sous système d'exploitation Windows.


1ère Etape : Préparation des données
=======================

L'ensemble des données adresses mises à jours et certifiées quotidiennement par les Communes dans le cadre de l'accompagnement CD14 sont stockées dans une table (ici nommée **adresse.v_bal_dept**) au sein de la Base de Données SIG du Département.

Ces données sont structurées selont le modèle de données BAL attendu par l'API de dépot : `ressources AITF voies-adresses <https://aitf-sig-topo.github.io/voies-adresses/>`_.

Un validateur en ligne permet de vérifier que les fichiers à déposer répondent bien à ce standart : `Validateur BAL adresse.data.gouv <https://adresse.data.gouv.fr/bases-locales/validateur>`_.

.. image:: ../images/Adressage/V_depot_bal/bal_dept.png
   :width: 880


Un traitement FME enregistre chaque nuit les entités adresses de cette table par commune dans des fichiers CSV nommés avec la valeurs INSEE de chaque commune ayant certifié son adressage (illustration ci-dessous)

.. image:: ../images/Adressage/V_depot_bal/enregistrement_csv_ban.png
   :scale: 50 %




Une seconde table de données regroupe l'ensemble des données adresses aglomérées à la Commune. Elle contient les champs suivants :

* L'INSEE de la commune
* Le nom de la commune
* Le nombre total de points adresses recencés le matin avant 6h00
* Le nombre total de points adresses recencés le soir après 23h00
* Le nombre total de points adresses modifiés dans la journée (comptabilisé le soir après 23h00)

Les 3 derniers champs de cette table sont mis à jours quotidienement comme suit :

    **1-** Mise en place de fichiers Batch pour execution des script sql via psql 
			.. code-block:: Batch

				@echo off
				CALL D:\_cron_postgres\conf\config_db_pg.bat
				setlocal
				set PGPASSWORD=%PGPASSWORD%
				"D:\PostgreSQL\11\bin\psql.exe" -h %PGHOSTNAME% -U %PGUSER% -d %PGROLE% -p %PGPORT% -f D:\_cron_postgres\adressage\api_ban\scripts\count_pts_matin.sql
				endlocal

	**2-** Execution des script sql  suivants :

			* A 6h00 du matin : 
			.. code-block:: sql
			
				-- Compte le nombre de points adresse par commune
				update adresse.commune set  nb_pts_matin = ct 
				from (
					select count(commune_insee) as ct, commune_insee
					from adresse.v_bal_dept
					group by commune_insee
					)b 
				where commune.insee_code = b.commune_insee
		
			* A 23h00 le soir : 
			.. code-block:: sql
			
				-- Remet le compte de points modifiés à null dans la table commune
				update adresse.commune set nb_pts_modif_today = null;

				-- Compte le nombre de points adresse modifié dans la journée (date now) par commune
				update  adresse.commune set nb_pts_modif_today = ct 
				from (
					select count(commune_insee) as ct, commune_insee
					from adresse.v_bal_dept where date_der_maj = NOW()::DATE
					group by commune_insee
					)b
				where commune.insee_code = b.commune_insee;

				-- Compte le nombre de points adresse par commune
				update  adresse.commune set  nb_pts_soir = ct 
				from (
					select count(commune_insee) as ct, commune_insee
					from adresse.v_bal_dept
					group by commune_insee
					)b 
				where commune.insee_code = b.commune_insee;


----


2e Etape : Chaîne de traitement FME
=======================

*Vous pouvez télécharger la dernière version du projet FME en cliquant sur le lien ci dessous :*

`Téléchargement du projet FME <https://github.com/sig14/private-doc/releases/download/adresse/FME_api_depot_bal.zip>`_

*Le Workbench FME a été déposé sur le serveur APW65. Suivre le lien ci dessous :*

`Lien projet FME APW65 <file:////apw65/_FME/ADRESSAGE/api_depot_bal.fmw>`_ 


2.1 - Ajouter les données sources
-----------------------------------


Ajout de la première table de données à l'échelle des communes dans le projet FME.

.. image:: ../images/Adressage/V_depot_bal/1_FME_donnees_sources.png
   :scale: 50 %

Supprimer les champs inutiles. Ne garder que les champs suivants :

* Le nom  communes du département
* Leurs code INSEE 
* Le nombre de points adresses total par commune actualisé chaque matin
* Le nombre points adresses total par commune actualisé chaque soir
* Le nombre de points modifié dans la journée actualisé chaque soir



2.2 - Ajouter les jeton d'accès API
-----------------------------------



Utiliser le transformer **AttributeCreator**.
Créer un nouveau champs **"jeton"** et attribuer la valeur de votre jeton d'accès à l'API.

.. image:: ../images/Adressage/V_depot_bal/2_FME_jeton_API.png
   :scale: 50 %


2.3 - Sélection des communes avec mises à jour de points adresse
----------------------------------------------------------------------


.. image:: ../images/Adressage/V_depot_bal/3_FME_verif_MAJ.png
   :width: 580

Dans cette partie, nous ne conserverons que les communes dont au moins 1 point a été mis à jour dans la journée.

Pour cela :

* Ajouter le transformer **testFilter** pour ne garder que les communes dont le compte de points de la journée (*pts_modif_today*) est égal ou supérieur à 1.

.. image:: ../images/Adressage/V_depot_bal/4_FME_test_MAJ.png
   :scale: 50 %

* Supprimer ensuite les champs non nécessaires à l'agregation, pour ne conserver que : **le jeton**,  **le nom de la commune** et **le code insee**




2.4 - Sélection des communes avec suppression ou ajout de points adresse
----------------------------------------------------------------------

.. image:: ../images/Adressage/V_depot_bal/5_FME_verif_ajout_supr.png
   :width: 780

Dans cette partie, nous ne conserverons que les communes pour lesquelles des adresses ont été suprimées ou ajoutées.

Pour cela :

* Ajouter le transformer **testFilter** pour ne garder que les communes dont le compte de point du matin (*nb_pts_matin*) est différent du compte de point du soir (*nb_pts_soir*).
.. image:: ../images/Adressage/V_depot_bal/6_FME_test_ajout_supr.png
   :scale: 50 %

* Supprimer ensuite les champs non nécessaires à l'aggregation, pour ne conserver que : **le jeton**,  **le nom de la commune** et **le code insee**



2.5 - Agregation des communes filtrées
-----------------------------------


Une fois les deux filtres éffectués, on agrége l'ensemble des données avec le transformer **Aggregator**.

.. image:: ../images/Adressage/V_depot_bal/7_FME_aggregation_com.png
   :scale: 50 %


2.6 - Requêtes à l'API 
-----------------------------------

.. image:: ../images/Adressage/V_depot_bal/8_FME_requête_api_com.png
   :width: 880

Le traitement pour dépot des BAL à l'API se déroule comme suit :

* Mise à jour des adresses d'une Commune par dépot d'une nouvelle BAL qui écrase l'ancienne :  **REVISION**
* Téléversement du fichier au format BAL : **TELEVERSEMENT**
* Validation des donénes transmises :  **VALIDATION**
* Publication de la nouvelle BAL :  **PUBLICATION**
* Récupération de la Réponse de l'API : **REPONSE**


**REVISION**


	**1-** Utliser le Transformer **HTTPCaller** comme suit 

.. image:: ../images/Adressage/V_depot_bal/10_caller_revision.png
   :width: 480

*Paramètres :*

1 *URL :* https://plateforme.adresse.data.gouv.fr/api-depot/communes/@Value(insee)/revisions

2 *Méthode HTTP* : POST

3 *En-têtes :*
			* *Nom =* Authorization
			* *Valeur =* Token @Value(jeton)

4 *Corps* : 
			* *Type de données à charger =* Specify Upload Body
			* *Corps de la requête (remplacer les termes après les :") = * { "context": { "nomComplet": "A remplacer", "organisation": "A remplacer" } }
			* *Type de contenu =* json

5 *Réponse* : 
			* *Enregistrer le corps de la réponse dans =* Attribut
			* *Attribut de réponse =* _response_body
			



	**2-** Récupérer l'ID dans la réponse avec les transformer *JSONFragmenter* et *Tester* comme suit :

.. image:: ../images/Adressage/V_depot_bal/11_recup_id_revision.png
   :width: 880



**TELEVERSEMENT**

	**1-** Utliser le Transformer **HTTPCaller** comme suit 

.. image:: ../images/Adressage/V_depot_bal/12_FME_caller_televersement.png
   :width: 480
   :align: center


*Paramètres :*

1 *URL :* https://plateforme.adresse.data.gouv.fr/api-depot/revisions/@Value(_response_body)/files/bal

2 *Méthode HTTP* : PUT

4 *Paramètres complémentaires de la requête :*
			* *Nom =* Content-MD5
			* *Valeur =* 1234567890abcdedf1234567890abcdedf

4 *En-têtes :*
			* *Nom =* Authorization
			* *Valeur =* Token @Value(jeton)

5 *Corps* : 
			* *Type de données à charger =* Envoyer à partir d'un fichier
			* *Chemin du fichier à charger = * Le chemin vers les fichiers CSV adresse par commune créés en partie I 
			* *Type de contenu =* text/csv

6 *Réponse* : 
			* *Enregistrer le corps de la réponse dans =* Attribut
			* *Attribut de réponse =* _response_body
			


	**2-** Récupérer l'ID dans la réponse avec les transformer **JSONFragmenter** et **Tester** comme précédemment pour la révision


**VALIDATION**

	**1-** Utliser le Transformer **HTTPCaller** comme suit 

.. image:: ../images/Adressage/V_depot_bal/13_FME_caller_validation.png
   :width: 480
   :align: center


*Paramètres :*

1 *URL :* https://plateforme.adresse.data.gouv.fr/api-depot/revisions/@Value(_response_body)/compute

2 *Méthode HTTP* : POST



	**2-** Récupérer l'ID dans la réponse avec les transformer **JSONFragmenter** et **Tester** comme précédemment pour la validation



**PUBLICATION**

	**1-** Utliser le Transformer **HTTPCaller** comme suit 

.. image:: ../images/Adressage/V_depot_bal/14_FME_caller_publication.png
   :width: 480
   :align: center


*Paramètres :*

1 *URL :* https://plateforme.adresse.data.gouv.fr/api-depot/revisions/@Value(_response_body)/publish



	**2-** Récupérer l'ID dans la réponse avec les transformer *JSONFragmenter* et *Tester* comme précédemment pour la validation


A la fin de cette étape, vos adresses sont publiées sur la BAN.

**REPONSE**

	**1-** Utliser le Transformer **HTTPCaller** comme suit 

.. image:: ../images/Adressage/V_depot_bal/15_FME_caller_reponse.png
   :width: 480
   :align: center


*Paramètres :*

1 *URL :* https://plateforme.adresse.data.gouv.fr/api-depot/communes/@Value(insee)/current-revision

2 *Méthode HTTP* : GET



	**2-** Récupérer l'ID dans la réponse avec les transformer **JSONFragmenter** et **Tester** comme précédemment pour la validation



2.6 - Mail récapitulatif 
-----------------------------------

.. image:: ../images/Adressage/V_depot_bal/16_FME_mail.png
   :width: 880

Suite à la réponse de l'API, on supprime les champs inutiles pour ne conserver que  :

* Commune
* Insee
* response_body

Avec le Transformer **StringSearcher**, on extrait par expression régulière les valeurs de chiffres après rowsCounts. L'idée est ici d'extraire le nombre d'adresses publiées de la réponse API.
		
		.. code-block:: python
			(?<=rowsCount":)[\w+.-]+

On créé ensuite un nouvel attribut comprenant le nombre de points extraits de la réponse suivi du texte que l'on souhaite ajouter.

.. image:: ../images/Adressage/V_depot_bal/17_FME_mail_attrribute_create.png
   :width: 480

Puis, on met en place une liste sur le champs précédemment créé et on va concatener la liste au niveau des sauts de lignes. Ceci pour n'obtenir qu'une seule entité à intégrer dans le mail.

.. image:: ../images/Adressage/V_depot_bal/18_FME_mail_list_concat.png
   :scale: 50 %


Enfin, avec le transformer **Emailer**, on envoie dans le corps du mail la valeur de concatenation de liste.

.. image:: ../images/Adressage/V_depot_bal/19_FME_mail_Emailer.png
   :scale: 50 %



2.7 - Intégration du compte de points publiés dans la base de données
----------------------------------------------------------------------

.. image:: ../images/Adressage/V_depot_bal/20_Intégration_bd.png
   :width: 680

Après identification du compte de points publiés, on supprime les champs inutiles pour ne garder que :

* Le nombre de points publiés extrait par **StringSearcher**  (*_rows*)
* Le code INSEE de la commune

On créé ensuite un champs *date_depot_api* avec la date du jour (**AttributeCreator** : @DateTimeFormat(@DateTimeNow(local), %Y%m%d)).

On insère finalement les données dans la table *commune* citée en partie I au niveau de la correspondance insee (**DatabaseUpdater**).

.. image:: ../images/Adressage/V_depot_bal/21_FME_Databaseupdater.png
   :scale: 50 %



3e Etape :  Mailing automatique
=======================

En complément de la chaine de traitement détaillée précédemment, un bilan hebdomadaire est réalisée sur la base de données adresse du Département.

Ce bilan vise à recenser le détaille des points adresses modifiés, supprimés et ajoutés sur les communes ayant ubliées leur BAN durant les 7 derniers jours.

Il est transmis chaque début de semaine au chef de projet du Département et aux partennaires du projet (La poste et DGFIP).



3.1 - Enregistrement des données adresses
----------------------------------------------------------------------

**Chaque lundi à 4h (n7) et à 5h du matin (n0) ** :

Enregistrement au format CSV d'une table de données des adresses sur les communes publiées. Elle contient les champs suivants :

* L'identifiant du point 
* Le nom de la commune et son code INSEE
* L'adresse complète du point

 		.. code-block:: sql

				\copy (select a.id_point, a.commune_nom, a.insee_code, a.adresse_complete 
				from adresse.v_point_adresse a, adresse.v_communes_publiees b where  a.insee_code = b.insee_code )
				TO 'D:\BD_adresse\bakup_adresses\v_point_adresse_dimanche.csv' DELIMITER ',' CSV HEADER NULL as 'NULL';


Enregistrement au format CSV d'une table de données des adresses modifiées durant les 7 derniers jours sur les communes publiées. Elle contient les champs suivants :

* L'identifiant du point 
* Le nom de la commune et son code INSEE
* L'adresse complète du point
* La date de modification du point

 		.. code-block:: sql
			
				\copy (select a.id_point, a.date_modif, a.commune_nom, a.insee_code, a.adresse_complete 
				from adresse.v_point_adresse a, adresse.v_communes_publiees b 
				where  a.insee_code = b.insee_code and (a.date_modif > current_date - integer '7')) 
				TO 'D:\BD_adresse\bakup_adresses\v_point_adresse_dimanche_modif.csv' DELIMITER ',' CSV HEADER NULL as 'NULL';


Enregistrement au format CSV d'une table de données des adresses créées durant les 7 derniers jours sur les communes publiées. Elle contient les champs suivants :

* L'identifiant du point 
* Le nom de la commune et son code INSEE
* L'adresse complète du point
* La date de création du point

 		.. code-block:: sql
			
				\copy (select a.id_point, a.date_creation, a.commune_nom, a.insee_code, a.adresse_complete 
				from adresse.v_point_adresse a, adresse.v_communes_publiees b 
				where  a.insee_code = b.insee_code and (a.date_creation > current_date - integer '7') ) 
				TO 'D:\BD_adresse\bakup_adresses\v_point_adresse_dimanche_creation.csv' DELIMITER ',' CSV HEADER NULL as 'NULL';



3.2 - Traitement FME
---------------------

**Chaque lundi à 4h30 du matin** :

*Vous pouvez télécharger la dernière version du projet FME en cliquant sur le lien ci dessous :*

`Téléchargement du projet FME <https://github.com/sig14/private-doc/releases/download/mailing/mail_depot_bal_laposte.fmw>`_


*Le Workbench FME a été déposé sur le serveur APW65. Suivre le lien ci dessous :*

`Lien projet FME APW65 <file://\\apw65\_FME\ADRESSAGE\mail_depot_bal_laposte.fmw>`_ 


Le traitement se déroule comme suit :

* Jointures des de points adresses n0 - n7 , ne garder que les n0 non joints

.. image:: ../images/Adressage/V_depot_bal/22_mailing_comptage_n0_n7.png
   :width: 680

* comparaisons des points adresses modifiés n7 avec les adresses n0. Ajout champ modif_geom et modif_semantique pour connaitre la modif.

.. image:: ../images/Adressage/V_depot_bal/22_mailing_comparaison_n0__modifn7.png
   :width: 680

* export csv pour piece jointe des adresses suprimees et modifiées


* Comptage Points adresses modfiés durant les 7 derniers jours et non créés durant les 7 derniers jours

.. image:: ../images/Adressage/V_depot_bal/23_mailing_comparaison_n0_n7.png
   :width: 680

* Points adresses créés durant les 7 derniers jours 

.. image:: ../images/Adressage/V_depot_bal/24_mailing_comptage_pts__modif_n7.png
   :width: 1000

* Jointure des comptages et envoi du mail 

.. image:: ../images/Adressage/V_depot_bal/25_mailing_comptage_pts__crees_n7.png
   :width: 1000
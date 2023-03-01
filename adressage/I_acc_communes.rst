

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

.. image:: ../immg/adressage/rapport_adressage_canton_bayeux.png
   :scale: 50

Les statistiques sont calculées avec des expressions QGIS intégrées dans du code HTML. Dans cet exemple ci-dessous, le nombre de communes accompagnées dans le Calvados est calculé avec le champ ``actif`` de la table ``Communes``. Il indique si la commune a engagé une démarche d'adressage avec le CD14) ::

	Nombre de communes engagées dans l'adressage : 
	[%aggregate(layer:='Communes', aggregate:='count', expression:=id_com, filter:=actif ='Oui' )%] 
	/ [%aggregate(layer:='Communes', aggregate:='count', expression:=id_com)%]</b>, 
	soit [%round(100*aggregate(layer:='Communes', aggregate:='count', expression:=id_com, filter:=actif ='Oui')/aggregate(layer:='Communes', aggregate:='count', expression:=id_com),1)%]%

Ce qui donne ::

	Nombre de communes engagées dans l\'adressage : 326 / 528 soit 61.6%



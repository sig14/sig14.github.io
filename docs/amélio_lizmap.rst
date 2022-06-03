Les fonctionnalités ajoutées à LizMap
=====================================

**popup_recherche.js** permet d'ajouter au client
LizMap web des fonctionnalités pour l'utilisateur.

Il fait appel à la feuille de style **popup_style.css** et est en partie dépendant
du script **getData.php** (dossier "php").

Fonction de l'outil :
---------------------

Ce script s'exécute au chargement de la page et ajoute au menu de LizMap un
bouton (BAN) déclenchant l'ouverture d'une fenêtre modale (popup). Cette popup
se lance également, par défaut, une fois la carte chargée.

Cette popup, "Recherche", met à disposition de l'utilisateur 2 champs pour
renseigner, au choix, une adresse ou un nom de commune. Jusqu'à 5 propositions
d'adresses ou de communes correspondantes sont alors affichées, sélectionnables
par l'utilisateur.

Quand l'une ou l'autre est sélectionnée, la popup se referme et la carte se
focalise sur le point ou sur la commune demandée.

Le fonctionnement dans ses grandes lignes :
-------------------------------------------

Le bouton, créé en chaîne de caractère, est ajouté au code html d'un élément
du menu de LizMap. Lors du clic, il déclenche la fonction
``address_researchPopup``. Après la déclaration de cette fonction, un clic est
simulé afin d'avoir l'ouverture initiale souhaitée de la popup.

``address_researchPopup`` ajoute, de la même façon qu'est ajouté le bouton, un
code html à l'élément ``#lizmap-modal`` de LizMap. Cet html contient 2 éléments
input, l'un pour la saisie d'adresse et l'autre pour la saisie de commune.

À chaque élément input est ensuite associé un objet javascript ``autoComplete``,
dont le constructeur est importé.

À chaque changement de valeur d'un champ d'input, une requête est envoyée.
La suite dépend alors du type de recherche choisi :

Adresse :
^^^^^^^^^

Dans le cas de l'adresse, c'est à l'API Adresse nationale, qui renvoie les
adresses correspondant au mieux à ce qui a été saisi.
À l'envoi, les mots-clés "Normandie", "Calvados" et "14" sont ajoutés à ce qui
a été saisi par l'utilisateur afin de favoriser l'apparition d'adresses du
Calvados dans les résultats.

Le nom complet des adresses renvoyées par l'API ainsi que les coordonnées en
longitude et latitude qui y sont associés sont stockées, et chaque adresse
affichée. Lorsque l'utilisateur en sélectionne une, un Point est créé à partir
des coordonnées de cette adresse et passé en paramètre de la méthode
``zoomToExtent()`` de la carte. La popup est ensuite refermée.

Commune :
^^^^^^^^^

Dans le cas du nom de commune, c'est à la base de donnée du SIG du CD14 que
l'expression est envoyée, via un appel au script **getData.php**. La requête SQL
effectuée renvoie, pour chaque commune dont le nom commence par l'expression,
son nom et son extent, c'est à dire les coordonnées du rectangle dans lequel
son territoire s'inscrit. Cependant, seuls 5 noms de commune sont affichés.

Lorsque l'utilisateur sélectionne une commune, son extent est changé en une
liste de coordonnées, qui servent à créer un Bounds ensuite passé en paramètre
de la méthode ``zoomToExtent()`` de la carte. La popup est ensuite refermée.

# Le site "Mon adresse, des services"
**index.html** est un fichier html incluant du javascript, à déployer sur les
serveurs du SIG du CD14.

Il fait appel à la feuille de style **min-style.css** et est également dépendant
du script **getData.php** (dossier "php").

## Fonction de l'outil :

Ce code génère une page web, avec un champ permettant à l'utilisateur de
renseigner une adresse. Jusqu'à 5 propositions d'adresses correspondantes sont
affichées et sélectionnables par l'utilisateur.

Quand une est sélectionnée, diverses informations géographiques viennent remplir
la page, par section, pour renseigner l'utilisateur.

## Le fonctionnement dans ses grandes lignes :

### Le HTML

Le corps principal du html est structuré en une div contenant l'élément input et
une autre contenant l'ensemble des sections et sous-sections accueillant les
résultats. À l'élément input est ensuite associé un objet javascript
``autoComplete``, dont le constructeur est importé.

### Questionnement de l'API Adresse

À chaque changement de valeur de ce champ, une requête est envoyée à l'API
Adresse nationale. Elle renvoie les adresses correspondant au mieux à ce qui lui
est envoyé, mais à l'expression saisie par l'utilisateur sont ajoutés les
mots-clés "Normandie", "Calvados" et "14" permettant de favoriser l'apparition
d'adresses du Calvados dans les résultats.

Le nom complet des adresses renvoyées par l'API ainsi que les coordonnées en
longitude et latitude qui y sont associés sont stockées, et chaque adresse
affichée.

### Questionnement de la BD du SIG :

Lorsque l'utilisateur sélectionne une adresse, la longitude et la latitude
relatives à cette adresse, préalablement stockées, sont envoyés à plusieurs
reprises à **getData.php**, avec des valeurs pour le paramètre "res" différentes
à chaque fois. C'est ce paramètre qui renseigne le script php sur la requête à
utiliser.

Pour chaque requête, les données retournées au format json sont alors ajoutées
à la section portant le nom correspondant.

Ajouter une page
================

Documentation publique
----------------------

Récupérer la documentation
''''''''''''''''''''''''''

Commencez par installer Git sur votre machine, si ça n'est pas déjà fait.
https://git-scm.com/download/win

Utilisez ensuite les scripts trouvables ici_ pour copier le dépôt distant.
  .. _ici: https://github.com/sig14/private-scripts/

Inclure la page à la documentation
''''''''''''''''''''''''''''''''''

Déposez le(s) fichier(s) .rst dans **documentation/docs/source/**

Dans le fichier index.rst, pensez à ajouter chaque page au sommaire :

.. code-block::rst

   .. toctree::

      page1
      page2
      ...
      //Ajouter ici le nom de votre fichier ('calvados' pour 'calvados.rst' par exemple).

Actualiser le dépôt distant
'''''''''''''''''''''''''''

Vous pouvez maintenant lancer les scripts pour pousser les modifications vers
Github. ReadTheDocs va automatiquement lancer une nouvelle compilation de la
documentation, qui sera changée après quelques minutes (pensez à actualiser).

.. note::
   Il est préférable de réaliser les modifications sur votre machine et de les
   envoyer ensuite à Github, mais il est aussi possible d'effectuer les
   modifications directement sur Github.

Documentation privée
--------------------

Récupérer la documentation
''''''''''''''''''''''''''

Commencez par installer Git sur votre machine, si ça n'est pas déjà fait.
https://git-scm.com/download/win

... à compléter

Inclure la page à la documentation
''''''''''''''''''''''''''''''''''

Déposez le(s) fichier(s) .rst dans **docs**

Dans le fichier index.rst, pensez à ajouter chaque page au sommaire :

.. code-block::rst

   .. toctree::

      tutoDoc
      //Ajouter ici le nom de votre fichier ('calvados' pour 'calvados.rst' par exemple).

Actualiser le dépôt distant
'''''''''''''''''''''''''''

... à compléter

Hébergé sur Github Pages, la documentation privée peut mettre jusqu'à une
vingtaine de minutes à s'actualiser. Soyez patients !

.. note::
   Il est préférable de réaliser les modifications sur votre machine et de les
   envoyer ensuite à Github, mais il est aussi possible d'effectuer les
   modifications directement sur Github.

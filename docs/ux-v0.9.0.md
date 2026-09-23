# PatriGest — UX/UI v0.9.0

## Objectif

Simplifier l'utilisation de PatriGest après la mise en place de la
nouvelle identité visuelle.

Principes :

- réduire les doublons de navigation ;
- réserver les boutons aux véritables actions ;
- utiliser des liens ou des onglets pour la navigation ;
- rendre les fonctionnalités accessibles là où l'utilisateur les attend ;
- conserver une interface simple et lisible ;
- conserver la nouvelle identité visuelle PatriGest.

---

## Séparation des usages d'un compte utilisateur

### Règle métier à préserver

Une même adresse e-mail ne doit pas permettre de cumuler :

- un compte permettant à l'utilisateur de créer et gérer ses propres
  dossiers de personnes protégées ;
- un accès obtenu comme collaborateur d'un autre propriétaire,
  qu'il soit en « Lecture seule » ou « Gestionnaire ».

Le rôle « Gestionnaire » attribué dans le cadre d'un partage donne
des droits de gestion sur le dossier partagé.

Il ne doit pas être confondu avec la capacité à créer et gérer ses
propres dossiers de personnes protégées.


### Audit obligatoire avant implémentation

Vérifier les protections actuellement existantes concernant
l'unicité et l'utilisation des adresses e-mail.

Contrôler notamment :

- l'inscription publique ;
- l'envoi d'une invitation de partage ;
- l'acceptation d'une invitation ;
- la création du compte associé à une invitation ;
- les autorisations existantes ;
- les protections backend et base de données ;
- la normalisation des adresses e-mail.

Vérifier explicitement les deux scénarios :

1. une adresse déjà utilisée par un collaborateur tente de créer
   ensuite un compte permettant de gérer ses propres dossiers ;

2. une adresse appartenant déjà à un utilisateur pouvant créer et
   gérer ses propres dossiers reçoit ensuite une invitation de partage.

La règle ne doit pas reposer uniquement sur un contrôle côté
interface.


### Adresse e-mail

Les contrôles doivent être réalisés sur une représentation normalisée
de l'adresse afin d'éviter qu'une différence de casse ou une variation
équivalente contourne les protections existantes.

Ne pas créer de mécanisme artisanal de validation syntaxique si le
système d'authentification assure déjà cette fonction.

Distinguer :

- validité syntaxique de l'adresse ;
- confirmation de possession de l'adresse ;
- unicité de l'adresse ;
- compatibilité de cette adresse avec le type d'accès demandé.


### Message utilisateur

Lorsqu'une adresse ne peut pas être utilisée en raison de cette règle,
afficher une explication compréhensible.

Ne pas présenter l'erreur comme une simple adresse invalide.

Expliquer que cette adresse est déjà associée à un autre type d'accès
PatriGest et qu'une autre adresse e-mail est nécessaire pour créer le
nouvel accès.


### Administration

La page « Comptes utilisateurs » doit permettre de distinguer
clairement :

- les utilisateurs disposant de leurs propres dossiers ;
- les collaborateurs invités sur les dossiers d'un autre propriétaire ;
- le rôle du collaborateur dans chaque accès partagé :
  « Lecture seule » ou « Gestionnaire ».

Ne pas utiliser le terme « Gestionnaire » seul lorsqu'il pourrait être
confondu avec la nature du compte utilisateur.


## 1. Tableau de bord principal

### Cartes de synthèse

État actuel :

- Dossiers actifs ;
- Comptes de gestion à traiter ;
- Actions à traiter.

### Décision

Supprimer ces trois cartes.

Motif :

Les informations sont déjà présentées de manière plus utile juste en dessous :

- les dossiers sont visibles dans « Dossiers suivis » ;
- les comptes de gestion et actions à traiter sont détaillés dans
  « À faire prochainement ».

Les trois compteurs créent donc une répétition sans apporter
d'information directement exploitable.

### Dossiers suivis

Afficher le nombre de dossiers actifs directement dans cette zone.

Exemple à étudier :

« Dossiers suivis (2) »

Conserver :

- les cartes permettant d'ouvrir les dossiers ;
- le lien « Voir tous les dossiers ».

### Nombre important de dossiers

À vérifier avant implémentation :

- comportement actuel avec un grand nombre de dossiers ;
- éviter d'afficher une liste excessivement longue sur le tableau de bord ;
- déterminer éventuellement un nombre maximum de dossiers affichés ;
- conserver « Voir tous les dossiers » pour accéder à la liste complète.

### À faire prochainement

Conserver cette zone.

Elle apporte davantage d'information qu'un simple compteur puisqu'elle
présente :

- le dossier concerné ;
- l'action à réaliser ;
- l'échéance.

### Fil d’Ariane

Le Tableau de bord principal est la racine de l’espace privé.

Décision :
- ne pas afficher de fil d’Ariane sur le Tableau de bord principal ;
- éviter les fils d’Ariane qui répètent uniquement le titre de la page ;
- utiliser le fil d’Ariane lorsqu’une page appartient à une hiérarchie
  et qu’il permet de revenir à un niveau supérieur.

Principe :
le menu principal indique la section courante ;
le fil d’Ariane indique le chemin à l’intérieur d’une section.

## 2. Page Dossiers

### État général

La page est satisfaisante et ne nécessite pas de réorganisation.

### Liste des dossiers

Conserver l'affichage sous forme de cartes :
- une carte par dossier accessible ;
- nom de la personne protégée ;
- commune si renseignée ;
- rôle de l'utilisateur ;
- état actif.

À vérifier avant implémentation :
- comportement actuel avec un nombre important de dossiers ;
- absence de limite ou troncature involontaire.

Cette page étant dédiée à la liste des dossiers, l'affichage de
l'ensemble des dossiers y est pertinent.

### Création d'un dossier

Conserver le bouton orange :

« + Nouveau dossier »

Justification :
il s'agit d'une véritable action de création.

Cela respecte la règle UX v0.9.0 :
- orange = action principale/création ;
- liens/onglets = navigation.

### Fil d'Ariane

Pas nécessaire sur cette page.

« Dossiers » est une section racine directement accessible depuis
le menu principal. Le titre de page et l'état actif du menu suffisent.

## Principes de navigation

### Navigation principale

Le menu gauche constitue la navigation principale de l'espace privé.

Groupe « PRINCIPAL » :
- Tableau de bord
- Dossiers
- Catégories

Conserver le nom « Tableau de bord ».
« PRINCIPAL » reste le nom du groupe et ne devient pas le nom de la page.

Ne pas dupliquer ces trois entrées dans une navigation horizontale
sur desktop.

### Pages racines

Les pages suivantes sont des pages racines :
- Tableau de bord ;
- Dossiers ;
- Catégories.

Décision :
aucun fil d'Ariane sur ces trois pages.

Le titre de la page et l'entrée active du menu gauche suffisent à
indiquer la position de l'utilisateur.

### Navigation contextuelle

Les menus/onglets horizontaux servent uniquement à naviguer à
l'intérieur d'un contexte.

Exemple pour un compte :
- Informations du compte
- Opérations
- Relevés
- Rapprochement

Ils ne doivent pas dupliquer la navigation principale.

### Fil d'Ariane

Le fil d'Ariane apparaît lorsque l'utilisateur descend dans une
hiérarchie.

Exemple :
Dossiers > Personne protégée > Comptes et patrimoine > Compte

Principe :
- menu gauche = section de l'application ;
- onglets = vues/fonctions du contexte courant ;
- fil d'Ariane = chemin hiérarchique ;
- bouton = action ;
- lien = navigation secondaire.

## Règles — Boutons, liens et onglets

### Bouton principal orange

Réservé aux actions principales qui créent, enregistrent ou déclenchent
une opération importante.

Exemples :
- Nouveau dossier
- Nouvelle catégorie
- Ajouter une recette
- Ajouter une dépense
- Ajouter un relevé
- Enregistrer
- Valider

Éviter d'utiliser un bouton orange pour une simple navigation.

### Bouton secondaire

Utilisé pour une action locale ou secondaire sur un objet existant.

Exemples :
- Modifier
- Annuler
- actions secondaires sur une carte ou un élément

Aspect plus discret que l'action principale.

### Lien

Utilisé pour naviguer vers une autre page ou un autre niveau.

Exemples :
- Voir tous les dossiers
- Ouvrir le dossier
- Retour...
- Historique

Une navigation ne doit pas devenir un gros bouton simplement pour
être visible.

### Onglets

Utilisés pour changer de vue à l'intérieur du même contexte.

Exemple compte financier :
- Informations du compte
- Opérations
- Relevés
- Rapprochements

Ne pas dupliquer un onglet par un bouton de navigation placé au-dessus.

### Principe général

- bouton orange = action principale ;
- bouton secondaire = action locale/secondaire ;
- lien = déplacement/navigation ;
- onglet = changement de vue dans le contexte courant.

## Tableau de bord d'un dossier

### Fil d'Ariane

Conserver :

Dossiers > Personne protégée > Tableau de bord

Le tableau de bord d'un dossier appartient à une hiérarchie et le
fil d'Ariane permet de comprendre immédiatement le contexte.

### Actions sous/en face du titre

Supprimer les boutons de navigation :
- Informations du dossier
- Comptes

Ces destinations sont déjà accessibles depuis la navigation du dossier.

Principe :
ne pas dupliquer une entrée de navigation par un bouton placé dans
l'en-tête de la page.

### Cartes du tableau de bord

Conserver l'organisation générale actuelle :

Première ligne :
- Patrimoine financier
- Comptes actifs
- Compte de gestion

Deuxième ligne :
- Dernières opérations
- À faire

Troisième ligne :
- Immobilier
- Dettes

La disposition desktop actuelle est lisible et hiérarchisée.

### Navigation depuis les cartes

Conserver les liens contextuels légers :
- Voir les comptes
- Continuer
- Voir le journal
- Voir les exercices
- accès Immobilier
- accès Dettes

Ces éléments sont des navigations et doivent rester des liens plutôt
que devenir des boutons d'action.

### Responsive

Conserver une grille sur desktop.

Sur mobile :
- une colonne ;
- largeur homogène des cartes ;
- espacements réguliers ;
- ordre logique identique au desktop autant que possible.

## Gestion financière — Comptes et patrimoine

### Fil d'Ariane

Conserver :

Dossiers > Personne protégée > Comptes et patrimoine

### Navigation contextuelle

Conserver les onglets :
- Comptes
- Opérations

Ils permettent de changer de vue dans le même contexte financier.

### Action principale

Conserver le bouton orange :
« + Ajouter un compte »

Il s'agit d'une action de création.

### Synthèse

Conserver :
- Patrimoine total actif
- Comptes actifs

Ces indicateurs résument directement le contenu de la page et ne
nécessitent pas de navigation supplémentaire.

### Comptes

Conserver la séparation :
- Comptes actifs
- Comptes clôturés

Conserver les cartes de comptes comme accès au détail du compte.

Aucun bouton « Ouvrir » supplémentaire n'est nécessaire :
la carte représente elle-même l'objet consultable.

## Gestion financière — Navigation d'un compte

### Page d'entrée d'un compte

Faire de « Opérations du compte » la vue principale d'un compte.

Quel que soit le point d'entrée :
- carte d'un compte depuis « Comptes » ;
- carte d'un solde depuis « Opérations » ;

le clic sur le compte doit ouvrir :
« Opérations du compte ».

Éviter qu'un même objet ouvre une vue différente selon la page
depuis laquelle l'utilisateur y accède.

### Ordre des onglets

Adopter :

1. Opérations du compte
2. Relevés
3. Informations du compte

Justification :
- les opérations constituent l'usage courant du compte ;
- les relevés et rapprochements appartiennent au suivi bancaire ;
- les informations du compte sont consultées ou modifiées plus
  occasionnellement.

### Actions du compte

Conserver dans l'en-tête les véritables actions :
- Ajouter une recette
- Ajouter une dépense
- Effectuer un virement
- Saisie successive

Conserver l'orange pour l'action principale selon le contexte.

### Navigation redondante

Supprimer de la rangée d'actions :
- Relevés
- Informations du compte

Ces destinations sont déjà représentées par les onglets.

Principe :
une destination présente dans la navigation contextuelle ne doit pas
être dupliquée par un bouton dans l'en-tête.

## Gestion financière — Relevés et rapprochements

### Navigation du compte

Adopter quatre onglets :

1. Opérations du compte
2. Relevés
3. Rapprochements
4. Informations du compte

### Relevés

La page « Relevés » reste l'archive documentaire des relevés bancaires.

Conserver notamment :
- Ajouter un relevé ;
- Voir ;
- Télécharger ;
- Modifier lorsque permis ;
- Supprimer lorsque permis ;
- Contrôler le solde.

Le contrôle rapide du solde reste accessible directement depuis
la ligne du relevé.

Prévoir la pagination de la liste des relevés afin d'éviter une page
excessivement longue lorsque l'historique augmente.

### Rapprochements

Créer une page dédiée « Rapprochements ».

Objectif :
rendre immédiatement visible et accessible la fonctionnalité de
rapprochement bancaire.

La page présente une synthèse des relevés et de leur état de contrôle :

- date du relevé ;
- solde du relevé ;
- solde calculé par PatriGest ;
- écart simple ;
- état du contrôle ;
- état du rapprochement détaillé ;
- écart résiduel lorsqu'il existe.

Permettre depuis cette page :
- de commencer un contrôle ;
- de reprendre un brouillon ;
- d'ouvrir un rapprochement détaillé ;
- de consulter un rapprochement validé.

Ne pas dupliquer toutes les fonctions documentaires de la page Relevés.

### Couleurs des écarts

Écart simple :
- 0,00 € : vert ;
- différent de 0,00 € : rouge.

Écart résiduel :
- 0,00 € : vert ;
- différent de 0,00 € : rouge.

Un écart simple non nul peut être expliqué par les opérations en
circulation.

L'écart résiduel représente donc le résultat final du rapprochement
détaillé.

### Principe

Relevés = documents bancaires.

Rapprochements = contrôle et explication de la concordance entre
la banque et PatriGest.

## Gestion financière — Informations du compte

### Navigation

Ordre des onglets :

1. Opérations du compte
2. Relevés
3. Rapprochements
4. Informations du compte

### En-tête

Conserver :
- Modifier

Supprimer :
- Relevés, car cette destination existe dans les onglets ;
- Ajouter un autre compte, car la création d'un compte appartient
  à la page « Comptes et patrimoine ».

### Solde

Conserver la carte « Solde actuel calculé ».

Elle présente immédiatement le solde courant calculé par PatriGest.

### Informations

Conserver et compléter la carte « Informations ».

Afficher les informations bancaires disponibles dans le modèle,
notamment le numéro de compte / IBAN s'ils existent.

Vérifier les champs réellement disponibles avant implémentation.
Ne pas créer de nouvelles données dans le cadre de cette refonte UX.

Harmoniser visuellement cette carte avec la carte
« Solde actuel calculé » :

- ajouter devant « Informations » un pictogramme représentant
  clairement l'information, par exemple une icône « information » ;
- utiliser pour ce pictogramme le même traitement visuel que celui
  de la carte « Solde actuel calculé » ;
- utiliser la même taille, graisse et couleur de titre ;
- conserver le même alignement entre pictogramme et titre.

Les deux cartes étant placées au même niveau, leurs en-têtes doivent
avoir la même hiérarchie visuelle.

### Dernières opérations

Supprimer la carte « Dernières opérations ».

Les opérations disposent désormais d'un onglet dédié
« Opérations du compte ».

Éviter de dupliquer une vue simplifiée du journal dans la page
« Informations du compte ».

### Gestion du compte

Remplacer l'intitulé technique « Cycle de vie du compte »
par « Gestion du compte ».

Présenter séparément les actions sensibles.

#### Clôturer le compte

Ajouter un texte explicatif avant l'action.

Il doit expliquer :
- ce que signifie la clôture ;
- ce qui est conservé ;
- ce qui n'est plus possible après clôture ;
- les conséquences sur le statut du compte et le patrimoine actif.

Le texte doit correspondre au comportement réel de l'application.

Vérifier avant implémentation le fonctionnement actuel de la clôture :
- changement de statut ;
- éventuelle date de clôture ;
- possibilité ou non de nouvelles opérations ;
- incidence sur le patrimoine actif ;
- possibilité ou non de réouverture.

#### Supprimer le compte

Ne plus présenter la suppression comme un simple lien rouge isolé.

Présenter une zone clairement identifiable expliquant :
- dans quelles conditions le compte peut être supprimé ;
- quelles données sont supprimées ou conservées ;
- les conséquences exactes de l'opération ;
- son caractère définitif si la suppression est irréversible.

Prévoir une confirmation explicite avant exécution.

Conserver une présentation rouge pour identifier le caractère
destructif de l'action.

Le texte présenté à l'utilisateur doit correspondre au comportement
réel de l'application, à vérifier avant implémentation.


## Cohérence des pictogrammes dans les cartes

### Principe général

Utiliser les pictogrammes comme éléments d'identification fonctionnelle
et non comme simple décoration.

Lorsqu'une carte représente une fonction ou une catégorie clairement
identifiable et qu'un pictogramme pertinent existe, afficher ce
pictogramme dans son en-tête.

Ne pas ajouter artificiellement un pictogramme lorsqu'il n'apporte
aucune information ou aucun repère supplémentaire.

### Cohérence visuelle

Pour les cartes de même niveau :

- utiliser des pictogrammes de même taille ;
- utiliser des conteneurs de pictogrammes de mêmes dimensions ;
- conserver des espacements identiques entre pictogramme et titre ;
- aligner pictogramme et titre de la même manière ;
- utiliser la même taille de titre ;
- utiliser la même graisse de titre ;
- utiliser la même hiérarchie de couleurs.

Deux cartes comparables ne doivent pas avoir l'une un pictogramme
et un petit titre tandis que l'autre présente un grand titre sans
pictogramme, sauf justification fonctionnelle.

### Couleurs

Les couleurs des pictogrammes peuvent conserver une signification
fonctionnelle lorsqu'elle existe déjà.

Ne pas uniformiser toutes les icônes dans une seule couleur si leurs
couleurs permettent d'identifier utilement leur fonction.

Conserver cependant un traitement graphique homogène :
taille, fond, rayon, marges et alignement.

### Application

Appliquer cette règle progressivement aux cartes existantes,
notamment :

- Patrimoine financier ;
- Comptes actifs ;
- Compte de gestion ;
- Immobilier ;
- Dettes ;
- Solde actuel calculé ;
- Informations du compte ;
- et aux autres cartes fonctionnelles comparables.

Lors de l'implémentation de v0.9.0, vérifier les cartes concernées
dans leur ensemble afin d'éviter des traitements différents pour
une même catégorie de composant.

## Comptes de gestion et exercices de gestion

### Navigation contextuelle

Créer une navigation commune sous forme d'onglets :

1. Comptes de gestion
2. Exercices de gestion

Afficher ces deux onglets sur les deux pages.

Sur la page « Comptes de gestion » :
- « Comptes de gestion » est actif ;
- « Exercices de gestion » permet d'accéder à la gestion des exercices.

Sur la page « Exercices de gestion » :
- « Exercices de gestion » est actif ;
- « Comptes de gestion » permet de revenir aux comptes de gestion.

Cette navigation rend explicite la relation entre les deux fonctions
sans utiliser de boutons d'action pour naviguer.

### Page Comptes de gestion

Conserver le lien :
« Consulter le modèle officiel sur Légifrance ».

Ce lien est spécifique au compte de gestion et ne doit pas être
dupliqué sur la page « Exercices de gestion ».

Supprimer le bloc actuel proposant :
« Gérer les exercices ».

L'accès aux exercices est désormais assuré par l'onglet
« Exercices de gestion ».

Conserver le formulaire permettant de préparer un compte de gestion
lorsqu'aucun exercice ne permet de préremplir automatiquement
la période.

Conserver l'action principale :
« Préparer un compte de gestion ».

### Page Exercices de gestion

Conserver le texte explicatif :

« Les exercices regroupent les opérations saisies sur une période.
Leur création ne déplace ni ne duplique aucune opération. »

Conserver l'action principale :
« Créer un exercice ».

Conserver les actions locales sur chaque exercice :
- Modifier ;
- Clôturer.

### États des comptes de gestion

Les différents états d'un compte de gestion doivent être
immédiatement différenciables visuellement.

Ne pas utiliser la même présentation pour des états fonctionnellement
différents.

Avant implémentation, inventorier les états réellement supportés par
l'application et leur signification.

Définir ensuite une sémantique de couleurs commune.

Orientation visuelle :

- En préparation : gris / neutre ;
- Projet généré : bleu ;
- état finalisé ou validé : vert, s'il existe réellement ;
- état nécessitant une action ou une attention : orange,
  s'il existe réellement ;
- erreur ou situation bloquante : rouge, si un tel état existe.

Les couleurs définitives doivent être déterminées à partir des états
réellement présents dans le modèle et non à partir d'états supposés.

La couleur complète le libellé mais ne doit jamais le remplacer :
l'état doit rester compréhensible sans dépendre de la couleur.

### États des exercices

Vérifier également les états réellement disponibles pour les exercices.

Appliquer la même logique sémantique lorsqu'un état équivalent existe,
afin qu'une couleur conserve la même signification dans toute
l'application.

## Informations du dossier

### Principe

Réorganiser la rubrique « Informations du dossier » afin d'éviter
une page unique trop longue regroupant des informations de natures
très différentes.

Créer quatre onglets contextuels :

1. Personne protégée
2. Situation patrimoniale
3. Gestion
4. Suppression du dossier

Ces onglets appartiennent tous à la rubrique
« Informations du dossier » du menu principal du dossier.

Conserver le fil d'Ariane permettant de situer l'utilisateur dans
le dossier.

Supprimer le bouton « Tableau de bord » actuellement affiché dans
l'en-tête.

Le tableau de bord est déjà accessible depuis la navigation du dossier.


### Onglet « Personne protégée »

Cet onglet constitue la fiche administrative de la personne protégée.

Afficher les cartes :

- Identité ;
- Domicile et résidence ;
- Mesure de protection.

#### Identité

Conserver les informations actuellement disponibles, notamment :

- nom d'usage ;
- prénom(s) ;
- nom de naissance ;
- date de naissance ;
- lieu de naissance ;
- téléphone ;
- email.

Conserver une action locale « Modifier ».

#### Domicile et résidence

Conserver les informations relatives :

- au domicile ;
- à la résidence lorsqu'elle est différente.

Conserver une action locale « Modifier ».

#### Mesure de protection

Conserver les informations relatives à la mesure de protection.

Conserver une action locale « Modifier ».

Ne pas imposer artificiellement une hauteur identique aux différentes
cartes lorsque leur quantité d'information diffère.


### Onglet « Situation patrimoniale »

Cet onglet fournit une synthèse du patrimoine de la personne protégée.

Afficher les cartes :

- Patrimoine actuel ;
- Comptes ;
- Patrimoine immobilier ;
- Dettes et emprunts.


#### Patrimoine actuel

Conserver l'indicateur global du patrimoine actuellement calculé
par PatriGest.

Avant implémentation, vérifier précisément les données entrant dans
ce calcul afin que sa présentation corresponde au calcul réel de
l'application.


#### Comptes

Ajouter une carte synthétique « Comptes ».

Afficher dans l'en-tête de la carte :

- le nombre de comptes actifs ;
- le nombre de comptes clôturés.

Exemple :

Comptes
6 actifs · 4 clôturés

Afficher ensuite les comptes actifs sous forme de lignes compactes.

Pour chaque compte, afficher au minimum :

- le nom ou libellé du compte ;
- son solde actuel calculé.

Ne pas afficher individuellement les comptes clôturés dans cette
synthèse.

Ajouter un lien contextuel :

« Voir les comptes → »

menant à « Comptes et patrimoine ».

Cette carte reste une synthèse et ne doit pas reproduire toutes les
fonctions de la page de gestion des comptes.


#### Patrimoine immobilier

Afficher une synthèse comprenant :

- le nombre de biens renseignés ;
- la valeur connue lorsqu'elle est disponible.

Conserver un accès léger vers la gestion des biens.

Éviter un gros bouton de navigation lorsqu'un lien contextuel suffit.


#### Dettes et emprunts

Afficher une synthèse comprenant :

- le nombre de dettes ou emprunts actifs ;
- leur montant global si cette information existe et est pertinente.

Lorsque aucune dette n'est renseignée, proposer l'action permettant
de commencer leur saisie.


### Onglet « Gestion »

Cet onglet regroupe les informations de synthèse relatives à la
gestion du dossier.

Afficher notamment :

- l'exercice de gestion courant ;
- l'état du compte de gestion correspondant lorsqu'il existe.


#### Exercice de gestion

Afficher :

- l'état de l'exercice ;
- sa période.

Ne plus afficher de bouton « Gérer les exercices ».

L'accès complet aux exercices est assuré par la rubrique
« Comptes de gestion » et ses onglets :

- Comptes de gestion ;
- Exercices de gestion.

Un lien contextuel léger peut être utilisé si un accès direct depuis
la synthèse est utile.


#### Compte de gestion

Afficher une synthèse du compte de gestion correspondant à l'exercice,
lorsqu'il existe.

Afficher au minimum les informations pertinentes disponibles,
par exemple :

- année ;
- état du compte de gestion.

Exemple :

Compte de gestion 2026
En préparation

Permettre un accès contextuel vers le compte de gestion concerné.

Ne pas reproduire dans cet onglet les fonctions complètes de la page
« Comptes de gestion ».


### Onglet « Suppression du dossier »

Isoler complètement la suppression définitive des autres informations
du dossier.

Cette page ne doit pas être une simple carte contenant un lien rouge.

Afficher une explication claire avant toute action.


#### Conditions de suppression

Expliquer :

- dans quelles conditions le dossier peut être supprimé ;
- quelles données associées empêchent actuellement sa suppression ;
- ce que l'utilisateur doit supprimer, clôturer ou traiter auparavant ;
- quelles données seront supprimées ;
- si la suppression est irréversible.

Avant implémentation, vérifier le comportement réel de l'application
et les protections existantes afin que les explications correspondent
exactement au fonctionnement de PatriGest.


#### Action destructive

Afficher clairement l'action :

« Supprimer le dossier »

Utiliser le traitement visuel réservé aux actions destructives.

Ne pas utiliser l'orange de l'action principale normale pour une
suppression définitive.

Prévoir une confirmation explicite avant exécution.

La confirmation doit rappeler le caractère définitif de l'opération
lorsque celle-ci est irréversible.


## Pictogrammes — Informations du dossier

Appliquer la convention générale des pictogrammes à l'ensemble des
cartes des quatre onglets.

Pictogrammes attendus :

### Personne protégée

- Identité : personne / identité ;
- Domicile et résidence : domicile / localisation ;
- Mesure de protection : protection / justice.

### Situation patrimoniale

- Patrimoine actuel : patrimoine / finance ;
- Comptes : compte bancaire ;
- Patrimoine immobilier : immobilier ;
- Dettes et emprunts : dette / emprunt.

### Gestion

- Exercice de gestion : calendrier / période ;
- Compte de gestion : document / compte de gestion.

Vérifier que chaque pictogramme représente réellement la fonction de
la carte.

Pour les cartes de même niveau, harmoniser :

- dimensions du pictogramme ;
- dimensions de son conteneur ;
- alignement ;
- espacement entre pictogramme et titre ;
- taille du titre ;
- graisse du titre ;
- traitement des couleurs.

Ne pas ajouter un pictogramme uniquement à titre décoratif.


## Responsive — Informations du dossier

Sur desktop :

- afficher les quatre onglets sur une même ligne lorsque l'espace
  disponible le permet ;
- organiser les cartes de chaque onglet dans une grille adaptée à
  leur contenu.

Sur mobile :

- conserver l'accès clair aux quatre vues ;
- permettre aux onglets de s'adapter à la largeur disponible sans
  réduire excessivement leur lisibilité ;
- afficher les cartes sur une seule colonne ;
- conserver des espacements homogènes.

## Partage du dossier

### Principe

Réorganiser la rubrique « Partage du dossier » autour de deux fonctions
clairement identifiables :

1. Inviter un collaborateur
2. Collaborateurs

Afficher ces fonctions sous forme d'onglets contextuels.

L'onglet « Inviter un collaborateur » est la vue affichée par défaut.

Ne pas créer d'onglets séparés « Propriétaire » et « Invitations ».

Le propriétaire constitue une information de contexte du partage.

Les invitations appartiennent au processus d'invitation et restent
donc dans la vue « Inviter un collaborateur ».


### Onglet « Inviter un collaborateur »

Organiser la page en trois zones :

1. Propriétaire
2. Inviter un collaborateur
3. Invitations envoyées


#### Propriétaire

Afficher une carte synthétique permettant d'identifier clairement
le propriétaire du dossier.

Afficher les informations pertinentes disponibles, notamment :

- nom et prénom ;
- email lorsqu'il est disponible.

Cette carte est informative et ne nécessite pas d'onglet dédié.


#### Inviter un collaborateur

Afficher une carte dédiée à la création d'une invitation.

Conserver :

- adresse email ;
- choix du rôle ;
- action « Inviter ».

Le bouton « Inviter » constitue l'action principale de cette vue
et utilise le traitement visuel d'une action principale.

Les rôles proposés doivent correspondre aux rôles réellement
supportés par l'application.


#### Invitations envoyées

Repenser la présentation actuelle afin d'éviter une longue liste
mélangeant invitations actives et historique ancien.

Donner la priorité aux invitations nécessitant encore une attention,
notamment les invitations en attente lorsqu'elles existent.

Pour chaque invitation active, afficher de manière lisible :

- destinataire ;
- rôle proposé ;
- date d'envoi ;
- date d'expiration lorsqu'elle existe ;
- état ;
- actions encore possibles.

Avant implémentation, inventorier les états réellement supportés
par le système d'invitation et les actions possibles pour chacun.


#### Historique des invitations

Ne pas afficher en permanence un historique très long des invitations
terminées.

Séparer :

- les invitations encore actives ;
- les invitations terminées.

Les invitations acceptées, annulées ou expirées peuvent être
regroupées dans une section secondaire :

« Historique des invitations »

Cette section peut être repliable ou présenter un nombre limité
d'éléments récents avec un accès permettant de consulter la suite.

Le choix définitif doit tenir compte :

- du volume réel des invitations ;
- des mécanismes de pagination existants ;
- de la nécessité éventuelle d'ajouter une pagination.

Ne supprimer aucune donnée d'historique uniquement pour simplifier
l'interface.


### Onglet « Collaborateurs »

Afficher uniquement les utilisateurs disposant actuellement d'un
accès au dossier.

Pour chaque collaborateur, présenter une ligne compacte comprenant :

- identité ;
- email lorsque pertinent ;
- rôle actuel ;
- action « Modifier » ;
- action « Retirer ».

Ne pas afficher en permanence un sélecteur de rôle sur chaque ligne.

La ligne constitue principalement une vue de consultation.

Le rôle affiché doit toujours correspondre au rôle réellement
enregistré pour ce collaborateur.


### Rôles des collaborateurs

Différencier visuellement les rôles.

Rôles actuellement identifiés et à vérifier dans le modèle :

- Lecture seule ;
- Gestionnaire.

Avant implémentation, inventorier tous les rôles réellement supportés
par l'application.

Définir ensuite une couleur sémantique stable pour chaque rôle.

Orientation :

- Lecture seule : gris / neutre ;
- Gestionnaire : couleur de marque distincte.

Le rôle doit toujours être écrit explicitement.

La couleur constitue un repère supplémentaire et ne remplace jamais
le libellé.


### Modification d'un collaborateur

Ne plus utiliser le fonctionnement actuel composé d'un sélecteur de
rôle affiché en permanence suivi d'un bouton « Modifier ».

Afficher normalement le rôle actuel sous forme de badge.

L'action secondaire « Modifier » ouvre une fenêtre de modification
dédiée.


#### Fenêtre de modification

Afficher :

- l'identité du collaborateur ;
- son email lorsqu'il est pertinent ;
- son rôle actuel ;
- un sélecteur permettant de choisir le nouveau rôle ;
- une action « Annuler » ;
- une action de validation.

Le sélecteur doit être initialisé avec le rôle réellement enregistré
pour le collaborateur.

Ne jamais sélectionner systématiquement le premier rôle disponible
comme valeur par défaut.


#### Point de contrôle obligatoire sur le rôle

Un problème a été constaté dans l'interface actuelle :

le sélecteur peut rester positionné par défaut sur « Lecture seule »
au lieu de refléter correctement le rôle réellement enregistré.

Avant implémentation, vérifier :

- la valeur du rôle enregistrée dans les données ;
- la valeur récupérée par l'interface ;
- l'initialisation du composant de sélection ;
- la correspondance entre valeurs techniques et libellés affichés ;
- le comportement pour « Lecture seule » ;
- le comportement pour « Gestionnaire » ;
- les autres rôles éventuels ;
- la valeur affichée immédiatement après modification ;
- la valeur affichée après rechargement complet de la page.

La fenêtre de modification doit toujours s'ouvrir avec le rôle réel
du collaborateur déjà sélectionné.

Après validation, le badge affiché dans la liste doit immédiatement
refléter le rôle réellement enregistré.


### Retrait d'un collaborateur

L'action « Retirer » correspond à la suppression de l'accès du
collaborateur au dossier.

La distinguer visuellement des actions ordinaires.

Utiliser un traitement rouge / destructif pour « Retirer ».

Ne pas utiliser l'orange réservé aux actions principales normales.


#### Confirmation du retrait

Ne pas retirer immédiatement le collaborateur au premier clic.

Afficher une fenêtre de confirmation indiquant clairement :

- l'identité du collaborateur concerné ;
- qu'il va perdre son accès au dossier ;
- les conséquences exactes de cette action selon le comportement
  réel de PatriGest.

Proposer :

- « Annuler » ;
- « Retirer l'accès ».

L'action finale « Retirer l'accès » utilise le traitement destructif
rouge.


#### Comportement du retrait à vérifier

Avant implémentation, vérifier ce que fait réellement le retrait
d'un collaborateur :

- suppression de son autorisation d'accès ;
- conservation ou non d'un historique de cette autorisation ;
- incidence éventuelle sur les invitations existantes ;
- possibilité de réinviter ultérieurement cette personne ;
- autres conséquences éventuelles.

Le texte de confirmation doit décrire exactement le comportement
réel de l'application.


### Présentation des actions d'un collaborateur

Pour chaque collaborateur :

- afficher le rôle sous forme de badge ;
- « Modifier » est une action secondaire normale ;
- « Retirer » est une action destructive rouge.

Éviter d'afficher simultanément un sélecteur de rôle, un bouton
« Modifier » et un bouton « Retirer » directement dans chaque ligne.

La modification du rôle est effectuée dans la fenêtre dédiée.


### Pictogrammes — Partage du dossier

Appliquer la convention générale des pictogrammes.

Prévoir notamment des pictogrammes adaptés pour :

- Propriétaire : personne / propriétaire ;
- Inviter un collaborateur : ajout d'utilisateur / invitation ;
- Invitations envoyées : invitation / courrier ;
- Collaborateurs : groupe / utilisateurs ;
- permissions ou rôles lorsque le pictogramme apporte réellement
  une information supplémentaire.

Dans les fenêtres de modification ou de confirmation, ne pas ajouter
des pictogrammes uniquement à titre décoratif.

Pour les cartes et sections de même niveau, harmoniser :

- taille des pictogrammes ;
- dimensions de leurs conteneurs ;
- alignement ;
- espacement entre pictogramme et titre ;
- taille des titres ;
- graisse des titres ;
- traitement des couleurs.


### Couleurs et statuts

Utiliser une sémantique visuelle cohérente pour les rôles et les états.

Les couleurs doivent compléter le texte et ne jamais être le seul
moyen de comprendre un rôle ou un état.

Avant implémentation, inventorier les états réellement disponibles
pour les invitations, notamment :

- en attente ;
- acceptée ;
- annulée ;
- expirée ;
- autres états éventuels.

Définir ensuite leur traitement visuel de manière cohérente avec les
autres statuts de PatriGest.

Les actions destructives telles que « Retirer » utilisent le rouge
et non la couleur orange des actions principales normales.


### Responsive

Sur desktop :

- afficher les deux onglets sur une même ligne ;
- privilégier des lignes compactes pour les collaborateurs ;
- privilégier également une présentation compacte pour les
  invitations plutôt que de grandes cartes individuelles.

Sur mobile :

- conserver un accès clair aux deux onglets ;
- afficher les informations sans débordement horizontal ;
- adapter les actions secondaires à la largeur disponible ;
- conserver le rôle clairement visible sans afficher en permanence
  son sélecteur de modification.

  ## Mon compte

### Principe

Réorganiser la page « Mon compte » afin de ne plus présenter dans une
seule longue page des fonctions de natures différentes.

Créer quatre onglets contextuels :

1. Profil
2. Adresse e-mail
3. Sécurité
4. Suppression du compte

L'onglet « Profil » constitue la vue affichée par défaut.

Conserver « Mon compte » comme entrée unique dans le menu principal.
Les quatre vues restent internes à cette rubrique.


### Onglet « Profil »

Regrouper les informations personnelles de l'utilisateur.

Afficher une carte « Profil » contenant notamment :

- prénom ;
- nom ;
- autres informations personnelles réellement disponibles
  lorsqu'elles sont pertinentes.

Conserver l'action permettant d'enregistrer les modifications du
profil.


#### Statut du compte

Intégrer dans cette vue le statut actuellement présenté dans la carte
séparée « Compte ».

Exemple :

Statut
Compte actif

Ne pas créer un onglet « Compte » uniquement pour afficher cette
information.

Le statut peut être présenté sous forme de badge lorsqu'une
différenciation visuelle est utile.

Avant implémentation, vérifier les différents statuts de compte
réellement supportés par l'application.


### Onglet « Adresse e-mail »

Regrouper exclusivement les fonctions relatives à l'adresse e-mail
utilisée pour se connecter à PatriGest.

Afficher :

- adresse e-mail actuelle ;
- mot de passe actuel lorsque sa saisie est nécessaire ;
- nouvelle adresse e-mail ;
- confirmation de la nouvelle adresse e-mail ;
- informations relatives à l'éventuelle confirmation de la nouvelle
  adresse.

Conserver l'action :

« Modifier mon adresse e-mail »

Le texte explicatif doit correspondre au fonctionnement réel du
processus d'authentification et de confirmation.


### Onglet « Sécurité »

Regrouper les fonctions relatives à la sécurité du compte.

Dans l'état actuel de l'application, afficher principalement la
modification du mot de passe.

Afficher :

- mot de passe actuel ;
- nouveau mot de passe ;
- confirmation du nouveau mot de passe ;
- règles applicables au nouveau mot de passe.

Conserver l'action :

« Modifier le mot de passe »

Si de nouvelles fonctions de sécurité sont ajoutées ultérieurement,
elles pourront naturellement rejoindre cet onglet.


### Onglet « Suppression du compte »

Isoler complètement la suppression du compte utilisateur des
paramètres ordinaires.

Cette vue constitue une zone sensible et doit clairement expliquer
les conséquences et les conditions de la suppression avant de
proposer l'action destructive.


#### Explications

Conserver et améliorer les informations actuellement présentées.

Expliquer notamment :

- si la suppression est irréversible ;
- quelles données personnelles sont supprimées ;
- quelles données métier ou historiques sont éventuellement
  conservées ;
- dans quelles situations la suppression est interdite ;
- quelles actions doivent être effectuées avant de pouvoir supprimer
  le compte.

L'interface actuelle indique notamment que la suppression peut être
bloquée lorsque l'utilisateur :

- possède encore un dossier ;
- est administrateur PatriGest.

Elle indique également que les dossiers dont l'utilisateur est
propriétaire doivent auparavant être transférés ou supprimés.

Avant implémentation, vérifier ces règles dans le comportement réel
de l'application.

Ne pas modifier les explications sur la seule base du texte actuel
si le comportement technique diffère.


#### Conditions bloquantes

Lorsque la suppression n'est pas actuellement possible, expliquer
précisément pourquoi.

Éviter de présenter une action de suppression utilisable si les
conditions nécessaires ne sont pas satisfaites.

Lorsque cela est possible, indiquer clairement ce que l'utilisateur
doit faire pour lever le blocage.


#### Action destructive

Afficher l'action :

« Supprimer mon compte »

Utiliser le traitement visuel rouge réservé aux actions destructives.

Ne pas utiliser l'orange des actions principales ordinaires.

Ne pas effectuer la suppression au premier clic.


#### Confirmation

Afficher une confirmation explicite avant toute suppression.

La confirmation doit rappeler :

- le compte concerné ;
- le caractère définitif de l'opération lorsqu'elle est irréversible ;
- les principales conséquences de la suppression.

L'action finale de confirmation utilise également le traitement
destructif rouge.


### Pictogrammes — Mon compte

Appliquer la convention générale des pictogrammes aux différentes
vues de « Mon compte ».

Prévoir notamment :

- Profil : utilisateur / identité ;
- Adresse e-mail : enveloppe / e-mail ;
- Sécurité : cadenas / bouclier ;
- Suppression du compte : suppression / avertissement.

Les pictogrammes doivent aider à identifier immédiatement la fonction
de chaque vue.

Pour les cartes et sections de même niveau, harmoniser :

- taille du pictogramme ;
- dimensions de son conteneur ;
- alignement ;
- espacement entre pictogramme et titre ;
- taille du titre ;
- graisse du titre ;
- traitement des couleurs.

Pour « Suppression du compte », le pictogramme peut utiliser la
sémantique destructive rouge.

Ne pas ajouter de pictogrammes supplémentaires uniquement à titre
décoratif.


### Actions et couleurs

Conserver la distinction entre :

- action normale de sauvegarde ou modification ;
- action destructive.

Les actions telles que :

- Enregistrer le profil ;
- Modifier mon adresse e-mail ;
- Modifier le mot de passe ;

utilisent le traitement normal des actions de formulaire.

« Supprimer mon compte » utilise exclusivement le traitement
destructif rouge.


### Responsive

Sur desktop :

- afficher les quatre onglets sur une même ligne lorsque l'espace
  disponible le permet ;
- limiter la largeur des formulaires afin de conserver une bonne
  lisibilité.

Sur mobile :

- conserver un accès clair aux quatre vues ;
- adapter les onglets à la largeur disponible ;
- afficher les champs sur une seule colonne lorsque nécessaire ;
- conserver les explications de sécurité et de suppression
  parfaitement lisibles.

  ## Historique des versions

### Structure

Conserver la présentation actuelle de la page.

Chaque version reste présentée dans une carte comprenant notamment :

- numéro de version ;
- date de publication ;
- titre ;
- résumé ;
- liste des principales nouveautés.

Conserver l'ordre chronologique décroissant afin que la version la
plus récente apparaisse en premier.

Ne pas ajouter d'onglets, de filtres ou de recherche tant que le
volume des versions ne le justifie pas.

### Pagination

Ajouter une pagination afin d'éviter que la page continue à
s'allonger indéfiniment au fil des versions.

Afficher 10 versions par page.

Prévoir une navigation simple :

- Précédent ;
- Page X sur Y ;
- Suivant.

La pagination doit conserver l'ordre chronologique décroissant.

Vérifier lors de l'implémentation que le chargement des versions est
lui-même paginé et qu'il ne consiste pas uniquement à charger toutes
les versions puis à en masquer une partie côté interface.

### Pictogrammes

Ne pas ajouter systématiquement de pictogramme aux cartes de version.

Dans cette page, le numéro de version, la date et le titre constituent
déjà des repères visuels suffisants.

Respecter le principe général :
un pictogramme est utilisé lorsqu'il apporte un repère fonctionnel
utile, et non uniquement à titre décoratif.

### Responsive

Conserver la présentation actuelle en cartes.

Sur mobile :

- conserver une seule colonne ;
- préserver la lisibilité du numéro de version, de la date et du titre ;
- adapter la pagination à la largeur disponible.

## Déconnexion

### Confirmation

Ne plus déconnecter immédiatement l'utilisateur lorsqu'il clique sur
« Déconnexion » dans le menu principal.

Le clic sur « Déconnexion » ouvre une fenêtre de confirmation.

Afficher :

« Se déconnecter de PatriGest ? »

avec une explication :

« Vous allez être déconnecté de votre session et redirigé vers la
page d'accueil. »

Proposer deux actions :

- Annuler ;
- Se déconnecter.

« Annuler » ferme la fenêtre sans aucune autre action.

« Se déconnecter » :
- ferme la session de l'utilisateur ;
- applique le mécanisme de déconnexion existant ;
- redirige ensuite vers la page d'accueil publique.


### Traitement visuel

La déconnexion est une action sensible mais non destructive.

Ne pas utiliser le traitement rouge réservé notamment à :

- la suppression ;
- le retrait d'un accès ;
- les autres actions destructives.

Utiliser le traitement normal d'une action principale pour
« Se déconnecter ».


### Sécurité et comportement

Ne modifier ni contourner le mécanisme d'authentification existant.

La fenêtre constitue uniquement une confirmation avant l'exécution
de la déconnexion actuelle.

Vérifier également le comportement des éventuelles protections déjà
existantes contre la perte de modifications non enregistrées.

Ne pas introduire dans ce chantier un nouveau mécanisme global de
gestion des formulaires non enregistrés s'il n'existe pas déjà.


### Pictogramme

Conserver le pictogramme de déconnexion dans le menu.

Dans la fenêtre de confirmation, ne pas ajouter de pictogramme
uniquement à titre décoratif.

## Fenêtres de dialogue — comportement après validation

### Principe général

Uniformiser le comportement des fenêtres de dialogue contenant
un formulaire de création ou de modification.

Une fenêtre ne doit pas rester dans son état d'édition après qu'une
opération a été exécutée avec succès.

Le comportement doit permettre à l'utilisateur de distinguer
immédiatement :

- l'état d'édition ;
- l'enregistrement en cours ;
- la réussite de l'opération ;
- l'échec éventuel de l'opération.


### État initial — édition

Lors de l'ouverture d'une fenêtre de modification, afficher :

- les informations ou champs modifiables ;
- l'action « Annuler » ;
- l'action principale correspondant à l'opération, par exemple :
  - Modifier ;
  - Enregistrer ;
  - Valider.

Les champs doivent être initialisés avec les valeurs réellement
enregistrées.


### Pendant l'enregistrement

Lorsque l'utilisateur valide le formulaire :

- empêcher les validations multiples ;
- désactiver temporairement les actions concernées ;
- indiquer l'enregistrement en cours lorsque l'opération n'est pas
  instantanée.

Ne pas permettre plusieurs soumissions simultanées du même formulaire.


### Après réussite

Lorsque l'opération a réussi, faire passer la fenêtre dans un état
de confirmation.

Ne plus afficher :

- « Annuler » ;
- « Modifier » ;
- « Enregistrer » ;
- « Valider » ;
- ou toute autre action ayant déjà été exécutée.

Afficher clairement le message de réussite.

Exemples :

« Les modifications ont été enregistrées. »

« Le rôle du collaborateur a été modifié. »

« Les informations ont été mises à jour. »

Afficher ensuite une seule action :

« Fermer »

Le bouton « Fermer » ferme la fenêtre.

Utiliser le libellé « Fermer » plutôt que « Fermeture ».


### Mise à jour de la page

Après une modification réussie, les informations visibles derrière
la fenêtre doivent déjà refléter les nouvelles données lorsque cela
est techniquement possible.

Après fermeture de la fenêtre, l'utilisateur doit voir la valeur
réellement enregistrée sans devoir actualiser manuellement la page.

Vérifier également la persistance de la modification après un
rechargement complet de la page.


### En cas d'échec

Si l'opération échoue, ne pas passer à l'état de confirmation.

Conserver le formulaire et les données saisies lorsque cela est
possible.

Afficher clairement le message d'erreur.

Conserver les actions permettant :

- de corriger les informations ;
- de réessayer ;
- ou d'annuler.

Ne jamais afficher le bouton unique « Fermer » comme si l'opération
avait réussi lorsque l'enregistrement a échoué.


### Fermeture manuelle

Avant validation, la fermeture par « Annuler » ne doit effectuer
aucune modification.

Après réussite, « Fermer » ne déclenche aucune nouvelle opération :
l'enregistrement a déjà été effectué.


### Point de contrôle transversal

Lors de l'implémentation UX v0.9.0, inventorier les fenêtres de
dialogue existantes contenant des opérations de création,
modification ou validation.

Vérifier notamment les fenêtres concernant :

- les comptes ;
- les opérations ;
- les relevés ;
- les rapprochements ;
- les comptes de gestion ;
- les exercices de gestion ;
- les informations du dossier ;
- le partage du dossier et les collaborateurs ;
- les paramètres de « Mon compte » ;
- toute autre fenêtre utilisant le même composant ou le même
  comportement.

Rechercher particulièrement les fenêtres qui affichent actuellement
un message vert de réussite tout en laissant visibles les boutons
« Annuler » et « Modifier/Enregistrer ».

Les harmoniser selon la présente règle.


### Pictogrammes et messages d'état

Un message de réussite peut utiliser un pictogramme de confirmation
lorsque cela améliore sa compréhension.

Conserver une présentation homogène dans toute l'application :

- réussite : traitement positif ;
- erreur : traitement d'erreur ;
- avertissement : traitement d'avertissement.

La couleur ne doit jamais être le seul moyen d'indiquer le résultat
de l'opération.

## Administration — architecture générale

### Navigation

Réorganiser le groupe « ADMINISTRATION » du menu gauche.

Afficher :

1. Tableau de bord
2. Inscriptions à valider
3. Comptes utilisateurs
4. Communication utilisateurs

Renommer l'entrée actuelle « Administration » en
« Tableau de bord ».

« ADMINISTRATION » reste le nom de l'espace administratif.

Ne pas ajouter d'onglets horizontaux reproduisant ces quatre
entrées du menu gauche.


### Fil d'Ariane

Le tableau de bord constitue la racine de l'administration et
n'affiche pas de fil d'Ariane.

Pour les pages de niveau inférieur, conserver :

Administration > Inscriptions à valider

Administration > Comptes utilisateurs

Administration > Communication utilisateurs


## Tableau de bord administrateur

Conserver les indicateurs :

- Comptes utilisateurs ;
- Inscriptions à valider ;
- Invitations en attente.

Une carte de synthèse disposant d'une destination fonctionnelle
pertinente doit être cliquable.

Conserver :

- Comptes utilisateurs → Comptes utilisateurs ;
- Inscriptions à valider → Inscriptions à valider.

Avant de modifier « Invitations en attente », vérifier :

- ce que cet indicateur compte exactement ;
- l'origine de ces invitations ;
- les actions administratives réellement disponibles ;
- la destination fonctionnelle pertinente.

Ne pas créer une page artificielle uniquement pour rendre
l'indicateur cliquable.

Conserver la zone « À traiter » pour les éléments nécessitant
une intervention administrative.

Retirer du tableau de bord la fonction actuelle
« Information des utilisateurs ».

Cette fonction devient une rubrique administrative dédiée.


## Communication utilisateurs

Créer une page administrative dédiée à la communication relative
aux nouvelles versions de PatriGest.

Y déplacer les fonctions actuellement présentes dans
« Information des utilisateurs ».

Afficher notamment :

- version concernée ;
- titre de la version ;
- résumé ;
- nombre de destinataires ;
- statistiques d'envoi disponibles ;
- choix du destinataire de test ;
- envoi d'un e-mail de test ;
- envoi de l'information aux utilisateurs concernés.

Conserver les protections et mécanismes d'envoi existants.

Appliquer les règles générales des fenêtres de confirmation et
des états de réussite.


## Inscriptions à valider

Conserver la séparation entre :

- inscriptions confirmées en attente ;
- éventuel historique encore nécessaire.

Supprimer les libellés anglais de l'interface.

Notamment, ne plus afficher « Approved ».

Avant modification, inventorier les valeurs techniques et tous
les états réellement supportés.

Définir pour chaque état :

- un libellé français ;
- une couleur sémantique cohérente ;
- les actions éventuellement disponibles.

La couleur complète le libellé et ne le remplace jamais.


### Historique de l'ancien système

Auditer l'utilité actuelle de la section
« Historique de l'ancien système ».

Vérifier :

- pourquoi ces données sont encore affichées ;
- si elles ont encore une utilité administrative ;
- si la période transitoire est terminée ;
- si elles doivent rester accessibles à long terme.

Ne supprimer aucune donnée ou fonctionnalité sans avoir vérifié
son rôle réel.


## Comptes utilisateurs

### Principe

La liste doit permettre à l'administrateur de distinguer :

- le compte utilisateur PatriGest ;
- les dossiers dont l'utilisateur est propriétaire ;
- ses accès comme gestionnaire ;
- ses accès en lecture seule.

Le nombre de « Dossiers possédés » ne suffit pas à représenter
les droits d'un utilisateur.


### Tableau

Étudier une présentation comprenant notamment :

- Nom ;
- E-mail ;
- Date d'inscription ;
- Statut ;
- Dossiers possédés ;
- Accès gestionnaire ;
- Accès lecture seule ;
- Actions.

Avant implémentation, vérifier le modèle de données et les rôles
réellement disponibles.

Éviter toute stratégie provoquant des requêtes N+1 lorsque le
nombre d'utilisateurs augmente.

Prévoir une pagination si le volume de comptes le nécessite.


### Statuts

Présenter le statut du compte sous forme de badge.

Inventorier les différents statuts réellement supportés avant de
définir leurs couleurs.

Le libellé reste obligatoire : la couleur ne doit jamais constituer
la seule indication du statut.


### Renvoyer l'e-mail d'activation

Remplacer le simple lien de fin de ligne par une action clairement
identifiée.

Avant envoi, afficher si nécessaire une confirmation indiquant
notamment l'adresse concernée.

Après réussite :

- afficher le message de confirmation ;
- supprimer les actions « Annuler » et « Envoyer » ;
- afficher uniquement « Fermer ».

Vérifier avant implémentation dans quelles situations cette action
est réellement pertinente.


### Suppression d'un utilisateur

Présenter « Supprimer l'utilisateur » comme une action destructive.

Utiliser le traitement rouge.

Ne jamais supprimer immédiatement l'utilisateur au premier clic.

Afficher une fenêtre de confirmation expliquant :

- l'utilisateur concerné ;
- les conséquences de la suppression ;
- les données supprimées ;
- les données éventuellement conservées ;
- les accès concernés ;
- le caractère irréversible lorsque c'est le cas.

Avant implémentation, auditer les protections backend existantes
et les conditions permettant ou interdisant une suppression.


### Utilisateur non supprimable

Ne pas se limiter à afficher « Non supprimable ».

Permettre à l'administrateur de comprendre la raison réelle du
blocage.

Vérifier notamment les contraintes liées :

- aux dossiers possédés ;
- au rôle platform_admin ;
- aux autres dépendances ou règles existantes.

Le texte présenté doit correspondre aux protections réellement
appliquées par l'application.


## Mon compte — administrateur

Appliquer la même organisation que pour un utilisateur standard :

1. Profil
2. Adresse e-mail
3. Sécurité
4. Suppression du compte

Réutiliser autant que possible les mêmes composants et les mêmes
règles UX.


## Déconnexion — administrateur

Appliquer exactement la règle générale de déconnexion.

Un clic sur « Déconnexion » ouvre une confirmation.

Ne pas fermer immédiatement la session.

Après confirmation, appliquer le mécanisme de déconnexion existant
puis rediriger vers la page publique prévue.


## Fenêtres de dialogue — administration

Appliquer intégralement la règle transversale définie pour les
fenêtres de dialogue de PatriGest.

Après réussite d'une opération :

- ne plus laisser le formulaire en état d'édition ;
- masquer « Annuler » ;
- masquer l'action déjà exécutée ;
- afficher le message de réussite ;
- afficher uniquement « Fermer ».

Vérifier l'ensemble des fenêtres et actions administratives pendant
l'implémentation v0.9.0.


## Pictogrammes — administration

Appliquer la convention générale des pictogrammes.

Prévoir notamment des pictogrammes cohérents pour :

- Tableau de bord : pilotage / tableau ;
- Inscriptions à valider : validation / inscription ;
- Comptes utilisateurs : utilisateurs ;
- Communication utilisateurs : annonce / courrier.

Harmoniser :

- taille ;
- conteneur ;
- alignement ;
- espacement ;
- traitement des couleurs.

Ne pas multiplier les pictogrammes à titre décoratif.


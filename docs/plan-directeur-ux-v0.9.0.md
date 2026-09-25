# PatriGest — Plan directeur UX/UI v0.9.0

**Statut :** document de pilotage  
**Version de référence :** v0.8.0  
**Cible envisagée :** v0.9.0  
**Date :** septembre 2026

> Ce document ne remplace ni `audit-ergonomie-parcours-utilisateur.md` ni `ux-v0.9.0.md`. Il les consolide afin de définir l'ordre de travail, les dépendances et les contrôles nécessaires avant implémentation.

## 1. Rôle des trois documents

- **Audit ergonomique** : conserve l'historique de l'audit fonctionnel et métier, les constats, règles métier et sujets encore à étudier.
- **UX v0.9.0** : conserve les décisions détaillées prises pendant la revue écran par écran.
- **Plan directeur** : pilote l'implémentation et évite les doublons, les décisions obsolètes et les audits Codex inutiles.

## 2. Règle de priorité

En cas de divergence :
1. une règle métier validée reste prioritaire ;
2. une décision UX v0.9.0 plus récente remplace un ancien choix purement ergonomique ;
3. une décision « à vérifier », « à étudier » ou « audit requis » ne devient pas une implémentation supposée ;
4. le comportement réel du code, de la base et des droits doit être vérifié avant une modification touchant données ou sécurité.

## 3. Principes transversaux

- menu gauche = grands domaines ;
- onglets = vues d'un même contexte ;
- fil d'Ariane = position hiérarchique ;
- bouton orange = action principale ;
- bouton secondaire = action locale ;
- lien = navigation ;
- rouge = action destructive ;
- aucune navigation dupliquée sous forme d'onglet et de bouton ;
- pictogrammes fonctionnels et homogènes ;
- couleurs d'état toujours accompagnées d'un libellé ;
- après réussite dans une fenêtre : message puis **Fermer** uniquement ;
- confirmation avant déconnexion ;
- préserver strictement owner, manager, read_only et platform_admin.

## 4. Méthode d'implémentation

Travailler par lots cohérents. Pour chaque lot :
1. reprendre les décisions documentées ;
2. identifier les fichiers réellement concernés ;
3. auditer techniquement uniquement les points inconnus ;
4. implémenter en une passe cohérente ;
5. exécuter les tests ciblés ;
6. réserver lint / TypeScript / build complet aux jalons pertinents ;
7. valider visuellement ;
8. commit/push lorsque le lot est stable.

Ne pas relancer un audit global du projet à chaque étape.

# LOT 0 — Prérequis métier et sécurité

**Priorité : bloquante pour les sujets concernés**

### Séparation des usages d'une adresse e-mail

**Décision métier validée à la suite de l'audit LOT 0A.**

Un compte PatriGest appartient à un seul mode d'utilisation :

- **compte autonome** ;
- **compte collaborateur**.

#### Compte autonome

Un compte autonome peut créer et posséder ses propres dossiers de
personnes protégées.

Il ne peut pas devenir collaborateur invité sur le dossier d'un autre
propriétaire avec la même adresse e-mail.

#### Compte collaborateur

Un compte collaborateur accède uniquement aux dossiers sur lesquels il
a été invité.

Son accès à chaque dossier est défini par un rôle :

- `manager` — Gestionnaire ;
- `read_only` — Lecture seule.

Le rôle `manager` est uniquement un rôle d'accès à un dossier partagé.
Il ne donne pas au collaborateur la qualité de compte autonome et ne
l'autorise pas à créer ou posséder ses propres dossiers.

Un même compte collaborateur peut accéder à plusieurs dossiers, y
compris à des dossiers appartenant à plusieurs propriétaires, lorsque
les invitations et autorisations correspondantes existent.

#### Exclusivité

Une même adresse e-mail ne peut pas être utilisée simultanément pour :

- un compte autonome ;
- un compte collaborateur.

Cette exclusivité doit être garantie côté serveur et base de données.
Les contrôles de l'interface servent également à fournir des messages
utilisateur compréhensibles, mais ne constituent pas la protection
principale.

La compatibilité du mode de compte doit être vérifiée aux étapes
pertinentes, notamment :

- inscription publique ;
- validation d'une inscription ;
- émission d'une invitation ;
- acceptation d'une invitation ;
- création d'un dossier.

L'acceptation d'une invitation doit recontrôler la compatibilité au
moment où l'accès est effectivement accordé afin d'éviter qu'un
changement intervenu depuis l'émission de l'invitation crée un état
incohérent.

Les comparaisons d'adresses e-mail doivent utiliser une normalisation
cohérente afin qu'une différence de casse ou d'espaces ne permette pas
de contourner la règle.

#### Platform admin

Le `platform_admin` conserve son régime spécifique.

Il ne doit pas devenir propriétaire d'un dossier de personne protégée,
collaborateur d'un dossier ni cible d'une invitation de partage.

Les protections existantes correspondantes doivent être conservées.

#### Situation des données existantes

À la date de l'audit LOT 0A, aucun compte mixte connu n'existe dans les
données actuellement utilisées.

Il n'est donc pas nécessaire de concevoir un mécanisme fonctionnel
permanent permettant de conserver des comptes mixtes.

La future migration devra néanmoins vérifier l'absence d'un état
historique incompatible avant d'activer les nouvelles contraintes, afin
d'échouer explicitement plutôt que de convertir silencieusement des
données inattendues.

#### Résultat de l'audit LOT 0A

L'implémentation actuelle ne garantit pas encore cette règle métier.

L'audit a notamment établi que :

- aucun état persistant ne distingue actuellement un compte autonome
  d'un compte collaborateur ;
- un collaborateur actif peut actuellement créer son propre dossier ;
- un propriétaire peut actuellement recevoir puis accepter une
  invitation de collaboration ;
- l'émission d'une invitation ne contrôle pas suffisamment le mode
  d'utilisation du compte cible ;
- l'acceptation ne recontrôle pas l'incompatibilité
  propriétaire/collaborateur ;
- la validation administrative d'une inscription ne recherche pas les
  invitations ou accès collaborateurs existants ;
- une invitation redondante vers un collaborateur déjà présent sur le
  même dossier peut être consommée sans modifier son rôle ;
- aucune protection globale RLS, trigger ou RPC ne garantit
  actuellement l'exclusivité.

#### Correction à prévoir

La correction technique du LOT 0A devra être réalisée avant les
modifications UX qui dépendent de cette distinction.

La conception technique devra notamment étudier :

- un mode de compte persistant et contrôlé côté serveur, par exemple
  `primary` / `collaborator` ;
- son attribution atomique selon le parcours de création du compte ;
- l'interdiction côté SQL de créer un dossier pour un collaborateur ;
- le refus d'une invitation visant un compte autonome ;
- le recontrôle de la compatibilité lors de l'acceptation ;
- les contrôles applicatifs correspondants afin de fournir des messages
  utilisateur explicites ;
- une normalisation centralisée des adresses e-mail ;
- le traitement correct d'une invitation envoyée à un collaborateur
  disposant déjà d'un accès au dossier ;
- les tests de concurrence entre création d'un dossier et acceptation
  d'une invitation.

La solution technique définitive ne doit pas être supposée à partir du
présent document : elle sera arrêtée lors de l'implémentation du
LOT 0A à partir du modèle et des protections existants.

### Actions destructives
Vérifier le comportement réel de la suppression d'un dossier, d'un compte financier, d'un utilisateur et de la clôture d'un compte avant de rédiger les explications UX définitives.

### États
Inventorier les états réellement supportés des comptes de gestion, exercices, invitations, comptes utilisateurs et rapprochements avant de définir les couleurs.

### Clôture et suppression — décisions issues de l'audit LOT 0B

**Décisions métier validées à la suite de l'audit LOT 0B.**

#### Clôture d'un compte financier

La clôture d'un compte financier est distincte de sa suppression.

Clôturer un compte :

- conserve le compte ;
- conserve l'intégralité de son historique ;
- conserve ses opérations, valorisations, relevés, rapprochements et
  documents ;
- l'exclut du patrimoine financier actif à compter de sa clôture ;
- permet de continuer à consulter son historique ;
- reste réversible par une réouverture du compte.

La date de clôture constitue la borne temporelle maximale des données
rattachées au compte.

Une clôture à une date donnée doit être refusée s'il existe déjà une
donnée métier datée après cette date, notamment :

- une opération ;
- une valorisation ;
- un relevé bancaire ;
- toute autre donnée datée dont la cohérence dépend de la période
  d'activité du compte.

Après clôture, une saisie ou correction historique reste autorisée si
sa date est antérieure ou égale à la date de clôture et si elle respecte
les autres règles métier applicables.

Aucune nouvelle donnée ne doit pouvoir être enregistrée avec une date
postérieure à la date de clôture.

Pour enregistrer une donnée postérieure à la date de clôture, le compte
doit d'abord être rouvert.

La réouverture remet le compte dans son état actif selon les règles
métier existantes.

Cette règle doit être garantie côté serveur/base et ne doit pas reposer
uniquement sur le filtrage des comptes clôturés dans l'interface.

#### Suppression d'un compte financier

La suppression est différente de la clôture.

Un compte financier ne peut être supprimé que lorsqu'il est réellement
vide et ne possède plus d'historique ou de dépendance métier empêchant
sa suppression.

La suppression est physique et réservée au propriétaire selon le modèle
actuel.

Les dépendances doivent être contrôlées explicitement lorsque cela
permet de fournir un message utilisateur utile, plutôt que de laisser
une contrainte de clé étrangère produire uniquement une erreur
générique.

La future UX doit expliquer clairement que :

- clôturer conserve l'historique ;
- supprimer exige un compte vide ;
- supprimer n'est pas une alternative à la clôture d'un compte ayant
  déjà servi.

#### Suppression d'un dossier

La suppression d'un dossier reste une suppression physique réservée au
propriétaire et uniquement possible lorsque le dossier ne contient plus
les données et relations métier qui doivent empêcher sa suppression.

Les protections par contraintes de base existantes doivent être
conservées.

Les dépendances actuellement protégées uniquement de manière indirecte
par des clés étrangères devront être prises en compte dans les contrôles
applicatifs/RPC lorsque cela est nécessaire pour fournir un motif de
blocage compréhensible.

La future interface ne doit jamais annoncer une suppression en cascade
de données qui n'existe pas réellement.

#### Suppression de son propre compte utilisateur

La suppression du compte Auth ne signifie pas la suppression de
l'ensemble de l'historique métier.

Les futurs textes UX devront distinguer explicitement :

- les données supprimées ;
- les accès supprimés ;
- les références anonymisées ou détachées de l'utilisateur ;
- les données métier conservées pour préserver l'intégrité et
  l'historique des dossiers ;
- les éventuelles informations personnelles qui doivent faire l'objet
  d'un traitement spécifique.

Aucune interface ne devra promettre la disparition de toutes les données
si le comportement réel ne la garantit pas.

#### Suppression administrative d'un utilisateur

Le caractère `Non supprimable` du compte platform_admin actuellement
observé est normal et attendu.

Un platform_admin ne peut pas être supprimé par le parcours
d'administration utilisateur existant.

Pour les utilisateurs ordinaires, l'interface devra à terme refléter
plus précisément les véritables motifs de blocage appliqués par le
backend afin d'éviter qu'une suppression présentée comme disponible
échoue ensuite sur une dépendance non expliquée.

#### Corrections techniques à prévoir

Avant ou pendant les lots concernés, prévoir notamment :

- cohérence de la date de clôture avec toutes les données déjà
  enregistrées ;
- interdiction backend des données postérieures à la clôture ;
- maintien des corrections/saisies historiques antérieures ou égales à
  la clôture ;
- amélioration des précontrôles de suppression pour les dépendances
  ajoutées après les RPC initiales ;
- parité entre les motifs de suppression affichés dans l'administration
  et les protections réelles du backend ;
- vérification du traitement des données personnelles conservées lors
  d'une suppression utilisateur ;
- vérification spécifique du traitement Storage lors des suppressions
  administratives.

# LOT 1 — Fondations UX transversales

**Priorité : très haute**

Le LOT 1 est traité comme un **fil rouge transversal** pendant l’implémentation des lots fonctionnels. Ses règles doivent être appliquées aux écrans touchés par chaque lot, sans déclencher à chaque étape un audit global ni une refonte générale de l’application.

Il n’est considéré comme totalement clôturé qu’après le **LOT 1F — Clôture des fondations UX transversales**, réalisé avant la validation finale de la v0.9.0.

Exigences à préserver tout au long des lots :

- Harmoniser navigation, onglets, fils d'Ariane et suppression des navigations redondantes.
- Harmoniser pictogrammes : taille, conteneur, alignement, espacement, titres et couleurs fonctionnelles.
- Harmoniser les dialogues : après réussite, masquer formulaire/actions et ne conserver que **Fermer** ; en cas d'échec, conserver les possibilités de correction.
- Déconnexion utilisateur et administrateur : confirmation avant fermeture de session.

## LOT 1F — Clôture des fondations UX transversales

**Priorité : bloquante avant validation finale v0.9.0**

Après réalisation des lots fonctionnels, effectuer une revue ciblée des exigences du LOT 1 sur l’application devenue quasi finale.

Cette clôture ne doit pas réimplémenter ce qui est déjà conforme. Elle doit uniquement identifier et corriger les écarts résiduels concernant :

- navigation, onglets, fils d'Ariane et navigations redondantes ;
- cohérence des pictogrammes sur les écrans concernés par la v0.9.0 ;
- comportement des dialogues après réussite et après échec ;
- confirmation de déconnexion utilisateur et administrateur ;
- **identité visuelle des e-mails PatriGest** : inventorier d’abord les e-mails réellement envoyés par l’application et ceux éventuellement générés par Supabase Auth, puis harmoniser les modèles que PatriGest contrôle avec la nouvelle identité graphique (logo, palette, hiérarchie, boutons, espacements, pied de page et rendu mobile), sans supposer que tous les e-mails utilisent le même moteur ;
- **favicon et identité navigateur** : auditer les fichiers et métadonnées réellement utilisés (`favicon.ico`, icônes Next.js, Apple Touch Icon, manifest et metadata éventuels), puis vérifier leur cohérence avec la nouvelle identité PatriGest sur navigateur desktop, onglets, favoris et mobile.

Le LOT 1F doit rester ciblé : pas d’audit métier général, pas de refonte fonctionnelle et pas de modification hors des exigences transversales ci-dessus. Pour les e-mails et les icônes, commencer par l’inventaire de l’existant avant toute modification afin de ne pas créer de doublons ni remplacer à tort un mécanisme externe.

# LOT 2 — Navigation principale et tableau de bord

**Priorité : haute**

### Pages racines
Tableau de bord, Dossiers et Catégories : aucun fil d'Ariane.

### Tableau de bord principal
Supprimer les cartes Dossiers actifs, Comptes de gestion à traiter et Actions à traiter. Afficher le nombre de dossiers actifs dans **Dossiers suivis**. Conserver les cartes dossiers, **Voir tous les dossiers** et **À faire prochainement**. Vérifier le comportement avec beaucoup de dossiers.

### Dossiers
Conserver la structure. Vérifier volume important et absence de troncature.

### Catégories
Conserver la structure ; appliquer seulement les conventions transversales.

# LOT 3 — Informations du dossier

**Priorité : très haute**

Créer quatre onglets :
1. **Personne protégée**
2. **Situation patrimoniale**
3. **Gestion**
4. **Suppression du dossier**

Supprimer le bouton redondant **Tableau de bord**.

### Personne protégée
Cartes : Identité, Domicile et résidence, Mesure de protection. Conserver les actions locales Modifier.

### Situation patrimoniale
Cartes : Patrimoine actuel, Comptes, Patrimoine immobilier, Dettes et emprunts.

La carte Comptes affiche nombres actifs/clôturés, comptes actifs en lignes compactes, soldes et lien **Voir les comptes**. Ne pas reproduire toute la gestion financière.

Préserver pour immobilier et dettes les états **Non renseigné / Aucun / Renseigné**.

### Gestion
Présenter exercice courant, période/état et compte de gestion correspondant. Navigation par liens contextuels légers.

### Suppression du dossier
Page isolée : conditions, conséquences, blocages, irréversibilité, action rouge et confirmation. Le texte définitif dépend du LOT 0.

# LOT 4 — Comptes de gestion et exercices

**Priorité : haute**

Créer deux onglets communs :
1. **Comptes de gestion**
2. **Exercices de gestion**

Sur Comptes de gestion : conserver le lien Légifrance uniquement ici, supprimer **Gérer les exercices**, conserver **Préparer un compte de gestion**, différencier les états.

Sur Exercices : conserver l'explication, **Créer un exercice**, Modifier et Clôturer. Les couleurs exactes dépendent des états réels.

# LOT 5 — Gestion financière et comptes

**Priorité : très haute**

Navigation d'un compte :
1. **Opérations du compte**
2. **Relevés**
3. **Rapprochements**
4. **Informations du compte**

**Opérations du compte** devient la vue d'entrée normale. Supprimer les boutons qui dupliquent les onglets. Conserver les véritables actions : Ajouter une recette, Ajouter une dépense, Effectuer un virement, Saisie successive.

### Informations du compte
Conserver Solde actuel calculé, Informations et Modifier. Vérifier numéro de compte/IBAN réellement disponible. Harmoniser pictogrammes/titres. Supprimer Dernières opérations, bouton Relevés et Ajouter un autre compte.

Remplacer **Cycle de vie du compte** par **Gestion du compte**. Expliquer clôture et suppression selon le comportement réel ; suppression dans une zone destructive avec confirmation.

# LOT 6 — Relevés et rapprochements bancaires

**Priorité : très haute**

### Relevés
Conserver comme archive documentaire : Ajouter, Voir, Télécharger, Modifier, Supprimer, Contrôler le solde. Le contrôle rapide reste sur la ligne. Prévoir pagination.

### Rapprochements
Créer une page dédiée accessible par onglet. Présenter : date du relevé, solde relevé, solde calculé, écart simple, état du contrôle, état du rapprochement détaillé, écart résiduel.

Selon l'état : commencer un contrôle, reprendre un brouillon, ouvrir un rapprochement détaillé, consulter un rapprochement validé.

Ne pas dupliquer les fonctions documentaires de Relevés.

### Couleurs
- écart simple 0,00 € = vert ; non nul = rouge ;
- écart résiduel 0,00 € = vert ; non nul = rouge.

### Audit technique préalable
Avant toute modification du modèle : tables, périodes, soldes, PDF, relations comptes/opérations/relevés, RLS, droits, calculs, suppression et contraintes de période. Aucune migration supposée.

# LOT 7 — Partage du dossier

**Priorité : haute**

Deux onglets :
1. **Inviter un collaborateur**
2. **Collaborateurs**

Vue d'invitation : Propriétaire, invitation, invitations envoyées. Nettoyer l'historique pour éviter une accumulation peu lisible.

Vue Collaborateurs : identité, rôle réel, statut. Ne pas utiliser un sélecteur permanent affichant par défaut **Lecture seule**. Préférer badge + **Modifier** ouvrant une fenêtre. **Retirer** = action destructive rouge. Après réussite : message + **Fermer**.

Le contrôle d'adresse dépend du LOT 0.

# LOT 8 — Mon compte

**Priorité : haute**

Quatre onglets :
1. **Profil**
2. **Adresse e-mail**
3. **Sécurité**
4. **Suppression du compte**

Même organisation pour platform_admin. Isoler la suppression, expliquer conditions/blocages/conséquences et confirmer. Appliquer les pictogrammes cohérents.

# LOT 9 — Administration platform_admin

**Priorité : haute**

Menu ADMINISTRATION :
1. **Tableau de bord**
2. **Inscriptions à valider**
3. **Comptes utilisateurs**
4. **Communication utilisateurs**

Renommer l'entrée actuelle Administration en Tableau de bord. Pas d'onglets horizontaux dupliquant le menu.

### Tableau de bord
Conserver les cartes utiles ; vérifier notamment **Invitations en attente**. Déplacer la communication des versions dans **Communication utilisateurs**.

### Inscriptions à valider
Supprimer les libellés anglais comme **Approved**. Statuts français sous forme de badges, avec couleur + texte.

### Comptes utilisateurs
Distinguer utilisateurs possédant leurs dossiers et collaborateurs invités, ainsi que Lecture seule/Gestionnaire pour chaque accès partagé. Éviter le terme Gestionnaire seul s'il est ambigu. Éviter N+1 et prévoir pagination si nécessaire.

Renvoyer l'e-mail d'activation : action claire, confirmation si pertinente, puis **Fermer** après réussite.

Supprimer l'utilisateur : rouge, jamais immédiat, confirmation détaillée. Expliquer pourquoi un utilisateur est non supprimable.

Mon compte, déconnexion et dialogues réutilisent les conventions utilisateur.

# LOT 0C-3 — Supervision des services externes

**Priorité : moyenne — administration technique**

Créer une vue réservée aux `platform_admin` permettant de centraliser les informations utiles au suivi technique de PatriGest, sans exposer de secret dans le navigateur.

Cette supervision concerne en priorité :

### Supabase
Étudier les informations réellement accessibles et pertinentes, notamment :
- état du projet ;
- taille réelle de la base PostgreSQL ;
- stockage utilisé lorsque l'information est disponible ;
- éventuels indicateurs de consommation ou de quota utiles.

Privilégier les informations obtenables depuis l'infrastructure déjà autorisée avant d'ajouter un nouveau secret de Management API.

### Vercel
Étudier l'accès aux informations de déploiement, notamment :
- état du dernier déploiement Production ;
- date du dernier déploiement ;
- commit Git correspondant ;
- éventuel échec de déploiement ;
- consommation ou quota uniquement si l'API et le plan permettent de les obtenir proprement.

### Resend
Étudier les métriques accessibles par API, notamment :
- nombre d'e-mails envoyés sur la période pertinente ;
- délivrés ;
- échecs / bounces lorsque disponibles ;
- consommation ou limite du plan lorsque cette information est exposée par l'API.

Ne pas modifier le mécanisme existant de notification des versions pour construire cette supervision.

### Gandi
Étudier les informations accessibles pour `patrigest.fr`, notamment :
- date d'expiration / fin d'enregistrement ;
- état du renouvellement automatique ;
- éventuels états nécessitant une attention administrative.

### Présentation
Prévoir une entrée dédiée dans le menu `ADMINISTRATION`, par exemple **Infrastructure**.

Présenter les services sous forme de cartes ou blocs synthétiques avec :
- nom du service ;
- état explicite en texte ;
- principales informations utiles ;
- date/heure de dernière actualisation ;
- message clair lorsque l'information est indisponible.

La couleur ne doit jamais être le seul indicateur d'état.

### Sécurité et architecture
- accès strictement réservé aux `platform_admin` ;
- appels aux API externes exclusivement côté serveur ;
- aucun token ou secret transmis au navigateur ;
- aucun secret journalisé ;
- ne pas ajouter un token externe si l'information recherchée peut être obtenue de manière plus sûre avec l'infrastructure existante ;
- prévoir timeout, gestion des erreurs et indisponibilité indépendante de chaque service ;
- une panne d'un fournisseur ne doit pas empêcher l'affichage des autres ;
- prévoir cache ou fréquence de rafraîchissement raisonnable afin de ne pas interroger inutilement les fournisseurs ;
- ne jamais exposer les valeurs des variables d'environnement dans l'interface.

### Audit préalable obligatoire
Avant toute implémentation :
1. inventorier les API et informations réellement accessibles avec les comptes/plans PatriGest actuels ;
2. identifier les secrets déjà disponibles et ceux qu'il faudrait éventuellement ajouter ;
3. distinguer les informations fiables par API de celles disponibles uniquement dans les tableaux de bord fournisseurs ;
4. proposer le périmètre minimal utile avant d'écrire le code.

Ne pas créer de dépendance artificielle ni reproduire intégralement les tableaux de bord Supabase, Vercel, Resend ou Gandi.

### Critères de sortie
- aucune information sensible exposée côté client ;
- aucune valeur secrète stockée en base pour les besoins de l'écran ;
- informations provenant des fournisseurs clairement identifiées ;
- erreurs partielles correctement gérées ;
- responsive vérifié ;
- tests ciblés ;
- lint ;
- TypeScript ;
- build ;
- `git diff --check` ;
- validation visuelle.

# LOT 10 — Historique des versions

**Priorité : basse**

Page globalement satisfaisante. Prévoir pagination ou chargement progressif lorsque le volume le justifiera. Ne pas modifier prématurément.

# LOT 11 — Chantiers métier de l'ancien audit à préserver

Ne pas perdre dans la refonte UX :
- première connexion et premier dossier ;
- parcours initial de configuration ;
- informations nécessaires au compte de gestion ;
- règle métier du solde initial ;
- saisie successive ;
- justificatifs immédiats ;
- documents liés à une ou plusieurs opérations ;
- correction Dépense ↔ Recette ;
- traitement spécifique des virements ;
- permanence des références de pièces ;
- états Non renseigné / Aucun / Renseigné ;
- moteur d'actions contextuel ;
- documents du dossier ;
- règles de fin d'exercice et de relevés.

Ces sujets doivent conserver leurs décisions métier et recevoir un chantier distinct lorsqu'ils exigent une évolution fonctionnelle substantielle.

# 12. Ordre recommandé

1. LOT 0 — audits bloquants métier/sécurité
2. LOT 1 — fondations UX transversales, appliquées en fil rouge
3. LOT 2 — navigation principale/tableau de bord
4. LOT 3 — Informations du dossier
5. LOT 4 — Comptes de gestion / Exercices
6. LOT 5 — Gestion financière / comptes
7. LOT 6 — Relevés / Rapprochements
8. LOT 7 — Partage du dossier
9. LOT 8 — Mon compte
10. LOT 9 — Administration
11. LOT 10 — Historique si nécessaire
12. LOT 1F — clôture des fondations UX transversales
13. validation globale v0.9.0

Le LOT 11 est une réserve de chantiers métier à planifier selon ce qui est déjà implémenté. Le LOT 1 reste actif comme fil rouge pendant les lots fonctionnels et n’est déclaré clôturé qu’après le LOT 1F.

# 13. Utilisation de Codex

Compte tenu du quota, Codex ne doit pas redécouvrir ce qui est déjà documenté.

Avant chaque lot, préparer ici :
- périmètre exact ;
- décisions UX ;
- questions techniques réellement inconnues ;
- critères d'acceptation.

Puis donner à Codex un prompt ciblé demandant audit minimal, implémentation, tests ciblés et rapport.

Éviter audits globaux répétés, exploration sans objectif, build complet après chaque micro-changement, prompts séparés pour de petites modifications d'une même page et modifications hors périmètre.

# 14. Critères de sortie v0.9.0

- navigation utilisateur cohérente ;
- navigation platform_admin cohérente ;
- aucune navigation redondante inutile ;
- pages complexes structurées par onglets ;
- Rapprochements directement découvrable ;
- actions destructives expliquées et confirmées ;
- déconnexion confirmée ;
- dialogues cohérents après réussite ;
- pictogrammes homogènes ;
- statuts lisibles par libellé et couleur ;
- droits owner / manager / read_only / platform_admin préservés ;
- responsive vérifié ;
- e-mails PatriGest contrôlés par l’application cohérents avec l’identité visuelle v0.9.0, après inventaire des e-mails applicatifs et Supabase Auth ;
- favicon, icônes navigateur/mobile, metadata et manifest éventuel vérifiés et cohérents avec l’identité PatriGest ;
- tests ciblés réussis ;
- lint réussi ;
- TypeScript réussi ;
- build réussi ;
- `git diff --check` réussi ;
- validation visuelle finale.

> La release v0.9.0, le changement de `APP_VERSION`, le tag et l'information des utilisateurs ne seront réalisés qu'après validation explicite du jalon.

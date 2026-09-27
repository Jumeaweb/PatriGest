# PatriGest — Plan de suite

**Statut :** document de pilotage actif  
**Point de départ :** v0.9.0  
**Date :** 27 septembre 2026

> Ce document devient le point d'entrée pour les travaux postérieurs à la v0.9.0.
>
> Les documents `ux-v0.9.0.md` et `plan-directeur-ux-v0.9.0.md` sont conservés comme historique des décisions et de la réalisation de la v0.9.0. Ils ne constituent plus la liste active des travaux à effectuer.

## 1. État de référence

La version **v0.9.0** est publiée et validée en production.

Référence Git de la release :

- commit : `922c6a5` — `chore: release v0.9.0`
- tag : `v0.9.0`

La recette globale v0.9.0 a validé notamment :

- navigation principale ;
- navigation des dossiers ;
- informations du dossier ;
- comptes de gestion et exercices ;
- gestion financière ;
- relevés et rapprochements ;
- partage et collaborateurs ;
- Mon compte ;
- administration ;
- historique des versions ;
- identité visuelle ;
- e-mails ;
- responsive ;
- contrôles techniques finaux.

La communication de release v0.9.0 a été envoyée avec succès aux 7 destinataires actifs prévus, sans échec.

Le chantier UX/UI v0.9.0 est donc **clos**.

---

# 2. Prochain chantier — Supervision des services externes

**Origine :** ancien LOT0C-3  
**Priorité :** moyenne — administration technique  
**État :** À auditer  
**Prochaine étape recommandée :** audit préalable uniquement

## Objectif

Créer une vue réservée aux `platform_admin` permettant de centraliser les informations techniques réellement utiles au suivi de PatriGest sans exposer de secret dans le navigateur.

Prévoir une entrée dédiée dans le menu `ADMINISTRATION`, par exemple :

**Infrastructure**

## Services à étudier

### Supabase

Étudier les informations réellement accessibles et pertinentes :

- état du projet ;
- taille réelle de la base PostgreSQL ;
- stockage utilisé lorsque disponible ;
- indicateurs de consommation ou quotas réellement accessibles.

Privilégier les informations obtenables depuis l'infrastructure déjà autorisée avant d'ajouter un secret de Management API.

### Vercel

Étudier notamment :

- état du dernier déploiement Production ;
- date du dernier déploiement ;
- commit Git correspondant ;
- éventuel échec de déploiement ;
- consommation ou quotas seulement lorsque l'API et le plan utilisés permettent de les obtenir proprement.

### Resend

Étudier notamment :

- nombre d'e-mails envoyés sur une période pertinente ;
- délivrés ;
- échecs ou bounces lorsque disponibles ;
- consommation ou limite du plan lorsque l'API l'expose.

Ne pas modifier le mécanisme existant de notification des versions pour construire cette supervision.

### Gandi

Étudier pour `patrigest.fr` :

- date d'expiration ou fin d'enregistrement ;
- renouvellement automatique ;
- éventuels états nécessitant une intervention administrative.

## Présentation envisagée

Présenter les services sous forme de cartes ou blocs synthétiques indiquant :

- nom du service ;
- état explicite en texte ;
- principales informations utiles ;
- date et heure de dernière actualisation ;
- message clair lorsque l'information est indisponible.

La couleur ne doit jamais constituer le seul indicateur d'état.

## Contraintes de sécurité

- accès strictement réservé aux `platform_admin` ;
- appels aux API externes exclusivement côté serveur ;
- aucun token ou secret transmis au navigateur ;
- aucun secret journalisé ;
- aucune valeur secrète stockée en base pour les besoins de cet écran ;
- ne pas ajouter un token externe lorsqu'une méthode plus sûre permet d'obtenir l'information ;
- prévoir timeout et gestion des erreurs ;
- l'indisponibilité d'un fournisseur ne doit pas empêcher l'affichage des autres ;
- prévoir une fréquence de rafraîchissement ou un cache raisonnable ;
- ne jamais exposer les valeurs des variables d'environnement dans l'interface.

## Audit obligatoire avant implémentation

Avant d'écrire du code :

1. inventorier les API et informations réellement accessibles avec les comptes et plans PatriGest actuels ;
2. identifier les secrets déjà disponibles et ceux qu'il faudrait éventuellement ajouter ;
3. distinguer les informations fiables par API de celles accessibles uniquement depuis les tableaux de bord fournisseurs ;
4. déterminer le périmètre minimal réellement utile ;
5. ne pas reproduire les tableaux de bord complets de Supabase, Vercel, Resend ou Gandi.

## Critères de sortie du futur chantier

- aucune information sensible exposée côté client ;
- informations fournisseurs clairement identifiées ;
- erreurs partielles correctement gérées ;
- responsive vérifié ;
- tests ciblés réussis ;
- lint réussi ;
- TypeScript réussi ;
- build réussi ;
- `git diff --check` réussi ;
- validation visuelle.

---

# 3. Chantiers métier à réexaminer

**Origine :** ancien LOT11  
**État général :** À qualifier

Ces sujets ont été volontairement conservés pendant la refonte UX afin de ne perdre aucune décision métier.

Ils ne doivent pas être considérés automatiquement comme des fonctionnalités manquantes.

Pour chacun, commencer par déterminer si le besoin est :

- déjà complètement couvert ;
- partiellement couvert ;
- à corriger ;
- à compléter ;
- à concevoir ;
- ou à abandonner parce qu'il n'est plus pertinent.

## Sujets à qualifier

### Première connexion et premier dossier
**État :** À vérifier

Vérifier le parcours d'un nouvel utilisateur depuis la première connexion jusqu'à la création et la configuration initiale de son premier dossier.

### Parcours initial de configuration
**État :** À vérifier

Déterminer si les informations essentielles d'un nouveau dossier sont demandées dans un ordre suffisamment clair et progressif.

### Informations nécessaires au compte de gestion
**État :** À vérifier

Identifier les informations nécessaires à la production du compte de gestion et vérifier leur disponibilité dans le modèle et les parcours actuels.

### Règle métier du solde initial
**État :** À vérifier

Reprendre la règle métier du solde initial et vérifier sa cohérence avec les comptes, opérations, exercices et rapprochements actuels.

### Saisie successive
**État :** Partiellement revue

La saisie successive existe et son UX a été améliorée pendant la recette v0.9.0, notamment avec l'ajout de l'annulation et de la confirmation d'abandon d'un brouillon.

Vérifier ultérieurement si d'autres besoins métier restent ouverts.

### Justificatifs immédiats
**État :** À vérifier

Vérifier le parcours permettant d'associer un justificatif au moment pertinent de la saisie d'une opération.

### Documents liés à une ou plusieurs opérations
**État :** À étudier

Déterminer le modèle métier attendu pour les documents pouvant concerner une ou plusieurs opérations.

### Correction Dépense ↔ Recette
**État :** À étudier

Vérifier les règles nécessaires lorsqu'une opération a été saisie dans le mauvais sens et déterminer le parcours de correction approprié.

### Traitement spécifique des virements
**État :** À vérifier

Vérifier les règles de modification, correction et cohérence des virements entre comptes.

### Permanence des références de pièces
**État :** À étudier

Définir les règles garantissant la stabilité des références de pièces lorsque les opérations ou documents évoluent.

### États Non renseigné / Aucun / Renseigné
**État :** À surveiller

Ces états ont été préservés dans la refonte UX lorsqu'ils étaient nécessaires.

Vérifier leur cohérence lors des futurs développements concernés.

### Moteur d'actions contextuel
**État :** À concevoir / réévaluer

Réexaminer le besoin avant toute implémentation afin de déterminer les actions réellement utiles et les contextes dans lesquels elles doivent apparaître.

### Documents du dossier
**État :** À concevoir / réévaluer

Déterminer le périmètre documentaire réellement nécessaire au niveau du dossier avant de définir stockage, classement et interface.

### Règles de fin d'exercice et de relevés
**État :** À étudier

Vérifier les règles métier attendues lors de la clôture d'un exercice et leur interaction avec les opérations, relevés et rapprochements.

---

# 4. Dettes techniques connues

Les dettes techniques doivent rester distinctes des fonctionnalités métier.

## Résolution des utilisateurs Auth dans le partage

**État :** dette connue — non bloquante

La récupération des utilisateurs Auth utilisée dans certaines fonctions de partage repose encore sur un balayage paginé des utilisateurs.

À réexaminer si le volume d'utilisateurs augmente ou lorsqu'une source applicative batch plus adaptée est mise en place.

Ne pas optimiser prématurément sans mesure ou besoin réel.

---

# 5. Éléments transitoires connus

## Historique de l'ancien système d'inscriptions

La page `Inscriptions à valider` conserve encore un bloc :

**Historique de l'ancien système**

avec d'anciennes demandes d'accès conservées à titre transitoire.

**État :** À nettoyer ultérieurement après vérification des données et de leur utilité historique.

Ne supprimer aucune donnée uniquement pour faire disparaître ce bloc de l'interface.

---

# 6. Règles de travail post-v0.9.0

Pour chaque nouveau chantier :

1. partir du présent document ;
2. définir le besoin fonctionnel avant le code ;
3. vérifier ce qui existe réellement ;
4. ne réaliser un audit technique que sur les points inconnus ;
5. fixer le périmètre et les critères d'acceptation ;
6. utiliser Codex uniquement pour les modifications de code nécessitant réellement son intervention ;
7. exécuter les tests ciblés ;
8. valider visuellement lorsque le chantier touche l'interface ;
9. effectuer Git, commit et push hors Codex ;
10. mettre à jour ce document lorsque le chantier est terminé ou lorsqu'une nouvelle dette est identifiée.

Les opérations Git, les contrôles Supabase distants et les opérations mécaniques ne doivent pas consommer inutilement le quota Codex.

---

# 7. Ordre de travail actuel

Ordre proposé à partir de la v0.9.0 :

1. **LOT0C-3 — audit de la supervision des services externes**
2. décider du périmètre minimal de la future vue Infrastructure ;
3. implémenter la supervision retenue si l'audit la justifie ;
4. reprendre les chantiers métier de la section 3 un par un ;
5. prioriser ces chantiers selon leur valeur métier et leurs dépendances ;
6. traiter les dettes techniques uniquement lorsqu'elles deviennent pertinentes.

Ne pas lancer simultanément plusieurs chantiers métier importants.

---

# 8. Historique des jalons

## v0.9.0 — 27 septembre 2026

**Statut : TERMINÉ**

- refonte UX/UI terminée ;
- recette globale terminée ;
- contrôles techniques réussis ;
- production validée ;
- communication utilisateurs terminée ;
- 7 e-mails globaux envoyés ;
- 0 échec.

Référence Git :

`922c6a5 — chore: release v0.9.0`

Tag :

`v0.9.0`

---

# 9. Prochaine action

**Auditer LOT0C-3 — Supervision des services externes.**

Commencer par l'inventaire des possibilités réelles de Supabase, Vercel, Resend et Gandi avec l'infrastructure et les plans actuellement utilisés.

Aucune implémentation avant validation du périmètre issu de cet audit.
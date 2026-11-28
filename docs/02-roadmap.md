# Roadmap â€“ PatriGest

Version : 1.0

---

# Philosophie

Le dÃ©veloppement de PatriGest est rÃ©alisÃ© par Ã©tapes.

Chaque phase doit Ãªtre :

- entiÃ¨rement dÃ©veloppÃ©e ;
- testÃ©e ;
- validÃ©e ;
- documentÃ©e ;
- sauvegardÃ©e dans Git.

Aucune nouvelle phase ne dÃ©bute tant que la prÃ©cÃ©dente n'est pas entiÃ¨rement terminÃ©e.

---

# Phase 0 â€“ Conception

## Objectif

DÃ©finir complÃ¨tement le projet avant d'Ã©crire la premiÃ¨re ligne de code.

## Livrables

- PrÃ©sentation
- Cahier des charges
- Roadmap
- ModÃ¨le de donnÃ©es
- SÃ©curitÃ©
- Design et navigation
- Rapports
- Design System
- Conventions de dÃ©veloppement

## RÃ©sultat attendu

Toute l'architecture fonctionnelle est validÃ©e.

---

# Phase 1 â€“ Fondation technique

## Objectif

CrÃ©er le socle de PatriGest.

## FonctionnalitÃ©s

- DÃ©pÃ´t GitHub
- Projet Next.js
- TypeScript
- Tailwind CSS
- Supabase
- PostgreSQL
- Authentification
- Design System
- Site public
- DÃ©ploiement Vercel

## RÃ©sultat attendu

Une application accessible en ligne avec authentification fonctionnelle.

---

# Phase 2 â€“ Gestion des dossiers

## Objectif

CrÃ©er les dossiers des personnes protÃ©gÃ©es.

## FonctionnalitÃ©s

- CrÃ©ation
- Modification
- Archivage
- Recherche
- Historique des mesures de protection

## RÃ©sultat attendu

Chaque utilisateur peut gÃ©rer plusieurs dossiers.

---

# Phase 3 â€“ Comptes et patrimoine

## Objectif

GÃ©rer les diffÃ©rents supports financiers.

## FonctionnalitÃ©s

- Comptes courants
- Livrets
- Assurances-vie
- Comptes Ã  terme
- Autres placements

## RÃ©sultat attendu

Le patrimoine de chaque personne protÃ©gÃ©e est entiÃ¨rement enregistrÃ©.

---

# Phase 4 â€“ Journal des opÃ©rations

## Objectif

Saisir les relevÃ©s bancaires.

## FonctionnalitÃ©s

- Recettes
- DÃ©penses
- Virements internes
- CatÃ©gories
- Commentaires
- RÃ©fÃ©rences de justificatifs

## RÃ©sultat attendu

Le journal des opÃ©rations est complet.

---

# Phase 5 â€“ Rapprochement bancaire

## Objectif

VÃ©rifier la conformitÃ© des opÃ©rations avec les relevÃ©s bancaires.

## FonctionnalitÃ©s

- Solde du relevÃ© bancaire
- Solde calculÃ© par PatriGest
- VÃ©rification
- Historique des rapprochements
- DÃ©tection des Ã©carts

## RÃ©sultat attendu

Chaque relevÃ© bancaire peut Ãªtre validÃ©.

---

# Phase 6 â€“ Rapports

## Objectif

Produire automatiquement les Ã©tats de gestion.

## FonctionnalitÃ©s

- Journal des opÃ©rations
- Situation des comptes
- Situation patrimoniale
- Recettes
- DÃ©penses
- Mouvements internes
- Ã‰volution du patrimoine

## RÃ©sultat attendu

Tous les rapports sont disponibles Ã  l'Ã©cran.

---

# Phase 7 â€“ PDF

## Objectif

Produire des documents imprimables.

## FonctionnalitÃ©s

- Export PDF
- Impression
- Compte de gestion
- Annexes

## RÃ©sultat attendu

Les rapports sont prÃªts Ã  Ãªtre remis aux autoritÃ©s compÃ©tentes.

---

# Phase 8 â€“ Confort d'utilisation

## Objectif

RÃ©duire le temps de saisie.

## FonctionnalitÃ©s

- CatÃ©gorisation automatique
- Organismes favoris
- Recherche rapide
- Filtres
- Tableaux de bord enrichis

## RÃ©sultat attendu

La saisie devient plus rapide et plus intuitive.

---

# Phase 9 â€“ Version 1.0

## Objectif

Stabiliser l'application.

## Travaux

- Corrections
- Optimisations
- Responsive
- AccessibilitÃ©
- SÃ©curitÃ©
- Documentation
- Validation finale

## RÃ©sultat attendu

Publication officielle de PatriGest Version 1.0.

## PAT-SEC-SUPPRESSION-01 — Sécurisation SQL de la suppression des comptes utilisateurs

Contrôle de sécurité à réaliser avant commercialisation. Étudier une défense SQL supplémentaire contre les suppressions accidentelles, compatible avec les purges légitimes.

- Recenser les protections SQL, les cascades et les dépendances entre Auth et les données métier, notamment les partages détenus par les collaborateurs.
- Distinguer la suppression administrative des purges automatiques autorisées et vérifier la compatibilité avec J60 et la purge après 12 mois de conservation.
- Analyser la concurrence entre la création de dépendances et la suppression, puis définir les exigences de traçabilité.
- Prévoir des tests de non-régression pour les refus, la concurrence, les purges légitimes et la conservation de l’audit.

---

# Ã‰volutions futures

Les versions suivantes pourront intÃ©grer :

- Import automatique des relevÃ©s bancaires (CSV, OFX, QIF...)
- DÃ©pÃ´t des justificatifs
- OCR des relevÃ©s
- Partage sÃ©curisÃ© d'un dossier
- Signature Ã©lectronique
- Synchronisation bancaire
- Statistiques avancÃ©es
- Calendrier des Ã©chÃ©ances
- GÃ©nÃ©ration des formulaires officiels
- Application mobile

---

# MÃ©thode de travail

Chaque fonctionnalitÃ© suit toujours le mÃªme cycle.

1. Conception
2. DÃ©veloppement
3. Tests
4. Corrections
5. Validation
6. Commit Git
7. Documentation

Une fonctionnalitÃ© n'est considÃ©rÃ©e comme terminÃ©e que lorsque :

- elle fonctionne ;
- elle respecte le Design System ;
- elle est responsive ;
- `npm run lint` est vert ;
- `npm run typecheck` est vert ;
- `npm run build` est vert ;
- elle a Ã©tÃ© testÃ©e manuellement.

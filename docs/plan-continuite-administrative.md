# Plan de continuité administrative et technique — PatriGest

## 1. Objet du document

Ce document décrit l'organisation de la continuité administrative et technique de PatriGest.

Il a pour objectifs de :

- réduire la dépendance à une seule identité technique ;
- identifier les services indispensables au fonctionnement de PatriGest ;
- documenter leurs propriétaires et mécanismes d'accès ;
- sécuriser les mécanismes de récupération ;
- préparer l'ajout futur d'une seconde personne de confiance ;
- définir les principes à appliquer en cas d'indisponibilité ou de compromission d'un administrateur.

Ce document ne doit contenir :

- aucun mot de passe ;
- aucun token ;
- aucune clé API ;
- aucun secret d'application ;
- aucun code MFA ;
- aucun code de récupération.

Les secrets et moyens de récupération doivent être conservés dans des emplacements sécurisés distincts de ce dépôt.

---

## 2. Organisation technique cible

### Jumeaweb

Jumeaweb constitue l'identité technique transverse utilisée pour les projets et services associés.

PatriGest est un produit/projet rattaché à cette organisation technique.

Principes :

- les comptes personnels restent nominatifs ;
- les ressources partageables doivent progressivement appartenir à une organisation ou une équipe plutôt qu'à un compte personnel ;
- aucune personne ne doit utiliser les identifiants d'une autre ;
- une future personne chargée de la continuité disposera de son propre compte ;
- les droits Owner/Admin seront attribués nominativement lorsque les services et leurs offres le permettent.

L'adresse technique actuellement utilisée pour plusieurs services est :

`jumeaweb@gmail.com`

Les anciens identifiants techniques tels que certains noms de compte, slugs ou URL peuvent être conservés lorsqu'un changement n'apporte aucun bénéfice fonctionnel ou présente un risque.

---

## 3. Gandi / domaine patrigest.fr

### État actuel

- Registrar : Gandi
- Domaine : `patrigest.fr`
- Compte associé : `jumeaweb@gmail.com`
- Propriétaire du domaine : Jérôme, personne physique
- Organisation propriétaire : aucune
- Contact administratif : propriétaire
- Contact technique : propriétaire
- Contact facturation : propriétaire
- Authentification à deux facteurs : active
- Mécanisme de récupération : configuré
- Autre personne disposant actuellement d'un accès : aucune
- Boîte e-mail `@patrigest.fr` dédiée à l'administration : aucune actuellement

### Décision

Le domaine reste actuellement détenu personnellement par Jérôme.

Il n'est pas nécessaire de créer une organisation Gandi ni de transférer artificiellement la propriété du domaine uniquement pour harmoniser les noms techniques.

Lorsqu'une personne chargée de la continuité sera désignée :

- elle devra disposer de son propre compte Gandi ;
- les possibilités de délégation ou de partage de gestion du domaine devront être utilisées si elles sont adaptées ;
- aucun partage de mot de passe ne devra être mis en place.

Une éventuelle transmission du domaine à une structure juridique pourra être étudiée ultérieurement si une telle structure devient propriétaire légitime du service.

### Continuité

Le domaine `patrigest.fr` peut être partagé nominativement avec un autre utilisateur Gandi, sans transfert de propriété du domaine.

Le partage peut être accordé à partir d'un nom d'utilisateur Gandi ou d'une adresse e-mail.

Les permissions proposées par Gandi sont configurables séparément :

- `Voir & renouveler` : consulter le domaine, sa configuration et effectuer son renouvellement ;
- `Configurer` : modifier la configuration technique du domaine, notamment les serveurs de noms, le DNS et les boîtes mail associées ;
- `Gérer les contacts` : modifier les informations légales et administratives du domaine et en partager la gestion ;
- `Acheter des options` : gérer certains services et options associés au domaine.

Aucun partage nominatif supplémentaire n'est actuellement configuré.

Lorsqu'une personne chargée de la continuité sera désignée, elle devra utiliser son propre compte Gandi. Les permissions nécessaires lui seront attribuées nominativement.

Le propriétaire actuel de `patrigest.fr` reste inchangé. La mise en place de la continuité ne nécessite pas de transfert de propriété du domaine.

Le compte principal conserve son MFA et son mécanisme de récupération déjà configurés.

### Récupération

Le mécanisme de récupération doit rester indépendant d'une adresse appartenant au domaine `patrigest.fr`.

Cela évite une dépendance circulaire dans laquelle la récupération du registrar dépendrait elle-même d'un domaine devenu inaccessible.

---

## 4. GitHub

### État actuel

Compte personnel :

- identifiant : `LRTeam83`
- adresse principale : `jumeaweb@gmail.com`
- authentification à deux facteurs : active
- codes de récupération : conservés dans un emplacement sécurisé

Organisation :

- nom : `Jumeaweb`
- propriétaire actuel : `LRTeam83`
- exigence 2FA pour les membres : active
- méthodes 2FA sécurisées exigées : active
- second Owner : aucun actuellement

Dépôt PatriGest :

`Jumeaweb/PatriGest`

Le dépôt a été transféré depuis :

`LRTeam83/PatriGest`

Le transfert a été réalisé avec succès.

### Accès Git local

Le dépôt local principal se trouve actuellement dans :

`C:\Users\jerom\Documents\PatriGest`

Remote canonique :

`https://github.com/Jumeaweb/PatriGest.git`

Mode d'accès :

- HTTPS ;
- Git Credential Manager ;
- identité GitHub utilisée : `LRTeam83`.

GitHub CLI n'est pas nécessaire au fonctionnement actuel.

L'accès en lecture et le droit de push vers `Jumeaweb/PatriGest` ont été vérifiés après le transfert.

### Codex

L'audit de l'environnement de développement n'a identifié aucune dépendance Git observable à une GitHub App OpenAI/Codex.

Les opérations Git réalisées depuis l'environnement local utilisent Git et les credentials de la machine via Git Credential Manager.

### Continuité à prévoir

À terme, l'organisation Jumeaweb devra disposer d'au moins deux Owners nominatifs lorsque la personne chargée de la continuité aura été désignée.

Cette personne devra :

- disposer de son propre compte GitHub ;
- activer une authentification forte ;
- rejoindre Jumeaweb nominativement ;
- recevoir le rôle nécessaire à la continuité.

Aucun compte GitHub partagé ne doit être créé.

---

## 5. Supabase

### État actuel

Organisation visible :

`Jumeaweb`

Ancien nom :

`LRTeam`

Le changement de nom de l'organisation n'a pas modifié son identifiant technique.

Projet PatriGest :

`patrigest-dev`

Référence projet :

`qtabsjeldxyrmozyybho`

Cette référence doit rester stable.

### Identités de connexion

Identité GitHub :

- compte GitHub : `LRTeam83`
- adresse GitHub principale : `jumeaweb@gmail.com`

Identité e-mail secondaire conservée :

`jerome.lucet@ik.me`

Cette identité secondaire est volontairement conservée pour le moment afin de disposer d'une voie d'accès indépendante.

### MFA

- authentification multifacteur principale : active ;
- facteur de secours : configuré via 2FAS Auth.

### Décision

Ne pas supprimer l'identité secondaire `jerome.lucet@ik.me` uniquement pour uniformiser les adresses.

La redondance des méthodes d'accès est actuellement préférable à une uniformisation purement esthétique.

### Continuité

L'organisation Supabase `Jumeaweb` permet d'inviter nominativement d'autres utilisateurs.

Les rôles actuellement proposés par l'interface sont :

- `Owner` : accès complet, notamment gestion des autres Owners, suppression de l'organisation et transfert ou suppression des projets ;
- `Administrator` : gestion des membres, de la facturation et des paramètres des projets, sans gestion des Owners ni des paramètres de l'organisation ;
- `Developer` : gestion du contenu des projets, sans modification des paramètres ni suppression des projets.

L'organisation ne comporte actuellement qu'un seul membre :
`jumeaweb@gmail.com`, avec le rôle `Owner` et le MFA activé.

Pour assurer une véritable continuité administrative, une seconde personne nominative pourra recevoir le rôle `Owner` lorsqu'elle aura été désignée et sécurisée avec une authentification forte.

L'interface indique que le SSO d'entreprise nécessite une offre Team ou supérieure. Le SSO n'est pas nécessaire à la stratégie actuelle de continuité.

Aucune invitation ne doit être envoyée avant la désignation de la personne de continuité.

Les clés Supabase, mots de passe de base de données et autres secrets ne doivent jamais être ajoutés à ce document ou au dépôt Git.

---

## 6. Vercel

### État actuel

Compte / équipe :

- nom visible : `Jumeaweb`
- offre actuelle : Hobby
- adresse du compte : `jumeaweb@gmail.com`

L'ancien nom visible de l'équipe était :

`LRTeam`

L'identifiant/URL technique historique de l'équipe peut rester inchangé tant qu'aucune nécessité fonctionnelle n'impose sa modification.

### Sécurité

- authentification à deux facteurs : active ;
- TOTP : configuré ;
- passkey : configurée ;
- codes de récupération : conservés dans un emplacement sécurisé.

### PatriGest

Projet Vercel :

`patrigest`

Dépôt Git connecté :

`Jumeaweb/PatriGest`

Vercel a suivi correctement le transfert du dépôt GitHub depuis `LRTeam83/PatriGest`.

La GitHub App Vercel est installée sur l'organisation Jumeaweb avec accès aux dépôts de l'organisation.

### Continuité

L'offre Hobby actuelle ne permet pas nécessairement de mettre en place la même organisation multi-administrateurs qu'une offre supérieure.

Il n'est pas prévu de changer d'offre uniquement pour ce motif à ce stade.

Cette limitation devra être réévaluée lorsqu'une seconde personne de continuité sera effectivement désignée.

---

## 7. Resend

### État actuel

- compte : `jumeaweb@gmail.com`
- PatriGest rattaché au compte actuel
- authentification multifacteur : active
- autre membre : aucun actuellement

Resend est utilisé notamment pour les e-mails applicatifs et les notifications de release PatriGest.

### Continuité

L'équipe Resend `jumeaweb` permet d'inviter nominativement d'autres utilisateurs.

Deux rôles sont actuellement proposés par l'interface :

- `Admin` : peut notamment inviter des utilisateurs, gérer le paiement et supprimer l'équipe ;
- `Member` : peut gérer les e-mails, domaines et webhooks.

Aucune seconde personne n'est actuellement membre de l'équipe.

Lorsqu'une personne chargée de la continuité sera désignée, elle devra disposer de son propre compte Resend. Le rôle à lui attribuer devra être choisi selon le niveau de continuité attendu ; le rôle `Admin` est celui permettant la continuité administrative la plus complète parmi les rôles actuellement affichés.

Aucune invitation ne doit être envoyée avant la désignation de cette personne.

Le mécanisme de récupération du compte en cas de perte du MFA reste à vérifier.

Les clés API Resend ne doivent jamais apparaître dans ce document.

---

## 8. Sauvegardes locales

Les projets locaux font l'objet d'une sauvegarde vers ShadowDrive.

Script actuellement utilisé :

`C:\Users\jerom\Scripts\Sauvegarde-Projets.ps1`

Projets concernés notamment :

- PatriGest ;
- AssoGestEvent ;
- CodalApp ;
- ArgEnPo.

Les répertoires techniques régénérables tels que `.git`, `node_modules` et `.next` sont exclus.

### Continuité à prévoir

Documenter séparément :

- l'emplacement de la sauvegarde ;
- la fréquence réelle d'exécution ;
- la procédure de restauration ;
- la date du dernier test réel de restauration.

Une sauvegarde ne doit pas être considérée comme opérationnelle uniquement parce que sa copie s'exécute : une restauration doit pouvoir être testée périodiquement.

### Test de restauration

Un test réel de restauration du code source de PatriGest a été effectué le 23/09/2026.

Source :
`ShadowDrive / Projets / patrigest`

Destination de test :
`C:\Users\jerom\Documents\Test-Restauration-PatriGest`

Le test a été réalisé dans un répertoire distinct du dépôt de travail afin de ne pas modifier l'installation principale de PatriGest.

Les dépendances ont été entièrement reconstruites avec `npm ci`.

Contrôles effectués après restauration :

- `npm run lint` : réussi ;
- `npx tsc --noEmit` : réussi ;
- `npm run build` : réussi.

Le build de production a été réalisé sans `.env.local`.

Conclusion : la sauvegarde ShadowDrive permet de restaurer le code source de PatriGest et de reconstruire avec succès l'application au niveau compilation.

Ce test ne valide pas encore la restauration des secrets, des variables d'environnement, des données Supabase ni des fichiers stockés à distance. Ces éléments font l'objet de procédures de continuité distinctes.

---

## 9. Secrets et récupération

Les informations suivantes ne doivent jamais être enregistrées dans Git :

- mots de passe ;
- tokens GitHub ;
- clés Supabase ;
- mot de passe de base de données Supabase ;
- clés Vercel ;
- clés Resend ;
- secrets applicatifs ;
- secrets TOTP ;
- codes de récupération ;
- clés privées.

Le présent document doit seulement indiquer :

- qu'un mécanisme existe ;
- qui en est responsable ;
- où se trouve la procédure permettant de le retrouver.

### Variables d'environnement de PatriGest

Le fichier local `.env.local` contient actuellement les variables suivantes :

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `APP_URL`

Aucune valeur de ces variables ne doit être inscrite dans ce document ni dans le dépôt Git.

`NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_ANON_KEY` sont des paramètres du projet Supabase `patrigest-dev`.

`SUPABASE_SERVICE_ROLE_KEY` est un secret critique lié au projet Supabase et ne doit être communiqué ni stocké dans la documentation.

`RESEND_API_KEY` est un secret critique lié au service Resend. En cas de perte ou de compromission, une nouvelle clé doit être créée et l'ancienne révoquée.

`APP_URL` correspond à l'URL utilisée par l'application et ne constitue pas un secret.

Le fichier `.env.local` reste présent uniquement dans l'environnement local de développement.

La copie de `.env.local` qui avait été ajoutée manuellement à ShadowDrive a été supprimée après la mise en place du coffre Bitwarden.

La sauvegarde ShadowDrive du code source ne contient donc plus cette copie de secrets de production.

Le test de restauration du code a démontré que `.env.local` n'est pas nécessaire pour installer les dépendances, exécuter les contrôles statiques et construire l'application.

### Variables d'environnement de production

Les variables d'environnement nécessaires à PatriGest sont également configurées dans l'environnement Vercel du projet.

La présence des cinq variables suivantes a été vérifiée dans Vercel Production :

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `APP_URL`

Les valeurs secrètes n'ont pas été affichées ni copiées pendant cette vérification.

`SUPABASE_SERVICE_ROLE_KEY` est actuellement affectée aux environnements Production et Preview. Les autres variables constatées lors de la vérification sont affectées à Production.

Vercel constitue la configuration de l'environnement déployé, mais ne doit pas être considéré comme l'unique sauvegarde des secrets. En situation de reprise, les secrets doivent pouvoir être récupérés ou, lorsque nécessaire, recréés et rotés depuis leurs services d'origine.

La présence d'une copie locale de `.env.local` dans ShadowDrive n'est donc pas nécessaire à la restauration du code source. La politique définitive de sauvegarde de ce fichier reste à décider en fonction de la stratégie retenue pour le coffre de secrets.

### Coffre de secrets

Un coffre Bitwarden dédié à la continuité de Jumeaweb et PatriGest a été mis en place.

Organisation Bitwarden :
`Jumeaweb`

Collection :
`PatriGest`

Le compte Bitwarden principal est protégé par MFA.

Le code de récupération Bitwarden est conservé séparément, hors du coffre Bitwarden. Sa valeur n'est pas inscrite dans la documentation.

La collection PatriGest contient les informations nécessaires à la continuité des principaux services techniques ainsi qu'une copie chiffrée des secrets critiques de production.

Les accès et procédures de continuité de Gandi, GitHub, Supabase, Vercel et Resend y sont documentés.

Les secrets techniques critiques suivants disposent d'une copie chiffrée dans Bitwarden :

- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`

Les valeurs de ces secrets ne doivent jamais être inscrites dans Git ni dans la documentation du projet.

Les variables de production sont également configurées dans Vercel.

Le fichier `.env.local` reste présent uniquement dans l'environnement local de développement. La copie qui avait été ajoutée manuellement dans ShadowDrive a été supprimée.

La sauvegarde ShadowDrive du code source ne contient donc plus `.env.local`.

Le test de restauration a confirmé que le code de PatriGest peut être restauré, contrôlé et construit sans ce fichier.

---

## 10. Principe de double administration

L'objectif de continuité à terme est de ne plus dépendre d'une seule personne pour les services critiques.

Lorsque la personne de confiance chargée de la continuité sera désignée :

1. elle utilisera ses propres comptes nominatifs ;
2. elle activera une authentification forte ;
3. elle recevra uniquement les droits nécessaires ;
4. aucun mot de passe principal ne sera partagé ;
5. les procédures de récupération seront documentées ;
6. l'accès sera testé avant d'être considéré comme opérationnel.

Les services devront être traités individuellement en fonction de leurs possibilités techniques et de l'offre souscrite.

---

## 11. Scénarios de continuité

### 11.1 Indisponibilité temporaire de l'administrateur principal

Objectif :

permettre à la personne de continuité d'assurer les opérations indispensables sans utiliser les identifiants de l'administrateur principal.

Priorités :

- accès au domaine ;
- accès au dépôt GitHub ;
- accès à l'hébergement ;
- accès à la base et aux services nécessaires ;
- accès aux mécanismes de communication indispensables.

### 11.2 Perte d'un facteur MFA

Utiliser en priorité :

- le facteur secondaire lorsqu'il existe ;
- les mécanismes officiels de récupération ;
- les codes de récupération conservés de manière sécurisée.

Ne pas désactiver durablement le MFA comme solution de facilité.

### 11.3 Compromission d'un compte

Ordre général :

1. sécuriser l'adresse e-mail ou l'identité racine concernée ;
2. révoquer les sessions compromises ;
3. renouveler les moyens d'authentification ;
4. révoquer ou renouveler les tokens et clés concernés ;
5. vérifier les changements administratifs effectués ;
6. contrôler GitHub, Vercel, Supabase, Resend et Gandi selon le périmètre de l'incident ;
7. conserver les éléments nécessaires à l'analyse de l'incident.

### 11.4 Indisponibilité longue, incapacité ou décès

La continuité ne doit pas reposer sur la connaissance du mot de passe personnel de Jérôme.

Elle devra reposer sur :

- des comptes nominatifs distincts ;
- des droits Owner/Admin préalablement attribués lorsque possible ;
- une procédure documentaire accessible à la personne de confiance ;
- des mécanismes de récupération indépendants ;
- les dispositions juridiques appropriées concernant les actifs détenus personnellement, notamment le domaine.

---

## 12. État de consolidation Jumeaweb

### Réalisé

- adresse `jumeaweb@gmail.com` utilisée sur les principaux services concernés ;
- Gandi sécurisé par 2FA et récupération ;
- GitHub sécurisé par 2FA et codes de récupération ;
- organisation GitHub Jumeaweb créée ;
- 2FA obligatoire dans l'organisation GitHub ;
- dépôt PatriGest transféré vers `Jumeaweb/PatriGest` ;
- remote Git local PatriGest migré et testé ;
- accès Git en lecture et push vérifié après transfert ;
- Vercel sécurisé par TOTP, passkey et codes de récupération ;
- équipe Vercel renommée Jumeaweb ;
- GitHub App Vercel installée sur Jumeaweb ;
- projet Vercel PatriGest correctement relié à `Jumeaweb/PatriGest` après transfert ;
- organisation Supabase renommée Jumeaweb ;
- MFA Supabase actif avec facteur de secours ;
- identité e-mail Supabase secondaire volontairement conservée ;
- MFA Resend activé.

### Volontairement inchangé

- compte GitHub personnel `LRTeam83` ;
- identifiant/slug technique Supabase ;
- référence projet Supabase `qtabsjeldxyrmozyybho` ;
- URL/identifiant technique historique de l'équipe Vercel ;
- identité Supabase secondaire `jerome.lucet@ik.me` ;
- propriété personnelle actuelle du domaine `patrigest.fr`.

Ces éléments ne doivent pas être renommés uniquement pour obtenir une uniformité visuelle.

---

## 13. Travaux restant à réaliser

### Personne de continuité

Aucune personne de continuité n'est désignée à ce jour.

Cette désignation est volontairement différée jusqu'à l'identification d'une personne de confiance appropriée.

L'infrastructure a néanmoins été préparée afin de permettre ultérieurement l'attribution d'accès nominatifs, sans partage des comptes personnels ni des mots de passe principaux.

Lorsqu'une personne sera désignée, les droits nécessaires devront être attribués service par service selon le principe du moindre privilège.

État : différé — aucune action requise actuellement.

### Droits secondaires

Après désignation de la personne de continuité, configurer les accès nominatifs nécessaires service par service, selon les possibilités et limitations déjà documentées.

Services concernés notamment :

- GitHub ;
- Gandi ;
- Supabase ;
- Vercel ;
- Resend.

### Revue périodique

Prévoir une revue périodique de ce document afin de vérifier :

- comptes ;
- propriétaires ;
- MFA ;
- récupération ;
- administrateurs secondaires ;
- dépendances ;
- sauvegardes ;
- changements d'offres ou de fournisseurs.

---

## 14. Tableau de suivi

| Service | Identité / organisation | MFA | Récupération | Second administrateur | État |
|---|---|---:|---:|---:|---|
| Gandi / patrigest.fr | compte `jumeaweb` / propriétaire actuel | Oui | Oui | Partage nominatif possible, non configuré | Délégation du domaine vérifiée |
| GitHub | `LRTeam83` + organisation `Jumeaweb` | Oui | Oui | Non | Migration Jumeaweb réalisée |
| Supabase | organisation `Jumeaweb` / `jumeaweb@gmail.com` Owner | Oui | Facteur secondaire 2FAS | Possible, non configuré | Rôles de continuité vérifiés |
| Vercel | équipe `Jumeaweb` | Oui | Oui | Non | Consolidation principale réalisée |
| Resend | équipe `jumeaweb` / `jumeaweb@gmail.com` Admin | Oui | À vérifier | Possible, non configuré | Équipe et rôles vérifiés |
| Sauvegardes | ShadowDrive | N/A | N/A | N/A | Validé — 23/09/2026 |
| Bitwarden | organisation `Jumeaweb` / collection `PatriGest` | Oui | Code de récupération conservé hors coffre | Personne de continuité différée | Coffre de continuité opérationnel |

---

## 15. Critère de clôture de LOT 0C-2

LOT 0C-2 peut être considéré comme clôturé lorsque :

- l'inventaire des services critiques est documenté ;
- les comptes principaux sont sécurisés ;
- les mécanismes de récupération disponibles sont identifiés ;
- les possibilités et limitations de seconde administration sont documentées service par service ;
- un coffre-fort sécurisé est opérationnel ;
- les secrets critiques nécessaires à la continuité disposent d'une conservation sécurisée distincte du dépôt Git ;
- une restauration réelle du code source a été testée ;
- les scénarios principaux d'urgence sont documentés ;
- la désignation d'une personne de continuité, lorsqu'elle n'est pas encore possible, est explicitement identifiée comme une action différée.

La personne de continuité n'est pas encore désignée. Cette décision est volontairement différée et ne bloque pas la clôture technique du LOT 0C-2.

Lorsqu'une personne appropriée aura été identifiée, les accès nominatifs prévus par le présent document devront être configurés et testés service par service.

État du LOT 0C-2 : clôturé techniquement le 23/09/2026, avec désignation de la personne de continuité différée.

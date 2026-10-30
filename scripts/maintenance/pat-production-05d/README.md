# PAT-PRODUCTION-05D — dispositif temporaire de maintenance

Ces scripts préparent une fenêtre de maintenance de publication. Ils ne sont pas
des migrations et ne doivent jamais être placés dans `supabase/migrations`.

## Garanties

- `activate-maintenance.sql` capture les ACL directes de `public` pour `PUBLIC`,
  `anon`, `authenticated` et `service_role`, puis retire `USAGE` et `CREATE`.
- L'activation échoue si les privilèges effectifs persistent par héritage.
- Un trigger temporaire inconditionnel refuse `INSERT`, `UPDATE` et `DELETE` sur
  `storage.objects`, y compris pour les chemins privilégiés.
- `deactivate-maintenance.sql` refuse la restauration si les appartenances de
  rôles ou les ACL ont dérivé. Il rétablit chaque droit sous son grantor initial.
- Activation et désactivation sont transactionnelles et protégées par le même
  verrou consultatif transactionnel.

## Ordre opératoire distant — après autorisation explicite uniquement

1. Activer **Vercel Authentication → All Deployments**.
2. Vérifier la protection de `patrigest.fr`, `www.patrigest.fr`, du domaine
   Vercel et des routes `/api` sans lien de contournement.
3. Suspendre les nouvelles inscriptions dans Supabase Auth.
4. Attendre la fin des requêtes applicatives déjà engagées.
5. Capturer et conserver hors dépôt la sortie de `capture-integrity.sql`.
6. Exécuter `activate-maintenance.sql` avec une connexion PostgreSQL
   administrative explicitement vérifiée.
7. Exécuter `inspect-maintenance.sql` et les contrôles Data API/Storage du
   harnais de répétition.
8. Réaliser une sauvegarde fraîche PostgreSQL/Auth/Storage et son manifeste.
9. Effectuer le dry-run, puis appliquer les 25 migrations attendues seulement.
10. Déployer la v0.9.2 et vérifier les migrations, données, ACL, RPC fermées et
    indicateurs expérimentaux désactivés.
11. Exécuter `deactivate-maintenance.sql`.
12. Comparer les contrôles d'intégrité et effectuer les tests de fumée derrière
    Vercel Authentication.
13. Réactiver les inscriptions.
14. Désactiver Vercel Authentication en dernier.

## Critères d'arrêt

- cible, URL, ports ou référence projet non démontrés ;
- migration proposée différente des 25 migrations validées ;
- privilège effectif résiduel sur `public` après activation ;
- mutation Data API ou Storage qui réussit pendant la maintenance ;
- dérive de données, de documents, d'ACL ou de rôle ;
- sauvegarde incomplète ;
- erreur de migration, de build ou de test de fumée ;
- état Supabase Auth ou Storage ambigu.

En cas d'échec, conserver Vercel Authentication, les inscriptions suspendues et
les protections SQL. Ne pas ouvrir le site. Corriger en avant ou restaurer de
façon coordonnée PostgreSQL/Auth/Storage et l'application. Une désactivation
SQL échouée est atomiquement annulée : inspecter l'état, corriger la dérive et
relancer le même script ; ne jamais accorder manuellement des droits supposés.

## Limites

Le trigger protège le catalogue Storage. Comme PostgreSQL et le service objet
ne forment pas une transaction distribuée, un refus après réception d'octets
par Storage doit aussi être vérifié au niveau de l'API et du backend local. La
répétition 05D documente ce comportement ; aucune atomicité non démontrée n'est
présumée.

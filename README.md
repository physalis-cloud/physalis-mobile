# Physalis — app mobile

App iOS de [Physalis](https://physalis.cloud) : le coffre dans le téléphone, et
bientôt le remplissage automatique des mots de passe dans Safari et les apps.
Android suivra sur la même architecture.

## Architecture

- **Écrans** : l'app charge le Physalis web (`https://vault.physalis.cloud`)
  dans une WebView [Capacitor](https://capacitorjs.com). Aucune interface
  embarquée hormis la page hors ligne (`www/offline.html`). Réservée au
  service cloud.
- **Natif (Swift)** :
  - `PhysalisAuth` (`ios/App/App/PhysalisAuthPlugin.swift`) reçoit de la page le
    jeton d'app (30 jours, propre à l'appareil) et le range dans le trousseau
    derrière Face ID. Contrat côté web : `lib/native-app.ts` du vault.
  - `PrivacyLock` cache l'app dans le sélecteur d'apps et demande Face ID au
    lancement et après une minute en arrière-plan.
  - L'extension de remplissage automatique arrive dans un second temps ; elle
    lira le même trousseau.
- **Pas de Mac requis** : le projet Xcode est décrit dans `ios/App/project.yml`
  ([XcodeGen](https://github.com/yonaskolb/XcodeGen)) et généré par la CI, qui
  compile, signe et envoie sur TestFlight (`.github/workflows/ios-testflight.yml`).

## Mise en place (une fois)

Côté Apple, avec le compte développeur ArgoWeb :

1. **Identifiant** : Certificates, Identifiers & Profiles → Identifiers → `+` →
   App IDs → App, bundle ID explicite `cloud.physalis.app`, sans capacité
   particulière.
2. **App Store Connect** : Apps → `+` → Nouvelle app, plateforme iOS, nom
   « Physalis », bundle ID `cloud.physalis.app`, SKU au choix.
3. **Clé d'API** : Utilisateurs et accès → Intégrations → API App Store
   Connect → clé d'équipe, rôle **Admin** (nécessaire pour que Xcode crée
   certificats et profils). Télécharger le `.p8` (une seule fois possible).
4. **TestFlight** : dans l'app, onglet TestFlight → test interne → s'ajouter
   comme testeur.

Côté GitHub, secrets du dépôt (Settings → Secrets and variables → Actions) :

| Secret | Valeur |
|---|---|
| `APPLE_TEAM_ID` | identifiant d'équipe (Membership details) |
| `ASC_KEY_ID` | identifiant de la clé d'API |
| `ASC_ISSUER_ID` | Issuer ID affiché au-dessus de la liste des clés |
| `ASC_KEY_P8` | contenu complet du fichier `.p8` |

Puis lancer le workflow « iOS → TestFlight » (onglet Actions, ou un push sur
`main`). Le build apparaît dans TestFlight après le traitement d'Apple
(5 à 30 minutes).

## Développer

```sh
npm ci
```

Le code Swift ne se compile que sur macOS : sur un autre système, c'est la CI
qui compile. `npx cap sync ios` exige le projet Xcode généré, donc un Mac ou la
CI.

## Licence

MIT

import type { CapacitorConfig } from '@capacitor/cli';

// L'app charge le Physalis web distant (plan mots-de-passe-quotidien §5 bis,
// D1' et D7') : réservée au cloud, entrée par le portail partagé, qui renvoie
// vers le sous-domaine de l'espace après connexion. Aucune interface embarquée
// hormis la page hors ligne.
//
// ⚠️ L'adresse figure aussi dans ios/App/Shared/PhysalisConfig.swift (API du
// plugin natif et de l'extension de remplissage) : les deux doivent bouger
// ensemble.
const VAULT_URL = 'https://vault.physalis.cloud';

const config: CapacitorConfig = {
  appId: 'cloud.physalis.app',
  appName: 'Physalis',
  webDir: 'www',
  server: {
    url: VAULT_URL,
    // Portail partagé → <slug>.physalis.cloud : la redirection doit rester
    // dans l'app. Tout autre domaine s'ouvre dans Safari.
    allowNavigation: ['*.physalis.cloud'],
    // Réseau absent ou serveur injoignable : page locale au lieu d'un écran
    // blanc.
    errorPath: 'offline.html',
  },
  ios: {
    // La page web n'a pas de marges pour l'encoche : on laisse iOS les poser.
    contentInset: 'always',
    // Permet au vault de reconnaître l'app dans ses journaux.
    appendUserAgent: 'PhysalisApp',
  },
};

export default config;

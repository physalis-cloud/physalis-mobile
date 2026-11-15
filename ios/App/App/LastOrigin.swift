import Foundation

/// Adresse de l'espace où vit la session web, pour y rouvrir l'app.
///
/// Pourquoi : l'app démarre sur le portail partagé (`vault.physalis.cloud`),
/// qui renvoie après connexion vers le sous-domaine de l'espace
/// (`<slug>.physalis.cloud`). Le cookie de session est posé sur CE
/// sous-domaine et n'est pas partagé (pas de COOKIE_DOMAIN en prod). Rouvrir
/// le portail au lancement présentait donc l'écran de connexion — mot de passe
/// et TOTP à chaque ouverture — alors que la session de l'espace était encore
/// valide (retour de test du 2026-11-15).
///
/// Ce n'est qu'une adresse (pas un secret) : UserDefaults suffit. Seule une
/// origine `https` de physalis.cloud est retenue ou rendue.
enum LastOrigin {
    private static let key = "physalis.lastOrigin"

    /// Origine retenue, ou nil (premier lancement, après déconnexion).
    static var value: String? {
        guard let stored = UserDefaults.standard.string(forKey: key),
              let url = URL(string: stored),
              url.scheme == "https",
              PhysalisConfig.isTrusted(host: url.host)
        else { return nil }
        return stored
    }

    static func remember(_ pageURL: URL?) {
        guard let url = pageURL, url.scheme == "https",
              let host = url.host, PhysalisConfig.isTrusted(host: host)
        else { return }
        UserDefaults.standard.set("https://\(host)", forKey: key)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

import Foundation

/// Réglages partagés par l'app et (à venir, R4) l'extension de remplissage.
enum PhysalisConfig {
    /// ⚠️ Même adresse que `VAULT_URL` dans capacitor.config.ts : les deux
    /// bougent ensemble. App réservée au cloud (plan §5 bis, D7').
    static let baseURL = URL(string: "https://vault.physalis.cloud")!

    /// Domaine dont les pages ont le droit de parler au plugin natif.
    static let trustedDomain = "physalis.cloud"

    /// Groupe de trousseau partagé app ↔ extension, préfixé par l'identifiant
    /// d'équipe. Lu dans l'Info.plist, où Xcode résout
    /// `$(AppIdentifierPrefix)` à la compilation.
    static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "PhysalisKeychainGroup") as? String
    }

    /// Vrai si `host` est physalis.cloud ou l'un de ses sous-domaines.
    static func isTrusted(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == trustedDomain || host.hasSuffix("." + trustedDomain)
    }
}

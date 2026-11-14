import Foundation
import LocalAuthentication
import Security

/// Jeton d'app (30 jours, plan §5 bis, D3') et ses métadonnées, dans le
/// trousseau.
///
/// Trois éléments :
///   - `deviceId` : UUID tiré une fois, propre à l'app (pas de groupe partagé).
///   - `meta`     : compte, espace, dates. Lisible SANS Face ID : la page en a
///                  besoin à chaque ouverture pour décider d'un renouvellement.
///   - `token`    : le jeton lui-même, protégé par la biométrie
///                  (`biometryCurrentSet`) et jamais synchronisé ni sauvegardé
///                  (`WhenPasscodeSetThisDeviceOnly`). Le lire demande Face ID ;
///                  un visage ou un doigt ajouté l'invalide.
///
/// `meta` et `token` vivent dans le groupe partagé avec l'extension.
enum SessionStore {
    private static let deviceService = "cloud.physalis.app.device"
    private static let sessionService = "cloud.physalis.app.session"

    struct Meta: Codable {
        let email: String
        let tenantSlug: String
        let issuedAt: Int
        let expiresAt: Int
    }

    enum StoreError: Error {
        /// Pas de code sur l'appareil : impossible de protéger le jeton.
        case passcodeNotSet
        case keychain(OSStatus)
    }

    // MARK: - deviceId

    static func deviceId() -> String {
        let query = baseQuery(service: deviceService, account: "deviceId", shared: false)
        if let data = copyData(query), let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString.lowercased()
        var add = query
        add[kSecValueData as String] = Data(id.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return id
    }

    // MARK: - Session

    /// Métadonnées du jeton rangé, ou nil si aucun jeton UTILISABLE n'est
    /// présent (absent, ou invalidé par un changement de biométrie).
    static func meta() -> Meta? {
        guard tokenExists(),
              let data = copyData(baseQuery(service: sessionService, account: "meta", shared: true))
        else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    static func store(token: String, meta: Meta) throws {
        clear()

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw StoreError.passcodeNotSet
        }

        var tokenItem = baseQuery(service: sessionService, account: "token", shared: true)
        tokenItem[kSecValueData as String] = Data(token.utf8)
        tokenItem[kSecAttrAccessControl as String] = access
        let tokenStatus = SecItemAdd(tokenItem as CFDictionary, nil)
        guard tokenStatus == errSecSuccess else {
            // errSecAuthFailed / errSecParam ici = pas de code ou pas de
            // biométrie enrôlée sur l'appareil.
            throw tokenStatus == errSecAuthFailed ? StoreError.passcodeNotSet : StoreError.keychain(tokenStatus)
        }

        var metaItem = baseQuery(service: sessionService, account: "meta", shared: true)
        metaItem[kSecValueData as String] = try JSONEncoder().encode(meta)
        metaItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let metaStatus = SecItemAdd(metaItem as CFDictionary, nil)
        guard metaStatus == errSecSuccess else {
            clear()
            throw StoreError.keychain(metaStatus)
        }
    }

    /// Lit le jeton : déclenche Face ID (ou le code). Utilisé par l'extension
    /// de remplissage (R4), jamais par l'app.
    static func readToken(reason: String) -> String? {
        let context = LAContext()
        context.localizedReason = reason
        var query = baseQuery(service: sessionService, account: "token", shared: true)
        query[kSecUseAuthenticationContext as String] = context
        guard let data = copyData(query) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        for account in ["token", "meta"] {
            SecItemDelete(baseQuery(service: sessionService, account: account, shared: true) as CFDictionary)
        }
    }

    // MARK: - Trousseau

    /// Présence du jeton SANS déclencher Face ID : avec l'interaction
    /// interdite, un élément présent répond errSecInteractionNotAllowed.
    private static func tokenExists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(service: sessionService, account: "token", shared: true)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private static func baseQuery(service: String, account: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared, let group = PhysalisConfig.keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func copyData(_ base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

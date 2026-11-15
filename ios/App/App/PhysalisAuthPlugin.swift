import Capacitor
import Foundation

/// Plugin `PhysalisAuth` : reçoit le jeton d'app frappé par la page web.
///
/// Contrat côté web : physalis-vault, lib/native-app.ts. Trois méthodes :
/// getState, storeSession, signOut. Le natif ne fait AUCUN appel réseau : la
/// page émet et révoque, sous sa session web.
@objc(PhysalisAuthPlugin)
public class PhysalisAuthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PhysalisAuthPlugin"
    public let jsName = "PhysalisAuth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "storeSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "signOut", returnType: CAPPluginReturnPromise),
    ]

    /// Le plugin n'écoute que les pages de physalis.cloud. La WebView n'en
    /// charge pas d'autre (allowNavigation), mais un jeton d'accès au coffre
    /// mérite une seconde garde.
    private func fromTrustedPage(_ call: CAPPluginCall) -> Bool {
        if PhysalisConfig.isTrusted(host: pageURL()?.host) { return true }
        call.reject("Untrusted origin", "UNTRUSTED")
        return false
    }

    /// URL de la page courante. `webView` est un objet UIKit : on le lit sur le
    /// fil principal, sans s'y bloquer si l'appel y arrive déjà.
    private func pageURL() -> URL? {
        var url: URL?
        if Thread.isMainThread {
            url = bridge?.webView?.url
        } else {
            DispatchQueue.main.sync { url = self.bridge?.webView?.url }
        }
        return url
    }

    @objc func getState(_ call: CAPPluginCall) {
        guard fromTrustedPage(call) else { return }
        // Appelé par CHAQUE page connectée de l'espace (NativeAppHandoff du
        // layout du dashboard), et pas seulement quand un jeton est remis — qui
        // n'arrive qu'une fois par 24 h. Retenir l'origine ICI : sinon un
        // utilisateur déjà muni d'un jeton n'est jamais rouvert sur son espace.
        LastOrigin.remember(pageURL())
        let meta = SessionStore.meta()
        call.resolve([
            "platform": "ios",
            "deviceId": SessionStore.deviceId(),
            "issuedAt": meta.map { $0.issuedAt as Any } ?? NSNull(),
            "email": meta.map { $0.email as Any } ?? NSNull(),
            "tenantSlug": meta.map { $0.tenantSlug as Any } ?? NSNull(),
        ])
    }

    @objc func storeSession(_ call: CAPPluginCall) {
        guard fromTrustedPage(call) else { return }
        guard let token = call.getString("sessionToken"),
              token.hasPrefix("sv_plugin_"),
              let email = call.getString("email"),
              let tenantSlug = call.getString("tenantSlug"),
              let expiresAt = call.getInt("expiresAt"),
              let issuedAt = call.getInt("issuedAt")
        else {
            call.reject("Invalid session", "INVALID")
            return
        }
        do {
            try SessionStore.store(
                token: token,
                meta: .init(email: email, tenantSlug: tenantSlug, issuedAt: issuedAt, expiresAt: expiresAt)
            )
            // La page qui remet le jeton est celle de l'espace où vit la session
            // web : l'app y rouvrira directement (cf. LastOrigin).
            LastOrigin.remember(pageURL())
            call.resolve()
            // Suggestions du clavier : le jeton est en clair ICI, sans Face ID
            // (il arrive de la page) — c'est le moment de rafraîchir la liste.
            Task { await CredentialIdentities.sync(token: token) }
        } catch SessionStore.StoreError.passcodeNotSet {
            call.reject("A device passcode is required", "PASSCODE_NOT_SET")
        } catch {
            call.reject("Keychain error", "KEYCHAIN", error)
        }
    }

    @objc func signOut(_ call: CAPPluginCall) {
        // Pas de garde d'origine : effacer ne divulgue rien.
        SessionStore.clear()
        // Déconnexion : le prochain lancement repart du portail partagé.
        LastOrigin.forget()
        // Plus aucune suggestion Physalis au-dessus du clavier.
        CredentialIdentities.clear()
        call.resolve()
    }
}

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
        // `webView` est un objet UIKit : on le lit sur le fil principal, sans
        // s'y bloquer si l'appel y arrive déjà.
        var host: String?
        if Thread.isMainThread {
            host = bridge?.webView?.url?.host
        } else {
            DispatchQueue.main.sync { host = self.bridge?.webView?.url?.host }
        }
        if PhysalisConfig.isTrusted(host: host) { return true }
        call.reject("Untrusted origin", "UNTRUSTED")
        return false
    }

    @objc func getState(_ call: CAPPluginCall) {
        guard fromTrustedPage(call) else { return }
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
            call.resolve()
        } catch SessionStore.StoreError.passcodeNotSet {
            call.reject("A device passcode is required", "PASSCODE_NOT_SET")
        } catch {
            call.reject("Keychain error", "KEYCHAIN", error)
        }
    }

    @objc func signOut(_ call: CAPPluginCall) {
        // Pas de garde d'origine : effacer ne divulgue rien.
        SessionStore.clear()
        call.resolve()
    }
}

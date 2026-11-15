import AuthenticationServices
import Foundation

/// Suggestions de la barre du clavier (QuickType) : iOS propose « identifiant —
/// Physalis » directement sur un champ de connexion, sans passer par la liste.
///
/// iOS n'interroge pas l'extension à ce moment-là : il lit une liste que l'app
/// lui a remise À L'AVANCE (`ASCredentialIdentityStore`). Elle ne contient que
/// des couples domaine + identifiant, JAMAIS de mot de passe — celui-ci n'est
/// demandé à `/api/plugin/match` qu'au toucher d'une suggestion, après Face ID.
///
/// Alimentée par l'inventaire sans secret (`/api/plugin/items`) :
///   - par l'app, quand la page lui remet un jeton (connexion, puis au plus
///     une fois par 24 h) ;
///   - par l'extension, à chaque ouverture déverrouillée.
/// Vidée à la déconnexion.
enum CredentialIdentities {

    /// `recordIdentifier` = "<id>|<domaine>" : de quoi retrouver l'entrée dans
    /// `/match` (par domaine, puis par id) au toucher de la suggestion.
    static func recordIdentifier(id: String, domain: String) -> String {
        "\(id)|\(domain)"
    }

    static func parse(recordIdentifier: String?) -> (id: String, domain: String)? {
        guard let value = recordIdentifier,
              let separator = value.firstIndex(of: "|") else { return nil }
        let id = String(value[..<separator])
        let domain = String(value[value.index(after: separator)...])
        guard !id.isEmpty, !domain.isEmpty else { return nil }
        return (id, domain)
    }

    /// Remplace la liste par l'inventaire courant. Silencieux en cas d'échec :
    /// les suggestions sont un confort, la liste de l'extension reste là.
    static func sync(token: String) async {
        guard await isEnabled() else { return }
        guard let items = try? await PhysalisAPI.items(token: token) else { return }
        let identities = items.map { item in
            ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: item.domain, type: .domain),
                // Sans identifiant connu (Services, comptes de projet), le nom
                // de l'entrée tient lieu de libellé.
                user: item.user ?? item.title,
                recordIdentifier: recordIdentifier(id: item.id, domain: item.domain)
            )
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) { _, _ in
                continuation.resume()
            }
        }
    }

    static func clear() {
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities(nil)
    }

    /// Physalis est-il activé dans Réglages → Remplissage automatique ? Sinon
    /// iOS refuse la liste : inutile d'appeler le serveur.
    private static func isEnabled() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            ASCredentialIdentityStore.shared.getState { state in
                continuation.resume(returning: state.isEnabled)
            }
        }
    }
}

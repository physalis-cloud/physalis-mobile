import Foundation

/// Appels au vault (extension de remplissage, et l'app pour l'inventaire), avec le jeton d'app (Bearer). Mêmes routes
/// que l'extension navigateur :
///   - GET /api/plugin/match?domain= : identifiants AVEC mot de passe, pour un
///     domaine (une ligne d'audit par appel côté serveur) ;
///   - GET /api/plugin/items : inventaire SANS secret, pour la recherche.
/// Aucune valeur n'est journalisée ni mise en cache.
enum PhysalisAPI {

    /// Un identifiant prêt à remplir.
    struct Credential {
        let id: String
        let title: String
        let subtitle: String
        let user: String
        let password: String
    }

    /// Une ligne de l'inventaire : de quoi l'afficher et la retrouver dans
    /// `/match` (par `domain`, puis par `id`).
    struct Item {
        let id: String
        let title: String
        let subtitle: String
        let domain: String
        /// Identifiant de connexion, connu pour les entrées de coffre seulement
        /// (celui des Services et comptes de projet est chiffré avec le mot
        /// de passe et n'est pas dans l'inventaire).
        let user: String?
    }

    enum APIError: Error {
        /// Jeton expiré ou révoqué : il faut rouvrir l'app.
        case unauthorized
        case http(Int)
        case invalidResponse
    }

    // MARK: - Routes

    static func match(domain: String, token: String) async throws -> [Credential] {
        var components = URLComponents(
            url: PhysalisConfig.baseURL.appendingPathComponent("api/plugin/match"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "domain", value: domain)]
        let json = try await get(components.url!, token: token)

        var out: [Credential] = []
        for entry in json["vault"] as? [[String: Any]] ?? [] {
            // Connexion tierce (« se connecter avec Google ») : rien à remplir.
            if let signInWith = entry["signInWith"] as? String, !signInWith.isEmpty { continue }
            guard let id = entry["id"] as? String,
                  let password = entry["password"] as? String, !password.isEmpty else { continue }
            let user = entry["username"] as? String ?? ""
            out.append(Credential(
                id: id,
                title: entry["name"] as? String ?? user,
                subtitle: user,
                user: user,
                password: password
            ))
        }
        for key in ["services", "accounts"] {
            for entry in json[key] as? [[String: Any]] ?? [] {
                guard let id = entry["id"] as? String,
                      let password = entry["password"] as? String, !password.isEmpty else { continue }
                let user = entry["user"] as? String ?? ""
                let project = entry["projectName"] as? String ?? ""
                out.append(Credential(
                    id: id,
                    title: entry["name"] as? String ?? user,
                    subtitle: project.isEmpty ? user : "\(user) · \(project)",
                    user: user,
                    password: password
                ))
            }
        }
        return out
    }

    static func items(token: String) async throws -> [Item] {
        let json = try await get(
            PhysalisConfig.baseURL.appendingPathComponent("api/plugin/items"),
            token: token
        )
        var out: [Item] = []
        for entry in json["vault"] as? [[String: Any]] ?? [] {
            if let signInWith = entry["signInWith"] as? String, !signInWith.isEmpty { continue }
            guard let id = entry["id"] as? String,
                  let domain = entry["domain"] as? String, !domain.isEmpty else { continue }
            let username = entry["username"] as? String
            out.append(Item(
                id: id,
                title: entry["name"] as? String ?? domain,
                subtitle: username ?? domain,
                domain: domain,
                user: (username?.isEmpty ?? true) ? nil : username
            ))
        }
        for key in ["services", "accounts"] {
            for entry in json[key] as? [[String: Any]] ?? [] {
                guard let id = entry["id"] as? String,
                      let domain = entry["domain"] as? String, !domain.isEmpty else { continue }
                out.append(Item(
                    id: id,
                    title: entry["name"] as? String ?? domain,
                    subtitle: entry["projectName"] as? String ?? domain,
                    domain: domain,
                    user: nil
                ))
            }
        }
        return out
    }

    // MARK: - HTTP

    private static func get(_ url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        // Session éphémère : ni cache disque ni cookies pour des réponses qui
        // portent des mots de passe.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }
}

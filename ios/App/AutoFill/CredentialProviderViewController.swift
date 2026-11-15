import AuthenticationServices
import UIKit

/// Extension de remplissage automatique (plan mots-de-passe-quotidien §5 bis,
/// R4). iOS l'ouvre quand l'utilisateur choisit Physalis au-dessus du clavier,
/// sur un champ de connexion.
///
/// 1. Lit le jeton d'app rangé par l'app dans le trousseau partagé — Face ID
///    est demandé par le trousseau lui-même (`biometryCurrentSet`).
/// 2. Propose les identifiants du domaine demandé (`/api/plugin/match`).
/// 3. Recherche libre dans l'inventaire sans secret (`/api/plugin/items`) ;
///    le mot de passe n'est demandé qu'au choix d'une ligne.
///
/// Pas de débogueur sans Mac : toute erreur est AFFICHÉE dans l'extension,
/// avec son code, pour être lue sur l'iPhone. Aucun mot de passe n'est
/// journalisé ni conservé après la réponse.
class CredentialProviderViewController: ASCredentialProviderViewController,
    UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    private var domain: String?
    private var token: String?
    private var matches: [PhysalisAPI.Credential] = []
    private var inventory: [PhysalisAPI.Item]?
    private var searchResults: [PhysalisAPI.Item] = []
    /// Entrée choisie via une suggestion du clavier : remplie dès que `/match`
    /// répond, sans afficher la liste.
    private var pendingRecordId: String?

    private let domainLabel = UILabel()
    private let searchBar = UISearchBar()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var isSearching: Bool {
        !(searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Points d'entrée iOS

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        loadViewIfNeeded()
        domain = serviceIdentifiers.lazy.compactMap(Self.host(of:)).first
        domainLabel.text = domain ?? Text.noDomain
        unlock()
    }

    /// Suggestion du clavier touchée. Le jeton est protégé par la biométrie :
    /// impossible de le lire sans interface, on demande donc à iOS de l'ouvrir
    /// (il rappelle alors `prepareInterfaceToProvideCredential`).
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        loadViewIfNeeded()
        if let record = CredentialIdentities.parse(recordIdentifier: credentialIdentity.recordIdentifier) {
            domain = record.domain
            pendingRecordId = record.id
        } else {
            domain = credentialIdentity.serviceIdentifier.identifier.lowercased()
        }
        domainLabel.text = domain
        unlock()
    }

    // MARK: - Déroulé

    private func unlock() {
        setStatus(Text.unlocking, loading: true)
        Task {
            // Lecture du trousseau HORS du fil principal : elle attend Face ID.
            let token = await Task.detached(priority: .userInitiated) {
                SessionStore.readToken(reason: Text.unlockReason)
            }.value
            guard let token = token else {
                setStatus(Text.notConnected, loading: false)
                return
            }
            self.token = token
            // Rafraîchit les suggestions du clavier en tâche de fond.
            Task.detached(priority: .utility) {
                await CredentialIdentities.sync(token: token)
            }
            await loadMatches()
        }
    }

    private func loadMatches() async {
        guard let token = token else { return }
        guard let domain = domain else {
            setStatus(Text.searchHint, loading: false)
            return
        }
        setStatus(Text.loading, loading: true)
        do {
            matches = try await PhysalisAPI.match(domain: domain, token: token)
            if let wanted = pendingRecordId {
                pendingRecordId = nil
                if let credential = matches.first(where: { $0.id == wanted }) {
                    complete(with: credential)
                    return
                }
                // Suggestion périmée (entrée supprimée ou déplacée) : on
                // retombe sur la liste du site.
            }
            setStatus(matches.isEmpty ? Text.noMatch(domain) : nil, loading: false)
        } catch {
            setStatus(Text.describe(error), loading: false)
        }
        tableView.reloadData()
    }

    private func loadInventoryIfNeeded() async {
        guard inventory == nil, let token = token else { return }
        setStatus(Text.loading, loading: true)
        do {
            inventory = try await PhysalisAPI.items(token: token)
            setStatus(nil, loading: false)
        } catch {
            setStatus(Text.describe(error), loading: false)
        }
    }

    private func filterInventory() {
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        searchResults = (inventory ?? []).filter {
            $0.title.lowercased().contains(query)
                || $0.subtitle.lowercased().contains(query)
                || $0.domain.lowercased().contains(query)
        }
        if isSearching && inventory != nil {
            setStatus(searchResults.isEmpty ? Text.noSearchResult : nil, loading: false)
        }
        tableView.reloadData()
    }

    private func choose(_ item: PhysalisAPI.Item) {
        guard let token = token else { return }
        setStatus(Text.loading, loading: true)
        Task {
            do {
                let found = try await PhysalisAPI.match(domain: item.domain, token: token)
                if let credential = found.first(where: { $0.id == item.id }) {
                    complete(with: credential)
                } else {
                    setStatus(Text.unavailable, loading: false)
                }
            } catch {
                setStatus(Text.describe(error), loading: false)
            }
        }
    }

    private func complete(with credential: PhysalisAPI.Credential) {
        let selected = ASPasswordCredential(user: credential.user, password: credential.password)
        extensionContext.completeRequest(withSelectedCredential: selected, completionHandler: nil)
    }

    @objc private func cancelTapped() {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userCanceled.rawValue
        ))
    }

    // MARK: - Liste

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isSearching ? searchResults.count : matches.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching { return searchResults.isEmpty ? nil : Text.searchSection }
        return matches.isEmpty ? nil : Text.matchSection
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let title: String
        let subtitle: String
        if isSearching {
            let item = searchResults[indexPath.row]
            title = item.title
            subtitle = item.subtitle
        } else {
            let credential = matches[indexPath.row]
            title = credential.title
            subtitle = credential.subtitle
        }
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "key.fill")
        cell.imageView?.tintColor = .systemOrange
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearching {
            choose(searchResults[indexPath.row])
        } else {
            complete(with: matches[indexPath.row])
        }
    }

    // MARK: - Recherche

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard token != nil else { return }
        if !isSearching {
            setStatus(matches.isEmpty && domain != nil ? Text.noMatch(domain ?? "") : nil, loading: false)
            tableView.reloadData()
            return
        }
        Task {
            await loadInventoryIfNeeded()
            filterInventory()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Interface

    private func setStatus(_ text: String?, loading: Bool) {
        statusLabel.text = text
        statusLabel.isHidden = (text == nil)
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    private func buildInterface() {
        view.backgroundColor = .systemGroupedBackground

        let titleLabel = UILabel()
        titleLabel.text = "Physalis"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        domainLabel.font = .preferredFont(forTextStyle: .subheadline)
        domainLabel.textColor = .secondaryLabel

        let cancel = UIButton(type: .system)
        cancel.setTitle(Text.cancel, for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let titles = UIStackView(arrangedSubviews: [titleLabel, domainLabel])
        titles.axis = .vertical
        titles.spacing = 2

        let header = UIStackView(arrangedSubviews: [titles, spinner, cancel])
        header.alignment = .center
        header.spacing = 12
        spinner.hidesWhenStopped = true

        searchBar.placeholder = Text.searchPlaceholder
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.delegate = self

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .callout)
        statusLabel.textColor = .secondaryLabel
        statusLabel.isHidden = true

        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag

        let stack = UIStackView(arrangedSubviews: [header, searchBar, statusLabel, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }

    /// Domaine demandé par iOS : hôte d'une URL (Safari) ou domaine associé
    /// (app native).
    private static func host(of identifier: ASCredentialServiceIdentifier) -> String? {
        switch identifier.type {
        case .URL:
            return URL(string: identifier.identifier)?.host?.lowercased()
        case .domain:
            let value = identifier.identifier.lowercased()
            return value.isEmpty ? nil : value
        @unknown default:
            return nil
        }
    }
}

/// Textes de l'extension : français par défaut, anglais et espagnol.
private enum Text {
    private static var lang: String {
        String((Locale.preferredLanguages.first ?? "fr").prefix(2))
    }

    private static func pick(_ fr: String, _ en: String, _ es: String) -> String {
        switch lang {
        case "en": return en
        case "es": return es
        default: return fr
        }
    }

    static var unlockReason: String { pick("Accéder à vos mots de passe Physalis", "Access your Physalis passwords", "Acceder a sus contraseñas de Physalis") }
    static var unlocking: String { pick("Déverrouillage…", "Unlocking…", "Desbloqueando…") }
    static var loading: String { pick("Chargement…", "Loading…", "Cargando…") }
    static var cancel: String { pick("Annuler", "Cancel", "Cancelar") }
    static var noDomain: String { pick("Aucun site indiqué", "No site provided", "Ningún sitio indicado") }
    static var searchPlaceholder: String { pick("Rechercher dans Physalis", "Search Physalis", "Buscar en Physalis") }
    static var searchHint: String { pick("Recherchez l'identifiant à utiliser.", "Search for the login to use.", "Busque el acceso que desea usar.") }
    static var matchSection: String { pick("Pour ce site", "For this site", "Para este sitio") }
    static var searchSection: String { pick("Résultats", "Results", "Resultados") }
    static var noSearchResult: String { pick("Aucun résultat.", "No results.", "Sin resultados.") }
    static var unavailable: String { pick("Cet identifiant n'est plus disponible.", "This login is no longer available.", "Este acceso ya no está disponible.") }
    static var notConnected: String {
        pick("Ouvrez l'app Physalis et connectez-vous : le remplissage automatique utilise la session de l'app.",
             "Open the Physalis app and sign in: AutoFill uses the app's session.",
             "Abra la app Physalis e inicie sesión: el autorrelleno usa la sesión de la app.")
    }

    static func noMatch(_ domain: String) -> String {
        pick("Aucun identifiant pour \(domain). Utilisez la recherche.",
             "No login for \(domain). Use search.",
             "Ningún acceso para \(domain). Use la búsqueda.")
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case PhysalisAPI.APIError.unauthorized:
            return pick("Session expirée : ouvrez l'app Physalis pour la renouveler.",
                        "Session expired: open the Physalis app to renew it.",
                        "Sesión caducada: abra la app Physalis para renovarla.")
        case PhysalisAPI.APIError.http(let code):
            return pick("Erreur du serveur (\(code)).", "Server error (\(code)).", "Error del servidor (\(code)).")
        default:
            return pick("Physalis est injoignable. Vérifiez la connexion.",
                        "Physalis is unreachable. Check your connection.",
                        "Physalis no está disponible. Compruebe la conexión.")
        }
    }
}

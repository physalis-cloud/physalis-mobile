import LocalAuthentication
import UIKit

/// Verrou de l'app : la WebView montre des mots de passe, on la cache
///   - dans l'aperçu du sélecteur d'apps (dès que l'app passe en arrière-plan) ;
///   - au lancement et au retour après `relockAfter` secondes, jusqu'à Face ID
///     (ou le code de l'appareil).
/// Sans code ni biométrie configurés sur l'appareil, rien n'est verrouillé :
/// il n'y aurait aucun moyen de déverrouiller.
final class PrivacyLock {
    private let relockAfter: TimeInterval = 60
    private weak var window: UIWindow?
    private var cover: UIView?
    private var backgroundedAt: Date?
    private var locked = false
    private var authenticating = false

    init(window: UIWindow) {
        self.window = window
    }

    /// Au lancement.
    func lockAtLaunch() {
        guard canAuthenticate() else { return }
        locked = true
        showCover()
    }

    /// L'app quitte le premier plan (sélecteur d'apps, appel, arrière-plan).
    func sceneWillResignActive() {
        showCover()
    }

    func sceneDidEnterBackground() {
        backgroundedAt = Date()
    }

    func sceneDidBecomeActive() {
        if let since = backgroundedAt, Date().timeIntervalSince(since) >= relockAfter, canAuthenticate() {
            locked = true
        }
        backgroundedAt = nil
        if locked {
            authenticate()
        } else {
            hideCover()
        }
    }

    private func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L10n.unlockReason) { success, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if success {
                    self.locked = false
                    self.hideCover()
                } else {
                    self.showUnlockButton()
                }
            }
        }
    }

    // MARK: - Écran de verrouillage

    private func showCover() {
        guard cover == nil, let window = window else { return }
        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground

        let logo = UIImageView(image: UIImage(systemName: "lock.fill"))
        logo.tintColor = .secondaryLabel
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            logo.widthAnchor.constraint(equalToConstant: 56),
            logo.heightAnchor.constraint(equalToConstant: 56),
        ])

        window.addSubview(view)
        cover = view
    }

    private func showUnlockButton() {
        guard let cover = cover, cover.viewWithTag(1) == nil else { return }
        let button = UIButton(type: .system)
        button.tag = 1
        button.setTitle(L10n.unlock, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)
        cover.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: cover.centerYAnchor, constant: 40),
        ])
    }

    @objc private func unlockTapped() {
        authenticate()
    }

    private func hideCover() {
        guard !locked else { return }
        cover?.removeFromSuperview()
        cover = nil
    }
}

/// Textes natifs (FR par défaut, EN, ES), comme la page hors ligne.
enum L10n {
    private static var lang: String {
        String((Locale.preferredLanguages.first ?? "fr").prefix(2))
    }

    static var unlockReason: String {
        switch lang {
        case "en": return "Unlock Physalis"
        case "es": return "Desbloquear Physalis"
        default: return "Déverrouiller Physalis"
        }
    }

    static var unlock: String {
        switch lang {
        case "en": return "Unlock"
        case "es": return "Desbloquear"
        default: return "Déverrouiller"
        }
    }
}

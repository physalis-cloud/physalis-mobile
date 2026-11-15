import Capacitor
import UIKit

/// Contrôleur de la WebView : enregistre le plugin local `PhysalisAuth` et
/// rouvre l'app sur l'espace de l'utilisateur.
class PhysalisBridgeViewController: CAPBridgeViewController {

    /// Point de départ : l'espace où vit la session web s'il est connu
    /// (LastOrigin), sinon le portail partagé de capacitor.config.ts. Les
    /// autres sous-domaines restent navigables (allowNavigation
    /// `*.physalis.cloud`).
    override func instanceDescriptor() -> InstanceDescriptor {
        let descriptor = super.instanceDescriptor()
        if let origin = LastOrigin.value {
            descriptor.serverURL = origin
        }
        return descriptor
    }

    /// Un plugin écrit dans l'app (et non livré par un paquet npm) n'est pas
    /// découvert automatiquement par Capacitor.
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(PhysalisAuthPlugin())
    }
}

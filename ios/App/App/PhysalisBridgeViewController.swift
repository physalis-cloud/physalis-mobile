import Capacitor
import UIKit

/// Contrôleur de la WebView : enregistre le plugin local `PhysalisAuth`.
/// Un plugin écrit dans l'app (et non livré par un paquet npm) n'est pas
/// découvert automatiquement par Capacitor.
class PhysalisBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(PhysalisAuthPlugin())
    }
}

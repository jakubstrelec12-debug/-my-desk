import Foundation

extension Bundle {
    /// Packaged applications keep SwiftPM resources in Contents/Resources.
    /// The generated Bundle.module accessor searches the app root and the
    /// original build directory, so it cannot be used after installation.
    static let deskResources: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            if let url = Bundle.main.resourceURL?.appendingPathComponent("MyDesk_MyDesk.bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
            // Missing artwork must not terminate the user's application.
            return Bundle.main
        }
        return Bundle.module
    }()
}

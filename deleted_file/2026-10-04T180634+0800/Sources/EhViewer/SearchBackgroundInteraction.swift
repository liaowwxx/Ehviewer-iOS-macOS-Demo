#if os(iOS)
import SwiftUI
import UIKit

/// The history panel lives in searchable content, so an empty search must
/// continue passing touches to that content instead of dismissing search.
struct SearchBackgroundInteraction: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ConfigurationController {
        ConfigurationController()
    }

    func updateUIViewController(_ controller: ConfigurationController, context: Context) {
        controller.configureSearchInteraction()
    }

    final class ConfigurationController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            configureSearchInteraction()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            configureSearchInteraction()
        }

        func configureSearchInteraction() {
            var ancestor = parent
            while let controller = ancestor {
                if let searchController = controller.navigationItem.searchController {
                    searchController.obscuresBackgroundDuringPresentation = false
                    return
                }
                ancestor = controller.parent
            }
            navigationController?.topViewController?.navigationItem.searchController?
                .obscuresBackgroundDuringPresentation = false
        }
    }
}
#endif

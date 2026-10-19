import SwiftUI

struct TeakDemoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: TeakDemoLanguageListViewController(style: .insetGrouped))
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

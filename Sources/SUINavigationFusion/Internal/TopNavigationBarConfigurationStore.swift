import SwiftUI

@MainActor
final class TopNavigationBarConfigurationStore: ObservableObject {
    @Published private(set) var configuration: TopNavigationBarConfiguration
    private var signature: Signature

    init(configuration: TopNavigationBarConfiguration = .defaultMaterial) {
        self.configuration = configuration
        self.signature = Signature(configuration)
    }

    func setConfiguration(_ configuration: TopNavigationBarConfiguration) {
        let newSignature = Signature(configuration)
        guard newSignature != signature else { return }

        signature = newSignature
        self.configuration = configuration
    }
}

private extension TopNavigationBarConfigurationStore {
    struct Signature: Hashable {
        let backgroundMaterialID: String?
        let backgroundColor: Color?
        let scrollDependentBackgroundOpacity: Bool
        let dividerColor: Color?
        let titleFont: Font?
        let titleFontColor: Color?
        let titleFontWeight: Font.Weight?
        let subtitleFont: Font?
        let subtitleFontColor: Color?
        let subtitleFontWeight: Font.Weight?
        let titleStackSpacing: CGFloat?
        let tintColor: Color?
        let backButtonIconName: String?
        let backButtonIconBundleID: ObjectIdentifier?

        init(_ configuration: TopNavigationBarConfiguration) {
            backgroundMaterialID = configuration.backgroundMaterial.map { material in
                let mirror = Mirror(reflecting: material)
                if let id = mirror.children.first(where: { $0.label == "id" })?.value {
                    return String(describing: id)
                }
                return String(describing: material)
            }
            backgroundColor = configuration.backgroundColor
            scrollDependentBackgroundOpacity = configuration.scrollDependentBackgroundOpacity
            dividerColor = configuration.dividerColor
            titleFont = configuration.titleFont
            titleFontColor = configuration.titleFontColor
            titleFontWeight = configuration.titleFontWeight
            subtitleFont = configuration.subtitleFont
            subtitleFontColor = configuration.subtitleFontColor
            subtitleFontWeight = configuration.subtitleFontWeight
            titleStackSpacing = configuration.titleStackSpacing
            tintColor = configuration.tintColor
            backButtonIconName = configuration.backButtonIcon?.name
            backButtonIconBundleID = configuration.backButtonIcon?.bundle.map(ObjectIdentifier.init)
        }
    }
}

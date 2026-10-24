import SwiftUI
import UIKit

/// Keys for settings stored on the device with @AppStorage.
enum SettingsKey {
    static let unitSystem = "unitSystem"
    static let defaultBudget = "defaultBudget"
    static let preferredStyles = "preferredStyles"
    static let preferredMaterials = "preferredMaterials"
    static let minimumRating = "minimumRating"
    static let didSeedSampleData = "didSeedSampleData"
    static let lockAngles = "lockAngles"
    /// Debug builds only: fake scan and image results, to try the screens
    /// without paying for a model.
    static let demoAIFeatures = "demoAIFeatures"
    static let didFinishOnboarding = "didFinishOnboarding"
}

/// Styles a person can say they like. Used by the profile and, later,
/// by catalog recommendations.
enum StyleOption {
    static let all = ["Modern", "Scandinavian", "Warm", "Minimal", "Industrial", "Classic"]
}

/// Materials a person can say they like.
enum MaterialOption {
    static let all = ["Wood", "Metal", "Fabric", "Leather", "Glass", "Rattan"]
}

/// Choices for the lowest star rating a product may have. Zero means any.
enum RatingOption {
    static let all: [Double] = [0, 3, 3.5, 4, 4.5]

    static func title(_ rating: Double) -> String {
        rating == 0 ? "Any" : String(format: "%g+", rating)
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

import Foundation

/// Where the app's backend lives. Only these two values may ever be in the
/// app: the project URL and the *publishable* key, which Supabase designs
/// to be public (what it can do is limited by row level security).
///
/// Never put a secret key, a service-role key, or any catalog or AI key in
/// the app. Those live in Supabase secrets, used only by Edge Functions.
enum BackendConfig {
    static let projectURL = URL(string: "https://tpansxzplscfoffsscqn.supabase.co")!
    static let publishableKey = "sb_publishable_toEEjAVgGMRyDyf63CrxYg_vFIA9wvb"

    /// Sign-in, sign-up, password reset.
    static var authURL: URL { projectURL.appendingPathComponent("auth/v1") }
    /// Our Edge Functions (search-products, delete-account, ...).
    static var functionsURL: URL { projectURL.appendingPathComponent("functions/v1") }
    /// Database tables, through row level security.
    static var restURL: URL { projectURL.appendingPathComponent("rest/v1") }

    /// The address Supabase sends people back to after Google sign-in or
    /// an email link. Must also be added in the Supabase dashboard under
    /// Authentication → URL Configuration → Redirect URLs.
    static let callbackScheme = "interiordesign"
    static let callbackURL = URL(string: "interiordesign://auth-callback")!

    /// Google sign-in stays off until the Google Cloud and Supabase setup
    /// is done (see supabase/README.md).
    static let googleSignInEnabled = false
    /// Sign in with Apple needs the paid Apple Developer account.
    static let appleSignInEnabled = false

    // Paid AI features (week 5). Each stays off until a model is chosen and
    // the matching switch in Supabase's app_config is turned on too.

    /// Label item photos with a backend model instead of on-device Vision.
    static let backendLabelingEnabled = false
    /// Turn room photos into a draft outline with a backend model.
    static let roomScanEnabled = false
    /// Make AI pictures of a layout.
    static let visualizeEnabled = false
}

import Foundation

extension Notification.Name {
    /// Posted whenever a provider's connect/disconnect state changes (a `TokenStore`
    /// write/delete succeeded). `ASWebAuthenticationSession` is presented by UIKit
    /// outside SwiftUI's own view hierarchy, so dismissing it does **not** trigger
    /// `.onAppear` on the presenting view — without this, `DashboardViewModel`'s
    /// `claudeConnected`/`codexConnected` would go stale until some unrelated view
    /// transition happened to refire `.onAppear`. `DashboardView` observes this to
    /// call `refreshConnectionStatus()` immediately instead.
    static let limitsProviderConnectionChanged = Notification.Name("com.caldf.limitsapp.providerConnectionChanged")
}

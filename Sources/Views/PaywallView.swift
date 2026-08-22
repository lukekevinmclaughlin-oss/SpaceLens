import SwiftUI

#if DIRECT_DISTRIBUTION
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HolographicBackground()
            VStack(spacing: 20) {
                HoloReticle(size: 86)
                Text("SpaceLens Direct edition").font(.title2.bold()).foregroundStyle(Theme.holoIce)
                Text("Storage Time Machine, forecasts, reports, cleanup tools, and the menu-bar watcher are all permanently unlocked.")
                    .multilineTextAlignment(.center).foregroundStyle(Theme.holoCyan)
                Button("Continue") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(30)
        }
        .preferredColorScheme(.dark)
    }
}
#else
struct PaywallView: View {
    @EnvironmentObject private var purchase: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HolographicBackground()
            VStack(spacing: 22) {
                HoloReticle(size: 86)
                VStack(spacing: 7) {
                    Text("Try Storage Atlas Premium")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.holoIce)
                        .multilineTextAlignment(.center)
                    Text("Nice scan! Analysis and cleanup stay free. Premium adds Storage Time Machine, forecasts, reports, and the Mac menu-bar watcher.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.holoCyan)
                }

                VStack(alignment: .leading, spacing: 12) {
                    feature("gauge.with.needle", "Menu-bar watcher with live free-space trends")
                    feature("clock.arrow.circlepath", "Storage Time Machine with scan comparisons")
                    feature("chart.xyaxis.line", "Growth forecasts and exportable reports")
                    feature("rectangle.on.rectangle", "Visual before/after cleanup comparisons")
                    feature("lock.shield.fill", "Private scanning—your filenames never leave the device")
                }
                .padding(18)
                .frame(maxWidth: 520, alignment: .leading)
                .liquidGlass(cornerRadius: 20)

                Button { Task { await purchase.purchaseYearly() } } label: {
                    VStack(spacing: 2) {
                        Text(purchase.yearlyCallToAction).font(.headline)
                        Text(purchase.yearlyProduct == nil ? purchase.yearlyPrice : "then \(purchase.yearlyPrice)/year").font(.caption)
                    }
                        .frame(maxWidth: 420)
                        .padding(.vertical, 7)
                }
                .buttonStyle(GlassButtonStyle(tint: Theme.holoCyan, prominent: true))
                .controlSize(.large)
                .disabled(purchase.yearlyProduct == nil || purchase.isPurchasing)

                Button(purchase.monthlyCallToAction) {
                    Task { await purchase.purchaseMonthly() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.holoCyan)
                .disabled(purchase.monthlyProduct == nil || purchase.isPurchasing)

                Text("Auto-renews at the selected price until cancelled in App Store settings. Your scans and data are never deleted if the subscription ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    Button("Restore Purchase") { Task { await purchase.restore() } }
                    Button("Continue Free") { dismiss() }
                }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Theme.holoCyan)

                HStack(spacing: 18) {
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    Link("Privacy Policy", destination: URL(string: "https://www.lukekevinmclaughlin.com/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption)
                .foregroundStyle(Theme.holoCyan)

                if let error = purchase.lastError {
                    Text(error).font(.caption).foregroundStyle(Theme.amber)
                }
            }
            .padding(30)
        }
        .preferredColorScheme(.dark)
        .task { await purchase.refresh() }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.holoCyan).frame(width: 24)
            Text(text).foregroundStyle(Theme.holoIce)
        }
    }
}
#endif

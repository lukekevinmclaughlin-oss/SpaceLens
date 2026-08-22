import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchase: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HolographicBackground()
            VStack(spacing: 22) {
                HoloReticle(size: 86)
                VStack(spacing: 7) {
                    Text("Start Your Free Trial")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.holoIce)
                        .multilineTextAlignment(.center)
                    Text("Nice scan! The analyzer, cleanup, and export are free forever. Storage Atlas Pro adds the advanced layer — 7 days free.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.holoCyan)
                }

                VStack(alignment: .leading, spacing: 12) {
                    feature("gauge.with.needle", "Menu-bar watcher with live free-space trends")
                    feature("clock.arrow.circlepath", "Unlimited scan history")
                    feature("doc.text.magnifyingglass", "Storage reports and file-type deep dives")
                    feature("rectangle.on.rectangle", "Visual before/after cleanup comparisons")
                    feature("lock.shield.fill", "Private scanning—your filenames never leave the device")
                }
                .padding(18)
                .frame(maxWidth: 520, alignment: .leading)
                .liquidGlass(cornerRadius: 20)

                Button { Task { await purchase.purchaseYearly() } } label: {
                    VStack(spacing: 2) {
                        Text("Start 1-Week Free Trial").font(.headline)
                        Text("then \(purchase.yearlyPrice)/year").font(.caption)
                    }
                        .frame(maxWidth: 420)
                        .padding(.vertical, 7)
                }
                .buttonStyle(GlassButtonStyle(tint: Theme.holoCyan, prominent: true))
                .controlSize(.large)

                Button("Monthly — \(purchase.monthlyPrice)/month after trial") {
                    Task { await purchase.purchaseMonthly() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.holoCyan)

                Text("Auto-renews at the selected price until cancelled in App Store settings. Your scans and data are never deleted if the subscription ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    Button("Restore Purchase") { Task { await purchase.restore() } }
                    Button("Not Now") { dismiss() }
                }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Theme.holoCyan)

                HStack(spacing: 18) {
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
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.holoCyan).frame(width: 24)
            Text(text).foregroundStyle(Theme.holoIce)
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var purchase: PurchaseManager
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Old & Unopened") {
                Stepper(value: $settings.oldFileDays, in: 30...1825, step: 30) {
                    LabeledContent("Older than", value: "\(settings.oldFileDays) days")
                }
                Stepper(value: $settings.oldFileMinMB, in: 1...500, step: 1) {
                    LabeledContent("Minimum size", value: "\(settings.oldFileMinMB) MB")
                }
            }
            Section("Duplicates") {
                Stepper(value: $settings.duplicateMinMB, in: 1...500, step: 1) {
                    LabeledContent("Minimum size", value: "\(settings.duplicateMinMB) MB")
                }
                Text("Larger minimums make duplicate scans much faster.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dev Junk") {
                Toggle("Scan for build caches & dependency folders", isOn: $settings.devJunkEnabled)
                Text("node_modules, DerivedData, .venv, target, Pods, and similar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu Bar Watcher") {
                if purchase.hasAccess {
                    Toggle("Show free space in the menu bar", isOn: $settings.menuBarEnabled)
                } else {
                    Button {
                        purchase.showPaywall = true
                    } label: {
                        Label("Menu-bar watcher is part of Storage Atlas Pro", systemImage: "lock")
                    }
                }
                Stepper(value: $settings.lowSpacePercent, in: 3...50, step: 1) {
                    LabeledContent("Warn below", value: "\(settings.lowSpacePercent)% free")
                }
                Text("A menu-bar item watches every disk and nudges you when one runs low.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if DIRECT_DISTRIBUTION
            Section("License") {
                Label("Direct edition — fully unlocked", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.holoCyan)
                Text("One-time website purchase. No subscription, in-app purchase, account, or restore step.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section("Subscription") {
                if purchase.hasAccess {
                    Label("Storage Atlas Pro is active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.holoCyan)
                } else {
                    Button("Try Premium") { purchase.showPaywall = true }
                }
                Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Button("Restore Purchases") { Task { await purchase.restore() } }
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }
}

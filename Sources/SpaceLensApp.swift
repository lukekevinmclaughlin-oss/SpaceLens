import SwiftUI

@main
struct SpaceLensApp: App {
    @StateObject private var model = ScanViewModel()
    @StateObject private var purchase = PurchaseManager.shared
    #if os(macOS)
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var monitor = DiskMonitor.shared
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(AppSettings.shared)
                .environmentObject(purchase)
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Scan…") { model.newScan() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.scannedURL == nil)
            }
            CommandMenu("Selection") {
                Button("Go Up") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)
                Divider()
                Button(model.inspected.map { model.isInBasket($0) } == true ? "Remove from Basket" : "Add to Basket") {
                    model.toggleSelectedInBasket()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model.inspected == nil)
                Button("Quick Look") { model.quickLookSelected() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(model.inspected == nil)
                Button("Reveal in Finder") { model.revealSelected() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.inspected == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Cleanup") { _ = model.undoLastTrash() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.lastTrash.isEmpty)
            }
        }
        #endif

        #if os(macOS)
        Settings { SettingsView() }

        // macOS 26 writes the `isInserted` binding back on every scene update.
        // @Published republishes on every set (it does not compare), so a plain
        // $settings.menuBarEnabled binding invalidates the scene each pass and
        // the app spins forever at launch (App Review's "froze on launch").
        // Deduplicate writes so the graph settles.
        // The menu-bar watcher is part of Storage Atlas Pro.
        MenuBarExtra(isInserted: Binding(
            get: { settings.menuBarEnabled && purchase.hasAccess },
            set: { newValue in
                if settings.menuBarEnabled != newValue { settings.menuBarEnabled = newValue }
            }
        )) {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(purchase)
        } label: {
            Image(systemName: monitor.isLow ? "externaldrive.badge.exclamationmark" : "internaldrive")
        }
        .menuBarExtraStyle(.window)

        #endif
    }
}

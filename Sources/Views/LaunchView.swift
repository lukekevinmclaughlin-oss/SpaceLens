import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LaunchView: View {
    @EnvironmentObject var model: ScanViewModel
    @EnvironmentObject var purchase: PurchaseManager
    @ObservedObject private var recents = RecentScans.shared
    @AppStorage("storageAtlas.didDismissProIntro") private var didDismissProIntro = false
    @State private var showImporter = false
    // Visible by default: the entrance is a bonus, never a gate. (A prior version
    // gated opacity on an onAppear-set flag, which the paywall's view-swap could
    // leave unfired — rendering the launch screen blank.)
    @State private var appear = true

    var body: some View {
        ZStack {
            HolographicBackground()

            switch model.state {
            case .scanning(let files, let bytes):
                ScanningHUD(files: files, bytes: bytes)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            default:
                launchContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isScanning)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.startScan(url: url)
            }
        }
    }

    private var isScanning: Bool { if case .scanning = model.state { return true }; return false }

    // MARK: Launch

    private var launchContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                HoloReticle(scanning: false, size: 132)
                    .shadow(color: Theme.holoCyan.opacity(0.4), radius: 24)
                    .scaleEffect(appear ? 1 : 0.6)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Storage Atlas")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cyanGradient)
                        .shadow(color: Theme.holoCyan.opacity(0.4), radius: 12)
                    Text("See what's eating your storage — then reclaim it.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .offset(y: appear ? 0 : 12)
                .opacity(appear ? 1 : 0)
            }

            VStack(spacing: 11) {
                #if os(macOS)
                ForEach(Array(QuickLocation.all.enumerated()), id: \.element.id) { i, loc in
                    Button { model.startScan(url: loc.url) } label: {
                        LocationRow(location: loc)
                    }
                    .buttonStyle(.plain)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1 + Double(i) * 0.06), value: appear)
                }
                #endif
                Button { chooseFolder() } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose a folder or volume…").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right").opacity(0.5)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(maxWidth: 430)
                    .foregroundStyle(.white)
                    .liquidGlass(cornerRadius: 14, tint: Theme.holoCyan)
                }
                .buttonStyle(.plain)
                .opacity(appear ? 1 : 0)
            }

            if !purchase.hasAccess && !didDismissProIntro {
                VStack(spacing: 8) {
                    Label("Premium adds Storage Time Machine, growth forecasts, reports, and the Mac menu-bar watcher.",
                          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 18) {
                        Button("Try Premium") { purchase.showPaywall = true }
                            .buttonStyle(.borderedProminent)
                        Button("Continue Free") { didDismissProIntro = true }
                            .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(maxWidth: 430)
                .liquidGlass(cornerRadius: 14, tint: Theme.holoCyan.opacity(0.25))
            }

            if !recents.recentLocations.isEmpty {
                recentsSection.opacity(appear ? 1 : 0)
            }

            if case .failed(let msg) = model.state {
                Text(msg).font(.callout).foregroundStyle(Theme.amber).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button("Clear") { recents.clear() }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            ForEach(recents.recentLocations) { entry in
                Button { openRecent(entry) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.holoCyan.opacity(0.8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).fontWeight(.medium).foregroundStyle(.white).lineLimit(1)
                            Text(entry.path).font(.caption2).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.bytes(entry.lastSize)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: 430)
                    .liquidGlass(cornerRadius: 12, strokeOpacity: 0.25)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 430)
    }

    private func openRecent(_ entry: RecentScans.Entry) {
        if let url = recents.resolve(entry) {
            model.startScan(url: url)
        } else {
            recents.remove(entry)
        }
    }

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or volume to analyse"
        if panel.runModal() == .OK, let url = panel.url { model.startScan(url: url) }
        #else
        showImporter = true
        #endif
    }
}

// MARK: - Scanning HUD

struct ScanningHUD: View {
    @EnvironmentObject var model: ScanViewModel
    let files: Int
    let bytes: Int64
    @State private var appear = false

    var body: some View {
        VStack(spacing: 30) {
            HoloReticle(scanning: true, size: 260)
                .shadow(color: Theme.holoCyan.opacity(0.5), radius: 34)

            VStack(spacing: 10) {
                Text("SCANNING")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Theme.holoCyan)

                HStack(spacing: 26) {
                    counter(value: Fmt.count(files), label: "FILES")
                    Rectangle().fill(Theme.holoCyan.opacity(0.25)).frame(width: 1, height: 34)
                    counter(value: Fmt.bytes(bytes), label: "MAPPED")
                }
                .padding(.horizontal, 26).padding(.vertical, 16)
                .liquidGlass(cornerRadius: 16)
            }

            Button("Cancel") { model.cancelScan() }
                .buttonStyle(GlassButtonStyle())
        }
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appear = true } }
    }

    private func counter(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label).font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Quick locations (macOS)

struct QuickLocation: Identifiable {
    // Identity must be STABLE across body evaluations. A `UUID()` here combined
    // with the computed `all` handed SwiftUI brand-new row identities on every
    // graph update; with the TimelineView background ticking each frame, the
    // launch screen rebuilt its ForEach forever -- 100% main-thread CPU and a
    // frozen app (App Review's "froze on launch" rejection).
    var id: String { url.path }
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL

    static let all: [QuickLocation] = {
        let fm = FileManager.default
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? {
            fm.urls(for: d, in: .userDomainMask).first
        }
        var out: [QuickLocation] = []
        #if os(macOS)
        let home = fm.homeDirectoryForCurrentUser
        out.append(.init(title: "Home Folder", subtitle: home.path, symbol: "house.fill", url: home))
        #endif
        if let d = dir(.downloadsDirectory) { out.append(.init(title: "Downloads", subtitle: d.lastPathComponent, symbol: "arrow.down.circle.fill", url: d)) }
        if let d = dir(.desktopDirectory) { out.append(.init(title: "Desktop", subtitle: d.lastPathComponent, symbol: "menubar.dock.rectangle", url: d)) }
        if let d = dir(.documentDirectory) { out.append(.init(title: "Documents", subtitle: d.lastPathComponent, symbol: "doc.fill", url: d)) }
        return out
    }()
}

struct LocationRow: View {
    let location: QuickLocation
    @State private var hover = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: location.symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(Theme.holoCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(location.title).fontWeight(.semibold).foregroundStyle(.white)
                Text(location.subtitle).font(.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").opacity(0.4).foregroundStyle(Theme.holoCyan)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: 430)
        .liquidGlass(cornerRadius: 14, strokeOpacity: hover ? 0.7 : 0.35)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.holoCyan.opacity(hover ? 0.5 : 0), lineWidth: 1)
        )
        .scaleEffect(hover ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        #if os(macOS)
        .onHover { hover = $0 }
        #endif
    }
}

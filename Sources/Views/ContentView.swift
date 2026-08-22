import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case largest = "Largest Files"
    case duplicates = "Duplicate Files"
    case old = "Old & Unopened"
    case devjunk = "Dev Junk"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .explore: return "circle.hexagongrid.fill"
        case .largest: return "arrow.up.right.circle.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .old: return "clock.badge.exclamationmark.fill"
        case .devjunk: return "hammer.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ScanViewModel
    @EnvironmentObject var purchase: PurchaseManager

    var body: some View {
        Group {
            // Free core: launch and analysis are never gated. The Pro paywall
            // appears contextually (as a dismissible sheet) after the first
            // completed scan.
            if model.root != nil {
                AnalysisView()
            } else {
                LaunchView()
            }
        }
        .onChange(of: model.root != nil) { _, hasRoot in
            if hasRoot { purchase.recordMeaningfulResult() }
        }
        .sheet(isPresented: $purchase.showPaywall) {
            PaywallView()
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["SPACELENS_SHOW_PAYWALL"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { purchase.showPaywall = true }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.holoCyan)
        .animation(.easeInOut(duration: 0.4), value: model.root != nil)
        #if DEBUG
        .task { model.seedDemoIfRequested() }
        #endif
    }
}

struct AnalysisView: View {
    @EnvironmentObject var model: ScanViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 244, ideal: 264)
                #endif
        } detail: {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                HUDGrid().opacity(0.5)

                VStack(spacing: 0) {
                    ContentHeader()
                    Group {
                        switch model.section {
                        case .explore:
                            if let current = model.current {
                                ExploreView(node: current)
                                    .id(current.id)
                                    .transition(.opacity)
                            }
                        default:
                            FinderListView(section: model.section)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: model.current?.id)
                    BasketBar()
                }
            }
        }
    }
}

/// Faint static HUD grid used behind the analysis surface.
struct HUDGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 44
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Theme.holoCyan.opacity(0.035)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ContentHeader: View {
    @EnvironmentObject var model: ScanViewModel

    var body: some View {
        HStack(spacing: 10) {
            if model.section == .explore {
                Button { model.goUp() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoUp)
                .opacity(model.canGoUp ? 1 : 0.3)
                .help("Go up one level (⌘↑)")
                BreadcrumbBar()
            } else {
                Label(model.section.rawValue, systemImage: model.section.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.holoIce)
            }
            Spacer()
            GlobalSearchButton()
            if model.section == .explore {
                Button { withAnimation(.easeInOut(duration: 0.3)) { model.colorByType.toggle() } } label: {
                    Image(systemName: model.colorByType ? "paintpalette.fill" : "paintpalette")
                        .foregroundStyle(model.colorByType ? Theme.holoCyan : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.colorByType ? "Colour by type: on" : "Colour by file type")
                ChartToggle(mode: $model.chartMode)
            }
            Button { model.rescan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Rescan (⌘R)")
            Button { model.newScan() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).help("New scan (⌘N)")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .liquidGlass(cornerRadius: 0)
        .overlay(Rectangle().fill(Theme.holoCyan.opacity(0.12)).frame(height: 1), alignment: .bottom)
    }
}

/// Glass segmented control for the sunburst / treemap toggle, with icons.
struct ChartToggle: View {
    @Binding var mode: ScanViewModel.ChartMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScanViewModel.ChartMode.allCases, id: \.self) { m in
                let selected = mode == m
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { mode = m }
                } label: {
                    Label(m.rawValue, systemImage: m == .sunburst ? "chart.pie.fill" : "square.grid.2x2.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.black : Color.primary)
                        .background {
                            if selected {
                                Capsule().fill(Theme.cyanGradient)
                                    .shadow(color: Theme.holoCyan.opacity(0.4), radius: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Global "find a file" search — walks the whole scanned tree by name and jumps
/// the chart to the chosen result.
struct GlobalSearchButton: View {
    @EnvironmentObject var model: ScanViewModel
    @State private var open = false
    @State private var query = ""
    @State private var results: [FileNode] = []

    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "magnifyingglass") }
            .buttonStyle(.plain)
            .help("Find a file (⌘F)")
            .keyboardShortcut("f", modifiers: .command)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a file across this scan…", text: $query)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    Divider()
                    if query.count >= 2 && results.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(20)
                    } else if !results.isEmpty {
                        List(results) { node in
                            Button {
                                model.showInChart(node); open = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: NodeIcon.symbol(for: node))
                                        .foregroundStyle(NodePalette.color(for: node)).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(node.name).lineLimit(1)
                                        Text(node.url.deletingLastPathComponent().path)
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(Fmt.bytes(node.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 300)
                    } else {
                        Text("Type at least 2 characters").foregroundStyle(.tertiary)
                            .font(.caption).frame(maxWidth: .infinity).padding(16)
                    }
                }
                .frame(width: 380)
                .onChange(of: query) { _, q in results = model.searchTree(q) }
            }
    }
}

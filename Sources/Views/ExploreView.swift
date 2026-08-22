import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var model: ScanViewModel
    let node: FileNode
    #if os(macOS)
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch model.chartMode {
                case .sunburst: SunburstView(node: node)
                case .treemap:  TreemapView(node: node)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Disk map of \(node.name)")
            .accessibilityValue(model.inspected.map { "\($0.name), \(Fmt.bytes($0.size))" } ?? "nothing selected")
            .accessibilityHint("Arrow keys move the selection, Return opens a folder, Escape goes up a level, Space previews, Delete adds to the cleanup basket.")

            InspectorPanel()
                .frame(width: 312)
                .padding(12)
        }
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: node.id) { focused = true }
        .onKeyPress(.leftArrow)  { model.selectSibling(offset: -1); return .handled }
        .onKeyPress(.rightArrow) { model.selectSibling(offset:  1); return .handled }
        .onKeyPress(.upArrow)    { model.selectSibling(offset: -1); return .handled }
        .onKeyPress(.downArrow)  { model.selectSibling(offset:  1); return .handled }
        .onKeyPress(.return)     { model.drillIntoSelected();       return .handled }
        .onKeyPress(.escape)     { model.goUp();                    return .handled }
        .onKeyPress(.space)      { model.quickLookSelected();       return .handled }
        .onKeyPress(.delete)     { model.toggleSelectedInBasket();  return .handled }
        #endif
    }
}

struct InspectorPanel: View {
    @EnvironmentObject var model: ScanViewModel
    @State private var breakdown: [CategoryTotal] = []
    @State private var breakdownID: UUID?

    private var focus: FileNode? { model.inspected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let node = focus {
                    header(node)
                    stats(node)
                    actions(node)
                    if node.isDirectory, let children = node.children, !children.isEmpty {
                        topChildren(node)
                        if breakdownID == node.id && !breakdown.isEmpty {
                            CategoryBreakdownView(totals: breakdown)
                        }
                    }
                }
            }
            .padding(16)
        }
        .liquidGlass(cornerRadius: 18)
        .task(id: focus?.id) { await computeBreakdown() }
    }

    private func computeBreakdown() async {
        guard let node = focus, node.isDirectory else { breakdown = []; breakdownID = nil; return }
        let id = node.id
        let result = await Task.detached { SmartFinders.categoryBreakdown(in: node) }.value
        if focus?.id == id { breakdown = result; breakdownID = id }
    }

    private func header(_ node: FileNode) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(NodePalette.color(for: node).opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: NodeIcon.symbol(for: node))
                    .font(.system(size: 22))
                    .foregroundStyle(NodePalette.color(for: node))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.headline).lineLimit(2)
                Text(node.isDirectory ? "Folder" : node.url.pathExtension.uppercased() + " file")
                    .font(.caption).foregroundStyle(Theme.holoCyan.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: node.id)
    }

    private func stats(_ node: FileNode) -> some View {
        VStack(spacing: 0) {
            statRow("Size", Fmt.bytes(node.size), emphasis: true)
            if node.allocatedSize > 0 && node.allocatedSize != node.size {
                statRow("On disk", Fmt.bytes(node.allocatedSize))
            }
            if node.isDirectory {
                statRow("Items", Fmt.count(node.fileCount))
            }
            statRow("Modified", Fmt.relativeDate(node.modificationDate))
            if let a = node.accessDate { statRow("Opened", Fmt.relativeDate(a)) }
        }
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private func statRow(_ label: String, _ value: String, emphasis: Bool = false) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(emphasis ? .bold : .medium))
                .foregroundStyle(emphasis ? Theme.holoCyan : .primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func actions(_ node: FileNode) -> some View {
        VStack(spacing: 8) {
            Button { model.toggleBasket(node) } label: {
                Label(model.isInBasket(node) ? "In Basket" : "Add to Basket",
                      systemImage: model.isInBasket(node) ? "checkmark.circle.fill" : "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(tint: model.isInBasket(node) ? .green : Theme.amber, prominent: true))

            #if os(macOS)
            HStack(spacing: 8) {
                Button { PlatformActions.revealInFinder(node) } label: {
                    Label("Reveal", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                Button { PlatformActions.quickLook(node) } label: {
                    Label("Look", systemImage: "eye").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(GlassButtonStyle())
            #endif
        }
    }

    private func topChildren(_ node: FileNode) -> some View {
        let children = Array(node.sortedChildren.prefix(6))
        let maxSize = children.first?.size ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("LARGEST INSIDE")
                .font(.caption2.weight(.bold)).tracking(1.5)
                .foregroundStyle(Theme.holoCyan.opacity(0.7))
            ForEach(children) { child in
                Button {
                    if child.isDirectory { model.drill(into: child) } else { model.selected = child }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: NodeIcon.symbol(for: child)).font(.caption2).frame(width: 14)
                                .foregroundStyle(NodePalette.color(for: child))
                            Text(child.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(Fmt.bytes(child.size)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // proportional size bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.06)).frame(height: 3)
                                Capsule().fill(NodePalette.color(for: child).gradient)
                                    .frame(width: geo.size.width * CGFloat(Double(child.size) / Double(max(1, maxSize))), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

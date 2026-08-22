import SwiftUI

// MARK: - Cursor tooltip

/// A compact glass tooltip that follows the cursor over the charts, showing the
/// hovered node's name, size and location — so you never have to look away.
struct HoverTooltip: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: NodeIcon.symbol(for: node))
                .foregroundStyle(NodePalette.color(for: node))
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text(node.isDirectory ? "\(Fmt.count(node.fileCount)) items" : node.url.pathExtension.uppercased())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(Fmt.bytes(node.size))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.holoCyan)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .liquidGlass(cornerRadius: 10)
        .frame(maxWidth: 300, alignment: .leading)
        .fixedSize()
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }
}

/// Positions a tooltip near a point, clamped inside the given container size so
/// it never spills off the edges.
struct TooltipPositioner<Content: View>: View {
    let point: CGPoint
    let container: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize()
            .background(GeometryReader { g in
                Color.clear.preference(key: TipSizeKey.self, value: g.size)
            })
            .modifier(PlaceTooltip(point: point, container: container))
    }
}

private struct TipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PlaceTooltip: ViewModifier {
    let point: CGPoint
    let container: CGSize
    @State private var tip: CGSize = .zero
    func body(content: Content) -> some View {
        let pad: CGFloat = 14
        var x = point.x + 16
        var y = point.y + 18
        if x + tip.width + pad > container.width { x = point.x - tip.width - 16 }
        if y + tip.height + pad > container.height { y = point.y - tip.height - 16 }
        x = max(pad, min(x, container.width - tip.width - pad))
        y = max(pad, min(y, container.height - tip.height - pad))
        return content
            .onPreferenceChange(TipSizeKey.self) { tip = $0 }
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Context menu items (shared by charts + finder rows)

@MainActor @ViewBuilder
func nodeContextItems(_ node: FileNode, model: ScanViewModel) -> some View {
    Button(model.isInBasket(node) ? "Remove from Basket" : "Add to Basket",
           systemImage: model.isInBasket(node) ? "trash.slash" : "trash") {
        model.toggleBasket(node)
    }
    if node.isDirectory && !(node.children?.isEmpty ?? true) {
        Button("Open in Chart", systemImage: "chart.pie") { model.drill(into: node) }
    } else {
        Button("Show in Chart", systemImage: "scope") { model.showInChart(node) }
    }
    Divider()
    #if os(macOS)
    Button("Reveal in Finder", systemImage: "magnifyingglass") { PlatformActions.revealInFinder(node) }
    Button("Quick Look", systemImage: "eye") { PlatformActions.quickLook(node) }
    Button("Open", systemImage: "arrow.up.forward.app") { PlatformActions.open(node) }
    #endif
}

// MARK: - Branded loading indicator

struct BrandedSpinner: View {
    var label: String
    var detail: String? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            HoloReticle(scanning: true, size: 96)
            Text(label).font(.headline).foregroundStyle(Theme.holoIce)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            if let onCancel {
                Button("Cancel", action: onCancel).buttonStyle(GlassButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Category breakdown

/// Space-by-file-type: a thin stacked bar plus a compact legend. Gives an
/// at-a-glance sense of what *kind* of stuff fills a folder.
struct CategoryBreakdownView: View {
    let totals: [CategoryTotal]
    private var sum: Int64 { max(1, totals.reduce(0) { $0 + $1.bytes }) }

    var body: some View {
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("BY TYPE").font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(Theme.holoCyan.opacity(0.7))

                GeometryReader { geo in
                    HStack(spacing: 1.5) {
                        ForEach(totals) { t in
                            t.category.color
                                .frame(width: max(2, geo.size.width * CGFloat(Double(t.bytes) / Double(sum))))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 9)

                VStack(spacing: 5) {
                    ForEach(totals.prefix(6)) { t in
                        HStack(spacing: 8) {
                            Circle().fill(t.category.color).frame(width: 8, height: 8)
                            Image(systemName: t.category.symbol).font(.caption2).foregroundStyle(.secondary).frame(width: 14)
                            Text(t.category.title).font(.caption)
                            Spacer()
                            Text(Fmt.bytes(t.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Disk capacity bar

/// Shows how full the scanned volume is, and how much of the used space the
/// current scan accounts for — the emotional core of a disk cleaner.
struct CapacityBar: View {
    let scannedSize: Int64
    let total: Int64
    let free: Int64
    @ObservedObject private var settings = AppSettings.shared

    private var used: Int64 { max(0, total - free) }
    private var isLow: Bool { freeRatio < Double(settings.lowSpacePercent) / 100 }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("DISK").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Fmt.bytes(free)) free")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isLow ? Theme.amber : Theme.holoCyan)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let usedW = w * CGFloat(Double(used) / Double(total))
                    let scanW = w * CGFloat(Double(min(scannedSize, used)) / Double(total))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(.white.opacity(0.22)).frame(width: usedW)          // used
                        Capsule().fill(Theme.cyanGradient).frame(width: scanW)            // this scan
                    }
                }
                .frame(height: 8)
                HStack(spacing: 6) {
                    Circle().fill(Theme.holoCyan).frame(width: 7, height: 7)
                    Text("This scan \(Fmt.bytes(scannedSize))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(usedRatio * 100))% full").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk \(Int(usedRatio * 100)) percent full, \(Fmt.bytes(free)) free\(isLow ? ", low space" : "")")
        }
    }

    private var freeRatio: Double { total > 0 ? Double(free) / Double(total) : 1 }
    private var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

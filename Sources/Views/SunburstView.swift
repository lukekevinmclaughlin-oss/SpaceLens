import SwiftUI

/// One drawn arc in the sunburst.
private struct Arc {
    let node: FileNode
    let depth: Int
    let start: Angle
    let end: Angle
    let innerR: CGFloat
    let outerR: CGFloat
    let color: Color
}

struct SunburstView: View {
    @EnvironmentObject var model: ScanViewModel
    let node: FileNode

    private let maxDepth = 4

    // Memoized arc geometry held in a reference cache so it recomputes only when
    // the node / size / colour-mode changes (keyed), never on hover — but is
    // always in sync with the current layout on every body pass.
    private final class ArcCache { var key = ""; var arcs: [Arc] = [] }
    @State private var cache = ArcCache()
    @State private var hoverPoint: CGPoint?
    @State private var reveal: CGFloat = 0     // 0→1 entrance fade/scale

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ringWidth = (size / 2 - 44) / CGFloat(maxDepth + 1)
            let holeR = ringWidth * 1.1
            let key = "\(node.id.uuidString)-\(Int(size))-\(model.colorByType)-\(model.finderEpoch)"
            let arcs = self.arcs(for: key, center: center, holeR: holeR, ringWidth: ringWidth)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.holoCyan.opacity(0.10), .clear],
                                         center: .center, startRadius: 0, endRadius: size/2))
                    .frame(width: size, height: size)
                    .position(center)

                Canvas { ctx, _ in draw(ctx, arcs: arcs, center: center) }

                centerHole(radius: holeR).position(center)

                if let hn = model.hovered, let hp = hoverPoint {
                    TooltipPositioner(point: hp, container: geo.size) { HoverTooltip(node: hn) }
                }
            }
            .scaleEffect(0.97 + 0.03 * reveal)
            .opacity(Double(reveal))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    if let hit = hitTest(value.location, arcs: arcs, center: center, holeR: holeR) {
                        model.activate(hit)
                    } else if hypot(value.location.x - center.x, value.location.y - center.y) < holeR {
                        model.goUp()
                    }
                }
            )
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt):
                    hoverPoint = pt
                    model.hovered = hitTest(pt, arcs: arcs, center: center, holeR: holeR)
                case .ended:
                    hoverPoint = nil; model.hovered = nil
                }
            }
            .contextMenu {
                if let n = model.hovered ?? model.selected { nodeContextItems(n, model: model) }
            }
            #endif
            .onChange(of: node.id, initial: true) {
                reveal = 0
                withAnimation(.easeOut(duration: 0.5)) { reveal = 1 }
            }
        }
        .padding(20)
    }

    /// Return cached arcs for `key`, rebuilding once if the key changed.
    private func arcs(for key: String, center: CGPoint, holeR: CGFloat, ringWidth: CGFloat) -> [Arc] {
        if cache.key != key {
            cache.key = key
            cache.arcs = buildArcs(center: center, holeR: holeR, ringWidth: ringWidth)
        }
        return cache.arcs
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, arcs: [Arc], center: CGPoint) {
        // When hovering, focus the hovered node's lineage (ancestors + itself +
        // descendants) and dim everything else.
        let hovered = model.hovered
        var lineage: Set<UUID> = []
        if let h = hovered {
            var n: FileNode? = h
            while let cur = n { lineage.insert(cur.id); n = cur.parent }   // ancestors + self
        }
        func related(_ node: FileNode) -> Bool {
            guard hovered != nil else { return true }
            if lineage.contains(node.id) { return true }
            var n: FileNode? = node                                        // is it a descendant of hovered?
            while let cur = n { if cur.id == hovered!.id { return true }; n = cur.parent }
            return false
        }

        if let hot = arcs.first(where: { hovered?.id == $0.node.id }) {
            var glow = ctx
            glow.addFilter(.blur(radius: 10))
            glow.fill(ringPath(center: center, arc: hot), with: .color(Theme.holoCyan.opacity(0.7)))
        }
        for arc in arcs {
            let path = ringPath(center: center, arc: arc)
            let isHot = hovered?.id == arc.node.id
            let isSel = model.selected?.id == arc.node.id
            let dim = hovered != nil && !related(arc.node)
            ctx.fill(path, with: .color(arc.color.opacity(dim ? 0.22 : (isHot ? 1 : 0.88))))
            ctx.stroke(path, with: .color(.black.opacity(0.22)), lineWidth: 1)
            if isSel { ctx.stroke(path, with: .color(Theme.amber), lineWidth: 2.5) }
            if isHot { ctx.stroke(path, with: .color(Theme.holoIce), lineWidth: 2) }

            // Label large, shallow arcs so wedges are legible without hovering.
            let span = arc.end.radians - arc.start.radians
            if arc.depth <= 2 && span > 0.34 {
                let mid = (arc.start.radians + arc.end.radians) / 2
                let r = (arc.innerR + arc.outerR) / 2
                let p = CGPoint(x: center.x + cos(mid) * r, y: center.y + sin(mid) * r)
                let name = arc.node.name.count > 14 ? String(arc.node.name.prefix(13)) + "…" : arc.node.name
                ctx.draw(Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white),
                         at: p, anchor: .center)
            }
        }
    }

    // MARK: Center

    private func centerHole(radius: CGFloat) -> some View {
        let display = model.hovered ?? model.inspected ?? node
        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Theme.holoCyan.opacity(0.4), lineWidth: 1.5))
                .overlay(Circle().fill(RadialGradient(colors: [Theme.holoCyan.opacity(0.18), .clear],
                                                      center: .center, startRadius: 0, endRadius: radius)))
                .shadow(color: Theme.holoCyan.opacity(0.3), radius: 16)
            VStack(spacing: 3) {
                Image(systemName: NodeIcon.symbol(for: display)).font(.title3).foregroundStyle(Theme.holoCyan)
                Text(display.name).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: radius * 1.6)
                Text(Fmt.bytes(display.size))
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.cyanGradient)
                    .contentTransition(.numericText())
                if model.canGoUp {
                    Label("up", systemImage: "arrow.up").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .frame(width: radius * 1.9, height: radius * 1.9)
        .animation(.easeOut(duration: 0.2), value: display.id)
    }

    // MARK: Geometry

    private func buildArcs(center: CGPoint, holeR: CGFloat, ringWidth: CGFloat) -> [Arc] {
        guard holeR > 0, ringWidth > 0 else { return [] }
        var arcs: [Arc] = []
        func recurse(_ n: FileNode, depth: Int, start: Double, end: Double) {
            guard depth <= maxDepth else { return }
            let children = n.sortedChildren.filter { $0.size > 0 }
            let total = children.reduce(Int64(0)) { $0 + $1.size }
            guard total > 0 else { return }
            var a = start
            let span = end - start
            let innerR = holeR + ringWidth * CGFloat(depth - 1)
            let outerR = innerR + ringWidth * 0.94
            for (i, child) in children.enumerated() {
                let frac = Double(child.size) / Double(total)
                let childEnd = a + span * frac
                if (childEnd - a) > 0.007 {
                    let color = model.colorByType
                        ? FileCategory.of(node: child).color.opacity(1.0 - Double(depth - 1) * 0.12)
                        : NodePalette.ringColor(depth: depth, index: i, total: children.count)
                    arcs.append(Arc(node: child, depth: depth,
                                    start: .radians(a), end: .radians(childEnd),
                                    innerR: innerR, outerR: outerR,
                                    color: color))
                    recurse(child, depth: depth + 1, start: a, end: childEnd)
                }
                a = childEnd
            }
        }
        recurse(node, depth: 1, start: -Double.pi / 2, end: -Double.pi / 2 + 2 * .pi)
        return arcs
    }

    private func ringPath(center: CGPoint, arc: Arc) -> Path {
        var p = Path()
        p.addArc(center: center, radius: arc.outerR, startAngle: arc.start, endAngle: arc.end, clockwise: false)
        p.addArc(center: center, radius: arc.innerR, startAngle: arc.end, endAngle: arc.start, clockwise: true)
        p.closeSubpath()
        return p
    }

    private func hitTest(_ pt: CGPoint, arcs: [Arc], center: CGPoint, holeR: CGFloat) -> FileNode? {
        let dx = pt.x - center.x, dy = pt.y - center.y
        let r = hypot(dx, dy)
        if r < holeR { return nil }
        var theta = atan2(dy, dx)
        while theta < -Double.pi / 2 { theta += 2 * .pi }
        while theta > -Double.pi / 2 + 2 * .pi { theta -= 2 * .pi }
        for arc in arcs {
            if r >= arc.innerR && r <= arc.outerR &&
                theta >= arc.start.radians && theta <= arc.end.radians {
                return arc.node
            }
        }
        return nil
    }
}

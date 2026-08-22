import SwiftUI

struct TreemapView: View {
    @EnvironmentObject var model: ScanViewModel
    let node: FileNode

    private final class TileCache { var key = ""; var tiles: [Tile] = [] }
    @State private var cache = TileCache()
    @State private var hoverPoint: CGPoint?
    @State private var reveal: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let key = "\(node.id.uuidString)-\(Int(geo.size.width))x\(Int(geo.size.height))-\(model.colorByType)-\(model.finderEpoch)"
            let tiles = self.tiles(for: key, size: geo.size)
            ZStack {
                Canvas { ctx, _ in draw(ctx, tiles: tiles) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            if let hit = tiles.first(where: { $0.rect.contains(value.location) }) {
                                model.activate(hit.node)
                            }
                        }
                    )
                    #if os(macOS)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt):
                            hoverPoint = pt
                            model.hovered = tiles.first(where: { $0.rect.contains(pt) })?.node
                        case .ended: hoverPoint = nil; model.hovered = nil
                        }
                    }
                    .contextMenu {
                        if let n = model.hovered ?? model.selected { nodeContextItems(n, model: model) }
                    }
                    #endif

                if let hn = model.hovered, let hp = hoverPoint {
                    TooltipPositioner(point: hp, container: geo.size) { HoverTooltip(node: hn) }
                }
            }
            .scaleEffect(0.98 + 0.02 * reveal)
            .opacity(Double(reveal))
            .onChange(of: node.id, initial: true) {
                reveal = 0
                withAnimation(.easeOut(duration: 0.45)) { reveal = 1 }
            }
        }
        .padding(12)
    }

    private func tiles(for key: String, size: CGSize) -> [Tile] {
        if cache.key != key {
            cache.key = key
            cache.tiles = Squarify.layout(children: node.sortedChildren.filter { $0.size > 0 },
                                          in: CGRect(origin: .zero, size: size))
        }
        return cache.tiles
    }

    private func draw(_ ctx: GraphicsContext, tiles: [Tile]) {
        if let hot = tiles.first(where: { model.hovered?.id == $0.node.id }) {
            var glow = ctx
            glow.addFilter(.blur(radius: 10))
            glow.fill(Path(roundedRect: hot.rect.insetBy(dx: 1, dy: 1), cornerRadius: 5),
                      with: .color(Theme.holoCyan.opacity(0.7)))
        }
        for tile in tiles {
            let r = tile.rect.insetBy(dx: 1, dy: 1)
            guard r.width > 0, r.height > 0 else { continue }
            let path = Path(roundedRect: r, cornerRadius: 5)
            let isHot = model.hovered?.id == tile.node.id
            let isSel = model.selected?.id == tile.node.id
            ctx.fill(path, with: .color(NodePalette.color(for: tile.node, byType: model.colorByType).opacity(isHot ? 1 : 0.86)))
            ctx.stroke(path, with: .color(.black.opacity(0.2)), lineWidth: 1)
            if isSel { ctx.stroke(path, with: .color(Theme.amber), lineWidth: 2.5) }
            if isHot { ctx.stroke(path, with: .color(Theme.holoIce), lineWidth: 2) }

            if r.width > 74 && r.height > 34 {
                let name = Text(tile.node.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                let sz = Text(Fmt.bytes(tile.node.size)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                ctx.draw(name, at: CGPoint(x: r.minX + 8, y: r.minY + 14), anchor: .leading)
                ctx.draw(sz, at: CGPoint(x: r.minX + 8, y: r.minY + 28), anchor: .leading)
            }
        }
    }
}

struct Tile {
    let node: FileNode
    let rect: CGRect
}

/// Squarified treemap layout — keeps tiles close to square so labels stay legible.
enum Squarify {
    static func layout(children: [FileNode], in rect: CGRect) -> [Tile] {
        let nodes = children.filter { $0.size > 0 }
        let totalSize = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > 0 else { return [] }

        let totalArea = Double(rect.width * rect.height)
        // Map each node to an area proportional to its byte size.
        var items = nodes.map { (node: $0, area: Double($0.size) / Double(totalSize) * totalArea) }

        var tiles: [Tile] = []
        var free = rect
        var row: [(node: FileNode, area: Double)] = []

        func shortestSide(_ r: CGRect) -> Double { Double(min(r.width, r.height)) }

        func worst(_ row: [(node: FileNode, area: Double)], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return .greatestFiniteMagnitude }
            let areas = row.map { $0.area }
            let sum = areas.reduce(0, +)
            let maxA = areas.max() ?? 0
            let minA = areas.min() ?? 0
            let s2 = sum * sum
            let side2 = side * side
            return max(side2 * maxA / s2, s2 / (side2 * minA))
        }

        func layoutRow(_ row: [(node: FileNode, area: Double)], into r: inout CGRect) {
            let sum = row.reduce(0.0) { $0 + $1.area }
            let horizontal = r.width >= r.height
            if horizontal {
                let rowW = CGFloat(sum) / r.height
                var y = r.minY
                for item in row {
                    let h = CGFloat(item.area) / rowW
                    tiles.append(Tile(node: item.node, rect: CGRect(x: r.minX, y: y, width: rowW, height: h)))
                    y += h
                }
                r = CGRect(x: r.minX + rowW, y: r.minY, width: r.width - rowW, height: r.height)
            } else {
                let rowH = CGFloat(sum) / r.width
                var x = r.minX
                for item in row {
                    let w = CGFloat(item.area) / rowH
                    tiles.append(Tile(node: item.node, rect: CGRect(x: x, y: r.minY, width: w, height: rowH)))
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + rowH, width: r.width, height: r.height - rowH)
            }
        }

        while !items.isEmpty {
            let item = items[0]
            let side = shortestSide(free)
            let withItem = row + [item]
            if row.isEmpty || worst(withItem, side: side) <= worst(row, side: side) {
                row = withItem
                items.removeFirst()
            } else {
                layoutRow(row, into: &free)
                row = []
            }
        }
        if !row.isEmpty { layoutRow(row, into: &free) }
        return tiles
    }
}

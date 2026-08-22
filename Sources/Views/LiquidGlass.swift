import SwiftUI

// MARK: - Liquid Glass surface

/// A Liquid Glass panel. On macOS 26 / iOS 26 it uses the real system
/// `.glassEffect`; on earlier OSes it falls back to a hand-built glass look
/// (blur material + specular top-edge highlight + inner hairline + soft shadow)
/// so the aesthetic is consistent everywhere.
struct LiquidGlass: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color? = nil
    var strokeOpacity: Double = 0.5

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                content.glassEffect(tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular,
                                    in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .background(shape.fill((tint ?? Theme.holoCyan).opacity(tint == nil ? 0.04 : 0.10)))
                    .overlay(
                        shape.strokeBorder(
                            LinearGradient(colors: [.white.opacity(strokeOpacity),
                                                    .white.opacity(0.04),
                                                    Theme.holoCyan.opacity(0.12)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            }
        }
        // Make the whole rounded frame hit-testable so glass buttons with Spacer()
        // gaps forward taps from anywhere in the row, not just on the text/icon.
        .contentShape(shape)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 18, tint: Color? = nil, strokeOpacity: Double = 0.5) -> some View {
        modifier(LiquidGlass(cornerRadius: cornerRadius, tint: tint, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Glass button

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Theme.holoCyan
    var prominent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .background {
                if prominent {
                    Capsule().fill(tint.gradient)
                        .shadow(color: tint.opacity(0.5), radius: configuration.isPressed ? 4 : 12)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Holographic animated background

/// Deep-navy field with slowly drifting cyan light blooms and a faint HUD grid —
/// the ambient backdrop for the launch / scan screens.
struct HolographicBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.bgGradient.ignoresSafeArea()

                Canvas { ctx, size in
                    // faint grid
                    let step: CGFloat = 46
                    var grid = Path()
                    var x: CGFloat = 0
                    while x < size.width { grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height)); x += step }
                    var y: CGFloat = 0
                    while y < size.height { grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)); y += step }
                    ctx.stroke(grid, with: .color(Theme.holoCyan.opacity(0.04)), lineWidth: 1)

                    // drifting blooms
                    let blooms: [(Double, Double, Double, Color)] = [
                        (0.11, 0.9, 260, Theme.holoCyan),
                        (0.19, 0.7, 200, Theme.holoCyanDim),
                        (0.07, 1.3, 150, Theme.amber),
                    ]
                    for (i, b) in blooms.enumerated() {
                        let px = size.width * (0.3 + 0.4 * sin(t * b.0 + Double(i)))
                        let py = size.height * (0.35 + 0.35 * cos(t * b.1 + Double(i) * 1.7))
                        let rect = CGRect(x: px - b.2, y: py - b.2, width: b.2*2, height: b.2*2)
                        ctx.fill(Circle().path(in: rect),
                                 with: .radialGradient(Gradient(colors: [b.3.opacity(0.22), b.3.opacity(0)]),
                                                       center: .init(x: px, y: py), startRadius: 0, endRadius: b.2))
                    }
                }
                .ignoresSafeArea()
                .blur(radius: 0.5)
            }
        }
    }
}

// MARK: - Holographic reticle (the animated arc-reactor mark)

/// The app's signature animated mark: rotating HUD reticles around a pulsing
/// arc-reactor core, with optional orbiting data nodes. Used on the launch hero
/// and, spun up, as the scanning indicator.
struct HoloReticle: View {
    var scanning: Bool = false
    var size: CGFloat = 150

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = scanning ? 1.0 : 0.28
            Canvas { ctx, canvas in
                let c = CGPoint(x: canvas.width/2, y: canvas.height/2)
                let R = min(canvas.width, canvas.height) / 2

                // outer segmented ring (rotates)
                drawSegmentedRing(ctx, center: c, radius: R*0.94, width: R*0.10,
                                  segments: 28, rotation: t*speed*0.5, litFraction: scanning ? headFraction(t) : 0.55)
                // mid ticks (counter-rotates)
                drawTicks(ctx, center: c, radius: R*0.72, rotation: -t*speed*0.35)
                // inner reticle ring
                let ring = Circle().path(in: CGRect(x: c.x-R*0.5, y: c.y-R*0.5, width: R, height: R))
                ctx.stroke(ring, with: .color(Theme.holoCyan.opacity(0.5)), lineWidth: 2)

                // radar sweep when scanning
                if scanning {
                    let head = t*1.6
                    let span = 0.9
                    var wedge = Path()
                    wedge.move(to: c)
                    wedge.addArc(center: c, radius: R*0.9, startAngle: .radians(head-span), endAngle: .radians(head), clockwise: false)
                    wedge.closeSubpath()
                    ctx.fill(wedge, with: .radialGradient(
                        Gradient(colors: [Theme.holoCyan.opacity(0), Theme.holoCyan.opacity(0.28)]),
                        center: c, startRadius: 0, endRadius: R*0.9))
                }

                // orbiting data nodes
                let nodeCount = 7
                for i in 0..<nodeCount {
                    let a = Double(i)/Double(nodeCount) * .pi*2 + t*speed*(scanning ? 0.9 : 0.4)
                    let rr = R*0.62 * (0.8 + 0.2*sin(t*1.3 + Double(i)))
                    let p = CGPoint(x: c.x + cos(a)*rr, y: c.y + sin(a)*rr)
                    let amber = (i % 4 == 0)
                    let col = amber ? Theme.amber : Theme.holoIce
                    ctx.fill(Circle().path(in: CGRect(x: p.x-9, y: p.y-9, width: 18, height: 18)),
                             with: .radialGradient(Gradient(colors: [col.opacity(0.7), col.opacity(0)]),
                                                   center: p, startRadius: 0, endRadius: 9))
                    ctx.fill(Circle().path(in: CGRect(x: p.x-2.6, y: p.y-2.6, width: 5.2, height: 5.2)),
                             with: .color(col))
                }

                // triangle reticle + core
                let triR = R*0.20
                var tri = Path()
                for k in 0..<3 {
                    let a = -Double.pi/2 + Double(k)*2*Double.pi/3
                    let pt = CGPoint(x: c.x+cos(a)*triR, y: c.y+sin(a)*triR)
                    if k == 0 { tri.move(to: pt) } else { tri.addLine(to: pt) }
                }
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(Theme.holoIce.opacity(0.9)), lineWidth: 2.5)

                let pulse = scanning ? (0.85 + 0.15*sin(t*6)) : (0.9 + 0.1*sin(t*2))
                let coreR = R*0.14 * pulse
                ctx.fill(Circle().path(in: CGRect(x: c.x-R*0.34, y: c.y-R*0.34, width: R*0.68, height: R*0.68)),
                         with: .radialGradient(Gradient(colors: [Theme.holoCyan.opacity(0.45), Theme.holoCyan.opacity(0)]),
                                               center: c, startRadius: 0, endRadius: R*0.34))
                ctx.fill(Circle().path(in: CGRect(x: c.x-coreR, y: c.y-coreR, width: coreR*2, height: coreR*2)),
                         with: .radialGradient(Gradient(colors: [.white, Theme.holoIce, Theme.holoCyan]),
                                               center: c, startRadius: 0, endRadius: coreR))
            }
        }
        .frame(width: size, height: size)
    }

    private func headFraction(_ t: Double) -> Double { 0.4 + 0.35*(0.5+0.5*sin(t*0.8)) }

    private func drawSegmentedRing(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                                   width: CGFloat, segments: Int, rotation: Double, litFraction: Double) {
        let gap = 0.06
        for i in 0..<segments {
            let a0 = Double(i)/Double(segments) * .pi*2 + rotation
            let a1 = a0 + (2*Double.pi/Double(segments)) * (1-gap)
            var p = Path()
            p.addArc(center: center, radius: radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            p.addArc(center: center, radius: radius-width, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
            p.closeSubpath()
            let lit = Double(i)/Double(segments) < litFraction
            ctx.fill(p, with: .color(lit ? Theme.holoCyan.opacity(0.9) : Theme.holoCyanDim.opacity(0.22)))
        }
    }

    private func drawTicks(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, rotation: Double) {
        let n = 48
        for i in 0..<n {
            let a = Double(i)/Double(n) * .pi*2 + rotation
            let major = i % 4 == 0
            let r1 = radius, r0 = radius - (major ? 14 : 7)
            var p = Path()
            p.move(to: CGPoint(x: center.x+cos(a)*r0, y: center.y+sin(a)*r0))
            p.addLine(to: CGPoint(x: center.x+cos(a)*r1, y: center.y+sin(a)*r1))
            ctx.stroke(p, with: .color(Theme.holoCyan.opacity(major ? 0.7 : 0.3)), lineWidth: major ? 2 : 1)
        }
    }
}

import SwiftUI
#if os(macOS)
import AppKit

/// The menu-bar "storage watcher" popover: live free-space for every mounted
/// volume, a low-space nudge, and quick actions into the app.
struct MenuBarView: View {
    @ObservedObject var monitor = DiskMonitor.shared
    @ObservedObject var settings = AppSettings.shared
    @EnvironmentObject var model: ScanViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(monitor.volumes) { vol in
                        VolumeRow(vol: vol, isLow: vol.freeFraction < Double(settings.lowSpacePercent) / 100)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 260)
            Divider()
            actions
        }
        .frame(width: 320)
        .onAppear { monitor.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(Theme.holoCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("Storage Atlas").font(.headline)
                if let p = monitor.primary {
                    Text("\(Fmt.bytes(p.free)) free of \(Fmt.bytes(p.total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if monitor.isLow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
                    .help("Low disk space")
            }
        }
        .padding(14)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if monitor.isLow {
                Text("Running low on space — reclaim some now.")
                    .font(.caption).foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 10)
            }
            HStack(spacing: 8) {
                Button {
                    model.startScan(url: FileManager.default.homeDirectoryForCurrentUser)
                    bringToFront()
                } label: {
                    Label("Scan Home", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { bringToFront() } label: {
                    Label("Open", systemImage: "macwindow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)

            Divider()
            HStack {
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                }
                .buttonStyle(.plain).font(.caption)
                Spacer()
                Button("Quit Storage Atlas") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        let content = NSApp.windows.filter { $0.contentView != nil && $0.canBecomeKey && $0.styleMask.contains(.titled) }
        if let w = content.first {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

private struct VolumeRow: View {
    let vol: DiskMonitor.VolumeInfo
    let isLow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: vol.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .foregroundStyle(isLow ? Theme.amber : Theme.holoCyan)
                Text(vol.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                Text("\(Fmt.bytes(vol.free)) free")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isLow ? Theme.amber : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(isLow ? AnyShapeStyle(Theme.amber.gradient) : AnyShapeStyle(Theme.cyanGradient))
                        .frame(width: geo.size.width * CGFloat(vol.usedFraction))
                }
            }
            .frame(height: 7)
            Text("\(Int(vol.usedFraction * 100))% used · \(Fmt.bytes(vol.used)) of \(Fmt.bytes(vol.total))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
#endif

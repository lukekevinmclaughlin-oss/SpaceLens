import SwiftUI

/// A subscription-backed feature that turns local scan snapshots into a useful
/// storage story. All calculations stay on-device and work on both platforms.
struct StorageTimeMachineView: View {
    @EnvironmentObject private var model: ScanViewModel
    @EnvironmentObject private var purchase: PurchaseManager
    @ObservedObject private var recents = RecentScans.shared

    private var path: String? { model.scannedURL?.path }
    private var snapshots: [RecentScans.Entry] {
        guard let path else { return [] }
        return recents.entries.filter { $0.path == path }.sorted { $0.lastScanned < $1.lastScanned }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("STORAGE TIME MACHINE", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Theme.holoCyan)
                        Text("See how this location changes over time")
                            .font(.title2.bold()).foregroundStyle(Theme.holoIce)
                        Text("Each completed scan becomes a private snapshot. Compare growth, model cleanup, and export a reviewer-friendly report.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: report) {
                        Label("Export Report", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!purchase.hasAccess || snapshots.isEmpty)
                }

                if !purchase.hasAccess {
                    lockedCard
                } else if snapshots.isEmpty {
                    ContentUnavailableView("No snapshots yet", systemImage: "clock.badge.questionmark",
                                           description: Text("Complete a scan to create the first snapshot."))
                        .frame(minHeight: 280)
                } else {
                    insightGrid
                    historyCard
                }
            }
            .padding(22)
        }
        .background(Theme.bgGradient)
    }

    private var lockedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.system(size: 42)).foregroundStyle(Theme.holoCyan)
            Text("Premium insight, free core").font(.title3.bold()).foregroundStyle(Theme.holoIce)
            Text("Scanning, visual analysis, smart finders, and cleanup remain free. Try Premium to unlock historical comparisons and reports.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("Try Premium") { purchase.showPaywall = true }.buttonStyle(.borderedProminent)
                Button("Continue Free") { model.section = .explore }.buttonStyle(.plain)
            }
        }
        .padding(30).frame(maxWidth: .infinity, minHeight: 300).liquidGlass(cornerRadius: 22)
    }

    private var insightGrid: some View {
        let latest = snapshots.last!
        let previous = snapshots.dropLast().last
        let delta = previous.map { latest.lastSize - $0.lastSize }
        let elapsedDays = previous.map { max(1.0 / 24.0, (latest.lastScanned - $0.lastScanned) / 86_400) }
        let daily: Int64? = {
            guard let delta, let elapsedDays else { return nil }
            return Int64(Double(delta) / elapsedDays)
        }()

        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                metric("Current scan", Fmt.bytes(latest.lastSize), "externaldrive.fill")
                metric("Since prior scan", delta.map(signedBytes) ?? "First snapshot", delta.map { $0 > 0 ? "arrow.up.right" : "arrow.down.right" } ?? "sparkles")
                metric("Daily pace", daily.map { "\(signedBytes($0))/day" } ?? "Learning", "chart.xyaxis.line")
            }
            HStack(spacing: 14) {
                metric("Cleanup basket", Fmt.bytes(model.basketTotal), "trash.fill")
                metric("Free after cleanup", Fmt.bytes(model.projectedFree), "internaldrive")
                metric("Snapshots", "\(snapshots.count)", "clock.arrow.circlepath")
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.holoCyan)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(Theme.holoIce).lineLimit(1)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).liquidGlass(cornerRadius: 16)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Snapshot ledger").font(.headline).foregroundStyle(Theme.holoIce)
            SnapshotSparkline(values: snapshots.map(\.lastSize))
                .frame(height: 130)
            ForEach(Array(snapshots.suffix(8).reversed())) { item in
                HStack {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(Theme.holoCyan)
                    Text(Date(timeIntervalSinceReferenceDate: item.lastScanned), format: .dateTime.month().day().hour().minute())
                    Spacer()
                    Text(Fmt.bytes(item.lastSize)).monospacedDigit().foregroundStyle(Theme.holoIce)
                    if let free = item.volumeFree {
                        Text("• \(Fmt.bytes(free)) free").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .padding(18).liquidGlass(cornerRadius: 18)
    }

    private func signedBytes(_ value: Int64) -> String {
        value == 0 ? "No change" : "\(value > 0 ? "+" : "−")\(Fmt.bytes(abs(value)))"
    }

    private var report: String {
        var lines = [
            "Storage Atlas — Storage Time Machine Report",
            "Location: \(path ?? "No location")",
            "Generated: \(Date().formatted(date: .long, time: .shortened))",
            "Snapshots: \(snapshots.count)",
            "Cleanup basket: \(Fmt.bytes(model.basketTotal))",
            "Projected free space: \(Fmt.bytes(model.projectedFree))",
            "",
            "Snapshot history"
        ]
        lines += snapshots.reversed().map {
            "\(Date(timeIntervalSinceReferenceDate: $0.lastScanned).formatted(date: .numeric, time: .shortened)) — \(Fmt.bytes($0.lastSize))"
        }
        lines += ["", "All analysis was performed locally on this device."]
        return lines.joined(separator: "\n")
    }
}

private struct SnapshotSparkline: View {
    let values: [Int64]

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? minValue
            let range = max(1, maxValue - minValue)
            let denominator = max(1, values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(denominator)
                let y = size.height - size.height * CGFloat(value - minValue) / CGFloat(range)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(Theme.holoCyan), lineWidth: 3)
        }
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.18))
        }
        .accessibilityLabel("Storage history chart with \(values.count) snapshots")
    }
}

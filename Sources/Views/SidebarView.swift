import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: ScanViewModel
    @EnvironmentObject var purchase: PurchaseManager

    var body: some View {
        List {
            Section {
                if let root = model.root {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.hexagongrid.fill")
                                .foregroundStyle(Theme.holoCyan)
                            Text(root.name).font(.headline).lineLimit(1)
                        }
                        Text(Fmt.bytes(root.size))
                            .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.cyanGradient)
                        HStack(spacing: 10) {
                            Label(Fmt.count(root.fileCount), systemImage: "doc")
                            if case .complete(let dur) = model.state {
                                Label("\(String(format: "%.1f", dur))s", systemImage: "bolt.fill")
                                    .foregroundStyle(Theme.amber.opacity(0.9))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        CapacityBar(scannedSize: root.allocatedSize > 0 ? root.allocatedSize : root.size,
                                    total: model.volumeTotal, free: model.volumeFree)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Views") {
                ForEach(SidebarSection.allCases) { s in
                    Button {
                        if s == .timeMachine && !purchase.hasAccess {
                            purchase.showPaywall = true
                        } else {
                            model.section = s
                        }
                    } label: {
                        HStack {
                            Label(s.rawValue, systemImage: s.symbol)
                            Spacer()
                            if s == .timeMachine && !purchase.hasAccess {
                                Image(systemName: "lock.fill").font(.caption2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.section == s ? Theme.holoCyan.opacity(0.16) : Color.clear)
                            .overlay(alignment: .leading) {
                                if model.section == s {
                                    Capsule().fill(Theme.holoCyan).frame(width: 3).padding(.vertical, 4)
                                }
                            }
                            .padding(.horizontal, 6)
                    )
                    .foregroundStyle(model.section == s ? Theme.holoCyan : Color.primary)
                }
            }

            if !model.basket.isEmpty {
                Section("Cleanup Basket") {
                    HStack {
                        Image(systemName: "trash.fill").foregroundStyle(Theme.amber)
                        VStack(alignment: .leading) {
                            Text("\(model.basket.count) items")
                                .font(.subheadline.weight(.medium))
                            Text("frees \(Fmt.bytes(model.basketTotal))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

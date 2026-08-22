import SwiftUI

enum FinderSort: String, CaseIterable, Identifiable {
    case size = "Size", name = "Name", date = "Date"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .size: return "arrow.down.right.circle"; case .name: return "textformat"; case .date: return "calendar" }
    }
}

struct FinderListView: View {
    @EnvironmentObject var model: ScanViewModel
    @EnvironmentObject var settings: AppSettings
    let section: SidebarSection

    @State private var files: [FileNode] = []
    @State private var duplicateGroups: [SmartFinders.DuplicateGroup] = []
    @State private var junk: [SmartFinders.JunkHit] = []
    @State private var loading = false
    @State private var progressName = ""
    @State private var query = ""
    @State private var sort: FinderSort = .size
    @State private var dupCancel = ManagedAtomicFlag()

    private var taskKey: String {
        "\(section.rawValue)-\(model.finderEpoch)-\(settings.oldFileDays)-\(settings.oldFileMinMB)-\(settings.duplicateMinMB)-\(settings.devJunkEnabled)"
    }

    var body: some View {
        Group {
            if loading {
                BrandedSpinner(label: section == .duplicates ? "Hashing candidates…" : "Analysing…",
                               detail: progressName,
                               onCancel: section == .duplicates ? { dupCancel.set() } : nil)
            } else if section == .duplicates {
                duplicateList
            } else if section == .devjunk {
                junkList
            } else {
                flatList
            }
        }
        .task(id: taskKey) { await compute() }
    }

    // MARK: Filtering + sorting

    private func sorted(_ items: [FileNode]) -> [FileNode] {
        switch sort {
        case .size: return items.sorted { $0.size > $1.size }
        case .name: return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date: return items.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        }
    }

    private var filteredFiles: [FileNode] {
        let base = query.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return sorted(base)
    }
    private var filteredJunk: [SmartFinders.JunkHit] {
        let base = query.isEmpty ? junk : junk.filter { $0.node.name.localizedCaseInsensitiveContains(query) || $0.rule.localizedCaseInsensitiveContains(query) }
        switch sort {
        case .size: return base.sorted { $0.node.size > $1.node.size }
        case .name: return base.sorted { $0.node.name.localizedCaseInsensitiveCompare($1.node.name) == .orderedAscending }
        case .date: return base.sorted { ($0.node.modificationDate ?? .distantPast) > ($1.node.modificationDate ?? .distantPast) }
        }
    }
    private var filteredGroups: [SmartFinders.DuplicateGroup] {
        query.isEmpty ? duplicateGroups : duplicateGroups.filter { g in g.files.contains { $0.name.localizedCaseInsensitiveContains(query) } }
    }

    // MARK: Flat list (largest / old)

    private var flatList: some View {
        let items = filteredFiles
        return VStack(spacing: 0) {
            resultsHeader(count: items.count,
                          total: items.reduce(Int64(0)) { $0 + $1.size },
                          addAll: { items.forEach(model.addToBasket) })
            if files.isEmpty {
                emptyState("Nothing found here — your storage looks tidy.")
            } else {
                List(items) { node in FinderRow(node: node) }
                    .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Dev junk

    private var junkList: some View {
        let items = filteredJunk
        return VStack(spacing: 0) {
            resultsHeader(count: items.count,
                          total: items.reduce(Int64(0)) { $0 + $1.node.size },
                          addAll: { items.forEach { model.addToBasket($0.node) } })
            if junk.isEmpty {
                emptyState("No build caches or dependency folders found.")
            } else {
                List(items) { hit in FinderRow(node: hit.node, badge: hit.rule) }
                    .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Duplicates

    private var duplicateList: some View {
        let groups = filteredGroups
        let reclaimable = groups.reduce(Int64(0)) { $0 + $1.reclaimable }
        return VStack(spacing: 0) {
            resultsHeader(count: groups.count,
                          total: reclaimable,
                          totalLabel: "reclaimable",
                          sortable: false,
                          addAll: { for g in groups { g.files.dropFirst().forEach(model.addToBasket) } })
            if duplicateGroups.isEmpty {
                emptyState("No duplicate files over 1 MB found.")
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(Array(group.files.enumerated()), id: \.element.id) { idx, node in
                                FinderRow(node: node, badge: idx == 0 ? "keep" : nil, dimmed: idx == 0)
                            }
                        } header: {
                            HStack {
                                Text("\(group.files.count) copies · \(Fmt.bytes(group.size)) each")
                                Spacer()
                                Text("free \(Fmt.bytes(group.reclaimable))").foregroundStyle(Theme.amber)
                            }
                            .font(.caption)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Shared UI

    private func resultsHeader(count: Int, total: Int64, totalLabel: String = "total", sortable: Bool = true, addAll: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.count(count)) result\(count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                Text("\(Fmt.bytes(total)) \(totalLabel)")
                    .font(.caption).foregroundStyle(Theme.holoCyan)
            }
            // search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Filter…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 200)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))

            if sortable {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(FinderSort.allCases) { s in
                            Label(s.rawValue, systemImage: s.symbol).tag(s)
                        }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()
            Button(action: addAll) {
                Label("Add all", systemImage: "trash")
            }
            .buttonStyle(GlassButtonStyle(tint: Theme.amber, prominent: true))
            .disabled(count == 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.green)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Compute

    private func compute() async {
        guard let root = model.root else { return }
        query = ""
        files = []; duplicateGroups = []; junk = []

        // Serve from cache if we have it (esp. Duplicates, which hashes).
        if let cached = model.finderCache[taskKey] {
            apply(cached); return
        }

        dupCancel.set()               // stop any in-flight duplicate scan
        let cancel = ManagedAtomicFlag()
        dupCancel = cancel
        loading = true
        let sec = section
        let days = settings.oldFileDays, oldMin = Int64(settings.oldFileMinMB) * 1024 * 1024
        let dupMin = Int64(settings.duplicateMinMB) * 1024 * 1024

        var result: ScanViewModel.FinderResult = .files([])
        switch sec {
        case .largest:
            result = .files(await Task.detached { SmartFinders.largestFiles(in: root) }.value)
        case .old:
            result = .files(await Task.detached { SmartFinders.oldFiles(in: root, days: days, minSize: oldMin) }.value)
        case .devjunk:
            result = .junk(settings.devJunkEnabled
                           ? await Task.detached { SmartFinders.devJunk(in: root) }.value
                           : [])
        case .duplicates:
            result = .dups(await Task.detached {
                SmartFinders.duplicates(in: root, minSize: dupMin, isCancelled: { cancel.isSet }) { name in
                    Task { @MainActor in progressName = name }
                }
            }.value)
        case .explore:
            break
        }
        if !cancel.isSet { model.finderCache[taskKey] = result }
        apply(result)
    }

    private func apply(_ result: ScanViewModel.FinderResult) {
        switch result {
        case .files(let f): files = f
        case .junk(let j): junk = j
        case .dups(let d): duplicateGroups = d
        }
        loading = false
    }
}

struct FinderRow: View {
    @EnvironmentObject var model: ScanViewModel
    let node: FileNode
    var badge: String? = nil
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: NodeIcon.symbol(for: node))
                .foregroundStyle(NodePalette.color(for: node))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(node.name).lineLimit(1)
                    if let badge {
                        Text(badge).font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(badge == "keep" ? Color.green.opacity(0.2) : Theme.holoCyan.opacity(0.18),
                                        in: Capsule())
                            .foregroundStyle(badge == "keep" ? .green : Theme.holoCyan)
                    }
                }
                Text(node.url.deletingLastPathComponent().path)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.bytes(node.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            #if os(macOS)
            Button { PlatformActions.revealInFinder(node) } label: {
                Image(systemName: "magnifyingglass")
            }.buttonStyle(.borderless).help("Reveal in Finder")
            #endif
            Button { model.toggleBasket(node) } label: {
                Image(systemName: model.isInBasket(node) ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(model.isInBasket(node) ? .green : Theme.amber)
            }.buttonStyle(.borderless)
        }
        .opacity(dimmed ? 0.6 : 1)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.showInChart(node) }
        .onTapGesture { model.select(node) }
        .contextMenu { nodeContextItems(node, model: model) }
        .listRowBackground(model.selected?.id == node.id ? Theme.holoCyan.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(Fmt.bytes(node.size))\(model.isInBasket(node) ? ", in basket" : "")")
        .accessibilityHint("Double tap to reveal in the chart")
    }
}

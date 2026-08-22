import SwiftUI

struct BasketBar: View {
    @EnvironmentObject var model: ScanViewModel
    @State private var showConfirm = false
    @State private var showBasket = false
    @State private var lastResult: (trashed: Int, bytes: Int64)?
    @State private var pulse = false

    private var hasItems: Bool { !model.basket.isEmpty }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(hasItems ? Theme.amber.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(hasItems ? Theme.amber.opacity(0.5) : .clear, lineWidth: 1)
                        .scaleEffect(pulse ? 1.25 : 1).opacity(pulse ? 0 : 0.8))
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(hasItems ? Theme.amber : Color.secondary)
            }

            if !hasItems {
                if let r = lastResult {
                    Label("Reclaimed \(Fmt.bytes(r.bytes)) · \(r.trashed) moved to Trash", systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.green)
                } else {
                    Text("Cleanup basket is empty — add items to reclaim space")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("You'll free \(Fmt.bytes(model.basketTotal))")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.amber)
                        .contentTransition(.numericText())
                        .shadow(color: Theme.amber.opacity(0.4), radius: 8)
                    if model.volumeTotal > 0 {
                        Text("\(Fmt.bytes(model.volumeFree)) → \(Fmt.bytes(model.projectedFree)) free")
                            .font(.caption).foregroundStyle(Theme.holoCyan)
                    } else {
                        Text("\(model.basket.count) item\(model.basket.count == 1 ? "" : "s") in basket")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.basketTotal)
            }

            Spacer()

            if !hasItems && !model.lastTrash.isEmpty {
                Button { _ = model.undoLastTrash(); lastResult = nil } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GlassButtonStyle())
            }
            if hasItems {
                Button("Review") { showBasket = true }
                    .buttonStyle(GlassButtonStyle())
                Button { showConfirm = true } label: {
                    Label("Empty to Trash", systemImage: "trash")
                }
                .buttonStyle(GlassButtonStyle(tint: Theme.amber, prominent: true))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .liquidGlass(cornerRadius: 0)
        .overlay(Rectangle().fill(Theme.holoCyan.opacity(hasItems ? 0.3 : 0.12)).frame(height: 1), alignment: .top)
        .onChange(of: hasItems) { _, now in
            if now { withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true } }
            else { pulse = false }
        }
        .confirmationDialog("Move \(model.basket.count) item\(model.basket.count == 1 ? "" : "s") to Trash?",
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                lastResult = model.emptyBasketToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees about \(Fmt.bytes(model.basketTotal)). Items go to the Trash and can be restored.")
        }
        .sheet(isPresented: $showBasket) {
            BasketReviewSheet()
        }
    }
}

struct BasketReviewSheet: View {
    @EnvironmentObject var model: ScanViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cleanup Basket").font(.title2.bold())
                Spacer()
                Text(Fmt.bytes(model.basketTotal))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding()

            Divider()

            List {
                ForEach(model.basket) { node in
                    HStack {
                        Image(systemName: NodeIcon.symbol(for: node))
                            .foregroundStyle(NodePalette.color(for: node))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.name).lineLimit(1)
                            Text(node.url.deletingLastPathComponent().path)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button {
                            model.removeFromBasket(node)
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Divider()
            HStack {
                Button("Clear All") { model.clearBasket(); dismiss() }
                Spacer()
                Button("Close") { dismiss() }
                Button {
                    showConfirm = true
                } label: {
                    Label("Empty to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(model.basket.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 420)
        .confirmationDialog("Move \(model.basket.count) items to Trash?",
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                _ = model.emptyBasketToTrash()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

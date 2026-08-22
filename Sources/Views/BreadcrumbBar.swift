import SwiftUI

struct BreadcrumbBar: View {
    @EnvironmentObject var model: ScanViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button {
                        model.navigateTo(breadcrumbIndex: index)
                    } label: {
                        Text(node.name)
                            .font(.subheadline.weight(index == model.breadcrumb.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == model.breadcrumb.count - 1 ? Color.primary : Color.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

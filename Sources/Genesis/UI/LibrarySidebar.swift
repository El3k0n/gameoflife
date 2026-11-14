import SwiftUI

struct LibrarySidebar: View {
    @Environment(LifeModel.self) private var model
    @State private var query = ""

    var body: some View {
        List {
            ForEach(PatternCategory.allCases) { category in
                let items = filtered(category)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            Button {
                                model.beginPlacing(item)
                            } label: {
                                PatternRow(item: item,
                                           palette: model.palette,
                                           isActive: model.placing != nil && model.placingName == item.name)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Place in World") { model.beginPlacing(item) }
                                Button("Load Alone (Clears the World)") { model.loadPattern(item.pattern, name: item.name) }
                            }
                        }
                    } header: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Search patterns")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Click a pattern, then click in the world", systemImage: "hand.tap")
                Text("R rotate · F flip · Esc done · right-click for more options")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func filtered(_ category: PatternCategory) -> [LibraryItem] {
        let items = PatternLibrary.items(in: category)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)
        }
    }
}

struct PatternRow: View {
    let item: LibraryItem
    let palette: Palette
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            PatternThumbnail(pattern: item.pattern, palette: palette)
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(palette.accent.color, lineWidth: isActive ? 2 : 0)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if let r = item.pattern.rule {
                        Text(r.notation)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    }
                }
                Text(item.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("\(item.summary)\n\(item.pattern.width)×\(item.pattern.height) · \(item.pattern.population) cells")
    }
}

struct PatternThumbnail: View {
    let pattern: Pattern
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let w = max(pattern.width, 1)
            let h = max(pattern.height, 1)
            let pad: CGFloat = 5
            let cell = min((size.width - pad * 2) / CGFloat(w), (size.height - pad * 2) / CGFloat(h))
            let ox = (size.width - cell * CGFloat(w)) / 2
            let oy = (size.height - cell * CGFloat(h)) / 2
            let gap: CGFloat = cell > 3 ? cell * 0.14 : 0
            var path = Path()
            for c in pattern.cells {
                path.addRect(CGRect(x: ox + CGFloat(c.x) * cell + gap / 2,
                                    y: oy + CGFloat(c.y) * cell + gap / 2,
                                    width: max(0.5, cell - gap),
                                    height: max(0.5, cell - gap)))
            }
            let colors = palette.stops.prefix(3).map { $0.color }
            context.fill(path, with: .linearGradient(Gradient(colors: colors),
                                                     startPoint: .zero,
                                                     endPoint: CGPoint(x: size.width, y: size.height)))
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.background.color))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

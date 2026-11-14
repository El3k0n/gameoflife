import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("Space", "Play / pause"),
        ("→  /  ←", "Step forward / back one generation"),
        ("⌘Z", "Undo (go back to the previous state)"),
        ("⇧⌘R", "Reset to the starting state"),
        ("[  /  ]", "Slower / faster"),
        ("1 2 3 4", "Draw · Erase · Select · Pan"),
        ("⌥ + drag", "Pan the view with any tool"),
        ("Pinch / ⌘ + scroll", "Zoom"),
        ("Two fingers", "Pan the view"),
        ("R", "Random soup (or rotate the pattern being placed)"),
        ("F", "Flip the pattern being placed / zoom to content"),
        ("Esc", "Finish placing / deselect"),
        ("⌫", "Clear the selection"),
        ("⌘C  ⌘X  ⌘V", "Copy, cut, paste patterns as RLE"),
        ("0", "Show the whole world"),
        ("G", "Toggle the grid"),
        ("I", "Toggle the inspector"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Genesis")
                        .font(.title.bold())
                    Text("John Conway's Game of Life")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("The rules")
                        .font(.headline)
                    Text("Every cell of the grid is either alive or dead. On each generation, simultaneously for every cell: a dead cell with exactly **3** live neighbors is born; a live cell with **2 or 3** live neighbors survives; every other cell dies or stays dead. From these tiny rules emerge spaceships, oscillators, guns and even universal computers.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("B/S notation describes any rule of this kind: B3/S23 means “born with 3, survives with 2 or 3”. In the inspector you can pick dozens of famous rules or invent new ones by tapping the numbers.")
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Exploring")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        bullet("Pick a pattern from the library and click in the world to place it.")
                        bullet("Travel back in time with ← or ⌘Z: the history records hundreds of generations.")
                        bullet("Genesis notices when the world settles down or enters a cycle, and tells you its period.")
                        bullet("Try symmetric random soups: they often produce surprising structures.")
                        bullet("Open or drop .rle and .cells files (for example from LifeWiki or Golly).")
                    }

                    Text("Shortcuts")
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        ForEach(shortcuts, id: \.0) { item in
                            GridRow {
                                Text(item.0)
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                                Text(item.1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 600, height: 640)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

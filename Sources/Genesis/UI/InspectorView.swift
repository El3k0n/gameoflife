import SwiftUI

struct InspectorView: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Statistics") {
                StatsPanel()
            }

            Section("Rule") {
                RulePanel()
            }

            Section("Random Generator") {
                LabeledContent("Density") {
                    HStack {
                        Slider(value: $model.density, in: 0.02...0.85)
                        Text("\(Int((model.density * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                Picker("Symmetry", selection: $model.symmetry) {
                    ForEach(Symmetry.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Button {
                    model.randomFill()
                } label: {
                    Label(model.selection == nil ? "Fill the Whole World" : "Fill the Selection",
                          systemImage: "dice.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let sel = model.selection {
                Section("Selection") {
                    LabeledContent("Size", value: "\(sel.width) × \(sel.height)")
                    LabeledContent("Origin", value: "\(sel.x), \(sel.y)")
                    HStack {
                        Button("Copy") { model.copySelection() }
                        Button("Cut") { model.copySelection(cut: true) }
                        Button("Clear") { model.deleteSelection() }
                    }
                    HStack {
                        Button("Isolate") { model.clearOutsideSelection() }
                            .help("Clear everything outside the selection")
                        Button("Save…") { model.saveFile() }
                        Button("Deselect") { model.deselect() }
                    }
                }
            }

            Section("World") {
                Picker("Size", selection: $model.gridSize) {
                    ForEach(LifeModel.gridSizes, id: \.self) { size in
                        Text("\(size) × \(size)").tag(size)
                    }
                }
                Picker("Topology", selection: $model.topology) {
                    ForEach(Topology.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                Toggle("Pause when it settles", isOn: $model.autoPause)
                    .help("Stops the simulation when the world becomes static or enters a cycle")
            }

            Section("Appearance") {
                PalettePicker()
                Toggle("Color by age", isOn: $model.ageColoring)
                    .help("Cells change color as they age")
                LabeledContent("Trails") {
                    HStack {
                        Slider(value: $model.trailLength, in: 0...60)
                        Text(model.trailLength < 1 ? "off" : "\(Int(model.trailLength))")
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                Toggle("Grid (when zoomed in)", isOn: $model.showGrid)
                Toggle("Glow", isOn: $model.glow)
                    .help("A luminous halo around cells (visible when the world is not zoomed in too far)")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Statistics

struct StatsPanel: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile("Generation", model.generation.formatted(), "clock")
                    tile("Population", model.population.formatted(), "circle.grid.3x3.fill")
                }
                GridRow {
                    tile("Births", "+\(model.births.formatted())", "plus.circle")
                    tile("Deaths", "−\(model.deaths.formatted())", "minus.circle")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Population over time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let mx = model.popHistory.max(), let mn = model.popHistory.min() {
                        Text("\(mn.formatted())–\(mx.formatted())")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Sparkline(values: model.popHistory, color: model.palette.isLight ? model.palette.stops[1].color : model.palette.accent.color)
                    .frame(height: 64)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.palette.background.color))
            }

            HStack(spacing: 6) {
                Image(systemName: model.statusSymbol)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.statusText)
                        .font(.system(size: 12, weight: .semibold))
                    if let start = model.cycleStart, let period = model.cyclePeriod {
                        Text(period == 1 ? "Unchanged since generation \(start)"
                                         : "Repeats every \(period) generations since \(start)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.population > 0 {
                        Text("No repetition detected yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct Sparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for pt in pts { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.4), color.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let mx = values.max(), let mn = values.min() else { return [] }
        let range = Double(max(mx - mn, 1))
        let n = CGFloat(values.count - 1)
        var result: [CGPoint] = []
        result.reserveCapacity(values.count)
        for (i, v) in values.enumerated() {
            result.append(CGPoint(x: size.width * CGFloat(i) / n,
                                  y: 2 + (size.height - 4) * (1 - CGFloat(Double(v - mn) / range))))
        }
        return result
    }
}

// MARK: - Rule

struct RulePanel: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Picker("Preset", selection: presetBinding) {
                ForEach(RulePreset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                if model.rule.presetName == nil {
                    Divider()
                    Text("Custom").tag("custom")
                }
            }

            if let preset = RulePreset.all.first(where: { $0.rule == model.rule }) {
                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                TextField("Notation", text: $model.ruleText, prompt: Text("B3/S23"))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.applyRuleText() }
                Button("Apply") { model.applyRuleText() }
            }

            RuleEditor()

            Button {
                model.randomRule()
            } label: {
                Label("Random Rule", systemImage: "wand.and.stars")
            }
            .help("Explore: generate a random B/S rule (⌥⌘R)")
        }
        .padding(.vertical, 2)
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { model.rule.presetName != nil ? model.rule.notation : "custom" },
            set: { id in
                if let preset = RulePreset.all.first(where: { $0.id == id }) {
                    model.setRule(preset.rule)
                }
            }
        )
    }
}

/// Visual editor: one chip per neighbor count, for birth and survival.
struct RuleEditor: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(title: "Born with n neighbors",
                isOn: { model.rule.births($0) },
                toggle: { model.setRule(model.rule.togglingBirth($0)) })
            row(title: "Survives with n neighbors",
                isOn: { model.rule.survives($0) },
                toggle: { model.setRule(model.rule.togglingSurvive($0)) })
        }
    }

    private func row(title: String, isOn: @escaping (Int) -> Bool, toggle: @escaping (Int) -> Void) -> some View {
        let pal = model.palette
        let onColor = pal.isLight ? pal.stops[1].color : pal.accent.color
        let onText = pal.isLight ? Color.white : pal.background.color
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { n in
                    let on = isOn(n)
                    Button {
                        toggle(n)
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 23, height: 23)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? onColor : Color.primary.opacity(0.08)))
                            .foregroundStyle(on ? onText : Color.primary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Palette

struct PalettePicker: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(Palette.all) { pal in
                let selected = pal.id == model.paletteID
                Button {
                    model.paletteID = pal.id
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(pal.background.color)
                            HStack(spacing: 3) {
                                ForEach(Array(pal.stops.prefix(4).enumerated()), id: \.offset) { item in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(item.element.color)
                                        .frame(width: 9, height: 9)
                                }
                            }
                        }
                        .frame(height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                              lineWidth: selected ? 2 : 1)
                        )
                        Text(pal.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

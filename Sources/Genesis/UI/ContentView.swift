import SwiftUI

struct ContentView: View {
    @Environment(LifeModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            ZStack {
                LifeCanvas(model: model)
                VStack(spacing: 0) {
                    if let toast = model.toast {
                        ToastView(text: toast, palette: model.palette)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                    Spacer(minLength: 0)
                    HUDView()
                        .padding(.bottom, 16)
                        .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Genesis")
            .navigationSubtitle(model.rule.presetName ?? model.rule.notation)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ToolPicker()
                }
                ToolbarItem(placement: .principal) {
                    PlaybackControls()
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.randomFill()
                    } label: {
                        Label("Random Soup", systemImage: "dice")
                    }
                    .help(model.selection == nil ? "Fill the world with a random soup (R)" : "Randomize the selection (R)")

                    Button {
                        model.zoomToFit()
                    } label: {
                        Label("Zoom to Content", systemImage: "viewfinder")
                    }
                    .help("Zoom to content (⌘0)")

                    Button {
                        model.clearAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .help("Clear the world (⇧⌘⌫) — undo with ⌘Z")

                    Button {
                        model.showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show/hide the inspector (⌥⌘I)")
                }
            }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 310, max: 400)
        }
        .tint(model.palette.isLight ? model.palette.stops[1].color : model.palette.accent.color)
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
    }
}

// MARK: - Toolbar

struct ToolPicker: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Tool", selection: $model.tool) {
            ForEach(Tool.allCases) { tool in
                Image(systemName: tool.symbol)
                    .accessibilityLabel(tool.label)
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Tools: 1 Draw · 2 Erase · 3 Select · 4 Pan (⌥-drag always pans)")
    }
}

struct PlaybackControls: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.resetToStart()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .help("Reset to the starting state (⇧⌘R)")
            .disabled(!model.hasStartSnapshot)

            Button {
                model.stepBack()
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .help("Step back one generation (←) — works after edits too")
            .disabled(!model.canStepBack)

            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .help("Play / Pause (Space)")

            Button {
                model.step()
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .help("Step forward one generation (→)")

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 6)

            Image(systemName: "tortoise.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(value: speedBinding, in: 0...Double(LifeModel.speeds.count - 1), step: 1)
                .frame(width: 120)
                .controlSize(.small)
                .help("Simulation speed ([ and ])")
            Image(systemName: "hare.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(model.speedLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
        }
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { Double(model.speedIndex) },
                set: { model.speedIndex = max(0, min(LifeModel.speeds.count - 1, Int($0.rounded()))) })
    }
}

// MARK: - HUD and notifications

struct HUDView: View {
    @Environment(LifeModel.self) private var model

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 2) {
                dockButton("backward.frame.fill", "Step back (←)", enabled: model.canStepBack) { model.stepBack() }
                dockButton(model.isRunning ? "pause.fill" : "play.fill", "Play / Pause (Space)", prominent: true) { model.togglePlay() }
                dockButton("forward.frame.fill", "Step forward (→)") { model.step() }
            }
            Divider().frame(height: 26)
            stat("Generation", model.generation.formatted())
            stat("Population", model.population.formatted())
            stat("Speed", model.isRunning ? "\(Int(model.measuredSpeed.rounded())) gen/s" : "paused")
            if let c = model.hoverCell {
                stat("Cell", "\(c.x), \(c.y)")
            }
            Label(model.statusText, systemImage: model.statusSymbol)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            if model.placing != nil, let name = model.placingName {
                Text("“\(name)” · R rotate · F flip · Esc cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .padding(.vertical, 6)
        .fixedSize()
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .environment(\.colorScheme, model.palette.isLight ? .light : .dark)
    }

    private func dockButton(_ symbol: String, _ help: String, enabled: Bool = true, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 15 : 12, weight: .semibold))
                .frame(width: prominent ? 34 : 26, height: prominent ? 34 : 26)
                .background(Circle().fill(prominent ? Color.primary.opacity(0.14) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }
}

struct ToastView: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.accent.color.opacity(0.35)))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
    }
}

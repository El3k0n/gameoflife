import SwiftUI

struct GenesisCommands: Commands {
    let model: LifeModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Empty World") { model.clearAll() }
                .keyboardShortcut("n")
            Button("Open Pattern…") { model.openFile() }
                .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save as RLE…") { model.saveFile() }
                .keyboardShortcut("s")
            Button("Export PNG Image…") { model.exportPNG() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo (Step Back)") { model.menuUndo() }
                .keyboardShortcut("z")
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { model.menuCut() }
                .keyboardShortcut("x")
            Button("Copy") { model.menuCopy() }
                .keyboardShortcut("c")
            Button("Paste") { model.menuPaste() }
                .keyboardShortcut("v")
            Divider()
            Button("Select All") { model.menuSelectAll() }
                .keyboardShortcut("a")
            Button("Deselect") { model.deselect() }
                .keyboardShortcut("d")
        }

        CommandMenu("Simulation") {
            Button("Play / Pause") { model.togglePlay() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Step Forward") { model.step() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Step Back") { model.stepBack() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Reset to Start") { model.resetToStart() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Faster") { model.faster() }
                .keyboardShortcut("]")
            Button("Slower") { model.slower() }
                .keyboardShortcut("[")
            Divider()
            Button("Random Soup") { model.randomFill() }
                .keyboardShortcut("r")
            Button("Random Rule") { model.randomRule() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Clear World") { model.clearAll() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-")
            Button("Zoom to Content") { model.zoomToFit() }
                .keyboardShortcut("0")
            Button("Show Whole World") { model.zoomToWorld() }
                .keyboardShortcut("9")
            Divider()
            Button("Toggle Grid") { model.showGrid.toggle() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
        }

        SidebarCommands()

        CommandGroup(replacing: .help) {
            Button("Genesis Help") { model.showHelp = true }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

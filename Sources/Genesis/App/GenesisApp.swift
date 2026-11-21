import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the executable is launched outside an .app bundle (e.g. `swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if #available(macOS 14.4, *), let snapshot = Snapshot(arguments: CommandLine.arguments) {
            Task { await snapshot.run() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            LifeModel.shared.loadFile(url)
        }
    }
}

@main
struct GenesisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Window("Genesis", id: "main") {
            ContentView()
                .environment(LifeModel.shared)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1400, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            GenesisCommands(model: LifeModel.shared)
        }
    }
}

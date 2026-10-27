import AppKit
import SwiftUI

@main
struct ProteusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SearchModel()
    /// The splash screen, shown at every launch and again from About Proteus.
    @State private var isAboutPresented = true

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window(Brand.name, id: "main") {
            AboutPresentation(isPresented: isAboutPresented, dismiss: { isAboutPresented = false }) {
                ContentView(model: model)
            }
        }
        .commands {
            // Replaces the standard About panel with the splash screen.
            CommandGroup(replacing: .appInfo) {
                Button("About Proteus") { isAboutPresented = true }
            }
            // Text fields keep ⌘Z for typing; undoing files gets its own shortcut.
            CommandGroup(after: .undoRedo) {
                Button("Undo Last Rename or Trash") { Task { await model.undoLast() } }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(!model.canUndo)
            }
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o")
            }
        }
    }
}

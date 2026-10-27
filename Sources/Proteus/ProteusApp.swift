import AppKit
import SwiftUI

@main
struct ProteusApp: App {
    /// The splash screen, shown at every launch and again from About Proteus.
    @State private var isAboutPresented = true

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window(Brand.name, id: "main") {
            AboutPresentation(isPresented: isAboutPresented, dismiss: { isAboutPresented = false }) {
                ContentView()
            }
        }
        .commands {
            // Replaces the standard About panel with the splash screen.
            CommandGroup(replacing: .appInfo) {
                Button("Σχετικά με το Proteus") { isAboutPresented = true }
            }
        }
    }
}

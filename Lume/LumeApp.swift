//
//  LumeApp.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData
import AppKit

final class WindowOpener {
    static let shared = WindowOpener()
    var openSettings: (() -> Void)?
    var openNewProject: (() -> Void)?
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        nukeSplitViewState()
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        applyWindowConstraints()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applyWindowConstraints() {
        for window in NSApp.windows {
            guard window.isVisible,
                  !window.isSheet,
                  window.styleMask.contains(.titled),
                  !["Settings", "Configurações", "New Project", "Novo Projeto"].contains(window.title),
                  !(window is NSPanel)
            else { continue }

            let minW: CGFloat = 1100
            let minH: CGFloat = 660

            window.minSize = NSSize(width: minW, height: minH)

            if window.frame.width < minW || window.frame.height < minH {
                var f = window.frame
                f.size.width  = max(f.size.width,  minW)
                f.size.height = max(f.size.height, minH)
                if let screen = window.screen {
                    f.origin.x = max(screen.visibleFrame.minX, min(f.origin.x, screen.visibleFrame.maxX - f.size.width))
                    f.origin.y = max(screen.visibleFrame.minY, min(f.origin.y, screen.visibleFrame.maxY - f.size.height))
                }
                window.setFrame(f, display: true, animate: false)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.enforceSidebarWidth(in: window, minWidth: 260)
            }
        }
    }

    private func enforceSidebarWidth(in window: NSWindow, minWidth: CGFloat) {
        guard let splitView = findSplitView(in: window.contentView) else { return }
        if let first = splitView.subviews.first, first.frame.width < minWidth {
            splitView.setPosition(minWidth, ofDividerAt: 0)
        }
    }

    private func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView { return split }
        for sub in view.subviews {
            if let found = findSplitView(in: sub) { return found }
        }
        return nil
    }

    private func nukeSplitViewState() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.contains("NSSplitView") || key.contains("SplitView") ||
               key.contains("NavigationSplit") || key.contains("NSWindow Frame") ||
               key.contains("splitView") || key.contains("columnWidth") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
    }
}

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var config = LumeConfig.load()
    @State private var showSettings = false
    // ✅ Novo Projeto agora é sheet
    @State private var showNewProject = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self, Conversation.self, Message.self, Artifact.self,
            AIProviderConfig.self, StyleProfile.self, MCPConnector.self,
            ScheduledTask.self, Workflow.self
        ])
        do {
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            ])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        KeychainMigration.runIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .task { FullDiskAccessHelper.requestAccessIfNeeded() }
                .environment(\.lumeConfig, config)
                .withWindowOpenerSetup(showSettings: $showSettings, showNewProject: $showNewProject)
                .onAppear {
                    DispatchQueue.main.async {
                        DispatchQueue.main.async {
                            self.appDelegate.applyWindowConstraints()
                        }
                    }
                }
                // Settings sheet
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .modelContainer(sharedModelContainer)
                        .environment(\.lumeConfig, config)
                        .frame(width: 900, height: 580)
                        .fixedSize()
                        .interactiveDismissDisabled(false)
                }
                // ✅ Novo Projeto como sheet
                .sheet(isPresented: $showNewProject) {
                    NewProjectSheet()
                        .modelContainer(sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            LumeMenuCommands(showSettings: $showSettings)
        }
        .defaultSize(width: 1300, height: 760)
        .restorationBehavior(.disabled)
        // ✅ Window("New Project") removida

        // ── Janela String(localized: "About Lume") ─────────────────────────────────
        Window(String(localized: "About Lume"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
    }
}

// MARK: - Comandos de menu

/// Comandos do menu do app. Em um `Commands` dedicado conseguimos acessar
/// `openWindow` via Environment para abrir a janela String(localized: "About Lume").
private struct LumeMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Binding var showSettings: Bool

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Lume")) {
                openWindow(id: "about")
            }
        }
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

// MARK: - Helper view modifier

private struct WindowOpenerSetup: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showNewProject: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            WindowOpener.shared.openSettings   = { showSettings   = true }
            WindowOpener.shared.openNewProject = { showNewProject = true }
        }
    }
}

private extension View {
    func withWindowOpenerSetup(showSettings: Binding<Bool>, showNewProject: Binding<Bool>) -> some View {
        modifier(WindowOpenerSetup(showSettings: showSettings, showNewProject: showNewProject))
    }
}

// MARK: - Environment

struct LumeConfigKey: EnvironmentKey {
    static let defaultValue = LumeConfig()
}

extension EnvironmentValues {
    var lumeConfig: LumeConfig {
        get { self[LumeConfigKey.self] }
        set { self[LumeConfigKey.self] = newValue }
    }
}

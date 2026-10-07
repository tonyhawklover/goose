//
//  GooseApp.swift
//  Goose
//
//  Originally by Oz Tamir.
//  Modified for Goose.
//

import SwiftUI
import AppIntents

struct GooseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GooseLockIntent(), phrases: ["Lock \(.applicationName)", "Unlock \(.applicationName)"])
    }
}

@main
struct GooseApp: App {
    @StateObject private var appBlocker = AppBlocker()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var tagManager = TagManager()
    @StateObject private var rulesManager = BlockRulesManager()

    var body: some Scene {
        WindowGroup {
            GooseView()
                .environmentObject(appBlocker)
                .environmentObject(profileManager)
                .environmentObject(tagManager)
                .environmentObject(rulesManager)
        }
    }
}
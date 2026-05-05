//
//  NMApp.swift
//  NM
//
//  Created by nomo1982 on 2026/4/25.
//

import SwiftUI

@main
struct NMApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowTitle(Config.shared.meetingName)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("设置...") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("NMShowSettings")
}
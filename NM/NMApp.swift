//
//  NMApp.swift
//  NM
//
//  Created by nomo1982 on 2026/4/25.
//

import SwiftUI

@main
struct NMApp: App {
    @StateObject private var localization = LocalizationManager.shared

    init() {
        // 并行预加载Tokenizer和BGE-M3模型，互不依赖，总耗时从17秒缩短到10秒
        DispatchQueue.global(qos: .userInitiated).async {
            _ = TokenizerService.shared
            print("✅ [预加载] Tokenizer词表加载完成")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = BGEM3EmbeddingService.shared
            print("✅ [预加载] BGE-M3模型加载完成")
        }
    }

    var body: some Scene {
        WindowGroup(localization.appWindowTitle) {
            ContentView()
                .environmentObject(localization)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(localization.settingsMenuTitle) {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button("Normal Meeting 帮助") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("NMShowSettings")
    static let showHelp = Notification.Name("NMShowHelp")
}
//
//  RaceCompassApp.swift
//  RaceCompass
//
//  Created by russellkt on 1/22/26.
//

import SwiftUI

@main
struct RaceCompassApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var watchRemote = WatchRemoteService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(watchRemote)
                .onAppear { watchRemote.initialize() }
                .onOpenURL { watchRemote.handleOpenURL($0) }
        }
    }
}

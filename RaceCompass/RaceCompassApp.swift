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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
        }
    }
}

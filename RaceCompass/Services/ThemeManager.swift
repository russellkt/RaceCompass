import SwiftUI

protocol Theme {
    var name: String { get }
    var background: Color { get }
    var primaryText: Color { get }
    var secondaryText: Color { get }
    var positive: Color { get } // Green/Good
    var negative: Color { get } // Red/Bad
    var warning: Color { get }  // Orange
    var tint: Color { get }     // Button/Action color
    var bubbleFill: Color { get } // For bubbles like compass
    var bubbleText: Color { get } // Text inside bubbles
    var topBarBackground: Color { get }
}

struct DayTheme: Theme {
    var name = "Day"
    var background = Color.white
    var primaryText = Color.black
    var secondaryText = Color.gray
    var positive = Color.green
    var negative = Color.red
    var warning = Color.orange
    var tint = Color.blue
    var bubbleFill = Color.black
    var bubbleText = Color.white
    var topBarBackground = Color.white
}

struct NightTheme: Theme {
    var name = "Night"
    var background = Color.black
    var primaryText = Color(red: 1.0, green: 0.1, blue: 0.1) // Red
    var secondaryText = Color(red: 0.6, green: 0.0, blue: 0.0) // Dim Red
    var positive = Color(red: 1.0, green: 0.3, blue: 0.3) // Bright Red
    var negative = Color(red: 0.3, green: 0.0, blue: 0.0) // Dark Red (or maybe blinking)
    var warning = Color(red: 1.0, green: 0.5, blue: 0.0) // Orange
    var tint = Color(red: 0.8, green: 0.0, blue: 0.0) // Red
    var bubbleFill = Color(red: 0.2, green: 0.0, blue: 0.0) // Dark Red bg
    var bubbleText = Color(red: 1.0, green: 0.1, blue: 0.1) // Red text
    var topBarBackground = Color.black
}

struct HighContrastTheme: Theme {
    var name = "High Contrast"
    var background = Color.black
    var primaryText = Color.white
    var secondaryText = Color.gray
    var positive = Color.white // Rely on text/icon, not just color
    var negative = Color.white
    var warning = Color.white
    var tint = Color.white
    var bubbleFill = Color.white
    var bubbleText = Color.black
    var topBarBackground = Color.black
}

class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme = DayTheme()

    // For persistence, we could save the name string
    @AppStorage("selectedThemeName") var selectedThemeName: String = "Day" {
        didSet {
            updateTheme()
        }
    }

    init() {
        updateTheme()
    }

    func updateTheme() {
        switch selectedThemeName {
        case "Night":
            currentTheme = NightTheme()
        case "High Contrast":
            currentTheme = HighContrastTheme()
        default:
            currentTheme = DayTheme()
        }
    }

    func setTheme(_ name: String) {
        selectedThemeName = name
    }
}

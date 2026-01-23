import UIKit
import SwiftUI

class HapticManager {
    static let shared = HapticManager()

    private let defaults = UserDefaults.standard
    private let key = "hapticsEnabled"

    var isEnabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: key) }
    }

    private init() {}

    private func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Semantic Haptics

    /// Triggered when the start phase changes (e.g. Hold -> Build)
    func playPhaseChange() {
        guard isEnabled else { return }
        // Distinct double tap to signal attention
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.impactOccurred()
        }
    }

    /// Triggered at the start gun (0:00)
    func playGun() {
        notification(type: .success)
    }

    /// Triggered for warnings (e.g. Late, OCS risk)
    func playWarning() {
        notification(type: .warning)
    }

    /// Triggered for positive confirmation (e.g. Ping set)
    func playSuccess() {
        notification(type: .success)
    }

    /// Triggered for countdown ticks (e.g. every second in last 10s)
    func playTick() {
        impact(style: .soft)
    }

    /// Triggered when button is tapped
    func playSelection() {
        impact(style: .light)
    }
}

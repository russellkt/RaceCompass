import Foundation
import Combine

class TimerService: ObservableObject {
    @Published var currentDate: Date = Date()
    private var timer: Timer?

    func start() {
        // Invalidate existing timer if any
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: Constants.timerInterval, repeats: true) { [weak self] _ in
            self?.currentDate = Date()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

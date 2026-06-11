import Foundation
import Combine
import CoreLocation
import ConnectIQ

// Bridge to the Garmin Connect IQ companion app (repo: racecompass-ciq).
// The watch is a thin terminal: we push phase/ttb/ttl at 1Hz plus vibe
// alerts on threshold crossings; the watch sends back button commands.
// Message contract is frozen in racecompass-ciq/README.md — keys must
// match the watch side exactly.
final class WatchRemoteService: NSObject, ObservableObject {

    static let urlScheme = "racecompass-ciq"
    // CIQ app id from racecompass-ciq/manifest.xml
    private static let watchAppUUID = UUID(uuidString: "3b05ca32-754a-4491-942e-68613c5c8cf9")!
    private static let devicesKey = "watchRemote.devices"

    @Published var deviceName: String?
    @Published var isConnected = false
    @Published var markEvents: [Date] = []

    private weak var compass: CompassViewModel?
    private var devices: [IQDevice] = []
    private var apps: [IQApp] = []
    private var pushTimer: AnyCancellable?
    private var lastLaylineZone = 0

    func initialize() {
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: nil)
        restoreDevices()
    }

    func attach(_ compass: CompassViewModel) {
        guard self.compass == nil else { return }
        self.compass = compass
        pushTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pushUpdate() }
    }

    // Opens Garmin Connect Mobile; it calls back via our URL scheme.
    func connectWatch() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              let parsed = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice]
        else { return }
        setDevices(parsed)
        saveDevices()
    }

    // MARK: - Phone -> watch

    private func pushUpdate() {
        guard let compass, isConnected, !apps.isEmpty else { return }
        var msg: [String: Any] = [
            "phase": compass.isTimerRunning && compass.secondsToStart > 0 ? "START" : "RACE",
            "ttb": Int(compass.timeToBurn),
            "ttl": Int(compass.timeToLayline),
        ]
        if let vibe = laylineVibe(compass) { msg["vibe"] = vibe }
        for app in apps {
            ConnectIQ.sharedInstance().sendMessage(msg, to: app, progress: nil) { _ in }
        }
    }

    // short buzz entering the 30s-to-layline window, long buzz on overstood
    private func laylineVibe(_ compass: CompassViewModel) -> String? {
        let ttl = compass.timeToLayline
        let zone = ttl < 0 ? -1 : (ttl > 0 && ttl <= 30 ? 1 : 0)
        defer { lastLaylineZone = zone }
        if zone == 1 && lastLaylineZone == 0 { return "short" }
        if zone == -1 && lastLaylineZone >= 0 { return "long" }
        return nil
    }

    // MARK: - Watch -> phone

    private func handleCommand(_ cmd: String) {
        guard let compass else { return }
        switch cmd {
        case "ping":
            // First press sets the boat (RC) end, second the pin;
            // afterwards re-ping whichever end is nearer.
            if compass.boatEnd == nil {
                compass.pingBoat()
            } else if compass.pinEnd == nil {
                compass.pingPin()
            } else if let loc = compass.currentLocation,
                      let pin = compass.pinEnd, let boat = compass.boatEnd {
                loc.distance(from: pin) < loc.distance(from: boat) ? compass.pingPin() : compass.pingBoat()
            }
        case "sync_gun":
            // Round the running countdown to the nearest whole minute.
            let mins = max(1, (compass.secondsToStart / 60).rounded())
            compass.syncTimer(minutes: mins)
        case "mark":
            markEvents.append(Date())
        default:
            break
        }
    }

    // MARK: - Device bookkeeping

    private func setDevices(_ list: [IQDevice]) {
        guard let ciq = ConnectIQ.sharedInstance() else { return }
        ciq.unregister(forAllDeviceEvents: self)
        ciq.unregister(forAllAppMessages: self)
        devices = list
        apps = list.map { device in
            ciq.register(forDeviceEvents: device, delegate: self)
            let app = IQApp(uuid: Self.watchAppUUID, store: Self.watchAppUUID, device: device)
            ciq.register(forAppMessages: app, delegate: self)
            return app!
        }
        deviceName = list.first?.friendlyName
    }

    private func saveDevices() {
        let plist = devices.map {
            ["id": $0.uuid.uuidString, "model": $0.modelName ?? "", "name": $0.friendlyName ?? ""]
        }
        UserDefaults.standard.set(plist, forKey: Self.devicesKey)
    }

    private func restoreDevices() {
        guard let plist = UserDefaults.standard.array(forKey: Self.devicesKey) as? [[String: String]],
              !plist.isEmpty else { return }
        setDevices(plist.compactMap {
            guard let id = UUID(uuidString: $0["id"] ?? "") else { return nil }
            return IQDevice(id: id, modelName: $0["model"] ?? "", friendlyName: $0["name"] ?? "")
        })
    }
}

extension WatchRemoteService: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        isConnected = (status == .connected)
        if status != .connected { lastLaylineZone = 0 }
    }
}

extension WatchRemoteService: IQAppMessageDelegate {
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any],
              let cmd = dict["cmd"] as? String else { return }
        handleCommand(cmd)
    }
}

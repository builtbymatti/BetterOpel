import Foundation
import UserNotifications
import WidgetKit

/// One start of the climate from the Lock Screen, as the widget shows it and
/// the notifications tell it.
struct PreheatStatus: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case idle, sending, waking, sent, running, failed
    }

    var phase = Phase.idle
    var at = Date.distantPast
    var detail = ""

    /// Still on its way: a second tap should not start a second one.
    var isBusy: Bool { phase == .sending || phase == .waking }
}

enum PreheatStore {
    static let widgetKind = "com.example.betteropel.preheat"
    private static let key = "preheat.status"

    /// How long each state is worth showing before the widget goes back to rest.
    static func lifetime(of phase: PreheatStatus.Phase) -> TimeInterval {
        switch phase {
        case .idle: .infinity
        case .sending, .waking: 120
        case .sent: 180
        case .running: ClimateState.cycleMinutes * 60
        case .failed: 300
        }
    }

    static func current(now: Date = .now) -> PreheatStatus {
        guard let data = SnapshotStore.defaults.data(forKey: key),
              let status = try? JSONDecoder().decode(PreheatStatus.self, from: data),
              now.timeIntervalSince(status.at) < lifetime(of: status.phase)
        else { return PreheatStatus() }
        return status
    }

    static func set(_ phase: PreheatStatus.Phase, detail: String = "") {
        let status = PreheatStatus(phase: phase, at: .now, detail: detail)
        SnapshotStore.defaults.set(try? JSONEncoder().encode(status), forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

/// The notification that follows a start. It is one notification that changes
/// its words, not a new one for every step.
enum PreheatNotice {
    private static let identifier = "com.example.betteropel.preheat"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Only the last word of a start makes a sound.
    static func post(_ title: String, _ body: String, isFinal: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = identifier
        content.sound = isFinal ? .default : nil
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

enum Preheat {
    /// Starts the climate and reports each step as it happens. With a server,
    /// the server does the waking, sending and waiting, and this follows it for
    /// as long as the system lets something run in the background.
    static func start() async {
        guard !PreheatStore.current().isBusy else { return }

        guard ConnectionStore.isLive, let server = VehicleService.warmUps as? ServerWarmUps else {
            await tell(.sending, "Sending the start", "To the demo car.")
            await direct(isDemo: true)
            return
        }
        await tell(.sending, "Sending the start", "Asking your server.")

        guard var run = try? await server.startNow() else {
            // A server without the scheduler can still pass the command on.
            await direct(isDemo: false)
            return
        }
        // The app shows the climate as asked for until the car has its say.
        Expectations.set(.climate, to: true)

        let deadline = Date.now.addingTimeInterval(22)
        var told = ""
        while true {
            if run.phase != told {
                told = run.phase
                switch run.phase {
                case "waking":
                    await tell(.waking, "Waking the car", "It is asleep and can take a minute or two to answer.")
                case "sending", "waiting":
                    await tell(.sent, "Start sent", "Waiting for the car to say it is running.")
                case "confirmed":
                    await finishRunning(isDemo: false)
                    return
                case "sent":
                    await tell(.sent, "Start sent", "The car did not confirm. It may still be starting.", isFinal: true)
                    return
                default:
                    await tell(.failed, "The climate did not start", run.detail.isEmpty ? "The server could not reach the car." : run.detail, isFinal: true)
                    return
                }
            }
            guard Date.now < deadline else { break }
            try? await Task.sleep(for: .seconds(2))
            run = (try? await server.runState()) ?? run
        }

        // Out of time on this side. The server carries on by itself.
        if told == "waking" {
            await PreheatNotice.post("Still waking the car", "Your server keeps trying. This can take another minute or two.", isFinal: true)
        } else {
            await PreheatNotice.post("Start sent", "The car has not confirmed yet. That can take another minute or two.", isFinal: true)
        }
    }

    private static func direct(isDemo: Bool) async {
        do {
            _ = try await VehicleService.background.setPreconditioning(true)
            if isDemo {
                await finishRunning(isDemo: true)
            } else {
                await tell(.sent, "Start sent", "The car takes a minute or two to answer.", isFinal: true)
            }
        } catch {
            await tell(.failed, "The climate did not start", error.localizedDescription, isFinal: true)
        }
    }

    private static func finishRunning(isDemo: Bool) async {
        let ready = Date.now.addingTimeInterval(ClimateState.cycleMinutes * 60)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: ready)
        let clock = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0).label
        await tell(.running, "Climate is running", (isDemo ? "Demo car. " : "") + "The cabin is ready around \(clock).", isFinal: true)
    }

    private static func tell(_ phase: PreheatStatus.Phase, _ title: String, _ body: String, isFinal: Bool = false) async {
        PreheatStore.set(phase, detail: phase == .failed ? body : "")
        await PreheatNotice.post(title, body, isFinal: isFinal)
    }
}

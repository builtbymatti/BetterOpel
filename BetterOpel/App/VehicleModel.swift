import SwiftUI
import WidgetKit

/// The one object the interface observes. It forwards commands to the vehicle
/// API, tracks which of them are in flight, and turns results into the haptic
/// and visual cues the views react to.
@MainActor
@Observable
final class VehicleModel {
    enum Command: Hashable {
        case refresh, lock, climate, charging, lights, horn, limit, schedule, programs
    }

    struct Notice: Equatable, Identifiable {
        enum Tone { case confirm, problem }
        let id = UUID()
        var icon: OpelIcon
        var text: String
        var tone: Tone = .confirm
    }

    private(set) var snapshot: VehicleSnapshot
    private(set) var trips: [Trip] = []
    private(set) var sessions: [ChargingSession] = []
    private(set) var pending: Set<Command> = []
    var notice: Notice?

    /// Counters the hero listens to. Each bump plays the matching light cue once.
    private(set) var lightFlashes = 0
    private(set) var lockCue = 0
    private(set) var chargeCue = 0
    /// Counts refreshes that brought back a newer reading, and those that did not.
    private(set) var refreshCue = 0
    private(set) var refreshMisses = 0

    var tariff = ElectricityTariff.standard

    /// Times the server starts the climate by itself.
    private(set) var warmUps: [WarmUp] = []
    private(set) var warmUpLink = WarmUpLink.loading

    enum WarmUpLink: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    /// The soonest start the server has planned.
    var nextWarmUp: WarmUp? {
        warmUps.filter { $0.isOn && $0.nextStart != nil }.min { ($0.nextStart ?? .distantFuture) < ($1.nextStart ?? .distantFuture) }
    }

    /// The colourway. Changing it re-dresses the app and the widgets.
    var theme = ThemeStore.current {
        didSet {
            guard theme != oldValue else { return }
            ThemeStore.set(theme)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Where the data comes from right now.
    enum Link: Equatable {
        case demo
        case connecting
        case live
        case offline(String)
    }

    private(set) var link: Link
    private(set) var isLive: Bool
    /// False for a real car until the server has answered at least once.
    private(set) var hasReading: Bool

    /// Commands that were sent and that the car has not confirmed yet.
    private(set) var awaiting: Set<Expectations.Kind> = []

    func isAwaiting(_ kind: Expectations.Kind) -> Bool { awaiting.contains(kind) }

    private func refreshAwaiting() {
        let now = Date.now
        let waiting = Set([Expectations.Kind.locked, .climate, .charging].filter { Expectations.isWaiting($0, now: now) })
        if waiting != awaiting { withAnimation(Motion.snappy) { awaiting = waiting } }
    }

    private var api: any VehicleAPI
    private var ticker: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastActivityLevel = -1.0
    private var lastPoll = Date.distantPast
    private var isPolling = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // `-resetDemo` disconnects first so public demos never use a saved car connection.
        if arguments.contains("-resetDemo") {
            ConnectionStore.disconnect()
            SnapshotStore.reset()
            DemoWarmUps.reset()
        }
        // `-parked` starts the demo car unplugged, so nothing ticks during a capture.
        if arguments.contains("-parked") {
            var parked = SnapshotStore.load()
            parked.charging.status = .disconnected
            parked.charging.powerKW = 0
            SnapshotStore.save(parked)
        }
        // `-theme copper` picks a colourway.
        if let index = arguments.firstIndex(of: "-theme"), arguments.indices.contains(index + 1),
           let theme = AppTheme(rawValue: arguments[index + 1]) {
            ThemeStore.set(theme)
        }
        // `-server http://host:5055 -vin XXXX` connects to a server; `-server none` returns to the demo.
        if let index = arguments.firstIndex(of: "-server"), arguments.indices.contains(index + 1) {
            if arguments[index + 1] == "none" {
                ConnectionStore.disconnect()
            } else {
                ConnectionStore.server = arguments[index + 1]
                if let vinIndex = arguments.firstIndex(of: "-vin"), arguments.indices.contains(vinIndex + 1) {
                    ConnectionStore.vin = arguments[vinIndex + 1]
                }
            }
        }
        #endif
        api = VehicleService.current
        isLive = ConnectionStore.isLive
        link = ConnectionStore.isLive ? .connecting : .demo
        hasReading = !ConnectionStore.isLive || SnapshotStore.hasLiveSnapshot
        theme = ThemeStore.current
        snapshot = SnapshotStore.load()
    }

    func isPending(_ command: Command) -> Bool { pending.contains(command) }

    /// One line for the header: the car's state, or why there is none.
    var headline: String {
        switch link {
        case .offline(let reason): reason
        case .connecting where !hasReading: "Connecting to your car"
        default: snapshot.statusLine
        }
    }

    // MARK: Lifecycle

    func start() {
        guard ticker == nil else { return }
        lastPoll = .distantPast
        loadHistory()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Picks up a changed connection: a new server, or back to the demo.
    func reconnect() {
        api = VehicleService.current
        isLive = ConnectionStore.isLive
        link = isLive ? .connecting : .demo
        hasReading = !isLive || SnapshotStore.hasLiveSnapshot
        lastPoll = .distantPast
        trips = []
        sessions = []
        withAnimation(Motion.fluid) { snapshot = SnapshotStore.load() }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        loadHistory()
        warmUps = []
        warmUpLink = .loading
        Task { await loadWarmUps() }
        tick()
    }

    private func loadHistory() {
        let api = api
        Task {
            let loadedTrips = (try? await api.trips()) ?? []
            let loadedSessions = (try? await api.chargingSessions()) ?? []
            withAnimation(Motion.fluid) {
                trips = loadedTrips
                sessions = loadedSessions
            }
            await nameTrips()
        }
    }

    /// Called every second while the app is in front.
    func tick() {
        // An optimistic edit is waiting for the car; don't read the old value back.
        guard pending.isDisjoint(with: [.limit, .schedule, .programs]) else { return }

        if isLive {
            refreshAwaiting()
            // Siri, a widget or a control may have talked to the car meanwhile.
            if hasReading, SnapshotStore.hasLiveSnapshot {
                let stored = SnapshotStore.load()
                if stored != snapshot { adopt(stored) }
            }
            // While a command waits on the car, look more often.
            if !isPolling, Date.now.timeIntervalSince(lastPoll) >= (awaiting.isEmpty ? 30 : 10) {
                Task { await poll() }
            }
            return
        }

        // The demo car: re-reading the store also advances the simulation.
        let fresh = SnapshotStore.load()
        if fresh != snapshot { adopt(fresh) }
    }

    private func poll() async {
        isPolling = true
        lastPoll = .now
        defer { isPolling = false }
        do {
            // Waiting on a command, the server's cached reading would lag behind.
            let fresh = try await api.vehicleInfo(fromCache: awaiting.isEmpty)
            hasReading = true
            if fresh != snapshot { adopt(fresh) }
            reportUnconfirmed()
            refreshAwaiting()
            if link != .live { withAnimation(Motion.snappy) { link = .live } }
        } catch {
            let reason = error.localizedDescription
            if link != .offline(reason) { withAnimation(Motion.snappy) { link = .offline(reason) } }
        }
    }

    /// Says so when the car never confirmed something that was asked of it.
    private func reportUnconfirmed() {
        guard let kind = Expectations.takeUnconfirmed() else { return }
        let what = switch kind {
        case .climate: "The car didn't confirm the climate"
        case .locked: "The car didn't confirm the lock"
        case .charging: "The car didn't confirm charging"
        }
        Haptics.shared.failure()
        show(Notice(icon: .warning, text: what, tone: .problem))
    }

    /// Takes on a new reading that arrived by itself, not as the result of a command.
    private func adopt(_ fresh: VehicleSnapshot) {
        let finishedNow = snapshot.isCharging && fresh.charging.status == .finished
        withAnimation(Motion.fluid) { snapshot = fresh }
        if finishedNow {
            Haptics.shared.success()
            show(Notice(icon: .check, text: "Charged to \(fresh.batteryPercent)%"))
            WidgetCenter.shared.reloadAllTimelines()
            syncActivity(force: true)
        } else {
            syncActivity(force: false)
        }
        nameLocation()
    }

    private func syncActivity(force: Bool) {
        // Live Activities are budgeted, so only push meaningful steps.
        guard force || abs(snapshot.batteryLevel - lastActivityLevel) >= 0.5 else { return }
        lastActivityLevel = snapshot.batteryLevel
        let snapshot = snapshot
        Task { await ChargingLiveActivity.sync(with: snapshot) }
    }

    /// Takes on the car's answer to a command.
    private func apply(_ fresh: VehicleSnapshot) {
        withAnimation(Motion.fluid) { snapshot = fresh }
        if isLive {
            hasReading = true
            lastPoll = .now
            if link != .live { link = .live }
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        syncActivity(force: true)
        nameLocation()
    }

    // MARK: Place names

    /// A real car reports coordinates only; look the address up once per spot.
    private func nameLocation() {
        guard isLive, snapshot.address.isEmpty else { return }
        let location = snapshot.location
        Task {
            guard let place = await PlaceNamer.shared.place(for: location), snapshot.location == location else { return }
            withAnimation(Motion.fluid) {
                snapshot.address = place.street
                snapshot.locality = place.locality
            }
            SnapshotStore.save(snapshot)
        }
    }

    private func nameTrips() async {
        guard isLive else { return }
        // Newest first, and only as many as someone will scroll through.
        for trip in trips.prefix(40) where trip.to.isEmpty {
            guard let start = trip.route.first, let end = trip.route.last else { continue }
            let from = await PlaceNamer.shared.place(for: start)
            let to = await PlaceNamer.shared.place(for: end)
            guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { continue }
            trips[index].from = from?.locality ?? ""
            trips[index].to = to?.locality ?? to?.street ?? ""
        }
    }

    // MARK: Commands

    private func run(_ command: Command, _ work: () async throws -> Void) async {
        guard !pending.contains(command) else { return }
        withAnimation(Motion.snappy) { _ = pending.insert(command) }
        defer { withAnimation(Motion.snappy) { _ = pending.remove(command) } }
        do {
            try await work()
        } catch {
            Haptics.shared.failure()
            show(Notice(icon: .warning, text: error.localizedDescription, tone: .problem))
            // Undo anything shown ahead of the car's answer.
            if hasReading { withAnimation(Motion.fluid) { snapshot = SnapshotStore.load() } }
        }
    }

    func refresh() async {
        guard !isPending(.refresh) else { return }
        let before = snapshot.updatedAt
        var answered = false
        await run(.refresh) {
            #if DEBUG
            // `-refreshDelay 6` keeps the car silent for six seconds, for UI checks.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-refreshDelay"), arguments.indices.contains(index + 1) {
                try await Task.sleep(for: .seconds(Double(arguments[index + 1]) ?? 0))
            }
            #endif
            apply(try await api.wakeUp())
            answered = true
        }
        // The screen plays the answer, and the tap in the hand comes with it.
        if answered, snapshot.updatedAt > before { refreshCue += 1 } else { refreshMisses += 1 }
        if isLive { loadHistory() }
    }

    func setLocked(_ locked: Bool) async {
        await run(.lock) {
            apply(try await api.setLocked(locked))
            lockCue += 1
            if locked { Haptics.shared.lock() } else { Haptics.shared.unlock() }
            show(Notice(icon: locked ? .lock : .unlock, text: locked ? "Locked" : "Unlocked"))
        }
    }

    /// The Climate screen reports the state on its own stage, so it asks for no
    /// banner; anywhere else the banner is the confirmation.
    func setClimate(_ on: Bool, announce: Bool = true) async {
        await run(.climate) {
            apply(try await api.setPreconditioning(on))
            if on { Haptics.shared.climateOn() } else { Haptics.shared.settle() }
            guard announce else { return }
            // A real car answers later; the demo car answers at once.
            let started = isLive ? "Climate start sent" : "Climate on, ready in 10 min"
            show(Notice(icon: .climate, text: on ? started : "Climate off"))
        }
    }

    func setCharging(_ on: Bool) async {
        await run(.charging) {
            apply(try await api.setCharging(on))
            chargeCue += 1
            if on { Haptics.shared.chargeStart() } else { Haptics.shared.chargeStop() }
            show(Notice(icon: on ? .bolt : .pause, text: on ? "Charging to \(snapshot.charging.thresholdPercent)%" : "Charging paused"))
        }
    }

    func setChargeLimit(_ percent: Int) async {
        guard percent != snapshot.charging.thresholdPercent else { return }
        // Show the new limit at once; the car confirms a moment later.
        withAnimation(Motion.release) { snapshot.charging.thresholdPercent = percent }
        await run(.limit) {
            apply(try await api.setChargeThreshold(percent))
            show(Notice(icon: .battery, text: "Limit \(percent)%, about \(snapshot.rangeKm(at: Double(percent))) km"))
        }
    }

    func setSchedule(enabled: Bool, start: TimeOfDay, stop: TimeOfDay?) async {
        withAnimation(Motion.fluid) {
            snapshot.charging.isScheduleEnabled = enabled
            snapshot.charging.startTime = start
            snapshot.charging.stopTime = stop
        }
        await run(.schedule) {
            apply(try await api.setChargeSchedule(enabled: enabled, start: start, stop: stop))
        }
    }

    func setPrograms(_ programs: [ClimateProgram]) async {
        withAnimation(Motion.fluid) { snapshot.climate.programs = programs }
        await run(.programs) {
            apply(try await api.setClimatePrograms(programs))
        }
    }

    // MARK: Timed starts

    func loadWarmUps() async {
        do {
            let list = try await VehicleService.warmUps.load()
            withAnimation(Motion.fluid) {
                warmUps = Self.ordered(list)
                warmUpLink = .ready
            }
        } catch {
            // Keep what is on screen if this was only a refresh that failed.
            if warmUpLink != .ready { warmUpLink = .unavailable(error.localizedDescription) }
        }
    }

    /// Shows the change at once and hands the whole list to the server. If the
    /// server refuses, the list goes back to what it holds.
    func setWarmUps(_ list: [WarmUp]) async {
        let before = warmUps
        withAnimation(Motion.fluid) { warmUps = Self.ordered(list) }
        do {
            let stored = try await VehicleService.warmUps.save(list)
            withAnimation(Motion.fluid) {
                warmUps = Self.ordered(stored)
                warmUpLink = .ready
            }
        } catch {
            Haptics.shared.failure()
            withAnimation(Motion.fluid) { warmUps = before }
            show(Notice(icon: .warning, text: error.localizedDescription, tone: .problem))
        }
    }

    private static func ordered(_ list: [WarmUp]) -> [WarmUp] {
        list.sorted { ($0.hour, $0.minute, $0.id) < ($1.hour, $1.minute, $1.id) }
    }

    func flashLights() async {
        await run(.lights) {
            try await api.flashLights(seconds: 10)
            lightFlashes += 1
            Haptics.shared.flash()
            show(Notice(icon: .headlight, text: "Lights flashing"))
        }
    }

    func honk() async {
        await run(.horn) {
            try await api.honk(count: 2)
            Haptics.shared.honk()
            show(Notice(icon: .horn, text: "Honked twice"))
        }
    }

    // MARK: Demo controls

    func setPlugged(_ plugged: Bool) async {
        guard let demo = api as? MockVehicleAPI else { return }
        apply(await demo.setPlugged(plugged))
        Haptics.shared.settle()
    }

    func setPowertrain(_ powertrain: Powertrain) {
        guard let demo = api as? MockVehicleAPI else { return }
        apply(demo.setPowertrain(powertrain))
    }

    func resetDemo() {
        guard !isLive else { return }
        SnapshotStore.reset()
        apply(SnapshotStore.load())
    }

    // MARK: Notices

    func show(_ notice: Notice) {
        noticeTask?.cancel()
        withAnimation(Motion.release) { self.notice = notice }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.fluid) { self?.notice = nil }
        }
    }

    // MARK: Derived

    var lastTrip: Trip? { trips.first }
}

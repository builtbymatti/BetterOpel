import MapKit
import SwiftUI

struct HomeView: View {
    @Environment(VehicleModel.self) private var model
    @Binding var tab: AppTab
    var openSettings: () -> Void

    @State private var isScrolled = false

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                VStack(spacing: 0) {
                    HeroStage(
                        safeTop: outer.safeAreaInsets.top,
                        width: outer.size.width,
                        openSettings: openSettings
                    )
                    .lensWave(cornerRadius: Self.displayCornerRadius(safeTop: outer.safeAreaInsets.top))

                    VStack(spacing: 28) {
                        EnergySummary()
                        QuickActions(tab: $tab)
                    }
                    .padding(.horizontal, 20)

                    VStack(spacing: 14) {
                        LocationPanel()
                        if let trip = model.lastTrip {
                            LastTripPanel(trip: trip) { tab = .trips }
                        }
                        VehicleFacts()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 34)
                    .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            // The lens is the progress, so the pull lets go at once instead of
            // holding the page down under a spinner.
            .refreshable { Task { await model.refresh() } }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 4
            } action: { _, scrolled in
                isScrolled = scrolled
            }
        }
        // At rest the stage already ends in the page colour, and the refresh
        // lens plays along that top edge.
        .statusBarFade(isActive: isScrolled)
        .background(Palette.canvas.ignoresSafeArea())
        #if DEBUG
        // `-autoRefresh 3` asks the car three seconds after launch, for UI checks.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-autoRefresh"), arguments.indices.contains(index + 1) else { return }
            try? await Task.sleep(for: .seconds(Double(arguments[index + 1]) ?? 3))
            await model.refresh()
        }
        #endif
    }

    /// The system does not publish the display's corner radius; the height of
    /// the top inset tells the families apart well enough for the lens.
    private static func displayCornerRadius(safeTop: CGFloat) -> CGFloat {
        switch safeTop {
        case 59...: 62
        case 50..<59: 55
        case 44..<50: 47
        default: 0
        }
    }
}

// MARK: Energy

private struct EnergySummary: View {
    @Environment(VehicleModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(snapshot.batteryPercent)")
                        .font(.display(32, .semibold, relativeTo: .title))
                        .contentTransition(.numericText(value: Double(snapshot.batteryPercent)))
                    Text("%")
                        .font(.display(17, .medium, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                }
                .foregroundStyle(Palette.ink)

                // At large text sizes the detail gives way rather than truncating.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        Text(detail(for: snapshot))
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSoft)
                            .contentTransition(.numericText())
                            .fixedSize()
                        Spacer(minLength: 8)
                    }
                    Spacer(minLength: 0)
                }

                Text("Limit \(snapshot.charging.thresholdPercent)%")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText(value: Double(snapshot.charging.thresholdPercent)))
            }
            .lineLimit(1)

            BatteryLine(
                level: snapshot.batteryLevel,
                limit: snapshot.charging.thresholdPercent,
                isCharging: snapshot.isCharging
            )

            RefreshStamp()
                .padding(.top, 2)
        }
        .animation(Motion.fluid, value: snapshot.batteryPercent)
    }

    private func detail(for snapshot: VehicleSnapshot) -> String {
        switch snapshot.charging.status {
        case .inProgress: "charging at \(Format.kWh(snapshot.charging.powerKW)) kW"
        case .finished: "charged"
        case .scheduled: "starts \(snapshot.charging.startTime.label)"
        case .stopped: "paused"
        case .disconnected: "battery"
        }
    }
}

/// How old the reading is, and a way to ask for a newer one.
private struct RefreshStamp: View {
    @Environment(VehicleModel.self) private var model

    var body: some View {
        let reported = model.snapshot.updatedAt
        let isRefreshing = model.isPending(.refresh)
        Button {
            Task { await model.refresh() }
        } label: {
            // Re-evaluated every half minute so "2 min ago" stays true.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 6) {
                    Text(text(reported: reported, now: context.date, isRefreshing: isRefreshing))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    Text(isRefreshing ? "" : "Refresh")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(minHeight: 28)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.pressable(scale: 0.99))
        .disabled(isRefreshing || !model.hasReading && !model.isLive)
        .animation(Motion.snappy, value: isRefreshing)
        .accessibilityLabel(isRefreshing ? "Asking the car" : "Car reported \(Format.ago(reported)). Refresh.")
    }

    private func text(reported: Date, now: Date, isRefreshing: Bool) -> String {
        if isRefreshing { return "Asking the car" }
        guard model.hasReading else { return "No reading yet" }
        let ago = Format.ago(reported, now: now)
        // Past a day, the time of day alone would mislead.
        if now.timeIntervalSince(reported) > 20 * 3600 {
            return "Car reported \(reported.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        return "Car reported \(ago), \(Format.clock(reported))"
    }
}

// MARK: Quick actions

private struct QuickActions: View {
    @Environment(VehicleModel.self) private var model
    @Binding var tab: AppTab

    var body: some View {
        let snapshot = model.snapshot
        HStack(alignment: .top, spacing: 0) {
            ActionOrb(
                title: snapshot.isLocked ? "Locked" : "Unlocked",
                isActive: !snapshot.isLocked,
                isBusy: model.isPending(.lock),
                // Locking is always safe; unlocking asks for a deliberate hold.
                holdDuration: snapshot.isLocked ? 0.65 : nil
            ) {
                Task { await model.setLocked(!snapshot.isLocked) }
            } glyph: {
                // The shackle swings rather than swapping one picture for another.
                LockGlyph(open: snapshot.isLocked ? 0 : 1)
                    .animation(Motion.release, value: snapshot.isLocked)
            }

            ActionOrb(
                title: climateTitle(snapshot),
                isActive: snapshot.climate.isOn,
                isBusy: model.isPending(.climate)
            ) {
                Task { await model.setClimate(!snapshot.climate.isOn) }
            } glyph: {
                SpinningFan(isOn: snapshot.climate.isOn)
            }

            ActionOrb(
                title: chargeTitle(snapshot),
                isActive: snapshot.isCharging,
                isBusy: model.isPending(.charging)
            ) {
                if snapshot.charging.status.isPlugged {
                    Task { await model.setCharging(!snapshot.isCharging) }
                } else {
                    tab = .charge
                }
            } glyph: {
                IconView(.bolt, size: 26)
                    .opacity(snapshot.charging.status.isPlugged ? 1 : 0.4)
            }

            ActionOrb(
                title: "Flash",
                isBusy: model.isPending(.lights)
            ) {
                Task { await model.flashLights() }
            } glyph: {
                IconView(.headlight, size: 26)
            }
        }
    }

    private func climateTitle(_ snapshot: VehicleSnapshot) -> String {
        guard snapshot.climate.isOn, let left = snapshot.climateMinutesRemaining else { return "Climate" }
        if model.isAwaiting(.climate) { return "Waking car" }
        return "\(max(1, Int(left.rounded(.up)))) min left"
    }

    private func chargeTitle(_ snapshot: VehicleSnapshot) -> String {
        switch snapshot.charging.status {
        case .inProgress: "Charging"
        case .disconnected: "Unplugged"
        case .finished: "Charged"
        case .stopped, .scheduled: "Charge"
        }
    }
}

// MARK: Panels

private struct LocationPanel: View {
    @Environment(VehicleModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 16) {
            Map(
                position: .constant(.camera(MapCamera(centerCoordinate: snapshot.location.location, distance: 1100))),
                interactionModes: []
            ) {
                Annotation(snapshot.name, coordinate: snapshot.location.location, anchor: .center) {
                    CarPin(heading: snapshot.heading ?? 0)
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 168)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.address.isEmpty ? "Parked" : snapshot.address)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text(snapshot.locality.isEmpty ? Format.ago(snapshot.parkedAt) : "\(snapshot.locality) · \(Format.ago(snapshot.parkedAt))")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await model.honk() }
                } label: {
                    IconView(.horn, size: 21)
                }
                .accessibilityLabel("Honk horn")
                Button {
                    openDirections(to: snapshot)
                } label: {
                    IconView(.navigate, size: 21)
                }
                .accessibilityLabel("Directions to the car")
            }
            .buttonStyle(RoundButtonStyle())
        }
        .padding(10)
        .padding(.bottom, 4)
        .background(PanelBackground(radius: 30))
    }

    private func openDirections(to snapshot: VehicleSnapshot) {
        let location = CLLocation(latitude: snapshot.location.latitude, longitude: snapshot.location.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = snapshot.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

/// Map marker: the car itself, seen from above and pointed the way it faces.
struct CarPin: View {
    /// Compass heading in degrees, 0 = north.
    var heading: Double = 0

    var body: some View {
        Image("CarTop")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 46)
            .rotationEffect(.degrees(heading))
            .shadow(color: .black.opacity(0.4), radius: 3, x: 2, y: 3)
            .accessibilityHidden(true)
    }
}

private struct LastTripPanel: View {
    let trip: Trip
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                RouteGlyph(route: trip.route)
                    .frame(width: 64, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Last drive, \(Format.ago(trip.end))")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                    Text("\(Format.km(trip.distanceKm)) km · \(Format.kWh(trip.consumption)) kWh/100 km")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
                IconView(.arrowOut, size: 15)
                    .foregroundStyle(Palette.inkFaint)
            }
            .panel()
        }
        .buttonStyle(.pressable(scale: 0.98))
    }
}

private struct VehicleFacts: View {
    @Environment(VehicleModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Readout(value: snapshot.odometerKm.formatted(.number.precision(.fractionLength(0))), unit: "km", caption: "Odometer", size: 22)
                // A car that doesn't report a value keeps the slot, so the row stays aligned.
                Readout(value: snapshot.healthPercent.map { "\(Int($0.rounded()))" } ?? "–", unit: snapshot.healthPercent == nil ? nil : "%", caption: "Battery health", size: 22)
                Readout(value: snapshot.outsideTempC.map { "\(Int($0.rounded()))" } ?? "–", unit: snapshot.outsideTempC == nil ? nil : "°C", caption: "Outside", size: 22)
            }
            if snapshot.powertrain == .plugInHybrid {
                HStack(alignment: .top, spacing: 12) {
                    Readout(value: "\(Int(snapshot.fuelLevel))", unit: "%", caption: "Fuel", size: 22)
                    Readout(value: "\(Int(snapshot.fuelRangeKm))", unit: "km", caption: "Fuel range", size: 22)
                    Readout(value: "\(snapshot.rangeKm + Int(snapshot.fuelRangeKm))", unit: "km", caption: "Combined", size: 22)
                }
            }
            Text("\(snapshot.model) · updated \(Format.clock(snapshot.updatedAt)) · \(model.isLive ? "live" : "demo data")")
                .font(.footnote)
                .foregroundStyle(Palette.inkFaint)
        }
        .panel()
    }
}

/// The climate glyph turns while the air is running, and stops where it is.
struct SpinningFan: View {
    var isOn: Bool
    var size: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isOn || reduceMotion)) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            IconView(.climate, size: size)
                .rotationEffect(.degrees(isOn && !reduceMotion ? turns * 360 : 0))
        }
    }
}

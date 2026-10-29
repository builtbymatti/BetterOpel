import SwiftUI

struct ChargeView: View {
    @Environment(VehicleModel.self) private var model
    @State private var previewLimit: Int?
    @State private var scheduleStart = TimeOfDay(hour: 22, minute: 30)
    @State private var scheduleStop = TimeOfDay(hour: 6, minute: 0)
    @State private var selectedSession: ChargingSession?

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                levelHeader(snapshot)
                    .padding(.top, 8)

                BatterySlab(
                    level: snapshot.batteryLevel,
                    limit: snapshot.charging.thresholdPercent,
                    isCharging: snapshot.isCharging,
                    rippleTrigger: model.chargeCue,
                    onPreview: { previewLimit = $0 },
                    onCommit: { percent in Task { await model.setChargeLimit(percent) } }
                )
                .padding(.top, 6)

                limitCaption(snapshot)
                    .padding(.top, 12)

                primaryAction(snapshot)
                    .padding(.top, 22)

                if snapshot.isCharging {
                    HStack(alignment: .top, spacing: 12) {
                        Readout(value: Format.kWh(snapshot.charging.powerKW), unit: "kW", caption: "Power")
                        Readout(value: "+" + Format.kWh(snapshot.sessionEnergyKWh), unit: "kWh", caption: "This session")
                        Readout(value: "+\(snapshot.chargeRateKmPerHour)", unit: "km/h", caption: "Range gain")
                    }
                    .padding(.top, 26)
                    .padding(.horizontal, 4)
                    .transition(.blurReplace)
                }

                schedule(snapshot)
                    .padding(.top, 30)

                sessions
                    .padding(.top, 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .background(Palette.canvas.ignoresSafeArea())
        .onAppear { syncSchedule(with: snapshot) }
        .onChange(of: snapshot.charging.startTime) { syncSchedule(with: model.snapshot) }
        .sheet(item: $selectedSession) { session in
            SessionDetail(session: session, tariff: model.tariff)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selectedSession)
    }

    // MARK: Level

    private func levelHeader(_ snapshot: VehicleSnapshot) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.batteryPercent)")
                    .font(.displayFixed(104, .bold))
                    .kerning(1.5)
                    .contentTransition(.numericText(value: Double(snapshot.batteryPercent)))
                Text("%")
                    .font(.displayFixed(34, .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .foregroundStyle(Palette.ink)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(snapshot.chargeTitle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(stateDetail(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 10)
        }
        .animation(Motion.fluid, value: snapshot.batteryPercent)
        .accessibilityElement(children: .combine)
    }

    private func stateDetail(_ snapshot: VehicleSnapshot) -> String {
        switch snapshot.charging.status {
        case .inProgress:
            if let minutes = snapshot.minutesToLimit { return "\(Format.duration(minutes: minutes)) to \(snapshot.charging.thresholdPercent)%" }
            return "\(snapshot.rangeKm) km"
        case .finished, .stopped, .scheduled, .disconnected:
            return "\(snapshot.rangeKm) km of range"
        }
    }

    private func limitCaption(_ snapshot: VehicleSnapshot) -> some View {
        let limit = previewLimit ?? snapshot.charging.thresholdPercent
        let summary = Text("Limit \(limit)%, about \(snapshot.rangeKm(at: Double(limit))) km")
            .contentTransition(.numericText(value: Double(limit)))
        let advice = Text(limit > 80 ? "Above 80% for long trips" : "Kind to the battery")
            .foregroundStyle(Palette.inkFaint)
            .contentTransition(.opacity)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                summary.fixedSize()
                Spacer(minLength: 12)
                advice.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                summary
                advice
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(Palette.inkSoft)
        .animation(Motion.snappy, value: limit)
    }

    // MARK: Action

    @ViewBuilder
    private func primaryAction(_ snapshot: VehicleSnapshot) -> some View {
        let plugged = snapshot.charging.status.isPlugged
        let charging = snapshot.isCharging
        let atLimit = snapshot.charging.status == .finished
        let busy = model.isPending(.charging)
        let isQuiet = charging || !plugged || atLimit

        Button {
            Task { await model.setCharging(!charging) }
        } label: {
            HStack(spacing: 10) {
                if busy {
                    Spinner()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    IconView(charging ? .pause : .bolt, size: 19)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(actionTitle(plugged: plugged, charging: charging, atLimit: atLimit))
                    .contentTransition(.interpolate)
            }
        }
        .buttonStyle(.brand(isQuiet ? .quiet : .primary))
        .disabled(!plugged || atLimit || busy)
        .opacity(!plugged || atLimit ? 0.6 : 1)
        .animation(Motion.snappy, value: charging)
        .animation(Motion.snappy, value: busy)
    }

    private func actionTitle(plugged: Bool, charging: Bool, atLimit: Bool) -> String {
        if !plugged { return "Plug in to charge" }
        if atLimit { return "At the limit" }
        return charging ? "Pause charging" : "Charge now"
    }

    // MARK: Schedule

    private func schedule(_ snapshot: VehicleSnapshot) -> some View {
        let enabled = snapshot.charging.isScheduleEnabled
        return VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: Binding(
                get: { enabled },
                set: { newValue in
                    Task { await model.setSchedule(enabled: newValue, start: scheduleStart, stop: scheduleStop) }
                }
            )) {
                Text("Charge overnight")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
            }
            .toggleStyle(.brand)

            ScheduleStrip(
                start: $scheduleStart,
                stop: $scheduleStop,
                isEnabled: enabled,
                tariff: model.tariff
            ) {
                Task { await model.setSchedule(enabled: enabled, start: scheduleStart, stop: scheduleStop) }
            }

            Text(scheduleSummary(snapshot, enabled: enabled))
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.numericText())
                .animation(Motion.snappy, value: scheduleStart)
                .animation(Motion.snappy, value: scheduleStop)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panel()
    }

    private func syncSchedule(with snapshot: VehicleSnapshot) {
        scheduleStart = snapshot.charging.startTime
        scheduleStop = snapshot.charging.stopTime ?? TimeOfDay(hour: 6, minute: 0)
    }

    private func scheduleSummary(_ snapshot: VehicleSnapshot, enabled: Bool) -> String {
        guard enabled else { return "Off. The car charges as soon as it is plugged in." }
        let length = ((scheduleStop.minutes - scheduleStart.minutes) + 1440) % 1440
        let hours = Double(length) / 60
        let needed = max(0, Double(snapshot.charging.thresholdPercent) - snapshot.batteryLevel) / 100 * snapshot.batteryCapacityKWh
        let available = hours * snapshot.onboardChargerKW
        let energy = min(needed, available)
        let price = model.tariff.isNight(scheduleStart) ? model.tariff.nightPrice : model.tariff.dayPrice
        let cost = Format.money(energy * price, code: model.tariff.currencyCode)
        if needed < 0.5 {
            return "\(Format.duration(minutes: length)) window. Already at the limit."
        }
        if available >= needed {
            let done = TimeOfDay(minutes: scheduleStart.minutes + Int(needed / snapshot.onboardChargerKW * 60))
            return "Reaches \(snapshot.charging.thresholdPercent)% around \(done.label), about \(cost)."
        }
        let reached = Int(snapshot.batteryLevel + available / snapshot.batteryCapacityKWh * 100)
        return "Gets to about \(reached)% by \(scheduleStop.label), about \(cost). Widen the window to reach the limit."
    }

    // MARK: Sessions

    private var sessions: some View {
        let month = model.sessions.filter { $0.start > Date.now.addingTimeInterval(-30 * 86_400) }
        let energy = month.reduce(0) { $0 + $1.energyKWh }
        let cost = month.reduce(0) { $0 + ($1.cost ?? 0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("30 days: \(Format.kWh(energy)) kWh, \(Format.money(cost, code: model.tariff.currencyCode))")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(model.sessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        SessionRow(session: session, currency: model.tariff.currencyCode)
                    }
                    .buttonStyle(.pressable(scale: 0.985))
                    if session.id != model.sessions.last?.id {
                        RowDivider()
                    }
                }
            }
            .background(PanelBackground())
        }
    }
}

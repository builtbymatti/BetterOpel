import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(VehicleModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(ChargingLiveActivity.enabledKey) private var liveActivityEnabled = true

    private enum Page: Hashable { case widgets, shortcuts }

    var body: some View {
        @Bindable var model = model
        let snapshot = model.snapshot

        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings", onClose: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        carSummary(snapshot)

                        SettingsSection("Colour", footer: "Dresses the whole app, the widgets and the Live Activity. Volt is Opel's yellow; the others follow Grandland paint.") {
                            ThemePicker(selection: $model.theme)
                                .padding(16)
                        }

                        ConnectionSection()

                        if !model.isLive {
                            SettingsSection("Demo car", footer: "The demo car charges forty times faster than a real one so you can watch a session finish.") {
                                SettingsRow("Cable plugged in") {
                                    BrandSwitch(isOn: Binding(
                                        get: { snapshot.charging.status.isPlugged },
                                        set: { plugged in Task { await model.setPlugged(plugged) } }
                                    ))
                                }
                                RowDivider()
                                SettingsRow("Powertrain") {
                                    BrandSegmented(
                                        options: Powertrain.allCases,
                                        title: { $0 == .electric ? "Electric" : "Hybrid" },
                                        selection: Binding(get: { snapshot.powertrain }, set: { model.setPowertrain($0) })
                                    )
                                    .frame(width: 176)
                                }
                                RowDivider()
                                Button {
                                    Haptics.shared.settle()
                                    model.resetDemo()
                                } label: {
                                    Text("Restart the demo")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Palette.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .frame(height: 54)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.pressable(scale: 0.985))
                            }
                        }

                        SettingsSection("Electricity", footer: "Used to estimate what a charge or a drive costs.") {
                            SettingsRow("Day rate") {
                                BrandStepper(value: $model.tariff.dayPrice, code: model.tariff.currencyCode)
                            }
                            RowDivider()
                            SettingsRow("Night rate") {
                                BrandStepper(value: $model.tariff.nightPrice, code: model.tariff.currencyCode)
                            }
                            RowDivider()
                            SettingsRow("Night starts") {
                                DatePicker("Night starts", selection: time($model.tariff.nightStart), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            RowDivider()
                            SettingsRow("Night ends") {
                                DatePicker("Night ends", selection: time($model.tariff.nightEnd), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                        }

                        SettingsSection("Feedback") {
                            SettingsRow("Haptics") {
                                BrandSwitch(isOn: $hapticsEnabled)
                            }
                            RowDivider()
                            SettingsRow("Live Activity while charging") {
                                BrandSwitch(isOn: $liveActivityEnabled)
                            }
                        }

                        SettingsSection("Beyond the app") {
                            NavigationLink(value: Page.widgets) {
                                linkRow("Widgets and Live Activity")
                            }
                            .buttonStyle(.pressable(scale: 0.985))
                            RowDivider()
                            NavigationLink(value: Page.shortcuts) {
                                linkRow("Siri and Shortcuts")
                            }
                            .buttonStyle(.pressable(scale: 0.985))
                        }

                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"). Built for my personal use. An independent project, not associated with, endorsed by, or affiliated with Opel Automobile GmbH or Stellantis. Opel and the Blitz are trademarks of their owner.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .widgets: WidgetGuide()
                case .shortcuts: ShortcutsGuide()
                }
            }
            // A new colourway rebuilds the sheet's content in place.
            .id(model.theme)
            .transition(.opacity)
        }
        .tint(Palette.accent)
        .onChange(of: hapticsEnabled) { _, enabled in
            if enabled { Haptics.shared.success() }
        }
        .onChange(of: liveActivityEnabled) {
            Task { await ChargingLiveActivity.sync(with: model.snapshot) }
        }
    }

    private func carSummary(_ snapshot: VehicleSnapshot) -> some View {
        HStack(spacing: 16) {
            CarRender()
                .frame(width: 118)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.model)
                    .font(.display(19, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text(summaryLine(snapshot))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func summaryLine(_ snapshot: VehicleSnapshot) -> String {
        var parts = ["\(snapshot.odometerKm.formatted(.number.precision(.fractionLength(0)))) km"]
        if let health = snapshot.healthPercent { parts.append("battery health \(Int(health.rounded()))%") }
        return parts.joined(separator: " · ")
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer()
            IconView(.arrowOut, size: 15)
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .contentShape(.rect)
    }

    private func time(_ binding: Binding<TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: binding.wrappedValue.hour, minute: binding.wrappedValue.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                binding.wrappedValue = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}

// MARK: Connection

/// Server address in, real car out. Connecting asks the server which cars it
/// knows, so the VIN rarely needs typing.
private struct ConnectionSection: View {
    @Environment(VehicleModel.self) private var model

    @State private var server = ConnectionStore.server
    @State private var vin = ConnectionStore.vin
    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        SettingsSection("Connection", footer: footer) {
            SettingsRow("Server") {
                TextField("mac-mini.example.ts.net", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .multilineTextAlignment(.trailing)
                    .disabled(model.isLive)
                    .foregroundStyle(model.isLive ? Palette.inkSoft : Palette.ink)
            }
            RowDivider()
            SettingsRow("VIN") {
                TextField("found automatically", text: $vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .disabled(model.isLive)
                    .foregroundStyle(model.isLive ? Palette.inkSoft : Palette.ink)
            }
            RowDivider()
            Button {
                if model.isLive { disconnect() } else { Task { await connect() } }
            } label: {
                HStack(spacing: 10) {
                    if isWorking { Spinner(size: 15) }
                    Text(model.isLive ? "Disconnect and use the demo car" : (isWorking ? "Connecting" : "Connect"))
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 20)
                .frame(height: 54)
                .contentShape(.rect)
            }
            .buttonStyle(.pressable(scale: 0.985))
            .disabled(isWorking || (!model.isLive && server.trimmingCharacters(in: .whitespaces).isEmpty))
            .opacity(!model.isLive && server.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
        }
        .animation(Motion.snappy, value: isWorking)
        .animation(Motion.snappy, value: problem)
    }

    private var footer: String {
        if let problem { return problem }
        if model.isLive {
            switch model.link {
            case .offline(let reason): return "\(reason) Showing the last reading from \(model.snapshot.model)."
            default: return "Connected to \(model.snapshot.model) through your psa_car_controller server."
            }
        }
        return "The address of your psa_car_controller server. Until you connect, everything you see is the demo car."
    }

    private func connect() async {
        problem = nil
        guard let url = ConnectionStore.url(from: server) else {
            problem = "That doesn't look like a server address."
            Haptics.shared.failure()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let cars = try await PSACCClient.discover(at: url)
            let wanted = vin.trimmingCharacters(in: .whitespaces).uppercased()
            guard let pick = cars.first(where: { $0.vin == wanted }) ?? cars.first else {
                throw VehicleError.server("The server is running, but its MyOpel account has no car.")
            }
            ConnectionStore.server = server
            ConnectionStore.vin = pick.vin
            ConnectionStore.car = pick.car
            vin = pick.vin
            model.reconnect()
            Haptics.shared.success()
        } catch {
            problem = error.localizedDescription
            Haptics.shared.failure()
        }
    }

    private func disconnect() {
        ConnectionStore.disconnect()
        problem = nil
        model.reconnect()
        Haptics.shared.settle()
    }
}

// MARK: Colourway picker

/// Three swatches, each cut on the bolt's diagonal: the accent on one side, the
/// ground it sits on at night on the other.
private struct ThemePicker: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                let isSelected = selection == theme
                Button {
                    guard !isSelected else { return }
                    Haptics.shared.detent()
                    withAnimation(.easeInOut(duration: 0.3)) { selection = theme }
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        swatch(theme, isSelected: isSelected)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(theme.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.ink)
                            Text(theme.note)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSoft)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable(scale: 0.96))
                .accessibilityLabel("\(theme.title), \(theme.note)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func swatch(_ theme: AppTheme, isSelected: Bool) -> some View {
        let tokens = theme.tokens
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(Color(uiColor: UIColor(hex: tokens.canvas.dark)))
            .overlay {
                DiagonalHalf()
                    .fill(Color(uiColor: UIColor(hex: tokens.fill.dark)))
            }
            .clipShape(shape)
            .frame(height: 74)
            .overlay(alignment: .topLeading) {
                if isSelected {
                    IconView(.check, size: 18)
                        .foregroundStyle(Color(uiColor: UIColor(hex: tokens.onFill.dark)))
                        .padding(11)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(4)
            .overlay {
                // The chosen swatch stands in a ring of the page's ink.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(isSelected ? 1 : 0), lineWidth: 2.5)
            }
    }
}

/// The left part of a rectangle, ending on the Blitz's slant.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Building blocks

/// Title, back and close for a sheet, in place of the system bar.
struct ScreenHeader: View {
    var title: String
    var onBack: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    IconView(.back, size: 19)
                }
                .buttonStyle(RoundButtonStyle())
                .accessibilityLabel("Back")
            }
            Text(title)
                .font(.display(24, .semibold, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if let onClose {
                Button(action: onClose) {
                    IconView(.close, size: 17)
                }
                .buttonStyle(RoundButtonStyle())
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(PanelBackground(radius: 26))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: () -> Control

    init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }
}

/// Price with a minus and a plus, one cent a step.
private struct BrandStepper: View {
    @Binding var value: Double
    var code: String

    var body: some View {
        HStack(spacing: 10) {
            Text(Format.money(value, code: code))
                .font(.display(17, .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: value))
                .animation(Motion.snappy, value: value)
                .fixedSize()
            step(.minus, by: -0.01, label: "Lower")
            step(.plus, by: 0.01, label: "Raise")
        }
    }

    private func step(_ icon: OpelIcon, by delta: Double, label: String) -> some View {
        Button {
            let next = ((value + delta) * 100).rounded() / 100
            guard (0.05...1.5).contains(next) else { return }
            Haptics.shared.tick()
            value = next
        } label: {
            IconView(icon, size: 15)
        }
        .buttonStyle(RoundButtonStyle(diameter: 36))
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

/// Two or three choices in one capsule, with a marker that slides.
struct BrandSegmented<Option: Hashable>: View {
    var options: [Option]
    var title: (Option) -> String
    @Binding var selection: Option

    @Namespace private var marker

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    guard !isSelected else { return }
                    Haptics.shared.tick()
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? Palette.canvas : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Palette.ink)
                                    .matchedGeometryEffect(id: "marker", in: marker)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.well, in: .capsule)
    }
}

// MARK: Siri and Shortcuts

/// What you can say, and what the Shortcuts app can automate.
struct ShortcutsGuide: View {
    @Environment(\.dismiss) private var dismiss

    private struct Phrase: Identifiable {
        var icon: OpelIcon
        var say: String
        var note: String
        var id: String { say }
    }

    private let phrases = [
        Phrase(icon: .lock, say: "Lock my Opel", note: "Locks the doors."),
        Phrase(icon: .climate, say: "Warm up my Opel", note: "Starts a ten-minute climate cycle."),
        Phrase(icon: .bolt, say: "Start charging my Opel", note: "Charges now, ignoring the schedule."),
        Phrase(icon: .battery, say: "How much charge has my Opel", note: "Battery and range, spoken or as a number for automations."),
        Phrase(icon: .headlight, say: "Flash my Opel", note: "Lights for ten seconds, to find it in a car park."),
        Phrase(icon: .car, say: "Opel status", note: "A card with range, battery and lock state."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Siri and Shortcuts", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsSection("Say to Siri") {
                        ForEach(phrases) { phrase in
                            HStack(spacing: 16) {
                                IconView(phrase.icon, size: 22)
                                    .foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phrase.say)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                    Text(phrase.note)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 13)
                            .accessibilityElement(children: .combine)
                            if phrase.id != phrases.last?.id {
                                RowDivider(leading: 58)
                            }
                        }
                    }

                    Text("In Shortcuts, combine these with automations: start the climate when your morning alarm stops, set the limit to 100% the night before a long drive, or get a nudge if the car is still unlocked at 22:00. Unlocking always asks for Face ID.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

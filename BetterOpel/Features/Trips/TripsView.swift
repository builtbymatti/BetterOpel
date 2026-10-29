import Charts
import SwiftUI

struct TripsView: View {
    @Environment(VehicleModel.self) private var model
    @Namespace private var zoom
    @State private var selectedDay: Date?
    @State private var lastTickedDay: Date?

    private struct DayTotal: Identifiable, Equatable {
        var day: Date
        var km: Double
        var kWh: Double
        var id: Date { day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let days = dayTotals
                    let focus = focusTotals(days)

                    header(focus)
                        .padding(.top, 8)

                    chart(days)
                        .padding(.top, 14)

                    HStack(alignment: .top, spacing: 12) {
                        Readout(value: Format.kWh(focus.kWh), unit: "kWh", caption: "Energy")
                        Readout(value: Format.money(focus.kWh * model.tariff.nightPrice, code: model.tariff.currencyCode), caption: "At home rates")
                        Readout(value: Format.clockDuration(minutes: focus.minutes), unit: focus.minutes >= 60 ? "h" : "min", caption: "At the wheel")
                    }
                    .padding(.top, 26)
                    .padding(.horizontal, 4)

                    tripList
                        .padding(.top, 30)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .navBarClearance()
            .statusBarFade()
            .background(Palette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Trip.self) { trip in
                TripDetail(trip: trip, average: averageConsumption)
                    .navigationTransition(.zoom(sourceID: trip.id, in: zoom))
            }
        }
    }

    // MARK: Aggregates

    private var averageConsumption: Double {
        let km = model.trips.reduce(0) { $0 + $1.distanceKm }
        let kWh = model.trips.reduce(0) { $0 + $1.energyKWh }
        return km > 0 ? kWh / km * 100 : 0
    }

    private var dayTotals: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let trips = model.trips.filter { calendar.isDate($0.start, inSameDayAs: day) }
            return DayTotal(day: day, km: trips.reduce(0) { $0 + $1.distanceKm }, kWh: trips.reduce(0) { $0 + $1.energyKWh })
        }
    }

    private struct Focus {
        var title: String
        var km: Double
        var kWh: Double
        var minutes: Int
        var consumption: Double { km > 0 ? kWh / km * 100 : 0 }
    }

    /// Either the day under the finger or the last seven days.
    private func focusTotals(_ days: [DayTotal]) -> Focus {
        let calendar = Calendar.current
        if let selectedDay, let day = days.first(where: { calendar.isDate($0.day, inSameDayAs: selectedDay) }) {
            let trips = model.trips.filter { calendar.isDate($0.start, inSameDayAs: day.day) }
            return Focus(
                title: day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                km: day.km,
                kWh: day.kWh,
                minutes: Int(trips.reduce(0) { $0 + $1.duration } / 60)
            )
        }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let trips = model.trips.filter { $0.start > weekAgo }
        return Focus(
            title: "Last 7 days",
            km: trips.reduce(0) { $0 + $1.distanceKm },
            kWh: trips.reduce(0) { $0 + $1.energyKWh },
            minutes: Int(trips.reduce(0) { $0 + $1.duration } / 60)
        )
    }

    // MARK: Header

    private func header(_ focus: Focus) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(focus.km.rounded()))")
                    .font(.displayFixed(104, .bold))
                    .kerning(1.5)
                    .contentTransition(.numericText(value: focus.km))
                Text("km")
                    .font(.displayFixed(30, .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(focus.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.interpolate)
                Text(focus.km > 0 ? "\(Format.kWh(focus.consumption)) kWh/100 km" : "no drives")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText(value: focus.consumption))
            }
            .padding(.bottom, 10)
            .layoutPriority(1)
        }
        .animation(Motion.snappy, value: focus.km)
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private func chart(_ days: [DayTotal]) -> some View {
        let calendar = Calendar.current
        return Chart(days) { day in
            let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day.day) } ?? false
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Distance", max(day.km, 1.2)),
                width: .ratio(0.62)
            )
            .clipShape(.rect(cornerRadius: 5, style: .continuous))
            .foregroundStyle(barColor(day: day, isSelected: isSelected))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                    }
                }
                .foregroundStyle(Palette.inkFaint)
            }
        }
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedDay)
        .frame(height: 132)
        .animation(Motion.snappy, value: selectedDay)
        .onChange(of: selectedDay) { _, day in
            let start = day.map { calendar.startOfDay(for: $0) }
            guard start != lastTickedDay else { return }
            lastTickedDay = start
            if start != nil { Haptics.shared.tick() }
        }
        .accessibilityLabel("Distance per day, last two weeks")
    }

    private func barColor(day: DayTotal, isSelected: Bool) -> Color {
        if day.km < 0.5 { return Palette.well }
        if selectedDay == nil { return Palette.ink }
        return isSelected ? Palette.accent : Palette.inkFaint.opacity(0.5)
    }

    // MARK: List

    private var tripList: some View {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: model.trips) { calendar.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 26) {
            ForEach(groups, id: \.key) { day, trips in
                VStack(alignment: .leading, spacing: 10) {
                    Text(dayTitle(day))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip)
                            }
                            .buttonStyle(.pressable(scale: 0.985))
                            .matchedTransitionSource(id: trip.id, in: zoom)
                            if trip.id != trips.last?.id {
                                RowDivider(leading: 84)
                            }
                        }
                    }
                    .background(PanelBackground())
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        // One line when everything fits whole; at large text sizes the figures
        // drop under the place names instead of squeezing them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                glyph
                places(fixed: true)
                Spacer(minLength: 6)
                figures(alignment: .trailing)
            }
            HStack(alignment: .top, spacing: 14) {
                glyph
                VStack(alignment: .leading, spacing: 8) {
                    places(fixed: false)
                    figures(alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var glyph: some View {
        RouteGlyph(route: trip.route)
            .frame(width: 50, height: 46)
    }

    private func places(fixed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.destination)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .contentTransition(.opacity)
            if !trip.from.isEmpty {
                Text("from \(trip.from)")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            Text("\(Format.clock(trip.start)) · \(Format.duration(minutes: Int(trip.duration / 60)))")
                .font(.footnote)
                .foregroundStyle(Palette.inkFaint)
        }
        .lineLimit(fixed ? 1 : 2)
        .fixedSize(horizontal: fixed, vertical: true)
    }

    private func figures(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.km(trip.distanceKm))
                    .font(.display(20, .medium, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text("km")
                    .font(.display(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSoft)
            }
            Text("\(Format.kWh(trip.consumption)) kWh/100")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }
}

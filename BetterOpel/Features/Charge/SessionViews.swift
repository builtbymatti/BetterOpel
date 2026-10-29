import Charts
import SwiftUI

struct SessionRow: View {
    let session: ChargingSession
    var currency: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.place)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    LevelSpan(from: session.startLevel, to: session.endLevel)
                        .frame(width: 78, height: 6)
                    Text("\(session.startLevel) to \(session.endLevel)%")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                Text("\(session.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(session.connector.rawValue) · \(Format.duration(minutes: Int(session.duration / 60)))")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.kWh(session.energyKWh))
                        .font(.display(20, .medium, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("kWh")
                        .font(.display(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSoft)
                }
                Text(session.cost.map { Format.money($0, code: currency) } ?? " ")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Where in the pack a session started and ended.
struct LevelSpan: View {
    var from: Int
    var to: Int

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: max(proxy.size.height, w * CGFloat(to - from) / 100))
                    .offset(x: w * CGFloat(from) / 100)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SessionDetail: View {
    let session: ChargingSession
    var tariff: ElectricityTariff

    @State private var selectedLevel: Double?
    @State private var lastTickLevel = -1

    private var selectedPoint: CurvePoint? {
        guard let selectedLevel else { return nil }
        return session.curve.min { abs($0.level - selectedLevel) < abs($1.level - selectedLevel) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.place)
                        .font(.display(26, .semibold, relativeTo: .title2))
                        .foregroundStyle(Palette.ink)
                    Text("\(session.start.formatted(date: .complete, time: .shortened)), \(session.connector.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                }

                if session.curve.count > 1 {
                    curve
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(session.startLevel) to \(session.endLevel)%")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        LevelSpan(from: session.startLevel, to: session.endLevel)
                            .frame(height: 10)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 22) {
                    GridRow {
                        Readout(value: Format.kWh(session.energyKWh), unit: "kWh", caption: "Energy")
                        Readout(value: session.cost.map { Format.money($0, code: tariff.currencyCode) } ?? "–", caption: "Cost")
                        Readout(value: Format.clockDuration(minutes: Int(session.duration / 60)), unit: session.duration >= 3600 ? "h" : "min", caption: "Duration")
                    }
                    GridRow {
                        if session.curve.isEmpty {
                            // Without a recorded curve, the average is what can be said.
                            Readout(value: Format.kWh(session.averageKW), unit: "kW", caption: "Average power")
                        } else {
                            Readout(value: Format.kWh(session.peakKW), unit: "kW", caption: "Peak power")
                        }
                        Readout(value: session.pricePerKWh.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–", unit: session.pricePerKWh == nil ? nil : "/kWh", caption: "Price")
                        Readout(value: session.gramsCO2PerKWh.map { Format.kWh(Double($0) * session.energyKWh / 1000) } ?? "–", unit: session.gramsCO2PerKWh == nil ? nil : "kg", caption: "Grid CO2")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.canvas.ignoresSafeArea())
    }

    private var curve: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let point = selectedPoint {
                    Text("\(Format.kWh(point.powerKW)) kW at \(Int(point.level))%")
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: point.level))
                } else {
                    Text("Charging power from \(session.startLevel) to \(session.endLevel)%")
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
            }
            .font(.subheadline.weight(.medium))
            .animation(Motion.snappy, value: selectedPoint)

            Chart {
                ForEach(session.curve) { point in
                    AreaMark(x: .value("Level", point.level), y: .value("Power", point.powerKW))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.accent.opacity(0.32), Palette.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Level", point.level), y: .value("Power", point.powerKW))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Level", point.level))
                        .foregroundStyle(Palette.inkFaint)
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))
                    PointMark(x: .value("Level", point.level), y: .value("Power", point.powerKW))
                        .symbolSize(90)
                        .foregroundStyle(Palette.ink)
                }
            }
            .chartXScale(domain: Double(session.startLevel)...Double(session.endLevel))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let level = value.as(Double.self) { Text("\(Int(level))%") }
                    }
                    .foregroundStyle(Palette.inkFaint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Palette.well)
                    AxisValueLabel {
                        if let power = value.as(Double.self) { Text("\(Int(power))") }
                    }
                    .foregroundStyle(Palette.inkFaint)
                }
            }
            .chartXSelection(value: $selectedLevel)
            .frame(height: 190)
            .onChange(of: selectedPoint) { _, point in
                guard let point, Int(point.level) != lastTickLevel else { return }
                lastTickLevel = Int(point.level)
                Haptics.shared.tick()
            }
            .accessibilityLabel("Charging curve")
        }
    }
}

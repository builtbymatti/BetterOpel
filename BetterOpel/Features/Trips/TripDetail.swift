import Charts
import MapKit
import SwiftUI

struct TripDetail: View {
    let trip: Trip
    /// The driver's overall consumption, to put this drive in context.
    var average: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var drawn = 0
    @State private var selectedIndex: Int?
    @State private var lastTick = -1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                map
                    .frame(height: 380)

                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.destination)
                            .font(.display(30, .semibold, relativeTo: .title))
                            .foregroundStyle(Palette.ink)
                        Text("\(trip.from.isEmpty ? "" : "from \(trip.from), ")\(trip.start.formatted(.dateTime.weekday(.wide).day().month(.wide))) at \(Format.clock(trip.start))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSoft)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 22) {
                        GridRow {
                            Readout(value: Format.km(trip.distanceKm), unit: "km", caption: "Distance")
                            Readout(value: Format.clockDuration(minutes: Int(trip.duration / 60)), unit: trip.duration >= 3600 ? "h" : "min", caption: "Duration")
                            Readout(value: "\(Int(trip.averageSpeed.rounded()))", unit: "km/h", caption: "Average")
                        }
                        GridRow {
                            Readout(value: Format.kWh(trip.consumption), unit: "kWh/100", caption: "Consumption")
                            Readout(value: Format.kWh(trip.energyKWh), unit: "kWh", caption: "Energy")
                            if let from = trip.startLevel, let to = trip.endLevel {
                                Readout(value: "\(from)", unit: "to \(to)%", caption: "Battery")
                            } else if let change = trip.altitudeChange {
                                Readout(value: (change >= 0 ? "+" : "") + "\(Int(change.rounded()))", unit: "m", caption: "Height change")
                            } else {
                                Readout(value: "–", caption: "Battery")
                            }
                        }
                    }

                    comparison

                    if trip.elevation.count > 1 {
                        elevation
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 36)
            }
        }
        .scrollIndicators(.hidden)
        .navBarClearance()
        .ignoresSafeArea(edges: .top)
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                IconView(.back, size: 20)
            }
            .buttonStyle(RoundButtonStyle(onImage: true))
            .padding(.leading, 18)
            .padding(.top, 6)
            .accessibilityLabel("Back")
        }
        .task { await drawRoute() }
    }

    // MARK: Map

    private var map: some View {
        let coordinates = trip.route.map(\.location)
        let visible = Array(coordinates.prefix(max(2, drawn)))
        return Map(initialPosition: .region(region(for: coordinates)), interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: visible)
                .stroke(Palette.onFill, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: visible)
                .stroke(Palette.fill, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            if let first = coordinates.first {
                Annotation("Start", coordinate: first, anchor: .center) {
                    Circle()
                        .fill(Palette.onFill)
                        .frame(width: 14, height: 14)
                        .overlay { Circle().fill(Palette.fill).frame(width: 6, height: 6) }
                }
                .annotationTitles(.hidden)
            }
            if let last = visible.last, drawn > 1 {
                Annotation("Car", coordinate: last, anchor: .center) {
                    CarPin(heading: heading(of: visible))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Keeps the Maps attribution above the feathered edge.
        .safeAreaPadding(.bottom, 112)
        // The map resolves into the page instead of ending on a line.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.82), location: 0.8),
                    .init(color: .black.opacity(0.5), location: 0.88),
                    .init(color: .black.opacity(0.18), location: 0.95),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityLabel("Route: \(trip.title)")
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion()
        }
        let latSpan = max(0.01, (maxLat - minLat) * 2.1)
        return MKCoordinateRegion(
            // The bottom inset already lifts the route; this clears the status bar.
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + latSpan * 0.09, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: max(0.01, (maxLon - minLon) * 1.5))
        )
    }

    /// Compass bearing of the last stretch, so the marker points along the road.
    private func heading(of coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        let to = coordinates[coordinates.count - 1]
        let from = coordinates[max(0, coordinates.count - 3)]
        let dLon = (to.longitude - from.longitude) * cos(to.latitude * .pi / 180)
        let dLat = to.latitude - from.latitude
        guard abs(dLon) + abs(dLat) > 0 else { return 0 }
        return atan2(dLon, dLat) * 180 / .pi
    }

    /// The route draws itself from the start, the car riding its tip.
    private func drawRoute() async {
        let total = trip.route.count
        guard !reduceMotion, total > 2 else {
            drawn = total
            return
        }
        try? await Task.sleep(for: .milliseconds(380))
        let steps = 44
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            // Ease out: quick away from the start, settling at the destination.
            let eased = 1 - pow(1 - t, 2.4)
            drawn = max(2, Int((Double(total) * eased).rounded()))
            try? await Task.sleep(for: .milliseconds(22))
        }
        drawn = total
        Haptics.shared.settle()
    }

    // MARK: Comparison

    private var comparison: some View {
        let delta = average > 0 ? (trip.consumption - average) / average : 0
        let better = delta <= 0
        let scale = max(trip.consumption, average) * 1.12
        return VStack(alignment: .leading, spacing: 14) {
            Text(better ? "\(abs(Int((delta * 100).rounded())))% thriftier than your average" : "\(Int((delta * 100).rounded()))% thirstier than your average")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 9) {
                comparisonBar(label: "This drive", value: trip.consumption, scale: scale, color: Palette.ink)
                comparisonBar(label: "Your average", value: average, scale: scale, color: Palette.inkFaint)
            }
            Text((trip.outsideTempC.map { "\(Int($0.rounded())) °C outside. " } ?? "") + "Cold air and motorway speeds cost the most.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
        }
        .panel()
    }

    private func comparisonBar(label: String, value: Double, scale: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 92, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * value / scale)
            }
            .frame(height: 8)
            Text(Format.kWh(value))
                .font(.display(15, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Elevation

    private var elevation: some View {
        let samples = Array(trip.elevation.enumerated())
        let low = (trip.elevation.min() ?? 0) - 12
        let high = (trip.elevation.max() ?? 100) + 12
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Elevation")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Group {
                    if let selectedIndex, trip.elevation.indices.contains(selectedIndex) {
                        let km = trip.distanceKm * Double(selectedIndex) / Double(max(1, trip.elevation.count - 1))
                        Text("\(Int(trip.elevation[selectedIndex])) m at km \(Format.km(km))")
                            .contentTransition(.numericText(value: Double(selectedIndex)))
                    } else {
                        Text("\(Int(trip.climb.rounded())) m climbed")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
            }

            Chart {
                ForEach(samples, id: \.offset) { index, metres in
                    AreaMark(x: .value("Sample", index), yStart: .value("Base", low), yEnd: .value("Elevation", metres))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.ink.opacity(0.22), Palette.ink.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Sample", index), y: .value("Elevation", metres))
                        .foregroundStyle(Palette.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let selectedIndex, trip.elevation.indices.contains(selectedIndex) {
                    RuleMark(x: .value("Sample", selectedIndex))
                        .foregroundStyle(Palette.inkFaint)
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))
                    PointMark(x: .value("Sample", selectedIndex), y: .value("Elevation", trip.elevation[selectedIndex]))
                        .symbolSize(90)
                        .foregroundStyle(Palette.accent)
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Palette.well)
                    AxisValueLabel {
                        if let metres = value.as(Double.self) { Text("\(Int(metres)) m") }
                    }
                    .foregroundStyle(Palette.inkFaint)
                }
            }
            .chartXSelection(value: $selectedIndex)
            .frame(height: 150)
            .onChange(of: selectedIndex) { _, index in
                guard let index, index != lastTick else { return }
                lastTick = index
                Haptics.shared.tick()
            }
            .accessibilityLabel("Elevation profile, \(Int(trip.climb.rounded())) metres climbed")
        }
    }
}

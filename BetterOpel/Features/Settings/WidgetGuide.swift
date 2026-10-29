import SwiftUI
import WidgetKit

/// Shows the real widget views with live data, and how to add them.
struct WidgetGuide: View {
    @Environment(VehicleModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 0) {
            ScreenHeader(title: "Widgets", onBack: { dismiss() })
            content(snapshot)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ snapshot: VehicleSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Touch and hold the Home Screen, tap Edit, then Add Widget and look for BetterOpel.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Home Screen")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    VStack(spacing: 14) {
                        HStack(alignment: .center, spacing: 16) {
                            tile { RangeWidgetView(snapshot: snapshot) }
                                .frame(width: 164, height: 164)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Range")
                                    .font(.headline)
                                    .foregroundStyle(Palette.ink)
                                Text("Range, battery and the charge limit. Counts up by itself while charging.")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        tile { VehicleWidgetView(snapshot: snapshot) }
                            .frame(height: 164)
                        Text("The medium widget locks, starts the climate and starts charging without opening the app.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(Palette.well, in: .rect(cornerRadius: 40, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Lock Screen")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            lockFace(PreheatStatus(), nil)
                            lockFace(PreheatStatus(phase: .waking, at: .now), nil)
                            lockFace(PreheatStatus(phase: .running, at: .now), 7)
                        }
                        PreheatWidgetView(status: PreheatStatus(phase: .waking, at: .now), minutesLeft: nil, shownAs: .accessoryRectangular)
                            .frame(width: 190, height: 44)
                    }
                    .foregroundStyle(ChargingActivityView.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ChargingActivityView.ground, in: .rect(cornerRadius: 26, style: .continuous))
                    // Shown here as pictures; the real ones are on the Lock Screen.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    Text("Preheat starts the climate with one tap and tells you each step in a notification: sending, waking the car, started. Touch and hold the Lock Screen, tap Customise, and add it from BetterOpel.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Live Activity")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    ChargingActivityView(
                        state: ChargingLiveActivity.contentState(for: snapshot, finished: !snapshot.isCharging),
                        vehicleName: snapshot.name
                    )
                    .background(ChargingActivityView.ground, in: .rect(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(ChargingActivityView.ink.opacity(0.1), lineWidth: 1)
                    }
                    Text("Appears on the Lock Screen and in the Dynamic Island while the car charges, with a Pause button.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Control Center and Lock Screen")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    VStack(alignment: .leading, spacing: 0) {
                        row(.lock, "Door Lock", "A toggle for Control Center or the Action button.")
                        divider
                        row(.climate, "Climate", "Start or stop preconditioning.")
                        divider
                        row(.headlight, "Flash Lights", "Find the car in a car park.")
                        divider
                        row(.battery, "Battery", "Circular, rectangular and inline Lock Screen widgets.")
                    }
                    .background(PanelBackground())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private func tile(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas, in: .rect(cornerRadius: 24, style: .continuous))
    }

    /// One round Lock Screen widget, on the disc the system would give it.
    private func lockFace(_ status: PreheatStatus, _ minutesLeft: Int?) -> some View {
        PreheatWidgetView(status: status, minutesLeft: minutesLeft, shownAs: .accessoryCircular)
            .frame(width: 58, height: 58)
            .background(ChargingActivityView.ink.opacity(0.14), in: .circle)
    }

    private var divider: some View {
        RowDivider(leading: 62)
    }

    private func row(_ icon: OpelIcon, _ title: String, _ note: String) -> some View {
        HStack(spacing: 14) {
            IconView(icon, size: 22)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

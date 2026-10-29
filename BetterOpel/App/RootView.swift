import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case car, charge, climate, trips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: "Car"
        case .charge: "Charge"
        case .climate: "Climate"
        case .trips: "Trips"
        }
    }

    var icon: OpelIcon {
        switch self {
        case .car: .car
        case .charge: .bolt
        case .climate: .climate
        case .trips: .route
        }
    }

    /// `-tab charge` on the launch arguments opens a specific tab, for UI checks.
    static var initial: AppTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1),
           let tab = AppTab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return .car
    }
}

struct RootView: View {
    @Environment(VehicleModel.self) private var model
    @State private var tab = AppTab.initial
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $tab) {
            Tab(AppTab.car.title, systemImage: "car", value: AppTab.car) {
                HomeView(tab: $tab, openSettings: { showSettings = true })
                    .clearsNavBar()
            }
            Tab(AppTab.charge.title, systemImage: "bolt", value: AppTab.charge) {
                ChargeView()
                    .clearsNavBar()
            }
            Tab(AppTab.climate.title, systemImage: "fan", value: AppTab.climate) {
                ClimateView()
                    .clearsNavBar()
            }
            Tab(AppTab.trips.title, systemImage: "map", value: AppTab.trips) {
                // Trips keeps the bar clear itself: an inset set out here does
                // not reach the scroll view inside its navigation stack.
                TripsView()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        // Colours are resolved when a view is built, so a new colourway rebuilds
        // the screens. Presentation state stays out here and survives it.
        .id(model.theme)
        .overlay(alignment: .bottom) {
            NavBar(tab: $tab)
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                NoticeBanner(notice: notice)
                    .padding(.bottom, NavBar.height + 22)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))
                        )
                    )
                    .id(notice.id)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .tint(Palette.accent)
        #if DEBUG
        // `-preheat` runs the Lock Screen start once at launch, for checks.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-preheat") else { return }
            let hold = UIApplication.shared.beginBackgroundTask()
            try? await Task.sleep(for: .seconds(4))
            await Preheat.start()
            UIApplication.shared.endBackgroundTask(hold)
        }
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #if DEBUG
        // `-guide widgets`, `-guide shortcuts` or `-guide icons` opens a page
        // directly, for UI checks.
        .sheet(item: $debugGuide) { guide in
            NavigationStack {
                switch guide {
                case .widgets: WidgetGuide()
                case .shortcuts: ShortcutsGuide()
                case .icons: IconSheet()
                case .settings: SettingsView()
                }
            }
        }
        #endif
    }

    #if DEBUG
    private enum DebugGuide: String, Identifiable {
        case widgets, shortcuts, icons, settings
        var id: String { rawValue }
    }

    @State private var debugGuide: DebugGuide? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-guide"), arguments.indices.contains(index + 1) else { return nil }
        return DebugGuide(rawValue: arguments[index + 1])
    }()
    #endif
}

/// The app's own navigation: a solid capsule in the brand's black with the
/// current section picked out in the accent. The marker slides between items.
struct NavBar: View {
    @Binding var tab: AppTab
    @Environment(VehicleModel.self) private var model
    @Namespace private var marker

    static let height: CGFloat = 68
    /// What a screen has to keep free at its bottom edge: the bar and its margins.
    static let clearance: CGFloat = height + 20

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                Button {
                    guard tab != item else { return }
                    Haptics.shared.tick()
                    withAnimation(Motion.snappy) { tab = item }
                } label: {
                    VStack(spacing: 5) {
                        IconView(item.icon, size: 23)
                        Text(label(for: item))
                            .font(.system(size: 11, weight: .bold))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                    }
                    .foregroundStyle(tab == item ? Palette.onFill : Palette.onBar)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.height - 12)
                    .background {
                        if tab == item {
                            Capsule()
                                .fill(Palette.fill)
                                .matchedGeometryEffect(id: "marker", in: marker)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(NavItemStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: Self.height)
        .background(Palette.bar, in: .capsule)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background {
            // Content dissolves into the canvas before it reaches the bar, and
            // stays hidden from there to the bottom edge of the screen.
            LinearGradient(
                stops: [
                    .init(color: Palette.canvas.opacity(0), location: 0),
                    .init(color: Palette.canvas.opacity(0.55), location: 0.16),
                    .init(color: Palette.canvas.opacity(0.9), location: 0.3),
                    .init(color: Palette.canvas, location: 0.42),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -44)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// While a session runs and you are elsewhere, the Charge item carries the level.
    private func label(for item: AppTab) -> String {
        if item == .charge, tab != .charge, model.snapshot.isCharging { return "\(model.snapshot.batteryPercent)%" }
        return item.title
    }
}

extension View {
    /// Hides the system tab bar and ends this screen's content above the app's
    /// own bar, so the last row of a page can always be scrolled into view.
    func clearsNavBar() -> some View {
        self
            .toolbarVisibility(.hidden, for: .tabBar)
            .navBarClearance()
    }

    /// The inset alone, for a scroll view that sits inside a navigation stack.
    func navBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: NavBar.clearance)
        }
    }
}

private struct NavItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
    }
}

#if DEBUG
/// Every icon at working size, for checking the set as a family.
struct IconSheet: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 22) {
                ForEach(OpelIcon.allCases, id: \.self) { icon in
                    VStack(spacing: 8) {
                        IconView(icon, size: 44)
                            .foregroundStyle(Palette.ink)
                        IconView(icon, size: 22)
                            .foregroundStyle(Palette.ink)
                        Text(icon.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .padding(24)
        }
        .background(Palette.canvas.ignoresSafeArea())
    }
}
#endif

import SwiftUI

@main
struct BetterOpelApp: App {
    @State private var model = VehicleModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        Haptics.shared.prepare()
                        model.start()
                        // The Lock Screen start reports its steps as notifications.
                        Task { await PreheatNotice.requestPermission() }
                        model.tick()
                    } else if phase == .background {
                        model.stop()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vehicleSnapshotChanged)) { _ in
                    model.tick()
                }
        }
    }
}

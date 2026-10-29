import AppIntents

/// Phrases that work with Siri and Spotlight the moment the app is installed.
struct BetterOpelShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .yellow

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VehicleStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "How is my \(.applicationName)",
            ],
            shortTitle: "Car Status",
            systemImageName: "car.side.fill"
        )
        AppShortcut(
            intent: LockDoorsIntent(),
            phrases: [
                "Lock my \(.applicationName)",
                "Lock the car with \(.applicationName)",
            ],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockDoorsIntent(),
            phrases: [
                "Unlock my \(.applicationName)",
            ],
            shortTitle: "Unlock",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "Warm up my \(.applicationName)",
                "Start climate in my \(.applicationName)",
                "Precondition my \(.applicationName)",
            ],
            shortTitle: "Start Climate",
            systemImageName: "fan.fill"
        )
        AppShortcut(
            intent: StopClimateIntent(),
            phrases: [
                "Stop climate in my \(.applicationName)",
            ],
            shortTitle: "Stop Climate",
            systemImageName: "fan.slash.fill"
        )
        AppShortcut(
            intent: StartChargingIntent(),
            phrases: [
                "Start charging my \(.applicationName)",
            ],
            shortTitle: "Charge Now",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: StopChargingIntent(),
            phrases: [
                "Stop charging my \(.applicationName)",
            ],
            shortTitle: "Pause Charging",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: BatteryLevelIntent(),
            phrases: [
                "How much charge has my \(.applicationName)",
                "\(.applicationName) battery",
            ],
            shortTitle: "Battery Level",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: FlashLightsIntent(),
            phrases: [
                "Flash my \(.applicationName)",
                "Find my \(.applicationName)",
            ],
            shortTitle: "Flash Lights",
            systemImageName: "headlight.high.beam.fill"
        )
        AppShortcut(
            intent: HonkHornIntent(),
            phrases: [
                "Honk my \(.applicationName)",
            ],
            shortTitle: "Honk",
            systemImageName: "horn.blast.fill"
        )
    }
}

import os
import SwiftUI
import UIKit

/// The app can dress in one of three colourways. Volt is Opel's own yellow; the
/// other two follow Grandland paint finishes. Each brings its accent and a set
/// of neutrals tinted toward it, so the whole surface shifts, not just a button.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case volt
    case copper
    case petrol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volt: "Volt"
        case .copper: "Copper"
        case .petrol: "Petrol"
        }
    }

    var note: String {
        switch self {
        case .volt: "Opel yellow"
        case .copper: "Impact Copper paint"
        case .petrol: "Deep blue-green paint"
        }
    }

    /// A light and a dark value for one role.
    struct Pair: Sendable {
        var light: UInt32
        var dark: UInt32
    }

    struct Tokens: Sendable {
        var canvas: Pair
        var surface: Pair
        var well: Pair
        var wellStrong: Pair
        var ink: Pair
        var inkSoft: Pair
        var inkFaint: Pair
        /// Accent for text and glyphs, tuned to stay readable on the canvas.
        var accent: Pair
        /// Accent as a solid fill: the primary button, the active control, energy.
        var fill: Pair
        var fillDeep: Pair
        /// The brightest part of the fill, used by the energy shader.
        var fillHot: Pair
        /// Text and glyphs on top of the fill.
        var onFill: Pair
        /// The navigation bar's own ground.
        var bar: Pair
        var onBar: Pair
    }

    var tokens: Tokens {
        switch self {
        case .volt:
            Tokens(
                canvas: Pair(light: 0xF1F2EA, dark: 0x090A06),
                surface: Pair(light: 0xFBFCF7, dark: 0x13150E),
                well: Pair(light: 0xE4E6DA, dark: 0x1D2015),
                wellStrong: Pair(light: 0xD3D6C6, dark: 0x2A2E1F),
                ink: Pair(light: 0x10120B, dark: 0xF4F6E8),
                inkSoft: Pair(light: 0x55584A, dark: 0xA9AD9B),
                inkFaint: Pair(light: 0x71746A, dark: 0x82867A),
                accent: Pair(light: 0x4A4F00, dark: 0xF7FF14),
                fill: Pair(light: 0xF7FF14, dark: 0xF7FF14),
                fillDeep: Pair(light: 0xC7D900, dark: 0xC7D900),
                fillHot: Pair(light: 0xFFFFBD, dark: 0xFFFFBD),
                onFill: Pair(light: 0x10120B, dark: 0x10120B),
                bar: Pair(light: 0x10120B, dark: 0x1D2015),
                onBar: Pair(light: 0xC9CCBB, dark: 0xA9AD9B)
            )
        case .copper:
            Tokens(
                canvas: Pair(light: 0xF2EEEA, dark: 0x0B0806),
                surface: Pair(light: 0xFCFAF7, dark: 0x17120E),
                well: Pair(light: 0xE7DFD8, dark: 0x231B15),
                wellStrong: Pair(light: 0xD6CBC1, dark: 0x33271F),
                ink: Pair(light: 0x150F0A, dark: 0xF7EFE8),
                inkSoft: Pair(light: 0x5E5249, dark: 0xB3A69B),
                inkFaint: Pair(light: 0x7A6E65, dark: 0x8C8076),
                accent: Pair(light: 0x91451A, dark: 0xEE9259),
                fill: Pair(light: 0xD97B42, dark: 0xD97B42),
                fillDeep: Pair(light: 0xB25A28, dark: 0xB25A28),
                fillHot: Pair(light: 0xFFD3AC, dark: 0xFFD3AC),
                onFill: Pair(light: 0x140C06, dark: 0x140C06),
                bar: Pair(light: 0x150F0A, dark: 0x231B15),
                onBar: Pair(light: 0xCDC1B7, dark: 0xB3A69B)
            )
        case .petrol:
            Tokens(
                canvas: Pair(light: 0xEBF1F0, dark: 0x050A0A),
                surface: Pair(light: 0xF8FCFB, dark: 0x0D1516),
                well: Pair(light: 0xDAE5E4, dark: 0x152122),
                wellStrong: Pair(light: 0xC6D5D4, dark: 0x20302F),
                ink: Pair(light: 0x081213, dark: 0xE9F4F3),
                inkSoft: Pair(light: 0x485A5B, dark: 0x9DB0AF),
                inkFaint: Pair(light: 0x66797A, dark: 0x78898A),
                accent: Pair(light: 0x0E5A5E, dark: 0x5CCFCB),
                // A deep paint colour cannot carry a control on a near-black
                // ground, so the dark side lifts it.
                fill: Pair(light: 0x0F6367, dark: 0x3DBAB6),
                fillDeep: Pair(light: 0x0A4A4E, dark: 0x25908D),
                fillHot: Pair(light: 0x4FB5B0, dark: 0xB4F4F0),
                onFill: Pair(light: 0xF1FBFA, dark: 0x041011),
                bar: Pair(light: 0x081213, dark: 0x152122),
                onBar: Pair(light: 0xB9CCCB, dark: 0x9DB0AF)
            )
        }
    }
}

/// The chosen colourway, shared with the widgets through the App Group.
enum ThemeStore {
    private static let key = "appearance.theme"
    private static let cache = OSAllocatedUnfairLock<AppTheme?>(initialState: nil)

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SnapshotStore.appGroup) ?? .standard
    }

    static var current: AppTheme {
        cache.withLock { cached in
            if let cached { return cached }
            let loaded = defaults.string(forKey: key).flatMap(AppTheme.init(rawValue:)) ?? .volt
            cached = loaded
            return loaded
        }
    }

    static func set(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: key)
        cache.withLock { $0 = theme }
    }

    /// Widgets run in their own process and re-read the choice on each refresh.
    static func reload() {
        cache.withLock { $0 = nil }
    }
}

/// Every colour in the product, resolved from the current colourway and the
/// system appearance.
enum Palette {
    static var canvas: Color { color(\.canvas) }
    static var surface: Color { color(\.surface) }
    static var well: Color { color(\.well) }
    static var wellStrong: Color { color(\.wellStrong) }

    static var ink: Color { color(\.ink) }
    static var inkSoft: Color { color(\.inkSoft) }
    static var inkFaint: Color { color(\.inkFaint) }

    static var accent: Color { color(\.accent) }
    static var fill: Color { color(\.fill) }
    static var fillDeep: Color { color(\.fillDeep) }
    static var onFill: Color { color(\.onFill) }

    /// The fill as it appears on a dark ground, whatever the system appearance.
    /// The Live Activity sits on its own dark panel and uses this.
    static var fillOnDark: Color {
        Color(uiColor: UIColor(hex: ThemeStore.current.tokens.fill.dark))
    }

    static var onFillOnDark: Color {
        Color(uiColor: UIColor(hex: ThemeStore.current.tokens.onFill.dark))
    }

    static var bar: Color { color(\.bar) }
    static var onBar: Color { color(\.onBar) }

    static let alert = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0xFF6B5E : 0xB3261E)
    })

    private static func color(_ role: KeyPath<AppTheme.Tokens, AppTheme.Pair>) -> Color {
        let pair = ThemeStore.current.tokens[keyPath: role]
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    /// Linear components for shader uniforms, which cannot resolve a dynamic colour.
    static func components(_ role: KeyPath<AppTheme.Tokens, AppTheme.Pair>, dark: Bool) -> (Float, Float, Float) {
        let pair = ThemeStore.current.tokens[keyPath: role]
        let hex = dark ? pair.dark : pair.light
        return (Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Oxanium carries numerals and titles; everything you read in a sentence is
/// San Francisco.
enum DisplayWeight: String {
    case regular = "Oxanium-Regular"
    case medium = "Oxanium-Medium"
    case semibold = "Oxanium-SemiBold"
    case bold = "Oxanium-Bold"
}

extension Font {
    static func display(_ size: CGFloat, _ weight: DisplayWeight = .medium, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Fixed-size variant for compositions that must not reflow with Dynamic Type.
    static func displayFixed(_ size: CGFloat, _ weight: DisplayWeight = .medium) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }
}

enum Format {
    static func km(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 100 ? 1 : 0)))
    }

    static func kWh(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Bare figure for a read-out whose unit is set separately: "29" or "1:02".
    static func clockDuration(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Compact elapsed time: "58 min ago", "3 h ago", "2 d ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if minutes < 48 * 60 { return "\(minutes / 60) h ago" }
        return "\(minutes / 1440) d ago"
    }

    static func money(_ value: Double, code: String = "EUR") -> String {
        value.formatted(.currency(code: code))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

extension VehicleSnapshot {
    /// One plain sentence for the state of the car, used in the header, widgets
    /// and Siri responses.
    var statusLine: String {
        switch charging.status {
        case .inProgress:
            if let minutes = minutesToLimit {
                return "Charging, \(Format.duration(minutes: minutes)) to \(charging.thresholdPercent)%"
            }
            return "Charging"
        case .finished: return "Charged to \(batteryPercent)%"
        case .scheduled: return "Charging starts \(charging.startTime.label)"
        case .stopped: return "Plugged in, paused"
        case .disconnected: return isLocked ? "Parked and locked" : "Parked, unlocked"
        }
    }

    var chargeTitle: String {
        switch charging.status {
        case .inProgress: "Charging"
        case .finished: "Charged"
        case .scheduled: "Scheduled"
        case .stopped: "Paused"
        case .disconnected: "Not plugged in"
        }
    }
}

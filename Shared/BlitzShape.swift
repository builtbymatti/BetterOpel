import SwiftUI

/// The 2023 Opel Blitz, redrawn from the geometry of the official SVG
/// (Wikimedia Commons, "Opel logo 2023.svg"): two ring arcs and the two halves of
/// the bolt. Kept as separate parts so the mark can be animated.
struct BlitzShape: Shape {
    struct Parts: OptionSet, Sendable {
        let rawValue: Int
        static let upperRing = Parts(rawValue: 1 << 0)
        static let lowerRing = Parts(rawValue: 1 << 1)
        static let upperBolt = Parts(rawValue: 1 << 2)
        static let lowerBolt = Parts(rawValue: 1 << 3)
        static let ring: Parts = [.upperRing, .lowerRing]
        static let bolt: Parts = [.upperBolt, .lowerBolt]
        static let all: Parts = [.ring, .bolt]
    }

    var parts: Parts = .all

    /// Width over height of the emblem's bounding box in the source artwork.
    static let aspectRatio: CGFloat = 450.37 / 280

    func path(in rect: CGRect) -> Path {
        // Source units: the bolt spans x 3.78...454.15, the ring y -0.07...279.93.
        let unit = min(rect.width / 450.37, rect.height / 280)
        let origin = CGPoint(
            x: rect.midX - 450.37 * unit / 2,
            y: rect.midY - 280 * unit / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x - 3.78) * unit, y: origin.y + (y + 0.07) * unit)
        }
        let center = point(229, 139.93)
        let outer = 140 * unit
        let inner = 130 * unit

        var path = Path()

        if parts.contains(.upperRing) {
            path.move(to: point(229, 9.93))
            path.addArc(center: center, radius: inner, startAngle: .degrees(-90), endAngle: .degrees(2.894), clockwise: false)
            path.addLine(to: point(368.75, 147.57))
            path.addArc(center: center, radius: outer, startAngle: .degrees(3.13), endAngle: .degrees(-160.93), clockwise: true)
            path.addLine(to: point(107.37, 94.2))
            path.addArc(center: center, radius: inner, startAngle: .degrees(-159.4), endAngle: .degrees(-90), clockwise: false)
            path.closeSubpath()
        }

        if parts.contains(.lowerRing) {
            path.move(to: point(229, 269.93))
            path.addArc(center: center, radius: inner, startAngle: .degrees(90), endAngle: .degrees(182.906), clockwise: false)
            path.addLine(to: point(89.17, 132.26))
            path.addArc(center: center, radius: outer, startAngle: .degrees(183.14), endAngle: .degrees(19.06), clockwise: true)
            path.addLine(to: point(350.6, 185.63))
            path.addArc(center: center, radius: inner, startAngle: .degrees(20.6), endAngle: .degrees(90), clockwise: false)
            path.closeSubpath()
        }

        if parts.contains(.upperBolt) {
            path.move(to: point(252.46, 139.9))
            path.addLine(to: point(320.56, 104.3))
            path.addLine(to: point(20.12, 104.21))
            path.addLine(to: point(3.78, 112.85))
            path.closeSubpath()
        }

        if parts.contains(.lowerBolt) {
            path.move(to: point(454.15, 167.0))
            path.addLine(to: point(205.47, 139.89))
            path.addLine(to: point(137.38, 175.58))
            path.addLine(to: point(437.78, 175.68))
            path.closeSubpath()
        }

        return path
    }
}

/// The static mark at a given height.
struct BlitzMark: View {
    var height: CGFloat = 22

    var body: some View {
        BlitzShape()
            .frame(width: height * BlitzShape.aspectRatio, height: height)
            .accessibilityHidden(true)
    }
}

#Preview {
    BlitzMark(height: 160)
        .foregroundStyle(Palette.ink)
        .padding(40)
        .background(Palette.canvas)
}

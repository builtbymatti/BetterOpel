import SwiftUI

/// The app's own icon set. Every glyph is a solid form drawn on a 24-unit grid
/// and built from the two things that make the Blitz and the typeface
/// recognisable: ends cut on the diagonal of the bolt, and squared, softly
/// radiused corners. Nothing here comes from a system symbol.
enum OpelIcon: String, CaseIterable, Sendable {
    case car, bolt, climate, route
    case lock, unlock, headlight, horn
    case sliders, navigate, arrowOut, back, close
    case plus, minus, pause, stop, trash, check, warning, battery
}

struct OpelIconShape: Shape {
    var icon: OpelIcon

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.unitPath(for: icon).applying(transform)
    }

    // MARK: Drawing helpers

    /// A closed polygon with softened corners.
    private static func polygon(_ points: [(CGFloat, CGFloat)], radius: CGFloat = 0.55) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let pts = points.map { CGPoint(x: $0.0, y: $0.1) }
        let last = pts[pts.count - 1], first = pts[0]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in pts.indices {
            path.addArc(tangent1End: pts[index], tangent2End: pts[(index + 1) % pts.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }

    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius, style: .continuous)
    }

    private static func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func line(_ points: [(CGFloat, CGFloat)], width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        return path.strokedPath(StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join, miterLimit: 6))
    }

    private static func rotated(_ path: Path, by degrees: CGFloat, around center: CGPoint) -> Path {
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
        return path.applying(transform)
    }

    // MARK: Glyphs

    static func unitPath(for icon: OpelIcon) -> Path {
        var path = Path()
        switch icon {
        case .bolt:
            // The Blitz's own flash: two blades meeting on the diagonal.
            path.addPath(polygon([(1.0, 6.2), (18.4, 6.2), (13.0, 12.9), (1.0, 7.9)], radius: 0.35))
            path.addPath(polygon([(23.0, 17.8), (5.6, 17.8), (11.0, 11.1), (23.0, 16.1)], radius: 0.35))

        case .car:
            var body = polygon([
                (1.4, 16.6), (1.4, 13.4), (2.6, 11.9), (8.0, 10.8), (11.0, 6.8),
                (18.8, 6.8), (22.2, 10.6), (22.6, 13.2), (22.6, 16.6),
            ], radius: 0.9)
            body = body.subtracting(disc(6.9, 16.9, 3.3))
            body = body.subtracting(disc(17.4, 16.9, 3.3))
            body = body.subtracting(polygon([(11.7, 8.3), (14.2, 8.3), (14.2, 10.7), (9.9, 10.7)], radius: 0.3))
            body = body.subtracting(polygon([(15.5, 8.3), (18.1, 8.3), (20.2, 10.7), (15.5, 10.7)], radius: 0.3))
            path.addPath(body)
            path.addPath(disc(6.9, 16.9, 2.25))
            path.addPath(disc(17.4, 16.9, 2.25))

        case .climate:
            // A four-blade fan; each blade is a slanted slab like the bolt's.
            let blade = polygon([(12.9, 9.6), (15.4, 2.2), (20.2, 4.9), (15.2, 11.4)], radius: 0.6)
            let center = CGPoint(x: 12, y: 12)
            for quarter in 0..<4 {
                path.addPath(rotated(blade, by: CGFloat(quarter) * 90, around: center))
            }
            path.addPath(disc(12, 12, 1.5))

        case .route:
            // A road doubling back on itself, from a start block to a destination.
            path.addPath(line([(6.4, 5.4), (17.0, 5.4), (17.0, 12.0), (7.0, 12.0), (7.0, 18.6), (16.4, 18.6)], width: 2.5, join: .round))
            path.addPath(box(2.4, 2.8, 5.2, 5.2, radius: 1.5))
            path.addPath(disc(18.4, 18.6, 2.9))

        case .lock, .unlock:
            path.addPath(LockGlyph.unitPath(open: icon == .unlock ? 1 : 0))

        case .headlight:
            var lamp = Path()
            lamp.move(to: CGPoint(x: 11.0, y: 5.6))
            lamp.addLine(to: CGPoint(x: 15.2, y: 5.6))
            lamp.addArc(center: CGPoint(x: 15.2, y: 12), radius: 6.4, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            lamp.addLine(to: CGPoint(x: 11.0, y: 18.4))
            lamp.closeSubpath()
            path.addPath(lamp)
            for beam in 0..<3 {
                let y = 6.0 + CGFloat(beam) * 4.4
                path.addPath(polygon([(8.4, y), (8.4, y + 2.0), (2.2, y + 3.6), (2.2, y + 1.6)], radius: 0.35))
            }

        case .horn:
            path.addPath(polygon([(2.4, 9.6), (7.4, 9.6), (15.6, 4.8), (15.6, 19.2), (7.4, 14.4), (2.4, 14.4)], radius: 0.8))
            path.addPath(line([(18.2, 8.2), (21.2, 6.0)], width: 2.0))
            path.addPath(line([(18.6, 12), (22.2, 12)], width: 2.0))
            path.addPath(line([(18.2, 15.8), (21.2, 18.0)], width: 2.0))

        case .sliders:
            var upper = box(2.6, 6.3, 18.8, 2.4, radius: 1.2)
            upper = upper.subtracting(box(11.6, 3.9, 7.2, 7.2, radius: 2.2))
            var lower = box(2.6, 15.3, 18.8, 2.4, radius: 1.2)
            lower = lower.subtracting(box(4.6, 12.9, 7.2, 7.2, radius: 2.2))
            path.addPath(upper)
            path.addPath(lower)
            path.addPath(box(12.6, 4.9, 5.2, 5.2, radius: 1.5))
            path.addPath(box(5.6, 13.9, 5.2, 5.2, radius: 1.5))

        case .navigate:
            path.addPath(polygon([(20.8, 3.2), (3.2, 10.4), (10.6, 13.4), (13.6, 20.8)], radius: 0.7))

        case .arrowOut:
            path.addPath(line([(6.6, 17.4), (16.6, 7.4)], width: 2.4))
            path.addPath(line([(8.6, 6.6), (17.4, 6.6), (17.4, 15.4)], width: 2.4))

        case .back:
            path.addPath(line([(14.8, 4.6), (7.4, 12), (14.8, 19.4)], width: 2.6))

        case .close:
            path.addPath(line([(5.6, 5.6), (18.4, 18.4)], width: 2.5))
            path.addPath(line([(18.4, 5.6), (5.6, 18.4)], width: 2.5))

        case .plus:
            path.addPath(box(10.75, 4.4, 2.5, 15.2, radius: 0.6))
            path.addPath(box(4.4, 10.75, 15.2, 2.5, radius: 0.6))

        case .minus:
            path.addPath(box(4.4, 10.75, 15.2, 2.5, radius: 0.6))

        case .pause:
            path.addPath(box(6.6, 5.2, 3.6, 13.6, radius: 1.0))
            path.addPath(box(13.8, 5.2, 3.6, 13.6, radius: 1.0))

        case .stop:
            path.addPath(box(5.6, 5.6, 12.8, 12.8, radius: 2.8))

        case .trash:
            path.addPath(box(4.2, 5.4, 15.6, 2.4, radius: 0.8))
            path.addPath(polygon([(9.4, 5.8), (9.9, 3.0), (14.1, 3.0), (14.6, 5.8)], radius: 0.5))
            var can = polygon([(6.0, 9.2), (18.0, 9.2), (17.0, 21.0), (7.0, 21.0)], radius: 1.1)
            can = can.subtracting(box(9.4, 11.6, 1.7, 6.8, radius: 0.5))
            can = can.subtracting(box(12.9, 11.6, 1.7, 6.8, radius: 0.5))
            path.addPath(can)

        case .check:
            path.addPath(line([(4.6, 12.6), (9.8, 17.6), (19.6, 6.6)], width: 2.6))

        case .warning:
            var sign = polygon([(12, 2.8), (22.2, 20.4), (1.8, 20.4)], radius: 1.4)
            sign = sign.subtracting(box(10.9, 8.6, 2.2, 6.2, radius: 0.6))
            sign = sign.subtracting(box(10.9, 16.0, 2.2, 2.2, radius: 0.6))
            path.addPath(sign)

        case .battery:
            var shell = box(1.8, 6.6, 18.4, 10.8, radius: 2.8)
            shell = shell.subtracting(box(3.8, 8.6, 14.4, 6.8, radius: 1.2))
            path.addPath(shell)
            path.addPath(polygon([(5.0, 9.8), (13.4, 9.8), (11.6, 14.2), (5.0, 14.2)], radius: 0.4))
            path.addPath(box(21.0, 10.0, 1.6, 4.0, radius: 0.7))
        }
        return path
    }
}

/// The lock, with a shackle that can swing open. Kept as its own shape so the
/// change between locked and unlocked is drawn, not cross-faded.
struct LockGlyph: Shape {
    /// 0 is locked, 1 is unlocked.
    var open: Double

    var animatableData: Double {
        get { open }
        set { open = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.unitPath(open: open).applying(transform)
    }

    static func unitPath(open: Double) -> Path {
        let lift = CGFloat(open) * 1.5
        // The free leg of the shackle draws up out of the body as it opens.
        let freeLeg = 11.6 - CGFloat(open) * 4.2

        var shackle = Path()
        shackle.move(to: CGPoint(x: 7.7, y: 11.6))
        shackle.addLine(to: CGPoint(x: 7.7, y: 7.4 - lift))
        shackle.addArc(tangent1End: CGPoint(x: 7.7, y: 3.3 - lift), tangent2End: CGPoint(x: 12, y: 3.3 - lift), radius: 3.6)
        shackle.addArc(tangent1End: CGPoint(x: 16.3, y: 3.3 - lift), tangent2End: CGPoint(x: 16.3, y: 7.4 - lift), radius: 3.6)
        shackle.addLine(to: CGPoint(x: 16.3, y: freeLeg - lift))

        var body = Path(roundedRect: CGRect(x: 4.2, y: 10.6, width: 15.6, height: 10.6), cornerRadius: 2.8, style: .continuous)
        // Keyhole: a slit cut on the bolt's diagonal.
        var slit = Path()
        slit.move(to: CGPoint(x: 11.5, y: 13.6))
        slit.addLine(to: CGPoint(x: 13.7, y: 13.6))
        slit.addLine(to: CGPoint(x: 12.5, y: 18.2))
        slit.addLine(to: CGPoint(x: 10.3, y: 18.2))
        slit.closeSubpath()
        body = body.subtracting(slit)

        var path = shackle.strokedPath(StrokeStyle(lineWidth: 2.5, lineCap: .butt, lineJoin: .round))
        path.addPath(body)
        return path
    }
}

/// An icon at a given point size, coloured by the surrounding foreground style.
struct IconView: View {
    var icon: OpelIcon
    var size: CGFloat = 22

    init(_ icon: OpelIcon, size: CGFloat = 22) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        OpelIconShape(icon: icon)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

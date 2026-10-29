import SwiftUI

/// One refresh as the lens plays it: when it was sent, and how it ended.
struct LensRun: Equatable {
    var sentAt: Date
    /// A fresh reading came back; the beads return from this moment.
    var answerAt: Date?
    /// Nothing newer came back; the film lets go from this moment.
    var failAt: Date?
    /// How far along the rim the return starts. A pair that is still on its way
    /// out when the answer comes turns around where it is.
    var returnFrom = 560.0
}

/// What the shader draws in one frame.
struct LensPose: Equatable, Sendable {
    var outHead = 0.0, outLength = 0.0, outWidth = 0.0
    var backHead = 0.0, backLength = 0.0, backWidth = 0.0
    var filmWidth = 0.0, filmReach = 250.0
    var clock = 0.0

    static let still = LensPose()
    var isVisible: Bool { outWidth > 0.05 || backWidth > 0.05 || filmWidth > 0.05 }
}

/// The choreography. Each part is a keyframed track, timed by hand:
///
/// - Send: the film along the top gathers, then lets two beads go. They whip
///   through the corners and glide out down the sides.
/// - Wait: a thin film stays on the top edge and breathes, and every few
///   seconds a slower, smaller pair goes out again.
/// - Answer: the pair comes back up the sides, picking up speed, and lands in
///   the film, which swells once and drains.
/// - Nothing new: the film shivers and lets go.
@MainActor
enum LensScore {
    struct Bead { var head = 0.0; var width = 0.0 }
    struct Film { var width = 0.0; var reach = 250.0 }

    static let launch = KeyframeTimeline(initialValue: Bead()) {
        KeyframeTrack(\.head) {
            // Held for a moment while the film gathers.
            LinearKeyframe(0, duration: 0.1)
            SpringKeyframe(660, duration: 1.6, spring: .smooth(duration: 1.25))
        }
        KeyframeTrack(\.width) {
            SpringKeyframe(46, duration: 0.3, spring: .bouncy(duration: 0.28, extraBounce: 0.08))
            CubicKeyframe(37, duration: 0.45)
            CubicKeyframe(22, duration: 0.6)
            CubicKeyframe(0, duration: 0.35)
        }
    }

    static let pulse = KeyframeTimeline(initialValue: Bead()) {
        KeyframeTrack(\.head) {
            SpringKeyframe(540, duration: 2.1, spring: .smooth(duration: 1.8))
        }
        KeyframeTrack(\.width) {
            CubicKeyframe(20, duration: 0.5)
            CubicKeyframe(13, duration: 1.0)
            CubicKeyframe(0, duration: 0.6)
        }
    }

    static let gather = KeyframeTimeline(initialValue: Film(width: 0, reach: 170)) {
        KeyframeTrack(\.width) {
            SpringKeyframe(15, duration: 0.14, spring: .snappy(duration: 0.14))
            // The beads take the glass with them,
            SpringKeyframe(4, duration: 0.3, spring: .smooth(duration: 0.3))
            // and it wells back up while the car is asked.
            SpringKeyframe(9, duration: 0.9, spring: .smooth(duration: 0.8))
        }
        KeyframeTrack(\.reach) {
            CubicKeyframe(210, duration: 0.14)
            CubicKeyframe(270, duration: 1.2)
        }
    }

    /// How long the beads take to come back up.
    static let climb = 0.6
    /// The return leaves no sooner than this after the send, so a quick answer
    /// still lets the send play out.
    static let shortestSend = 1.15

    /// A pair that turns around nearer the top has less far to come.
    static func climbTime(_ run: LensRun) -> Double {
        climb * max(0.55, (run.returnFrom / 560).squareRoot())
    }

    static let landing = KeyframeTimeline(initialValue: Film(width: 9, reach: 270)) {
        KeyframeTrack(\.width) {
            // Draws breath while the beads climb,
            CubicKeyframe(6, duration: climb)
            // takes them in,
            SpringKeyframe(24, duration: 0.15, spring: .snappy(duration: 0.13))
            // and drains.
            SpringKeyframe(0, duration: 0.65, spring: .smooth(duration: 0.5))
        }
        KeyframeTrack(\.reach) {
            CubicKeyframe(270, duration: climb)
            CubicKeyframe(330, duration: 0.15)
            CubicKeyframe(190, duration: 0.65)
        }
    }

    static let slump = KeyframeTimeline(initialValue: Film(width: 9, reach: 270)) {
        KeyframeTrack(\.width) {
            SpringKeyframe(14, duration: 0.09, spring: .snappy(duration: 0.09))
            SpringKeyframe(5, duration: 0.11, spring: .snappy(duration: 0.1))
            SpringKeyframe(10, duration: 0.11, spring: .snappy(duration: 0.1))
            SpringKeyframe(0, duration: 0.5, spring: .smooth(duration: 0.4))
        }
        KeyframeTrack(\.reach) {
            CubicKeyframe(270, duration: 0.31)
            CubicKeyframe(140, duration: 0.5)
        }
    }

    /// The beads come back on a curve that keeps accelerating into the landing.
    private static let pullIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.5, y: 0),
        endControlPoint: UnitPoint(x: 0.86, y: 0.52)
    )

    static func end(of run: LensRun) -> Date? {
        if let answerAt = run.answerAt {
            return answerAt.addingTimeInterval(climbTime(run) + landing.duration - climb + 0.05)
        }
        if let failAt = run.failAt { return failAt.addingTimeInterval(slump.duration + 0.05) }
        return nil
    }

    static func pose(at now: Date, run: LensRun) -> LensPose {
        let t = now.timeIntervalSince(run.sentAt)
        var pose = LensPose()
        pose.clock = t

        // Outbound: the launch, then the slow pairs for as long as the car is asked.
        var out = stretched(launch, at: t)
        if t > launch.duration {
            let first = 2.3, period = 3.3
            let index = ((t - first) / period).rounded(.down)
            let start = first + index * period
            let closes = (run.answerAt ?? run.failAt)?.timeIntervalSince(run.sentAt)
            if index >= 0, closes.map({ start < $0 }) ?? true {
                out = stretched(pulse, at: t - start)
            }
        }
        (pose.outHead, pose.outLength, pose.outWidth) = out

        // The film: gathers, then breathes.
        var film = gather.value(time: t)
        if t > gather.duration {
            film.width *= 1 + 0.18 * sin((t - gather.duration) * 2 * .pi / 3.4)
        }

        if let answerAt = run.answerAt, now >= answerAt {
            let u = now.timeIntervalSince(answerAt)
            let rise = climbTime(run)
            // Glass that was still on its way out gives itself to the return.
            pose.outWidth *= max(0, 1 - u / 0.14)
            if u < rise {
                film.width *= landing.value(time: u / rise * climb).width / 9
                let progress = pullIn.value(at: u / rise)
                let earlier = pullIn.value(at: max(0, u - 1.0 / 90) / rise)
                let speed = (progress - earlier) * run.returnFrom * 90
                pose.backHead = run.returnFrom * (1 - progress)
                pose.backLength = min(max(60 + speed * 0.17, 60), 250)
                // Gathers glass as it climbs.
                pose.backWidth = (13 + 18 * (u / rise)) * min(1, u / 0.1)
            } else {
                film = landing.value(time: climb + u - rise)
            }
        } else if let failAt = run.failAt, now >= failAt {
            let u = now.timeIntervalSince(failAt)
            // A pair still on its way out thins away with the film.
            pose.outWidth *= max(0, 1 - u / 0.3)
            let waiting = film.width
            film = slump.value(time: u)
            film.width *= waiting / 9
        }
        pose.filmWidth = max(0, film.width)
        pose.filmReach = film.reach
        return pose
    }

    /// A bead with its tail: longer the faster it moves, catching up as it slows.
    private static func stretched(_ timeline: KeyframeTimeline<Bead>, at time: Double) -> (Double, Double, Double) {
        guard time >= 0, time <= timeline.duration else { return (0, 0, 0) }
        let bead = timeline.value(time: time)
        let earlier = timeline.value(time: max(0, time - 1.0 / 90))
        let speed = max(0, bead.head - earlier.head) * 90
        return (bead.head, min(max(64 + speed * 0.19, 64), 290), max(0, bead.width))
    }
}

/// Plays the lens over a view that reaches the top of the screen. The view is
/// drawn with a strip of page above it, so the lens still has something to sit
/// on while the page is pulled down.
struct LensWaveModifier: ViewModifier {
    /// The display's corner radius, so the beads follow the real corners.
    var cornerRadius: CGFloat

    @Environment(VehicleModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var run: LensRun?
    @State private var place = CGRect.zero

    private static let apron: CGFloat = 320

    /// `-lensAt 0.4` holds the wave 0.4 s after the send, for UI checks. Add
    /// `-lensAnswerAt 2.5` or `-lensFailAt 2.5` to hold a moment of an ending.
    private static var frozenPose: LensPose? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> Double? {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return Double(arguments[index + 1])
        }
        guard let time = value("-lensAt") else { return nil }
        let sent = Date(timeIntervalSinceReferenceDate: 0)
        var run = LensRun(sentAt: sent)
        if let answer = value("-lensAnswerAt") {
            let answerAt = sent.addingTimeInterval(answer)
            let then = LensScore.pose(at: answerAt, run: run)
            run.returnFrom = then.outWidth > 3 && then.outHead < 560 ? max(then.outHead, 120) : 560
            run.answerAt = answerAt
        }
        if let fail = value("-lensFailAt") { run.failAt = sent.addingTimeInterval(fail) }
        return LensScore.pose(at: sent.addingTimeInterval(time), run: run)
        #else
        return nil
        #endif
    }

    func body(content: Content) -> some View {
        let padded = content
            .padding(.top, Self.apron)
            .background(alignment: .top) {
                Palette.canvas
                    .frame(height: Self.apron + 2)
                    .allowsHitTesting(false)
            }

        // Where the padded layer sits on the screen, and how large it is.
        let top = place.minY
        let size = place.size
        // Pulling the page down draws a bulge out of the top edge, never deeper
        // than the gap the pull has opened.
        let pull = max(0, top + Self.apron)
        let drawn = min(pull / 130, 1)
        let bulge = min(56 * (1 - (1 - drawn) * (1 - drawn)), pull * 0.62)

        TimelineView(.animation(paused: run == nil)) { context in
            let pose = Self.frozenPose ?? run.map { LensScore.pose(at: context.date, run: $0) } ?? .still
            padded.layerEffect(
                ShaderLibrary.lensWave(
                    .float2(size),
                    .float4(-top, cornerRadius, size.height, 0),
                    .float4(pose.outHead, pose.outLength, pose.outWidth, 1),
                    .float4(pose.backHead, pose.backLength, pose.backWidth, -1),
                    .float4(pose.filmWidth, pose.filmReach, bulge, pose.clock),
                    .float(scheme == .dark ? 1 : -1)
                ),
                maxSampleOffset: CGSize(width: 48, height: 48),
                isEnabled: !reduceMotion && size.width > 0 && (pose.isVisible || bulge > 0.5)
            )
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            place = frame
        }
        .padding(.top, -Self.apron)
        .onChange(of: model.isPending(.refresh)) { _, isAsking in
            guard isAsking, !reduceMotion else { return }
            run = LensRun(sentAt: .now)
        }
        .onChange(of: model.refreshCue) {
            guard var current = run, current.answerAt == nil else {
                Haptics.shared.settle()
                return
            }
            let answerAt = max(.now, current.sentAt.addingTimeInterval(LensScore.shortestSend))
            let then = LensScore.pose(at: answerAt, run: current)
            current.returnFrom = then.outWidth > 3 && then.outHead < 560 ? max(then.outHead, 120) : 560
            current.answerAt = answerAt
            run = current
        }
        .onChange(of: model.refreshMisses) {
            guard var current = run, current.failAt == nil else { return }
            current.failAt = .now
            run = current
        }
        .task(id: run) {
            guard let run, let end = LensScore.end(of: run) else { return }
            if let answerAt = run.answerAt {
                // The tap in the hand lands with the beads, not with the data.
                let landing = answerAt.addingTimeInterval(LensScore.climbTime(run))
                try? await Task.sleep(for: .seconds(max(0, landing.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                Haptics.shared.settle()
            }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self.run = nil
        }
    }
}

extension View {
    /// The refresh lens, for a view whose top edge is the top of the screen.
    func lensWave(cornerRadius: CGFloat) -> some View {
        modifier(LensWaveModifier(cornerRadius: cornerRadius))
    }
}

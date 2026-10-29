import SwiftUI

/// The three-quarter render of the car. Everything that shows the car from this
/// angle goes through here, so a new render only has to be described once.
struct CarRender: View {
    /// The large asset for the hero, the small one everywhere else.
    var isLarge = false

    /// Width over height of the render.
    static let aspect: CGFloat = 2121 / 1064

    var body: some View {
        Image(isLarge ? "CarHero" : "CarHeroSmall")
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.aspect, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

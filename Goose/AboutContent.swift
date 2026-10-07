import Foundation

/// Everything personal on the info screens. Rows whose link is nil are hidden.
enum AboutContent {
    static let developerName = "Blake"

    /// An image in Assets.xcassets, shown in a circle. Nil shows the goose instead.
    static let photoName: String? = "DeveloperPhoto"

    /// Shown on the About the Developer page. Blank lines start new paragraphs.
    static let story = """
    I live in Portland, Oregon. I like solving problems, and I like making things free that should have been free to begin with.

    When I'm not doing that, it's coffee, music, chess, sports, and running.
    """

    /// A Buy Me a Coffee (or similar) page. Only shown on the US App Store,
    /// the one storefront where Apple allows links to outside payment.
    static let coffeeURL = URL(string: "https://buymeacoffee.com/blakeabel")

    /// The public GitHub repository.
    static let sourceURL = URL(string: "https://github.com/tonyhawklover/goose")

    /// Where people should report problems, e.g. the repository's issues page.
    static let supportURL = URL(string: "https://github.com/tonyhawklover/goose/issues")

    /// The hosted copy of docs/privacy.md, e.g. on GitHub Pages.
    static let privacyPolicyURL = URL(string: "https://tonyhawklover.github.io/goose/privacy.html")
}

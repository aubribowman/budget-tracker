import SwiftUI
import CoreText

// The app's two fonts, bundled in Resources/Fonts (free under the SIL Open Font License,
// see the OFL files next to them):
// - Space Grotesk for headings, titles and money figures (`.display`)
// - DM Sans for everything else (`.ui`)
// Both grow with the user's text size, like the system font.

enum AppFonts {
    static let display = "Space Grotesk"
    static let text = "DM Sans"

    /// Makes the bundled fonts available. Called once at launch, before any view draws.
    static func register() {
        for name in ["SpaceGrotesk", "DMSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The system's size for each text style at the default text setting, so the new
    /// fonts line up with what each style looked like before.
    static func size(_ s: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        switch s {
        case .largeTitle: 26; case .title: 22; case .title2: 17; case .title3: 15
        case .headline, .body: 13; case .callout: 12; case .subheadline: 11
        case .footnote, .caption: 10; case .caption2: 10
        default: 13
        }
        #else
        switch s {
        case .largeTitle: 34; case .title: 28; case .title2: 22; case .title3: 20
        case .headline, .body: 17; case .callout: 16; case .subheadline: 15
        case .footnote: 13; case .caption: 12; case .caption2: 11
        default: 17
        }
        #endif
    }
}

extension Font {
    /// Body text in DM Sans. Titles (largeTitle through title3) use Space Grotesk, so
    /// `.font(.ui(.title3))` still reads as a heading. Headline is semibold, like the system's.
    static func ui(_ style: Font.TextStyle) -> Font {
        switch style {
        case .largeTitle, .title, .title2, .title3:
            return display(style, weight: .bold)
        case .headline:
            return .custom(AppFonts.text, size: AppFonts.size(style), relativeTo: style).weight(.semibold)
        default:
            return .custom(AppFonts.text, size: AppFonts.size(style), relativeTo: style)
        }
    }

    /// Headings and money figures in Space Grotesk, sized like a text style.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .custom(AppFonts.display, size: AppFonts.size(style), relativeTo: style).weight(weight)
    }

    /// Space Grotesk at a set size that still grows with the user's text size.
    static func display(size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(AppFonts.display, size: size, relativeTo: style).weight(weight)
    }
}

#if os(iOS)
import UIKit

extension AppFonts {
    /// Space Grotesk for the iPhone's big page titles and small bar titles.
    static func styleNavigationBars() {
        func font(_ size: CGFloat, _ w: UIFont.Weight) -> UIFont {
            let d = UIFontDescriptor(fontAttributes: [.family: display, .traits: [UIFontDescriptor.TraitKey.weight: w]])
            return UIFontMetrics(forTextStyle: size > 20 ? .largeTitle : .headline).scaledFont(for: UIFont(descriptor: d, size: size))
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: font(34, .bold)]
        bar.titleTextAttributes = [.font: font(17, .bold)]
    }
}
#endif

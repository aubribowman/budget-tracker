import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// iPhone-only touches, with a Mac version (or nothing) for each, so screens can
/// use them without checking the platform themselves.
extension View {
    /// Number keypad on iPhone. On Mac, a form would show the "0.00" placeholder as a
    /// separate label beside the box, so hide it there and let it act as a placeholder.
    func decimalPad() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        labelsHidden()
        #endif
    }

    /// Mac: keep cards a comfortable width and centered in a wide window.
    func readableWidth() -> some View {
        #if os(macOS)
        frame(maxWidth: 680).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// Mac: sheets shrink to fit their content, so give them a sensible size and the
    /// iPhone-style grouped form look.
    func macSheet() -> some View {
        #if os(macOS)
        formStyle(.grouped)
            .frame(minWidth: 460, idealWidth: 540, minHeight: 480, idealHeight: 680)
        #else
        self
        #endif
    }

    /// Mac: iPhone-style grouped forms instead of the Mac's two-column layout.
    func macFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Small title in the bar on iPhone. Mac windows always show it that way.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// A "Done" button above the iPhone number keypad, which has no return key.
    func keyboardDoneButton(_ action: @escaping () -> Void = {}) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { action(); hideKeyboard() }
            }
        }
        #else
        self
        #endif
    }
}

/// Puts the keyboard away on iPhone.
func hideKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

/// The system colors the app uses, in their iPhone and Mac versions.
enum SystemColor {
    #if canImport(UIKit)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let bg = Color(UIColor.systemGroupedBackground)
    static let track = Color(UIColor.tertiarySystemFill)
    #else
    static let card = Color(NSColor.controlBackgroundColor)
    static let bg = Color(NSColor.windowBackgroundColor)
    static let track = Color(NSColor.quaternaryLabelColor)
    #endif

    /// A color that switches between two shades for light and dark mode.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        Color(NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

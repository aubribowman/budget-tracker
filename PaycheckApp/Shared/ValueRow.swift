import SwiftUI

/// A row with a name on the left and a value (usually money) on the right.
/// At the largest accessibility text sizes there isn't room for both on one line, so
/// the value moves under the name instead of squeezing both into narrow columns.
/// Use it instead of `HStack { name; Spacer(); value }` for any row that shows an amount.
struct ValueRow<Leading: View, Value: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var value: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
         @ViewBuilder _ leading: () -> Leading, @ViewBuilder value: () -> Value) {
        self.alignment = alignment; self.spacing = spacing
        self.leading = leading(); self.value = value()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: spacing) { leading }
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: spacing) { value }
            }
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                leading
                Spacer(minLength: Space.s)
                value
            }
        }
    }
}

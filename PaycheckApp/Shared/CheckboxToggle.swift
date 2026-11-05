import SwiftUI

/// A checkbox on iPhone and Mac, for a long label that reads as a sentence.
struct CheckboxToggle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: c.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(c.isOn ? Theme.rosy : .secondary)
                    .font(.title3)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                c.label.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(c.isOn ? "On" : "Off")
    }
}

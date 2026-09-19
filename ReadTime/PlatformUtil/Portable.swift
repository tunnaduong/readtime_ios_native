import SwiftUI

// Small wrappers around SwiftUI and Foundation APIs that Skip can't transpile yet, so the
// shared views stay free of `#if !SKIP` blocks. On iOS each one is the original API.

extension View {
    /// `contentShape(Rectangle())`: makes the whole frame tappable. Compose already hit-tests the full frame.
    func tappableRect() -> some View {
        #if !SKIP
        contentShape(Rectangle())
        #else
        self
        #endif
    }

    /// `contentShape(Capsule())`.
    func tappableCapsule() -> some View {
        #if !SKIP
        contentShape(Capsule())
        #else
        self
        #endif
    }

    /// `.buttonBorderShape(.capsule)`. Material buttons are already capsule shaped.
    func capsuleButtonShape() -> some View {
        #if !SKIP
        buttonBorderShape(.capsule)
        #else
        self
        #endif
    }

    /// `.controlSize(.large)`.
    func largeControl() -> some View {
        #if !SKIP
        controlSize(.large)
        #else
        self
        #endif
    }

    /// `.accessibilityElement(children: .combine)`.
    func accessibilityCombined() -> some View {
        #if !SKIP
        accessibilityElement(children: .combine)
        #else
        self
        #endif
    }

    /// `.accessibilityElement(children: .ignore)`.
    func accessibilityIgnoringChildren() -> some View {
        #if !SKIP
        accessibilityElement(children: .ignore)
        #else
        self
        #endif
    }

    /// `.accessibilityElement(children: .contain)`.
    func accessibilityContaining() -> some View {
        #if !SKIP
        accessibilityElement(children: .contain)
        #else
        self
        #endif
    }

    /// `.listRowInsets(...)`. Android keeps the default row padding.
    func rowInsets(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> some View {
        #if !SKIP
        listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
        #else
        self
        #endif
    }

    /// `.monospacedDigit()`.
    func monospacedDigits() -> some View {
        #if !SKIP
        monospacedDigit()
        #else
        self
        #endif
    }

    /// `.lineLimit(min...max)` for a growing text field.
    func lineRange(_ min: Int, _ max: Int) -> some View {
        #if !SKIP
        lineLimit(min...max)
        #else
        lineLimit(max)
        #endif
    }

    /// `.datePickerStyle(.graphical)`. Android shows its own Material date picker.
    func graphicalDatePicker() -> some View {
        #if !SKIP
        datePickerStyle(.graphical)
        #else
        self
        #endif
    }

    /// `.safeAreaInset(edge: .bottom)`: content pinned under the view. On Android it's stacked
    /// below instead, which looks the same for the full-width button bars this is used for.
    func bottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if !SKIP
        safeAreaInset(edge: .bottom) { bar() }
        #else
        VStack(spacing: 0) {
            self
            bar()
        }
        #endif
    }
}

/// Redraws its content every second, like `TimelineView(.periodic(from: .now, by: 1))`.
struct EverySecond<Content: View>: View {
    @ViewBuilder let content: (Date) -> Content
    #if SKIP
    @State private var now = Date()
    #endif

    var body: some View {
        #if !SKIP
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(context.date)
        }
        #else
        content(now)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
        #endif
    }
}

/// Localised date text from a `DateFormatter` template such as "EEE" or "MMMMy".
enum DateText {
    static func string(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        #if !SKIP
        formatter.setLocalizedDateFormatFromTemplate(template)
        #else
        formatter.dateFormat = android.text.format.DateFormat.getBestDateTimePattern(java.util.Locale.getDefault(), template)
        #endif
        return formatter.string(from: date)
    }

    /// Medium date, like `formatted(date: .abbreviated, time: .omitted)`.
    static func abbreviated(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// 2026-09-19, for file names and CSV exports.
    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Short weekday names, Sunday first (`Calendar.shortStandaloneWeekdaySymbols`).
    static var shortWeekdaySymbols: [String] {
        #if !SKIP
        Calendar.current.shortStandaloneWeekdaySymbols
        #else
        Calendar.current.shortWeekdaySymbols
        #endif
    }

    /// One or two letter weekday names, Sunday first (`veryShortStandaloneWeekdaySymbols`).
    static var veryShortWeekdaySymbols: [String] {
        #if !SKIP
        Calendar.current.veryShortStandaloneWeekdaySymbols
        #else
        Calendar.current.shortWeekdaySymbols.map { String($0.prefix(1)) }
        #endif
    }
}

extension View {
    /// `.accessibilityAddTraits(.isSelected)` when `selected`.
    func selectedTrait(_ selected: Bool) -> some View {
        #if !SKIP
        accessibilityAddTraits(selected ? .isSelected : [])
        #else
        self
        #endif
    }
}

/// `Stepper(_:value:in:step:)`, which Skip lacks: Android clamps in the increment/decrement actions.
struct BoundedStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        #if !SKIP
        Stepper(title, value: $value, in: range, step: step)
        #else
        let lower: Int = range.start
        let upper: Int = range.endInclusive
        Stepper(title, onIncrement: {
            let next = value + step
            value = next > upper ? upper : next
        }, onDecrement: {
            let next = value - step
            value = next < lower ? lower : next
        })
        #endif
    }
}

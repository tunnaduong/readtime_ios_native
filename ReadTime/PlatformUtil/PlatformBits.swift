import SwiftUI

// MARK: - App icon

#if !SKIP

enum AlternateIcon: String, CaseIterable, Identifiable {
    case standard = "Default", midnight = "Midnight", paper = "Paper", sunset = "Sunset", forest = "Forest", ocean = "Ocean"

    var id: String { rawValue }

    /// Nil selects the primary icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .standard: LocalizedStringKey("Default")
        case .midnight: LocalizedStringKey("Midnight")
        case .paper: LocalizedStringKey("Paper")
        case .sunset: LocalizedStringKey("Sunset")
        case .forest: LocalizedStringKey("Forest")
        case .ocean: LocalizedStringKey("Ocean")
        }
    }

    static var current: AlternateIcon {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

struct AppIconPickerView: View {
    @State private var selection = AlternateIcon.current
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 22) {
                ForEach(AlternateIcon.allCases) { icon in
                    Button {
                        choose(icon)
                    } label: {
                        VStack(spacing: 8) {
                            Image("AppIconPreview-\(icon.rawValue)")
                                .resizable()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                                        .stroke(selection == icon ? Color.readTimePurple : .clear, lineWidth: 3)
                                )
                            Text(icon.title)
                                .font(.subheadline.weight(selection == icon ? .semibold : .regular))
                                .foregroundStyle(selection == icon ? Color.readTimePurple : Color.readTimeText)
                        }
                    }
                    .buttonStyle(.plain)
                    .selectedTrait(selection == icon)
                }
            }
            .padding(24)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .alert("App Icon", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func choose(_ icon: AlternateIcon) {
        guard icon != selection, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selection
        selection = icon
        Task {
            do {
                try await setIcon(icon, retries: 2)
            } catch {
                selection = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    /// iOS sometimes answers EAGAIN ("Resource temporarily unavailable") while it's still busy,
    /// occasionally even after the icon did change, so check the icon in use and try again.
    private func setIcon(_ icon: AlternateIcon, retries: Int) async throws {
        do {
            try await UIApplication.shared.setAlternateIconName(icon.iconName)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EAGAIN) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if UIApplication.shared.alternateIconName == icon.iconName { return }
            guard retries > 0 else { throw error }
            try await setIcon(icon, retries: retries - 1)
        }
    }
}

#endif

// Android has no runtime alternate-launcher-icon API (changing it requires shipping
// multiple activity-alias manifest entries ahead of time, a build-time choice, not a
// runtime one) — so the "App Icon" settings row itself is hidden there entirely below,
// rather than stubbing a picker that can't do anything. Revisit if product wants an
// Android-specific implementation using pre-declared activity aliases.

// MARK: - Keyboard

extension View {
    /// Adds a Done button above the keyboard and lets scrolling push the keyboard away.
    /// Use inside a NavigationStack on screens with text input.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { KeyboardDismissal.dismiss() }
                        .fontWeight(.semibold)
                }
            }
    }
}

#if !SKIP

/// Hides the keyboard when the user taps anywhere that isn't a text field, across the whole
/// app (sheets included), without swallowing taps meant for buttons.
enum KeyboardDismissal {
    private static let handler = TapHandler()

    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func install() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is DismissTap }) {
            let tap = DismissTap(target: handler, action: #selector(TapHandler.handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = handler
            window.addGestureRecognizer(tap)
        }
    }

    private final class DismissTap: UITapGestureRecognizer {}

    private final class TapHandler: NSObject, UIGestureRecognizerDelegate {
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Let taps on text inputs through so moving between fields keeps the keyboard up.
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

#else

// TODO(android): Compose has its own keyboard-dismiss primitive
// (`LocalFocusManager.current.clearFocus()`), reachable only from inside a Composable —
// `dismiss()` here has no receiver to call it on. Left a no-op; wire up once `install()`'s
// call site (`ReadTimeApp.body.onAppear`) has a Compose-side hook available via Skip interop.
enum KeyboardDismissal {
    static func dismiss() {}
    static func install() {}
}

#endif

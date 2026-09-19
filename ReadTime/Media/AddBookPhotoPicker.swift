import SwiftUI
#if !SKIP
import PhotosUI
#endif

// Cross-platform stand-in for `PhotosPickerItem` so `AddBookView` doesn't need
// platform-specific state/logic beyond this one seam.

#if !SKIP

typealias CoverPickerItem = PhotosPickerItem

extension PhotosPickerItem {
    func loadCoverData() async throws -> Data? {
        try await loadTransferable(type: Data.self)
    }
}

struct CoverPickerButton<Label: View>: View {
    @Binding var selection: CoverPickerItem?
    @ViewBuilder let label: () -> Label

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) { label() }
    }
}

#else

// TODO(android): back this with the Android Photo Picker
// (`ActivityResultContracts.PickVisualMedia`) via Skip's Kotlin interop, setting
// `selection` to a `CoverPickerItem` wrapping the picked image's bytes.
struct CoverPickerItem: Equatable {
    let data: Data
}

extension CoverPickerItem {
    func loadCoverData() async throws -> Data? { data }
}

struct CoverPickerButton<Label: View>: View {
    @Binding var selection: CoverPickerItem?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: {
            // TODO(android): launch the Android Photo Picker here.
        }) {
            label()
        }
    }
}

#endif

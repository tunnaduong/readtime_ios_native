import SwiftUI
#if !SKIP
import UniformTypeIdentifiers
#else
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
#endif

/// The kinds of files the import screens open.
public enum PickedFileKind {
    case json
    case text

    #if !SKIP
    var contentTypes: [UTType] {
        switch self {
        case .json: [.json]
        case .text: [.commaSeparatedText, .plainText]
        }
    }
    #else
    var mimeTypes: [String] {
        switch self {
        case .json: ["application/json", "application/octet-stream", "text/plain"]
        case .text: ["text/csv", "text/comma-separated-values", "text/plain", "application/csv"]
        }
    }
    #endif
}

extension View {
    /// `fileImporter` on iOS; the system document picker (`ACTION_OPEN_DOCUMENT`) on Android,
    /// copying the chosen file into the cache so it can be read with `Data(contentsOf:)`.
    func filePicker(isPresented: Binding<Bool>, kind: PickedFileKind, onPick: @escaping (URL) -> Void, onError: @escaping (Error) -> Void) -> some View {
        #if !SKIP
        fileImporter(isPresented: isPresented, allowedContentTypes: kind.contentTypes) { result in
            switch result {
            case .success(let url): onPick(url)
            case .failure(let error): onError(error)
            }
        }
        #else
        background {
            AndroidFilePicker(isPresented: isPresented, mimeTypes: kind.mimeTypes, onPick: onPick, onError: onError)
        }
        #endif
    }
}

#if SKIP
struct AndroidFilePicker: View {
    @Binding var isPresented: Bool
    let mimeTypes: [String]
    let onPick: (URL) -> Void
    let onError: (Error) -> Void

    var body: some View {
        ComposeView { _ in
            let context = LocalContext.current
            let launcher = rememberLauncherForActivityResult(contract: ActivityResultContracts.OpenDocument()) { uri in
                isPresented = false
                guard let uri else { return }
                do {
                    onPick(try Self.copyToCache(uri: uri, context: context))
                } catch {
                    onError(error)
                }
            }
            LaunchedEffect(isPresented) {
                if isPresented {
                    launcher.launch((mimeTypes.kotlin() as kotlin.collections.List<String>).toTypedArray())
                }
            }
        }
    }

    static func copyToCache(uri: Uri, context: Context) throws -> URL {
        guard let input = context.contentResolver.openInputStream(uri) else { throw PickedFileError.unreadable }
        let bytes = input.readBytes()
        input.close()
        let file = java.io.File(context.cacheDir, "picked-\(UUID().uuidString)")
        file.writeBytes(bytes)
        return URL(fileURLWithPath: file.absolutePath)
    }
}

enum PickedFileError: Error {
    case unreadable
}
#endif

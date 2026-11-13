import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuillFolders") {
      QuillFolders.register(with: registrar)
    }
  }
}

// Folder access on iOS: the Files picker grants a security-scoped folder. Its bookmark is
// saved so access survives restarts; books are read in place through file:// URLs.
// Not yet compiled: Xcode was unavailable when this was written (see mobile/README.md).
class QuillFolders: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private static let bookmarkKey = "quill.folderBookmark"
  private static let extensions: Set<String> = ["epub", "pdf", "cbr", "cbz"]
  private var pending: FlutterResult?
  private var activeFolder: URL?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.quill/folders", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(QuillFolders(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "pick": pick(result)
    case "hasAccess": result(resolve(args?["uri"] as? String) != nil)
    case "scan":
      guard let folder = resolve(args?["uri"] as? String) else {
        result(FlutterError(code: "scan", message: "Folder access was lost. Select Books again to reconnect.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let files = Self.scan(folder)
        DispatchQueue.main.async { result(files) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A folder picker is already open.", details: nil))
      return
    }
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
      result(FlutterError(code: "pick", message: "No window to show the folder picker.", details: nil))
      return
    }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    root.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else { result(nil); return }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
      result(url.absoluteString)
    } catch {
      result(FlutterError(code: "pick", message: "Unable to keep access to this folder.", details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  // Resolves the saved bookmark and keeps the folder open for the rest of the session.
  private func resolve(_ uri: String?) -> URL? {
    if let active = activeFolder { return active }
    guard uri?.isEmpty == false, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
          url.startAccessingSecurityScopedResource() else { return nil }
    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
    }
    activeFolder = url
    return url
  }

  private static func scan(_ folder: URL) -> [[String: Any]] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
    guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return [] }
    var found: [[String: Any]] = []
    let rootPath = folder.standardizedFileURL.path
    for case let url as URL in walker {
      guard extensions.contains(url.pathExtension.lowercased()),
            let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory != true else { continue }
      let parent = url.deletingLastPathComponent().standardizedFileURL.path
      let relative = parent.hasPrefix(rootPath) ? String(parent.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : ""
      found.append([
        "uri": url.absoluteString,
        "name": url.lastPathComponent,
        "folder": relative,
        "size": values.fileSize ?? 0,
        "modified": Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000),
      ])
    }
    return found
  }
}

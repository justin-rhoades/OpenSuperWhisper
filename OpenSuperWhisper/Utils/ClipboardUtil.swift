import Cocoa
import Carbon

enum ClipboardUtil {
    /// Copies text to the clipboard. Used only as an optional independent stash;
    /// insertion into the focused app is done by `TextInserter`, not the clipboard.
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Clipboard save / restore

    /// Raw snapshot of the system clipboard at a point in time. All item data is
    /// copied out as `Data` so the original pasteboard items can be freed.
    struct Snapshot: @unchecked Sendable {
        fileprivate let itemData: [[(NSPasteboard.PasteboardType, Data)]]
    }

    /// Captures the current clipboard so it can be restored after a paste.
    static func snapshot() -> Snapshot {
        let pb = NSPasteboard.general
        let captured = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
        return Snapshot(itemData: captured)
    }

    /// Writes `saved` back to the clipboard, but only if the clipboard currently holds
    /// `expectedText` — skips the restore if the user manually copied something else
    /// during the delay window.
    static func restore(_ saved: Snapshot, ifClipboardContains expectedText: String) {
        let pb = NSPasteboard.general
        guard pb.string(forType: .string) == expectedText else { return }
        pb.clearContents()
        guard !saved.itemData.isEmpty else { return }
        let items: [NSPasteboardItem] = saved.itemData.map { pairs in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }

    // MARK: - Input source helpers (used by keyboard-layout tests)

    static func getCurrentInputSourceID() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    static func switchToInputSource(withID targetID: String) -> Bool {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        for source in sourceList {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            if sourceID.contains(targetID) || targetID.contains(sourceID) || sourceID == targetID {
                let result = TISSelectInputSource(source)
                usleep(100000) // 100ms delay for layout switch
                return result == noErr
            }
        }
        return false
    }

    static func getAvailableInputSources() -> [String] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        var result: [String] = []
        for source in sourceList {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
            else { continue }

            let isSelectable = unsafeBitCast(selectablePtr, to: CFBoolean.self) == kCFBooleanTrue
            if isSelectable {
                let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                result.append(sourceID)
            }
        }
        return result
    }
}

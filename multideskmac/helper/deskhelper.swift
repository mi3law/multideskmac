// deskhelper — reports desktops (Spaces) and the windows on each of them as JSON.
// Hammerspoon only sees windows on the current desktop, so spaces.lua and chrome.lua use this.
//
//   deskhelper state          displays, their desktops, and every normal window with its desktop(s)
//   deskhelper axwindows PID [WID...]
//                             titles of an app's standard windows on *all* desktops, searching until
//                             the given windows (default: all its large ones) are found. Uses
//                             Accessibility, inherited from Hammerspoon when launched by it.
import AppKit
import ApplicationServices
import Foundation

let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func sym<T>(_ name: String, _: T.Type) -> T { unsafeBitCast(dlsym(sky, name)!, to: T.self) }

let mainConnection = sym("SLSMainConnectionID", (@convention(c) () -> Int32).self)
let copyManagedDisplaySpaces = sym("SLSCopyManagedDisplaySpaces", (@convention(c) (Int32) -> CFArray).self)
let copySpacesForWindows = sym("SLSCopySpacesForWindows", (@convention(c) (Int32, Int32, CFArray) -> CFArray).self)

func emit(_ obj: Any) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func state() {
    let cid = mainConnection()
    var displays: [[String: Any]] = []
    for d in copyManagedDisplaySpaces(cid) as? [[String: Any]] ?? [] {
        let spaces = (d["Spaces"] as? [[String: Any]] ?? []).map { s -> [String: Any] in
            ["id": s["ManagedSpaceID"] ?? 0, "type": s["type"] ?? 0]
        }
        let current = (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] ?? 0
        displays.append(["uuid": d["Display Identifier"] ?? "", "current": current, "spaces": spaces])
    }

    let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var windows: [[String: Any]] = []
    for w in info {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let wid = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { continue }
        let spaces = copySpacesForWindows(cid, 0x7, [wid] as CFArray) as? [Int] ?? []
        if spaces.isEmpty { continue } // off-desktop helper windows
        windows.append([
            "id": wid,
            "pid": w[kCGWindowOwnerPID as String] ?? 0,
            "app": w[kCGWindowOwnerName as String] ?? "",
            "x": b["X"] ?? 0, "y": b["Y"] ?? 0, "w": b["Width"] ?? 0, "h": b["Height"] ?? 0,
            "alpha": w[kCGWindowAlpha as String] ?? 1,
            "onscreen": w[kCGWindowIsOnscreen as String] ?? false,
            "spaces": spaces,
        ])
    }
    emit(["displays": displays, "windows": windows])
}

// AX only lists windows on the current desktop. Elements for windows elsewhere can be built from
// a remote token (the approach AltTab uses): 20 bytes = pid, 0, "coco", element id.
typealias CreateWithToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
let hiServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_NOW)
let axCreateWithToken = unsafeBitCast(dlsym(hiServices, "_AXUIElementCreateWithRemoteToken"), to: CreateWithToken?.self)
let axGetWindow = unsafeBitCast(dlsym(hiServices, "_AXUIElementGetWindow"), to: GetWindow.self)

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func axWindows(pid: pid_t, wanted: [CGWindowID]) {
    guard AXIsProcessTrusted() else { emit(["error": "accessibility not granted"]); exit(2) }
    // Windows we expect to find: the requested ones, else the app's large windows on some desktop.
    let cid = mainConnection()
    let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var expected = Set<CGWindowID>()
    for w in info where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let wid = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              (b["Width"] ?? 0) >= 200, (b["Height"] ?? 0) >= 150,
              !(copySpacesForWindows(cid, 0x7, [wid] as CFArray) as? [Int] ?? []).isEmpty else { continue }
        expected.insert(CGWindowID(wid))
    }
    if !wanted.isEmpty { expected = Set(wanted) }

    var found: [CGWindowID: AXUIElement] = [:]
    var seen = Set<CGWindowID>()
    let app = AXUIElementCreateApplication(pid)
    for w in attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        var wid: CGWindowID = 0
        if axGetWindow(w, &wid) == .success {
            seen.insert(wid)
            if (attr(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole { found[wid] = w }
        }
    }
    // Element IDs grow over the app's lifetime (Chrome's reach the thousands), so keep going until
    // every expected window is accounted for, within a time budget.
    if let create = axCreateWithToken, !expected.isSubset(of: seen) {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        let deadline = Date().addingTimeInterval(1.5)
        var elementID: UInt64 = 0
        while elementID < 100_000 && !expected.isSubset(of: seen) && Date() < deadline {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            elementID += 1
            guard let el = create(token as CFData)?.takeRetainedValue(),
                  (attr(el, kAXRoleAttribute) as? String) == kAXWindowRole else { continue }
            var wid: CGWindowID = 0
            guard axGetWindow(el, &wid) == .success else { continue }
            seen.insert(wid)
            if (attr(el, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole { found[wid] = el }
        }
    }
    emit([
        "windows": found.map { wid, el in ["id": Int(wid), "title": attr(el, kAXTitleAttribute) as? String ?? ""] },
        "missing": expected.subtracting(Set(found.keys)).map { Int($0) },
    ])
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "state": state()
case "axwindows" where args.count > 2:
    axWindows(pid: pid_t(args[2]) ?? 0, wanted: args.dropFirst(3).compactMap { CGWindowID($0) })
default:
    FileHandle.standardError.write("usage: deskhelper state | axwindows PID [WID...]\n".data(using: .utf8)!)
    exit(64)
}

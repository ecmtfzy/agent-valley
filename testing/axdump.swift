// Prints what a screen reader is told about the test copy's windows: one line per element with
// its role, label, value, help, whether it is the one selected, and whether it can be pressed.
// Stands in for VoiceOver, which an agent cannot listen to. Run: swift testing/axdump.swift
// With a process id after it, the windows of that process: how testing/pictures.sh reads the
// panel it draws off the screen.
import AppKit
import ApplicationServices

func text(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    if let string = value as? String { return string.isEmpty ? nil : string }
    return (value as? NSNumber)?.stringValue
}

/// The tree an app reports can lead back up: on 2026-10-16 the test copy's application listed
/// itself among its own children, and the dump ran to gigabytes. An element already above is
/// not walked again, and no walk goes deeper than any panel is.
let deepest = 64

func dump(_ element: AXUIElement, depth: Int, above: [AXUIElement] = []) {
    var parts = [text(element, kAXRoleAttribute) ?? "?"]
    for (key, name) in [("label", kAXDescriptionAttribute), ("title", kAXTitleAttribute), ("value", kAXValueAttribute), ("help", kAXHelpAttribute)] {
        if let string = text(element, name) { parts.append("\(key)=\"\(string)\"") }
    }
    if text(element, kAXSelectedAttribute) == "1" { parts.append("[selected]") }
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success, (actions as? [String])?.contains(kAXPressAction) == true {
        parts.append("[press]")
    }
    print(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
    var children: CFTypeRef?
    guard depth < deepest, AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let list = children as? [AXUIElement] else { return }
    let path = above + [element]
    for child in list where !path.contains(where: { CFEqual($0, child) }) { dump(child, depth: depth + 1, above: path) }
}

guard AXIsProcessTrusted() else {
    print("This terminal has no Accessibility permission.")
    exit(1)
}
if CommandLine.arguments.count > 1 {
    guard let pid = pid_t(CommandLine.arguments[1]) else {
        print("usage: swift testing/axdump.swift [process id]")
        exit(2)
    }
    dump(AXUIElementCreateApplication(pid), depth: 0)
    exit(0)
}
let id = "com.morsechimwai.agent-valley.test-copy"
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) else {
    print("The test copy is not running. Name the process instead: swift testing/axdump.swift <process id>")
    exit(1)
}
dump(AXUIElementCreateApplication(app.processIdentifier), depth: 0)

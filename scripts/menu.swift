// Drives OpenRecord's menu bar item through the Accessibility API, for end-to-end checks.
// usage: swift scripts/menu.swift list | open | press "<menu item title prefix>" | hotkey
// The calling terminal needs Accessibility permission.
import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func title(_ element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute) as? String ?? ""
}

func menuItems(_ element: AXUIElement, depth: Int = 0) -> [(AXUIElement, String, Int)] {
    children(element).flatMap { child -> [(AXUIElement, String, Int)] in
        let role = attribute(child, kAXRoleAttribute) as? String ?? ""
        let own = role == kAXMenuItemRole ? [(child, title(child), depth)] : []
        return own + menuItems(child, depth: role == kAXMenuItemRole ? depth + 1 : depth)
    }
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "io.github.dorukgunes.openrecord" }) else {
    fatalError("OpenRecord is not running")
}
let command = CommandLine.arguments.dropFirst().first ?? "list"

if command == "hotkey" {
    let source = CGEventSource(stateID: .hidSystemState)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0x0F, keyDown: keyDown)!
        event.flags = [.maskControl, .maskAlternate, .maskCommand]
        event.post(tap: .cghidEventTap)
        // Exiting right after posting can drop the synthesized events.
        Thread.sleep(forTimeInterval: 0.2)
    }
    print("sent ⌃⌥⌘R")
    exit(0)
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)
guard let extras = attribute(axApp, "AXExtrasMenuBar"), let statusItem = children(extras as! AXUIElement).first else {
    fatalError("OpenRecord has no menu bar item")
}
AXUIElementPerformAction(statusItem, kAXPressAction as CFString)
Thread.sleep(forTimeInterval: 0.5)
let items = menuItems(statusItem)

switch command {
case "list":
    for (item, title, depth) in items where !title.isEmpty {
        let checked = (attribute(item, "AXMenuItemMarkChar") as? String).map { _ in " ✓" } ?? ""
        print(String(repeating: "  ", count: depth) + title + checked)
    }
    AXUIElementPerformAction(statusItem, kAXCancelAction as CFString)
case "open":
    print("menu left open")
case "press":
    let prefix = CommandLine.arguments[2]
    guard let (item, title, _) = items.first(where: { $0.1.hasPrefix(prefix) }) else {
        AXUIElementPerformAction(statusItem, kAXCancelAction as CFString)
        fatalError("No menu item starting with \(prefix)")
    }
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    print("pressed \(title)")
default:
    fatalError("unknown command \(command)")
}

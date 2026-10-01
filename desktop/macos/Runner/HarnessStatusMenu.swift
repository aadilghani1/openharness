import Cocoa
import CoreText

/// Unread conversations in the system menu bar. Dart owns the
/// unread ledger and navigation; AppKit only presents a snapshot and its receipts.
final class HarnessStatusMenu: NSObject, NSMenuDelegate {
  let menu = NSMenu(title: "Harness")
  private(set) var statusItem: NSStatusItem?
  private var entries: [[String: Any]] = []
  private var working: [[String: Any]] = []
  private var workingExpanded = false
  private var workingItems: [NSMenuItem] = []
  private var keymap: HarnessNativeKeymap?
  private var keyContext = "workspace"
  private var menuKeys: Any?
  private var enabled = false
  private var workspaceAvailable = false
  private var tracking = false
  private var dirty = true
  private let showWindow: () -> Void
  private let emit: (String, Any?) -> Void

  init(installStatusItem: Bool = true, showWindow: @escaping () -> Void,
       emit: @escaping (String, Any?) -> Void) {
    self.showWindow = showWindow
    self.emit = emit
    super.init()
    menu.autoenablesItems = false
    menu.delegate = self
    if installStatusItem {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      statusItem = item
      item.menu = menu
      item.button?.imagePosition = .imageOnly
      item.button?.setAccessibilityLabel("Harness notifications")
    }
    update([:])
  }

  deinit {
    if let menuKeys { NSEvent.removeMonitor(menuKeys) }
    if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
  }

  func update(_ state: [String: Any]) {
    let nextEnabled = state["enabled"] as? Bool == true
    let nextAvailable = state["statusMenuEntries"] != nil
    let nextEntries = (state["statusMenuEntries"] as? [[String: Any]] ?? [])
      .filter { $0["unread"] as? Bool == true }
    let nextWorking = state["statusMenuWorkingEntries"] as? [[String: Any]] ?? []
    guard dirty || enabled != nextEnabled || workspaceAvailable != nextAvailable ||
          !NSArray(array: entries).isEqual(to: nextEntries) ||
          !NSArray(array: working).isEqual(to: nextWorking) else { return }
    enabled = nextEnabled
    workspaceAvailable = nextAvailable
    entries = nextEntries
    working = nextAvailable ? nextWorking : []
    if !workspaceAvailable { workingExpanded = false }
    let count = entries.count
    statusItem?.button?.image = Self.badgeImage(logo: NSImage(named: "HarnessStatusIcon"),
                                              count: workspaceAvailable ? count : nil)
    statusItem?.button?.toolTip = workspaceAvailable ? "Harness · \(count) unread" : "Harness"
    statusItem?.button?.setAccessibilityValue("\(count) unread")
    dirty = true
    // Never move a conversation out from under the pointer. Stale actions are
    // revalidated against `entries`, even while the displayed menu stays still.
    if !tracking { rebuild() }
    if !workspaceAvailable { menu.cancelTracking() }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === self.menu && !tracking && dirty { rebuild() }
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    if dirty { rebuild() }
    refreshTimes()
    tracking = true
    if menuKeys == nil {
      menuKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.tracking, let item = self.menu.highlightedItem,
              self.handleWorkingKey(event, item: item) else { return event }
        return nil
      }
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    tracking = false
    if let menuKeys { NSEvent.removeMonitor(menuKeys); self.menuKeys = nil }
    // AppKit dispatches the selected item after closing. Rebuild on next open
    // or update so its receipt remains the snapshot the person selected.
  }

  /// AppKit normally closes a menu on Return. This disclosure stays open for
  /// keyboard users too; all other keys keep native menu navigation.
  func handleWorkingKey(_ event: NSEvent, item: NSMenuItem) -> Bool {
    guard item.menu === menu, item.identifier?.rawValue == "toggleWorking", item.isEnabled,
          event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
          let row = item.view as? HarnessStatusMenuRow else { return false }
    switch event.keyCode {
    case 36, 76, 49: return row.accessibilityPerformPress() // Return, keypad Enter, Space
    case 124: // Right opens; Left closes an already expanded section.
      if !workingExpanded { _ = row.accessibilityPerformPress() }
      return true
    case 123 where workingExpanded: return row.accessibilityPerformPress()
    default: return false
    }
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    for row in menu.items {
      (row.view as? HarnessStatusMenuRow)?.highlighted = row === item
    }
  }

  func updateKeymap(_ map: HarnessNativeKeymap, context: String) {
    keymap = map
    keyContext = context
    map.applyMenuKeys(to: menu, context: context)
  }

  private func refreshTimes() {
    for item in menu.items {
      (item.view as? HarnessStatusMenuRow)?.refreshTime()
      for child in item.submenu?.items ?? [] {
        (child.view as? HarnessStatusMenuRow)?.refreshTime()
      }
    }
  }

  private func rebuild() {
    dirty = false
    menu.removeAllItems()
    workingItems.removeAll()
    if working.isEmpty { workingExpanded = false }
    menu.minimumWidth = 360
    let clear = add("Mark all read", "clearStatusNotifications", enabled: enabled && !entries.isEmpty)
    clear.representedObject = entries
    clear.view = HarnessStatusMenuRow(item: clear, heading: "Notifications (\(entries.count))")
    if entries.isEmpty {
      let empty = NSMenuItem(title: workspaceAvailable ? "No unread notifications" : "Open Harness to get started",
                            action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      for entry in entries.prefix(5) { addSession(entry, to: menu) }
      if entries.count > 5 {
        add("View all \(entries.count) notifications…", "notificationInbox", enabled: enabled)
      }
    }
    if workspaceAvailable {
      menu.addItem(.separator())
      let toggle = add("Working (\(working.count))", "toggleWorking", enabled: !working.isEmpty)
      toggle.view = HarnessStatusMenuRow(item: toggle, expanded: workingExpanded)
      for entry in working.prefix(5) {
        workingItems.append(addSession(entry, to: menu))
      }
      if working.count > 5 {
        let more = add("More working sessions (\(working.count - 5))", "moreWorking", enabled: enabled)
        let submenu = NSMenu(title: "Working")
        submenu.autoenablesItems = false
        submenu.delegate = self
        for entry in working.dropFirst(5) { addSession(entry, to: submenu) }
        more.submenu = submenu
        workingItems.append(more)
      }
      for item in workingItems { item.isHidden = !workingExpanded }
    }
    menu.addItem(.separator())
    add("New Harness…", HarnessKeymapMenu.actionPrefix + "newAgent", enabled: enabled)
    add("Open Harness…", HarnessKeymapMenu.actionPrefix + "addAgent", enabled: enabled)
    menu.addItem(.separator())
    add("Show Harness", "openWindow")
    add("Quit", "quit")
    keymap?.applyMenuKeys(to: menu, context: keyContext)
  }

  @discardableResult private func addSession(_ entry: [String: Any], to destination: NSMenu) -> NSMenuItem {
    let title = entry["title"] as? String ?? "Unavailable harness"
    let item = NSMenuItem(title: compact(title), action: #selector(selected(_:)), keyEquivalent: "")
    item.identifier = NSUserInterfaceItemIdentifier("openStatusHarness")
    item.target = self
    item.isEnabled = enabled && entry["unavailable"] as? String == nil
    item.representedObject = entry
    item.view = HarnessStatusMenuRow(item: item, entry: entry)
    destination.addItem(item)
    return item
  }

  @discardableResult private func add(_ title: String, _ action: String, enabled: Bool = true) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(selected(_:)), keyEquivalent: "")
    item.identifier = NSUserInterfaceItemIdentifier(action)
    item.target = self
    item.isEnabled = enabled
    menu.addItem(item)
    return item
  }

  @objc private func selected(_ item: NSMenuItem) {
    guard item.isEnabled, let identifier = item.identifier?.rawValue else { return }
    let action = identifier.hasPrefix(HarnessKeymapMenu.actionPrefix)
      ? String(identifier.dropFirst(HarnessKeymapMenu.actionPrefix.count)) : identifier
    switch action {
    case "openWindow": showWindow()
    case "quit": NSApp.terminate(nil)
    case "toggleWorking":
      workingExpanded.toggle()
      (item.view as? HarnessStatusMenuRow)?.expanded = workingExpanded
      // Expand the already displayed snapshot. New arrivals and their receipts
      // stay deferred until the next opening, just like the notification rows.
      for row in workingItems { row.isHidden = !workingExpanded }
      menu.update()
    case "openStatusHarness":
      guard enabled, let receipt = item.representedObject as? [String: Any],
            (receipt["unread"] as? Bool == true ? entries : working).contains(where: {
              sameReceipt($0, receipt) && $0["unavailable"] as? String == nil
            }) else { return }
      // Dart opens the destination before revealing the window, so activating
      // the previously selected tab cannot acknowledge the wrong notification.
      emit(action, receipt)
    case "clearStatusNotifications":
      guard enabled, let receipts = item.representedObject as? [[String: Any]] else { return }
      emit(action, ["receipts": receipts])
    default:
      guard enabled else { return }
      showWindow()
      emit(action, nil)
    }
  }

  private func sameReceipt(_ current: [String: Any], _ displayed: [String: Any]) -> Bool {
    ["machineId", "agentId", "sessionId", "readToken", "questionId"].allSatisfy {
      current[$0] as? String == displayed[$0] as? String
    }
  }

  private func compact(_ text: String) -> String {
    let line = text.components(separatedBy: .newlines).joined(separator: " ")
    return line.count > 56 ? String(line.prefix(55)) + "…" : line
  }

  /// A single template mask lets AppKit tint the logo and badge together for
  /// the menu bar's appearance and selection. Clear digits and a small halo
  /// keep the overlapping badge legible without painting a fixed background.
  private static func badgeImage(logo: NSImage?, count: Int?) -> NSImage {
    let label: String
    if let count, count > 0 {
      label = count > 99 ? "99+" : String(count)
    } else {
      label = ""
    }
    let image = NSImage(size: NSSize(width: 28, height: 22), flipped: false) { bounds in
      // Balance the portrait's fine cutouts against neighboring system symbols.
      logo?.draw(in: NSRect(x: label.isEmpty ? (bounds.width - 17) / 2 : 2, y: label.isEmpty ? 2.5 : 4,
                           width: 17, height: 17))
      if !label.isEmpty, let context = NSGraphicsContext.current?.cgContext {
        let badge = NSRect(x: bounds.maxX - 15, y: 0.5, width: 12.5, height: 12.5)
        context.saveGState()
        context.setBlendMode(.clear)
        context.fillEllipse(in: badge.insetBy(dx: -0.75, dy: -0.75))
        context.restoreGState()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let size: CGFloat = label.count == 1 ? 9.5 : label.count == 2 ? 8.5 : 6.5
        let text = NSAttributedString(string: label, attributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
          .foregroundColor: NSColor.black,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.textPosition = NSPoint(x: badge.midX - ink.midX, y: badge.midY - ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = count.map { "\($0) unread" } ?? "Harness"
    return image
  }

}

/// Rich rows keep NSMenuItem's native keyboard/type-select actions, just like
/// the History menu. All clicks and VoiceOver presses use the same receipt.
private final class HarnessStatusMenuRow: NSView {
  private weak var item: NSMenuItem?
  private let entry: [String: Any]?
  private let heading: String?
  private var time = ""
  var highlighted = false { didSet { needsDisplay = true } }
  var expanded: Bool? { didSet { updateAccessibility(); needsDisplay = true } }
  override var isFlipped: Bool { true }

  init(item: NSMenuItem, entry: [String: Any]? = nil, heading: String? = nil, expanded: Bool? = nil) {
    self.item = item
    self.entry = entry
    self.heading = heading
    self.expanded = expanded
    let unread = entry?["unread"] as? Bool == true
    let message = entry?["message"] as? String ?? ""
    let measured = (message as NSString).boundingRect(with: NSSize(width: 316, height: 1000),
      options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let messageHeight = message.isEmpty ? 0 : min(32, ceil(measured.height)) + 2
    let height: CGFloat = entry == nil ? 32 : unread ? 64 + messageHeight : 44
    super.init(frame: NSRect(x: 0, y: 0, width: 360, height: height))
    autoresizingMask = [.width]
    setAccessibilityElement(true)
    setAccessibilityRole(.menuItem)
    refreshTime()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    highlighted = false
    refreshTime()
  }

  func refreshTime() {
    time = ""
    if let entry {
      let unread = entry["unread"] as? Bool == true
      if let stamp = entry[unread ? "receivedAt" : "startedAt"] as? NSNumber {
        let age = max(0, Int(Date().timeIntervalSince1970 - stamp.doubleValue / 1000))
        if age < 60 { time = unread ? "now" : "\(age)s" }
        else if age < 3600 { time = "\(age / 60)m" }
        else if age < 86400 { time = "\(age / 3600)h" }
        else { time = "\(age / 86400)d" }
        if unread && age >= 60 { time += " ago" }
      }
    }
    updateAccessibility()
    needsDisplay = true
  }

  private var context: String {
    guard let entry else { return "" }
    return [entry["tabName"] as? String, entry["machineName"] as? String,
            entry["unavailable"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private func updateAccessibility() {
    guard let item else { return }
    let text: String
    if let entry {
      text = [entry["title"] as? String, entry["label"] as? String, entry["message"] as? String,
              context, time, entry["unread"] as? Bool == true ? "Unread" : nil]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
      toolTip = [text, entry["detail"] as? String].compactMap { $0 }.joined(separator: " · ")
    } else if let expanded {
      text = "\(item.title), \(expanded ? "expanded" : "collapsed")"
      setAccessibilityExpanded(expanded)
      toolTip = expanded ? "Hide working sessions" : "Show working sessions"
    } else {
      text = "\(heading ?? "Notifications"), Mark all read"
      toolTip = "Mark these notifications as read. Pending questions stay unanswered."
    }
    setAccessibilityLabel(text)
    setAccessibilityEnabled(item.isEnabled)
    item.setAccessibilityLabel(text)
    item.toolTip = toolTip
  }

  private var clearRect: NSRect {
    NSRect(x: bounds.width - 110, y: 2, width: 102, height: bounds.height - 4)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let item else { return }
    let selected = highlighted && item.isEnabled
    if selected {
      NSColor.selectedContentBackgroundColor.setFill()
      NSBezierPath(roundedRect: heading == nil ? bounds.insetBy(dx: 4, dy: 2) : clearRect,
                   xRadius: 5, yRadius: 5).fill()
    }
    let primary: NSColor = !item.isEnabled ? .disabledControlTextColor
      : selected ? .selectedMenuItemTextColor : .labelColor
    let secondary: NSColor = !item.isEnabled ? .disabledControlTextColor
      : selected ? .selectedMenuItemTextColor : .secondaryLabelColor
    if let heading {
      text(heading, x: 16, y: 8, width: clearRect.minX - 20, height: 18,
           size: 12, weight: .medium, color: .secondaryLabelColor)
      text("Mark all read", x: clearRect.minX, y: 8, width: clearRect.width, height: 18,
           size: 12, color: !item.isEnabled ? .disabledControlTextColor
             : selected ? .selectedMenuItemTextColor : .labelColor, alignment: .center)
      return
    }
    if let expanded {
      if item.isEnabled, let icon = HarnessControlSymbols.image(expanded ? "chevron.down" : "chevron.right")?.copy() as? NSImage {
        icon.lockFocus()
        primary.set()
        NSRect(origin: .zero, size: icon.size).fill(using: .sourceAtop)
        icon.unlockFocus()
        let scale = min(16 / icon.size.width, 16 / icon.size.height)
        let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
        icon.draw(in: NSRect(x: 11 + (16 - size.width) / 2, y: 8 + (16 - size.height) / 2,
                            width: size.width, height: size.height),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      }
      text(item.title, x: 34, y: 7, width: bounds.width - 50, height: 20, color: primary)
      return
    }
    guard let entry else { return }
    let unread = entry["unread"] as? Bool == true
    let message = entry["message"] as? String ?? ""
    if unread {
      (selected ? NSColor.selectedMenuItemTextColor : NSColor.systemBlue).setFill()
      NSBezierPath(ovalIn: NSRect(x: 13, y: 13, width: 6, height: 6)).fill()
    }
    text(entry["title"] as? String ?? item.title, x: 28, y: 6,
         width: bounds.width - 111, height: 19, weight: unread ? .semibold : .regular, color: primary)
    text(time, x: bounds.width - 78, y: 8, width: 62, height: 17,
         size: 12, color: secondary, alignment: .right)
    if unread {
      text(entry["label"] as? String ?? "", x: 28, y: 26, width: bounds.width - 44,
           height: 17, size: 12, color: secondary)
      if !message.isEmpty {
        text(message, x: 28, y: 43, width: bounds.width - 44, height: 32, color: primary, multiline: true)
      }
    }
    text(context, x: 28, y: bounds.height - 20, width: bounds.width - 44, height: 17,
         size: 12, color: secondary)
  }

  private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                    size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor,
                    alignment: NSTextAlignment = .left, multiline: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = multiline ? .byWordWrapping : .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph,
    ]
    (value as NSString).draw(with: NSRect(x: x, y: y, width: max(0, width), height: height),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
  }

  override func resetCursorRects() {
    if item?.isEnabled == true { addCursorRect(heading == nil ? bounds : clearRect, cursor: .pointingHand) }
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard (heading == nil ? bounds : clearRect).contains(point) else { return }
    activate()
  }

  override func accessibilityPerformPress() -> Bool { activate() }
  @discardableResult private func activate() -> Bool {
    guard let item, item.isEnabled, let menu = item.menu else { return false }
    let index = menu.index(of: item)
    guard index >= 0 else { return false }
    if expanded == nil { menu.cancelTracking() }
    menu.performActionForItem(at: index)
    return true
  }
}

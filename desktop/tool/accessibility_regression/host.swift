// Appended only to the runner's disposable macOS host. Production uses no
// private Flutter selectors. This fixture toggles the engine's existing setter
// to reproduce the accessibility bridge recreation normally driven by macOS.
private enum AccessibilityRegression {
  static func install(window: NSWindow, controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "harness/accessibility_regression", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak window, weak controller] call, result in
      guard let window = window, let controller = controller else {
        result(FlutterError(code: "missing_window", message: nil, details: nil))
        return
      }
      switch call.method {
      case "semantics":
        guard let enabled = call.arguments as? Bool,
          controller.engine.responds(to: NSSelectorFromString("setSemanticsEnabled:")) else {
          result(FlutterError(code: "unsupported_engine", message: nil, details: nil))
          return
        }
        controller.engine.setValue(enabled, forKey: "semanticsEnabled")
        result(nil)
      case "resize":
        let step = call.arguments as! Int
        window.setContentSize(NSSize(width: 700 + (step % 3) * 70, height: 500 + (step % 4) * 50))
        result(nil)
      case "increment":
        var seen = Set<ObjectIdentifier>()
        var sliders = [NSObject]()
        func visit(_ value: Any) {
          guard let node = value as? NSAccessibilityProtocol,
            let object = value as? NSObject else { return }
          guard seen.insert(ObjectIdentifier(node as AnyObject)).inserted else { return }
          if node.accessibilityRole() == .slider { sliders.append(object) }
          for child in node.accessibilityChildren() ?? [] { visit(child) }
        }
        visit(controller.view)
        guard sliders.count == 1 else {
          result(FlutterError(code: "slider_count", message: "Expected 1 visible slider, found \(sliders.count)", details: nil))
          return
        }
        // Flutter's AXPlatformNodeCocoa implements the legacy AppKit action
        // entry point; this is also what macOS accessibility clients invoke.
        let slider = sliders[0]
        guard slider.accessibilityActionNames().contains(.increment) else {
          result(false)
          return
        }
        slider.accessibilityPerformAction(.increment)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

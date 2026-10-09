import Cocoa
import FlutterMacOS

// 声明 AppDelegate 类以便访问
@objc protocol AppDelegateProtocol {
  func checkAndSetupStatusBar()
}

class MainFlutterWindow: NSWindow {
  var windowDelegate: WindowDelegate?
  /// 原生 → Flutter 事件通道（全屏状态等）。与 cn.dlrow.keycore/window 分开，避免 Dart 侧多个 handler 互相覆盖。
  var eventsChannel: FlutterMethodChannel?
  private var chromeObservers: [NSObjectProtocol] = []

  /// v3 顶栏高度：红绿灯在其中垂直居中（form_v3.md §10）
  static let kBarHeight: CGFloat = 52

  /// 把三个红绿灯移到 52px 顶栏中垂直居中。
  /// 公式同 VS Code：y = floor((52 − h) / 2)，x = y + 1。AppKit 在 resize / 全屏 / 激活时会复位，需要反复调用。
  func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen),
          let close = standardWindowButton(.closeButton),
          let mini = standardWindowButton(.miniaturizeButton),
          let zoom = standardWindowButton(.zoomButton),
          let container = close.superview?.superview else { return }
    let barHeight = MainFlutterWindow.kBarHeight
    let h = close.frame.height
    let y = floor((barHeight - h) / 2)
    let x = y + 1
    var r = container.frame
    r.size.height = barHeight
    r.origin.y = frame.height - barHeight
    container.frame = r
    let gap = mini.frame.minX - close.frame.minX
    let step = gap > 0 ? gap : 20
    for (i, b) in [close, mini, zoom].enumerated() {
      b.setFrameOrigin(NSPoint(x: x + CGFloat(i) * step, y: y))
    }
  }

  private func installChromeObservers() {
    let nc = NotificationCenter.default
    let relayout: (Notification) -> Void = { [weak self] _ in self?.layoutTrafficLights() }
    for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                 NSWindow.didResignKeyNotification, NSWindow.didEndLiveResizeNotification,
                 NSWindow.didChangeBackingPropertiesNotification] {
      chromeObservers.append(nc.addObserver(forName: name, object: self, queue: .main, using: relayout))
    }
    chromeObservers.append(nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.eventsChannel?.invokeMethod("fullscreenChanged", arguments: true)
    })
    chromeObservers.append(nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.layoutTrafficLights()
      self?.eventsChannel?.invokeMethod("fullscreenChanged", arguments: false)
    })
  }

  override var title: String {
    didSet { layoutTrafficLights() }
  }
  
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // 窗口创建后立即注册 MethodChannel（确保 FlutterViewController 存在）
    setupMethodChannel(flutterViewController: flutterViewController)

    // 设置最小窗口尺寸
    self.minSize = NSSize(width: 800, height: 600)
    
    // macOS 26 风格：沉浸式标题栏（标题与界面融为一体）
    // 1. 使标题栏透明
    self.titlebarAppearsTransparent = true
    // 2. 隐藏标题文本
    self.titleVisibility = .hidden
    // 3. 允许通过窗口背景拖动窗口
    self.isMovableByWindowBackground = true
    // 4. 设置全尺寸内容视图，让内容延伸到标题栏区域
    self.styleMask.insert(.fullSizeContentView)
    // 5. 移除标题栏的阴影效果
    self.hasShadow = true
    
    // 设置窗口关闭行为（保存 delegate 引用避免被释放）
    windowDelegate = WindowDelegate()
    self.delegate = windowDelegate

    eventsChannel = FlutterMethodChannel(
      name: "cn.dlrow.keycore/window_events",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    installChromeObservers()

    super.awakeFromNib()
    layoutTrafficLights()
  }
  
  func setupMethodChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "cn.dlrow.keycore/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      // 窗口外观相关的方法直接在窗口上处理
      switch call.method {
      case "performDrag":
        if let event = NSApp.currentEvent { self?.performDrag(with: event) }
        result(nil)
        return
      case "titleBarDoubleClick":
        // 尊重系统「双击标题栏」偏好：Minimize / Maximize(zoom) / None
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        if action == "Minimize" { self?.miniaturize(nil) } else if action != "None" { self?.zoom(nil) }
        result(nil)
        return
      case "isFullScreen":
        result(self?.styleMask.contains(.fullScreen) ?? false)
        return
      default:
        break
      }
      // 获取 AppDelegate 来处理调用
      guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
        result(FlutterMethodNotImplemented)
        return
      }
      
      // 调用 AppDelegate 的处理方法
      appDelegate.handleMethodCall(call, result: result)
    }
  }
  
  override func close() {
    // 检查是否启用了最小化到状态栏
    let userDefaults = UserDefaults.standard
    let shouldMinimizeToTray = userDefaults.bool(forKey: "minimize_to_tray")
    
    if shouldMinimizeToTray {
      // 隐藏窗口到状态栏而不是关闭或最小化到 Dock
      // 使用 orderOut 隐藏窗口，不会最小化到 Dock
      // 注意：状态栏图标应该在开启设置时就已创建，不需要在这里创建
      self.orderOut(nil)
    } else {
      // 正常关闭
      super.close()
    }
  }
}

class WindowDelegate: NSObject, NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // 检查是否启用了最小化到状态栏
    let userDefaults = UserDefaults.standard
    let shouldMinimizeToTray = userDefaults.bool(forKey: "minimize_to_tray")
    
    if shouldMinimizeToTray {
      // 隐藏窗口到状态栏，而不是关闭或最小化到 Dock
      // 使用 orderOut 隐藏窗口，不会最小化到 Dock
      // 注意：状态栏图标应该在开启设置时就已创建，不需要在这里创建
      sender.orderOut(nil)
      return false // 阻止窗口关闭
    }
    
    return true // 允许窗口关闭
  }
}

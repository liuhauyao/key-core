import Cocoa
import FlutterMacOS

// 声明 AppDelegate 类以便访问
@objc protocol AppDelegateProtocol {
  func checkAndSetupStatusBar()
}

class MainFlutterWindow: NSWindow {
  var windowDelegate: WindowDelegate?
  
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
    
    super.awakeFromNib()
  }
  
  func setupMethodChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.example.keyCore/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
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

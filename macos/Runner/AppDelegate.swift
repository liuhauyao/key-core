import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, AppDelegateProtocol {
  var statusItem: NSStatusItem?
  var mainWindow: NSWindow?
  var statusBarChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    print("AppDelegate: ========== 应用启动 ==========")
    
    // ⚠️ 关键：必须在 super.applicationDidFinishLaunching 之前恢复权限
    // 因为 super 会启动 Flutter 引擎，Flutter 应用启动后立即会访问文件
    print("AppDelegate: [1/3] 恢复 Security-Scoped Bookmark 访问权限（在 Flutter 启动前）...")
    restoreBookmarkOnLaunch()
    
    print("AppDelegate: [2/3] 启动 Flutter 引擎...")
    super.applicationDidFinishLaunching(notification)
    
    // 激活应用并置于前台
    NSApp.setActivationPolicy(.regular)
    
    // 参考标准 macOS 做法：在应用启动时立即创建状态栏图标
    print("AppDelegate: [3/3] 设置状态栏图标...")
    checkAndSetupStatusBar()
    
    // 立即尝试注册 MethodChannel（不等待窗口创建）
    print("AppDelegate: [4/4] 注册 MethodChannel...")
    setupMethodChannel()
    
    // 延迟激活，确保窗口已创建
    DispatchQueue.main.async { [weak self] in
      NSApp.activate(ignoringOtherApps: true)
      
      // 获取主窗口引用
      if let window = NSApplication.shared.windows.first {
        self?.mainWindow = window
        // 确保窗口显示在前台
        window.makeKeyAndOrderFront(nil)
        print("AppDelegate: ✅ 主窗口已创建并显示")
      }
    }
    
    print("AppDelegate: ========== 应用启动完成 ==========")
  }
  
  func setupMethodChannel() {
    // 使用递归延迟重试，确保 FlutterViewController 已创建
    registerMethodChannel(retryCount: 0, maxRetries: 20)
  }
  
  func registerMethodChannel(retryCount: Int, maxRetries: Int) {
    // 如果已经注册过，跳过
    if statusBarChannel != nil {
      print("AppDelegate: MethodChannel 已注册，跳过")
      return
    }
    
    // 尝试从主窗口获取 FlutterViewController
    var controller: FlutterViewController? = nil
    
    // 首先尝试从已存在的窗口获取
    if let window = NSApplication.shared.windows.first,
       let flutterController = window.contentViewController as? FlutterViewController {
      controller = flutterController
    }
    
    // 如果还没有，尝试从 AppDelegate 的窗口获取
    if controller == nil, let window = mainWindow,
       let flutterController = window.contentViewController as? FlutterViewController {
      controller = flutterController
    }
    
    guard let flutterController = controller else {
      // 如果窗口还未创建，延迟重试
      if retryCount < maxRetries {
        print("AppDelegate: FlutterViewController 未创建，延迟重试 (\(retryCount + 1)/\(maxRetries))...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.registerMethodChannel(retryCount: retryCount + 1, maxRetries: maxRetries)
        }
      } else {
        print("AppDelegate: ❌ 无法获取 FlutterViewController，已达最大重试次数")
      }
      return
    }
    
    print("AppDelegate: ✅ 找到 FlutterViewController，开始注册 MethodChannel...")
    
    let channel = FlutterMethodChannel(
      name: "cn.dlrow.keycore/window",
      binaryMessenger: flutterController.engine.binaryMessenger
    )
    
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleMethodCall(call, result: result)
    }
    
    // 注册文件访问权限相关的 MethodChannel
    let fileAccessChannel = FlutterMethodChannel(
      name: "cn.dlrow.keycore/fileAccess",
      binaryMessenger: flutterController.engine.binaryMessenger
    )
    
    fileAccessChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "saveSecurityScopedBookmark":
        if let args = call.arguments as? [String: Any],
           let path = args["path"] as? String {
          self?.saveSecurityScopedBookmark(path: path, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        }
      case "restoreSecurityScopedBookmark":
        self?.restoreSecurityScopedBookmark(result: result)
      case "hasSecurityScopedBookmark":
        self?.hasSecurityScopedBookmark(result: result)
      case "clearSecurityScopedBookmark":
        self?.clearSecurityScopedBookmark(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // 创建状态栏菜单专用的 MethodChannel
    statusBarChannel = FlutterMethodChannel(
      name: "cn.dlrow.keycore/statusBar",
      binaryMessenger: flutterController.engine.binaryMessenger
    )
    
    print("AppDelegate: ✅ MethodChannel 注册完成")
    
    // statusBarChannel 初始化后，更新状态栏菜单（如果状态栏已存在）
    if statusItem != nil {
      // 延迟更长时间，确保 Flutter 端的 StatusBarMenuBridge.init() 已完成
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.updateStatusBarMenu()
      }
    }
  }
  
  func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "updateWindowTheme" {
      if let args = call.arguments as? [String: Any],
         let themeMode = args["themeMode"] as? String {
        updateWindowTheme(themeMode)
        result(nil)
      } else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      }
    } else if call.method == "updateStatusBar" {
      updateStatusBarIfNeeded()
      result(nil)
    } else if call.method == "syncMinimizeToTray" {
      if let args = call.arguments as? [String: Any],
         let value = args["value"] as? Bool {
        let userDefaults = UserDefaults.standard
        userDefaults.set(value, forKey: "minimize_to_tray")
        checkAndSetupStatusBar()
        result(nil)
      } else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      }
    } else if call.method == "updateStatusBarMenu" {
      updateStatusBarMenu()
      result(nil)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
  
  func updateWindowTheme(_ themeMode: String) {
    guard let window = mainWindow ?? NSApplication.shared.windows.first else { return }
    
    if #available(macOS 10.14, *) {
      let appearance: NSAppearance.Name
      switch themeMode {
      case "dark":
        appearance = .darkAqua
      case "light":
        appearance = .aqua
      case "system":
        // 跟随系统：检测当前系统主题
        if NSApp.effectiveAppearance.name == .darkAqua {
          appearance = .darkAqua
        } else {
          appearance = .aqua
        }
      default:
        // 默认跟随系统
        if NSApp.effectiveAppearance.name == .darkAqua {
          appearance = .darkAqua
        } else {
          appearance = .aqua
        }
      }
      window.appearance = NSAppearance(named: appearance)
    }
  }

  func checkAndSetupStatusBar() {
    // 确保在主线程执行
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.checkAndSetupStatusBar()
      }
      return
    }
    
    // 使用 UserDefaults.standard 而不是 suite name
    let userDefaults = UserDefaults.standard
    
    // 检查设置是否存在，如果不存在则使用默认值 true（首次安装）
    let shouldMinimizeToTray: Bool
    if userDefaults.object(forKey: "minimize_to_tray") != nil {
      // 设置已存在，读取值
      shouldMinimizeToTray = userDefaults.bool(forKey: "minimize_to_tray")
    } else {
      // 设置不存在（首次安装），使用默认值 true
      shouldMinimizeToTray = true
      userDefaults.set(true, forKey: "minimize_to_tray")
    }
    
    // 根据设置决定是否显示状态栏图标
    if shouldMinimizeToTray {
      // 如果应该显示但图标不存在，创建它
      if statusItem == nil {
        setupStatusBar()
      }
    } else {
      // 如果设置关闭，移除状态栏图标
      removeStatusBar()
    }
  }

  func setupStatusBar() {
    // 确保在主线程执行
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.setupStatusBar()
      }
      return
    }
    
    // 如果已经存在，先移除
    if statusItem != nil {
      removeStatusBar()
    }
    
    // 创建状态栏项（标准 macOS 方法）
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    guard let currentStatusItem = statusItem else {
      return
    }
    
    // 获取按钮（必须设置 image 或 title，否则不会显示）
    guard let button = currentStatusItem.button else {
      statusItem = nil
      return
    }
    
    // 设置状态栏图标（兼容 macOS 10.15+）
    // 关键：必须设置 image 或 title，否则按钮不会显示
    if #available(macOS 11.0, *) {
      if let image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "密枢") {
        button.image = image
        button.image?.isTemplate = true
      } else {
        // 如果系统图标失败，使用文本图标
        button.title = "🔑"
        button.font = NSFont.systemFont(ofSize: 14)
      }
    } else {
      // macOS 10.15 兼容方案：使用文本图标
      button.title = "🔑"
      button.font = NSFont.systemFont(ofSize: 14)
    }
    
    button.toolTip = "密枢"
    
    // 设置点击事件
    button.action = #selector(statusBarButtonClicked)
    button.target = self
    
    // 创建状态栏菜单（动态创建，包含密钥切换功能）
    // 如果 statusBarChannel 还未初始化，updateStatusBarMenu 会创建临时菜单并延迟更新
    updateStatusBarMenu()
    
    // 如果 statusBarChannel 还未初始化，尝试立即注册（窗口可能已经创建）
    if statusBarChannel == nil {
      if let window = NSApplication.shared.windows.first,
         window.contentViewController is FlutterViewController {
        registerMethodChannel(retryCount: 0, maxRetries: 20)
      }
    }
    
    // 强制刷新按钮显示
    button.needsDisplay = true
  }

  func removeStatusBar() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  @objc func statusBarButtonClicked() {
    toggleWindow()
  }

  @objc func showWindow() {
    if let window = mainWindow ?? NSApplication.shared.windows.first {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  @objc func quitApplication() {
    NSApplication.shared.terminate(nil)
  }

  func toggleWindow() {
    guard let window = mainWindow ?? NSApplication.shared.windows.first else { return }
    
    if window.isVisible {
      window.orderOut(nil)
    } else {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
  
  // 当设置改变时调用此方法更新状态栏
  func updateStatusBarIfNeeded() {
    checkAndSetupStatusBar()
  }
  
  // 更新状态栏菜单（动态创建，包含密钥切换功能）
  func updateStatusBarMenu() {
    guard statusItem != nil else {
      return
    }
    
    // 如果 statusBarChannel 还未初始化，先创建基础菜单，稍后再更新
    guard statusBarChannel != nil else {
      // 创建临时基础菜单
      let menu = NSMenu()
      let showItem = NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: "")
      showItem.target = self
      menu.addItem(showItem)
      menu.addItem(NSMenuItem.separator())
      let quitItem = NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q")
      quitItem.target = self
      menu.addItem(quitItem)
      statusItem?.menu = menu
      
      // 延迟更新菜单（等待 statusBarChannel 初始化）
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.updateStatusBarMenu()
      }
      return
    }
    
    // 异步获取密钥列表并添加菜单项（避免阻塞主线程）
    // 先创建基础菜单，然后异步更新
    let menu = NSMenu()
    let showItem = NSMenuItem(title: "显示窗口", action: #selector(self.showWindow), keyEquivalent: "")
    showItem.target = self
    menu.addItem(showItem)
    menu.addItem(NSMenuItem.separator())
    let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
    loadingItem.isEnabled = false
    menu.addItem(loadingItem)
    let quitItem = NSMenuItem(title: "退出", action: #selector(self.quitApplication), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    self.statusItem?.menu = menu
    
    // 异步获取数据并更新菜单
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      
      // 检查工具是否启用并获取密钥列表
      let claudeEnabled = self.isToolEnabled("claudecode")
      let codexEnabled = self.isToolEnabled("codex")
      let geminiEnabled = self.isToolEnabled("gemini")
      
      var claudeKeys: [[String: Any]] = []
      var codexKeys: [[String: Any]] = []
      var geminiKeys: [[String: Any]] = []
      var currentClaudeKeyId: Int? = nil
      var currentCodexKeyId: Int? = nil
      var currentGeminiKeyId: Int? = nil
      
      if claudeEnabled {
        if let keys = self.getClaudeCodeKeys() {
          claudeKeys = keys
        }
        currentClaudeKeyId = self.getCurrentClaudeCodeKeyId()
      }
      
      if codexEnabled {
        if let keys = self.getCodexKeys() {
          codexKeys = keys
        }
        currentCodexKeyId = self.getCurrentCodexKeyId()
      }
      
      if geminiEnabled {
        if let keys = self.getGeminiKeys() {
          geminiKeys = keys
        }
        currentGeminiKeyId = self.getCurrentGeminiKeyId()
      }
      
      // 回到主线程更新菜单
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.statusItem != nil else { return }
        
        // 创建菜单
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "显示窗口", action: #selector(self.showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 添加 ClaudeCode 密钥切换菜单（仅在工具启用时）
        if claudeEnabled {
          let claudeHeader = NSMenuItem(title: "─── Claude ───", action: nil, keyEquivalent: "")
          claudeHeader.isEnabled = false
          menu.addItem(claudeHeader)
          
          if claudeKeys.isEmpty {
            let emptyItem = NSMenuItem(title: "  (无密钥，请在主界面添加)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
          } else {
            for key in claudeKeys {
              if let keyId = key["id"] as? Int,
                 let keyName = key["name"] as? String {
                // 处理官方配置（keyId 为 -1）的情况
                let isCurrent: Bool
                if keyId == -1 {
                  // 官方配置：currentClaudeKeyId 应该是 -1
                  isCurrent = (currentClaudeKeyId == -1)
                } else {
                  // 普通密钥：直接比较
                  isCurrent = (keyId == currentClaudeKeyId)
                }
                let menuItem = NSMenuItem(
                  title: keyName,
                  action: #selector(self.switchClaudeCodeKey(_:)),
                  keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = keyId
                menuItem.state = isCurrent ? .on : .off
                menu.addItem(menuItem)
              }
            }
          }
          
          menu.addItem(NSMenuItem.separator())
        }
        
        // 添加 Codex 密钥切换菜单（仅在工具启用时）
        if codexEnabled {
          let codexHeader = NSMenuItem(title: "─── Codex ───", action: nil, keyEquivalent: "")
          codexHeader.isEnabled = false
          menu.addItem(codexHeader)
          
          if codexKeys.isEmpty {
            let emptyItem = NSMenuItem(title: "  (无密钥，请在主界面添加)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
          } else {
            for key in codexKeys {
              if let keyId = key["id"] as? Int,
                 let keyName = key["name"] as? String {
                // 处理官方配置（keyId 为 -1）的情况
                let isCurrent: Bool
                if keyId == -1 {
                  // 官方配置：currentCodexKeyId 应该是 -1
                  isCurrent = (currentCodexKeyId == -1)
                } else {
                  // 普通密钥：直接比较
                  isCurrent = (keyId == currentCodexKeyId)
                }
                let menuItem = NSMenuItem(
                  title: keyName,
                  action: #selector(self.switchCodexKey(_:)),
                  keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = keyId
                menuItem.state = isCurrent ? .on : .off
                menu.addItem(menuItem)
              }
            }
          }
          
          menu.addItem(NSMenuItem.separator())
        }
        
        // 添加 Gemini 密钥切换菜单（仅在工具启用时）
        if geminiEnabled {
          let geminiHeader = NSMenuItem(title: "─── Gemini ───", action: nil, keyEquivalent: "")
          geminiHeader.isEnabled = false
          menu.addItem(geminiHeader)
          
          if geminiKeys.isEmpty {
            let emptyItem = NSMenuItem(title: "  (无密钥，请在主界面添加)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
          } else {
            for key in geminiKeys {
              if let keyId = key["id"] as? Int,
                 let keyName = key["name"] as? String {
                // 处理官方配置（keyId 为 -1）的情况
                let isCurrent: Bool
                if keyId == -1 {
                  // 官方配置：currentGeminiKeyId 应该是 -1
                  isCurrent = (currentGeminiKeyId == -1)
                } else {
                  // 普通密钥：直接比较
                  isCurrent = (keyId == currentGeminiKeyId)
                }
                let menuItem = NSMenuItem(
                  title: keyName,
                  action: #selector(self.switchGeminiKey(_:)),
                  keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = keyId
                menuItem.state = isCurrent ? .on : .off
                menu.addItem(menuItem)
              }
            }
          }
          
          menu.addItem(NSMenuItem.separator())
        }
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(self.quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
      }
    }
  }
  
  // 检查工具是否启用（异步调用，避免阻塞）
  func isToolEnabled(_ tool: String) -> Bool {
    guard let channel = statusBarChannel else {
      return false
    }
    
    var result: Bool = false
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("isToolEnabled", arguments: tool) { (response: Any?) in
        if let enabled = response as? Bool {
          result = enabled
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("isToolEnabled", arguments: tool) { (response: Any?) in
          if let enabled = response as? Bool {
            result = enabled
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取 ClaudeCode 密钥列表（异步调用，避免阻塞）
  func getClaudeCodeKeys() -> [[String: Any]]? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: [[String: Any]]? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getClaudeCodeKeys", arguments: nil) { (response: Any?) in
        if let keys = response as? [[String: Any]] {
          result = keys
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getClaudeCodeKeys", arguments: nil) { (response: Any?) in
          if let keys = response as? [[String: Any]] {
            result = keys
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取 Codex 密钥列表（异步调用，避免阻塞）
  func getCodexKeys() -> [[String: Any]]? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: [[String: Any]]? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getCodexKeys", arguments: nil) { (response: Any?) in
        if let keys = response as? [[String: Any]] {
          result = keys
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getCodexKeys", arguments: nil) { (response: Any?) in
          if let keys = response as? [[String: Any]] {
            result = keys
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取当前 ClaudeCode 使用的密钥ID（异步调用，避免阻塞）
  func getCurrentClaudeCodeKeyId() -> Int? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: Int? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getCurrentClaudeCodeKeyId", arguments: nil) { (response: Any?) in
        if let keyId = response as? Int {
          result = keyId
        } else if response is NSNull {
          result = nil
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getCurrentClaudeCodeKeyId", arguments: nil) { (response: Any?) in
          if let keyId = response as? Int {
            result = keyId
          } else if response is NSNull {
            result = nil
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取当前 Codex 使用的密钥ID（异步调用，避免阻塞）
  func getCurrentCodexKeyId() -> Int? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: Int? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getCurrentCodexKeyId", arguments: nil) { (response: Any?) in
        if let keyId = response as? Int {
          result = keyId
        } else if response is NSNull {
          result = nil
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getCurrentCodexKeyId", arguments: nil) { (response: Any?) in
          if let keyId = response as? Int {
            result = keyId
          } else if response is NSNull {
            result = nil
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取 Gemini 密钥列表（异步调用，避免阻塞）
  func getGeminiKeys() -> [[String: Any]]? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: [[String: Any]]? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getGeminiKeys", arguments: nil) { (response: Any?) in
        if let keys = response as? [[String: Any]] {
          result = keys
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getGeminiKeys", arguments: nil) { (response: Any?) in
          if let keys = response as? [[String: Any]] {
            result = keys
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 获取当前 Gemini 使用的密钥ID（异步调用，避免阻塞）
  func getCurrentGeminiKeyId() -> Int? {
    guard let channel = statusBarChannel else {
      return nil
    }
    
    var result: Int? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    // 确保在主线程调用 Flutter MethodChannel
    if Thread.isMainThread {
      channel.invokeMethod("getCurrentGeminiKeyId", arguments: nil) { (response: Any?) in
        if let keyId = response as? Int {
          result = keyId
        } else if response is NSNull {
          result = nil
        }
        semaphore.signal()
      }
    } else {
      DispatchQueue.main.sync {
        channel.invokeMethod("getCurrentGeminiKeyId", arguments: nil) { (response: Any?) in
          if let keyId = response as? Int {
            result = keyId
          } else if response is NSNull {
            result = nil
          }
          semaphore.signal()
        }
      }
    }
    
    _ = semaphore.wait(timeout: .now() + 2.0)
    return result
  }
  
  // 切换 ClaudeCode 密钥
  @objc func switchClaudeCodeKey(_ sender: NSMenuItem) {
    guard let keyId = sender.representedObject as? Int else {
      return
    }
    
    guard let channel = statusBarChannel else {
      return
    }
    
    channel.invokeMethod("switchClaudeCodeKey", arguments: keyId) { (response: Any?) in
      if let success = response as? Bool, success {
        // 切换成功后更新菜单
        DispatchQueue.main.async { [weak self] in
          self?.updateStatusBarMenu()
        }
      }
    }
  }
  
  // 切换 Codex 密钥
  @objc func switchCodexKey(_ sender: NSMenuItem) {
    guard let keyId = sender.representedObject as? Int else {
      return
    }
    
    guard let channel = statusBarChannel else {
      return
    }
    
    channel.invokeMethod("switchCodexKey", arguments: keyId) { (response: Any?) in
      if let success = response as? Bool, success {
        // 切换成功后更新菜单
        DispatchQueue.main.async { [weak self] in
          self?.updateStatusBarMenu()
        }
      }
    }
  }
  
  // 切换 Gemini 密钥
  @objc func switchGeminiKey(_ sender: NSMenuItem) {
    guard let keyId = sender.representedObject as? Int else {
      return
    }
    
    guard let channel = statusBarChannel else {
      return
    }
    
    channel.invokeMethod("switchGeminiKey", arguments: keyId) { (response: Any?) in
      if let success = response as? Bool, success {
        // 切换成功后更新菜单
        DispatchQueue.main.async { [weak self] in
          self?.updateStatusBarMenu()
        }
      }
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    // 应用退出时，停止访问 Security-Scoped 资源
    if let url = self.securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      self.securityScopedURL = nil
      print("AppDelegate: 应用退出时已停止访问 Security-Scoped 资源")
    }
    super.applicationWillTerminate(notification)
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 检查是否启用了最小化到托盘
    let userDefaults = UserDefaults.standard
    
    // 检查设置是否存在，如果不存在则使用默认值 true（首次安装）
    let shouldMinimizeToTray: Bool
    if userDefaults.object(forKey: "minimize_to_tray") != nil {
      shouldMinimizeToTray = userDefaults.bool(forKey: "minimize_to_tray")
    } else {
      // 设置不存在，使用默认值 true
      shouldMinimizeToTray = true
    }
    
    // 如果启用了最小化到托盘，不退出应用（但需要确保状态栏图标存在）
    if shouldMinimizeToTray {
      // 确保状态栏图标存在
      if statusItem == nil {
        setupStatusBar()
      }
      return false // 不退出应用
    }
    
    return true // 退出应用
  }

  /// 处理 Dock 图标点击事件
  /// 当用户点击 Dock 图标时，如果窗口被隐藏，则重新显示窗口
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // 如果已经有可见窗口，不需要处理
    if flag {
      return false
    }
    
    // 查找主窗口
    // 优先使用 mainWindow 引用
    // 如果 mainWindow 为 nil 或窗口已被释放，则从 NSApplication.shared.windows 中查找
    var window: NSWindow?
    
    if let mainWindow = mainWindow, mainWindow.isVisible == false {
      // mainWindow 存在但被隐藏，使用它
      window = mainWindow
    } else {
      // 尝试从所有窗口中查找主窗口（Flutter 窗口）
      window = NSApplication.shared.windows.first { win in
        win.contentViewController is FlutterViewController
      }
      
      // 如果找到了窗口，更新 mainWindow 引用
      if let foundWindow = window {
        mainWindow = foundWindow
      }
    }
    
    // 如果找到了窗口，重新显示它
    if let window = window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return true
    }
    
    // 如果没有找到窗口，返回 false 让系统使用默认行为
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  // MARK: - Security-Scoped Bookmarks
  
  private var securityScopedBookmark: Data?
  // 保存 Security-Scoped URL 引用，确保权限在整个应用生命周期中有效
  private var securityScopedURL: URL?
  private let bookmarkKey = "home_dir_security_scoped_bookmark"
  
  /// 保存 Security-Scoped Bookmark
  /// 注意：此方法需要在用户通过 NSOpenPanel 选择目录后立即调用
  /// 当用户通过 NSOpenPanel 选择目录时，系统会自动授予该目录的访问权限
  /// 我们需要在这个权限有效时创建 Security-Scoped Bookmark
  func saveSecurityScopedBookmark(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    
    // 验证目录是否存在
    guard FileManager.default.fileExists(atPath: path) else {
      print("AppDelegate: 目录不存在: \(path)")
      result(FlutterError(code: "NOT_FOUND", message: "目录不存在", details: nil))
      return
    }
    
    // 尝试访问目录以验证权限是否有效
    // 如果用户刚刚通过 NSOpenPanel 选择了目录，这个访问应该会成功
    var canAccess = false
    do {
      let contents = try FileManager.default.contentsOfDirectory(atPath: path)
      canAccess = true
      print("AppDelegate: 可以访问目录，包含 \(contents.count) 个项目")
    } catch {
      print("AppDelegate: 无法访问目录: \(error.localizedDescription)")
      canAccess = false
    }
    
    // 如果无法访问，尝试先获取 Security-Scoped 权限
    // 这可能是因为 FilePicker 返回后权限上下文已失效
    if !canAccess {
      // 尝试通过 Security-Scoped Bookmark 恢复权限（如果之前保存过）
      if let existingBookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
        do {
          var isStale = false
          let existingURL = try URL(
            resolvingBookmarkData: existingBookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
          )
          if !isStale && existingURL.path == path {
            let accessGranted = existingURL.startAccessingSecurityScopedResource()
            if accessGranted {
              print("AppDelegate: 通过现有 Bookmark 恢复了访问权限")
              canAccess = true
            }
          }
        } catch {
          print("AppDelegate: 无法通过现有 Bookmark 恢复权限: \(error)")
        }
      }
    }
    
    do {
      // 创建 Security-Scoped Bookmark
      // 当用户通过 NSOpenPanel 选择目录时，系统已经授予了访问权限
      // bookmarkData 方法会使用当前的访问权限上下文创建 bookmark
      // 注意：即使当前无法访问，bookmarkData 也可能成功创建 bookmark
      // 但这个 bookmark 可能无法在下次启动时恢复权限
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      
      // 保存到 UserDefaults
      UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
      UserDefaults.standard.set(path, forKey: "home_dir_path")
      UserDefaults.standard.synchronize() // 确保立即保存
      self.securityScopedBookmark = bookmarkData
      
      print("AppDelegate: Security-Scoped Bookmark 已保存: \(path)")
      
      // 立即尝试恢复并激活 bookmark，验证是否成功
      // 注意：如果之前已经有激活的 URL，先停止访问（避免资源泄漏）
      if let existingURL = self.securityScopedURL {
        existingURL.stopAccessingSecurityScopedResource()
        self.securityScopedURL = nil
      }
      
      do {
        var isStale = false
        let resolvedURL = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
        
        if !isStale {
          let accessGranted = resolvedURL.startAccessingSecurityScopedResource()
          if accessGranted {
            // 保存 URL 引用，确保权限在整个应用生命周期中有效
            self.securityScopedURL = resolvedURL
            
            // 验证权限是否真的有效（尝试列出目录内容）
            do {
              let contents = try FileManager.default.contentsOfDirectory(atPath: resolvedURL.path)
              print("AppDelegate: Security-Scoped Bookmark 已激活并验证成功: \(resolvedURL.path)（包含 \(contents.count) 个项目）")
              result(true)
              return
            } catch {
              print("AppDelegate: Security-Scoped Bookmark 已激活，但无法读取目录: \(error.localizedDescription)")
            }
          } else {
            print("AppDelegate: Security-Scoped Bookmark 已保存，但无法立即激活")
          }
        } else {
          print("AppDelegate: Security-Scoped Bookmark 已过期")
        }
      } catch {
        print("AppDelegate: 验证 Security-Scoped Bookmark 失败: \(error)")
      }
      
      // 即使激活失败，也保存 bookmark（下次启动时可以恢复）
      if canAccess {
        print("AppDelegate: Security-Scoped Bookmark 已保存（当前可以访问，但激活失败，可能需要重启应用）")
      } else {
        print("AppDelegate: Security-Scoped Bookmark 已保存（当前无法访问，可能需要重启应用后恢复权限）")
      }
      result(true)
    } catch {
      print("AppDelegate: 保存 Security-Scoped Bookmark 失败: \(error)")
      result(FlutterError(code: "SAVE_FAILED", message: error.localizedDescription, details: nil))
    }
  }
  
  /// 恢复 Security-Scoped Bookmark 访问权限
  func restoreSecurityScopedBookmark(result: @escaping FlutterResult) {
    guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
      print("AppDelegate: 没有保存的 Security-Scoped Bookmark")
      result(false)
      return
    }
    
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      
      if isStale {
        print("AppDelegate: Bookmark 已过期，需要重新授权")
        if let existingURL = self.securityScopedURL {
          existingURL.stopAccessingSecurityScopedResource()
        }
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "home_dir_path")
        self.securityScopedBookmark = nil
        self.securityScopedURL = nil
        result(false)
        return
      }
      
      // 如果之前已经有激活的 URL，先停止访问（避免资源泄漏）
      if let existingURL = self.securityScopedURL {
        existingURL.stopAccessingSecurityScopedResource()
      }
      
      // 开始访问 Security-Scoped 资源
      let success = url.startAccessingSecurityScopedResource()
      if success {
        print("AppDelegate: Security-Scoped Bookmark 访问权限已恢复: \(url.path)")
        self.securityScopedBookmark = bookmarkData
        // 保存 URL 引用，确保权限在整个应用生命周期中有效
        self.securityScopedURL = url
        
        // 验证权限是否真的有效（尝试列出目录内容）
        do {
          let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
          print("AppDelegate: 权限验证成功，可以访问目录（包含 \(contents.count) 个项目）")
        } catch {
          print("AppDelegate: 警告：startAccessingSecurityScopedResource 返回成功，但无法访问目录: \(error.localizedDescription)")
        }
        
        result(true)
      } else {
        print("AppDelegate: 无法访问 Security-Scoped Bookmark，可能需要重新授权")
        self.securityScopedURL = nil
        result(false)
      }
    } catch {
      print("AppDelegate: 恢复 Security-Scoped Bookmark 失败: \(error)")
      // 清除无效的 bookmark
      if let url = self.securityScopedURL {
        url.stopAccessingSecurityScopedResource()
      }
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      UserDefaults.standard.removeObject(forKey: "home_dir_path")
      self.securityScopedBookmark = nil
      self.securityScopedURL = nil
      result(false)
    }
  }
  
  /// 检查是否有保存的 Security-Scoped Bookmark
  func hasSecurityScopedBookmark(result: @escaping FlutterResult) {
    let hasBookmark = UserDefaults.standard.data(forKey: bookmarkKey) != nil
    result(hasBookmark)
  }
  
  /// 清除 Security-Scoped Bookmark
  func clearSecurityScopedBookmark(result: @escaping FlutterResult) {
    // 停止访问 Security-Scoped 资源
    if let url = self.securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      self.securityScopedURL = nil
    }
    UserDefaults.standard.removeObject(forKey: bookmarkKey)
    UserDefaults.standard.removeObject(forKey: "home_dir_path")
    self.securityScopedBookmark = nil
    result(true)
  }
  
  /// 在应用启动时恢复 Security-Scoped Bookmark 访问权限
  /// 这个方法必须在应用启动时立即调用，以确保后续文件访问有权限
  func restoreBookmarkOnLaunch() {
    print("AppDelegate: 开始恢复 Security-Scoped Bookmark 访问权限...")
    guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
      print("AppDelegate: 没有保存的 Security-Scoped Bookmark（首次启动或未授权）")
      return
    }
    print("AppDelegate: 找到保存的 Security-Scoped Bookmark，开始恢复...")
    
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      
      if isStale {
        print("AppDelegate: Bookmark 已过期，已清除")
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "home_dir_path")
        self.securityScopedBookmark = nil
        self.securityScopedURL = nil
        return
      }
      
      // 开始访问 Security-Scoped 资源
      // 注意：一旦调用 startAccessingSecurityScopedResource()，权限就会保持有效
      // 直到应用退出或调用 stopAccessingSecurityScopedResource()
      // 根据 Apple 文档，对于需要在整个应用生命周期中保持访问权限的情况，
      // 应该在应用启动时调用 startAccessingSecurityScopedResource()，并在应用退出时调用 stopAccessingSecurityScopedResource()
      let success = url.startAccessingSecurityScopedResource()
      if success {
        print("AppDelegate: 应用启动时已恢复 Security-Scoped Bookmark 访问权限: \(url.path)")
        self.securityScopedBookmark = bookmarkData
        // 保存 URL 引用，确保权限在整个应用生命周期中有效
        self.securityScopedURL = url
        
        // 验证权限是否真的有效（尝试列出目录内容）
        do {
          let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
          print("AppDelegate: ✅ 权限验证成功，可以访问目录（包含 \(contents.count) 个项目）")
          
          // 进一步验证：尝试访问子目录（模拟实际使用场景）
          let testSubdirs = [".claude", ".codex", ".gemini", ".cursor", ".codeium"]
          var accessibleSubdirs: [String] = []
          for subdir in testSubdirs {
            let subdirPath = (url.path as NSString).appendingPathComponent(subdir)
            if FileManager.default.fileExists(atPath: subdirPath) {
              do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: subdirPath)
                accessibleSubdirs.append(subdir)
              } catch {
                print("AppDelegate: ⚠️ 无法访问子目录 \(subdir): \(error.localizedDescription)")
              }
            }
          }
          if !accessibleSubdirs.isEmpty {
            print("AppDelegate: ✅ 可以访问以下子目录: \(accessibleSubdirs.joined(separator: ", "))")
          }
        } catch {
          print("AppDelegate: ❌ 警告：startAccessingSecurityScopedResource 返回成功，但无法访问目录: \(error.localizedDescription)")
          // 即使无法访问，也保留 bookmark，因为可能是临时问题
        }
      } else {
        print("AppDelegate: 无法访问 Security-Scoped Bookmark，可能需要重新授权")
        // 清除无效的 bookmark
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "home_dir_path")
        self.securityScopedBookmark = nil
        self.securityScopedURL = nil
      }
    } catch {
      print("AppDelegate: 启动时恢复 Bookmark 失败: \(error)")
      // 清除无效的 bookmark
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      UserDefaults.standard.removeObject(forKey: "home_dir_path")
      self.securityScopedBookmark = nil
    }
  }
}

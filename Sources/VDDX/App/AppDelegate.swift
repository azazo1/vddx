import AppKit
import Foundation

/// 应用生命周期与窗口编排的唯一入口.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var updateWindowController: UpdateWindowController?
    private var aboutWindowController: AboutWindowController?
    private var trayController: TrayController?
    private var mirrorControllers: [UUID: MirrorWindowController] = [:]
    private var signalSources: [DispatchSourceSignal] = []
    private var didShutdown = false
    private var instanceLock: SingleInstanceLock?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 同一数据目录只允许一个实例; 隔离调试实例使用不同数据目录, 可以并行运行.
        guard let lock = SingleInstanceLock(directory: AppPaths.dataDirectory) else {
            Log.shared.warn("同一数据目录已有实例在运行, 当前进程退出")
            activateExistingInstance()
            Log.shared.flush()
            exit(0)
        }
        instanceLock = lock

        let model = AppModel()
        self.model = model
        model.applyLogLevel()

        Log.shared.info("应用启动: \(AppInfo.appName) \(AppInfo.displayVersion)")
        Log.shared.info("channel=\(AppInfo.channel) form=\(AppInfo.distributionForm) pid=\(ProcessInfo.processInfo.processIdentifier)")
        Log.shared.info("数据目录: \(AppPaths.dataDirectory.path)")

        installSignalHandlers()
        installExceptionHandler()
        NSApp.mainMenu = MainMenuBuilder.make(appDelegate: self)

        model.displayManager.restoreSavedDisplays()
        trayController = TrayController(model: model, delegate: self)

        if model.settings.general.hideMainWindowOnLaunch {
            NSApp.setActivationPolicy(.accessory)
            Log.shared.info("按设置启动时隐藏主窗口, 仅驻留菜单栏")
        } else {
            NSApp.setActivationPolicy(.regular)
            presentMainWindow()
        }

        if model.settings.updates.automaticallyChecks {
            Task { [weak self] in
                await model.checkForUpdates(silent: true)
                self?.presentUpdateWindowIfNeeded()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.shared.info("收到 reopen 事件, 显示主窗口")
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        performShutdown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        performShutdown()
    }

    // MARK: - 主窗口

    func showMainWindow() {
        guard model != nil else { return }
        if NSApp.activationPolicy() != .regular {
            // 先恢复普通应用身份, 等系统完成切换后再显示窗口, 避免窗口落在其他应用的全屏 Space 上.
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.async { [weak self] in
                self?.presentMainWindow()
            }
        } else {
            presentMainWindow()
        }
    }

    private func presentMainWindow() {
        guard let model else { return }
        if mainWindowController == nil {
            let controller = MainWindowController(model: model)
            controller.onCloseRequest = { [weak self] in self?.hideMainWindow() }
            controller.onOpenMirror = { [weak self] display in self?.openMirror(for: display) }
            controller.onOpenSettings = { [weak self] in self?.openSettings() }
            controller.onCheckUpdates = { [weak self] in self?.checkForUpdates() }
            controller.onOpenUpdateWindow = { [weak self] in self?.presentUpdateWindowIfNeeded() }
            mainWindowController = controller
        }
        guard let window = mainWindowController?.window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.shared.info("主窗口已显示")
    }

    private func hideMainWindow() {
        mainWindowController?.window?.orderOut(nil)
        Log.shared.info("主窗口已隐藏")
        if model?.settings.general.hideDockWhenWindowHidden == true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - 其他窗口

    func openSettings() {
        guard let model else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                model: model,
                onCheckUpdates: { [weak self] in self?.checkForUpdates() }
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.shared.info("打开设置窗口")
    }

    func openMirror(for display: VirtualDisplay) {
        guard let model else { return }
        if let existing = mirrorControllers[display.id] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = MirrorWindowController(display: display, model: model)
        controller.onClose = { [weak self] in
            self?.mirrorControllers.removeValue(forKey: display.id)
        }
        mirrorControllers[display.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.startCapture()
        Log.shared.info("打开镜像窗口: \(display.profile.name)")
    }

    func checkForUpdates() {
        guard let model else { return }
        Task { [weak self] in
            await model.checkForUpdates(silent: false)
            guard let self else { return }
            switch model.updates.state {
            case .available:
                self.presentUpdateWindowIfNeeded()
            case .upToDate:
                let alert = NSAlert()
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前版本 \(AppInfo.displayVersion) 已是最新."
                alert.runModal()
            case .failed(let message):
                let alert = NSAlert()
                alert.messageText = "检查更新失败"
                alert.informativeText = message
                alert.runModal()
            default:
                break
            }
        }
    }

    func presentUpdateWindowIfNeeded() {
        guard let model else { return }
        guard case .available(let release) = model.updates.state else { return }
        if updateWindowController == nil {
            updateWindowController = UpdateWindowController(
                model: model,
                onDownload: { [weak self] release in self?.downloadUpdate(release) },
                onInstall: { [weak self] release, url in self?.installUpdate(release, packageURL: url) },
                onSkip: { [weak self] release in self?.skipUpdate(release) },
                onOpenReleasePage: { NSWorkspace.shared.open(AppInfo.releasesURL) }
            )
        }
        updateWindowController?.update(with: release)
        updateWindowController?.showWindow(nil)
        updateWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.shared.info("展示更新窗口: \(release.tagName)")
    }

    private func downloadUpdate(_ release: UpdateRelease) {
        guard let model else { return }
        Task { await model.updates.download(release) }
    }

    private func installUpdate(_ release: UpdateRelease, packageURL: URL) {
        let alert = NSAlert()
        alert.messageText = "重启并更新?"
        alert.informativeText = "应用会退出, 由替换脚本安装 \(release.tagName) 后重新打开."
        alert.addButton(withTitle: "重启并更新")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try model?.updates.installAndRelaunch(release, packageURL: packageURL)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "无法自动更新"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.runModal()
        }
    }

    private func skipUpdate(_ release: UpdateRelease) {
        guard let model else { return }
        model.updateSettings { settings in
            settings.updates.skippedVersion = release.tagName
        }
        model.updates.dismissAvailable()
        updateWindowController?.close()
        Log.shared.info("用户跳过版本: \(release.tagName)")
    }

    func requestCreateDisplay() {
        showMainWindow()
        model?.createDisplayRequest = true
    }

    @objc func menuNewDisplay() {
        requestCreateDisplay()
    }

    @objc func menuOpenSettings() {
        openSettings()
    }

    @objc func showAboutPanel() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 退出

    func requestQuit() {
        Log.shared.info("收到退出请求")
        NSApp.terminate(nil)
    }

    private func performShutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        Log.shared.info("开始退出清理")
        for controller in mirrorControllers.values {
            controller.stopCapture()
        }
        mirrorControllers.removeAll()
        trayController?.teardown()
        trayController = nil
        mainWindowController?.prepareForTermination()
        mainWindowController = nil
        // 销毁全部虚拟屏, 这是最关键的清理步骤: 不能把虚拟屏留给系统.
        model?.displayManager.destroyAll()
        model?.settingsStore.save()
        updateWindowController?.close()
        settingsWindowController?.close()
        aboutWindowController?.close()
        Log.shared.info("退出清理完成")
        Log.shared.flush()
    }

    // MARK: - 信号与异常

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                Log.shared.info("收到信号 \(sig), 优雅退出")
                self?.requestQuit()
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            if application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                application.activate(options: [])
                break
            }
        }
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            Log.shared.error("未捕获异常: \(exception.name.rawValue): \(exception.reason ?? "无描述")")
            Log.shared.flush()
        }
    }
}

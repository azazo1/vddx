import AppKit

/// 菜单栏常驻图标.
///
/// 左键: 显示主窗口. 右键: 弹出菜单.
@MainActor
final class TrayController: NSObject {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private weak var delegate: AppDelegate?

    init(model: AppModel, delegate: AppDelegate) {
        self.model = model
        self.delegate = delegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "VDDX")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "VDDX \(AppInfo.displayVersion)"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            Log.shared.info("托盘左键点击, 显示主窗口")
            delegate?.showMainWindow()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "VDDX \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        let createItem = NSMenuItem(title: "新建虚拟屏...", action: #selector(menuCreate), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        if !model.displayManager.displays.isEmpty {
            let displaysItem = NSMenuItem(title: "虚拟屏", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for display in model.displayManager.displays {
                let item = NSMenuItem(
                    title: "\(display.profile.name)  (\(display.profile.resolutionLabel))",
                    action: nil,
                    keyEquivalent: ""
                )
                let actions = NSMenu()
                let mirrorItem = NSMenuItem(title: "镜像...", action: #selector(menuMirror(_:)), keyEquivalent: "")
                mirrorItem.target = self
                mirrorItem.representedObject = display.id.uuidString
                actions.addItem(mirrorItem)
                item.submenu = actions
                submenu.addItem(item)
            }
            displaysItem.submenu = submenu
            menu.addItem(displaysItem)
        }

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(menuShow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "检查更新...", action: #selector(menuCheckUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 VDDX", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func menuCreate() {
        delegate?.requestCreateDisplay()
    }

    @objc private func menuMirror(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let display = model.displayManager.displays.first(where: { $0.id == id }) else {
            return
        }
        delegate?.openMirror(for: display)
    }

    @objc private func menuShow() {
        delegate?.showMainWindow()
    }

    @objc private func menuSettings() {
        delegate?.openSettings()
    }

    @objc private func menuCheckUpdates() {
        delegate?.checkForUpdates()
    }

    @objc private func menuQuit() {
        delegate?.requestQuit()
    }

    func teardown() {
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

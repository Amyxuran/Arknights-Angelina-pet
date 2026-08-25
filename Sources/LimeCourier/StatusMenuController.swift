import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private let preferences: AppPreferences

    var isPetVisible: (() -> Bool)?
    var petStatus: (() -> String)?
    var onTogglePet: (() -> Void)?
    var onResetPosition: (() -> Void)?
    var onQuit: (() -> Void)?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
    }

    func makeContextMenu() -> NSMenu {
        makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "酸橙信使")
        let status = NSMenuItem(title: petStatus?() ?? "休息中 · 坐坐", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item(
            isPetVisible?() == false ? "显示安洁莉娜" : "隐藏安洁莉娜",
            action: #selector(togglePet),
            imageName: isPetVisible?() == false ? "eye" : "eye.slash"
        ))
        menu.addItem(toggleItem("自主活动", isOn: preferences.autonomousEnabled, action: #selector(toggleAutonomous)))
        menu.addItem(toggleItem("鼠标追随", isOn: preferences.mouseFollowEnabled, action: #selector(toggleMouseFollow)))
        menu.addItem(toggleItem("边缘气泡", isOn: preferences.edgeHideEnabled, action: #selector(toggleEdgeHide)))
        menu.addItem(toggleItem("始终置顶", isOn: preferences.alwaysOnTop, action: #selector(toggleAlwaysOnTop)))

        let actionItem = NSMenuItem(title: "待机动作", action: nil, keyEquivalent: "")
        actionItem.image = NSImage(systemSymbolName: "figure.seated.side", accessibilityDescription: nil)
        let actionMenu = NSMenu(title: "待机动作")
        for action in PetSelectableAction.allCases {
            let option = item(action.rawValue, action: #selector(selectStandbyAction))
            option.representedObject = action.rawValue as NSString
            option.state = preferences.selectedStandbyAction == action ? .on : .off
            actionMenu.addItem(option)
        }
        actionItem.submenu = actionMenu
        menu.addItem(actionItem)

        menu.addItem(.separator())
        let sizeItem = NSMenuItem(title: "角色大小", action: nil, keyEquivalent: "")
        sizeItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        let sizeMenu = NSMenu(title: "角色大小")
        for size in AppPreferences.supportedSizes {
            let title: String
            switch size {
            case 120: title = "小 · 120 pt"
            case 224: title = "大 · 224 pt"
            default: title = "中 · 168 pt"
            }
            let option = item(title, action: #selector(selectSize))
            option.representedObject = NSNumber(value: size)
            option.state = abs(preferences.petSize - size) < 0.5 ? .on : .off
            sizeMenu.addItem(option)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let speedItem = NSMenuItem(title: "动画速度", action: nil, keyEquivalent: "")
        speedItem.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: nil)
        let speedMenu = NSMenu(title: "动画速度")
        for speed in AppPreferences.supportedSpeeds {
            let title = speed == 0.8 ? "舒缓 · 0.8×" : speed == 1 ? "标准 · 1.0×" : "轻快 · 1.25×"
            let option = item(title, action: #selector(selectSpeed))
            option.representedObject = NSNumber(value: speed)
            option.state = abs(preferences.animationSpeed - speed) < 0.01 ? .on : .off
            speedMenu.addItem(option)
        }
        speedItem.submenu = speedMenu
        menu.addItem(speedItem)

        menu.addItem(.separator())
        menu.addItem(toggleItem("开机启动", isOn: preferences.launchAtLogin, action: #selector(toggleLaunchAtLogin)))
        menu.addItem(item("重置角色位置", action: #selector(resetPosition), imageName: "location.fill"))
        menu.addItem(.separator())
        menu.addItem(item("退出酸橙信使", action: #selector(quit), imageName: "power"))
        return menu
    }

    private func item(_ title: String, action: Selector, imageName: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        if let imageName {
            menuItem.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        }
        return menuItem
    }

    private func toggleItem(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let menuItem = item(title, action: action)
        menuItem.state = isOn ? .on : .off
        return menuItem
    }

    @objc private func togglePet() { onTogglePet?() }
    @objc private func toggleAutonomous() { preferences.autonomousEnabled.toggle() }
    @objc private func toggleMouseFollow() { preferences.mouseFollowEnabled.toggle() }
    @objc private func toggleEdgeHide() { preferences.edgeHideEnabled.toggle() }
    @objc private func toggleAlwaysOnTop() { preferences.alwaysOnTop.toggle() }
    @objc private func toggleLaunchAtLogin() { preferences.launchAtLogin.toggle() }
    @objc private func resetPosition() { onResetPosition?() }
    @objc private func quit() { onQuit?() }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else { return }
        preferences.petSize = AppPreferences.normalizedSize(value.doubleValue)
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else { return }
        preferences.animationSpeed = AppPreferences.normalizedSpeed(value.doubleValue)
    }

    @objc private func selectStandbyAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = PetSelectableAction(rawValue: rawValue) else { return }
        preferences.selectedStandbyAction = action
    }
}

import AppKit
import SwiftUI

@main
struct LimeCourierApp: App {
    @NSApplicationDelegateAdaptor(LimeCourierAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(appDelegate: appDelegate)
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarRootView: View {
    @ObservedObject var appDelegate: LimeCourierAppDelegate

    var body: some View {
        if let controller = appDelegate.controller {
            MenuBarContentView(controller: controller)
        } else {
            Text("正在启动")
                .disabled(true)
        }
    }
}

private struct MenuBarIcon: View {
    private let image: NSImage

    init() {
        if let url = ResourceLocator.url(for: "23", extension: "png", subdirectory: "UI素材"),
           let resourceImage = NSImage(contentsOf: url) {
            resourceImage.size = NSSize(width: 16, height: 18)
            resourceImage.isTemplate = false
            image = resourceImage
        } else {
            image = NSImage(systemSymbolName: "figure.wave", accessibilityDescription: "酸橙信使") ?? NSImage()
        }
    }

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.original)
            .interpolation(.high)
            .accessibilityLabel("酸橙信使")
    }
}

@MainActor
final class LimeCourierAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = AppController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareToTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var preferences: AppPreferences

    init(controller: AppController) {
        self.controller = controller
        preferences = controller.preferences
    }

    var body: some View {
        Text(controller.petStatus)
            .disabled(true)
        Divider()

        Button {
            controller.togglePetVisibility()
        } label: {
            Label(
                controller.isPetVisible ? "隐藏安洁莉娜" : "显示安洁莉娜",
                systemImage: controller.isPetVisible ? "eye.slash" : "eye"
            )
        }

        Toggle("自主活动", isOn: $preferences.autonomousEnabled)
        Toggle("鼠标追随", isOn: $preferences.mouseFollowEnabled)
        Toggle("边缘气泡", isOn: $preferences.edgeHideEnabled)
        Toggle("始终置顶", isOn: $preferences.alwaysOnTop)

        Menu {
            ForEach(PetSelectableAction.allCases, id: \.rawValue) { action in
                Button {
                    preferences.selectedStandbyAction = action
                } label: {
                    selectionLabel(action.rawValue, selected: preferences.selectedStandbyAction == action)
                }
            }
        } label: {
            Label("待机动作", systemImage: "figure.seated.side")
        }

        Divider()

        Menu {
            ForEach(AppPreferences.supportedSizes, id: \.self) { size in
                Button {
                    preferences.petSize = size
                } label: {
                    selectionLabel(sizeTitle(size), selected: preferences.petSize == size)
                }
            }
        } label: {
            Label("角色大小", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Menu {
            ForEach(AppPreferences.supportedSpeeds, id: \.self) { speed in
                Button {
                    preferences.animationSpeed = speed
                } label: {
                    selectionLabel(speedTitle(speed), selected: preferences.animationSpeed == speed)
                }
            }
        } label: {
            Label("动画速度", systemImage: "gauge.with.dots.needle.50percent")
        }

        Divider()

        Toggle("开机启动", isOn: $preferences.launchAtLogin)
        Button {
            controller.resetPetPosition()
        } label: {
            Label("重置角色位置", systemImage: "location.fill")
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出酸橙信使", systemImage: "power")
        }
    }

    @ViewBuilder
    private func selectionLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func sizeTitle(_ size: Double) -> String {
        switch size {
        case 120: "小 · 120 pt"
        case 224: "大 · 224 pt"
        default: "中 · 168 pt"
        }
    }

    private func speedTitle(_ speed: Double) -> String {
        switch speed {
        case 0.8: "舒缓 · 0.8×"
        case 1.25: "轻快 · 1.25×"
        default: "标准 · 1.0×"
        }
    }
}

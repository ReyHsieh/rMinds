import SwiftUI
import UIKit

private func dynamicColor(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}

/// 黑白灰极简配色（浅色对照原设计，深色为适配版）。
extension Color {
    /// 主文字：近黑
    static let primaryText = dynamicColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1),
        dark: .white
    )
    /// 次要文字：时间、计数
    static let secondaryText = dynamicColor(
        light: UIColor(white: 0, alpha: 0.42),
        dark: UIColor(white: 1, alpha: 0.55)
    )
    /// 卡片底色：#F2F1ED（暖灰）
    static let cardBackground = dynamicColor(
        light: UIColor(red: 242 / 255, green: 241 / 255, blue: 237 / 255, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    /// 卡片纯色填充
    static let cardTint = dynamicColor(
        light: UIColor(red: 236 / 255, green: 234 / 255, blue: 229 / 255, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
    )
    static let appBackground = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    )
    /// 输入栏芯片底色
    static let newTaskBackground = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let newTaskText = dynamicColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1),
        dark: .white
    )
    /// 位于 primaryText（近黑/纯白）底色之上的前景色
    static let onPrimary = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    )
    /// 未勾选复选框的描边
    static let checkboxBorder = dynamicColor(
        light: UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.4)
    )
    /// 白色芯片（复选框底、编辑器菜单标签等）
    static let chipFill = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    /// 小标签/置顶区底色
    static let badgeBackground = dynamicColor(
        light: UIColor(white: 0, alpha: 0.06),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let disabledFill = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.12)
    )

    // MARK: 强调色主题

    /// 按主题取强调色（墨=近黑，其余为低饱和彩色）
    static func accent(for theme: AccentTheme) -> Color {
        switch theme {
        case .ink:
            return dynamicColor(
                light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1),
                dark: .white
            )
        case .indigo:
            return dynamicColor(
                light: UIColor(red: 0.29, green: 0.29, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.62, green: 0.62, blue: 0.94, alpha: 1)
            )
        case .amber:
            return dynamicColor(
                light: UIColor(red: 0.72, green: 0.47, blue: 0.11, alpha: 1),
                dark: UIColor(red: 0.93, green: 0.72, blue: 0.38, alpha: 1)
            )
        case .forest:
            return dynamicColor(
                light: UIColor(red: 0.13, green: 0.45, blue: 0.28, alpha: 1),
                dark: UIColor(red: 0.45, green: 0.78, blue: 0.58, alpha: 1)
            )
        case .rose:
            return dynamicColor(
                light: UIColor(red: 0.72, green: 0.22, blue: 0.34, alpha: 1),
                dark: UIColor(red: 0.94, green: 0.55, blue: 0.65, alpha: 1)
            )
        case .ocean:
            return dynamicColor(
                light: UIColor(red: 0.10, green: 0.40, blue: 0.66, alpha: 1),
                dark: UIColor(red: 0.47, green: 0.72, blue: 0.93, alpha: 1)
            )
        case .slate:
            return dynamicColor(
                light: UIColor(red: 0.34, green: 0.38, blue: 0.44, alpha: 1),
                dark: UIColor(red: 0.68, green: 0.73, blue: 0.80, alpha: 1)
            )
        case .cocoa:
            return dynamicColor(
                light: UIColor(red: 0.46, green: 0.32, blue: 0.24, alpha: 1),
                dark: UIColor(red: 0.80, green: 0.64, blue: 0.52, alpha: 1)
            )
        }
    }
}

/// 全局字号缩放（设置 → 字体大小；由 AppSettings 更新）
enum FS {
    static var scale: CGFloat = 1.0
    static func s(_ base: CGFloat) -> CGFloat { base * scale }
}

// MARK: - 按压反馈（统一的手感体系）

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var opacity: CGFloat = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - 新手引导用的布局取帧

struct FrameReporterKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// 把自身 frame(in: .global) 上报给祖先视图，key 为 nil 时不生效。
    @ViewBuilder
    func reportFrame(_ key: String?) -> some View {
        if let key {
            background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FrameReporterKey.self, value: [key: proxy.frame(in: .global)])
                }
            )
        } else {
            self
        }
    }
}

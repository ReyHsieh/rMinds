import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum FontSizeMode: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .standard: return 1.0
        case .large: return 1.15
        }
    }
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case ink
    case indigo
    case amber
    case forest
    case rose
    case ocean
    case slate
    case cocoa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ink: return "墨"
        case .indigo: return "靛"
        case .amber: return "琥珀"
        case .forest: return "森"
        case .rose: return "蔷薇"
        case .ocean: return "海"
        case .slate: return "石板"
        case .cocoa: return "可可"
        }
    }
}

/// 可绑定到手势的动作
enum GestureAction: String, CaseIterable, Identifiable {
    case none
    case toggleHighlight
    case toggleDone
    case togglePin
    case edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "无"
        case .toggleHighlight: return "切换高光"
        case .toggleDone: return "标记完成（待办）"
        case .togglePin: return "切换置顶"
        case .edit: return "打开编辑"
        }
    }
}

/// 全局设置，UserDefaults 持久化。
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.reminders) }
    }
    /// "今天" 从几点开始（0-23），影响 Today 分组与已完成任务的归档时机。
    var dayStartHour: Int {
        didSet { defaults.set(dayStartHour, forKey: Keys.dayStartHour) }
    }
    var dayStartMinute: Int {
        didSet { defaults.set(dayStartMinute, forKey: Keys.dayStartMinute) }
    }
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var fontSize: FontSizeMode {
        didSet {
            defaults.set(fontSize.rawValue, forKey: Keys.fontSize)
            FS.scale = fontSize.scale
        }
    }
    var accent: AccentTheme {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }
    /// 手势自定义：双击条目 / 长按条目 触发的动作
    var doubleTapAction: GestureAction {
        didSet { defaults.set(doubleTapAction.rawValue, forKey: Keys.doubleTap) }
    }
    var longPressAction: GestureAction {
        didSet { defaults.set(longPressAction.rawValue, forKey: Keys.longPress) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let reminders = "settings.remindersEnabled"
        static let dayStartHour = "settings.dayStartHour"
        static let dayStartMinute = "settings.dayStartMinute"
        static let appearance = "settings.appearance"
        static let fontSize = "settings.fontSize"
        static let accent = "settings.accent"
        static let doubleTap = "settings.gesture.doubleTap"
        static let longPress = "settings.gesture.longPress"
    }

    private init() {
        // App Group 组内 defaults，供小组件扩展同步读取
        self.defaults = SharedStore.userDefaults
        remindersEnabled = defaults.object(forKey: Keys.reminders) as? Bool ?? false
        dayStartHour = defaults.object(forKey: Keys.dayStartHour) as? Int ?? 4
        dayStartMinute = defaults.object(forKey: Keys.dayStartMinute) as? Int ?? 0
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        fontSize = FontSizeMode(rawValue: defaults.string(forKey: Keys.fontSize) ?? "") ?? .standard
        accent = AccentTheme(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .ink
        doubleTapAction = GestureAction(rawValue: defaults.string(forKey: Keys.doubleTap) ?? "") ?? .toggleHighlight
        longPressAction = GestureAction(rawValue: defaults.string(forKey: Keys.longPress) ?? "") ?? .none
        FS.scale = fontSize.scale
    }
}

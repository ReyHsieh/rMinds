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
    private let defaults: UserDefaults

    private enum Keys {
        static let reminders = "settings.remindersEnabled"
        static let dayStartHour = "settings.dayStartHour"
        static let dayStartMinute = "settings.dayStartMinute"
        static let appearance = "settings.appearance"
    }

    private init() {
        // App Group 组内 defaults，供小组件扩展同步读取
        self.defaults = SharedStore.userDefaults
        remindersEnabled = defaults.object(forKey: Keys.reminders) as? Bool ?? false
        dayStartHour = defaults.object(forKey: Keys.dayStartHour) as? Int ?? 4
        dayStartMinute = defaults.object(forKey: Keys.dayStartMinute) as? Int ?? 0
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
    }
}

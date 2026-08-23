import SwiftUI
import SwiftData

/// 设置：原生 Form 风格（iOS 26 玻璃分组自动应用）。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(OnboardingManager.self) private var onboarding
    @Query private var tasks: [TaskItem]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("到期提醒通知", isOn: remindersBinding)
                } header: {
                    Text("提醒")
                } footer: {
                    Text("任务到达设定时间时发送通知。需要系统通知权限；关闭后所有待发提醒会被清除。")
                }

                Section {
                    DatePicker(
                        "每日开始时间",
                        selection: dayStartTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("日程")
                } footer: {
                    Text("“今天” 从几点开始。影响 Today 分组与已完成任务的归档时机。")
                }

                Section {
                    Picker("外观", selection: appearanceBinding) {
                        Text("跟随系统").tag(AppearanceMode.system)
                        Text("浅色").tag(AppearanceMode.light)
                        Text("深色").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("外观")
                }

                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            onboarding.restart()
                        }
                    } label: {
                        Label("重新查看新手引导", systemImage: "sparkles")
                    }
                } header: {
                    Text("新手引导")
                } footer: {
                    Text("重新体验创建任务、勾选完成等基本操作。")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("任务数", value: "\(tasks.count)")
                } header: {
                    Text("关于")
                }

                #if DEBUG
                Section {
                    Button {
                        SeedData.loadSample(context: context)
                    } label: {
                        Label("载入示例数据", systemImage: "square.grid.2x2")
                    }
                    Button(role: .destructive) {
                        SeedData.reset(context)
                    } label: {
                        Label("清除全部数据", systemImage: "trash")
                    }
                } header: {
                    Text("开发者选项（仅调试构建）")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            // sheet 不继承呈现方的 preferredColorScheme，需自行应用才能实时响应外观切换
            .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    // MARK: 绑定

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { settings.remindersEnabled },
            set: { enabled in
                if enabled {
                    settings.remindersEnabled = true
                    NotificationManager.requestAuthorization { granted in
                        if granted {
                            NotificationManager.refreshPending(tasks: tasks, enabled: true)
                        } else {
                            settings.remindersEnabled = false
                        }
                    }
                } else {
                    settings.remindersEnabled = false
                    NotificationManager.cancelAll()
                }
            }
        )
    }

    private var dayStartTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.dayStartHour,
                    minute: settings.dayStartMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.dayStartHour = components.hour ?? 4
                settings.dayStartMinute = components.minute ?? 0
            }
        )
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { settings.appearance },
            set: { settings.appearance = $0 }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

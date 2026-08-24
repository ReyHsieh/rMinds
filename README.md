# rMinds

记录一切值得记住的：碎碎念、待办、照片和语音。一款聊天式时间线记录应用，SwiftUI + SwiftData 构建，iOS 26 Liquid Glass 设计，支持桌面与锁屏小组件。

> 前身是 [rDos](https://x.com/daimajia/status/2091362554291577217)（极简待办应用），2.0 起转型为通用记录工具。

## 设计理念

待办应用回答的是"什么必须在什么时候完成"；但生活里更多的是——

> 好多事，我并不想甚至也没有办法安排到底什么时候一定要完成。—— [@daimajia](https://x.com/daimajia)

rMinds 把一切记录统一进一条按时间倒序的**时间线**：碎碎念、待办、照片、语音混排在一起，随手记、不强迫组织。想归拢的时候，用 **#标签**（正文里写 `#想法` `#工作`）在分类页聚合即可。

## 功能

- **时间线**：一切记录按天倒序（今天 · 8月24日 / 昨天 / …），左侧时间列
- **置顶与高光**：重要记录置顶显示在时间线顶部；精彩记录加高光标记
- **四种记录**：
  - 碎碎念文字：输入栏敲字回车即入流
  - 待办：输入栏一键切待办模式，可设日期/时间/到点提醒，时间线上可勾选
  - 照片：系统相册选择器，时间线缩略图 + 全屏查看
  - 语音：输入栏按住麦克风录音，条目内直接播放
- **手势**：右滑待办标记完成，左滑任何记录删除，点按进入编辑
- **小组件**：桌面小/中/大（待办进度 + 最近记录）+ 锁屏环形/矩形/内联
- **外观定制**：浅色 / 深色 / 跟随系统；八种强调色主题；三种 App 图标随时切换；三档字体大小
- **手势自定义**：双击 / 长按条目可绑定动作（切换高光、标记完成、切换置顶、打开编辑）
- **本地通知**：带时间的待办到点提醒
- **数据管理**：一键导出全部记录为纯文本（系统分享）、清空数据
- **最近删除**：删除进回收站（软删除），可单条恢复、恢复全部、彻底删除
- 纯本地存储（SwiftData + App Group），无账号、无云端、无追踪
- 旧版 rDos 的任务数据会在首次启动时自动迁移为待办记录

## 技术栈

- Swift 5 / SwiftUI / SwiftData / WidgetKit
- iOS 26+（Liquid Glass、ultraThinMaterial、sensoryFeedback 等）
- AVAudioRecorder / AVAudioPlayer（语音）
- 零第三方依赖

## 构建

```bash
# 模拟器
xcodebuild -project rDos.xcodeproj -scheme rDos \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 真机（需要已配置的开发者签名）
xcodebuild -project rDos.xcodeproj -scheme rDos -configuration Release \
  -destination 'platform=iOS,id=<设备UDID>' -allowProvisioningUpdates build
```

> Debug 构建首次启动会预置少量示例记录（设置 → 开发者选项可清除）；Release 构建不包含任何预置数据。

## 项目结构

```
rDos/
  rDosApp.swift          # 入口、容器、旧数据迁移、调试示例(#if DEBUG)
  Record.swift           # 记录模型（文字/待办/照片/语音 + 标签解析）
  TaskItem.swift         # 旧版模型（仅迁移用）+ App Group 共享
  AppSettings.swift      # 设置持久化(@Observable)
  DayGrouping.swift      # 日期分组/格式化
  NotificationManager.swift
  AudioHelper.swift      # 录音/播放
  Theme.swift            # 动态配色、按压反馈样式
  MainView.swift         # 主界面（header/标签/输入栏）
  TimelineView.swift     # 时间线（置顶区 + 按天分组）
  RecordRowView.swift    # 记录行（四类型渲染/滑动/照片查看/高光）
  RecordInputBar.swift   # 底部输入栏（模式切换/照片/按住录音）
  RecordEditorView.swift # 记录编辑器
  Onboarding.swift       # 新手引导浮层
rDosWidgets/
  rDosWidgets.swift      # 桌面 + 锁屏小组件
```

## 致谢

- 待办一侧的产品 idea 来自 [@daimajia](https://x.com/daimajia/status/2091362554291577217) 的推文。
- rMinds 改版（聊天式时间线记录形态）参考了 [@cbvivi](https://x.com/cbvivi) 的 [mynd](https://x.com/myndnote) 应用——[相关推文](https://x.com/cbvivi/status/2038245566505971716)，也可以在 [App Store](https://apps.apple.com/cn/app/mynd-%E8%AE%B0%E5%BD%95%E4%B8%80%E5%88%87%E7%9A%84%E8%81%8A%E5%A4%A9%E5%BC%8F%E6%97%A5%E8%AE%B0/id6759103234) 下载体验原版。

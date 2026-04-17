# ChronoTick

ChronoTick 是一个面向 macOS 14+ 的本地优先时间管理应用，使用 SwiftUI + SwiftData 构建，聚焦周视图时间轴、自然文本建任务、本地提醒、CSV 导入导出与 Habit 打卡。

## 如何运行

1. 在 macOS 14+ 上安装 Xcode 15 或更高版本。
2. 打开项目目录中的 `Package.swift` 或 `ChronoTick.xcodeproj`。
3. 运行 `ChronoTick` 目标。
4. 首次启用提醒时允许通知权限。

如果你只装了 Command Line Tools，也可以在终端执行：

```bash
swift build
swift test
```

## 技术架构

- UI: SwiftUI
- 本地存储: SwiftData
- 架构: MVVM
- 通知: UserNotifications
- 数据交换: CSV（ISO 8601 日期时间）

主要分层：

- `Models/`: SwiftData 实体
- `ViewModels/`: 页面共享状态与任务编辑逻辑
- `Views/`: 周视图、日列表、打卡、设置、菜单栏等界面
- `Services/`: 提醒、CSV、Habit 统计、种子数据
- `Utilities/`: 时间文本解析、日期工具、CSV 文档

## 数据模型说明

### TaskItem

- `id: UUID`
- `title: String`
- `date: Date`
- `startDateTime: Date?`
- `endDateTime: Date?`
- `hasTime: Bool`
- `isCompleted: Bool`
- `reminderEnabled: Bool`
- `reminderOffsetMinutes: Int`
- `notes: String?`
- `createdAt: Date`
- `updatedAt: Date`

### Habit

- `id: UUID`
- `name: String`
- `colorHex: String?`
- `createdAt: Date`
- `updatedAt: Date`

### HabitCheckIn

- `id: UUID`
- `habit: Habit?`
- `date: Date`
- `isCheckedIn: Bool`

## 时间解析规则说明

支持以下格式：

- `23:30 ~ 23:50 read book`
- `23:30~23:50 read book`
- `09:00-10:30 Review paper`
- `9:00 Review paper`
- `18:30 dinner`
- `Complete things`

规则：

- 识别到开始和结束时间时，创建时间段任务
- 只识别到一个时间时，创建单时间点任务
- 未识别到时间时，创建无时间任务
- 结束时间早于开始时间时，给出中文错误提示

## CSV 格式说明

### 任务导出字段

`id,date,title,start_datetime,end_datetime,has_time,is_completed,reminder_enabled,reminder_offset_minutes,notes,created_at,updated_at`

### 打卡导出字段

`id,name,date,is_checked_in`

导入支持两种模式：

- 合并导入：按 `id` 或 `(date + title + 时间)` 近似去重
- 覆盖导入：先清空当前数据，再导入 CSV

示例文件见 [Samples/tasks_sample.csv](/Users/wenhant2/software/ChronoTick/Samples/tasks_sample.csv) 和 [Samples/habits_sample.csv](/Users/wenhant2/software/ChronoTick/Samples/habits_sample.csv)。

## 已知限制

- 时间轴拖拽目前为单任务直接吸附移动，尚未处理复杂重叠布局
- 单时间点任务支持拖动，不支持单独拉伸结束时间
- 菜单栏快速打开主应用当前使用激活现有应用窗口
- 第一版不包含重复任务、云同步、账号系统和多端协同

## 后续扩展建议

### 重复任务

- 为 `TaskItem` 增加 `RecurrenceRule` 实体或规则值对象
- 实例化未来 occurrences 时保持源任务与实例任务的映射关系
- 提前考虑“只改本次 / 改全部 / 改未来”的分叉策略

### iCloud 同步

- 持久层抽象出 repository 接口
- 在 SwiftData/Core Data 之上增加 CloudKit 同步层
- 冲突解决优先使用基于 `updatedAt` 的 last-write-wins，再逐步增强

### 多端同步

- 将任务与 habit 的变更记录化，设计可合并的 operation log
- 统一使用稳定 UUID、时区无关的 ISO 8601 与变更版本号
- 为通知、菜单栏和各平台视图层保留独立适配层

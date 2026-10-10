import SwiftUI

private let leaf = Color(red: 0.23, green: 0.39, blue: 0.31)
private let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
private let ink = Color(red: 0.17, green: 0.21, blue: 0.18)

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("给眼睛，一点留白。")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("柔和屏幕，记得休息。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "leaf")
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(leaf)
                    .frame(width: 56, height: 56)
                    .background(leaf.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            }

            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $model.filterEnabled) {
                    Label("柔和屏幕", systemImage: "sun.haze")
                        .font(.system(size: 16, weight: .semibold))
                }.toggleStyle(.switch)

                HStack {
                    Toggle("智能护眼", isOn: $model.smartEnabled)
                    Spacer()
                    Toggle("夜间助眠", isOn: $model.nightEnabled)
                }.toggleStyle(.switch).disabled(!model.filterEnabled)
                Text(model.smartEnabled ? "跟随本地时间调整：中午柔和，夜间增强。" : "手动选择强度，也可开启智能护眼随时间调整。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                filterSlider(model.smartEnabled ? "当前护眼强度 · 自动" : "手动护眼强度",
                             value: Binding(get: { model.effectiveLevel }, set: { model.warmth = $0 }),
                             start: "自然", end: "暖琥珀", symbol: "sun.max")
                    .disabled(model.smartEnabled)
                filterSlider("屏幕调暗", value: $model.dimming,
                             start: "原始亮度", end: "更暗", symbol: "moon")
                Text("关闭后恢复启用前的屏幕颜色。夜间助眠在 20:00—08:00 生效。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let error = model.gammaError {
                    Text("屏幕调节已暂停：" + error)
                        .font(.system(size: 11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $model.reminderEnabled) {
                    Label("休息提醒", systemImage: "eye")
                        .font(.system(size: 16, weight: .semibold))
                }.toggleStyle(.switch)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.schedule.phase == .resting ? "正在休息" : "距离下次休息")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(model.reminderEnabled ? model.countdown : "未开启")
                            .font(.system(size: model.reminderEnabled ? 34 : 25,
                                          weight: .medium, design: .rounded))
                            .monospacedDigit().foregroundStyle(leaf)
                    }
                    Spacer()
                    Button("现在休息", action: model.restNow)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.schedule.phase == .resting)
                }
                HStack(spacing: 20) {
                    Picker("间隔", selection: $model.interval) {
                        ForEach([20, 30, 45, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }
                    Picker("休息", selection: $model.duration) {
                        ForEach([20, 30, 60], id: \.self) { Text("\($0) 秒").tag($0) }
                    }
                }.font(.system(size: 12))
            }.padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))

            HStack(spacing: 7) {
                Image(systemName: "menubar.rectangle")
                Text("⌘M 最小化 · 关闭窗口后，可从菜单栏的眼睛图标打开")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(30)
        }
        .frame(width: 520, height: 710)
        .foregroundStyle(ink).tint(leaf).background(paper)
        .preferredColorScheme(.light)
    }

    private func filterSlider(_ title: String, value: Binding<Double>,
                              start: String, end: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1).accessibilityLabel(title)
            HStack {
                Text(start)
                Spacer()
                Text(end)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.opacity(model.filterEnabled ? 1 : 0.5).disabled(!model.filterEnabled)
    }
}

struct RestView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 48, weight: .ultraLight)).foregroundStyle(leaf)
            Text("把目光，交给远处。")
                .font(.system(size: 23, weight: .medium, design: .rounded))
            Text("暂时离开屏幕，眨眨眼，放松一下。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Text(model.countdown)
                .font(.system(size: 42, weight: .light, design: .rounded))
                .monospacedDigit().foregroundStyle(leaf)
            HStack(spacing: 12) {
                Button("稍后 5 分钟", action: model.snooze)
                Button("完成休息", action: model.finishRest).buttonStyle(.borderedProminent)
            }.controlSize(.large)
        }.padding(32).frame(width: 390)
            .foregroundStyle(ink).tint(leaf).background(paper).preferredColorScheme(.light)
    }
}

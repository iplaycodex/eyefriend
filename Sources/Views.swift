import SwiftUI

private let leaf = Color(red: 0.23, green: 0.39, blue: 0.31)
private let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
private let ink = Color(red: 0.17, green: 0.21, blue: 0.18)

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("给眼睛，一点留白。")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("跟随时间，自动调节屏幕。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "leaf")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(leaf)
                    .frame(width: 54, height: 54)
                    .background(leaf.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            }

            VStack(alignment: .leading, spacing: 20) {
                Toggle(isOn: $model.smartEnabled) {
                    Label("智能护眼", systemImage: "eye")
                        .font(.system(size: 17, weight: .semibold))
                }.toggleStyle(.switch)

                HStack(alignment: .firstTextBaseline) {
                    Text(model.smartEnabled ? "当前自动强度" : "屏幕原色")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.smartEnabled ? "\(Int((model.effectiveLevel * 100).rounded()))%" : "已关闭")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .monospacedDigit().foregroundStyle(leaf)
                }
                ProgressView(value: model.smartEnabled ? model.effectiveLevel : 0)
                    .accessibilityLabel("自动护眼强度")
                Text("按护眼宝的时间曲线自动调整，白天减弱、夜间增强。关闭即可恢复启用前的屏幕颜色。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = model.gammaError {
                    Text("智能护眼已暂停：" + error)
                        .font(.system(size: 11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))

            Label("⌘M 最小化 · 关闭窗口后可从菜单栏打开", systemImage: "menubar.rectangle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 500)
        .foregroundStyle(ink).tint(leaf).background(paper)
        .preferredColorScheme(.light)
    }
}

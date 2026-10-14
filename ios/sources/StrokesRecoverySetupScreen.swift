//
// Strokes:首次登录强制设置恢复密钥。
// 3 步:说明 → 显示钥匙(复制 + 勾选「已存好」)→ 输入最后 4 位验证。不能跳过、不能返回。
// 由 app/element-x-ios/apply-branding.sh 复制进 Element X 源码。
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import Compound
import SwiftUI

enum StrokesRecoverySetupAction {
    case done
    case logout
}

/// 生成钥匙后、验证完成前 App 被关掉:下次打开时重新生成一把,保证员工手里一定有存好的钥匙
enum StrokesRecoverySetup {
    private static let pendingKey = "strokesRecoverySetupPending"
    static var isPending: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }
}

final class StrokesRecoverySetupScreenCoordinator: CoordinatorProtocol {
    private let model: StrokesRecoverySetupModel
    var actions: AnyPublisher<StrokesRecoverySetupAction, Never> { model.actions.eraseToAnyPublisher() }

    init(secureBackupController: SecureBackupControllerProtocol) {
        model = StrokesRecoverySetupModel(secureBackupController: secureBackupController)
    }

    func toPresentable() -> AnyView {
        AnyView(StrokesRecoverySetupScreen(model: model))
    }
}

@MainActor
final class StrokesRecoverySetupModel: ObservableObject {
    enum Step { case explain, showKey, verify }

    @Published var step = Step.explain
    @Published var recoveryKey = ""
    @Published var isGenerating = false
    @Published var failed = false
    @Published var saved = false
    @Published var lastFour = ""
    @Published var wrongLastFour = false
    @Published private var recoveryState: SecureBackupRecoveryState

    let actions = PassthroughSubject<StrokesRecoverySetupAction, Never>()
    private let secureBackupController: SecureBackupControllerProtocol
    private var cancellable: AnyCancellable?

    init(secureBackupController: SecureBackupControllerProtocol) {
        self.secureBackupController = secureBackupController
        recoveryState = secureBackupController.recoveryState.value
        cancellable = secureBackupController.recoveryState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                recoveryState = state
                // 刚登录时状态可能还没加载完;加载完发现账号早已有钥匙(而且不是上次没走完),就不用设置
                if step == .explain, !isGenerating, !StrokesRecoverySetup.isPending, state == .enabled || state == .incomplete {
                    actions.send(.done)
                }
            }
    }

    /// 状态没加载完时先不让点,避免误把已有的钥匙换掉
    var canGenerate: Bool {
        !isGenerating && (recoveryState == .disabled || StrokesRecoverySetup.isPending)
    }

    func generate() {
        isGenerating = true
        failed = false
        StrokesRecoverySetup.isPending = true
        Task {
            switch await secureBackupController.generateRecoveryKey(withPassphrase: nil) {
            case .success(let key):
                recoveryKey = key
                step = .showKey
            case .failure:
                failed = true
            }
            isGenerating = false
        }
    }

    func verify() {
        let expected = String(recoveryKey.filter { !$0.isWhitespace }.suffix(4))
        if lastFour.trimmingCharacters(in: .whitespaces) == expected {
            StrokesRecoverySetup.isPending = false
            actions.send(.done)
        } else {
            wrongLastFour = true
        }
    }
}

struct StrokesRecoverySetupScreen: View {
    @ObservedObject var model: StrokesRecoverySetupModel
    @State private var copied = false

    var body: some View {
        Group {
            switch model.step {
            case .explain: explain
            case .showKey: showKey
            case .verify: verify
            }
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
    }

    // MARK: 第 1 屏:说明

    private var explain: some View {
        FullscreenDialog(topPadding: UIConstants.startScreenBreakerScreenTopPadding) {
            VStack(spacing: 16) {
                BigIcon(icon: \.lockSolid)
                title(Self.text("你的聊天记录有一个专属保险箱", "Your chats have a private safe"))
                paragraph(Self.text("你发的每条消息都锁在保险箱里,只有你能打开,公司和管理员都打不开(开启了翻译机器人的群除外:机器人会读取群消息来翻译)。",
                               "Every message you send is locked in this safe. Only you can open it — not the company, not the admins (except in groups with the translation bot, which reads group messages to translate them)."))
                paragraph(Self.text("保险箱的钥匙就是「恢复密钥」。平时用不到,换手机或重装 App 时才需要。",
                               "The key to the safe is your recovery key. You won't need it day to day — only when you change phones or reinstall the app."))
                if model.failed {
                    Text(Self.text("没能生成钥匙,请检查网络后重试。", "Couldn't create your key. Check your connection and try again."))
                        .font(.compound.bodyMDSemibold)
                        .foregroundColor(.compound.textCriticalPrimary)
                        .multilineTextAlignment(.center)
                }
            }
        } bottomContent: {
            VStack(spacing: 16) {
                Button {
                    model.generate()
                } label: {
                    if model.isGenerating || !model.canGenerate {
                        ProgressView()
                    } else {
                        Text(model.failed ? Self.text("重试", "Try again") : Self.text("领取我的钥匙", "Get my key"))
                    }
                }
                .buttonStyle(.compound(.primary))
                .disabled(!model.canGenerate)

                if model.failed {
                    Button(Self.text("退出登录", "Sign out")) { model.actions.send(.logout) }
                        .buttonStyle(.compound(.tertiary))
                }
            }
        }
    }

    // MARK: 第 2 屏:保存

    private var showKey: some View {
        FullscreenDialog {
            VStack(alignment: .leading, spacing: 16) {
                title(Self.text("这是你的钥匙,请收好", "This is your key — keep it safe"))
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.recoveryKey)
                        .font(.compound.bodyLG.monospaced())
                        .foregroundColor(.compound.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("strokesRecoveryKey")
                    Button {
                        UIPasteboard.general.string = model.recoveryKey
                        copied = true
                    } label: {
                        Label(copied ? Self.text("已复制", "Copied") : Self.text("复制", "Copy"), icon: \.copy)
                    }
                    .buttonStyle(.compound(.secondary, size: .medium))
                }
                .padding(16)
                .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))

                bullet(Self.text("钥匙只有这一把,公司不会替你保管。", "There is only one key. The company does not keep a copy."))
                bullet(Self.text("丢了钥匙,旧的聊天记录就任何人都打不开了,管理员也不行(新消息不受影响)。",
                                 "If you lose it, nobody can open your old chats — not even the admins (new messages are not affected)."))
                bullet(Self.text("建议存在:密码管理器 / 抄在纸上放好。不要发给别人,也不要存在聊天里。",
                                 "Keep it in a password manager or write it on paper. Never send it to anyone or save it in a chat."))

                Button {
                    model.saved.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        CompoundIcon(model.saved ? \.checkCircleSolid : \.circle)
                            .foregroundColor(model.saved ? .compound.iconAccentPrimary : .compound.iconSecondary)
                        Text(Self.text("我已经把钥匙存好了", "I have saved my key"))
                            .font(.compound.bodyLGSemibold)
                            .foregroundColor(.compound.textPrimary)
                    }
                }
                .accessibilityAddTraits(model.saved ? .isSelected : [])
            }
        } bottomContent: {
            Button(Self.text("下一步", "Next")) { model.step = .verify }
                .buttonStyle(.compound(.primary))
                .disabled(!model.saved)
        }
    }

    // MARK: 第 3 屏:验证

    private var verify: some View {
        FullscreenDialog {
            VStack(spacing: 16) {
                title(Self.text("确认一下", "Quick check"))
                paragraph(Self.text("输入钥匙的最后 4 位,确认你真的存好了。", "Enter the last 4 characters of your key to confirm you saved it."))
                TextField(Self.text("最后 4 位", "Last 4 characters"), text: $model.lastFour)
                    .font(.compound.headingMD.monospaced())
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: model.lastFour) { model.wrongLastFour = false }
                if model.wrongLastFour {
                    Text(Self.text("不对,请对照你存的钥匙再看一下(注意大小写)。", "That doesn't match. Check your saved key (letters are case-sensitive)."))
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textCriticalPrimary)
                        .multilineTextAlignment(.center)
                }
            }
        } bottomContent: {
            VStack(spacing: 16) {
                Button(Self.text("完成,开始聊天", "Done — start chatting")) { model.verify() }
                    .buttonStyle(.compound(.primary))
                    .disabled(model.lastFour.trimmingCharacters(in: .whitespaces).count < 4)
                Button(Self.text("再看一眼钥匙", "Show my key again")) { model.step = .showKey }
                    .buttonStyle(.compound(.tertiary))
            }
        }
    }

    // MARK: 小部件

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.compound.headingMDBold)
            .multilineTextAlignment(.center)
            .foregroundColor(.compound.textPrimary)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.compound.bodyMD)
            .multilineTextAlignment(.center)
            .foregroundColor(.compound.textSecondary)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🔑")
            Text(text)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textSecondary)
        }
    }

    /// 第一期只做中文、英文;系统语言是中文(简 / 繁)时显示中文
    private static func text(_ zh: String, _ en: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
    }
}

#!/usr/bin/env bash
# 在一份【全新的】Element X iOS 源码上套用 Strokes 品牌。
# 用法:bash apply-branding.sh <element-x-ios 源码目录> <compound-design-tokens 官方 v11.0.0 目录>
# 第二个参数:git clone --depth 1 --branch v11.0.0 https://github.com/element-hq/compound-design-tokens.git compound-design-tokens
#   (版本要与 compound-ios/Package.swift 一致)。脚本把我们的 63 个颜色(assets/compound-colors,由 app/design-system 生成)拷进去
set -euo pipefail
X="$1"
CDT_IOS="$(cd "$2" && pwd)"
# Xcode 按文件夹名识别本地包,必须叫 compound-design-tokens
[ "$(basename "$CDT_IOS")" = "compound-design-tokens" ] || { echo "第二个参数的文件夹名必须是 compound-design-tokens"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
A="$HERE/assets"

# 1. 名称、包名、团队(包名 com.strokes.chat)
python3 -I - "$X/app.yml" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
for a, b in [("APP_DISPLAY_NAME: Element X", "APP_DISPLAY_NAME: Strokes"),
             ("PRODUCTION_APP_NAME: Element", "PRODUCTION_APP_NAME: Strokes"),
             ("APP_GROUP_IDENTIFIER: group.io.element", "APP_GROUP_IDENTIFIER: group.com.strokes.chat"),
             ("BASE_BUNDLE_IDENTIFIER: io.element.elementx", "BASE_BUNDLE_IDENTIFIER: com.strokes.chat"),
             ("DEVELOPMENT_TEAM: 7J4U792NQT", "DEVELOPMENT_TEAM: Z58WFF3G5C")]:
    assert a in s, a
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY

# 1b. 系统弹窗里的 App 名(如登录时「"Strokes" 想使用 auth.strokes.cc 登录」)读的是 CFBundleName,原来显示 ElementX。
#     Info.plist 由 xcodegen 按 target.yml 重新生成,所以要改 target.yml(直接改 Info.plist 会被覆盖)
python3 -I - "$X/ElementX/SupportingFiles/target.yml" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = "        CFBundleDisplayName: $(APP_DISPLAY_NAME)\n"
assert s.count(a) == 1, a
open(p, "w", encoding="utf-8").write(s.replace(a, a + "        CFBundleName: $(PRODUCTION_APP_NAME)\n"))
PY

# 2. 配色:把我们的颜色拷进官方颜色包,compound-ios 改用这个本地包
cp -R "$A/compound-colors/Colors.xcassets/." "$CDT_IOS/assets/ios/swift/Colors.xcassets/"
grep -q '"red": "0.0431"' "$CDT_IOS/assets/ios/swift/Colors.xcassets/gray1400.colorset/Contents.json"  # 抽查:正文色深海蓝 #0B2A4A(0.0431×255=11)
python3 -I - "$X/compound-ios/Package.swift" "$CDT_IOS" <<'PY'
import sys
p, path = sys.argv[1], sys.argv[2]; s = open(p, encoding="utf-8").read()
a = '.package(url: "https://github.com/element-hq/compound-design-tokens", exact: "11.0.0"),'
assert a in s, a
s = s.replace(a, f'.package(path: "{path}"),  // Strokes 配色')
open(p, "w", encoding="utf-8").write(s)
PY

# 3. 自己发的气泡:浅蓝
F="$X/compound-ios/Sources/Compound/Colors/CompoundColors.swift"
sed -i '' 's|public let _bgBubbleOutgoing = Color(UIColor { $0.isLight ? UIColor(coreTokens.gray400) : UIColor(coreTokens.gray500) })|public let _bgBubbleOutgoing = Color(UIColor { $0.isLight ? UIColor(coreTokens.green400) : UIColor(coreTokens.green500) })|' "$F"
grep -q "coreTokens.green400" "$F"

# 4. 运行时设置:锁定服务器、关闭注册按钮和数据分析、链接与登录回调都用 strokes.cc
python3 -I - "$X/ElementX/Sources/Application/Settings/AppSettings.swift" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
pairs = [
 ('[.managed(serverName: "matrix.org", baseURL: "https://matrix-client.matrix.org")]',
  '[.managed(serverName: "strokes.cc", baseURL: "https://matrix.strokes.cc")]'),
 ("private(set) var allowOtherAccountProviders = true", "private(set) var allowOtherAccountProviders = false"),
 ('private(set) var websiteURL: URL = "https://element.io"', 'private(set) var websiteURL: URL = "https://strokes.cc"'),
 ('private(set) var logoURL: URL = "https://element.io/mobile-icon.png"', 'private(set) var logoURL: URL = "https://strokes.cc/app/logo.png"'),
 ('private(set) var copyrightURL: URL = "https://element.io/copyright"', 'private(set) var copyrightURL: URL = "https://strokes.cc/app/copyright"'),
 ('private(set) var acceptableUseURL: URL = "https://element.io/acceptable-use-policy-terms"', 'private(set) var acceptableUseURL: URL = "https://strokes.cc/app/terms"'),
 ('private(set) var privacyURL: URL = "https://element.io/privacy"', 'private(set) var privacyURL: URL = "https://strokes.cc/app/privacy"'),
 ('URL(string: "https://element.io/oauth/ios/\\(InfoPlistReader.main.bundleIdentifier)")',
  'URL(string: "https://strokes.cc/oauth/ios/\\(InfoPlistReader.main.bundleIdentifier)")'),
 ("let showCreateAccountButton = true", "let showCreateAccountButton = false"),
 ('private(set) var pushGatewayBaseURL: URL = "https://matrix.org"', 'private(set) var pushGatewayBaseURL: URL = "https://push.strokes.cc"  // 自建推送'),
 ("let appLockIsMandatory = false", "let appLockIsMandatory = true  // Strokes:强制应用锁"),
 ("let analyticsConfiguration: AnalyticsConfiguration? = AppSettings.makeAnalyticsConfiguration()",
  "let analyticsConfiguration: AnalyticsConfiguration? = nil  // Strokes:不做数据分析"),
 ('private(set) var analyticsTermsURL: URL? = "https://element.io/cookie-policy"', "private(set) var analyticsTermsURL: URL? = nil"),
 ("let bugReportSentryURL: URL? = Secrets.sentryDSN.map { URL(string: $0)! }", "let bugReportSentryURL: URL? = nil  // Strokes:不上报崩溃"),
 ("let bugReportSentryRustURL: URL? = Secrets.sentryRustDSN.map { URL(string: $0)! }", "let bugReportSentryRustURL: URL? = nil"),
]
for a, b in pairs:
    assert a in s, a
    s = s.replace(a, b, 1)
open(p, "w", encoding="utf-8").write(s)
PY

# 4b. App 声明的域名:只留 strokes.cc(苹果会到 https://strokes.cc/.well-known/apple-app-site-association 验证)
python3 -I - "$X/ElementX/SupportingFiles/target.yml" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
new = "        com.apple.developer.associated-domains:\n        - webcredentials:strokes.cc\n"
s, n = re.subn(r"        com\.apple\.developer\.associated-domains:\n(?:        (?:- |# ).*\n)+", new, s)
assert n == 1, n
open(p, "w", encoding="utf-8").write(s)
PY

# 4c. 去掉 我们的开发者账号拿不到的两项权限,否则正式签名打不了包:
#     - 主 App 的 group.im.vector:Element 公司旧版 App 的数据区(用于从旧版迁移账号),我们用不到
#     - 通知扩展的「通知过滤」:要苹果单独批准(2026-10-13 已申请,Request ID UVH779ZHUV);批准后删掉这段即可恢复
python3 -I - "$X/ElementX/SupportingFiles/target.yml" "$X/NSE/SupportingFiles/target.yml" <<'PY'
import sys
for p, a in [(sys.argv[1], "        - $(CLASSIC_APP_GROUP_IDENTIFIER)\n"),
             (sys.argv[2], "        com.apple.developer.usernotifications.filtering: true\n")]:
    s = open(p, encoding="utf-8").read()
    assert s.count(a) == 1, a
    open(p, "w", encoding="utf-8").write(s.replace(a, ""))
PY

# 5. App 图标(iOS 26 图标合成器格式,只有一张 1024)
cp "$A/AppIcon.png" "$X/ElementX/Resources/AppIcon.icon/Assets/AppIcon.png"

# 6. 欢迎页:logo(矢量)、背景、标语
IMG="$X/ElementX/Resources/Assets.xcassets/images"
rm -f "$IMG/app-logo.imageset/app-logo.pdf"
cp "$A/app-logo.svg" "$IMG/app-logo.imageset/app-logo.svg"
sed -i '' 's|"app-logo.pdf"|"app-logo.svg"|' "$IMG/app-logo.imageset/Contents.json"
cp "$A"/iphone-{light,dark}.png "$A"/ipad-{light,dark}.png "$IMG/launch-background.imageset/"
cp "$A"/background-bottom-{light,dark}.png "$IMG/background-bottom.imageset/"
L="$X/ElementX/Resources/Localizations"
s(){ python3 -I - "$L/$1.lproj/Localizable.strings" "$2" "$3" <<'PY'
import sys, re
p, title, msg = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
s, n1 = re.subn(r'^"screen_onboarding_welcome_title" = ".*";$', f'"screen_onboarding_welcome_title" = "{title}";', s, flags=re.M)
s, n2 = re.subn(r'^"screen_onboarding_welcome_message" = ".*";$', f'"screen_onboarding_welcome_message" = "{msg}";', s, flags=re.M)
assert n1 == 1 and n2 == 1, p
open(p, "w", encoding="utf-8").write(s)
PY
}
s en "Work chat, kept private" "Messages and calls for our team, end-to-end encrypted."
s en-US "Work chat, kept private" "Messages and calls for our team, end-to-end encrypted."
s zh-Hans "安心的工作沟通" "公司内部聊天与通话，全程端到端加密。"
s zh-Hant-TW "安心的工作溝通" "公司內部聊天與通話，全程端對端加密。"

# 7. 中文、英文里剩下的 "Element" 文字改成 Strokes(含相机 / 麦克风权限提示,苹果审核会看);
#    Element Pro / Classic / employees 指 Element 公司的其他产品,不改;
#    「空间 / Space」改叫「部门 / Department」(底部标签变成「聊天 / 部门」);「儲存空間」是存储的意思,不改
python3 -I - "$L" <<'PY'
import sys, re, glob
L = sys.argv[1]
KEEP = ("Element Pro", "Element Classic", "Element employees")
EN = [(r"\b[Ss]ubspaces\b", "sub-departments"), (r"\b[Ss]ubspace\b", "sub-department"), (r"\bSpaces\b", "Departments"), (r"\bspaces\b", "departments"), (r"\bSpace\b", "Department"), (r"\bspace\b", "department")]
SPACE = {"en": EN, "en-US": EN, "zh-Hans": [(r"(?<!存储)空间", "部门")], "zh-Hant-TW": [(r"(?<!儲存)空間", "部門")]}
def fix(t, lang):
    for a, b in SPACE[lang]:
        t = re.sub(a, b, t)
    for i, k in enumerate(KEEP):
        t = t.replace(k, f"\x00{i}\x00")
    t = t.replace("Element X", "Strokes").replace("Element Call", "Strokes Call")
    t = re.sub(r"\bElement\b", "Strokes", t)
    for i, k in enumerate(KEEP):
        t = t.replace(f"\x00{i}\x00", k)
    return t
n = 0
for lang in ("en", "en-US", "zh-Hans", "zh-Hant-TW"):
    for f in glob.glob(f"{L}/{lang}.lproj/*.strings*"):
        s = open(f, encoding="utf-8").read()
        if f.endswith(".strings"):   # 只改等号右边的值
            new = re.sub(r'^("[^"]+" = ")(.*)(";)$', lambda m: m.group(1) + fix(m.group(2), lang) + m.group(3), s, flags=re.M)
        else:                         # .stringsdict:只改 <string> 里的文字
            new = re.sub(r"(<string>)([^<]*)(</string>)", lambda m: m.group(1) + fix(m.group(2), lang) + m.group(3), s)
        if new != s:
            n += sum(1 for a, b in zip(s.splitlines(), new.splitlines()) if a != b)
            open(f, "w", encoding="utf-8").write(new)
print(f"  替换 {n} 行")
assert n > 0
PY

# 8. 首次登录强制设置恢复密钥:登录引导最后一步插入我们的 3 屏流程,不能跳过
mkdir -p "$X/ElementX/Sources/Screens/Onboarding/StrokesRecoverySetupScreen"
cp "$HERE/sources/StrokesRecoverySetupScreen.swift" "$X/ElementX/Sources/Screens/Onboarding/StrokesRecoverySetupScreen/"
python3 -I - "$X/ElementX/Sources/FlowCoordinators/OnboardingFlowCoordinator.swift" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
for a, b in [
    ("return isNewLogin || requiresVerification || requiresAppLockSetup || requiresAnalyticsSetup || requiresNotificationsSetup\n",
     "return isNewLogin || requiresVerification || requiresAppLockSetup || requiresAnalyticsSetup || requiresNotificationsSetup || requiresRecoverySetup\n"),
    ("""    private var requiresNotificationsSetup: Bool {
        !appSettings.hasRunNotificationPermissionsOnboarding
    }
""", """    private var requiresNotificationsSetup: Bool {
        !appSettings.hasRunNotificationPermissionsOnboarding
    }

    // Strokes:账号还没有恢复密钥就必须先设置(刚登录时状态可能还没加载完,也先进设置页等它加载)
    private var requiresRecoverySetup: Bool {
        let state = userSession.sessionSecurityStatePublisher.value
        guard state.verificationState == .verified else { return false }
        if StrokesRecoverySetup.isPending { return true }
        switch state.recoveryState {
        case .disabled: return true
        case .unknown, .settingUp: return isNewLogin
        case .enabled, .incomplete: return false
        }
    }
"""),
    ("""            case (_, _, .finished):
                isNewLogin = false
                appSettings.hasSignedInBefore = true
                actionsSubject.send(.dismiss)
                stateMachine.tryState(.initial)
""", """            case (_, _, .finished):
                if requiresRecoverySetup {
                    presentStrokesRecoverySetupScreen()
                } else {
                    finishOnboarding()
                }
"""),
    ("""    private func presentCoordinator(_ coordinator: CoordinatorProtocol""", """    private func finishOnboarding() {
        isNewLogin = false
        appSettings.hasSignedInBefore = true
        actionsSubject.send(.dismiss)
        stateMachine.tryState(.initial)
    }

    private func presentStrokesRecoverySetupScreen() {
        let coordinator = StrokesRecoverySetupScreenCoordinator(secureBackupController: userSession.clientProxy.secureBackupController)
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .done: self?.finishOnboarding()
                case .logout: self?.actionsSubject.send(.logoutConfirmed)
                }
            }
            .store(in: &cancellables)
        presentCoordinator(coordinator)
    }

    private func presentCoordinator(_ coordinator: CoordinatorProtocol"""),
]:
    assert s.count(a) == 1, "OnboardingFlowCoordinator.swift 结构变了:" + a[:50]
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY

# 重新生成 Xcode 工程
(cd "$X" && xcodegen >/dev/null)
echo "Strokes 品牌已套用。改动的文件数:"
git -C "$X" status --short | wc -l

#!/usr/bin/env bash
# 在一份【全新的】Element X Android 源码上套用 Strokes 品牌。
# 2026-10-12 在 v26.09.4 上验证通过(见本目录 README.md)。
# 用法:bash apply-branding.sh <element-x-android 源码目录>
set -euo pipefail
X="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
CDT="$HERE/assets/compound-android"   # 由 app/design-system 的调色板经 compound-design-tokens 生成
ICON="$HERE/assets/launcher"
OB="$HERE/assets/onboarding"

# 1. 名称、包名(com.strokes.chat,覆盖旧 Rocket.Chat 版)
sed -i '' \
  -e 's|const val APPLICATION_ID = "io.element.android.x"|const val APPLICATION_ID = "com.strokes.chat"|' \
  -e 's|const val APPLICATION_NAME = "Element X"|const val APPLICATION_NAME = "Strokes"|' \
  "$X/plugins/src/main/kotlin/config/BuildTimeConfig.kt"

# 2. 锁定只连公司服务器
F="$X/features/enterprise/impl-foss/src/main/kotlin/io/element/android/features/enterprise/impl/DefaultEnterpriseService.kt"
python3 -I - "$F" <<'EOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
pairs = [
 ("override fun accountProviderAllowList(): List<AccountProvider> = emptyList()",
  'override fun accountProviderAllowList(): List<AccountProvider> = listOf(\n'
  '        AccountProvider.Managed(serverName = "strokes.cc", baseUrl = "https://matrix.strokes.cc", canUseServerName = true),\n'
  '    )'),
 ("override fun canConnectToAnyAccountProvider(): Boolean = true",
  "override fun canConnectToAnyAccountProvider(): Boolean = false"),
 ("override suspend fun isAllowedToConnectToAccountProvider(accountProvider: AccountProvider) = true",
  'override suspend fun isAllowedToConnectToAccountProvider(accountProvider: AccountProvider) =\n'
  '        accountProvider.serverNameOrBaseUrl().removePrefix("https://").substringBefore("/") in setOf("strokes.cc", "matrix.strokes.cc")'),
]
for a, b in pairs:
    assert a in s, a
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
EOF

# 3. 关闭 App 内注册账号入口
sed -i '' 's|const val CAN_CREATE_ACCOUNT = true|const val CAN_CREATE_ACCOUNT = false|' \
  "$X/appconfig/src/main/kotlin/io/element/android/appconfig/OnBoardingConfig.kt"

# 4. 配色:换上我们生成的 4 个颜色文件
cp "$CDT"/{Light,Dark,LightHc,DarkHc}ColorTokens.kt \
  "$X/libraries/compound/src/main/kotlin/io/element/android/compound/tokens/generated/internal/"

# 5. 自己发的气泡:浅蓝
sed -i '' \
  's|get() = if (isLight) LightColorTokens.colorGray400 else DarkColorTokens.colorGray500|get() = if (isLight) LightColorTokens.colorGreen400 else DarkColorTokens.colorGreen500|' \
  "$X/libraries/designsystem/src/main/kotlin/io/element/android/libraries/designsystem/theme/ColorAliases.kt"

# 6. 图标:删掉原 webp,放入 png;背景色改深海蓝
R="$X/appicon/element/src/main/res"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  rm -f "$R/mipmap-$d"/ic_launcher*.webp
  cp "$ICON/mipmap-$d"/*.png "$R/mipmap-$d/"
done
cp "$ICON/ic_launcher-playstore.png" "$X/appicon/element/src/main/ic_launcher-playstore.png"
for v in debug release nightly; do
  sed -i '' -E 's|android:fillColor="#[0-9A-Fa-f]{6}"|android:fillColor="#0B2A4A"|' "$X/appicon/element/src/$v/res/drawable/ic_launcher_background.xml"
done

# 7. 彻底关闭数据分析(PostHog / Sentry 模块不打包,也不弹「是否发送使用数据」)
python3 -I - "$X/plugins/src/main/kotlin/ModulesConfig.kt" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
if "Analytics disabled (Strokes)" in s: sys.exit(0)  # 已改过
a = """        println("Analytics enabled with Posthog and Sentry")
        AnalyticsConfig.Enabled(
            withPosthog = true,
            withSentry = true,
        )"""
assert a in s
s = s.replace(a, """        println("Analytics disabled (Strokes)")
        AnalyticsConfig.Disabled""")
open(p, "w", encoding="utf-8").write(s)
PY

# 8. 欢迎页:产品名、logo、背景、标语
sed -i '' -E 's#const val (PRODUCTION|DESKTOP)_APPLICATION_NAME: String = "Element"#const val \1_APPLICATION_NAME: String = "Strokes"#' \
  "$X/appconfig/src/main/kotlin/io/element/android/appconfig/ApplicationConfig.kt"
DS="$X/libraries/designsystem/src/main/res"
cp "$OB/element_logo.png" "$DS/drawable-xxhdpi/element_logo.png"
cp "$OB/element_logo.png" "$DS/drawable-night-xxhdpi/element_logo.png"
cp "$OB/onboarding_bg_light.png" "$DS/drawable/onboarding_bg.png"
cp "$OB/onboarding_bg_dark.png" "$DS/drawable-night/onboarding_bg.png"
L="$X/features/login/impl/src/main"
python3 -I - "$L/kotlin/io/element/android/features/login/impl/screens/onboarding/OnBoardingView.kt" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
for a, b in [("R.string.screen_onboarding_welcome_title)", "R.string.strokes_onboarding_title)"),
             ("R.string.screen_onboarding_welcome_message, state.productionApplicationName)", "R.string.strokes_onboarding_message)")]:
    assert a in s, a
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
w(){ mkdir -p "$L/res/$1"; printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="strokes_onboarding_title">%s</string>\n    <string name="strokes_onboarding_message">%s</string>\n</resources>\n' "$2" "$3" > "$L/res/$1/strokes_strings.xml"; }
w values "Work chat, kept private" "Messages and calls for our team, end-to-end encrypted."
w values-zh "安心的工作沟通" "公司内部聊天与通话，全程端到端加密。"
w values-zh-rTW "安心的工作溝通" "公司內部聊天與通話，全程端對端加密。"

# 9. 强制应用锁:员工必须设 PIN 码或指纹
sed -i '' 's|const val IS_PIN_MANDATORY: Boolean = false|const val IS_PIN_MANDATORY: Boolean = true|' \
  "$X/appconfig/src/main/kotlin/io/element/android/appconfig/LockScreenConfig.kt"
grep -q "IS_PIN_MANDATORY: Boolean = true" "$X/appconfig/src/main/kotlin/io/element/android/appconfig/LockScreenConfig.kt"

# 10. 推送:走自建推送服务器 push.strokes.cc。谷歌 Firebase 配置(firebase.xml)要等 Firebase 项目建好后再换
sed -i '' 's|const val PUSHER_HTTP_URL: String = "https://matrix.org/_matrix/push/v1/notify"|const val PUSHER_HTTP_URL: String = "https://push.strokes.cc/_matrix/push/v1/notify"|' \
  "$X/libraries/pushproviders/firebase/src/main/kotlin/io/element/android/libraries/pushproviders/firebase/FirebaseConfig.kt"
sed -i '' -E 's#val PUSHER_APP_ID_(RELEASE|DEBUG): String\? = null#val PUSHER_APP_ID_\1: String? = "com.strokes.chat.android"#' \
  "$X/plugins/src/main/kotlin/config/BuildTimeConfig.kt"
grep -q "push.strokes.cc" "$X/libraries/pushproviders/firebase/src/main/kotlin/io/element/android/libraries/pushproviders/firebase/FirebaseConfig.kt"

# 10b. 登录时向登录服务自报身份用 strokes.cc(原来是 element.io,登录页会显示 Element 的名字和链接);
#      登录回调地址随之变成 cc.strokes:/(登录服务要求它是 client_uri 域名倒过来写)。条款、隐私页
sed -i '' -E \
  -e 's#val METADATA_HOST_REVERSED: String\? = null#val METADATA_HOST_REVERSED: String? = "cc.strokes"#' \
  -e 's#val URL_WEBSITE: String\? = null#val URL_WEBSITE: String? = "https://strokes.cc"#' \
  -e 's#val URL_LOGO: String\? = null#val URL_LOGO: String? = "https://strokes.cc/app/logo.png"#' \
  -e 's#val URL_COPYRIGHT: String\? = null#val URL_COPYRIGHT: String? = "https://strokes.cc/app/copyright"#' \
  -e 's#val URL_ACCEPTABLE_USE: String\? = null#val URL_ACCEPTABLE_USE: String? = "https://strokes.cc/app/terms"#' \
  -e 's#val URL_PRIVACY: String\? = null#val URL_PRIVACY: String? = "https://strokes.cc/app/privacy"#' \
  -e 's#val URL_POLICY: String\? = null#val URL_POLICY: String? = "https://strokes.cc/app/privacy"#' \
  "$X/plugins/src/main/kotlin/config/BuildTimeConfig.kt"
[ "$(grep -c 'strokes' "$X/plugins/src/main/kotlin/config/BuildTimeConfig.kt")" -ge 10 ]

# 10c. 正式包用 Strokes 签名密钥(原版正式包也用调试密钥签名)。必须与旧 Rocket.Chat 版是同一把密钥才能覆盖安装。
#      密钥和密码不进仓库:沿用旧版做法,从构建机的 ~/.gradle/gradle.properties 读 KEYSTORE / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD
# 。没配置时打正式包会报错,调试包不受影响
python3 -I - "$X/app/build.gradle.kts" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = "    signingConfigs {\n"
b = a + '''        register("strokes") {
            (project.findProperty("KEYSTORE") as String?)?.let { storeFile = file(it) }
            storePassword = project.findProperty("KEYSTORE_PASSWORD") as String?
            keyAlias = project.findProperty("KEY_ALIAS") as String?
            keyPassword = project.findProperty("KEY_PASSWORD") as String?
        }
'''
c = '''                oAuthRedirectSchemeBase,
            )
            signingConfig = signingConfigs.getByName("debug")
'''
assert s.count(a) == 1 and s.count(c) == 1, "build.gradle.kts 结构变了"
s = s.replace(a, b).replace(c, c.replace('"debug"', '"strokes"'))
open(p, "w", encoding="utf-8").write(s)
PY

# 11.中文、英文里剩下的 "Element" 文字改成 Strokes(Element Pro / Classic / employees 指 Element 公司的其他产品,不改);
#     「空间 / Space」改叫「部门 / Department」(底部标签变成「聊天 / 部门」);「金鑰儲存空間」是存储的意思,不改
#     做法:在 app 模块生成同名字符串覆盖各模块的原文,不改原文件,跟进官方升级时不冲突
python3 -I - "$X" <<'PY'
import sys, os, re, glob, copy
import xml.etree.ElementTree as ET
X = sys.argv[1]
KEEP = ("Element Pro", "Element Classic", "Element employees")
SPACE = {"values": [(r"\b[Ss]ubspaces\b", "sub-departments"), (r"\b[Ss]ubspace\b", "sub-department"), (r"\bSpaces\b", "Departments"), (r"\bspaces\b", "departments"), (r"\bSpace\b", "Department"), (r"\bspace\b", "department")],
         "values-zh": [(r"(?<!存储)空间", "部门")],
         "values-zh-rTW": [(r"(?<!儲存)空間", "部門")]}
def fix(t, q):
    if not t:
        return t
    for a, b in SPACE[q]:
        t = re.sub(a, b, t)
    if "Element" not in t:
        return t
    for i, k in enumerate(KEEP):
        t = t.replace(k, f"\x00{i}\x00")
    t = t.replace("Element X", "Strokes").replace("Element Call", "Strokes Call")
    t = re.sub(r"\bElement\b", "Strokes", t)
    for i, k in enumerate(KEEP):
        t = t.replace(f"\x00{i}\x00", k)
    return t
total = 0
for q in ("values", "values-zh", "values-zh-rTW"):
    out = {}
    for f in glob.glob(f"{X}/**/src/main/res/{q}/*.xml", recursive=True):
        if "/build/" in f or "/app/src/" in f:
            continue
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        for el in root:
            if el.tag not in ("string", "plurals"):
                continue
            texts = [el] if el.tag == "string" else list(el)
            if not any(x.text and fix(x.text, q) != x.text for x in texts):
                continue
            new = copy.deepcopy(el)
            for x in ([new] if new.tag == "string" else list(new)):
                x.text = fix(x.text, q)
            out[el.get("name")] = new
    if out:
        d = f"{X}/app/src/main/res/{q}"
        os.makedirs(d, exist_ok=True)
        res = ET.Element("resources")
        res.text = "\n    "
        for name in sorted(out):
            e = out[name]; e.tail = "\n    "; res.append(e)
        res[-1].tail = "\n"
        ET.ElementTree(res).write(f"{d}/strokes_brand_strings.xml", encoding="utf-8", xml_declaration=True)
        total += len(out)
        print(f"  {q}: 覆盖 {len(out)} 条")
assert total > 0
PY

# 12. 首次登录强制设置恢复密钥:登录引导(FTUE)最后一步插入我们的 3 屏流程,不能跳过
FT="$X/features/ftue/impl/src"
mkdir -p "$FT/main/kotlin/io/element/android/features/ftue/impl/strokesrecovery"
cp "$HERE/sources/StrokesRecoverySetupNode.kt" "$FT/main/kotlin/io/element/android/features/ftue/impl/strokesrecovery/"
python3 -I - "$FT" <<'PY'
import sys
FT = sys.argv[1]
K = f"{FT}/main/kotlin/io/element/android/features/ftue/impl"
def patch(p, reps):
    s = open(p, encoding="utf-8").read()
    for a, b in reps:
        assert s.count(a) == 1, f"{p} 结构变了:{a[:50]}"
        s = s.replace(a, b)
    open(p, "w", encoding="utf-8").write(s)

patch(f"{K}/state/DefaultFtueService.kt", [
    ("import io.element.android.libraries.matrix.api.verification.SessionVerificationService\n",
     "import io.element.android.features.ftue.impl.strokesrecovery.StrokesRecoveryPending\n"
     "import io.element.android.libraries.matrix.api.encryption.EncryptionService\n"
     "import io.element.android.libraries.matrix.api.encryption.RecoveryState\n"
     "import io.element.android.libraries.matrix.api.verification.SessionVerificationService\n"),
    ("    private val sessionPreferencesStore: SessionPreferencesStore,\n) : FtueService {",
     "    private val sessionPreferencesStore: SessionPreferencesStore,\n"
     "    private val encryptionService: EncryptionService,\n"
     "    private val strokesRecoveryPending: StrokesRecoveryPending,\n) : FtueService {"),
    ("            analyticsService.didAskUserConsentFlow.distinctUntilChanged(),\n",
     "            analyticsService.didAskUserConsentFlow.distinctUntilChanged(),\n"
     "            encryptionService.recoveryStateStateFlow,\n"),
    ("            FtueStep.AnalyticsOptIn -> null\n",
     "            FtueStep.AnalyticsOptIn -> if (needsStrokesRecoverySetup()) {\n"
     "                FtueStep.StrokesRecoverySetup\n"
     "            } else {\n"
     "                null\n"
     "            }\n"
     "            FtueStep.StrokesRecoverySetup -> null\n"),
    ("    fun onUserCompletedSessionVerification() {",
     "    // Strokes:账号还没有恢复密钥(或上次没走完)就必须先设置;第二台手机验证前不会走到这里\n"
     "    private fun needsStrokesRecoverySetup(): Boolean {\n"
     "        return sessionVerificationService.sessionVerifiedStatus.value == SessionVerifiedStatus.Verified &&\n"
     "            (strokesRecoveryPending.isPending || encryptionService.recoveryStateStateFlow.value == RecoveryState.DISABLED)\n"
     "    }\n\n"
     "    fun onUserCompletedSessionVerification() {"),
    ("    data object LockscreenSetup : FtueStep\n",
     "    data object LockscreenSetup : FtueStep\n    data object StrokesRecoverySetup : FtueStep\n"),
])

patch(f"{K}/FtueFlowNode.kt", [
    ("import io.element.android.features.ftue.impl.state.InternalFtueState\n",
     "import io.element.android.features.ftue.impl.state.InternalFtueState\n"
     "import io.element.android.features.ftue.impl.strokesrecovery.StrokesRecoverySetupNode\n"),
    ("        @Parcelize\n        data object LockScreenSetup : NavTarget\n",
     "        @Parcelize\n        data object LockScreenSetup : NavTarget\n\n"
     "        @Parcelize\n        data object StrokesRecoverySetup : NavTarget\n"),
    ("            NavTarget.LockScreenSetup -> {\n",
     "            NavTarget.StrokesRecoverySetup -> {\n"
     "                val callback = object : StrokesRecoverySetupNode.Callback {\n"
     "                    override fun onDone() {\n"
     "                        defaultFtueService.updateFtueStep()\n"
     "                    }\n"
     "                }\n"
     "                createNode<StrokesRecoverySetupNode>(buildContext, listOf(callback))\n"
     "            }\n"
     "            NavTarget.LockScreenSetup -> {\n"),
    ("            FtueStep.LockscreenSetup -> {\n                backstack.newRoot(NavTarget.LockScreenSetup)\n            }\n",
     "            FtueStep.LockscreenSetup -> {\n                backstack.newRoot(NavTarget.LockScreenSetup)\n            }\n"
     "            FtueStep.StrokesRecoverySetup -> {\n                backstack.newRoot(NavTarget.StrokesRecoverySetup)\n            }\n"),
])

# 单元测试的构造函数跟着加两个参数(默认恢复状态 UNKNOWN,不影响原有用例)
T = f"{FT}/test/kotlin/io/element/android/features/ftue/impl/DefaultFtueServiceTest.kt"
patch(T, [
    ("    sessionPreferencesStore = sessionPreferencesStore,\n)",
     "    sessionPreferencesStore = sessionPreferencesStore,\n"
     "    encryptionService = io.element.android.libraries.matrix.test.encryption.FakeEncryptionService(),\n"
     "    strokesRecoveryPending = object : io.element.android.features.ftue.impl.strokesrecovery.StrokesRecoveryPending {\n"
     "        override var isPending = false\n"
     "    },\n)"),
])
PY

echo "Strokes 品牌已套用。改动的文件数:"
git -C "$X" status --short | wc -l

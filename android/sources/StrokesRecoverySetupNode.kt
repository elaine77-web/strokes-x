/*
 * Strokes:首次登录强制设置恢复密钥。
 * 3 步:说明 → 显示钥匙(复制 + 勾选「已存好」)→ 输入最后 4 位验证。不能跳过、不能返回。
 * 由 app/element-x-android/apply-branding.sh 复制进 Element X 源码(features/ftue/impl)。
 *
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package io.element.android.features.ftue.impl.strokesrecovery

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.background
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import com.bumble.appyx.core.modality.BuildContext
import com.bumble.appyx.core.node.Node
import com.bumble.appyx.core.plugin.Plugin
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Assisted
import dev.zacsweers.metro.AssistedInject
import dev.zacsweers.metro.ContributesBinding
import dev.zacsweers.metro.SingleIn
import io.element.android.annotations.ContributesNode
import io.element.android.compound.theme.ElementTheme
import io.element.android.compound.tokens.generated.CompoundIcons
import io.element.android.libraries.architecture.NodeInputs
import io.element.android.libraries.architecture.inputs
import io.element.android.libraries.designsystem.atomic.pages.FlowStepPage
import io.element.android.libraries.designsystem.components.BigIcon
import io.element.android.libraries.designsystem.components.list.CheckboxListItem
import io.element.android.libraries.designsystem.theme.components.Button
import io.element.android.libraries.designsystem.theme.components.OutlinedButton
import io.element.android.libraries.designsystem.theme.components.Text
import io.element.android.libraries.designsystem.theme.components.TextButton
import io.element.android.libraries.designsystem.theme.components.TextField
import io.element.android.libraries.di.SessionScope
import io.element.android.libraries.di.annotations.ApplicationContext
import io.element.android.libraries.matrix.api.encryption.EncryptionService
import io.element.android.libraries.matrix.api.encryption.RecoveryState
import kotlinx.coroutines.launch
import java.util.Locale

/** 生成钥匙后、验证完成前 App 被关掉:下次打开时重新生成一把,保证员工手里一定有存好的钥匙 */
interface StrokesRecoveryPending {
    var isPending: Boolean
}

@ContributesBinding(AppScope::class)
@SingleIn(AppScope::class)
class SharedPrefsStrokesRecoveryPending(
    @ApplicationContext context: Context,
) : StrokesRecoveryPending {
    private val prefs = context.getSharedPreferences("strokes_recovery_setup", Context.MODE_PRIVATE)
    override var isPending: Boolean
        get() = prefs.getBoolean("pending", false)
        set(value) = prefs.edit { putBoolean("pending", value) }
}

@ContributesNode(SessionScope::class)
@AssistedInject
class StrokesRecoverySetupNode(
    @Assisted buildContext: BuildContext,
    @Assisted plugins: List<Plugin>,
    private val encryptionService: EncryptionService,
    private val pending: StrokesRecoveryPending,
) : Node(buildContext, plugins = plugins) {
    interface Callback : NodeInputs {
        fun onDone()
    }

    private val callback = inputs<Callback>()

    @Composable
    override fun View(modifier: Modifier) {
        StrokesRecoverySetupView(encryptionService, pending, onDone = { callback.onDone() }, modifier = modifier)
    }
}

private enum class Step { Explain, ShowKey, Verify }

@Composable
private fun StrokesRecoverySetupView(
    encryptionService: EncryptionService,
    pending: StrokesRecoveryPending,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var step by rememberSaveable { mutableStateOf(Step.Explain) }
    var recoveryKey by rememberSaveable { mutableStateOf("") }
    var saved by rememberSaveable { mutableStateOf(false) }
    var lastFour by rememberSaveable { mutableStateOf("") }
    var wrongLastFour by remember { mutableStateOf(false) }
    var isGenerating by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    // 不能返回、不能跳过;第 3 屏可以回到第 2 屏再看一眼钥匙
    BackHandler { if (step == Step.Verify) step = Step.ShowKey }

    when (step) {
        Step.Explain -> FlowStepPage(
            modifier = modifier,
            iconStyle = BigIcon.Style.Default(CompoundIcons.LockSolid()),
            title = text("你的聊天记录有一个专属保险箱", "Your chats have a private safe"),
            subTitle = text(
                "你发的每条消息都锁在保险箱里,只有你能打开,公司和管理员都打不开(开启了翻译机器人的群除外:机器人会读取群消息来翻译)。\n\n保险箱的钥匙就是「恢复密钥」。平时用不到,换手机或重装 App 时才需要。",
                "Every message you send is locked in this safe. Only you can open it — not the company, not the admins (except in groups with the translation bot, which reads group messages to translate them).\n\n" +
                    "The key to the safe is your recovery key. You won't need it day to day — only when you change phones or reinstall the app.",
            ),
            content = {
                if (failed) {
                    Text(
                        text = text("没能生成钥匙,请检查网络后重试。", "Couldn't create your key. Check your connection and try again."),
                        color = ElementTheme.colors.textCriticalPrimary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            buttons = {
                Button(
                    text = if (failed) text("重试", "Try again") else text("领取我的钥匙", "Get my key"),
                    showProgress = isGenerating,
                    enabled = !isGenerating,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        isGenerating = true
                        failed = false
                        // 上次没走完(钥匙已生成但没确认存好):换一把新的;否则第一次开启
                        val regenerate = pending.isPending && encryptionService.recoveryStateStateFlow.value != RecoveryState.DISABLED
                        pending.isPending = true
                        scope.launch {
                            val result = if (regenerate) {
                                encryptionService.resetRecoveryKey()
                            } else {
                                encryptionService.enableRecovery(waitForBackupsToUpload = false)
                            }
                            result
                                .onSuccess {
                                    recoveryKey = it
                                    step = Step.ShowKey
                                }
                                .onFailure { failed = true }
                            isGenerating = false
                        }
                    },
                )
            },
        )
        Step.ShowKey -> FlowStepPage(
            modifier = modifier,
            isScrollable = true,
            iconStyle = BigIcon.Style.Default(CompoundIcons.KeySolid()),
            title = text("这是你的钥匙,请收好", "This is your key — keep it safe"),
            content = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(ElementTheme.colors.bgSubtleSecondary, RoundedCornerShape(12.dp))
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = recoveryKey,
                            style = ElementTheme.typography.fontBodyLgRegular.copy(fontFamily = FontFamily.Monospace),
                            color = ElementTheme.colors.textPrimary,
                        )
                        OutlinedButton(
                            text = text("复制", "Copy"),
                            onClick = { clipboard.setText(AnnotatedString(recoveryKey)) },
                        )
                    }
                    Bullet(text("钥匙只有这一把,公司不会替你保管。", "There is only one key. The company does not keep a copy."))
                    Bullet(
                        text(
                            "丢了钥匙,旧的聊天记录就任何人都打不开了,管理员也不行(新消息不受影响)。",
                            "If you lose it, nobody can open your old chats — not even the admins (new messages are not affected).",
                        )
                    )
                    Bullet(
                        text(
                            "建议存在:密码管理器 / 抄在纸上放好。不要发给别人,也不要存在聊天里。",
                            "Keep it in a password manager or write it on paper. Never send it to anyone or save it in a chat.",
                        )
                    )
                    CheckboxListItem(
                        headline = text("我已经把钥匙存好了", "I have saved my key"),
                        checked = saved,
                        onChange = { saved = it },
                    )
                }
            },
            buttons = {
                Button(
                    text = text("下一步", "Next"),
                    enabled = saved,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { step = Step.Verify },
                )
            },
        )
        Step.Verify -> FlowStepPage(
            modifier = modifier,
            iconStyle = BigIcon.Style.Default(CompoundIcons.KeySolid()),
            title = text("确认一下", "Quick check"),
            subTitle = text("输入钥匙的最后 4 位,确认你真的存好了。", "Enter the last 4 characters of your key to confirm you saved it."),
            content = {
                TextField(
                    value = lastFour,
                    onValueChange = {
                        lastFour = it
                        wrongLastFour = false
                    },
                    placeholder = text("最后 4 位", "Last 4 characters"),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                    supportingText = if (wrongLastFour) {
                        text("不对,请对照你存的钥匙再看一下(注意大小写)。", "That doesn't match. Check your saved key (letters are case-sensitive).")
                    } else {
                        null
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            buttons = {
                Button(
                    text = text("完成,开始聊天", "Done — start chatting"),
                    enabled = lastFour.trim().length >= 4,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        val expected = recoveryKey.filterNot { it.isWhitespace() }.takeLast(4)
                        if (lastFour.trim() == expected) {
                            pending.isPending = false
                            onDone()
                        } else {
                            wrongLastFour = true
                        }
                    },
                )
                TextButton(
                    text = text("再看一眼钥匙", "Show my key again"),
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { step = Step.ShowKey },
                )
            },
        )
    }
}

@Composable
private fun Bullet(content: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = "🔑")
        Text(text = content, color = ElementTheme.colors.textSecondary, style = ElementTheme.typography.fontBodyMdRegular)
    }
}

/** 第一期只做中文、英文;系统语言是中文(简 / 繁)时显示中文 */
private fun text(zh: String, en: String): String = if (Locale.getDefault().language == "zh") zh else en

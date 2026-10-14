# Strokes(Element X 定制版)源代码

Strokes 是我们公司内部使用的聊天 App,基于 [Element X](https://element.io)(iOS / Android)定制。Element X 以 **GNU AGPL-3.0** 许可发布,按许可要求,这里公开我们对它做的全部改动和重新构建的方法。

Strokes is our company's internal chat app, a customised build of [Element X](https://element.io) for iOS and Android. Element X is licensed under the **GNU AGPL-3.0**; as the licence requires, this repository publishes all of our changes and how to rebuild the app.

## 内容 / Contents

| 目录 | 说明 |
|---|---|
| `ios/apply-branding.sh` | 在官方 Element X iOS 源码上套用全部改动的脚本 |
| `ios/sources/` | 新增的「首次登录设置恢复密钥」页面 |
| `ios/assets/` | 图标、欢迎页图片、配色(Compound 设计令牌的颜色值) |
| `android/apply-branding.sh` | 在官方 Element X Android 源码上套用全部改动的脚本 |
| `android/sources/` | 新增的「首次登录设置恢复密钥」页面 |
| `android/assets/` | 图标、欢迎页图片、配色 |

改动内容:App 名称、包名和图标;配色;锁定只能登录公司服务器;关闭注册入口、数据分析和崩溃上报;强制应用锁;推送走公司自建推送服务器;首次登录强制设置恢复密钥;「空间」改称「部门」;界面文字中的产品名。

Changes: app name, bundle ID and icons; colours; locked to the company homeserver; sign-up, analytics and crash reporting removed; mandatory app lock; push via the company's own push gateway; mandatory recovery-key setup on first sign-in; "Spaces" renamed "Departments"; product name in UI strings.

## 基于的上游版本 / Upstream versions

| 平台 | Element X 版本 | 提交 |
|---|---|---|
| iOS | `release/26.09.2` | `47f881c` |
| Android | `v26.09.4` | `8f078659` |

## 构建 / Build

**iOS**(macOS + Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen))
```bash
git clone --branch release/26.09.2 https://github.com/element-hq/element-x-ios.git element-x-ios
git clone --depth 1 --branch v11.0.0 https://github.com/element-hq/compound-design-tokens.git compound-design-tokens
bash ios/apply-branding.sh element-x-ios compound-design-tokens
cd element-x-ios && xcodebuild -project ElementX.xcodeproj -scheme ElementX -configuration Release build
```
装到真机或上架需要你自己的苹果开发者账号签名。

**Android**(JDK 21 + Android SDK)
```bash
git clone --branch v26.09.4 https://github.com/element-hq/element-x-android.git element-x-android
bash android/apply-branding.sh element-x-android
cd element-x-android && ./gradlew assembleGplayDebug
```
正式包需要自己的签名密钥(脚本从 `~/.gradle/gradle.properties` 读取 `KEYSTORE` 等参数)。

## 许可 / Licence

本仓库的代码与 Element X 一样,以 **GNU AGPL-3.0** 发布,见 [LICENSE](LICENSE)。

「Strokes」名称和图标是本公司的标识,源代码许可不包括使用它们的权利;自行构建发布时请换成你自己的名称和图标。

The code here is licensed under the **GNU AGPL-3.0**, the same as Element X (see [LICENSE](LICENSE)). The "Strokes" name and logo are our company's marks and are not licensed for use by others; replace them if you build and distribute your own version.

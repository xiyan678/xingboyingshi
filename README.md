# 星播影院 · 双端客户端 0.2.0

基于 Flutter 与苹果 CMS V10，保留深色频道、大幅海报、横向片单和星播影院蓝金品牌。

## 本版交付

- Android 三架构调试 APK：ARMv7、ARM64、x86_64，适合手机与雷电测试。不是正式上架包。
- Android / iOS 共用源码及原生工程。iOS 工程需在 Mac 上构建、签名和真机验证，当前未交付 IPA。
- 网站配套扩展在 server/，详细步骤见 server/安装说明.md。尚未部署到 xbxx.pro，真实注册和数据同步尚未联调。

## 已实现的功能

首页、分类、搜索、分页、详情、线路和选集；个人中心、账号登录/注册表单、安全保存登录令牌；每个账号独立的本机收藏与观看记录；账号观看进度上传和读取；全站年份、地区、语言和排序筛选；弹幕读取、登录后发送、开关、字号、透明度与速度；倍速、拖动进度、续播、全屏、应用内可拖动小窗、系统画中画入口。

网站扩展安装成功后，APP 注册调用网站原有 User 模型，创建的就是网站账号。网站已有账号也可登录 APP。验证码、注册关闭、账号审核等由网站原有规则控制；强制手机/邮箱验证时本版提示去网站注册。

公共影片 API 保持为 https://xbxx.pro/api.php/provide/vod/ 。新增账号等功能使用 https://xbxx.pro/api.php/xingbo/ 。扩展未就绪时会显示明确提示；普通列表和播放仍走原接口。电影资料在刷新/重新加载时从网站获取，更新影片不需要重新打包 APP。

## 使用与限制

- “我的”登录后自动同步观看记录，也可手动同步。游客记录不自动合并到账号；收藏只保存在本机。
- 保存登录的是系统安全存储中的令牌，APP 不保存明文密码。服务端默认有效期 30 天；改密码或禁用账号会使后续认证失败。
- 跨设备秒级续播使用扩展表；未改网站网页播放器，因此网页播放进度尚未与 APP 互通。
- 弹幕默认审核后显示，当前在数据库管理器中审核，具体方法见安装说明。桌面画中画使用原生视频层，不显示弹幕；弹幕在普通/全屏播放器显示。
- 系统画中画须设备支持并允许对应权限；应用小窗可在 APP 内拖动。iOS 两种小窗均待真机验证，安卓目前只做启动验证，实际视频、小窗进出和后台恢复需进一步真机测试。
- 支持系统解码器可播放的 HTTPS 媒体地址。不提供网页解析器、DRM 授权、付费会员、支付或下载。
- 服务器尚未部署，不能将本次本地测试视为网站注册、验证码、数据库读写、审核和跨设备端到端测试通过。

## 构建

Flutter 3.47.4 / Dart 3.13.3，Java 17，Android SDK 36 / Gradle 9.3.1；依赖以 pubspec.lock 为准。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm,android-arm64,android-x64
```

Windows 可运行 scripts/build-debug.ps1。scripts/verify-apk.ps1 校验三种架构的真实 Flutter ELF 引擎，防止再次出现雷电加载 ARM64 库进入 x86_64 进程的闪退问题。正式分发前配置自己的 release 签名，工程未使用 debug 签名伪装发布版。

API_ENDPOINT、EXTENSION_ENDPOINT 可用 dart-define 修改，默认是上述正式网站地址。POSTER_PROXY 仅供浏览器预览使用，安装包不传入 localhost 地址。

iOS 需在 Mac 安装 Flutter 与 Xcode，然后：

```sh
flutter pub get
flutter build ios --no-codesign
# 在 Xcode 配置开发团队、Bundle ID 与签名后
flutter build ipa
```

现用包名 Android pro.xbxx.xingbo_app，iOS pro.xbxx.xingboApp。系统小窗已设置 Android FragmentActivity、supportsPictureInPicture 和 iOS background audio。

## 验证

- 14 项 Flutter 测试：接口解析和错误、查询参数、本机持久化、3 种宽度布局、令牌恢复/失效、验证码会话 cookie、账号记录隔离、异步旧响应隔离、弹幕跟随播放时间。
- Flutter 静态检查、Android debug 构建与三架构引擎校验。
- PHP 语法检查与 13 项隔离契约检查。测试替身不连接生产数据库。
- 0.1.0 曾在雷电验证修复后的启动；0.2.0 本次设备验证情况见同目录交付说明。

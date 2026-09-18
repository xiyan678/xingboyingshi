# 星播 iOS 自动去插播与画中画优化版

版本 0.2.7，云端构建号 10，Bundle ID 沿用 `app.eggplant1907.jet4469`。

这是 Codemagic 云端编译源码包，不是已签名 IPA。播放器右上角新增选集图标，普通播放和全屏都能切换集数及线路，高亮当前集数；其他页面保持原样。

1. 解压源码 ZIP，将内容更新到现有 GitHub 仓库根目录。`pubspec.yaml`、`codemagic.yaml`、`ios`、`lib`、`third_party` 应在同一级。务必一起上传 `third_party/video_player_avfoundation`，保留 LICENSE。
2. 在现有 Codemagic 应用选择仓库里的 `codemagic.yaml`。
3. 可先运行 `xingbo-ios-verify`：不需要证书，运行测试并用 Xcode 编译。生成的 `unsigned-Runner.zip` 不能直接安装。
4. 安装版选择 `xingbo-ios-adhoc`。沿用已配置且未过期的 Apple Distribution 证书与 Ad Hoc 描述文件；没有配置时在 Codemagic 签名设置上传 `.p12` 与匹配的 `.mobileprovision`，填写证书密码。描述文件须包含手机 UDID。不要把证书或密码上传到 GitHub。
5. 签名的 Bundle ID 必须匹配；不同则同时修改 `codemagic.yaml` 和 `ios/Runner.xcodeproj/project.pbxproj` 中的应用 Bundle ID。
6. 成功后从 Artifacts 下载 IPA，安装到描述文件包含的设备。

## 本次修改

播放器普通与全屏播放结束后自动进入当前线路下一集并从头继续播放；最后一集结束后停止。暂停、缓冲和错误不会触发跳集。iOS 画中画中结束一集会关闭当前画中画并加载下一集，不会自动重开系统画中画或强制唤起应用。安卓原生画中画使用独立播放器，本次不加入其自动连播。

每个视频单独分析插播结构，广告位置和时长不写死。苹果端通过仅绑定 `127.0.0.1`、带随机路径的本地服务交付过滤后的 m3u8；视频片段从原源加载，没有第三方解析接口。无法可靠识别、加密、多音轨等未支持结构保留原播放。

原画中画会创建第二个 AVPlayer，重新加载、跳转当前进度；本次改为直接复用正在播放的 AVPlayer 和已有缓冲。进入和返回不重新加载、不跳转、不切换音频流，保留倍速。关闭画中画则暂停。

本地修改的 AVFoundation 插件源码放在 `third_party`，保留上游 BSD 许可证，修改说明为 `XINGBO_CHANGES.md`。不用私有 Apple API，不对共享依赖缓存打补丁。安卓继续使用原先的播放与画中画实现。

## 验证边界

本机已通过 35 项自动化测试及 Flutter 静态检查，包含选集交互、去插播时间换算、苹果本地播放列表服务、画中画通道参数与错误处理。

Windows 可运行 Dart 测试、静态分析及本地播放列表服务测试，无法运行 Xcode。此交付未执行云端构建，也没有完成 iPhone 真机播放、后台与画中画流畅性验证；不能保证消除网络本身造成的卡顿。云端编译配置固定 Flutter 3.47.4，使用现有 iOS 项目和签名方案。

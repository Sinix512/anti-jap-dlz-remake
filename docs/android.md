# Android 触控测试包

- 应用 ID：`com.mwgames.dlz`；显示名称：抗日：地雷战。
- 当前交付为 **debug 签名 APK**，不是 Play 商店/AAB 或正式 release 签名。
- 横屏、原 640×480 等比视口，ARM64，最低 Android 7.0（API 24），target API 36。
- 离线游戏，不要求网络、相机、麦克风或外部存储权限；存档保存在应用沙盒，不读取桌面存档。
- 构建脚本不自动安装到连接手机，不启动游戏、不访问玩家存档。

## 构建

依赖：Godot **4.7.2 stable** 编辑器与同版本官方 Android 导出模板、JDK 17 或更新版本、Android SDK（platform-tools、platform android-36、build-tools 36）。本地已使用 JDK 21 验证。

官方安装说明：[Godot Android 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)；模板：[Godot 4.7.2 官方发布](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)。可在编辑器的“管理导出模板”安装模板；或以 `--template` 指定同版本 `android_debug.apk`。

先按仓库说明准备 `godot/assets/` 和 `godot/data/`（生成物因体积/版权不入库）。打包工具不会从玩家存档提取数据，也不会自动重新生成游戏数值。

```sh
python3 tools/build_android.py
# 可显式指定工具链：
python3 tools/build_android.py --godot /path/to/Godot \
  --sdk /path/to/Android/sdk --java-home /path/to/jdk \
  --template /path/to/4.7.2.stable/android_debug.apk
```

上述绝对路径是通用占位符，实际路径仅在本地传入。Godot 按 `--godot`、`GODOT_BIN`、`GODOT`、PATH 的顺序发现；JDK 按 `--java-home`、`JAVA_HOME`、系统 JDK 查询/PATH 发现，不依赖某台开发机的安装位置。触控验证工具使用相同的 Godot 发现规则。

默认输出：

- `out/android/dlz-android-debug.apk`：可安装 ARM64 APK。
- `out/android/build-report.json`：包名、SDK、ABI、权限、资源完整性、签名验证、SHA-256 与打包时源码/数据指纹。
- `out/android/aapt-*.txt`、`AndroidManifest.txt`、`apksigner.txt`：Android 官方工具原始核查结果。
- `out/android/export-stdout.log`、`godot-export.log`：独立导出日志。

报告中的 APK 路径使用仓库相对路径；仓库外产物标记为 `<external>/文件名`。原始工具日志、编辑器配置及报告的其他诊断字段仍可能含本机信息，均只供本地核查，不应原样上传或强制加入 Git。发布前按根目录 `AGENTS.md` 检查。

脚本复制一个自包含编辑器至 ignored 的 `out/android/toolchain/editor/`，仅给该副本配置 SDK/JDK，不修改用户现有 Godot 编辑器设置。macOS 上仅对这个副本做 ad-hoc 签名。debug 私钥和随机凭据只存放在 ignored 的 `out/android/toolchain/`，不会写进导出预设、源码或日志。保留该目录可用同一测试签名升级安装；删除后生成的新签名不能覆盖安装旧测试包。

导出预设在 `godot/export_presets.cfg`：明确包括动态读取的 JSON/二进制数据与导入的图像、音频、Theora 过场；排除开发测试、未播放的 WebM 交付副本和原始 ANM 源文件。校验 APK 内的 47 关定义、触控入口、中文字体、全部数据表引用的运行时资源及 ARM64 引擎；发现脚本解析错误、资源缺失或导出期间源码变化就失败。

## 核查现有 APK

```sh
python3 tools/build_android.py --verify-only out/android/dlz-android-debug.apk
```

只核查时将结果写到 `out/android/verification-report.json`，不会覆盖原构建的源码指纹报告。

构建使用标准模板、不使用 Gradle 插件，不需要远程调试或网络权限。debug 包是便于当前触控验收的安装产物，不表示已完成所有 Android 真机、刘海屏、平板及长时间后台恢复验证。

## 平台交互边界

Android/mobile 自动启用触控；桌面默认关闭，即使系统报告触摸硬件或收到触摸事件也不会切换。桌面仅追加 `-- --touch-ui` 才显式启用测试界面，普通鼠标键盘不改变。

移动单点执行，仍可按原流程撤回暂移；攻击、策略等最终行动提交保留预览确认。瞄准期间有明确可点击的取消按钮；桌面也有普通 HUD 取消按钮，但不会因此启用触控界面。操作细节见 [触控操作](TOUCH_CONTROLS.md)。

Android 返回事件由独立输入桥归并：每次原生 BACK DOWN（含重复键）与引擎延迟窗口通知配对，即使通知跨帧到达也不多取消一层，不使用毫秒防抖吞掉连续返回。只有窗口通知的返回路径仍可取消。

2026-10-30 在指定的 MuMu 测试设备（Android 12L/API 32）升级安装本包，实际验证排行榜返回、退出确认取消、新游戏首关单点移动、可见取消攻击、休息确认取消及暂移撤回；应用进程保持存活，无脚本或致命错误。另有 15 套同源触控/桌面定向回归通过。该烟测不是首关通关或全战役证明，也未把 adb 按键/滑动注入冒充真机系统返回手势验证。设备序列号仅留本地，不写入公开文档。

## 安装和升级

用户可自行把 APK 复制到 Android 设备，允许该文件来源安装后打开。也可明确指定测试设备安装：

```sh
adb -s YOUR_DEVICE_SERIAL install -r out/android/dlz-android-debug.apk
```

脚本自身不会执行这个命令。卸载会清除应用沙盒存档；不要为解决签名冲突随意卸载正在游玩的版本。正式分发需要单独的 release 签名、版本号管理及原素材分发权确认，不复用本地 debug 私钥。

# VDDX

macOS 上的虚拟屏管理工具. 用 `CGVirtualDisplay` 创建虚拟显示器, 在菜单栏和主窗口里管理它们, 并支持把虚拟屏画面镜像到普通窗口.

## 功能

- 创建与销毁任意数量的虚拟屏, 可配置分辨率, 刷新率, HiDPI 与名称.
- 菜单栏常驻: 左键显示主窗口, 右键弹出管理菜单.
- 可标记虚拟屏在应用启动时自动重建, 退出时全部销毁.
- 镜像窗口: 用 ScreenCaptureKit 捕获虚拟屏画面, 在普通窗口中实时显示.
- 窗口尺寸记忆, 单实例运行, Ctrl+C 或信号退出都会走统一清理路径.

## 系统要求

- macOS 15 (Sequoia) 及以上.
- Apple Silicon 或 Intel.

## 安装

从 Releases 下载 `vddx-<版本>-macos-<架构>.dmg`, 打开后把 VDDX 拖到 Applications.

首次打开如果被系统拦下, 到 系统设置 > 隐私与安全性 里允许运行.

镜像功能需要屏幕录制权限: 在 系统设置 > 隐私与安全性 > 屏幕与系统音频录制 里手动添加 VDDX 并打开开关. macOS 15 起该权限不再自动弹窗.

## 已知限制

- 虚拟屏依赖 CoreGraphics 私有类 `CGVirtualDisplay`, 不是公开 API, 系统升级后可能失效.
- 在 macOS 15 上, 部分机器的虚拟屏不合成第三方窗口: 窗口被系统报告为 on-screen, 但画面不显示. 这与本应用无关.
- 屏幕录制权限与代码签名绑定. 开发时每次重新签名后都需要在系统设置里重新授权.

## 开发

需要 Xcode 26 或对应的 Swift 6.2 工具链, 以及 just 与 uv.

```shell
just build      # 编译
just app        # 组装调试版 target/VDDX.app
just debug      # 以隔离数据目录运行调试实例
just run        # 打开调试版应用包
just dist       # 生成当前平台的 dmg
just fake-dist  # 生成 v0.0.0 的 fake 安装版
```

调试实例的数据与日志在 `target/vddx-debug/` 下, 不影响日常数据.

日常使用时:

- 数据: `~/Library/Application Support/com.azazo1.vddx/`
- 日志: `~/Library/Logs/com.azazo1.vddx/`

可用环境变量覆盖: `VDDX_DATA_DIR`, `VDDX_LOG_DIR`, `VDDX_LOG_FILE`, `VDDX_LOG_LEVEL`, `VDDX_LOG_STDERR`.

## 目录结构

```
Sources/
  CVirtualDisplayBridge/   私有 API 的 Objective-C 桥接层
  VDDX/
    App/                   应用生命周期与状态聚合
    Core/                  显示管理, 捕获, 配置, 日志, 更新
    UI/                    SwiftUI 视图与 AppKit 窗口
scripts/                   打包与版本脚本
assets/                    应用图标
docs/changelog/            每个版本的发布说明
```

## 隐私

本应用不收集任何数据. 唯一的网络请求是检查 GitHub Releases 是否有新版本.

## 许可证

MIT

# TeakTextView

[English](README.md) | [中文](README.zh-CN.md)

**Teak 浏览器内置的代码编辑器与预览器。**

The native code editor and previewer built into the Teak browser.

TeakTextView 将 Teak 的原生文本编辑与源码预览能力独立为 Swift Package，基于 UIKit、TextKit 2 和 C++20 文档缓冲实现。支持可编辑及只读预览模式、原生文本选择与复制，并内置 19 种语言的基础语法高亮。预览展示文件源码，不执行代码。

## 功能

- 原生输入、中文输入法、选区手柄、复制/剪切/粘贴、撤销与重做。
- 逻辑行号、自动折行，以及针对压缩代码长行的有界排版和分块绘制。
- C++ 持久化 Rope 与不可变文档快照，编辑时共享未变化节点。
- 后台文件读取、解码和保存，支持 UTF-8、带 BOM 的 UTF-16 LE/BE，保留编码、BOM 和换行。
- 后台按视口高亮、过期结果检查，以及可导入的 JSON 语言规则。
- 独立 Demo：语言列表、正常/大文件切换、文件导入与导出、只读模式及性能指标。

## 环境

| 用途 | 要求 |
| --- | --- |
| 编辑器与 Demo | iOS 17+、Xcode 16+、Swift 6、C++20 |
| 文档与高亮核心 | macOS 14+ 或 iOS 17+ |

无第三方运行时依赖。编辑 UI 目前使用 UIKit；macOS 支持核心模块与测试。

## 安装

在 Xcode 的 **File → Add Package Dependencies** 中添加：

```
https://github.com/yangliu-1995/TeakTextView.git
```

当前可选择 `main` 分支。也可以在 `Package.swift` 中添加：

```swift
.package(url: "https://github.com/yangliu-1995/TeakTextView.git", branch: "main")
```

然后将 `TeakTextView` 产品加入 App target；直接使用语言规则和文档快照时，同时添加 `TeakTextCore` 产品。

## 使用

在 `MainActor` 中创建和操作编辑器，将它作为普通 `UIView` 加入界面：

```swift
import UIKit
import TeakTextView
import TeakTextCore

@MainActor
func makeEditor(fileURL: URL) async throws -> TeakTextView {
    let editor = TeakTextView()
    editor.showsLineNumbers = true

    let registry = TeakLanguageRegistry()
    let language = try await registry.bundledLanguage(id: "javascript")
    let highlighter = try await registry.makeHighlighter(language: language)
    editor.installPlugin(highlighter)

    try await editor.open(fileURL: fileURL)
    return editor
}
```

常用操作：

```swift
try await editor.load(text: "const answer = 42;\n")
editor.isEditable = false // 只读源码预览，仍可选择和复制
editor.isEditable = true

try await editor.save(to: destinationURL)
editor.undoManager?.undo()
editor.undoManager?.redo()

let snapshot = editor.snapshot
let excerpt = try snapshot.text(
    in: NSRange(location: 0, length: min(200, snapshot.utf16Count))
)
```

所有范围使用 UTF-16 坐标。大文档优先使用范围读取和 `save(to:)`，避免为显示少量内容而请求全文字符串。`snapshot` 共享不可变树，可安全交给后台任务。

语言规则可以从本地 JSON 动态加载：

```swift
let definition = try await registry.load(url: ruleURL)
let plugin = try await registry.makeHighlighter(language: definition)
editor.installPlugin(plugin)
editor.removePlugin(id: plugin.id)
```

`TeakLanguageRegistry.bundledLanguages()` 返回内置语言，`detect(fileName:firstLine:among:)` 支持文件名、最长后缀及已知解释器 shebang 检测。未识别的文件可按纯文本显示。

## 支持语言

JavaScript / TypeScript、Python、HTML / CSS / Markdown、Java / C#、C / C++、Go、Rust、Swift、Kotlin、SQL、Bash、JSON、YAML、TOML。

规则位于 [`Sources/TeakTextCore/Languages`](Sources/TeakTextCore/Languages)，提供关键词、注释、字符串、数字和部分上下文着色。它们是有限词法规则：尚不支持完整语义分析、HTML 内嵌语言、Markdown 围栏内语言、JS 模板插值/正则字面量、Bash heredoc 或 SQL dollar quoting。自定义规则格式可参考 [`Examples/python.json`](Examples/python.json)。

## Demo

打开 [`Demo/TeakTextViewDemo.xcodeproj`](Demo/TeakTextViewDemo.xcodeproj)，选择 **TeakTextViewDemo**，在 iPhone 或 arm64 模拟器运行。真机运行需在 Signing 中选择自己的 Team。

启动页列出 19 种语言，进入后默认打开正常文件，右上角 **Demo files** 可切换大文件。共 38 份真实开源项目文件，保留原始内容、文件名及后缀；最大样本为 TypeScript 的 `checker.ts`（约 3.1 MB）。编辑使用临时副本，不修改打包资源。菜单还支持手动选择语言、导入文件与规则、保存、导出及查看开源声明。

全部来源、固定提交、大小、SHA-256 和许可证见 [`Demo/Samples/SOURCES.md`](Demo/Samples/SOURCES.md) 与 [`catalog.json`](Demo/Samples/catalog.json)。这些文件仅作为展示资源，不编译或执行。

命令行编译 arm64 模拟器 Demo：

```sh
xcodebuild -project Demo/TeakTextViewDemo.xcodeproj \
  -scheme TeakTextViewDemo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

在 macOS 上验证文档缓冲、编码往返及高亮核心：

```sh
swift test
```

## 架构与边界

| 模块 | 职责 |
| --- | --- |
| `TeakTextBuffer` | C++20 Rope、快照与换行索引 |
| `TeakTextCore` | 文件 I/O、语言规则、后台高亮插件及缓存 |
| `TeakTextStorage` | Foundation / TextKit 2 存储与有界布局元素 |
| `TeakTextView` | UIKit 输入、行号、视口绘制及选区几何 |

超长行按组合字符边界拆分内部布局元素，可能改变少量自动折行位置；原文、逻辑行号、复制和保存内容保持一致。打开文件仍会解码全文并常驻 UTF-16 文档，不是按需加载的磁盘编辑器。数百 MB 文件及百万行文件尚未建立真机性能指标。

大选区使用视口内几何减少全文排版。`TeakTextTouchSupport` 中集中封装了带签名校验的私有 UIKit 可选能力探测；系统版本变化时需要验证触摸选择行为。单元测试覆盖核心数据正确性，实际滚动、输入法、选区与编辑菜单性能需要在目标真机验证。

更多实现细节见 [`docs/Architecture.md`](docs/Architecture.md)。

## 许可证

TeakTextView 使用 [MIT 许可证](LICENSE)。Demo 和测试中的第三方样本归各原作者所有，适用其随附许可证，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

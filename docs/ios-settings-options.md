# FSNotes iOS 设置项总览

本文档基于当前代码实现梳理 iOS `Settings` 页面可达的所有选项与行为。

## 1. 入口与总结构

主入口：`FSNotes iOS/ViewController.swift` 的 `openSettings()`，打开 `SettingsViewController`。

主设置页面分 3 组：
- `General`
- `Library`
- `FSNotes`

定义位置：`FSNotes iOS/Preferences/SettingsViewController.swift`。

---

## 2. General 组

### 2.1 Files
页面：`DefaultExtensionViewController`
文件：`FSNotes iOS/Preferences/DefaultExtensionControllerView.swift`

选项：
- `Container`
- `Textbundle`（开关）
  - 写入：`UserDefaultsManagement.fileContainer`（`.textBundleV2` / `.none`）

- `Extension`
- `markdown` / `md` / `txt`（单选）
  - 写入：`UserDefaultsManagement.noteExtension`
  - 写入：`UserDefaultsManagement.fileFormat`

- `Files Naming`
- `Autoname By Title`
- `Auto Rename By Title`
- `Format: Untitled Note`
- `Format: yyyyMMddHHmmss`
- `Format: yyyy-MM-dd hh.mm.ss a`
  - 单选写入：`UserDefaultsManagement.naming`

### 2.2 Editor
页面：`SettingsEditorViewController`
文件：`FSNotes iOS/Preferences/SettingsEditorViewController.swift`

选项：
- `Settings`
- `Autocorrection`（开关）
  - 写入：`UserDefaultsManagement.editorAutocorrection`
- `Check Spelling`（开关）
  - 写入：`UserDefaultsManagement.editorSpellChecking`

- `View`
- `Code Block Live Highlighting`（开关）
  - 写入：`UserDefaultsManagement.codeBlockHighlight`
- `MathJax`（开关）
  - 写入：`UserDefaultsManagement.mathJaxPreview`

- `Line Spacing`
- 滑杆（0~25）
  - 写入：`UserDefaultsManagement.editorLineSpacing`

- `Font`
- `Family`（跳转 `FontViewController`）
- `Dynamic Type`（开关）
  - 写入：`UserDefaultsManagement.dynamicTypeFont`
- `Font Size`（Stepper，10~40）
  - 写入：`UserDefaultsManagement.fontSize`

- `Code`
- `Font`（跳转 `CodeFontViewController`）
- `Theme`（跳转 `CodeThemeViewController`）

关联子页：
- `FontViewController`：System/Avenir Next/Georgia/Helvetica Neue/Menlo/Courier/Palatino
  - 写入：`UserDefaultsManagement.fontName` 或 `UserDefaultsManagement.noteFont`
- `CodeFontViewController`：Source Code Pro/Menlo/Courier
  - 写入：`UserDefaultsManagement.codeFontName` 或 `UserDefaultsManagement.codeFont`
- `CodeThemeViewController`：github/solarized/atom-one
  - 写入：`UserDefaultsManagement.codeTheme`

### 2.3 Security
页面：`SecurityViewController`
文件：`FSNotes iOS/Preferences/SecurityViewController.swift`

选项：
- `Password`
- `Verify Password`
- `Save`

行为：
- 主密码保存到 Keychain：账号 `Master Password`
- 两次输入不一致会弹错误提示

### 2.4 Git
页面：`GitViewController`（通过主页面统一入口）
相关文件：
- `FSNotes iOS/Preferences/SettingsViewController.swift`
- `FSNotes iOS/ViewController+More.swift`
- `FSNotes iOS/Preferences/GitViewController.swift`

当前实现要点：
- `Settings -> Git` 与 Vault 菜单里的 Git 使用同一流程
- 会优先使用当前选中的 vault；否则进入 vault 选择流程

Git 页选项：
- `Vault`
- `Selected vault`（只读）

- `Automation`
- `Pull (every 30 sec)`（开关）
  - 写入：`project.settings.gitAutoPull`

- `Authorization`
- `Provider`（GitHub）
- `Authorize with GitHub` / `Re-authorize`
- `Disconnect`

- `Origin`
- 仓库地址输入框（如 `https://github.com/username/repo.git`）
  - 写入：`project.settings.gitOrigin`
  - 同步写入：`UserDefaultsManagement.gitOrigin`
- 主按钮（动态）：`Init/commit` / `Clone/push` / `Add/commit` / `Pull/push`
- `Remove`（删除本地仓库）

- `Status`
- 显示诊断/同步日志（GitDebug）

### 2.5 Icon
页面：`AppIconViewController`
文件：`FSNotes iOS/Preferences/AppIconViewController.swift`

选项：
- `Modern`
- `Classic`
- `Neo`

行为：
- 调用 `UIApplication.shared.setAlternateIconName`
- 写入：`UserDefaultsManagement.appIcon`

### 2.6 Advanced
页面：`ProViewController`
文件：`FSNotes iOS/Preferences/ProViewController.swift`

选项：
- `+`
- `Default Keyboard`（跳转 `LanguageViewController`）
- `Use Inline Tags`（开关）
  - 写入：`UserDefaultsManagement.inlineTags`
- `Use TextBundle info.json to store c/mtime`（开关）
  - 写入：`UserDefaultsManagement.useTextBundleMetaToStoreDates`

- `View`
- `Sort By`（跳转 `SortByViewController`）
  - 写入：`UserDefaultsManagement.sort`
- `Library`（跳转 `SidebarViewController`）

关联子页：
- `LanguageViewController`：选择默认键盘语言
  - 写入：`UserDefaultsManagement.defaultKeyboard`
- `SidebarViewController`：侧栏显示控制
  - `Inbox` -> `UserDefaultsManagement.sidebarVisibilityInbox`
  - `Todo` -> `UserDefaultsManagement.sidebarVisibilityTodo`
  - `Untagged` -> `UserDefaultsManagement.sidebarVisibilityUntagged`
  - `Trash` -> `UserDefaultsManagement.sidebarVisibilityTrash`

---

## 3. Library 组

### 3.1 iCloud Drive
主页面开关
文件：`SettingsViewController`

行为：
- 写入：`UserDefaultsManagement.iCloudDrive`
- 调用：`UIApplication.getVC().reloadDatabase()`
- 关闭时会停止 iCloud 同步引擎

### 3.2 Choose Vault Folder
行为：
- 打开 `ExternalViewController`（系统目录选择器）
- 选中目录后保存 security-scoped bookmark
- 在单 Vault 模式下会替换旧 vault（只保留一个书签项目）

### 3.3 Folders
页面：`ProjectsViewController`
文件：`FSNotes iOS/Preferences/ProjectsViewController.swift`

状态：
- 历史遗留多项目管理页。
- 当前单 Vault 模式下，主设置页已移除该入口，不再作为正式流程使用。

### 3.4 Import Notes
行为：
- 通过 `UIDocumentPickerViewController` 导入文件到 `storageUrl`

---

## 4. Folders -> 单项目设置

页面：`ProjectSettingsViewController`
文件：`FSNotes iOS/Preferences/ProjectSettingsViewController.swift`

分组与选项：
- `Sort By`
  - None / Modification Date / Creation Date / Title
  - 写入：`project.settings.sortBy`

- `Sort Direction`
  - Ascending / Descending
  - 写入：`project.settings.sortDirection`

- `Visibility`
  - Show Notes in "Notes" and "Todo"（开关）
    - 写入：`project.settings.showInCommon`
  - Show Folder in Library（开关）
    - 写入：`project.settings.showInSidebar`

- `Notes List`
  - Use First Line as Title（开关）
    - 写入：`project.settings.firstLineAsTitle`

所有项目页改动最终会 `project.saveSettings()`。

---

## 5. FSNotes 组

来自 `SettingsViewController`：
- `Support` -> 打开 Issues: `https://github.com/glushchenko/fsnotes/issues`
- `Website` -> `https://fsnot.es`
- `X` -> `https://twitter.com/fsnotesapp`
- `Thanks` -> `ThanksViewController`（贡献者链接）

---

## 6. 备注

- 当前文档只覆盖 **iOS Settings 路径可达**选项。
- Git 流程细节（vault onboarding / OAuth PKCE / repo diagnostics）另见：
  - `docs/ios-vault-git-flow.md`

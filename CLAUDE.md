# CLAUDE.md — 题库抽题器 (Randomselector)

## 项目概述

跨平台刷题应用（Windows + Android），Flutter 3.x + Dart。功能：导入 Word/PDF 题库 → 自动解析 → 随机抽题 → 错题本 → AI 精选模式。GPL-3.0 开源，纯本地，无账号系统。

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.44+ |
| 路由 | go_router (ShellRoute + NavigationBar) |
| 状态管理 | Provider (ChangeNotifier) |
| 数据库 | sqflite + sqflite_common_ffi (Windows 桌面需 FFI 初始化) |
| .docx 解析 | archive + xml (Dart 包，手写解析器) |
| PDF 解析 | 手写降级方案（按 BT/ET 块提取） |
| LLM | http 包，兼容 OpenAI/Claude 格式 |

## 关键设计决策（grilling 确认）

- **Flutter 而非 Electron**：一套代码 Windows+Android，框架级动画，学习门槛低
- **纯本地 SQLite**：无后端，无需网络
- **客观题自动判分、主观题需配 LLM 后开放**
- **API 配置**：自定义 Base URL + API Key + Model Name，兼容所有 OpenAI 格式接口
- **两种刷题模式**：逐题（PageView 即时判分）+ 试卷（ListView 统一交卷）
- **AI 精选**：规则引擎（导入时自动评分）+ 可选 LLM 深度分析（手动触发）
- **错题本**：独立表，做对后自动移除

## 踩坑记录 ⚠️

### 1. initState 中不能直接调 Provider 的 notifyListeners
`BankListScreen.initState` 中调 `context.read<BankProvider>().loadBanks()`，
`loadBanks()` 内部 `notifyListeners()` 在 build 阶段触发 → 框架崩溃 + 黑屏。
**修复**：所有 `initState` 中的 provider 调用必须包 `WidgetsBinding.instance.addPostFrameCallback`。

### 2. sqflite 桌面端需 FFI 初始化
Windows 和 Linux 桌面版 sqflite 不会自动初始化 factory。
**修复**：`main.dart` 中调用 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`

### 3. Slider 值不能超过 max
异步加载数据时，Slider 的初始值必须在 min~max 范围内。
**修复**：`_totalQuestions` 初始值设为 100，`_selectedCount` 初始值设为 1。

### 4. .docx 同行的 ABCD 选项会被错误合并
`_extractOptions` 按行匹配时，整行 `A．xxx    B．yyy    C．zzz    D．www` 被当成一个选项。
**修复**：改用 `[A-E]\s*[．、.]` 正则匹配所有选项标记位置，按标记切分。

### 5. MaterialApp vs MaterialApp.router
Flutter 3.44+ 使用 `go_router` 必须用 `MaterialApp.router()` 构造函数，`routerConfig` 参数只在 `.router()` 下有效。

### 6. go_router ShellRoute 中 showDialog 必须用 useRootNavigator
ShellRoute 创建了自己的 Navigator，`showDialog` 默认把 dialog 推到 go_router 的 Navigator 上。
此时 `Navigator.pop(context)` 会被 go_router 的 `onPopPage` 拦截 → 路由栈被错误弹出 → 框架崩溃 + 黑屏或 "popped the last page" 断言失败。
**修复**：所有 `showDialog` 加 `useRootNavigator: true`，并用 dialog builder 的 context 做 `Navigator.pop(dialogContext, ...)`。
涉及文件：`settings_screen.dart`, `bank_list_screen.dart`, `quiz_screen.dart`。

### 7. QuizCard 切题时 _selectedSingle 残留
Flutter Element 复用时 `didUpdateWidget` 只处理了 `userAnswer` 变化（试卷模式），没处理题目切换。
切到下一题后 `_selectedSingle` 保留着上一题的值 → 第二题自动选中了上一题的选项。
**修复**：`didUpdateWidget` 中检测 `widget.question.id != oldWidget.question.id`，调用 `_resetForNewQuestion()` 清空或从 `initialAnswer` 恢复。
涉及文件：`lib/widgets/quiz_card.dart`。

### 8. 逐题模式改为两阶段交互（选择 → 确认 → 下一题）
原来选项点击立即 `submitAnswer` → 多选题选一个就判错。改为：
1. 选择阶段：自由点选，多选题可增删，「确认答案 ✓」按钮亮起
2. 确认后：显示对错高亮，按钮变「下一题 →」
涉及文件：`lib/widgets/quiz_card.dart`（`onAnswered` → `onSelectionChanged`），`lib/screens/quiz_screen.dart`（`_PerQuestionView` 重写为 StatefulWidget）。

### 9. 刷题页底部导航栏未隐藏
ShellRoute 的 `AppScaffold` 无差别给所有子路由套了 NavigationBar，刷题和结果页也显示了导航栏。
**修复**：`AppScaffold` 加 `_shouldShowNav()` 判断当前路由，`/quiz/`（不含 setup）和 `/result/` 全屏隐藏导航栏。
涉及文件：`lib/app.dart`。

### 10. useRootNavigator dialog 中导航前必须先 pop
dialog 在 root navigator 上，`context.go()` 只操作 go_router，dialog 不会自动关闭。
**修复**：dialog 内「退出」按钮改为先 `Navigator.pop(dialogContext)` 再 `context.go('/')`。
涉及文件：`lib/screens/quiz_screen.dart`（两处 `_showExitDialog`）。

### 11. 错题本刷错题黑屏 — 多个连续 dialog 叠加破坏路由栈
`_startWrongQuiz()` 中两个 dialog 都没有 `useRootNavigator`，每次 `Navigator.pop` 被 go_router 拦截，两次弹窗后路由栈损坏 → `context.go('/quiz/...')` 黑屏。
**修复**：`wrong_book_screen.dart` 全部 3 处 dialog + `bank_list_screen.dart` 的 ImportDialog 统一加 `useRootNavigator: true`。
**全项目现状**：10 处 `showDialog` 全部已加 `useRootNavigator`，新增 dialog 必须照此模板。

## 项目结构

```
lib/
├── main.dart              # 入口，sqfliteFfiInit，MultiProvider
├── app.dart               # MaterialApp.router + ShellRoute + NavigationBar
├── models/                # QuestionBank, Question, QuizSession, QuizAnswer
├── database/
│   ├── database_helper.dart  # sqflite 初始化 + 建表
│   └── dao.dart              # 所有 CRUD + 统计 + 按题库错题查询
├── parser/
│   ├── docx_parser.dart      # archive + xml → 纯文本
│   ├── pdf_parser.dart       # 降级方案提取文本
│   └── question_extractor.dart  # 纯文本 → List<ParsedQuestion>
├── ai/
│   ├── rule_engine.dart      # 关键词评分（难度/重要性/理论性）
│   └── llm_client.dart       # HTTP 调用 LLM API
├── providers/             # BankProvider, QuizProvider, WrongBookProvider, SettingsProvider
├── screens/               # 10 个页面：home, bank_list, test_list, test_create, quiz, result, wrong_book, wrong_book_bank_detail, wrong_book_test_list, settings
└── widgets/               # quiz_card, option_tile, progress_bar, import_dialog, empty_state
```

## 数据库表

question_banks → questions → quiz_sessions → quiz_answers → wrong_questions → settings

外键 CASCADE：删除题库 → 删除所有题目 → 删除相关错题记录。

## 验证清单

- [ ] 导入《原理课后练习题.docx》→ 判断/单选/多选解析数正确
- [ ] 基本随机模式逐题刷题
- [ ] 试卷模式统一交卷
- [ ] 错题本收录 + 刷错题 + 做对移除
- [ ] 配置 LLM API → AI 分析 → featured 模式
- [ ] 清空记录 / 清空题库
### 12. `_dependents.isEmpty` 断言 —— dialog 按钮 + TextField 失焦冲突

Dialog 内 TextField 有焦点时点击按钮（取消/保存/开始），按钮 handler 中同步 `Navigator.pop(dialogContext)` 或读 `controller.text`，与 TextField 失焦触发的 widget 生命周期冲突 → State.dispose() 时 InheritedWidget 依赖未清理。

**两种场景及修复**：

| 场景 | 修复 |
|---|---|
| TextField `onSubmitted`（回车提交）| `addPostFrameCallback` 包裹 `Navigator.pop` |
| Dialog 按钮 `onPressed`（读值 + pop + 导航）| **复杂 dialog 改用独立 StatefulWidget**，避免 StatefulBuilder；简单 dialog 所有变量读取和 pop 放入 `addPostFrameCallback` |

**关键原则**：TextEditingController 必须由 StatefulWidget 的 `State.dispose()` 管理，不要用 `showDialog(...).then((_) => controller.dispose())`——它在退出动画期间触发，此时 TextField 仍在树中。

涉及文件：`test_list_screen.dart`（重命名保存按钮）、`wrong_book_test_list_screen.dart`（重命名保存 + 创建 dialog 重构为 `_CreateWrongBookDialog`）。

### 13. `returnTo` query parameter —— quiz 退出回到发起页

QuizScreen 退出时需要知道从哪个页面进入的。go_router 路由定义为 `/quiz/:sessionId`，通过 query parameter 传递 `returnTo`：
- 题库测试：`/quiz/:id?returnTo=/banks/:bankId/tests`
- 错题测试：`/quiz/:id?returnTo=/wrongbook/tests`
- QuizScreen 退出：`context.go(widget.returnTo ?? '/')`

遗漏 returnTo 会导致退出回首页而非列表页。涉及文件：`app.dart`（路由定义）、`test_list_screen.dart`、`test_create_screen.dart`、`wrong_book_test_list_screen.dart`（各入口处拼接 returnTo）。

### 14. `tab` query parameter —— 结果页返回保留已完成 tab

ResultScreen 返回 TestListScreen 时，已完成测试应回到"已完成"tab。通过 URL `?tab=1` 传递，TestListScreen/WrongBookTestListScreen 在 initState 中从 `GoRouterState.of(context).uri.queryParameters` 恢复 tab 状态。

### 15. 错题详情页 —— `_QuestionDetailPage`

错题本列表每项可点 → 用 `Navigator.of(context, rootNavigator: true).push` 推 `_QuestionDetailPage`（避开 go_router 干扰）。详情页异步加载用户最后一次错误答案（DAO 新增 `getLastWrongAnswer`），传给 QuizCard（`showAnswer: true`, `initialAnswer` = 用户错答）。正确选项绿底、用户错选红底、底部 `_AnswerBanner` 显示正确答案与解析。

- [ ] `flutter build windows` + `flutter build apk`

# Handoff — 题库抽题器 (Randomselector)

## 项目状态

Flutter 3.44+ 跨平台刷题应用，纯本地 SQLite。当前处于功能完善 + Bug 修复阶段。Windows 平台可正常运行，Android 未测试。

## 本次会话完成的工作 (2026-07-21)

### Git 仓库 & 发布
- Git 初始化并提交（80 files, `e72b431`），远程 `https://github.com/beluga11716/suijitiku`
- `.gitignore` 加固：新增 `*.docx *.doc *.pdf *.txt`（防止用户题库文件泄露）+ `*.zip`（防止发布包入库）
- Windows release 编译：`flutter build windows --release` → `build/windows/x64/runner/Release/randomselector.exe`
- 打包脚本：PowerShell `Compress-Archive` 将 `flutter_windows.dll` + `sqlite3.dll` + `data/` + `randomselector.exe` 打包为 `randomselector-v1.0.0-windows.zip` (~14MB)
- GitHub Release 手动上传流程：`git push` → GitHub Releases 页 → 创建 tag → 上传 zip → Publish

### 数据重置
- 删除 `.dart_tool/sqflite_common_ffi/databases/randomselector.db`，应用重启后自动重建空库

### 错题本按题库分组
- **新流程**：`/wrongbook` → 题库列表（只显示有错题的题库，卡片样式类 `BankListScreen`）→ 点击进入 `/wrongbook/:bankId` → 该题库的错题详情
- 不同题库的错题完全隔离：统计、刷错题、清空均按题库作用域
- DAO 新增 `getBanksWithWrongQuestions()`、`getWrongQuestionsByBank()`、`getWrongQuestionCountByBank()`、`clearWrongQuestionsByBank()`、`getWrongQuestionCount()`
- `QuizProvider` 新增 `startWrongBookSessionByBank(bankId:)` — 按题库创建错题测试
- `WrongBookProvider` 新增 `banksWithWrong` 列表 + `loadBanksWithWrongQuestions()` / `loadWrongQuestionsByBank()` / `clearByBank()`
- 新文件 `wrong_book_bank_detail_screen.dart`：按题库错题详情页（统计 + 刷错题 + 清空 + 错题列表 + `QuestionDetailPage`）
- `wrong_book_test_list_screen.dart` 修复 `_showCreateDialog` 直接用 DAO 查错题总数（不再依赖 Provider 缓存）

### 返回导航全面修复
- 全部 9 个页面审计并修复返回按钮，确保 `context.go()` 指向正确的上一级路由
- **`returnTo` query parameter 模式**：quiz 退出时回到发起页面
  - 题库测试：`/quiz/:id?returnTo=/banks/:bankId/tests`
  - 错题测试（全部）：`/quiz/:id?returnTo=/wrongbook/tests`
  - 错题测试（按题库）：`/quiz/:id?returnTo=/wrongbook/:bankId`
- **`tab` query parameter 模式**：结果页返回保留已完成 tab 状态
  - `/banks/:bankId/tests?tab=1`、`/wrongbook/tests?tab=1`

### `_dependents.isEmpty` 断言崩溃修复

**根因**：dialog 内 TextField 失焦时，同步 `Navigator.pop` 与 widget 生命周期冲突，导致 State 被 dispose 时 InheritedWidget 依赖未清理。

**两种场景及修复**：

| 场景 | 修复 |
|---|---|
| TextField `onSubmitted`（回车）| `addPostFrameCallback` 包裹 `Navigator.pop` |
| Dialog 按钮 `onPressed`（读值+pop+导航）| **复杂 dialog 换独立 StatefulWidget**，controller 由 State.dispose() 管理，避免 `.then()` 在退出动画期间 dispose；简单 dialog 用 `addPostFrameCallback` |

**涉及文件**：
- `test_list_screen.dart` — 重命名 dialog 保存按钮
- `wrong_book_test_list_screen.dart` — 重命名 dialog 保存 + 创建 dialog 重构为 `_CreateWrongBookDialog`

### 错题本题目详情页
- DAO 新增 `getLastWrongAnswer(questionId)` — 查 quiz_answers 获取用户最后一次错误答案
- 错题列表每项可点 → `rootNavigator: true` 推 `_QuestionDetailPage`
- 详情页展示 QuizCard（`showAnswer: true`, `initialAnswer` = 用户错答）：正确选项绿底、用户错选红底、`_AnswerBanner` 显示正确答案与解析

### 批量选择全选
- `test_list_screen.dart` + `wrong_book_test_list_screen.dart` → `_toggleSelectAll()`

### 其他修复
- 删除 quiz 退出 dialog 的"丢弃并退出"按钮
- 创建测试页补充返回按钮 (`test_create_screen.dart`)
- 题库列表页断链路由修复：`/quiz/setup/:id` → `/banks/:id/tests`

---

## 架构速览

```
lib/
├── main.dart           # sqfliteFfiInit + MultiProvider
├── app.dart            # MaterialApp.router + ShellRoute + NavigationBar
├── models/             # QuestionBank, Question, QuizSession, QuizAnswer
├── database/
│   ├── database_helper.dart
│   └── dao.dart        # 全 CRUD + 统计 + getLastWrongAnswer + 按题库错题查询
├── parser/             # docx_parser, pdf_parser, question_extractor
├── ai/                 # rule_engine (评分), llm_client (HTTP)
├── providers/          # Bank/Quiz/WrongBook/Settings Provider
├── screens/            # 10 个页面
└── widgets/            # quiz_card, option_tile, import_dialog
```

## 页面 & 关键路由

| 路由 | 页面 | 返回 |
|---|---|---|
| `/` | HomeScreen | — |
| `/banks` | BankListScreen | — |
| `/banks/:bankId/tests` | TestListScreen | `/banks` |
| `/banks/:bankId/tests/create` | TestCreateScreen | `/banks/:bankId/tests` |
| `/wrongbook` | WrongBookScreen (题库列表) | — |
| `/wrongbook/:bankId` | WrongBookBankDetailScreen | `/wrongbook` |
| `/wrongbook/tests` | WrongBookTestListScreen | `/wrongbook` |
| `/quiz/:sessionId` | QuizScreen | `returnTo` 或 `/` |
| `/result/:sessionId` | ResultScreen | 按 source 决定 `?tab=1` |
| `/settings` | SettingsScreen | — |

## 核心约定（新增人员必读）

1. **所有 `showDialog` 必须 `useRootNavigator: true`** — go_router ShellRoute 会拦截非 root 的 pop → 路由栈崩溃
2. **initState 调 Provider** → 包 `addPostFrameCallback`，禁止 build 阶段 notifyListeners
3. **复杂 dialog（含 TextField + Slider 等）** → 用独立 StatefulWidget，不用 StatefulBuilder；TextEditingController 在 State.dispose() 中释放，不要用 `.then()` 提前 dispose
4. **导航用 `context.go()`**，不用 `context.pop()`（ShellRoute 栈无历史可 pop）
5. **Navigator.push 非 go_router 页面** → 用 `rootNavigator: true` 避免 go_router onPopPage 干扰

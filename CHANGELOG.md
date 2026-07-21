# Changelog

## [Unreleased] — 2026-07-21

### 项目工程化
- Git 初始化 + 远程仓库 `https://github.com/beluga11716/suijitiku`
- `.gitignore` 加固：排除 `*.docx *.doc *.pdf *.txt *.zip`，防止用户题库文件和发布包泄露
- Windows 构建 & 打包流程：`flutter build windows --release` → zip → GitHub Release
- Android APK 构建已就绪（缺 Android SDK 环境，待用户安装 Android Studio）

### 数据重置
- 删除 SQLite 数据库文件，应用重启自动重建空库（还原至无题库状态）

### 错题本按题库分组
- 错题本第一页改为题库列表（只显示有错题的题库），点击进入该题库的错题详情
- 不同题库的错题完全隔离：统计、刷错题、清空均按题库作用域
- DAO 新增 `getBanksWithWrongQuestions()`、`getWrongQuestionsByBank()`、`getWrongQuestionCountByBank()`、`clearWrongQuestionsByBank()`、`getWrongQuestionCount()`
- `QuizProvider` 新增 `startWrongBookSessionByBank(bankId:)` 按题库创建错题测试
- `WrongBookProvider` 新增 `banksWithWrong`、`loadBanksWithWrongQuestions()`、`loadWrongQuestionsByBank()`、`clearByBank()`
- 新文件 `wrong_book_bank_detail_screen.dart`：按题库错题详情页（统计 + 刷错题 + 清空 + 错题列表）
- 路由新增 `/wrongbook/:bankId`，`_shouldShowNav` 对此路由隐藏导航栏
- `QuestionDetailPage` 从私有变为公开，提取到 `wrong_book_bank_detail_screen.dart`

### 导航系统修复
- 全部 9 页面返回按钮审计修复：统一用 `context.go()` 指向正确上级路由
- `returnTo` query parameter 模式：quiz 退出回到发起页面（题库/错题测试列表）
- `tab` query parameter 模式：结果页返回保留已完成 tab
- 题库列表页断链路由修复：`/quiz/setup/:id` → `/banks/:id/tests`
- 创建测试页补充返回按钮
- 删除 quiz 退出 dialog 的"丢弃并退出"选项

### Bug 修复
- `_dependents.isEmpty` 断言崩溃：dialog 按钮 handler 与 TextField 失焦冲突
  - `onSubmitted` 场景：addPostFrameCallback 包裹 Navigator.pop
  - 复杂 dialog（含 TextField + Slider + SegmentedButton）：改用独立 StatefulWidget 替代 StatefulBuilder；TextEditingController 由 State.dispose() 管理

### 新功能
- 错题本题目详情页：点击错题列表项 → 查看题目详情（正确/错误选项高亮、正确答案、解析）
- DAO 新增 `getLastWrongAnswer(questionId)` 查询最后错误答案
- 批量选择全选功能（TestListScreen + WrongBookTestListScreen）

---

## [0.1.0] — 2026-07-20

### 项目搭建
- Flutter 3.44+ 项目初始化，Windows + Android 双平台配置
- 技术栈确认：go_router + Provider + sqflite + archive/xml

### 数据层
- SQLite 数据库设计（6 张表）：question_banks, questions, quiz_sessions, quiz_answers, wrong_questions, settings
- DAO 全部 CRUD 方法 + 统计查询
- 数据模型：QuestionBank, Question, QuizSession, QuizAnswer

### 解析器
- .docx 解析器：archive 解压 ZIP → xml 解析 word/document.xml → 纯文本
- PDF 解析器：降级方案（BT/ET 块文本提取）
- 题目提取器：支持章节/题型/题号三层分割，内嵌答案识别 `（A）`、同行/换行选项切分

### AI 模块
- 规则引擎：关键词匹配三维评分（难度/重要性/理论性），综合 featured_score
- LLM 客户端：OpenAI/Claude 兼容 API 调用，批量分析 + 主观题评判

### UI（7 页面 + 5 组件）
- 首页：统计面板（题库数/题目数/刷题数/正确率）+ 快速选题库
- 题库管理：导入 + 列表 + 删除 + 解析预览对话框
- 刷题设置：题目数量、模式（随机/AI精选）、方式（逐题/试卷）
- 刷题页面：逐题模式（PageView）+ 试卷模式（ListView）
- 结果页面：正确率 + 逐题回顾 + 对错高亮
- 错题本：列表 + 统计 + 一键刷错题
- 设置页面：LLM API 配置 + 预设模板 + 清空数据

### Bug 修复
- initState 中 Provider notifyListeners 导致框架崩溃 → addPostFrameCallback
- sqflite Windows 桌面端缺少 FFI 初始化 → sqfliteFfiInit()
- Slider 异步加载前值越界 → 默认值调整
- .docx 同行 ABCD 选项被合并 → 按标记位置切分
- MaterialApp 构造函数不匹配 → 改用 MaterialApp.router()
- BankProvider.importBank 丢失 AI 评分 → 传递所有 score 字段

### 已知问题
- PDF 解析为降级方案，准确度有限
- 主观题（填空/简答）需配 LLM 后才能导入
- Android 端未测试

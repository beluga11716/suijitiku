# <img src="assets/icon/icon.png" width="40" alt="题库抽题器图标"> 题库抽题器 (Randomselector)

跨平台刷题应用，支持 Windows 和 Android。导入 Word/PDF 题库文档，自动解析题目，随机抽题刷题，错题本管理，LLM 精选模式。

这个项目基本全部都由claude CLI加DeepSeek-v4-pro来完成 这也是我vibecoding出的第一个项目 可能有漏洞或bug 有的话和我提issue吧

## 下载

最新安装包见 [Releases](https://github.com/beluga11716/suijitiku/releases)：

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows | `randomselector-v1.0.0-windows.zip` | 解压后运行 `randomselector.exe`，免安装 |
| Android | `app-release.apk` | 侧载安装 |

## 功能

- **题库导入**：支持 `.docx`、`.pdf`，自动解析章节、题型、题干、选项、答案、解析
- **全局题库切换**：首页下拉切换题库，刷题页和错题本自动跟随
- **随机抽题**：从当前题库随机抽取指定数量的题目
- **AI 精选模式**：用 LLM 按自定义 Prompt 筛选打分，按分数从高到低抽题（最多 120 道）
- **逐题模式**：左右滑动翻页，答对自动跳下一题，答错停留看解析（可点「下一题 →」），退出后进度可恢复
- **试卷模式**：题目全部显示，统一交卷判分
- **错题本**：自动收录错题，做对自动移除；支持单独刷错题、查看错题详情（含上次错答）
- **主观题**：精确匹配判分，配置 LLM 后可一键「AI 评分」
- **主题系统**：浅色 / 深色 / 跟随系统，20 种主题颜色；启动 Tab、错题提醒等个性化设置
- **纯本地**：所有数据存储在本地 SQLite，无账号、无需网络（AI 功能除外）

## 安装与运行

### 环境要求

- Flutter SDK 3.44+
- Windows 10+ 或 Android 10+

### 运行

```bash
# 安装依赖
flutter pub get

# Windows 运行
flutter run -d windows

# Android 运行
flutter run -d android
```

### 打包

```bash
# Windows
flutter build windows --release

# Android APK
flutter build apk --release
```

## AI 功能配置

设置 → AI 配置 中填写：

1. **Base URL**：API 地址（如 `https://api.openai.com` 或 `https://api.deepseek.com`）
2. **API Key**：你的 API 密钥
3. **Model Name**：模型名称（如 `gpt-4o`、`deepseek-chat`）

支持任何兼容 OpenAI 格式的 API。提供 OpenAI / Claude / DeepSeek 三个预设按钮一键填入，也可点 ☁ 按钮从 API 自动获取可用模型列表。

配置 LLM 后：

- **LLM 分析**：首页题库卡片菜单「LLM 分析」→ 按自定义 Prompt 对全库题目打分（可在 AI 配置页开启「导入后自动分析」）
- **AI 精选模式**：创建测试时选择，按 LLM 分数从高到低抽题；未配置 LLM 时该选项锁定并引导配置
- **AI 评分主观题**：主观题精确匹配失败时，可让 LLM 评分

自定义 Prompt 支持 `{questions_json}` 占位符，可自己定义筛选标准（如「选出与考试重点最相关的题目」）。

## 题目格式

支持 `.docx` 和 `.pdf`（PDF 按视觉行提取文本，格式要求相同）：

```
第一章 章节名

一、判断题
1．题干内容。（ A ）
A．对  B．错

二、单选题
1．题干内容（B）。
A．选项1     B．选项2     C．选项3     D．选项4

三、多选题
1．题干内容（ABD）。
A．选项1  B．选项2  C．选项3  D．选项4

四、简答题
1．题干内容？
解析：参考答案……
```

解析器兼容多种变体：判断题中文答案（对/错/√/×）、答案与解析分行或同行（「答案：B 解析：…」）、无选项的判断题自动补「正确/错误」选项、无编号题目、题目紧凑排布等。没有章节/题型标题的文档也会按标题关键词自动识别题型。

## 开发

```bash
# 运行测试
flutter test

# 静态检查
flutter analyze
```

## 许可证

GPL-3.0

# 题库抽题器 (Randomselector)

跨平台刷题应用，支持 Windows 和 Android。导入 Word/PDF 题库文档，自动解析题目，随机抽题刷题，错题本管理。

这个项目基本全部都由claude CLI加DeepSeek-v4-pro来完成 这也是我vibecoding出的第一个项目 可能有漏洞或bug 有的话和我提issue吧

## 功能

- **题库导入**：支持 `.docx`、`.pdf` 格式，自动解析章节、题型、题干、选项、答案
- **随机抽题**：从题库中随机抽取指定数量的题目
- **AI 精选模式**：基于本地规则引擎评分，或配置 LLM API 进行深度分析
- **逐题模式**：每次一题，即时判分
- **试卷模式**：全部显示，统一交卷
- **错题本**：自动收录错题，支持单独刷错题
- **暗色模式**：跟随系统主题
- **纯本地**：所有数据存储在本地 SQLite，无需账号

## 安装与运行

### 环境要求

- Flutter SDK 3.x+
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
flutter build windows

# Android APK
flutter build apk --release
```

## AI 功能配置

在"设置"页面填写：

1. **Base URL**：API 地址（如 `https://api.openai.com` 或 `https://api.anthropic.com`）
2. **API Key**：你的 API 密钥
3. **Model Name**：模型名称（如 `gpt-4o` 或 `claude-sonnet-5`）

支持任何兼容 OpenAI 格式的 API。点击"OpenAI 默认"或"Claude 默认"一键填入。

配置 LLM 后：
- 可使用 AI 精选模式（按难度/重要性/理论性综合排序）
- 可导入和评判主观题（填空、简答）

## 题目格式

支持的题目格式（以 .docx 为例）：

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
```

## 许可证

GPL-3.0

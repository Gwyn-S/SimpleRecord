---
name: gitcommit-plan
description: 当用户要求提交代码（说"提交"、"commit"、"拟提交"、"整合提交"、"分成几个提交"、"分主题提交"、"按主题分提交"、"分提交"）时使用。提交前必须先拟定每个提交的主题与消息，展示给用户确认，用户点头后才真正执行 git add / git commit。绝不先斩后奏。
---

# 提交前先拟定（Commit Plan First）

原则：**先拟提交，别真的提交。** 除非用户明确说"直接提交/commit"，否则一律：

1. 列提交方案，等用户确认。
2. 用户确认后再动手 add / commit。

## 流程

1. `git status --short` 与 `git log --oneline -5` 看清当前改动与提交风格。
2. 把未提交改动按**主题**分组（功能 / 修复 / 重构 / 清理要分开）。
3. 拟定每个提交的消息（遵循 conventional commits）：

   - `feat: ...` 新功能
   - `fix: ...` 修复
   - `refactor: ...` 重构
   - `chore: ...` 杂务（依赖、清理）
   - `docs: ...` 文档

   commit 名用中文，简洁、能概括主题。

4. 以表格或列表形式展示给用户：

   | 提交 | 拟提交的主题 / 消息 |
   |---|---|
   | 1 | feat: ... |

5. **必须等用户确认**。用户确认后，再逐条 `git add` + `git commit`。

## 约定（遵守，不要违反）

- 不要 add 这些构建产物：`app/pubspec.lock`、`app/macos/Flutter/GeneratedPluginRegistrant.swift`、`app/linux/flutter/generated_plugin_registrant.cc`、`app/linux/flutter/generated_plugins.cmake`、`app/windows/flutter/generated_plugin_registrant.cc`、`app/windows/flutter/generated_plugins.cmake`、`.omo/`。
- 别用 `git add .` / `git add -A` 一键全加；按主题精确 add。
- commit 消息里不要写临时注释或占位内容。
- 用户上次强调：**提交信息要一次定准**，改中间提交历史代价高（rebase 易出错）。拟定消息时把措辞想清楚再给用户。
- 若用户要求修改某个"已提交但未推送"的提交消息，推荐用 `git commit --amend`（仅最新）或先报备风险（中间提交需重写历史），不擅自 rebase。

## 完成后的汇报

- 列出本次实际产生的提交 hash + 消息。
- 提醒剩余未提交内容（如有），并说明未推送（除非用户明确要求 push）。
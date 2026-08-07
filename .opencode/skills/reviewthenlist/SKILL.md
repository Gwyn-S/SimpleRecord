---
name: reviewthenlist
description: Use when the user asks to review the SimpleRecord codebase and present findings as a table ("审查", "review", "列个表", "审查项目", "todolist"). Loads todolist.txt as the baseline checklist, checks each item against current code, and outputs a status table. Read-only: do not modify code unless asked.
---

# Review Then List

审查 SimpleRecord 项目代码并以表格形式输出结论。该 Skill 只读，不修改代码。

## 前置准备

1. 读取 `E:\KeepBook\todolist.txt`，它是审查基准清单（逐行格式：`优先级<TAB>类别<TAB>问题<TAB>位置<TAB>状态`）。
2. 运行 `git status --short` 和 `git log --oneline -5`（工作目录 `E:\KeepBook`），确认自上次审查以来改动了哪些文件。
3. 运行 `git diff --stat HEAD` 核对实际改动范围。

## 审查流程

1. **逐项核对**清单每行：
   - 用 grep/read 定位清单中标注的文件与行号（如 `bills_page.dart:129`），确认问题当前是否仍存在。
   - 状态符号定义：
     - `⬜` 未处理 / 仍存在
     - `◐` 部分处理 / 进行中
     - `✅` 已修复
     - `🚫` 决定不修（保持原状）
   - 注意：行号可能因近期改动偏移，以 grep 实际定位为准，不要盲目相信行号。
2. **检查新增问题**：对本次会话/提交涉及的改动文件，检查是否引入新隐患（如备份/恢复的 close 顺序、isolate 传参可传递性、临时文件清理等）。
3. **输出表格**，列头固定为：
   `| # | 类型 | 问题 | 位置 | 状态 |`
   - 保持清单原有行序与编号、类型（P1/P2/P3/—）、问题描述、位置不变，只更新状态列。
4. 表后附一段说明：本次改动了哪些文件、状态有无变化、是否发现新增问题。

## 约定

- 回答使用中文。
- 不修改任何代码文件，除非用户明确要求修复。
- 若 `git status` 显示未提交改动，在结论中说明。
- 若清单文件不存在或为空，则改为从代码库独立审查（架构/性能/健壮性/工程分层维度）并直接列表。

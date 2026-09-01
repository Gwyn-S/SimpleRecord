# SimpleRecord 四维度全库 Review

日期：2026-08-31
分支：feature/cloud-sync
范围：app/lib 全部 Dart 文件（92 个）
方式：4 个子代理首轮扫描 → 4 个子代理二次回读复核（每项核对真实性/行号/严重度）

## 结论说明

- 首轮 32 项候选经二次复核：2 项被排除、约 6 项下调定级、对象合并收窄 2 组、行号/行数修正若干
- 二次复核新增 3 项（含 2 项涉及数据正确性，为最重要发现）
- 工作区在审查期间未做任何代码修改

---

## P1 — 建议修（正确性/用户可见）

| # | 位置 | 问题 | 状态 |
|---|------|------|------|
| 1 | `services/sync_service.dart`（oplog 设计）+ `services/supabase_service.dart:215-226,246-249` | **云同步冲突策略与注释不符**：类注释声称"按 created_at 最后写赢"，但 oplog 只存记录创建时间（不区分 insert/update/delete 先后）、按 id 升序应用，实际为"**最后上传赢**"。离线旧编辑上线可静默覆盖在线新编辑；update 以 replace 实现，叠加陈旧 update 还会复活已删记录 | ⏸ 待决（用户暂缓） |
| 2 | `services/ledger_service.dart:96-127` + `pages/ledger_list_page.dart:398` | **共享账本删除无权限校验/无警示**：任一成员删除共享账本，远端会删除该账本全部记录（`sync_service.dart:234-238`），确认框无"影响所有成员"提示、无恢复路径 | ⏸ 待决（用户再考虑） |
| 3 | ~~`pages/stats_page.dart:58-68` + `pages/main_page.dart:60-84`~~ | ~~**统计页不监听版本/账本变化**：IndexedStack 保活不重建，`initState` 仅首次 `_loadData`，全库唯一未 addListener(`recordsVersion`/`currentLedgerId`) 的列表页 → 切账本/增删记录后展示旧数据~~ ✅ 已处理（`641d18c`） |
| 4 | ~~`services/stats_service.dart:8-21` + `pages/stats_page.dart:125-130,226`~~ | ~~**统计缓存 key 缺维度**：`StatsCacheKey` 缺 ledgerId 与 custom 起止日期，切账本快速切换时命中旧账本缓存（与 #3 独立但关联，service 本身每次真查库）~~ ✅ 已处理（`641d18c` + `8cb3b94`） |
| 5 | ~~`pages/stats_page.dart:102-134`~~ | ~~**统计页 `_loadData` 竞态无 seq 保护**：快速切换 range/index 时异步返回乱序，后到覆盖先到展示错位（对比 `bills_page.dart:39,61,77` 有 `_loadSeq`）~~ ✅ 已处理（`fdd7258`） |

## P2 — 可优化（结构/性能）

| # | 位置 | 问题 |
|---|------|------|
| 6 | ~~`pages/ai_text_record_page.dart:152-169` / `ai_image_record_page.dart:147-164` / `ai_voice_record_page.dart:189-206`~~ | ~~三 AI 页结果区 UI（ListView+AiRecordResultCard+确认按钮）及 `_saveRecords` 薄包装三份复制；保存核心已复用 `saveAiResults`，可再抽结果区组件~~ **✅ 已处理**（`b7d65f9`：三页结果区已抽为共用 `AiRecordResultSection`，置于 `ai_record_result_card.dart`，删除独立文件） |
| 7 | ~~`constants/app_colors.dart:46-53` + `models/asset_account.dart:30-37` + `services/asset_account_service.dart:11-30` + `pages/add_asset_account_page.dart`~~ | ~~**资产分类元数据（颜色+图标）分散 4 文件**：8 组颜色与 `colorAssetXxx` 1:1 重复、分类图标与类型图标映射多处维护，改一漏一即不一致~~ **✅ 已处理**（`3e0fe2e`：7 个无引用 `colorAssetXxx` 删除、`_iconByCategory` 删除改查 `assetAccountCategories`） |
| 8 | ~~`widgets/bill_detail_sheet.dart:129` / `pages/manual_entry_page.dart:412`~~ | ~~全屏图片查看器两处平行实现，可抽公共组件 + 可选 onDelete~~ **✅ 已处理**（`693cdbf`：抽公共 `FullImageViewer` + 账单详情补全删图回调） |
| 9 | `services/ledger_service.dart:11-12,90-93` | 本地账本 CRUD 反向依赖 supabase/sync 层；`renameRoom` 结果被 `unawaited` 丢弃，失败时新加入者拿到旧账本名、无重试无提示 |
| 10 | `services/sync_service.dart:76-162,164-240,242-367` + 循环 import | 同步引擎一个类兼职上行/下行/订阅/编排多职责，且与 `record_service` 循环 import（仅为 `recordsVersion` 一个量）；另 `refresh()` 为死代码无调用点、outbox 表无清理无限膨胀、并发 flush 产生重复 oplog |
| 11 | ~~`pages/stats_page.dart:131-133`~~ | ~~`_loadData` catch 空吞无提示无日志；`data==null`（ledgerId 空）也不提示~~ **⏸ 已评估跳过（账本不会空、启动自动创建，仅剩数据库损坏极端场景，用户判定无修的价值）** |

## P3 — 可选/洁癖

| # | 位置 | 问题 |
|---|------|------|
| 12 | ~~`pages/bills_page.dart:210-296` / `calendar_page.dart:336-387` / `stats_detail_page.dart:87-171`~~ | ~~日卡片折叠列表结构三处同构~~ **✅ 已处理**（`6baa20e`：抽公共 `DayCard`，三页统一） |
| 13 | ~~`pages/stats_page.dart:50-54` / `asset_statistics_page.dart:139-145` / `stats_service.dart:267`~~ | ~~"今年/去年/前年"标签三处重复~~ **✅ 已处理**（`f4ecb00`：抽公共 `yearLabel`；另 `stats_service.dart:267` 实为月份标签，非年份重复，录入原误认，未动） |
| 14 | ~~`pages/manual_entry_page.dart:269-275` / `transfer_page.dart:267-276`~~ | ~~金额实时预览三目表达式逐字重复，可入 `calculator.dart`~~ **✅ 已处理**（`f4e13a7`：抽公共 `amountPreview`） |
| 15 | ~~`local_backup_page.dart:69-96` / `webdav_page.dart:168-212`~~ | ~~srb 恢复确认Key弹窗重复（独立于 AppBar 问题）~~ **⏸ 已评估跳过**（骨架同、文案及确定逻辑分叉，抽公共会加迁就参数） |
| 16 | ~~`transfer_page.dart:139` / `asset_detail_page.dart:421` / `tag_manage_page.dart:32`~~ | ~~单字段输入 AlertDialog 3 处一致样板可抽公共函数（budget/ledger 样式不同不入列）~~ **⏸ 已评估跳过**（asset/tag 的"确定"按钮耦合异步保存+校验+是否关闭，强行抽公共参数过重） |
| 17 | ~~`pages/backup_page.dart:18` / `local_backup_page.dart:116` / `webdav_page.dart:240` / `supabase_sync_page.dart:118`~~ | ~~四处手写 AppBar 与 `CommonAppBar` 重复（支持 bottom 可替换）~~ **✅ 已处理**（`0e1a039`：四处统一 `CommonAppBar`，各保留 1px 分隔线 `bottom`） |
| 18 | ~~`pages/assets_page.dart:54-60,176`~~ | ~~`_grouped` 每次 build 重建 + `entries.elementAt` O(n²)（账户数十个量级影响小）~~ **✅ 已处理**（`d86e34f`：分组缓存到 `_categoryEntries`，下标取值） |
| 19 | ~~`services/settings.dart:38-44`~~ | ~~每次 set 全量 `writeAsStringSync`，webdav 保存连写 4 次、cloud_config 连写 2 次~~ **✅ 已处理**（`696851e`：新增 `setStrings` 批量写 + 单次落盘，webdav/cloud 改为一次调用） |
| 20 | `sync_service.dart:273,334,427` | subscribeOplogs 回调三处重复且再判 room_id（订阅已 filter 冗余） —— **⏸ 云端待决** |
| 21 | `pages/bills_page.dart:71-76` + `ledger_service.dart:68-70` | 每次变更全表 `loadLedgers()` 仅判断当前账本 syncMode，有单查可替代 |
| 22 | ~~`services/ai_service.dart:192` / `widgets/ai_record_result_card.dart:55`~~ | ~~两处私有 `_pad` 重复且都重复既有 `pad2`(formatters.dart:51)；加 `formatDateYmd` 未复用~~ **✅ 已处理**（`f44e826`：两处改复用 `pad2` 并删私有 `_pad`） |
| 23 | ~~`pages/search_page.dart:449-450`~~ | ~~`_fmtAmount` 与 `formatAmountEdit` 等价，可复用~~ **✅ 已处理**（`29092cf`：删 `_fmtAmount`，改复用 `formatAmountEdit`） |
| 24 | `pages/asset_statistics_page.dart:282-289` | 走势图为 `SimpleRandom(42)` 占位假数据（仅当前月真实），过期 TODO |
| 25 | `pages/budget_page.dart:93-96` | 每分类一次 `Settings.getInt`（实为内存读，影响可忽略） |
| 26 | `services/` 多处 | 模型类挤在服务文件未归 `models/`：`Tag`/`AiConfig`/`WebDavConfig`/`WebDavFile`/`LedgerStats`/`TencentAsrConfig` |
| 27 | `services/ai_service.dart:210,232,242` + `supabase_service.dart:129,144,195,229,250` | 空 catch 静默降级吞异常（AI 有兜底 return、supabase 有"上层重试"设计注释，但无日志不利排查） |
| 28 | `pages/user_page.dart:67` / `ai_record_page.dart:264` | 两页各自 `_settingsItem`（有 trailing 差异） —— **⏸ 已评估跳过**（横间距 20 vs spacingL=16 本就不同，抽公共会改视觉或加迁就参数） |
| 29 | ~~`services/stats_service.dart:166-170,159`~~ | ~~`_buildPeriodData` 形参 `customStart` 传入从未引用（死参数）~~ **✅ 已处理**（`ec02e29`） |
| 30 | ~~`services/theme_service.dart:8`~~ | ~~主题主色 `0xFF3F9795` 未集中常量~~ **✅ 已处理**（`7540e6f`：抽 `colorPrimaryDefault`，全项目仅此一处） |
| 31 | `pages/ai_record_page.dart:79-100` | `_supports`/`_modelField` 双 switch 镜像可精简 |
| 32 | 约 16 个文件 | import 排序分组混乱、4 处缩进错位、多处超长行/行尾空格——`dart format` 可批收敛 |
| 33 | services/ 12 个文件约 30 处 | 公共 API 缺 `///` 文档注释 |
| 34 | `pages/main.dart:29` | `start()` 未 await，多步 async 失败为 unhandled error（非仅 debugPrint），快速触发有并发重入 |
| 35 | `pages/ledger_list_page.dart:45-48,69-79` | `_loadStats` 无 try/catch，`Future.wait` 无异常兜底 |
| 36 | `sync_service.dart:215-238` / `asset_statistics_page.dart:56-64` | switch 非空 case 无 break——Dart 3 隐式 break 下功能正确，纯可读性 |

## 排除项（首轮误报，经复核排除）

| 原候选 | 排除原因 |
|--------|---------|
| asset_statistics 图表未复用 trend_line_chart | X 轴类型（Category vs Numeric）、数据模型、tooltip 均不同，强合收益低 |
| sync `_deviceId` 未初始化防回声失效 | 所有订阅路径在赋值之后，实际不可触发 |
| >500 行文件需拆分（search 635/calendar 631/asset_detail 560/budget 556/ledger 543） | 单页 UI 复杂度、分区清晰，不建议强拆 |

## 汇总

- P1 5（已处理 3：#3/#4/#5；待决 2：#1/#2）/ P2 6 / P3 25 / 排除 3（含 >500 行组）
- 待决：#1 云同步冲突策略与注释不符、#2 共享账本删除无警示 —— 详见归档 txt；P3#20 云端回调，并入云端待决
- 已处理：P1#3/#4/#5（641d18c / 8cb3b94 / fdd7258）；P2#6/#7/#8（b7d65f9 / 3e0fe2e / 693cdbf）；P3#12/#13/#14/#17/#18/#19/#22/#23/#29/#30（6baa20e / f4ecb00 / f4e13a7 / 0e1a039 / d86e34f / 696851e / f44e826 / 29092cf / ec02e29 / 7540e6f）
- 已评估跳过（未在清单时增录）：恢复确认弹窗（#15）、单字段输入框（#16）、两页 `_settingsItem`（#28，横间距本就不同）；走势图假数据（#24）待后续
- 额外收尾（非清单原项）：日卡片金额样式抽 `textDayAmount`（acf17ac）；共享账本结余分组分支（随 6baa20e 并入 DayCard）
- 工作区在新分支 feature/cloud-sync 进行
## P1 — 建议修（正确性/用户可见）

| # | 位置 | 问题 | 状态 |
|---|------|------|------|
| 1 | `services/sync_service.dart`（oplog 设计）+ `services/supabase_service.dart:215-226,246-249` | **云同步冲突策略与注释不符**：类注释声称"按 created_at 最后写赢"，但 oplog 只存记录创建时间（不区分 insert/update/delete 先后）、按 id 升序应用，实际为"**最后上传赢**"。离线旧编辑上线可静默覆盖在线新编辑；update 以 replace 实现，叠加陈旧 update 还会复活已删记录 | ⏸ 待决（用户暂缓） |
| 2 | `services/ledger_service.dart:96-127` + `pages/ledger_list_page.dart:398` | **共享账本删除无权限校验/无警示**：任一成员删除共享账本，远端会删除该账本全部记录（`sync_service.dart:234-238`），确认框无"影响所有成员"提示、无恢复路径 | ⏸ 待决（用户再考虑） |

## P2 — 可优化（结构/性能）

| # | 位置 | 问题 |
|---|------|------|
| 9 | `services/ledger_service.dart:11-12,90-93` | 本地账本 CRUD 反向依赖 supabase/sync 层；`renameRoom` 结果被 `unawaited` 丢弃，失败时新加入者拿到旧账本名、无重试无提示 |
| 10 | `services/sync_service.dart:76-162,164-240,242-367` + 循环 import | 同步引擎一个类兼职上行/下行/订阅/编排多职责，且与 `record_service` 循环 import（仅为 `recordsVersion` 一个量）；另 `refresh()` 为死代码无调用点、outbox 表无清理无限膨胀、并发 flush 产生重复 oplog |

## P3 — 可选/洁癖

| # | 位置 | 问题 |
|---|------|------|
| 20 | `sync_service.dart:273,334,427` | subscribeOplogs 回调三处重复且再判 room_id（订阅已 filter 冗余） —— **⏸ 云端待决** |
| 24 | `pages/asset_statistics_page.dart:282-289` | 走势图为 `SimpleRandom(42)` 占位假数据（仅当前月真实），过期 TODO |
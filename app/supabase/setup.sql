-- ============================================================
-- SimpleRecord 双人云同步 - Supabase 初始化脚本
-- 用法：Supabase 控制台 → SQL Editor → 粘贴整段执行
-- 前置：Authentication → Sign In / Up → 开启 "Anonymous sign-ins"
-- ============================================================

-- 房间 = 共享账本。id 与本地账本 id 对齐（客户端生成的 uuid）
create table if not exists public.rooms (
  id uuid primary key,
  name text not null,
  owner_id uuid not null,
  members uuid[] not null default '{}',
  invite_code text not null,
  seq bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists rooms_invite_code_key on public.rooms (invite_code);

-- 操作日志：上行写入此表，下行按自增 id 增量拉取
create table if not exists public.oplogs (
  id bigserial primary key,
  room_id uuid not null references public.rooms (id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  op text not null,
  payload jsonb not null,
  uid uuid,
  device_id text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists oplogs_room_id_idx on public.oplogs (room_id, id);

-- RLS：家庭双人场景，所有已登录(authenticated)用户可读写，
-- 邀请码做软隔离。未来若需严格隔离，再按 members 收紧。
alter table public.rooms enable row level security;
alter table public.oplogs enable row level security;

create policy rooms_read_all on public.rooms
  for select to authenticated using (true);
create policy rooms_write_all on public.rooms
  for all to authenticated using (true) with check (true);
create policy oplogs_read_all on public.oplogs
  for select to authenticated using (true);
create policy oplogs_write_all on public.oplogs
  for all to authenticated using (true) with check (true);

-- Realtime：把两表加进发布，App 端才能收到推送
alter publication supabase_realtime add table public.oplogs;
alter publication supabase_realtime add table public.rooms;
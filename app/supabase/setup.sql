-- ============================================================
-- SimpleRecord 家庭共享账本 - Supabase 初始化脚本（真实邮箱认证版）
-- 用法：Supabase 控制台 → SQL Editor → 粘贴整段执行
-- 前置：Authentication → Sign In / Up → 开启 "Email"（邮箱+密码）。
--       建议关闭 "Confirm email"，避免注册后还需邮件确认。
--
-- 注意：本脚本会清理并重建——
--       1. DROP rooms/oplogs/profiles 业务表；
--       2. 清空 auth.users 全部注册用户。
--       当前应用尚未发布，允许直接重建；如有已存数据请自行备份。
--
-- avatars 桶的头像文件不在本脚本清理：新版 Supabase 对 storage 表启用
-- protect_delete 触发器并限制属主（supabase_admin），SQL 直接删除会被拦截。
-- 请用控制台（Storage → avatars → 全选删除）或官方 Storage API 清空，见下：
--   curl -X DELETE "$SUPABASE_URL/storage/v1/bucket/avatars?emptied=true" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY"
-- （SUPABASE_URL / SERVICE_ROLE_KEY 在项目 Settings → API 里获取；
--   emptied=true 表示清空桶内对象但保留桶本身。）
-- ============================================================

-- 清空全部注册用户（auth.users 由 Supabase 管理，含密码/会话等）。
-- cascade 会同时清掉这些用户关联的 storage 对象等其他引用；
-- public.profiles.author_id 只是 text、无外键，删除用户不影响。
truncate table auth.users cascade;

-- 房间 = 共享账本。id 与本地账本 id 对齐（客户端生成的 uuid）
-- owner_id / members 存的是登录邮箱（author_id），非匿名 uid。
drop table if exists public.piggy_ops;
drop table if exists public.piggies;
drop table if exists public.oplogs;
drop table if exists public.rooms;
drop table if exists public.profiles;

create table public.rooms (
  id uuid primary key,
  name text not null,
  owner_id text not null,
  members text[] not null default '{}',
  invite_code text not null,
  seq bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index rooms_invite_code_key on public.rooms (invite_code);
create index rooms_members_idx on public.rooms using gin (members);

-- 操作日志：上行写入此表，下行按自增 id 增量拉取
create table public.oplogs (
  id bigserial primary key,
  room_id uuid not null references public.rooms (id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  op text not null,
  payload jsonb not null,
  uid text,
  device_id text not null default '',
  created_at timestamptz not null default now()
);
create index oplogs_room_id_idx on public.oplogs (room_id, id);

-- 昵称/头像（author_id 主键，author_id = 登录邮箱）
create table public.profiles (
  author_id text primary key,
  nickname text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- ============ RLS：严格按成员隔离，成员身份 = 登录邮箱 ============
alter table public.rooms enable row level security;
alter table public.oplogs enable row level security;
alter table public.profiles enable row level security;

-- rooms：仅本房间成员可见（select），仅成员可改
create policy rooms_read_member on public.rooms
  for select to authenticated
  using (auth.jwt() ->> 'email' = any(members));
create policy rooms_write_member on public.rooms
  for all to authenticated
  using (auth.jwt() ->> 'email' = any(members))
  with check (auth.jwt() ->> 'email' = any(members));

-- oplogs：通过所属房间的成员资格放行读写
create policy oplogs_read_member on public.oplogs
  for select to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = oplogs.room_id
        and auth.jwt() ->> 'email' = any(r.members)
    )
  );
create policy oplogs_write_member on public.oplogs
  for all to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = oplogs.room_id
        and auth.jwt() ->> 'email' = any(r.members)
    )
  )
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = oplogs.room_id
        and auth.jwt() ->> 'email' = any(r.members)
    )
  );

-- profiles：昵称/头像对所有已登录用户可读（家人展示用）；
-- 写仅限自己（author_id = 当前登录邮箱）
create policy profiles_read_all on public.profiles
  for select to authenticated using (true);
create policy profiles_write_own on public.profiles
  for insert to authenticated
  with check (author_id = auth.jwt() ->> 'email');
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (author_id = auth.jwt() ->> 'email')
  with check (author_id = auth.jwt() ->> 'email');

-- Realtime：把表加进发布，App 端才能收到推送（授权跟随各表 RLS）
alter publication supabase_realtime add table public.oplogs;
alter publication supabase_realtime add table public.rooms;

-- ============ 邀请码加入 RPC ============
-- 普通 select 受房间 RLS 阻挡，未加入者无法先查房间；
-- 这里用 SECURITY DEFINER 让函数以定义者权限一次完成「查房间 + 加入 members」。
-- 只有知晓有效邀请码的已登录用户才能加入，加入后该房间的 RLS 才会对其放行。
create or replace function public.join_by_invite(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  select * into v_room
    from public.rooms
    where invite_code = upper(btrim(p_invite_code));

  if not found then
    return null;
  end if;

  if not v_email = any(v_room.members) then
    update public.rooms
      set members = array_append(v_room.members, v_email),
          updated_at = now()
      where id = v_room.id;
    v_room.members := array_append(v_room.members, v_email);
  end if;

  return to_jsonb(v_room);
end;
$$;

grant execute on function public.join_by_invite(text) to authenticated;

-- ============ 全局小金库（跨账本共享资产）============
-- 小金库 = 两个账号共享的一个全局资产。一人创建（owner）、另一人凭邀请码加入（peer）。
-- 双方可见、可存取（存=deposit 支出语义、取=withdraw 收入语义）。
-- 余额通过 append-only 的 piggy_ops 事件同步。
-- 本表同样纳入「清空重建」集（见文件头 DROP 区）。

create table public.piggies (
  id uuid primary key,
  name text not null default '小金库',
  owner_email text not null,
  peer_email text,               -- 未加入前为 null
  invite_code text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index piggies_invite_code_key on public.piggies (invite_code);

create table public.piggy_ops (
  id bigserial primary key,
  piggy_id uuid not null references public.piggies (id) on delete cascade,
  entity_id text not null,         -- 本地操作事件 id（字符串）
  op text not null,                -- deposit / withdraw
  payload jsonb not null,          -- {piggy_id, delta, remark, operator_email}
  uid text,
  device_id text not null default '',
  created_at timestamptz not null default now()
);
create index piggy_ops_piggy_id_idx on public.piggy_ops (piggy_id, id);

-- ============ 小金库 RLS：仅 owner/peer 双方可见可写 ============
alter table public.piggies enable row level security;
alter table public.piggy_ops enable row level security;

create policy piggies_read_participant on public.piggies
  for select to authenticated
  using (auth.jwt() ->> 'email' = owner_email or auth.jwt() ->> 'email' = peer_email);
create policy piggies_write_participant on public.piggies
  for all to authenticated
  using (auth.jwt() ->> 'email' = owner_email or auth.jwt() ->> 'email' = peer_email)
  with check (auth.jwt() ->> 'email' = owner_email or auth.jwt() ->> 'email' = peer_email);

create policy piggy_ops_read_participant on public.piggy_ops
  for select to authenticated
  using (
    exists (
      select 1 from public.piggies p
      where p.id = piggy_ops.piggy_id
        and (auth.jwt() ->> 'email' = p.owner_email or auth.jwt() ->> 'email' = p.peer_email)
    )
  );
create policy piggy_ops_write_participant on public.piggy_ops
  for all to authenticated
  using (
    exists (
      select 1 from public.piggies p
      where p.id = piggy_ops.piggy_id
        and (auth.jwt() ->> 'email' = p.owner_email or auth.jwt() ->> 'email' = p.peer_email)
    )
  )
  with check (
    exists (
      select 1 from public.piggies p
      where p.id = piggy_ops.piggy_id
        and (auth.jwt() ->> 'email' = p.owner_email or auth.jwt() ->> 'email' = p.peer_email)
    )
  );

-- Realtime：piggy_ops 加进发布，双方实时收到 INSERT
alter publication supabase_realtime add table public.piggy_ops;

-- ============ 小金库 RPC ============
-- create_piggy：id 由客户端生成（与本地小金库 id 对齐），owner = 当前登录邮箱。
-- invite_code 唯一冲突（或 id 冲突）时返回 null；成功返回该行 jsonb。
create or replace function public.create_piggy(p_id uuid, p_name text, p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.piggies;
begin
  insert into public.piggies (id, name, owner_email, peer_email, invite_code)
  values (p_id, p_name, auth.jwt() ->> 'email', null, upper(btrim(p_invite_code)))
  on conflict do nothing;

  select * into v_row from public.piggies where id = p_id;
  if not found then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;

grant execute on function public.create_piggy(uuid, text, text) to authenticated;

-- join_piggy_by_invite：仿 join_by_invite 原子完成「查小金库 + 填 peer」。
-- 已是 owner 直接返回该行；peer_email 为空则填入当前邮箱并返回行；
-- 已是 peer 直接返回该行（重复加入幂等）；否则（peer 已被他人占用）返回 null。
create or replace function public.join_piggy_by_invite(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_piggy public.piggies;
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  select * into v_piggy
    from public.piggies
    where invite_code = upper(btrim(p_invite_code));

  if not found then
    return null;
  end if;

  if v_email = v_piggy.owner_email then
    return to_jsonb(v_piggy);
  end if;

  if v_piggy.peer_email is null then
    update public.piggies
      set peer_email = v_email,
          updated_at = now()
      where id = v_piggy.id;
    v_piggy.peer_email := v_email;
    return to_jsonb(v_piggy);
  end if;

  if v_email = v_piggy.peer_email then
    return to_jsonb(v_piggy);
  end if;

  return null;
end;
$$;

grant execute on function public.join_piggy_by_invite(text) to authenticated;
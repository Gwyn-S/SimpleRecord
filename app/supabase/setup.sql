-- ============================================================
-- SimpleRecord 家庭共享账本 - Supabase 初始化脚本（真实邮箱认证版）
-- 用法：Supabase 控制台 → SQL Editor → 粘贴整段执行
-- 前置：Authentication → Sign In / Up → 开启 "Email"（邮箱+密码）。
--       建议关闭 "Confirm email"，避免注册后还需邮件确认。
--
-- 注意：本脚本会 DROP 已存在的 rooms/oplogs/profiles 表。
--       当前应用尚未发布，允许直接重建；如有已存数据请自行备份。
-- ============================================================

-- 房间 = 共享账本。id 与本地账本 id 对齐（客户端生成的 uuid）
-- owner_id / members 存的是登录邮箱（author_id），非匿名 uid。
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
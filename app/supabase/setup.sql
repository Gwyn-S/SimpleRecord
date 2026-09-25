-- ============================================================
-- SimpleRecord - Supabase 初始化脚本
-- 幂等可重复执行：先清理业务表/函数/注册用户，再重建。
-- ============================================================

-- ============ 1. 清理（先删子表后删父表）============

truncate table auth.users cascade;

drop table if exists public.vault_ops;
drop table if exists public.vaults;
drop table if exists public.ledger_ops;
drop table if exists public.ledger;
drop table if exists public.profiles;

drop function if exists public.create_vault(uuid, text, text, text);
drop function if exists public.create_vault(uuid, text, text);
drop function if exists public.join_vault_by_invite(text);
drop function if exists public.delete_vault(uuid);
drop function if exists public.join_by_invite(text);

-- ============ 2. 表结构 ============

-- 房间 = 共享账本。id 与本地账本 id 对齐（客户端生成的 uuid）
-- owner_id / members 存的是登录邮箱（author_id），非匿名 uid。
create table public.ledger (
  id uuid primary key,
  name text not null,
  owner_id text not null,
  members text[] not null default '{}',
  invite_code text not null,
  seq bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index ledger_invite_code_key on public.ledger (invite_code);
create index ledger_members_idx on public.ledger using gin (members);

-- 操作日志：上行写入此表，下行按自增 id 增量拉取
create table public.ledger_ops (
  id bigserial primary key,
  ledger_id uuid not null references public.ledger (id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  op text not null,
  payload jsonb not null,
  uid text,
  device_id text not null default '',
  created_at timestamptz not null default now()
);
create index ledger_ops_ledger_id_idx on public.ledger_ops (ledger_id, id);

-- 昵称/头像（author_id 主键，author_id = 登录邮箱）
create table public.profiles (
  author_id text primary key,
  nickname text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- ============ 3. RLS：严格按成员隔离，成员身份 = 登录邮箱 ============

alter table public.ledger enable row level security;
alter table public.ledger_ops enable row level security;
alter table public.profiles enable row level security;

-- ledger：仅本房间成员可见（select），仅成员可改
create policy ledger_read_member on public.ledger
  for select to authenticated
  using (auth.jwt() ->> 'email' = any(members));
create policy ledger_write_member on public.ledger
  for all to authenticated
  using (auth.jwt() ->> 'email' = any(members))
  with check (auth.jwt() ->> 'email' = any(members));

-- ledger_ops：通过所属房间的成员资格放行读写
create policy ledger_ops_read_member on public.ledger_ops
  for select to authenticated
  using (exists (
    select 1 from public.ledger r
    where r.id = ledger_ops.ledger_id
      and auth.jwt() ->> 'email' = any(r.members)
  ));
create policy ledger_ops_write_member on public.ledger_ops
  for all to authenticated
  using (exists (
    select 1 from public.ledger r
    where r.id = ledger_ops.ledger_id
      and auth.jwt() ->> 'email' = any(r.members)
  ))
  with check (exists (
    select 1 from public.ledger r
    where r.id = ledger_ops.ledger_id
      and auth.jwt() ->> 'email' = any(r.members)
  ));

-- profiles：昵称/头像对所有已登录用户可读（家人展示用）；写仅限自己
create policy profiles_read_all on public.profiles
  for select to authenticated using (true);
create policy profiles_write_own on public.profiles
  for insert to authenticated
  with check (author_id = auth.jwt() ->> 'email');
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (author_id = auth.jwt() ->> 'email')
  with check (author_id = auth.jwt() ->> 'email');

-- ============ 4. Realtime：App 端才能收到推送（授权跟随各表 RLS）============

alter publication supabase_realtime add table public.ledger_ops;
alter publication supabase_realtime add table public.ledger;

-- ============ 5. 账本邀请码加入 RPC ============
create or replace function public.join_by_invite(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ledger public.ledger;
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  select * into v_ledger
    from public.ledger
    where invite_code = upper(btrim(p_invite_code));

  if not found then
    return null;
  end if;

  if not v_email = any(v_ledger.members) then
    update public.ledger
      set members = array_append(v_ledger.members, v_email),
          updated_at = now()
      where id = v_ledger.id;
    v_ledger.members := array_append(v_ledger.members, v_email);
  end if;

  return to_jsonb(v_ledger);
end;
$$;

grant execute on function public.join_by_invite(text) to authenticated;

-- ============ 6. 多人金库房间 ============
-- 金库 = 两个账号共享的一个小金库资产。一人创建（owner）、另一人凭邀请码加入（peer），
-- 双方可见可存取。金库以本地资产账户（category_name = 小金库）为 owner 载体。

create table public.vaults (
  id uuid primary key,
  name text not null default '小金库',
  owner_email text not null,
  peer_email text,               -- 未加入前为 null
  invite_code text not null,
  remark text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index vaults_invite_code_key on public.vaults (invite_code);
create index vaults_owner_idx on public.vaults (owner_email);
create index vaults_peer_idx on public.vaults (peer_email);

-- 金库存取动作事件（append-only，增量同步）
create table public.vault_ops (
  id bigserial primary key,
  vault_id uuid not null references public.vaults (id) on delete cascade,
  entity_id text not null,         -- 本地操作事件 id（字符串）
  op text not null,                -- deposit / withdraw
  payload jsonb not null,          -- {vault_id, delta, remark, operator_email}
  uid text,
  device_id text not null default '',
  created_at timestamptz not null default now()
);
create index vault_ops_vault_id_idx on public.vault_ops (vault_id, id);
create unique index if not exists vault_ops_entity_id_uidx
  on public.vault_ops (entity_id);

-- vaults：仅 owner / peer 双方可见可写
alter table public.vaults enable row level security;
alter table public.vault_ops enable row level security;

create policy vaults_read_participant on public.vaults
  for select to authenticated
  using (auth.jwt() ->> 'email' = owner_email
    or auth.jwt() ->> 'email' = peer_email);
create policy vaults_write_participant on public.vaults
  for all to authenticated
  using (auth.jwt() ->> 'email' = owner_email
    or auth.jwt() ->> 'email' = peer_email)
  with check (auth.jwt() ->> 'email' = owner_email
    or auth.jwt() ->> 'email' = peer_email);

create policy vault_ops_read_participant on public.vault_ops
  for select to authenticated
  using (exists (
    select 1 from public.vaults p
    where p.id = vault_ops.vault_id
      and (auth.jwt() ->> 'email' = p.owner_email
        or auth.jwt() ->> 'email' = p.peer_email)
  ));
create policy vault_ops_write_participant on public.vault_ops
  for all to authenticated
  using (exists (
    select 1 from public.vaults p
    where p.id = vault_ops.vault_id
      and (auth.jwt() ->> 'email' = p.owner_email
        or auth.jwt() ->> 'email' = p.peer_email)
  ))
  with check (exists (
    select 1 from public.vaults p
    where p.id = vault_ops.vault_id
      and (auth.jwt() ->> 'email' = p.owner_email
        or auth.jwt() ->> 'email' = p.peer_email)
  ));

alter publication supabase_realtime add table public.vault_ops;

-- create_vault：id 由客户端生成（与本地小金库账户 id 对齐），owner = 当前登录邮箱。
-- 冲突显式抛错细分：invite_code_taken（邀请码撞车）、vault_id_taken（id 撞车）。
create or replace function public.create_vault(
  p_id uuid,
  p_name text,
  p_invite_code text,
  p_remark text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_code text := upper(btrim(p_invite_code));
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.vaults where invite_code = v_code) then
    raise exception 'invite_code_taken';
  end if;
  if exists (select 1 from public.vaults where id = p_id) then
    raise exception 'vault_id_taken';
  end if;
  insert into public.vaults (id, name, owner_email, peer_email, invite_code, remark)
  values (p_id, p_name, v_email, null, v_code, p_remark);
  return to_jsonb((select v from public.vaults v where id = p_id));
end;
$$;

grant execute on function public.create_vault(uuid, text, text, text) to authenticated;

-- join_vault_by_invite：仿 join_by_invite 原子完成「查金库 + 填 peer」。
-- 已是 owner 直接返回该行；peer_email 为空则填入当前邮箱并返回行；
-- 已是 peer 直接返回该行（重复加入幂等）；否则（peer 已被他人占用）返回 null。
create or replace function public.join_vault_by_invite(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vault public.vaults;
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  select * into v_vault
    from public.vaults
    where invite_code = upper(btrim(p_invite_code));

  if not found then
    return null;
  end if;

  if v_email = v_vault.owner_email then
    return to_jsonb(v_vault);
  end if;

  if v_vault.peer_email is null then
    update public.vaults
      set peer_email = v_email,
          updated_at = now()
      where id = v_vault.id;
    v_vault.peer_email := v_email;
    return to_jsonb(v_vault);
  end if;

  if v_email = v_vault.peer_email then
    return to_jsonb(v_vault);
  end if;

  return null;
end;
$$;

grant execute on function public.join_vault_by_invite(text) to authenticated;

-- delete_vault：删除金库房间（仅 owner / peer 本人可删），
-- vault_ops 依赖 on delete cascade 一并清理。
create or replace function public.delete_vault(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;
  delete from public.vaults
    where id = p_id
      and (owner_email = v_email or peer_email = v_email);
  return found;
end;
$$;

grant execute on function public.delete_vault(uuid) to authenticated;
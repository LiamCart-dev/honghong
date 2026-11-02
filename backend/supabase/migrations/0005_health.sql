-- 哄哄 健康记录家庭同步（#1 / 原 #28）：shared_health_logs + RLS + push_health_logs。
-- 不改现有表。本地对应 drift health_logs（schema v6）。
--
-- 【执行须知 / ADR-0010】
-- 迁移由 DevOps 在发版前按 0004 → 0005 顺序执行；执行前再找 Liam 确认。
-- 开发不自己跑线上迁移。0005 不依赖 0004（可单独执行，但上线清单仍建议先 0004）。
-- 执行后请：notify pgrst, 'reload schema';

create table public.shared_health_logs (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  baby_id uuid not null references public.shared_babies(id) on delete cascade,
  kind text not null check (kind in ('temperature', 'medication', 'symptom')),
  at timestamptz not null,
  temp_c double precision,
  temp_site text check (temp_site is null or temp_site in ('armpit', 'ear', 'forehead', 'rectal', 'oral')),
  med_kind text check (med_kind is null or med_kind in ('drug', 'supplement')),
  med_name text check (med_name is null or char_length(med_name) <= 20),
  med_dose text check (med_dose is null or char_length(med_dose) <= 20),
  symptoms text, -- JSON 数组字符串，与本地一致
  symptom_other text check (symptom_other is null or char_length(symptom_other) <= 20),
  note text,
  updated_at timestamptz not null,
  updated_by uuid not null default auth.uid(),
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
  -- 故意不在库里写体温范围 CHECK（范围由客户端配置校验）
);
create index on public.shared_health_logs (family_id, server_updated_at);

create trigger t_touch before insert or update on public.shared_health_logs
  for each row execute function public.touch_server_updated_at();

alter table public.shared_health_logs enable row level security;

create policy health_sel on public.shared_health_logs for select to authenticated
  using (public.is_family_member(family_id));
create policy health_ins on public.shared_health_logs for insert to authenticated
  with check (public.is_family_member(family_id));
create policy health_upd on public.shared_health_logs for update to authenticated
  using (public.is_family_member(family_id)) with check (public.is_family_member(family_id));
-- 无 delete 策略：删除走 soft delete（deleted = true）

create or replace function public.push_health_logs(rows jsonb) returns int
language plpgsql security invoker set search_path = public as $$
declare n int;
begin
  insert into shared_health_logs as t (
    id, family_id, baby_id, kind, at, temp_c, temp_site, med_kind, med_name, med_dose,
    symptoms, symptom_other, note, updated_at, deleted)
  select r.id, r.family_id, r.baby_id, r.kind, r.at, r.temp_c, r.temp_site, r.med_kind, r.med_name, r.med_dose,
         r.symptoms, r.symptom_other, r.note, r.updated_at, coalesce(r.deleted, false)
  from jsonb_to_recordset(rows) as r(
    id uuid, family_id uuid, baby_id uuid, kind text, at timestamptz,
    temp_c double precision, temp_site text, med_kind text, med_name text, med_dose text,
    symptoms text, symptom_other text, note text, updated_at timestamptz, deleted boolean)
  on conflict (id) do update set
    baby_id = excluded.baby_id,
    kind = excluded.kind,
    at = excluded.at,
    temp_c = excluded.temp_c,
    temp_site = excluded.temp_site,
    med_kind = excluded.med_kind,
    med_name = excluded.med_name,
    med_dose = excluded.med_dose,
    symptoms = excluded.symptoms,
    symptom_other = excluded.symptom_other,
    note = excluded.note,
    updated_at = excluded.updated_at,
    deleted = excluded.deleted
  where t.updated_at <= excluded.updated_at and t.family_id = excluded.family_id;
  get diagnostics n = row_count; return n;
end $$;

revoke execute on function public.push_health_logs(jsonb) from public, anon;
grant execute on function public.push_health_logs(jsonb) to authenticated;

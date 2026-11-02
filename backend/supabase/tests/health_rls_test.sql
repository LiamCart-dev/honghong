-- 0005_health：shared_health_logs RLS / push_health_logs / 软删除 / 外人隔离（本机临时库）
\set ON_ERROR_STOP 1
create temp table if not exists ctx (k text primary key, v text);
grant all on ctx to authenticated;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;

set role authenticated;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000011');
-- 若上一套测试已解散家庭，重新建一个
delete from ctx;
insert into ctx values ('fid', public.create_family('bbbbbbbb-0000-0000-0000-000000000011', '健康测', '2026-08-01', '爸爸', 'dad')::text);
insert into ctx select 'code', code from public.family_invites;

select public.push_health_logs(jsonb_build_array(jsonb_build_object(
  'id','dddddddd-0000-0000-0000-000000000001',
  'family_id',(select v from ctx where k='fid'),
  'baby_id','bbbbbbbb-0000-0000-0000-000000000011',
  'kind','temperature',
  'at','2026-11-02T08:00:00Z',
  'temp_c',37.6,
  'temp_site','armpit',
  'updated_at','2026-11-02T08:10:00Z',
  'deleted',false))) as a_push_health;

-- 外人 C
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000013');
do $$ begin
  assert (select count(*) from public.shared_health_logs) = 0, 'C 不应看到健康记录';
  begin
    perform public.push_health_logs(('[{"id":"dddddddd-0000-0000-0000-000000000009","family_id":"' || (select v from ctx where k='fid') ||
      '","baby_id":"bbbbbbbb-0000-0000-0000-000000000011","kind":"symptom","at":"2026-11-02T09:00:00Z","symptoms":"[\"cough\"]","updated_at":"2026-11-02T09:00:00Z","deleted":false}]')::jsonb);
    raise exception 'C 通过 RPC 推送健康记录竟然成功';
  exception when insufficient_privilege then null; end;
end $$;

-- 成员 B 加入后可见；旧写不覆盖、新写覆盖；软删除
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000012');
select public.join_family((select v from ctx where k='code'), '妈妈', 'mom') is not null as b_joined_health;
do $$ begin
  assert (select count(*) from public.shared_health_logs) = 1, 'B 应看到 1 条健康记录';
  assert (select temp_c from public.shared_health_logs) = 37.6, '体温应对';
  assert public.push_health_logs(('[{"id":"dddddddd-0000-0000-0000-000000000001","family_id":"' || (select v from ctx where k='fid') ||
    '","baby_id":"bbbbbbbb-0000-0000-0000-000000000011","kind":"temperature","at":"2026-11-02T08:00:00Z","temp_c":39.0,"temp_site":"armpit","updated_at":"2026-11-02T07:00:00Z","deleted":false}]')::jsonb) = 0, '旧版本不应覆盖';
  assert (select temp_c from public.shared_health_logs) = 37.6, '旧写未覆盖';
  assert public.push_health_logs(('[{"id":"dddddddd-0000-0000-0000-000000000001","family_id":"' || (select v from ctx where k='fid') ||
    '","baby_id":"bbbbbbbb-0000-0000-0000-000000000011","kind":"temperature","at":"2026-11-02T08:00:00Z","temp_c":38.2,"temp_site":"rectal","updated_at":"2026-11-02T09:00:00Z","deleted":true}]')::jsonb) = 1, '新版本应覆盖';
  assert (select deleted from public.shared_health_logs), '应为软删除';
  assert (select temp_c from public.shared_health_logs) = 38.2, '新写应覆盖体温';
end $$;

-- 匿名不能执行
set role anon;
do $$ begin
  begin
    perform public.push_health_logs('[]'::jsonb);
    raise exception 'anon 竟然能调用 push_health_logs';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select 'ALL HEALTH RLS CHECKS PASSED' as result;

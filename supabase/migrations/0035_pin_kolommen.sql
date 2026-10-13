-- 0035 PIN-kolommen afschermen (hardening stap 12, architecture 13.24). Na 0034 EN na de app van stap 12 (die leest de PIN
-- alleen nog op de server). Rollback: rollbacks/0035_rollback.sql
-- authenticated: SELECT alleen nog op de niet-geheime kolommen; INSERT/UPDATE ongewijzigd (RLS: MANAGE_SETTINGS). service_role ongewijzigd.
-- Uitgangsrechten (vooraf gecontroleerd): authenticated tabel-SELECT ja; anon geen SELECT (tabel noch kolom); service_role leest pin_hash
-- en pin_salt (nodig voor de PIN-controle op de server). anon en service_role worden niet aangeraakt.
-- Let op: een nieuwe kolom op approval_settings is daarna NIET vanzelf leesbaar voor authenticated (bewust openzetten).
begin;
do $m$
declare k text := 'auto_lock,company_id,created_at,id,is_required,method,notify_email,updated_at';
begin
if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'approval_settings'
                and policyname = 'approval_settings select')
  or (select string_agg(column_name, ',' order by column_name) from information_schema.columns
      where table_schema = 'public' and table_name = 'approval_settings')
     <> 'auto_lock,company_id,created_at,id,is_required,method,notify_email,pin_hash,pin_salt,updated_at'
  or not has_table_privilege('authenticated', 'public.approval_settings', 'SELECT')
  or not has_column_privilege('service_role', 'public.approval_settings', 'pin_hash', 'SELECT')
  or not has_column_privilege('service_role', 'public.approval_settings', 'pin_salt', 'SELECT')
  or exists (select 1 from information_schema.columns x where x.table_schema = 'public' and x.table_name = 'approval_settings'
             and has_column_privilege('anon', 'public.approval_settings', x.column_name, 'SELECT'))
then raise exception '0035 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if;

revoke select on public.approval_settings from authenticated;
execute format('grant select (%s) on public.approval_settings to authenticated', k);

if has_column_privilege('authenticated', 'public.approval_settings', 'pin_hash', 'SELECT')
  or has_column_privilege('authenticated', 'public.approval_settings', 'pin_salt', 'SELECT')
  or exists (select 1 from information_schema.columns x where x.table_schema = 'public' and x.table_name = 'approval_settings'
             and has_column_privilege('anon', 'public.approval_settings', x.column_name, 'SELECT'))
  or exists (select 1 from unnest(string_to_array(k, ',')) c
             where not has_column_privilege('authenticated', 'public.approval_settings', c, 'SELECT'))
  or not has_table_privilege('authenticated', 'public.approval_settings', 'INSERT,UPDATE')
  or not has_column_privilege('service_role', 'public.approval_settings', 'pin_hash', 'SELECT')
  or not has_column_privilege('service_role', 'public.approval_settings', 'pin_salt', 'SELECT')
then raise exception '0035 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;

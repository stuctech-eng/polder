-- Rollback 0035 PIN-kolommen. NOODMAATREGEL: maakt pin_hash/pin_salt weer leesbaar voor elke ingelogde gebruiker van het
-- restaurant (het oude lek). Alleen tijdelijk. De app van stap 12 werkt ook met de oude rechten.
-- Herstelt precies de stand vóór 0035: authenticated tabel-SELECT; anon blijft zonder SELECT (had die vóór 0035 ook niet).
begin;
do $m$
declare k text := 'auto_lock,company_id,created_at,id,is_required,method,notify_email,updated_at';
begin
if has_table_privilege('authenticated', 'public.approval_settings', 'SELECT')
  or exists (select 1 from information_schema.columns x where x.table_schema = 'public' and x.table_name = 'approval_settings'
             and has_column_privilege('anon', 'public.approval_settings', x.column_name, 'SELECT'))
  or has_column_privilege('authenticated', 'public.approval_settings', 'pin_hash', 'SELECT')
  or has_column_privilege('authenticated', 'public.approval_settings', 'pin_salt', 'SELECT')
  or exists (select 1 from unnest(string_to_array(k, ',')) c
             where not has_column_privilege('authenticated', 'public.approval_settings', c, 'SELECT'))
then raise exception '0035-rollback vooraf: 0035 niet (precies) aanwezig, niets gewijzigd'; end if;
execute format('revoke select (%s) on public.approval_settings from authenticated', k);
grant select on public.approval_settings to authenticated;
if not has_table_privilege('authenticated', 'public.approval_settings', 'SELECT')
  or exists (select 1 from information_schema.columns x where x.table_schema = 'public' and x.table_name = 'approval_settings'
             and has_column_privilege('anon', 'public.approval_settings', x.column_name, 'SELECT'))
  or (select count(*) from information_schema.column_privileges where table_schema = 'public'
      and table_name = 'approval_settings' and grantee = 'authenticated' and privilege_type = 'SELECT') <> 10
then raise exception '0035-rollback achteraf: controle mislukt'; end if;
end $m$;
commit;

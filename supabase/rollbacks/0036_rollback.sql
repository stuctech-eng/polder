-- Rollback 0036 overbodige rechten. NOODMAATREGEL: zet precies de gemeten stand van voor 0036 terug (de dode rechten van
-- authenticated, MAINTAIN, platform_log_id_seq, MAINTAIN in de standaardrechten van postgres). Verder niets.
-- Vooraf exact de stand na 0036, achteraf exact de stand ervoor; anders afgebroken zonder wijziging.
begin;
do $m$
declare f text; v text := $v$select md5(string_agg(r, '|' order by r collate "C")) from (
select c.relname || ':' || x.grantee::regrole || ':' || x.privilege_type r from pg_class c, aclexplode(c.relacl) x
where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','S') and c.relname not like '\_%'
and x.grantee::regrole::text in ('anon','authenticated','service_role')
union all
select c.relname || '.' || a.attname || ':' || x.grantee::regrole || ':' || x.privilege_type
from pg_class c, pg_attribute a, aclexplode(a.attacl) x
where a.attrelid = c.oid and c.relnamespace = 'public'::regnamespace and c.relname not like '\_%'
and x.grantee::regrole::text in ('anon','authenticated','service_role')
union all
select d.defaclrole::regrole || ':' || d.defaclobjtype::text || ':' || d.defaclnamespace::regnamespace || ':'
|| x.grantee::regrole || ':' || x.privilege_type from pg_default_acl d, aclexplode(d.defaclacl) x
where d.defaclnamespace in (0, 'public'::regnamespace)) s$v$;
begin
execute v into f;
if f is distinct from 'afd46a8208fb2d9892202d4ce71b912e' then
  raise exception '0036-rollback vooraf: 0036 niet (precies) aanwezig (%), niets gewijzigd', f; end if;
grant delete, maintain on public.approval_settings, public.approvals, public.companies, public.configurations,
 public.invoices, public.workflow_rules to authenticated;
grant update, delete, maintain on public.company_codes, public.cost_centers, public.daily_closings, public.departments,
 public.documents, public.payments, public.projects, public.receipt_lines to authenticated;
grant select, insert, update, delete, maintain on public.contacts, public.integration_plugins, public.notifications
 to authenticated;
grant maintain on public.activity_log, public.audit_log, public.domain_events, public.invoice_lines, public.open_tabs,
 public.receipts, public.restaurants, public.users to authenticated;
grant select, usage on sequence public.platform_log_id_seq to authenticated;
alter default privileges for role postgres in schema public grant maintain on tables to anon, authenticated;
execute v into f;
if f is distinct from '469416b6636280c00f84839ce260ce38' then
  raise exception '0036-rollback achteraf: mislukt (%), niets gewijzigd', f; end if;
end $m$;
commit;

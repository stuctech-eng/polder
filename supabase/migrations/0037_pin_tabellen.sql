-- 0037 PIN-pogingen: tabellen (stap 14a, deel 1 van 5; 0038-0041 functies en wachten). Na 0036. Rollback: rollbacks/0037_rollback.sql
-- Tabellen zonder enig recht voor anon/authenticated/service_role: alleen de functies en wachten (eigenaar postgres) gebruiken ze.
-- Bestaande objecten worden niet aangeraakt (controleblok prod-pin14-checks.sql: md5 voor = na).
begin;
do $m$ begin
if to_regclass('public.pin_pogingen') is not null or to_regclass('public.pin_reserveringen') is not null
  or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'pin\_%' or proname like '%pin\_wacht'))
  or not exists (select 1 from pg_trigger where tgname = 'receipts_guard') or not exists (select 1 from pg_trigger where tgname = 'approvals_guard')
then raise exception '0037 vooraf: uitgangsstand wijkt af (PIN-objecten bestaan al of wachten ontbreken), niets gewijzigd'; end if;
end $m$;

create table public.pin_pogingen (company_id uuid primary key references public.companies(id) on delete cascade,
  generatie bigint not null default 1, geblokkeerd_tot timestamptz);
create table public.pin_reserveringen (id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  receipt_id uuid not null references public.receipts(id) on delete cascade, generatie bigint not null,
  gemaakt_op timestamptz not null, status text not null default 'lopend' check (status in ('lopend','fout','juist','verlopen')),
  afgerond_op timestamptz, verbruikt_op timestamptz);
create index pin_reserveringen_telling on public.pin_reserveringen (company_id, generatie, gemaakt_op);
alter table public.pin_pogingen enable row level security;
alter table public.pin_reserveringen enable row level security;
revoke all on public.pin_pogingen, public.pin_reserveringen from public, anon, authenticated, service_role;

do $m$ begin
if exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'public'::regnamespace
           and c.relname in ('pin_pogingen', 'pin_reserveringen') and x.grantee <> c.relowner)
  or (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('pin_pogingen', 'pin_reserveringen')
      and relkind = 'r' and relrowsecurity and pg_get_userbyid(relowner) = 'postgres') <> 2
  or exists (select 1 from pg_policies where tablename in ('pin_pogingen', 'pin_reserveringen'))
then raise exception '0037 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;

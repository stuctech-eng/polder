-- ============================================================
-- POLDER — Security Hardening: TESTHARNAS (alleen staging / lokale testdatabase!)
-- ============================================================
-- Draait ALLEEN als public._polder_staging_marker bestaat (aangemaakt door staging-seed.sql).
-- Alle testacties worden binnen een subtransactie uitgevoerd en ALTIJD teruggedraaid:
-- de testdata verandert niet. Voorbeeld:
--
--   select * from hardening_test.run(0);          -- huidige (ongehardende) toestand
--   select * from hardening_test.run(3);          -- verwachting na hardening-stap 3
--   select * from hardening_test.summary(3);      -- samenvatting
--   select * from hardening_test.run(11) where result <> 'PASS';   -- alleen afwijkingen
--
-- Semantiek per case:
--   kind 'select' : "toegestaan" = de query geeft ≥ 1 rij
--   kind 'dml'    : "toegestaan" = geen fout én ≥ 1 rij geraakt (RLS filtert stil naar 0 rijen)
--   kind 'check'  : de query geeft een boolean terug (true = "toegestaan")
-- Verwachting: expect_now (nu) of expect_after (vanaf hardening-stap `step`).
-- expect_after = NULL betekent: open beslispunt (resultaat 'OPEN', geen pass/fail).
-- ============================================================
create schema if not exists hardening_test;

drop table if exists hardening_test.cases cascade;
create table hardening_test.cases (
  id text primary key,
  category text not null,
  title text not null,
  as_user text not null,          -- e-mail van testgebruiker, of 'service_role' / 'postgres' / 'anon' / 'nosub' (auth.uid() NULL) / 'uid:<uuid>'
  kind text not null check (kind in ('select','dml','check')),
  sql text not null,
  expect_now boolean not null,
  expect_after boolean,           -- NULL = open beslispunt
  step int not null default 0,    -- hardening-stap waarin expect_after gaat gelden (0 = verandert nooit)
  note text,
  setup text                      -- optioneel: SQL als postgres vóór de test (in dezelfde teruggedraaide subtransactie), bv. FK-ballast opruimen
);

drop table if exists hardening_test.permission_baseline cascade;
create table hardening_test.permission_baseline (role text, permission text, allowed boolean, primary key (role, permission));
-- Exacte kopie van PERMISSIONS in lib/user-management/role-helpers.ts (gegenereerd; zie permission-baseline.json)
insert into hardening_test.permission_baseline (role, permission, allowed) values
  ('owner','VIEW_DASHBOARD',true),
  ('manager','VIEW_DASHBOARD',true),
  ('administratie','VIEW_DASHBOARD',true),
  ('bediening','VIEW_DASHBOARD',false),
  ('keuken','VIEW_DASHBOARD',false),
  ('owner','VIEW_REVENUE',true),
  ('manager','VIEW_REVENUE',true),
  ('administratie','VIEW_REVENUE',true),
  ('bediening','VIEW_REVENUE',false),
  ('keuken','VIEW_REVENUE',false),
  ('owner','MANAGE_COMPANIES',true),
  ('manager','MANAGE_COMPANIES',false),
  ('administratie','MANAGE_COMPANIES',true),
  ('bediening','MANAGE_COMPANIES',false),
  ('keuken','MANAGE_COMPANIES',false),
  ('owner','MANAGE_OPEN_TABS',true),
  ('manager','MANAGE_OPEN_TABS',true),
  ('administratie','MANAGE_OPEN_TABS',true),
  ('bediening','MANAGE_OPEN_TABS',true),
  ('keuken','MANAGE_OPEN_TABS',false),
  ('owner','MANAGE_RECEIPTS',true),
  ('manager','MANAGE_RECEIPTS',true),
  ('administratie','MANAGE_RECEIPTS',true),
  ('bediening','MANAGE_RECEIPTS',true),
  ('keuken','MANAGE_RECEIPTS',false),
  ('owner','APPROVE_RECEIPTS',true),
  ('manager','APPROVE_RECEIPTS',true),
  ('administratie','APPROVE_RECEIPTS',false),
  ('bediening','APPROVE_RECEIPTS',false),
  ('keuken','APPROVE_RECEIPTS',false),
  ('owner','MANAGE_INVOICES',true),
  ('manager','MANAGE_INVOICES',false),
  ('administratie','MANAGE_INVOICES',true),
  ('bediening','MANAGE_INVOICES',false),
  ('keuken','MANAGE_INVOICES',false),
  ('owner','VIEW_DAILY_CLOSING',true),
  ('manager','VIEW_DAILY_CLOSING',true),
  ('administratie','VIEW_DAILY_CLOSING',true),
  ('bediening','VIEW_DAILY_CLOSING',false),
  ('keuken','VIEW_DAILY_CLOSING',false),
  ('owner','EXECUTE_DAILY_CLOSING',true),
  ('manager','EXECUTE_DAILY_CLOSING',true),
  ('administratie','EXECUTE_DAILY_CLOSING',false),
  ('bediening','EXECUTE_DAILY_CLOSING',false),
  ('keuken','EXECUTE_DAILY_CLOSING',false),
  ('owner','MANAGE_TEAM',true),
  ('manager','MANAGE_TEAM',false),
  ('administratie','MANAGE_TEAM',false),
  ('bediening','MANAGE_TEAM',false),
  ('keuken','MANAGE_TEAM',false),
  ('owner','MANAGE_SETTINGS',true),
  ('manager','MANAGE_SETTINGS',false),
  ('administratie','MANAGE_SETTINGS',true),
  ('bediening','MANAGE_SETTINGS',false),
  ('keuken','MANAGE_SETTINGS',false);

-- hulpfunctie voor cases die een mislukkende opdracht (bv. TRUNCATE) moeten toetsen: true = gelukt, false = geweigerd
create or replace function hardening_test.attempt(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return true; exception when others then return false; end $$;

-- hulpfunctie voor cases die een weigering met een bepaalde reden moeten bewijzen: true = de opdracht faalde EN de foutmelding bevat p_msg.
-- Een mislukte testopzet (andere fout) telt dus niet als geslaagde weigering.
create or replace function hardening_test.refused_with(p_sql text, p_msg text) returns boolean
language plpgsql as $$
begin execute p_sql; return false; exception when others then return position(p_msg in sqlerrm) > 0; end $$;
grant usage on schema hardening_test to public;
grant execute on function hardening_test.refused_with(text, text) to public;

create or replace function hardening_test.run(p_step int default 0)
returns table (id text, category text, title text, as_user text, expected text, actual text, result text, detail text)
language plpgsql
as $fn$
declare
  c record;
  v_uid uuid; v_role text; v_n bigint; v_allowed boolean; v_err text; v_exp boolean; v_claims text;
begin
  if to_regclass('public._polder_staging_marker') is null then
    raise exception 'GEWEIGERD: geen staging-marker gevonden. Dit harnas draait nooit op productie.';
  end if;

  for c in select * from hardening_test.cases order by category, id loop
    v_allowed := null; v_err := null; v_n := null; v_uid := null;
    if c.as_user like 'uid:%' then
      v_uid := substr(c.as_user, 5)::uuid;          -- willekeurige uid (ook niet-bestaande) als geldig JWT-subject
    elsif c.as_user not in ('service_role','postgres','anon','nosub') then
      select u.id into v_uid from auth.users u where u.email = c.as_user;
      if v_uid is null then
        id := c.id; category := c.category; title := c.title; as_user := c.as_user;
        expected := '-'; actual := '-'; result := 'FOUT'; detail := 'testgebruiker bestaat niet (seed gedraaid?)';
        return next; continue;
      end if;
    end if;

    begin
      if c.setup is not null then execute c.setup; end if;
      set constraints all immediate;     -- uitgestelde (deferred) constraint-triggers meteen toetsen: de subtransactie wordt altijd teruggedraaid
      if c.as_user = 'service_role' then
        v_claims := '{"role":"service_role"}';
        perform set_config('request.jwt.claims', v_claims, true);
        perform set_config('request.jwt.claim.sub', '', true);
        set local role service_role;
      elsif c.as_user = 'anon' then
        perform set_config('request.jwt.claims', '{"role":"anon"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        set local role anon;
      elsif c.as_user = 'nosub' then                -- ingelogde rol maar zonder subject: auth.uid() IS NULL
        perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        set local role authenticated;
      elsif c.as_user <> 'postgres' then
        v_claims := json_build_object('sub', v_uid, 'role', 'authenticated')::text;
        perform set_config('request.jwt.claims', v_claims, true);
        perform set_config('request.jwt.claim.sub', v_uid::text, true);
        perform set_config('request.jwt.claim.role', 'authenticated', true);
        set local role authenticated;
      end if;

      if c.kind = 'select' then
        execute 'select count(*) from (' || c.sql || ') q' into v_n;
        v_allowed := v_n > 0;
      elsif c.kind = 'check' then
        execute c.sql into v_allowed;
      else
        execute c.sql;
        get diagnostics v_n = row_count;
        v_allowed := v_n > 0;
      end if;
      raise exception using errcode = 'P0999', message = 'rollback';   -- ALTIJD terugdraaien
    exception
      when sqlstate 'P0999' then null;
      when others then v_allowed := false; v_err := sqlerrm;
    end;

    v_exp := case when c.step > 0 and p_step >= c.step then c.expect_after else c.expect_now end;
    id := c.id; category := c.category; title := c.title; as_user := c.as_user;
    expected := case when v_exp is null then 'OPEN' when v_exp then 'toegestaan' else 'geweigerd' end;
    actual := case when v_allowed then 'toegestaan' else 'geweigerd' end;
    result := case when v_exp is null then 'OPEN' when v_allowed = v_exp then 'PASS' else 'FAIL' end;
    detail := coalesce(v_err, case when c.kind <> 'check' then 'rijen=' || coalesce(v_n::text,'0') else '' end);
    return next;
  end loop;
end
$fn$;

create or replace function hardening_test.summary(p_step int default 0)
returns table (category text, totaal bigint, pass bigint, fail bigint, open_ bigint, fout bigint)
language sql as $$
  select r.category, count(*), count(*) filter (where result='PASS'), count(*) filter (where result='FAIL'),
         count(*) filter (where result='OPEN'), count(*) filter (where result='FOUT')
  from hardening_test.run(p_step) r group by r.category
  union all
  select 'TOTAAL', count(*), count(*) filter (where result='PASS'), count(*) filter (where result='FAIL'),
         count(*) filter (where result='OPEN'), count(*) filter (where result='FOUT')
  from hardening_test.run(p_step) r
  order by 1;
$$;

-- Bekende zwaktes van vandaag = cases waarvan de verwachting later omslaat
create or replace view hardening_test.known_weaknesses as
select id, category, title, as_user, step as opgelost_in_stap, note
from hardening_test.cases where expect_now = true and expect_after is false order by step, id;

-- ============================================================
-- Fase 1 (migratie 0024): bewijs dat een GEDEACTIVEERDE gebruiker op de 15 tenant-tabellen niets kan,
-- terwijl een ACTIEVE gebruiker met EXACT dezelfde opdracht wel effect heeft. Per tabel en bewerking:
--   1. verse doelrij (+ verse ouders) als postgres, met bekend id; rij bestaat aantoonbaar
--   2. actieve gebruiker voert de opdracht uit -> precies 1 rij en het effect wordt nagemeten
--   3. teruggedraaid; rij exact gelijk aan stap 1 (md5 van de hele rij)
--   4. gedeactiveerde gebruiker voert DEZELFDE opdracht uit (zelfde SQL, zelfde id, zelfde WHERE)
--   5. rij exact gelijk aan stap 1
-- opzet_ok  = 1, 2, 3 en 5 kloppen (een fout in de test zelf geeft dus nooit een vals PASS)
-- geweigerd = opzet_ok én stap 4 weigert: 0 rijen (SELECT/UPDATE/DELETE) of RLS-fout (INSERT)
-- Alles in subtransacties die altijd worden teruggedraaid.
-- ============================================================
drop table if exists hardening_test.dml_def cascade;
create table hardening_test.dml_def (tbl text primary key, setup text, ins text, upd text, gewijzigd text);
-- tokens: {R} doelrij, {N} nieuw id, {FC}/{FC2} verse bedrijven, {FI} verse factuur, {RA} restaurant A
insert into hardening_test.dml_def values
 ('companies',
  'insert into public.companies (id, restaurant_id, name) values ({R},{RA},''proef'')',
  'insert into public.companies (id, restaurant_id, name) values ({N},{RA},''proef-n'')',
  'update public.companies set name = ''proef-gewijzigd'' where id = {R}',
  'select name = ''proef-gewijzigd'' from public.companies where id = {R}'),
 ('invoices',
  'insert into public.invoices (id, restaurant_id, company_id, invoice_number, status) values ({R},{RA},{FC},''P-1'',''draft'')',
  'insert into public.invoices (id, restaurant_id, company_id, invoice_number, status) values ({N},{RA},{FC},''P-2'',''draft'')',
  'update public.invoices set invoice_number = ''proef-gewijzigd'' where id = {R}',
  'select invoice_number = ''proef-gewijzigd'' from public.invoices where id = {R}'),
 ('documents',
  'insert into public.documents (id, restaurant_id, type, related_table, related_id, storage_path) values ({R},{RA},''report_export'',''invoices'',{FI},''a/proef.pdf'')',
  'insert into public.documents (id, restaurant_id, type, related_table, related_id, storage_path) values ({N},{RA},''report_export'',''invoices'',{FI},''a/proef-n.pdf'')',
  'update public.documents set storage_path = ''proef-gewijzigd'' where id = {R}',
  'select storage_path = ''proef-gewijzigd'' from public.documents where id = {R}'),
 ('workflow_rules',
  'insert into public.workflow_rules (id, restaurant_id, company_id, invoice_frequency, requires_approval) values ({R},{RA},{FC},''weekly'',false)',
  'insert into public.workflow_rules (id, restaurant_id, company_id, invoice_frequency, requires_approval) values ({N},{RA},{FC2},''weekly'',false)',
  'update public.workflow_rules set invoice_frequency = ''monthly'' where id = {R}',
  'select invoice_frequency = ''monthly'' from public.workflow_rules where id = {R}'),
 ('configurations',
  'insert into public.configurations (id, restaurant_id, company_id, key, value) values ({R},{RA},{FC},''proef'',''{}'')',
  'insert into public.configurations (id, restaurant_id, company_id, key, value) values ({N},{RA},{FC2},''proef'',''{}'')',
  'update public.configurations set value = ''{"proef":1}'' where id = {R}',
  'select value = ''{"proef":1}'' from public.configurations where id = {R}'),
 ('notifications',
  'insert into public.notifications (id, restaurant_id, type, trigger_event) values ({R},{RA},''email'',''proef'')',
  'insert into public.notifications (id, restaurant_id, type, trigger_event) values ({N},{RA},''email'',''proef-n'')',
  'update public.notifications set trigger_event = ''proef-gewijzigd'' where id = {R}',
  'select trigger_event = ''proef-gewijzigd'' from public.notifications where id = {R}'),
 ('integration_plugins',
  'insert into public.integration_plugins (id, restaurant_id, plugin_type, plugin_name, plugin_version, min_core_version) values ({R},{RA},''pos'',''proef'',''1'',''1'')',
  'insert into public.integration_plugins (id, restaurant_id, plugin_type, plugin_name, plugin_version, min_core_version) values ({N},{RA},''pos'',''proef-n'',''1'',''1'')',
  'update public.integration_plugins set plugin_name = ''proef-gewijzigd'' where id = {R}',
  'select plugin_name = ''proef-gewijzigd'' from public.integration_plugins where id = {R}'),
 ('contacts',
  'insert into public.contacts (id, company_id, full_name) values ({R},{FC},''proef'')',
  'insert into public.contacts (id, company_id, full_name) values ({N},{FC},''proef-n'')',
  'update public.contacts set full_name = ''proef-gewijzigd'' where id = {R}',
  'select full_name = ''proef-gewijzigd'' from public.contacts where id = {R}'),
 ('departments',
  'insert into public.departments (id, company_id, name) values ({R},{FC},''proef'')',
  'insert into public.departments (id, company_id, name) values ({N},{FC},''proef-n'')',
  'update public.departments set name = ''proef-gewijzigd'' where id = {R}',
  'select name = ''proef-gewijzigd'' from public.departments where id = {R}'),
 ('cost_centers',
  'insert into public.cost_centers (id, company_id, name) values ({R},{FC},''proef'')',
  'insert into public.cost_centers (id, company_id, name) values ({N},{FC},''proef-n'')',
  'update public.cost_centers set name = ''proef-gewijzigd'' where id = {R}',
  'select name = ''proef-gewijzigd'' from public.cost_centers where id = {R}'),
 ('projects',
  'insert into public.projects (id, company_id, name) values ({R},{FC},''proef'')',
  'insert into public.projects (id, company_id, name) values ({N},{FC},''proef-n'')',
  'update public.projects set name = ''proef-gewijzigd'' where id = {R}',
  'select name = ''proef-gewijzigd'' from public.projects where id = {R}'),
 ('company_codes',
  'insert into public.company_codes (id, company_id, type, code) values ({R},{FC},''routecode'',''P1'')',
  'insert into public.company_codes (id, company_id, type, code) values ({N},{FC},''routecode'',''P2'')',
  'update public.company_codes set code = ''proef-gewijzigd'' where id = {R}',
  'select code = ''proef-gewijzigd'' from public.company_codes where id = {R}'),
 ('approval_settings',
  'insert into public.approval_settings (id, company_id) values ({R},{FC})',
  'insert into public.approval_settings (id, company_id) values ({N},{FC2})',
  'update public.approval_settings set method = ''email'' where id = {R}',
  'select method = ''email'' from public.approval_settings where id = {R}'),
 ('invoice_lines',
  'insert into public.invoice_lines (id, invoice_id, description, amount) values ({R},{FI},''proef'',1)',
  'insert into public.invoice_lines (id, invoice_id, description, amount) values ({N},{FI},''proef-n'',1)',
  'update public.invoice_lines set description = ''proef-gewijzigd'' where id = {R}',
  'select description = ''proef-gewijzigd'' from public.invoice_lines where id = {R}'),
 ('payments',
  'insert into public.payments (id, invoice_id, amount) values ({R},{FI},1)',
  'insert into public.payments (id, invoice_id, amount) values ({N},{FI},1)',
  'update public.payments set amount = 99 where id = {R}',
  'select amount = 99 from public.payments where id = {R}');

create or replace function hardening_test.dml_vul(p_sql text, ids jsonb) returns text language plpgsql immutable as $$
declare k text; s text := p_sql;
begin
  for k in select jsonb_object_keys(ids) loop s := replace(s, '{' || k || '}', quote_literal(ids->>k)); end loop;
  return s;
end $$;

-- voert p_sql uit als p_email (null = postgres); altijd teruggedraaid; geeft rijen, fout en nagemeten effect
create or replace function hardening_test.dml_probeer(p_email text, p_sql text, p_select boolean, p_check text,
  out n bigint, out fout text, out effect boolean) language plpgsql as $$
declare v uuid;
begin
  n := null; fout := null; effect := null;
  begin
    if p_email is not null then
      select id into v from auth.users where email = p_email;
      if v is null then raise exception 'testgebruiker % bestaat niet', p_email; end if;
      perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v::text, true);
      execute 'set local role authenticated';
    end if;
    if p_select then execute 'select count(*) from (' || p_sql || ') q' into n;
    else execute p_sql; get diagnostics n = row_count; end if;
    execute 'set local role postgres';
    if p_check is not null then execute p_check into effect; effect := coalesce(effect, false); end if;
    raise exception using errcode = 'P0999';
  exception
    when sqlstate 'P0999' then null;
    when others then fout := sqlerrm; n := 0;
  end;
end $$;

create or replace function hardening_test.dml_rij(p_tbl text, p_id uuid) returns text language plpgsql as $$
declare h text;
begin
  execute format('select md5(t::text) from public.%I t where id = %L', p_tbl, p_id) into h;
  return coalesce(h, '(weg)');
end $$;

-- Fase 2 (0025): met p_restaurant_uit = true wordt restaurant A vlak vóór stap 4 uitgezet en voert p_weiger (standaard de
-- gedeactiveerde gebruiker; voor fase 2 de actieve owner van A) de opdracht uit. Bestaat de kolom is_active nog niet
-- (vóór 0025), dan blijft A aan en heeft de opdracht dus effect (= FAIL om de juiste reden).
drop function if exists hardening_test.inactief_dml(text, text, text);
-- zet restaurant A uit (alleen als de kolom bestaat, dus vanaf 0025); altijd binnen een teruggedraaide (sub)transactie gebruiken
create or replace function hardening_test.restaurant_a_uit() returns void language plpgsql as $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'restaurants' and column_name = 'is_active') then
    execute 'update public.restaurants set is_active = false where id = ''a0000000-0000-0000-0000-000000000001''';
  end if;
end $$;
grant execute on function hardening_test.restaurant_a_uit() to public;
create or replace function hardening_test.restaurant_a_aan() returns void language plpgsql as $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'restaurants' and column_name = 'is_active') then
    execute 'update public.restaurants set is_active = true where id = ''a0000000-0000-0000-0000-000000000001''';
  end if;
end $$;
grant execute on function hardening_test.restaurant_a_aan() to public;

create or replace function hardening_test.inactief_dml(p_tbl text, p_op text,
  p_actief text default 'a.owner@staging.test', p_weiger text default 'a.inactive@staging.test',
  p_restaurant_uit boolean default false, out opzet_ok boolean, out geweigerd boolean, out detail text)
language plpgsql as $fn$
declare
  d record; ids jsonb; s text; a record; i record; h0 text; h1 text; h2 text;
begin
  opzet_ok := false; geweigerd := false;
  select * into d from hardening_test.dml_def where tbl = p_tbl;
  if d.tbl is null or p_op not in ('SELECT','INSERT','UPDATE','DELETE') then detail := 'onbekende tabel/bewerking'; return; end if;
  begin
    ids := jsonb_build_object('R', gen_random_uuid(), 'N', gen_random_uuid(), 'FC', gen_random_uuid(), 'FC2', gen_random_uuid(),
                              'FI', gen_random_uuid(), 'RA', 'a0000000-0000-0000-0000-000000000001');
    execute hardening_test.dml_vul('insert into public.companies (id, restaurant_id, name) values ({FC},{RA},''proef-bedrijf''), ({FC2},{RA},''proef-bedrijf-2'')', ids);
    execute hardening_test.dml_vul('insert into public.invoices (id, restaurant_id, company_id, invoice_number, status) values ({FI},{RA},{FC},''P-0'',''draft'')', ids);
    execute hardening_test.dml_vul(d.setup, ids);
    h0 := hardening_test.dml_rij(p_tbl, (ids->>'R')::uuid);
    s := case p_op when 'SELECT' then hardening_test.dml_vul('select 1 from public.' || p_tbl || ' where id = {R}', ids)
                   when 'INSERT' then hardening_test.dml_vul(d.ins, ids)
                   when 'UPDATE' then hardening_test.dml_vul(d.upd, ids)
                   else hardening_test.dml_vul('delete from public.' || p_tbl || ' where id = {R}', ids) end;
    select * into a from hardening_test.dml_probeer(p_actief, s, p_op = 'SELECT',
      case p_op when 'UPDATE' then hardening_test.dml_vul(d.gewijzigd, ids)
                when 'DELETE' then hardening_test.dml_vul('select not exists (select 1 from public.' || p_tbl || ' where id = {R})', ids)
                when 'INSERT' then hardening_test.dml_vul('select exists (select 1 from public.' || p_tbl || ' where id = {N})', ids)
                else null end);
    h1 := hardening_test.dml_rij(p_tbl, (ids->>'R')::uuid);
    if p_restaurant_uit then perform hardening_test.restaurant_a_uit(); end if;
    select * into i from hardening_test.dml_probeer(p_weiger, s, p_op = 'SELECT', null);
    h2 := hardening_test.dml_rij(p_tbl, (ids->>'R')::uuid);
    opzet_ok := h0 <> '(weg)' and a.fout is null and a.n = 1 and coalesce(a.effect, true) and h1 = h0 and h2 = h0;
    geweigerd := opzet_ok and case when p_op = 'INSERT' then coalesce(i.fout, '') like '%row-level security%'
                                   else i.fout is null and i.n = 0 end;
    detail := 'actief: ' || coalesce(a.fout, 'rijen=' || a.n) || ' | gedeactiveerd: ' || coalesce(i.fout, 'rijen=' || i.n);
    raise exception using errcode = 'P0999';
  exception when sqlstate 'P0999' then null;
  end;
end
$fn$;

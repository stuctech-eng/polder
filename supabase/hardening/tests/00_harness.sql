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

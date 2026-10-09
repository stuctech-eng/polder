-- ============================================================
-- Migratie 0023 — PLAN 7b: afgewezen bon niet factureren (databasedeel)
-- Vereist 0021 (open_tabs_guard) en 0022 (approvals_guard-aanscherping). Geen data wordt gewijzigd.
--
--  Eén toevoeging aan open_tabs_guard(), uitsluitend voor de overgang closed -> invoiced:
--  de overgang wordt geweigerd als de rekening een afgewezen bon heeft die nog niet opnieuw is goedgekeurd.
--  Definitie van "afgewezen bon": een goedkeuring 'rejected' bestaat, er is geen goedkeuring 'approved', en de
--  bonstatus is niet 'approved' of 'locked'. Geldt voor iedereen, ook service_role en postgres (geen bypass).
--
--  LET OP — dit is GEEN volledige factuurbescherming:
--   * een factuur en factuurregels kunnen tot Step 8 (invoice_lines-guard) nog los worden aangemaakt;
--   * de blokkade voor bonnen die voor het eerst op goedkeuring wachten (pending_approval) zit alleen in de app.
--  Rollback: supabase/rollbacks/0023_rollback.sql
-- ============================================================
begin;

-- PREFLIGHT 0022: approvals_guard() moet exact de versie van migratie 0022 zijn (fingerprint van de functietekst, zelfde methode
-- als hieronder), met de verwachte eigenschappen en zonder uitvoerrechten voor anderen dan de eigenaar. Een tekstfragment is onvoldoende.
do $$
declare v_hash text; v_secdef boolean; v_config text[]; v_lang text; v_ret text; v_vol "char";
begin
  if to_regprocedure('public.approvals_guard()') is null then
    raise exception 'Preflight 0023: approvals_guard() ontbreekt: draai 0021 en 0022 eerst. Niets gewijzigd.';
  end if;
  select md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))), p.prosecdef, p.proconfig, l.lanname, p.prorettype::regtype::text, p.provolatile
    into v_hash, v_secdef, v_config, v_lang, v_ret, v_vol
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = 'public.approvals_guard()'::regprocedure;
  -- toegestaan zijn uitsluitend twee bekende versies van migratie 0022:
  --   3320a9525bbc54bdd29516a459fc6a61 = zoals in het bestand (met commentaar)
  --   d84e5483f3bad1bcb48aa443a2e16644 = dezelfde functie zonder de --commentaren (zo staat hij in productie; aangetoond: commentaar-gestript bestand geeft deze fingerprint)
  if v_hash not in ('3320a9525bbc54bdd29516a459fc6a61', 'd84e5483f3bad1bcb48aa443a2e16644') then
    raise exception 'Preflight 0023: approvals_guard() is niet exact de versie van migratie 0022 (gevonden fingerprint %). Niets gewijzigd.', v_hash;
  end if;
  if v_secdef is distinct from false or v_config is distinct from array['search_path=public, pg_temp']
     or v_lang <> 'plpgsql' or v_ret <> 'trigger' or v_vol <> 'v' then
    raise exception 'Preflight 0023: approvals_guard() heeft afwijkende eigenschappen. Niets gewijzigd.';
  end if;
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid = 'public.approvals_guard()'::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner) then
    raise exception 'Preflight 0023: approvals_guard() heeft afwijkende uitvoerrechten. Niets gewijzigd.';
  end if;
end $$;

-- PREFLIGHT: de migratie gaat alleen door als open_tabs_guard() een van de twee bekende 0021-versies is (of, bij herhaling, al de versie van 0023).
-- Elke afwijking breekt af VOOR de functie wordt overschreven en voor elke andere wijziging.
do $$
declare
  v_hash text; v_secdef boolean; v_config text[]; v_lang text; v_ret text; v_vol "char";
  v_trig_count int; v_trig_def text; v_t record; v_fn_trigs int;
begin
  -- 1. de functie moet bestaan en exact de verwachte versie zijn (versie uit 0021, of bij herhaling de versie van 0023)
  if to_regprocedure('public.open_tabs_guard()') is null then
    raise exception 'Preflight 0023: open_tabs_guard() ontbreekt (migratie 0021 niet uitgevoerd?). Niets gewijzigd.';
  end if;
  select md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))), p.prosecdef, p.proconfig, l.lanname, p.prorettype::regtype::text, p.provolatile
    into v_hash, v_secdef, v_config, v_lang, v_ret, v_vol
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = 'public.open_tabs_guard()'::regprocedure;
  -- herkenning: md5 van de functietekst met alle witruimte samengevoegd (CRLF/inspringing maken geen verschil; elke andere wijziging wel)
  -- toegestaan zijn uitsluitend deze vier bekende versies (twee voor 0021, twee voor 0023; per versie met en zonder --commentaren):
  --   5e61b6f591159e6ad958a35ca3a1ee08 = 0021 zoals in het bestand
  --   dc970c3a71212b9b27352ae989d437b1 = 0021 zonder commentaar (zo staat hij in productie)
  --   fb9257a37816d3de6775d982135110b2 = 0023 zoals in dit bestand (bij herhaling)
  --   4e5b902991d05e76167ae7581c382636 = 0023 zonder commentaar (bij herhaling, als de SQL-editor of een kopie het commentaar weglaat)
  if v_hash not in ('5e61b6f591159e6ad958a35ca3a1ee08', 'dc970c3a71212b9b27352ae989d437b1', 'fb9257a37816d3de6775d982135110b2', '4e5b902991d05e76167ae7581c382636') then
    raise exception 'Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud (gevonden fingerprint %). Niets gewijzigd.', v_hash;
  end if;
  -- 2. de eigenschappen van de functie moeten kloppen (SECURITY INVOKER, vaste search_path, plpgsql, trigger-functie, VOLATILE)
  if v_secdef is distinct from false or v_config is distinct from array['search_path=public, pg_temp']
     or v_lang <> 'plpgsql' or v_ret <> 'trigger' or v_vol <> 'v' then
    raise exception 'Preflight 0023: open_tabs_guard() heeft afwijkende eigenschappen (security definer, search_path, taal of volatiliteit). Niets gewijzigd.';
  end if;
  -- 3. de rechten moeten kloppen: niemand mag de functie rechtstreeks uitvoeren.
  --    (a) ACL zelf (pg_proc.proacl; bij NULL de standaard-ACL, waarin PUBLIC EXECUTE heeft): EXECUTE voor iedere grantee behalve de eigenaar (PUBLIC of welke rol dan ook).
  --    (b) daarnaast effectieve rechten van die drie rollen (ook via lidmaatschap van een andere rol). Alleen bestaande rollen worden bekeken.
  if exists (select 1
               from pg_proc p
              cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid = 'public.open_tabs_guard()'::regprocedure
                and a.privilege_type = 'EXECUTE'
                and a.grantee <> p.proowner)   -- iedere andere grantee: 0 = PUBLIC, of welke rol dan ook (alleen de eigenaar mag EXECUTE hebben)
     or exists (select 1 from pg_roles r
                 where r.rolname in ('anon', 'authenticated', 'service_role')
                   and has_function_privilege(r.oid, 'public.open_tabs_guard()'::regprocedure, 'EXECUTE')) then
    raise exception 'Preflight 0023: open_tabs_guard() heeft afwijkende uitvoerrechten. Niets gewijzigd.';
  end if;
  -- 4. de trigger, rechtstreeks via de catalogus: precies één trigger met deze naam, en die staat op public.open_tabs,
  --    roept public.open_tabs_guard() aan, is BEFORE + FOR EACH ROW + INSERT/UPDATE/DELETE (tgtype 31), is ingeschakeld (O),
  --    heeft geen argumenten, geen WHEN-voorwaarde, geen kolomlijst (UPDATE OF) en is geen constraint-trigger.
  select count(*) into v_trig_count from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard';
  if v_trig_count <> 1 then
    raise exception '%: verwacht precies één trigger open_tabs_guard, gevonden %. Niets gewijzigd.', 'Preflight 0023', v_trig_count;
  end if;
  select t.tgrelid, t.tgfoid, t.tgtype, t.tgenabled, t.tgnargs, (t.tgqual is not null) as has_when, (t.tgattr::text <> '') as has_cols, t.tgconstraint
    into v_t
    from pg_trigger t where not t.tgisinternal and t.tgname = 'open_tabs_guard';
  select count(*) into v_fn_trigs from pg_trigger where not tgisinternal and tgfoid = 'public.open_tabs_guard()'::regprocedure;
  if v_t.tgrelid is distinct from 'public.open_tabs'::regclass
     or v_t.tgfoid is distinct from 'public.open_tabs_guard()'::regprocedure::oid
     or v_t.tgtype <> 31 or v_t.tgenabled <> 'O' or v_t.tgnargs <> 0
     or v_t.has_when or v_t.has_cols or v_t.tgconstraint <> 0 or v_fn_trigs <> 1 then
    raise exception '%: trigger open_tabs_guard staat niet aan of heeft een afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde). Niets gewijzigd.', 'Preflight 0023';
  end if;
  select pg_get_triggerdef(oid) into v_trig_def from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard';
  if v_trig_def <> 'CREATE TRIGGER open_tabs_guard BEFORE INSERT OR DELETE OR UPDATE ON public.open_tabs FOR EACH ROW EXECUTE FUNCTION open_tabs_guard()' then
    raise exception '%: trigger open_tabs_guard heeft een afwijkende definitie. Niets gewijzigd.', 'Preflight 0023';
  end if;
end $$;

create or replace function public.open_tabs_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() > 1
       and not exists (select 1 from public.restaurants where id = old.restaurant_id) then
      return old;
    end if;
    if old.status <> 'open' then
      raise exception 'Alleen een open rekening kan worden verwijderd' using errcode = 'check_violation';
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'Een nieuwe rekening moet status open hebben' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- UPDATE
  if old.status = 'invoiced' and to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'Een gefactureerde rekening is onveranderlijk' using errcode = 'check_violation';
  end if;
  if new.status is distinct from old.status then
    if old.status = 'open' and new.status = 'closed' then
      if not public.has_perm('MANAGE_OPEN_TABS') then
        raise exception 'Geen recht om een rekening te sluiten' using errcode = 'insufficient_privilege';
      end if;
    elsif old.status = 'closed' and new.status = 'invoiced' then
      if not public.has_perm('MANAGE_INVOICES') then
        raise exception 'Geen recht om een rekening te factureren' using errcode = 'insufficient_privilege';
      end if;
      -- NIEUW (0023): geen factuur zolang een bon is afgewezen en nog niet opnieuw goedgekeurd.
      -- Definitie (zelfde als lib/approval/invoice-blocking.ts, isRejectionBlocked): een afwijzing bestaat,
      -- er bestaat geen goedkeuring, en de bonstatus is niet approved/locked.
      -- Dit is statusbescherming: factuur en factuurregels aanmaken blijft tot Step 8 mogelijk zonder deze controle.
      if exists (select 1 from public.receipts r
                  where r.open_tab_id = old.id
                    and r.status not in ('approved', 'locked')
                    and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'rejected')
                    and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')) then
        raise exception 'Een afgewezen bon is nog niet opnieuw goedgekeurd: de rekening kan niet worden gefactureerd' using errcode = 'check_violation';
      end if;
    else
      raise exception 'Ongeldige statusovergang van rekening: % -> %', old.status, new.status using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

revoke all on function public.open_tabs_guard() from public, anon, authenticated, service_role;

commit;

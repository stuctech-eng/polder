-- ============================================================
-- Rollback van migratie 0023: open_tabs_guard() terug naar exact de versie van 0021.
-- Trigger, rechten en data blijven ongemoeid.
-- ============================================================
begin;

-- PREFLIGHT: terugdraaien gaat alleen door als open_tabs_guard() exact de versie van migratie 0023 is.
-- Elke afwijking (ook: al teruggedraaid) breekt af VOOR de functie wordt overschreven.
do $$
declare
  v_hash text; v_secdef boolean; v_config text[]; v_lang text; v_ret text; v_vol "char";
  v_trig_count int; v_trig_def text; v_t record; v_fn_trigs int;
begin
  -- 1. de functie moet bestaan en exact de verwachte versie zijn (exact de versie van 0023)
  if to_regprocedure('public.open_tabs_guard()') is null then
    raise exception 'Preflight rollback 0023: open_tabs_guard() ontbreekt (migratie 0021 niet uitgevoerd?). Niets gewijzigd.';
  end if;
  select md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))), p.prosecdef, p.proconfig, l.lanname, p.prorettype::regtype::text, p.provolatile
    into v_hash, v_secdef, v_config, v_lang, v_ret, v_vol
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = 'public.open_tabs_guard()'::regprocedure;
  -- herkenning: md5 van de functietekst met alle witruimte samengevoegd (CRLF/inspringing maken geen verschil; elke andere wijziging wel)
  -- toegestaan: uitsluitend de 0023-versie, met commentaar (fb92...) of zonder commentaar (4e5b...)
  if v_hash not in ('fb9257a37816d3de6775d982135110b2', '4e5b902991d05e76167ae7581c382636') then
    raise exception 'Preflight rollback 0023: open_tabs_guard() heeft niet de verwachte inhoud (gevonden fingerprint %). Niets gewijzigd.', v_hash;
  end if;
  -- 2. de eigenschappen van de functie moeten kloppen (SECURITY INVOKER, vaste search_path, plpgsql, trigger-functie, VOLATILE)
  if v_secdef is distinct from false or v_config is distinct from array['search_path=public, pg_temp']
     or v_lang <> 'plpgsql' or v_ret <> 'trigger' or v_vol <> 'v' then
    raise exception 'Preflight rollback 0023: open_tabs_guard() heeft afwijkende eigenschappen (security definer, search_path, taal of volatiliteit). Niets gewijzigd.';
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
    raise exception 'Preflight rollback 0023: open_tabs_guard() heeft afwijkende uitvoerrechten. Niets gewijzigd.';
  end if;
  -- 4. de trigger, rechtstreeks via de catalogus: precies één trigger met deze naam, en die staat op public.open_tabs,
  --    roept public.open_tabs_guard() aan, is BEFORE + FOR EACH ROW + INSERT/UPDATE/DELETE (tgtype 31), is ingeschakeld (O),
  --    heeft geen argumenten, geen WHEN-voorwaarde, geen kolomlijst (UPDATE OF) en is geen constraint-trigger.
  select count(*) into v_trig_count from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard';
  if v_trig_count <> 1 then
    raise exception '%: verwacht precies één trigger open_tabs_guard, gevonden %. Niets gewijzigd.', 'Preflight rollback 0023', v_trig_count;
  end if;
  select t.tgrelid, t.tgfoid, t.tgtype, t.tgenabled, t.tgnargs, (t.tgqual is not null) as has_when, (t.tgattr::text <> '') as has_cols, t.tgconstraint
    into v_t
    from pg_trigger t where not t.tgisinternal and t.tgname = 'open_tabs_guard';
  select count(*) into v_fn_trigs from pg_trigger where not tgisinternal and tgfoid = 'public.open_tabs_guard()'::regprocedure;
  if v_t.tgrelid is distinct from 'public.open_tabs'::regclass
     or v_t.tgfoid is distinct from 'public.open_tabs_guard()'::regprocedure::oid
     or v_t.tgtype <> 31 or v_t.tgenabled <> 'O' or v_t.tgnargs <> 0
     or v_t.has_when or v_t.has_cols or v_t.tgconstraint <> 0 or v_fn_trigs <> 1 then
    raise exception '%: trigger open_tabs_guard staat niet aan of heeft een afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde). Niets gewijzigd.', 'Preflight rollback 0023';
  end if;
  select pg_get_triggerdef(oid) into v_trig_def from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard';
  if v_trig_def <> 'CREATE TRIGGER open_tabs_guard BEFORE INSERT OR DELETE OR UPDATE ON public.open_tabs FOR EACH ROW EXECUTE FUNCTION open_tabs_guard()' then
    raise exception '%: trigger open_tabs_guard heeft een afwijkende definitie. Niets gewijzigd.', 'Preflight rollback 0023';
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
    else
      raise exception 'Ongeldige statusovergang van rekening: % -> %', old.status, new.status using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

revoke all on function public.open_tabs_guard() from public, anon, authenticated, service_role;

commit;

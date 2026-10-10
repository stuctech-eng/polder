#!/usr/bin/env python3
"""
Genereert 10_cases.sql (de security-testmatrix) — draai: python3 generate_cases.py > 10_cases.sql
Eén lijst met cases; elke case heeft:
  id, categorie, titel, uitvoerder (e-mail | service_role | postgres), soort (select|dml|check), sql,
  expect_now (True=toegestaan vandaag), expect_after (True/False/None=open beslispunt),
  step (hardening-stap waarin expect_after gaat gelden; 0 = verandert nooit), note

Testdata komt uit staging-seed.sql (vaste UUID's: restaurant A = a0000000-…, B = b0000000-…).
Gedeactiveerde gebruiker: a.inactive@staging.test. Wees-account zonder profiel: c0000000-…0001.
"""

def q(x): return "'" + x.replace("'", "''") + "'"
def u(L, n): return f"{L}0000000-0000-0000-0000-{n:012d}"
R = {"a": "a0000000-0000-0000-0000-000000000001", "b": "b0000000-0000-0000-0000-000000000001"}
ORPH = "c0000000-0000-0000-0000-000000000001"
A = lambda n: u("a", n)
B = lambda n: u("b", n)
RA, RB = R["a"], R["b"]
RC = "d0000000-0000-0000-0000-000000000001"   # leeg restaurant C (alleen voor verwijder-tests, geen FK-ballast)

def em(l, name): return f"{l}.{name}@staging.test"

cases = []
FREE_OWNER = ("set local session_replication_role = replica; "   # testopzet: logs zijn vanaf stap 4 append-only, dus triggers even uit
              "update receipts set created_by=null where created_by is not null; update daily_closings set closed_by=null, reopened_by=null; "
              "update activity_log set user_id=null; update domain_events set published_by=null; update audit_log set changed_by=null; "
              "update notifications set recipient_user_id=null; set local session_replication_role = origin;")
def case(id, cat, title, user, kind, sql, now, after=None, step=0, note="", setup=None):
    if step == 0: after = now
    cases.append((id, cat, title, user, kind, sql.strip(), now, after, step, note, setup))

OWNER, MGR, ADM, BED, KEU, INA = (em("a", x) for x in ("owner", "manager", "admin", "bediening", "keuken", "inactive"))

# ---------------------------------------------------------------- TENANT ISOLATION (altijd geweigerd)
for cid, tbl, where in [
    ("TI01", "restaurants", f"id = '{RB}'"),
    ("TI02", "users", f"restaurant_id = '{RB}'"),
    ("TI03", "companies", f"restaurant_id = '{RB}'"),
    ("TI04", "open_tabs", f"restaurant_id = '{RB}'"),
    ("TI05", "receipts", f"restaurant_id = '{RB}'"),
    ("TI06", "invoices", f"restaurant_id = '{RB}'"),
    ("TI07", "payments", f"invoice_id = '{B(502)}'"),
    ("TI08", "activity_log", f"restaurant_id = '{RB}'"),
    ("TI09", "documents", f"restaurant_id = '{RB}'"),
    ("TI10", "approvals", f"receipt_id = '{B(301)}'"),
    ("TI11", "approval_settings", f"company_id = '{B(100)}'"),
    ("TI12", "integration_plugins", f"restaurant_id = '{RB}'"),
    ("TI13", "daily_closings", f"restaurant_id = '{RB}'"),
    ("TI14", "domain_events", f"restaurant_id = '{RB}'"),
    ("TI15", "configurations", f"restaurant_id = '{RB}'"),
]:
    case(cid, "TENANT", f"A-owner kan {tbl} van B niet lezen", OWNER, "select", f"select 1 from {tbl} where {where}", False)
case("TI20", "TENANT", "A-owner kan opslagbestand van B niet lezen", OWNER, "select",
     f"select 1 from storage.objects where bucket_id='documents' and name like '{RB}/%'", False)
case("TI21", "TENANT", "A-bediening kan bonnen van B niet lezen", BED, "select", f"select 1 from receipts where restaurant_id='{RB}'", False)
case("TW01", "TENANT", "A-owner kan bedrijf van B niet wijzigen", OWNER, "dml", f"update companies set name='x' where id='{B(100)}'", False)
case("TW02", "TENANT", "A-owner kan bon van B niet wijzigen", OWNER, "dml", f"update receipts set notes='x' where id='{B(300)}'", False)
case("TW03", "TENANT", "A-owner kan factuur van B niet wijzigen", OWNER, "dml", f"update invoices set status='sent' where id='{B(500)}'", False)
case("TW04", "TENANT", "A-owner kan gebruiker van B niet wijzigen", OWNER, "dml", f"update users set full_name='x' where id='{B(10)}'", False)
case("TW05", "TENANT", "A-owner kan restaurant B niet wijzigen", OWNER, "dml", f"update restaurants set name='x' where id='{RB}'", False)
case("TW06", "TENANT", "A-owner kan B-bon niet naar A verplaatsen", OWNER, "dml", f"update receipts set restaurant_id='{RA}' where id='{B(300)}'", False)
case("TD01", "TENANT", "A-owner kan bon van B niet verwijderen", OWNER, "dml", f"delete from receipts where id='{B(300)}'", False)
case("TD02", "TENANT", "A-owner kan logregel van B niet verwijderen", OWNER, "dml", f"delete from activity_log where id='{B(610)}'", False)
case("TD03", "TENANT", "A-owner kan restaurant B niet verwijderen", OWNER, "dml", f"delete from restaurants where id='{RB}'", False)
case("TD04", "TENANT", "A-owner kan gebruiker van B niet verwijderen", OWNER, "dml", f"delete from users where id='{B(14)}'", False)
case("TI30", "TENANT", "A-owner kan geen bon voor restaurant B aanmaken", OWNER, "dml",
     f"insert into receipts (restaurant_id, status) values ('{RB}','draft')", False)

# ---------------------------------------------------------------- ROLE ESCALATION (H2, stap 3)
for cid, usr, label in [("RE01", BED, "bediening"), ("RE02", MGR, "manager"), ("RE03", ADM, "administratie"), ("RE04", KEU, "keuken")]:
    case(cid, "ESCALATIE", f"{label} maakt zichzelf owner (direct)", usr, "dml",
         "update users set role='owner' where id = auth.uid()", True, False, 3, "bevinding 1")
case("RE05", "ESCALATIE", "bediening promoveert collega (keuken → manager)", BED, "dml",
     f"update users set role='manager' where id='{A(14)}'", True, False, 3)
case("RE06", "ESCALATIE", "manager promoveert bediening tot owner", MGR, "dml",
     f"update users set role='owner' where id='{A(13)}'", True, False, 3)
case("RE07", "ESCALATIE", "administratie degradeert de owner", ADM, "dml",
     f"update users set role='keuken' where id='{A(10)}'", True, False, 3)
case("RE08", "ESCALATIE", "gedeactiveerde gebruiker maakt zichzelf owner", INA, "dml",
     "update users set role='owner' where id = auth.uid()", True, False, 1, "gedeactiveerde gebruiker verliest schrijfrecht al in stap 1 (H9)")
case("RE09", "ESCALATIE", "bediening verhuist eigen profiel naar restaurant B", BED, "dml",
     f"update users set restaurant_id='{RB}' where id = auth.uid()", False)
case("RE10", "ESCALATIE", "bediening activeert zichzelf weer (is_active) — gedeactiveerde", INA, "dml",
     "update users set is_active=true where id = auth.uid()", True, False, 1, "gedeactiveerde mag zichzelf niet heractiveren — dicht door H9 (stap 1)")

# ---------------------------------------------------------------- TEAMBEHEER (H2, stap 3)
case("TM01", "TEAM", "bediening verwijdert de owner", BED, "dml", f"delete from users where id='{A(10)}'", True, False, 3, "bevinding 2", setup=FREE_OWNER)
case("TM02", "TEAM", "manager verwijdert de owner", MGR, "dml", f"delete from users where id='{A(10)}'", True, False, 3, setup=FREE_OWNER)
case("TM03", "TEAM", "owner wijzigt teamlid DIRECT via eigen verbinding (moet via server)", OWNER, "dml",
     f"update users set role='manager' where id='{A(14)}'", True, False, 3, "app gaat naar service-role na stap 3")
case("TM04", "TEAM", "owner verwijdert teamlid DIRECT via eigen verbinding (moet via server)", OWNER, "dml",
     f"delete from users where id='{A(14)}'", True, False, 3)
case("TM05", "TEAM", "bediening maakt profiel aan (insert)", BED, "dml",
     f"insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','x','keuken')", False)
case("TM06", "TEAM", "owner maakt profiel aan via eigen verbinding = HUIDIGE UITNODIGFLOW (faalt!)", OWNER, "dml",
     f"insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','Nieuw','keuken')", False, None, 0,
     "BEWIJS: uitnodigen kan met huidige policies niet werken; profiel moet server-side (stap 3). Blijft geweigerd via owner-verbinding.")
case("TM07", "TEAM", "service_role maakt profiel aan (nieuwe uitnodigflow)", "service_role", "dml",
     f"insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','Nieuw','keuken')", True)
case("TM08", "TEAM", "service_role deactiveert de LAATSTE actieve owner", "service_role", "dml",
     f"update users set is_active=false where id='{A(10)}'", True, False, 3, "DB-vangnet: altijd ≥1 actieve owner")
case("TM09", "TEAM", "service_role verwijdert de LAATSTE owner", "service_role", "dml",
     f"delete from users where id='{A(10)}'", True, False, 3, setup=FREE_OWNER)
case("TM10", "TEAM", "service_role wijzigt restaurant_id van een gebruiker", "service_role", "dml",
     f"update users set restaurant_id='{RB}' where id='{A(13)}'", True, False, 3, "restaurant_id onveranderlijk")
case("TM11", "TEAM", "bediening leest andere teamleden", BED, "select",
     f"select 1 from users where id <> auth.uid() and restaurant_id='{RA}'", True, None, 3, "OPEN: besluit D2 (alleen owner ziet team) is nog niet genomen; leespolicy bewust ongewijzigd in stap 3")
case("TM12", "TEAM", "owner leest teamleden", OWNER, "select", f"select 1 from users where id <> auth.uid() and restaurant_id='{RA}'", True)
case("TM13", "TEAM", "gebruiker leest eigen profiel", BED, "select", "select 1 from users where id = auth.uid()", True)
case("TM14", "TEAM", "service_role verwijdert NIET-laatste owner (tweede owner bestaat)", "service_role", "dml",
     f"delete from users where id='{A(10)}'", True, True, 0, "mag wel als er een opvolger is",
     setup=FREE_OWNER + f" insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','tweede owner','owner');")

# ---------------------------------------------------------------- RESTAURANT (H3, stap 2)
case("RS01", "RESTAURANT", "owner wijzigt eigen restaurant (direct)", OWNER, "dml", f"update restaurants set name='x' where id='{RA}'", True, False, 2, "bevinding 3")
case("RS02", "RESTAURANT", "bediening wijzigt eigen restaurant", BED, "dml", f"update restaurants set name='x' where id='{RA}'", True, False, 2)
case("RS03", "RESTAURANT", "owner verwijdert eigen restaurant (cascade!)", em("d","owner"), "dml", f"delete from restaurants where id='{RC}'", True, False, 2)
case("RS04", "RESTAURANT", "bediening verwijdert eigen restaurant (cascade!)", em("d","bediening"), "dml", f"delete from restaurants where id='{RC}'", True, False, 2)
case("RS05", "RESTAURANT", "gebruiker leest eigen restaurant", BED, "select", f"select 1 from restaurants where id='{RA}'", True)
case("RS06", "RESTAURANT", "bediening maakt nieuw restaurant aan", BED, "dml", "insert into restaurants (name) values ('Nieuw')", False)

# ---------------------------------------------------------------- LOGBOEKEN (H5, stap 4)
for cid, tbl, rid, uidcol in [("LG01", "activity_log", 610, "user_id"), ("LG03", "domain_events", 611, "published_by"), ("LG05", "audit_log", 612, "changed_by")]:
    case(cid, "LOGS", f"bediening wijzigt {tbl}", BED, "dml", f"update {tbl} set {uidcol}='{A(13)}' where id='{A(rid)}'", True, False, 4, "bevinding 4")
    case(cid[:2] + f"{int(cid[2:])+1:02d}", "LOGS", f"bediening verwijdert uit {tbl}", BED, "dml", f"delete from {tbl} where id='{A(rid)}'", True, False, 4)
case("LG07", "LOGS", "bediening schrijft logregel onder naam van de owner (vervalsen)", BED, "dml",
     f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}','{A(10)}','vals')", True, False, 4)
case("LG08", "LOGS", "bediening schrijft logregel voor restaurant B", BED, "dml",
     f"insert into activity_log (restaurant_id, user_id, action) values ('{RB}','{A(13)}','x')", False)
case("LG09", "LOGS", "bediening schrijft normale logregel (eigen naam, eigen restaurant)", BED, "dml",
     f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}','{A(13)}','normaal')", True)
case("LG10", "LOGS", "service_role wijzigt logregel (append-only geldt ook voor service)", "service_role", "dml",
     f"update activity_log set action='x' where id='{A(610)}'", True, False, 4)
case("LG11", "LOGS", "service_role schrijft logregel (publieke goedkeuring)", "service_role", "dml",
     f"insert into activity_log (restaurant_id, action) values ('{RA}','publiek')", True)
case("LG12", "LOGS", "service_role schrijft domain_event", "service_role", "dml",
     f"insert into domain_events (restaurant_id, event_type, payload) values ('{RA}','ApprovalCompleted','{{}}')", True)
case("LG13", "LOGS", "bediening schrijft domain_event onder naam van de owner", BED, "dml",
     f"insert into domain_events (restaurant_id, event_type, payload, published_by) values ('{RA}','X','{{}}','{A(10)}')", True, False, 4)

LOGT = ["activity_log", "audit_log", "domain_events"]
LOGROW = {"activity_log": 610, "domain_events": 611, "audit_log": 612}
LOGACTOR = {"activity_log": "user_id", "domain_events": "published_by", "audit_log": "changed_by"}
def ins(tbl, rest, actor):
    a = "null" if actor is None else f"'{actor}'"
    if tbl == "activity_log":
        return f"insert into activity_log (restaurant_id, user_id, action) values ('{rest}',{a},'test')"
    if tbl == "domain_events":
        return f"insert into domain_events (restaurant_id, event_type, payload, published_by) values ('{rest}','X','{{}}',{a})"
    return f"insert into audit_log (restaurant_id, table_name, record_id, action, changed_by) values ('{rest}','receipts','{A(300)}','insert',{a})"
case("LG14", "LOGS", "owner wijzigt activity_log (ook de owner mag logs niet aanpassen)", OWNER, "dml",
     f"update activity_log set action='x' where id='{A(610)}'", True, False, 4)
case("LG15", "LOGS", "owner verwijdert uit audit_log", OWNER, "dml", f"delete from audit_log where id='{A(612)}'", True, False, 4)
case("LG16", "LOGS", "manager wijzigt domain_events", MGR, "dml", f"update domain_events set event_type='x' where id='{A(611)}'", True, False, 4)
case("LG17", "LOGS", "administratie verwijdert uit activity_log", ADM, "dml", f"delete from activity_log where id='{A(610)}'", True, False, 4)
for i, t in enumerate(LOGT):
    n = 20 + i * 10
    case(f"LG{n}", "LOGS", f"bediening voegt {t}-regel toe onder eigen naam (normaal)", BED, "dml", ins(t, RA, A(13)), True)
    case(f"LG{n+1}", "LOGS", f"bediening voegt {t}-regel toe onder naam van de owner (vervalsen)", BED, "dml", ins(t, RA, A(10)), True, False, 4)
    case(f"LG{n+2}", "LOGS", f"bediening voegt {t}-regel toe voor restaurant B", BED, "dml", ins(t, RB, A(13)), False)
    case(f"LG{n+3}", "LOGS", f"A-owner voegt {t}-regel toe voor restaurant B onder eigen naam", OWNER, "dml", ins(t, RB, A(10)), False)
    case(f"LG{n+4}", "LOGS", f"gewone gebruiker voegt {t}-regel toe zonder naam (actor NULL)", BED, "dml", ins(t, RA, None), True, False, 4, "NULL-actor is alleen nog voor server-side schrijvers")
    case(f"LG{n+5}", "LOGS", f"gedeactiveerde voegt {t}-regel toe", INA, "dml", ins(t, RA, A(15)), True, False, 4, "gedeactiveerde verliest schrijfrecht (my_restaurant_id() = NULL)")
    case(f"LG{n+6}", "LOGS", f"service_role voegt {t}-regel zonder actor toe (server-side logwrite)", "service_role", "dml", ins(t, RA, None), True)
    case(f"LG{n+7}", "LOGS", f"service_role verwijdert {t}-regel (append-only geldt ook voor service)", "service_role", "dml",
         f"delete from {t} where id='{A(LOGROW[t])}'", True, False, 4)
    case(f"LG{n+8}", "LOGS", f"postgres (eigenaar) wijzigt {t}-regel — geen uitzondering voor beheerders", "postgres", "dml",
         f"update {t} set {LOGACTOR[t]}=null where id='{A(LOGROW[t])}'", True, False, 4)
    case(f"LG{n+9}", "LOGS", f"postgres (eigenaar) kan {t} niet leegmaken (TRUNCATE)", "postgres", "check",
         f"select hardening_test.attempt('truncate {t}')", True, False, 4)
case("LG50", "LOGS", "A-owner leest eigen audit_log", OWNER, "select", f"select 1 from audit_log where restaurant_id='{RA}'", True)
case("LG51", "LOGS", "A-owner leest audit_log van B niet", OWNER, "select", f"select 1 from audit_log where restaurant_id='{RB}'", False)
case("LG52", "LOGS", "A-bediening leest eigen domain_events", BED, "select", f"select 1 from domain_events where restaurant_id='{RA}'", True)
case("LG53", "LOGS", "gedeactiveerde leest activity_log van eigen restaurant", INA, "select",
     f"select 1 from activity_log where restaurant_id='{RA}'", True, False, 4, "SELECT volgt nu my_restaurant_id() (fail closed voor gedeactiveerde); zie D9")
case("LG54", "LOGS", "authenticated heeft UPDATE of DELETE op een logtabel", "postgres", "check",
     "select exists (select 1 from unnest(array['activity_log','audit_log','domain_events']) t where has_table_privilege('authenticated','public.'||t,'UPDATE') or has_table_privilege('authenticated','public.'||t,'DELETE'))", True, False, 4)
case("LG55", "LOGS", "authenticated behoudt SELECT en INSERT op alle drie de logtabellen", "postgres", "check",
     "select bool_and(has_table_privilege('authenticated','public.'||t,'SELECT') and has_table_privilege('authenticated','public.'||t,'INSERT')) from unnest(array['activity_log','audit_log','domain_events']) t", True)
case("LG56", "LOGS", "service_role behoudt SELECT en INSERT op alle drie de logtabellen", "postgres", "check",
     "select bool_and(has_table_privilege('service_role','public.'||t,'SELECT') and has_table_privilege('service_role','public.'||t,'INSERT')) from unnest(array['activity_log','audit_log','domain_events']) t", True)
case("LG57", "LOGS", "alle drie de logtabellen hebben de append-only triggers (UPDATE/DELETE en TRUNCATE)", "postgres", "check",
     "select (select count(*) from pg_trigger where not tgisinternal and tgname in ('logs_append_only','logs_no_truncate') and tgrelid in ('public.activity_log'::regclass,'public.audit_log'::regclass,'public.domain_events'::regclass)) = 6", False, True, 4)
case("LG58", "LOGS", "geen policy van het type ALL meer op de logtabellen", "postgres", "check",
     "select not exists (select 1 from pg_policies where schemaname='public' and tablename in ('activity_log','audit_log','domain_events') and cmd in ('ALL','UPDATE','DELETE'))", False, True, 4)
case("LG59", "LOGS", "bestaande logregels zijn nog aanwezig (data behouden)", "postgres", "check",
     f"select (select count(*) from activity_log where id in ('{A(610)}','{B(610)}')) = 2 and (select count(*) from domain_events where id in ('{A(611)}','{B(611)}')) = 2 and (select count(*) from audit_log where id in ('{A(612)}','{B(612)}')) = 2", True)
case("LG60", "LOGS", "restaurant verwijderen ruimt de logregels van dat restaurant mee op (cascade blijft werken)", "postgres", "dml",
     f"delete from restaurants where id='{RC}'", True, setup=(
     f"insert into activity_log (restaurant_id, action) values ('{RC}','x'); insert into domain_events (restaurant_id, event_type, payload) values ('{RC}','X','{{}}'); "
     f"insert into audit_log (restaurant_id, table_name, record_id, action) values ('{RC}','receipts','{A(300)}','insert');"))
case("LG61", "LOGS", "na het verwijderen van een restaurant zijn logregels weg", "postgres", "check",
     f"select not exists (select 1 from activity_log where restaurant_id='{RC}') and not exists (select 1 from domain_events where restaurant_id='{RC}') and not exists (select 1 from audit_log where restaurant_id='{RC}')", True,
     setup=(f"insert into activity_log (restaurant_id, action) values ('{RC}','x'); delete from restaurants where id='{RC}';"))

# ---------------------------------------------------------------- CROSS-REFERENTIES (H7, stap 5)
case("XR01", "CROSSREF", "open_tab in A met bedrijf uit B", OWNER, "dml",
     f"insert into open_tabs (restaurant_id, company_id) values ('{RA}','{B(100)}')", True, False, 5)
case("XR02", "CROSSREF", "open_tab met afdeling van ander bedrijf (zelfde restaurant)", OWNER, "dml",
     f"insert into open_tabs (restaurant_id, company_id, department_id) values ('{RA}','{A(100)}','{A(106)}')", True, False, 5)
case("XR03", "CROSSREF", "bon in A gekoppeld aan rekening van B", OWNER, "dml",
     f"insert into receipts (restaurant_id, open_tab_id, status) values ('{RA}','{B(200)}','draft')", True, False, 5)
case("XR04", "CROSSREF", "approval voor bon van B (bedrijf van A)", OWNER, "dml",
     f"insert into approvals (receipt_id, company_id, method, status) values ('{B(300)}','{A(100)}','qr','pending')", True, False, 5)
case("XR05", "CROSSREF", "factuur in A voor bedrijf van B", ADM, "dml",
     f"insert into invoices (restaurant_id, company_id, invoice_number) values ('{RA}','{B(100)}','X-1')", True, False, 5)
case("XR06", "CROSSREF", "bestaande rekening in A omzetten naar bedrijf van B", OWNER, "dml",
     f"update open_tabs set company_id='{B(100)}' where id='{A(200)}'", True, False, 5)
case("XR07", "CROSSREF", "factuurregel in A naar bon van B", ADM, "dml",
     f"insert into invoice_lines (invoice_id, receipt_id, description, amount) values ('{A(500)}','{B(300)}','x',1)", True, False, 5)
case("XR08", "CROSSREF", "normale rekening aanmaken (eigen bedrijf, eigen afdeling)", OWNER, "dml",
     f"insert into open_tabs (restaurant_id, company_id, department_id) values ('{RA}','{A(100)}','{A(101)}')", True)

SVC = "service_role"
XR = [  # (id, titel, uitvoerder, sql, nu, na, noot)
 ("XR09", "open_tab in A met bedrijf uit B (via service-role: geen bypass)", SVC, f"insert into open_tabs (restaurant_id, company_id) values ('{RA}','{B(100)}')", True, False, ""),
 ("XR10", "open_tab zonder bedrijf maar met afdeling uit B", OWNER, f"insert into open_tabs (restaurant_id, department_id) values ('{RA}','{B(101)}')", True, False, "tenant-grens geldt ook zonder bedrijf"),
 ("XR11", "open_tab zonder bedrijf met afdeling uit eigen restaurant (bewust toegestaan)", OWNER, f"insert into open_tabs (restaurant_id, department_id) values ('{RA}','{A(101)}')", True, True, "bewuste uitzondering: geen bedrijf om tegen te toetsen"),
 ("XR12", "open_tab in A met kostenplaats uit B", OWNER, f"insert into open_tabs (restaurant_id, company_id, cost_center_id) values ('{RA}','{A(100)}','{B(102)}')", True, False, ""),
 ("XR13", "open_tab in A met project uit B", OWNER, f"insert into open_tabs (restaurant_id, company_id, project_id) values ('{RA}','{A(100)}','{B(103)}')", True, False, ""),
 ("XR14", "open_tab in A met contact uit B", OWNER, f"insert into open_tabs (restaurant_id, company_id, contact_id) values ('{RA}','{A(100)}','{B(104)}')", True, False, ""),
 ("XR15", "rekening wisselt naar afdeling van ander bedrijf (zelfde restaurant)", OWNER, f"update open_tabs set department_id='{A(106)}' where id='{A(200)}'", True, False, "cross-company"),
 ("XR16", "rekening wisselt van bedrijf terwijl afdeling/kostenplaats/project bij het oude bedrijf horen", OWNER, f"update open_tabs set company_id='{A(105)}' where id='{A(200)}'", True, False, "cross-company"),
 ("XR17", "gewone wijziging van een rekening (tafelnummer) blijft werken", OWNER, f"update open_tabs set table_number='7', guest_count=3 where id='{A(200)}'", True, True, ""),
 ("XR18", "rekening: zelfde bedrijf/afdeling opnieuw opslaan blijft werken", OWNER, f"update open_tabs set company_id='{A(100)}', department_id='{A(101)}' where id='{A(200)}'", True, True, ""),
 ("XR19", "kostenplaats met afdeling van ander bedrijf", OWNER, f"insert into cost_centers (company_id, department_id, name) values ('{A(100)}','{A(106)}','x')", True, False, "cross-company"),
 ("XR20", "kostenplaats met afdeling uit restaurant B", OWNER, f"insert into cost_centers (company_id, department_id, name) values ('{A(100)}','{B(101)}','x')", True, False, ""),
 ("XR21", "kostenplaats met eigen afdeling (geldig)", OWNER, f"insert into cost_centers (company_id, department_id, name) values ('{A(100)}','{A(101)}','x')", True, True, ""),
 ("XR22", "bon aan eigen rekening koppelen (geldig)", OWNER, f"insert into receipts (restaurant_id, open_tab_id, status) values ('{RA}','{A(200)}','draft')", True, True, ""),
 ("XR23", "bestaande bon naar rekening van B verplaatsen", OWNER, f"update receipts set open_tab_id='{B(200)}' where id='{A(300)}'", True, False, ""),
 ("XR24", "bon in A met rekening van B (via service-role)", SVC, f"insert into receipts (restaurant_id, open_tab_id, status) values ('{RA}','{B(200)}','draft')", True, False, ""),
 ("XR25", "bestaande factuur naar bedrijf van B", ADM, f"update invoices set company_id='{B(100)}' where id='{A(500)}'", True, False, ""),
 ("XR26", "factuur voor eigen bedrijf (geldig)", ADM, f"insert into invoices (restaurant_id, company_id, invoice_number) values ('{RA}','{A(105)}','X-OK')", True, True, ""),
 ("XR27", "factuurregel met eigen bon (geldig)", ADM, f"insert into invoice_lines (invoice_id, receipt_id, description, amount) values ('{A(500)}','{A(303)}','ok',1)", True, True, ""),
 ("XR28", "factuurregel in A naar bon van B (via service-role)", SVC, f"insert into invoice_lines (invoice_id, receipt_id, description, amount) values ('{A(500)}','{B(300)}','x',1)", True, False, ""),
 ("XR29", "factuurregel zonder bon blijft mogelijk", ADM, f"insert into invoice_lines (invoice_id, description, amount) values ('{A(500)}','vrij',1)", True, True, ""),
 ("XR30", "goedkeuring voor eigen bon en eigen bedrijf (geldig)", OWNER, f"insert into approvals (receipt_id, company_id, method, status) values ('{A(300)}','{A(100)}','qr','pending')", True, True, ""),
 ("XR31", "goedkeuring: bon van A met bedrijf van B (via service-role)", SVC, f"insert into approvals (receipt_id, company_id, method, status) values ('{A(300)}','{B(100)}','qr','pending')", True, False, ""),
 ("XR32", "configuratie in A met bedrijf van B", OWNER, f"insert into configurations (restaurant_id, company_id, key, value) values ('{RA}','{B(100)}','kx','{{}}')", True, False, ""),
 ("XR33", "configuratie in A met eigen bedrijf (geldig)", OWNER, f"insert into configurations (restaurant_id, company_id, key, value) values ('{RA}','{A(100)}','kx','{{}}')", True, True, ""),
 ("XR34", "configuratie zonder bedrijf (restaurantbreed) blijft mogelijk", OWNER, f"insert into configurations (restaurant_id, company_id, key, value) values ('{RA}',null,'kx','{{}}')", True, True, ""),
 ("XR35", "workflowregel in A met bedrijf van B", OWNER, f"insert into workflow_rules (restaurant_id, company_id) values ('{RA}','{B(100)}')", True, False, ""),
 ("XR36", "document in A dat naar factuur van B wijst", OWNER, f"insert into documents (restaurant_id, type, related_table, related_id, storage_path) values ('{RA}','invoice','invoices','{B(502)}','{RA}/invoices/x.pdf')", True, False, ""),
 ("XR37", "document bij eigen factuur (geldig)", OWNER, f"insert into documents (restaurant_id, type, related_table, related_id, storage_path) values ('{RA}','invoice','invoices','{A(501)}','{RA}/invoices/{A(501)}.pdf')", True, True, ""),
 ("XR38", "document met andere related_table wordt niet gecontroleerd (bewuste uitzondering)", OWNER, f"insert into documents (restaurant_id, type, related_table, related_id, storage_path) values ('{RA}','report_export','receipts','{B(300)}','{RA}/x.pdf')", True, True, "alleen related_table='invoices' wordt gebruikt en gecontroleerd"),
 ("XR40", "bon met created_by uit restaurant B", OWNER, f"insert into receipts (restaurant_id, status, created_by) values ('{RA}','draft','{B(10)}')", True, False, ""),
 ("XR41", "dagafsluiting met closed_by uit restaurant B", OWNER, f"insert into daily_closings (restaurant_id, closing_date, closed_by) values ('{RA}', date '2031-01-01', '{B(10)}')", True, False, ""),
 ("XR42", "notificatie voor ontvanger uit restaurant B", OWNER, f"insert into notifications (restaurant_id, recipient_user_id, type, trigger_event) values ('{RA}','{B(10)}','email','x')", True, False, ""),
 ("XR43", "activity_log in A onder naam van gebruiker uit B (via service-role)", SVC, f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}','{B(10)}','x')", True, False, ""),
 ("XR44", "domain_event in A met published_by uit B (via service-role)", SVC, f"insert into domain_events (restaurant_id, event_type, payload, published_by) values ('{RA}','X','{{}}','{B(10)}')", True, False, ""),
 ("XR45", "audit_log in A met changed_by uit B (via service-role)", SVC, f"insert into audit_log (restaurant_id, table_name, record_id, action, changed_by) values ('{RA}','receipts','{A(300)}','insert','{B(10)}')", True, False, ""),
 ("XR46", "service-role logt zonder gebruiker (publieke goedkeuring) blijft werken", SVC, f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}',null,'publiek')", True, True, ""),
 ("XR47", "service-role logt onder naam van een eigen gebruiker blijft werken", SVC, f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}','{A(13)}','ok')", True, True, ""),
 ("XR50", "bedrijf verhuist naar ander restaurant (ouder-kant)", "postgres", f"update companies set restaurant_id='{RB}' where id='{A(100)}'", True, False, "ouder-sleutel onveranderlijk"),
 ("XR51", "afdeling verhuist naar ander bedrijf", "postgres", f"update departments set company_id='{A(105)}' where id='{A(101)}'", True, False, ""),
 ("XR52", "kostenplaats verhuist naar ander bedrijf", "postgres", f"update cost_centers set company_id='{A(105)}' where id='{A(102)}'", True, False, ""),
 ("XR53", "project verhuist naar ander bedrijf", "postgres", f"update projects set company_id='{A(105)}' where id='{A(103)}'", True, False, ""),
 ("XR54", "contact verhuist naar ander bedrijf", "postgres", f"update contacts set company_id='{A(105)}' where id='{A(104)}'", True, False, ""),
 ("XR55", "rekening verhuist naar ander restaurant", "postgres", f"update open_tabs set restaurant_id='{RB}' where id='{A(204)}'", True, False, ""),
 ("XR56", "bon verhuist naar ander restaurant", "postgres", f"update receipts set restaurant_id='{RB}' where id='{A(303)}'", True, False, ""),
 ("XR57", "factuur verhuist naar ander restaurant", "postgres", f"update invoices set restaurant_id='{RB}' where id='{A(500)}'", True, False, ""),
 ("XR58", "gewone wijziging van een bedrijf (naam) blijft werken", OWNER, f"update companies set name='Nieuwe naam' where id='{A(100)}'", True, True, ""),
 ("XR59", "ouder-sleutel opnieuw met dezelfde waarde opslaan blijft werken", "postgres", f"update companies set restaurant_id='{RA}' where id='{A(100)}'", True, True, ""),
]
for cid, title, usr, sql, now, after, note in XR:
    case(cid, "CROSSREF", title, usr, "dml", sql, now, after, 5 if now != after else 0, note)
case("XR60", "CROSSREF", "alle 23 xref-triggers aanwezig", "postgres", "check",
     "select (select count(*) from pg_trigger where not tgisinternal and tgname in ('xref_open_tabs','xref_cost_centers','xref_receipts','xref_invoices','xref_invoice_lines','xref_approvals','xref_company_scoped','xref_documents','xref_user_ref','xref_keys_immutable')) = 23", False, True, 5)
case("XR61", "CROSSREF", "xref-functies zijn voor niemand rechtstreeks uitvoerbaar", "postgres", "check",
     "select not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname like 'xref\\_%' and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('service_role',p.oid,'EXECUTE')))", True)
case("XR62", "CROSSREF", "bestaande seed-relaties zijn nog geldig (geen cross-reference in de data)", "postgres", "check",
     "select not exists (select 1 from open_tabs t join companies c on c.id=t.company_id where c.restaurant_id<>t.restaurant_id) and not exists (select 1 from receipts r join open_tabs t on t.id=r.open_tab_id where t.restaurant_id<>r.restaurant_id) and not exists (select 1 from invoices i join companies c on c.id=i.company_id where c.restaurant_id<>i.restaurant_id)", True)

# ---------------------------------------------------------------- STORAGE (H6, stap 6)
pdf = f"{RA}/invoices/{A(502)}.pdf"
case("ST01", "STORAGE", "administratie leest factuur-PDF", ADM, "select", f"select 1 from storage.objects where bucket_id='documents' and name='{pdf}'", True)
case("ST02", "STORAGE", "bediening leest factuur-PDF", BED, "select", f"select 1 from storage.objects where bucket_id='documents' and name='{pdf}'", True, False, 6, "geen MANAGE_INVOICES")
case("ST03", "STORAGE", "manager leest factuur-PDF", MGR, "select", f"select 1 from storage.objects where bucket_id='documents' and name='{pdf}'", True, False, 6, "geen MANAGE_INVOICES")
case("ST04", "STORAGE", "administratie overschrijft bestaand PDF (update)", ADM, "dml",
     f"update storage.objects set name=name where bucket_id='documents' and name='{pdf}'", True, False, 6, "bevinding 6")
case("ST05", "STORAGE", "administratie verwijdert PDF", ADM, "dml", f"delete from storage.objects where bucket_id='documents' and name='{pdf}'", False)
case("ST06", "STORAGE", "administratie uploadt nieuw PDF in eigen map", ADM, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", True)
case("ST07", "STORAGE", "administratie uploadt in map van restaurant B", ADM, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RB}/invoices/{A(501)}.pdf')", False)
case("ST08", "STORAGE", "bediening uploadt in eigen map", BED, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(500)}.pdf')", True, False, 6)
case("ST09", "STORAGE", "upload met pad zonder restaurant-uuid", ADM, "dml",
     "insert into storage.objects (bucket_id, name) values ('documents','geen-uuid/x.pdf')", False)

BADM = em("b", "admin")
sel = lambda p: f"select 1 from storage.objects where bucket_id='documents' and name='{p}'"
case("ST10", "STORAGE", "owner leest factuur-PDF", OWNER, "select", sel(pdf), True)
case("ST11", "STORAGE", "keuken leest factuur-PDF", KEU, "select", sel(pdf), True, False, 6, "geen MANAGE_INVOICES")
case("ST12", "STORAGE", "administratie van restaurant B leest PDF van A niet", BADM, "select", sel(pdf), False)
case("ST13", "STORAGE", "gedeactiveerde gebruiker leest factuur-PDF", INA, "select", sel(pdf), True, False, 6, "gedeactiveerde verliest leesrecht (helpers uit stap 1)")
case("ST14", "STORAGE", "owner overschrijft bestaand PDF (update)", OWNER, "dml",
     f"update storage.objects set name=name where bucket_id='documents' and name='{pdf}'", True, False, 6)
case("ST15", "STORAGE", "bediening overschrijft bestaand PDF (update)", BED, "dml",
     f"update storage.objects set name=name where bucket_id='documents' and name='{pdf}'", True, False, 6)
case("ST16", "STORAGE", "owner verwijdert PDF", OWNER, "dml", f"delete from storage.objects where bucket_id='documents' and name='{pdf}'", False)
case("ST17", "STORAGE", "owner uploadt nieuw PDF in eigen map (geldig)", OWNER, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", True)
case("ST18", "STORAGE", "manager uploadt in eigen map", MGR, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(500)}.pdf')", True, False, 6, "geen MANAGE_INVOICES")
case("ST19", "STORAGE", "administratie van B uploadt in map van restaurant A", BADM, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", False)
case("ST20", "STORAGE", "gedeactiveerde gebruiker uploadt in eigen map", INA, "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", True, False, 6)
case("ST21", "STORAGE", "administratie uploadt in een andere bucket", ADM, "dml",
     f"insert into storage.objects (bucket_id, name) values ('andere','{RA}/invoices/{A(501)}.pdf')", False,
     setup="insert into storage.buckets (id, name, public) values ('andere','andere',false) on conflict do nothing;")
case("ST22", "STORAGE", "anon leest factuur-PDF", "anon", "select", sel(pdf), False)
case("ST23", "STORAGE", "anon uploadt", "anon", "dml", f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", False)
case("ST24", "STORAGE", "pad zonder uuid: leesactie geeft nette weigering (geen fout)", ADM, "check",
     "select count(*) = 0 from storage.objects where bucket_id='documents' and name = 'geen-uuid/x.pdf'", True)
case("ST25", "STORAGE", "service_role (server-side) uploadt PDF — blijft werken", "service_role", "dml",
     f"insert into storage.objects (bucket_id, name) values ('documents','{RA}/invoices/{A(501)}.pdf')", True)
case("ST26", "STORAGE", "service_role leest PDF — blijft werken", "service_role", "select", sel(pdf), True)
case("ST27", "STORAGE", "geen UPDATE-, DELETE- of ALL-policy op storage.objects", "postgres", "check",
     "select not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd in ('UPDATE','DELETE','ALL'))", False, True, 6)
case("ST28", "STORAGE", "storage.objects heeft precies 2 policies (lezen en uploaden), beide alleen voor authenticated", "postgres", "check",
     "select (select count(*) from pg_policies where schemaname='storage' and tablename='objects') = 2 and not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and roles <> '{authenticated}')", False, True, 6)
case("ST29", "STORAGE", "bestaand PDF van restaurant A en B nog aanwezig (data behouden)", "postgres", "check",
     f"select (select count(*) from storage.objects where bucket_id='documents' and name in ('{pdf}','{RB}/invoices/{B(502)}.pdf')) = 2", True)

# ---------------------------------------------------------------- BOEKHOUDING / STATUSSEN (H4, stap 7-9)
case("AC01", "BOEKHOUDING", "bediening wijzigt notitie van vergrendelde bon", BED, "dml", f"update receipts set notes='x' where id='{A(302)}'", True, False, 7, "bevinding 5")
case("AC02", "BOEKHOUDING", "bediening zet bon pending_approval → locked (zelf goedkeuren)", BED, "dml", f"update receipts set status='locked' where id='{A(301)}'", True, False, 7)
case("AC03", "BOEKHOUDING", "manager zet bon pending_approval → locked (legitiem goedkeuren)", MGR, "dml", f"update receipts set status='locked' where id='{A(301)}'", True)
case("AC04", "BOEKHOUDING", "bediening verwijdert vergrendelde bon", BED, "dml", f"delete from receipts where id='{A(302)}'", True, False, 7, setup="delete from invoice_lines where receipt_id='%s'" % A(302))
case("AC05", "BOEKHOUDING", "bediening voegt zelf een goedgekeurde approval toe", BED, "dml",
     f"insert into approvals (receipt_id, company_id, method, status) values ('{A(300)}','{A(100)}','pin','approved')", True, False, 7)
case("AC06", "BOEKHOUDING", "administratie zet gefactureerde rekening terug naar open", ADM, "dml", f"update open_tabs set status='open' where id='{A(202)}'", True, False, 7)
case("AC07", "BOEKHOUDING", "manager zet rekening closed → invoiced (zonder factuurrecht)", MGR, "dml", f"update open_tabs set status='invoiced' where id='{A(201)}'", True, False, 7)
case("AC08", "BOEKHOUDING", "bediening sluit open rekening (legitiem)", BED, "dml", f"update open_tabs set status='closed' where id='{A(200)}'", True)
case("AC09", "BOEKHOUDING", "bediening verwijdert GESLOTEN lege rekening (alleen open mag)", BED, "dml", f"delete from open_tabs where id='{A(203)}'", True, False, 7)
case("AC10", "BOEKHOUDING", "bediening verwijdert OPEN lege rekening (legitiem)", BED, "dml", f"delete from open_tabs where id='{A(204)}'", True)
case("AC11", "BOEKHOUDING", "bediening maakt direct een vergrendelde bon aan", BED, "dml",
     f"insert into receipts (restaurant_id, open_tab_id, status) values ('{RA}','{A(200)}','locked')", True, False, 7)
case("AC12", "BOEKHOUDING", "bediening wijzigt regel van vergrendelde bon", BED, "dml", f"update receipt_lines set unit_price=1 where id='{A(311)}'", True, False, 7)
case("AC13", "BOEKHOUDING", "bediening bewerkt gewone bon (legitiem)", BED, "dml", f"update receipts set notes='ok' where id='{A(300)}'", True)
case("AC14", "BOEKHOUDING", "bediening dient bon in voor goedkeuring (linked → pending_approval)", BED, "dml", f"update receipts set status='pending_approval' where id='{A(300)}'", True)
case("AC15", "BOEKHOUDING", "service_role (publieke link) zet pending_approval → locked", "service_role", "dml", f"update receipts set status='locked' where id='{A(301)}'", True)
case("AC16", "BOEKHOUDING", "service_role (publieke link) zet pending_approval → linked (afwijzen)", "service_role", "dml", f"update receipts set status='linked' where id='{A(301)}'", True)
case("AC17", "BOEKHOUDING", "service_role wijzigt vergrendelde bon (geen algemene bypass)", "service_role", "dml", f"update receipts set notes='x' where id='{A(302)}'", True, False, 7, "technisch risico A")
case("AC18", "BOEKHOUDING", "service_role keurt approval goed (pending → approved)", "service_role", "dml", f"update approvals set status='approved' where id='{A(400)}'", True)
case("AC19", "BOEKHOUDING", "service_role wijzigt verification_code van approval", "service_role", "dml", f"update approvals set verification_code='x' where id='{A(400)}'", True, False, 7)
case("AC20", "BOEKHOUDING", "bediening wijzigt bestaande goedgekeurde approval", BED, "dml", f"update approvals set approved_by='ik' where id='{A(401)}'", True, False, 7)

case("AC30", "FACTUREN", "bediening leest facturen", BED, "select", f"select 1 from invoices where restaurant_id='{RA}'", True, False, 9)
case("AC31", "FACTUREN", "manager leest facturen (VIEW_REVENUE)", MGR, "select", f"select 1 from invoices where restaurant_id='{RA}'", True)
case("AC32", "FACTUREN", "bediening registreert betaling", BED, "dml", f"insert into payments (invoice_id, amount) values ('{A(501)}', 5)", True, False, 9)
case("AC33", "FACTUREN", "administratie registreert betaling (legitiem)", ADM, "dml", f"insert into payments (invoice_id, amount) values ('{A(501)}', 5)", True)
case("AC34", "FACTUREN", "administratie wijzigt totaal van betaalde factuur", ADM, "dml", f"update invoices set total=1 where id='{A(502)}'", True, False, 9)
case("AC35", "FACTUREN", "administratie zet betaalde factuur terug naar sent", ADM, "dml", f"update invoices set status='sent' where id='{A(502)}'", True, False, 9)
case("AC36", "FACTUREN", "administratie verwijdert factuur", ADM, "dml", f"delete from invoices where id='{A(500)}'", True, False, 9)
case("AC37", "FACTUREN", "administratie wijzigt bedrag van bestaande betaling", ADM, "dml", f"update payments set amount=0.01 where id='{A(520)}'", True, False, 9)
case("AC38", "FACTUREN", "administratie verwijdert bestaande betaling", ADM, "dml", f"delete from payments where id='{A(520)}'", True, False, 9)
case("AC39", "FACTUREN", "administratie zet factuur draft → sent (legitiem)", ADM, "dml", f"update invoices set status='sent' where id='{A(500)}'", True)
case("AC40", "FACTUREN", "administratie zet factuur sent → paid (legitiem)", ADM, "dml", f"update invoices set status='paid' where id='{A(501)}'", True)
case("AC41", "FACTUREN", "OPEN BESLISPUNT D6: factuur draft → paid rechtstreeks", ADM, "dml", f"update invoices set status='paid' where id='{A(500)}'", True, None, 9, "D6 — niet zelf beslissen")
case("AC42", "FACTUREN", "bediening wijzigt factuurregel", BED, "dml", f"update invoice_lines set amount=1 where id='{A(510)}'", True, False, 9)
case("AC43", "FACTUREN", "bediening verwijdert document-record", BED, "dml", f"delete from documents where id='{A(530)}'", True, False, 9)

case("AC50", "DAGAFSLUITING", "bediening maakt dagafsluiting", BED, "dml",
     f"insert into daily_closings (restaurant_id, closing_date, closed_by) values ('{RA}', current_date, '{A(13)}')", True, False, 10)
case("AC51", "DAGAFSLUITING", "administratie maakt dagafsluiting (alleen bekijken)", ADM, "dml",
     f"insert into daily_closings (restaurant_id, closing_date, closed_by) values ('{RA}', current_date, '{A(12)}')", True, False, 10)
case("AC52", "DAGAFSLUITING", "manager maakt dagafsluiting (legitiem)", MGR, "dml",
     f"insert into daily_closings (restaurant_id, closing_date, closed_by) values ('{RA}', current_date, '{A(11)}')", True)
case("AC53", "DAGAFSLUITING", "manager wijzigt bestaande dagafsluiting", MGR, "dml", f"update daily_closings set total_revenue=1 where id='{A(600)}'", True, False, 10)
case("AC54", "DAGAFSLUITING", "owner verwijdert dagafsluiting", OWNER, "dml", f"delete from daily_closings where id='{A(600)}'", True, False, 10)

case("AC60", "STAMDATA", "bediening wijzigt bedrijf", BED, "dml", f"update companies set name='x' where id='{A(100)}'", True, False, 10)
case("AC61", "STAMDATA", "administratie wijzigt bedrijf (legitiem)", ADM, "dml", f"update companies set name='ok' where id='{A(100)}'", True)
case("AC62", "STAMDATA", "manager maakt bedrijf aan (geen MANAGE_COMPANIES)", MGR, "dml", f"insert into companies (restaurant_id, name) values ('{RA}','x')", True, False, 10)
case("AC63", "STAMDATA", "bediening wijzigt configuratie", BED, "dml", f"update configurations set value='[]' where id='{A(620)}'", True, False, 10)
case("AC64", "STAMDATA", "bediening wijzigt workflowregel", BED, "dml", f"update workflow_rules set requires_approval=false where id='{A(621)}'", True, False, 10)
case("AC65", "STAMDATA", "administratie wijzigt workflowregel (legitiem)", ADM, "dml", f"update workflow_rules set requires_approval=false where id='{A(621)}'", True)
case("AC66", "STAMDATA", "bediening leest bedrijven (nodig voor rekening openen)", BED, "select", f"select 1 from companies where restaurant_id='{RA}'", True)
case("AC67", "STAMDATA", "bediening leest integration_plugins (incl. config)", BED, "select", f"select 1 from integration_plugins where restaurant_id='{RA}'", True, False, 10, "bevinding 7")
case("AC68", "STAMDATA", "bediening wijzigt integration_plugins.config", BED, "dml", f"update integration_plugins set config='{{}}' where id='{A(630)}'", True, False, 10)
case("AC69", "STAMDATA", "keuken leest bonnen (D1: geen leestoegang)", KEU, "select", f"select 1 from receipts where restaurant_id='{RA}'", True, False, 7, "besluit D1")
case("AC70", "STAMDATA", "bediening leest approvals incl. verification_code (D5: bewust zichtbaar)", BED, "select", f"select verification_code from approvals where receipt_id='{A(301)}'", True)

# ---------------------------------------------------------------- PIN-GEHEIMEN (H10, stap 10)
case("PN01", "PIN", "bediening leest pin_hash/pin_salt", BED, "select", f"select pin_hash, pin_salt from approval_settings where company_id='{A(100)}'", True, False, 11, "bevinding 12")
case("PN02", "PIN", "owner leest pin_hash via eigen verbinding", OWNER, "select", f"select pin_hash from approval_settings where company_id='{A(100)}'", True, False, 11)
case("PN03", "PIN", "bediening leest niet-geheime goedkeuringsinstelling (methode)", BED, "select", f"select method, is_required from approval_settings where company_id='{A(100)}'", True)
case("PN04", "PIN", "bediening wijzigt pin_hash", BED, "dml", f"update approval_settings set pin_hash='x' where id='{A(410)}'", True, False, 10)
case("PN05", "PIN", "service_role leest pin_hash (server-verificatie)", "service_role", "select", f"select pin_hash from approval_settings where company_id='{A(100)}'", True)

# ---------------------------------------------------------------- GEDEACTIVEERDE GEBRUIKER (H9)
case("IN01", "INACTIEF", "gedeactiveerde leest bonnen", INA, "select", f"select 1 from receipts where restaurant_id='{RA}'", True, False, 7, "bevinding 11 — zie open beslispunt D9")
case("IN02", "INACTIEF", "gedeactiveerde leest facturen", INA, "select", f"select 1 from invoices where restaurant_id='{RA}'", True, False, 8)
case("IN03", "INACTIEF", "gedeactiveerde leest bedrijven", INA, "select", f"select 1 from companies where restaurant_id='{RA}'", True, False, 8)
case("IN04", "INACTIEF", "gedeactiveerde leest dagafsluitingen (policy gebruikt my_restaurant_id)", INA, "select", f"select 1 from daily_closings where restaurant_id='{RA}'", True, False, 1)
case("IN05", "INACTIEF", "gedeactiveerde leest teamleden (policy gebruikt my_restaurant_id)", INA, "select", f"select 1 from users where id <> auth.uid() and restaurant_id='{RA}'", True, False, 1)
case("IN06", "INACTIEF", "gedeactiveerde leest EIGEN profiel (nodig voor middleware)", INA, "select", "select 1 from users where id = auth.uid()", True)
case("IN07", "INACTIEF", "gedeactiveerde schrijft logregel", INA, "dml", f"insert into activity_log (restaurant_id, user_id, action) values ('{RA}','{A(15)}','x')", True, False, 4)
case("IN08", "INACTIEF", "gedeactiveerde wijzigt bon", INA, "dml", f"update receipts set notes='x' where id='{A(300)}'", True, False, 7)

# ---------------------------------------------------------------- TENANTSWITCH (fase 1, migratie 0024, stap 8)
# De 15 tabellen met de oude inline-controle. Per tabel en bewerking twee cases (zie hardening_test.inactief_dml):
#   TOxx = de testopzet klopt (rij bestaat, actieve gebruiker heeft met dezelfde SQL effect, rij daarna exact hersteld) — altijd waar
#   TSxx = de gedeactiveerde gebruiker wordt geweigerd om de juiste reden — waar vanaf stap 8
STAP_TENANT = 8
TS_TABELLEN = ["companies", "invoices", "documents", "workflow_rules", "configurations", "notifications", "integration_plugins",
               "contacts", "departments", "cost_centers", "projects", "company_codes", "approval_settings", "invoice_lines", "payments"]
for n, tbl in enumerate(TS_TABELLEN, start=1):
    for op, letter in (("SELECT", "S"), ("INSERT", "I"), ("UPDATE", "U"), ("DELETE", "D")):
        case(f"TO{n:02d}{letter}", "TENANTSWITCH", f"opzet {tbl} {op}: actieve owner heeft effect met dezelfde SQL, rij hersteld", "postgres", "check",
             f"select (hardening_test.inactief_dml('{tbl}','{op}')).opzet_ok", True)
        case(f"TS{n:02d}{letter}", "TENANTSWITCH", f"gedeactiveerde {op} op {tbl} geweigerd (0 rijen / RLS-fout), actieve gebruiker niet", "postgres", "check",
             f"select (hardening_test.inactief_dml('{tbl}','{op}')).geweigerd", False, True, STAP_TENANT)
# actieve bediening (geen owner) wordt door de tenantswitch niet beperkt: zelfde opzet, andere actieve rol
for n, tbl in enumerate(TS_TABELLEN, start=1):
    case(f"TB{n:02d}", "TENANTSWITCH", f"actieve bediening leest {tbl} met dezelfde opzet (niet beperkt)", "postgres", "check",
         f"select (hardening_test.inactief_dml('{tbl}','SELECT','{BED}')).opzet_ok", True)
# isolatie aanvullen voor de tabellen zonder TENANT-case; met positieve controle (B-owner ziet zijn eigen rij)
OWNER_B = em("b", "owner")
for cid, tbl, where in [
    ("TI40", "contacts", f"company_id = '{B(100)}'"), ("TI41", "departments", f"company_id = '{B(100)}'"),
    ("TI42", "cost_centers", f"company_id = '{B(100)}'"), ("TI43", "projects", f"company_id = '{B(100)}'"),
    ("TI44", "invoice_lines", f"invoice_id = '{B(502)}'"), ("TI45", "workflow_rules", f"restaurant_id = '{RB}'"),
    ("TI46", "company_codes", f"company_id = '{B(100)}'"), ("TI47", "notifications", f"restaurant_id = '{RB}'"),
]:
    case(cid, "TENANT", f"A-owner kan {tbl} van B niet lezen", OWNER, "select", f"select 1 from {tbl} where {where}", False)
    case(cid + "p", "TENANT", f"controle: B-owner leest eigen {tbl}", OWNER_B, "select", f"select 1 from {tbl} where {where}", True)

# ---------------------------------------------------------------- PRIVILEGES / FUNCTIES (H1, H8, H9)
for cid, role, priv in [("PR01", "authenticated", "TRUNCATE"), ("PR02", "anon", "TRUNCATE"), ("PR03", "authenticated", "TRIGGER"),
                        ("PR04", "authenticated", "REFERENCES"), ("PR05", "anon", "REFERENCES")]:
    case(cid, "PRIVILEGES", f"{role} heeft {priv} op receipts", "postgres", "check",
         f"select has_table_privilege('{role}','public.receipts','{priv}')", True, False, 2, "bevinding 9")
case("PR06", "PRIVILEGES", "anon heeft SELECT op receipts", "postgres", "check", "select has_table_privilege('anon','public.receipts','SELECT')", False)
case("PR07", "PRIVILEGES", "anon heeft INSERT op receipts", "postgres", "check", "select has_table_privilege('anon','public.receipts','INSERT')", False)
case("PR08", "PRIVILEGES", "authenticated heeft DELETE op payments (geen route gebruikt dit)", "postgres", "check",
     "select has_table_privilege('authenticated','public.payments','DELETE')", True, False, 12, "least privilege (stap 11)")
case("PR09", "PRIVILEGES", "authenticated heeft UPDATE op restaurants", "postgres", "check",
     "select has_table_privilege('authenticated','public.restaurants','UPDATE')", True, False, 2)
case("PR10", "PRIVILEGES", "anon mag my_restaurant_id() uitvoeren", "postgres", "check",
     "select has_function_privilege('anon','public.my_restaurant_id()','EXECUTE')", True, False, 1)
case("PR11", "PRIVILEGES", "my_restaurant_id() heeft vast search_path", "postgres", "check",
     "select coalesce((select exists (select 1 from unnest(proconfig) c where c like 'search_path=%') from pg_proc where proname='my_restaurant_id' and proconfig is not null), false)",
     False, True, 1)
case("PR12", "PRIVILEGES", "my_role() bestaat", "postgres", "check", "select to_regprocedure('public.my_role()') is not null", False, True, 1)
case("PR13", "PRIVILEGES", "role_has_permission() == TypeScript-matrix (alle 55 combinaties)", "postgres", "check",
     """select case when to_regprocedure('public.role_has_permission(text,text)') is null then false
        else not exists (select 1 from hardening_test.permission_baseline b
                         where public.role_has_permission(b.role, b.permission) is distinct from b.allowed) end""",
     False, True, 1, "consistentietest matrix TS ↔ SQL")
case("PR14", "PRIVILEGES", "service_role heeft INSERT op activity_log (blijft nodig)", "postgres", "check",
     "select has_table_privilege('service_role','public.activity_log','INSERT')", True)
case("PR15", "PRIVILEGES", "service_role heeft UPDATE op receipts (publieke goedkeuring)", "postgres", "check",
     "select has_table_privilege('service_role','public.receipts','UPDATE')", True)
case("PR16", "PRIVILEGES", "elke public-tabel heeft RLS aan", "postgres", "check",
     "select not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity and c.relname not like '\\_%')", True)
case("PR17", "PRIVILEGES", "geen policy van het type ALL meer in public", "postgres", "check",
     "select not exists (select 1 from pg_policies where schemaname='public' and cmd='ALL')", False, True, 10, "eindcontrole: geen 'for all'")

# ---------------------------------------------------------------- HELPERS (H1 + H9, stap 1)
OTHER_ORPHAN = "orphan@staging.test"
for cid, usr, role in [("HP01", OWNER, "owner"), ("HP02", MGR, "manager"), ("HP03", ADM, "administratie"), ("HP04", BED, "bediening"), ("HP05", KEU, "keuken")]:
    case(cid, "HELPERS", f"my_role() van actieve {role} = '{role}'", usr, "check", f"select public.my_role() = '{role}'", False, True, 1)
for cid, usr in [("HP06", OWNER), ("HP07", MGR), ("HP08", ADM), ("HP09", BED), ("HP10", KEU)]:
    case(cid, "HELPERS", f"my_restaurant_id() van actieve gebruiker ({usr.split('.')[1].split('@')[0]}) = eigen restaurant A", usr, "check",
         f"select public.my_restaurant_id() = '{RA}'", True)
case("HP11", "HELPERS", "my_restaurant_id() van A-gebruiker is nooit restaurant B", OWNER, "check", f"select public.my_restaurant_id() is distinct from '{RB}'", True)
case("HP12", "HELPERS", "my_restaurant_id() van B-owner = B", em("b", "owner"), "check", f"select public.my_restaurant_id() = '{RB}'", True)
case("HP13", "HELPERS", "gedeactiveerde gebruiker: my_restaurant_id() = NULL (fail closed)", INA, "check", "select public.my_restaurant_id() is null", False, True, 1)
case("HP14", "HELPERS", "gedeactiveerde gebruiker: my_role() = NULL (fail closed)", INA, "check", "select public.my_role() is null", False, True, 1)
case("HP15", "HELPERS", "gedeactiveerde gebruiker: has_perm('MANAGE_RECEIPTS') = false", INA, "check", "select public.has_perm('MANAGE_RECEIPTS') is false", False, True, 1)
case("HP16", "HELPERS", "account zonder profiel (wees): my_restaurant_id() = NULL", OTHER_ORPHAN, "check", "select public.my_restaurant_id() is null", True)
case("HP17", "HELPERS", "account zonder profiel (wees): my_role() = NULL", OTHER_ORPHAN, "check", "select public.my_role() is null", False, True, 1)
case("HP18", "HELPERS", "niet-bestaande gebruiker (willekeurige uid): my_restaurant_id() = NULL", "uid:99999999-9999-9999-9999-999999999999", "check", "select public.my_restaurant_id() is null", True)
case("HP19", "HELPERS", "niet-bestaande gebruiker: my_role() = NULL", "uid:99999999-9999-9999-9999-999999999999", "check", "select public.my_role() is null", False, True, 1)
case("HP20", "HELPERS", "auth.uid() IS NULL: my_restaurant_id() = NULL", "nosub", "check", "select public.my_restaurant_id() is null", True)
case("HP21", "HELPERS", "auth.uid() IS NULL: my_role() = NULL", "nosub", "check", "select public.my_role() is null", False, True, 1)
case("HP22", "HELPERS", "auth.uid() IS NULL: has_perm('VIEW_DASHBOARD') = false", "nosub", "check", "select public.has_perm('VIEW_DASHBOARD') is false", False, True, 1)
case("HP23", "HELPERS", "onbekende rol → geen permissie", "postgres", "check", "select public.role_has_permission('superadmin','VIEW_DASHBOARD') is false", False, True, 1)
case("HP24", "HELPERS", "NULL-rol → false (niet NULL)", "postgres", "check", "select public.role_has_permission(null,'VIEW_DASHBOARD') is false", False, True, 1)
case("HP25", "HELPERS", "onbekende permissie → false", "postgres", "check", "select public.role_has_permission('owner','NOPE') is false", False, True, 1)
case("HP26", "HELPERS", "NULL-permissie → false (niet NULL)", "postgres", "check", "select public.role_has_permission('owner',null) is false", False, True, 1)
case("HP27", "HELPERS", "has_perm('NOPE') van owner = false", OWNER, "check", "select public.has_perm('NOPE') is false", False, True, 1)
for cid, usr, perm, exp in [("HP28", OWNER, "MANAGE_TEAM", True), ("HP29", MGR, "MANAGE_TEAM", False), ("HP30", ADM, "MANAGE_INVOICES", True),
                            ("HP31", BED, "MANAGE_INVOICES", False), ("HP32", BED, "MANAGE_RECEIPTS", True), ("HP33", KEU, "MANAGE_RECEIPTS", False),
                            ("HP34", MGR, "APPROVE_RECEIPTS", True), ("HP35", ADM, "APPROVE_RECEIPTS", False)]:
    sql = f"select public.has_perm('{perm}')" + ("" if exp else " is false")
    case(cid, "HELPERS", f"has_perm('{perm}') voor {usr.split('.')[1].split('@')[0]} = {str(exp).lower()}", usr, "check", sql, False, True, 1)
case("HP36", "HELPERS", "geen overload my_restaurant_id(uuid): een gebruiker kan geen restaurant_id meegeven", "postgres", "check",
     "select to_regprocedure('public.my_restaurant_id(uuid)') is null and to_regprocedure('public.my_role(uuid)') is null", True)
case("HP37", "HELPERS", "my_restaurant_id() levert geen ander restaurant via select * (hele users-tabel eigen rij) ", OWNER, "check",
     f"select (select count(*) from public.users where restaurant_id <> public.my_restaurant_id()) = 0", True)
case("HP38", "HELPERS", "search_path vast op my_role()", "postgres", "check",
     "select coalesce((select exists (select 1 from unnest(proconfig) c where c like 'search_path=%') from pg_proc where proname='my_role' and pronamespace='public'::regnamespace and proconfig is not null), false)", False, True, 1)
case("HP39", "HELPERS", "search_path vast op has_perm()", "postgres", "check",
     "select coalesce((select exists (select 1 from unnest(proconfig) c where c like 'search_path=%') from pg_proc where proname='has_perm' and pronamespace='public'::regnamespace and proconfig is not null), false)", False, True, 1)
case("HP40", "HELPERS", "search_path vast op role_has_permission()", "postgres", "check",
     "select coalesce((select exists (select 1 from unnest(proconfig) c where c like 'search_path=%') from pg_proc where proname='role_has_permission' and pronamespace='public'::regnamespace and proconfig is not null), false)", False, True, 1)
case("HP41", "HELPERS", "my_restaurant_id/my_role/has_perm zijn SECURITY DEFINER; role_has_permission is dat NIET", "postgres", "check",
     """select (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('my_restaurant_id','my_role','has_perm') and prosecdef) = 3
        and not coalesce((select prosecdef from pg_proc where pronamespace='public'::regnamespace and proname='role_has_permission'), true)""", False, True, 1)
# EXECUTE-rechten
case("HP42", "HELPERS", "PUBLIC heeft geen EXECUTE op de vier helpers", "postgres", "check",
     "select not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.pronamespace='public'::regnamespace and p.proname in ('my_restaurant_id','my_role','has_perm','role_has_permission') and a.grantee = 0)", False, True, 1)
case("HP43", "HELPERS", "anon heeft geen EXECUTE op de vier helpers", "postgres", "check",
     "select not (has_function_privilege('anon','public.my_restaurant_id()','EXECUTE') or has_function_privilege('anon','public.my_role()','EXECUTE') or has_function_privilege('anon','public.has_perm(text)','EXECUTE') or has_function_privilege('anon','public.role_has_permission(text,text)','EXECUTE'))", False, True, 1)
case("HP44", "HELPERS", "authenticated en service_role hebben EXECUTE op de vier helpers", "postgres", "check",
     "select bool_and(has_function_privilege(r, f, 'EXECUTE')) from unnest(array['authenticated','service_role']) r, unnest(array['public.my_restaurant_id()','public.my_role()','public.has_perm(text)','public.role_has_permission(text,text)']) f", False, True, 1)
case("HP45", "HELPERS", "anon kan my_restaurant_id() niet aanroepen (permission denied)", "anon", "check", "select public.my_restaurant_id() is null", True, False, 1)
case("HP46", "HELPERS", "anon kan has_perm() niet aanroepen", "anon", "check", "select public.has_perm('VIEW_DASHBOARD') is false", False, False, 1)
case("HP47", "HELPERS", "rls_auto_enable() ongewijzigd (zelfde ACL: PUBLIC + owner, event_trigger)", "postgres", "check",
     "select coalesce((select prorettype = 'event_trigger'::regtype and prosecdef from pg_proc where proname='rls_auto_enable'), true)", True)
# search_path-misbruik: een gebruiker zet een eigen tijdelijke tabel 'users' neer die naar restaurant B wijst
case("HP48", "HELPERS", "search_path-aanval: tijdelijke nep-users-tabel kan my_restaurant_id() niet omleiden", BED, "check",
     f"select public.my_restaurant_id() = '{RA}'", False, True, 1,
     "vóór stap 1 geeft de functie het restaurant uit de nep-tabel (B) terug",
     setup=f"create temp table users (id uuid, restaurant_id uuid, role text, is_active boolean); grant all on pg_temp.users to authenticated; insert into pg_temp.users values ('{A(13)}','{RB}','owner',true)")
case("HP49", "HELPERS", "search_path-aanval: nep-tabel kan my_role() niet omleiden (bediening blijft bediening)", BED, "check",
     "select public.my_role() = 'bediening'", False, True, 1, "nieuwe functie bestaat nog niet vóór stap 1",
     setup=f"create temp table users (id uuid, restaurant_id uuid, role text, is_active boolean); grant all on pg_temp.users to authenticated; insert into pg_temp.users values ('{A(13)}','{RB}','owner',true)")
case("HP50", "HELPERS", "dagafsluitingen van B blijven onleesbaar voor A, ook mét nep-users-tabel", OWNER, "select",
     f"select 1 from daily_closings where restaurant_id='{RB}'", True, False, 1, "vóór stap 1 leest A via de nep-tabel de dagafsluitingen van B",
     setup=f"create temp table users (id uuid, restaurant_id uuid, role text, is_active boolean); grant all on pg_temp.users to authenticated; insert into pg_temp.users values ('{A(10)}','{RB}','owner',true)")

# ---------------------------------------------------------------- STAP 2 (H3 restaurants + H8a rechten)
RS_ALL = "select count(*) from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%'"
case("RS07", "RESTAURANT", "gedeactiveerde gebruiker leest eigen restaurant", INA, "select", f"select 1 from restaurants where id='{RA}'", True, False, 2, "policy gebruikt my_restaurant_id() (H9)")
case("RS08", "RESTAURANT", "actieve owner leest eigen restaurant (naam voor facturen/mails)", OWNER, "select", f"select name from restaurants where id='{RA}'", True)
case("RS09", "RESTAURANT", "B-owner leest restaurant van A niet", em("b", "owner"), "select", f"select 1 from restaurants where id='{RA}'", False)
case("RS10", "RESTAURANT", "restaurants heeft precies één policy: SELECT 'restaurants read own'", "postgres", "check",
     "select (select count(*) from pg_policies where schemaname='public' and tablename='restaurants') = 1 and exists (select 1 from pg_policies where schemaname='public' and tablename='restaurants' and policyname='restaurants read own' and cmd='SELECT')", False, True, 2)
case("RS11", "RESTAURANT", "service_role kan restaurant nog wijzigen (toekomstig platformbeheer, nu niet gebruikt)", "service_role", "dml", f"update restaurants set name=name where id='{RA}'", True)
case("RS12", "RESTAURANT", "service_role leest restaurants (ping-supabase)", "service_role", "select", "select id from restaurants limit 1", True)
case("RS13", "RESTAURANT", "owner kan geen restaurant aanmaken", OWNER, "dml", "insert into restaurants (name) values ('Nieuw')", False)
case("RS14", "RESTAURANT", "owner wijzigt restaurantnaam van eigen restaurant (bestaat niet in de app)", OWNER, "dml", f"update restaurants set name='x' where id='{RA}'", True, False, 2, "zelfde als RS01, nu expliciet als regressiecheck app-gedrag")
case("PR20", "PRIVILEGES", "authenticated heeft op GEEN enkele tabel TRUNCATE/TRIGGER/REFERENCES", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and has_table_privilege('authenticated', c.oid, 'truncate,trigger,references'))", False, True, 2)
case("PR21", "PRIVILEGES", "service_role heeft op GEEN enkele tabel TRUNCATE/TRIGGER/REFERENCES", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and has_table_privilege('service_role', c.oid, 'truncate,trigger,references'))", False, True, 2)
case("PR22", "PRIVILEGES", "anon heeft op GEEN enkele tabel enig recht", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger'))", False, True, 2)
case("PR23", "PRIVILEGES", "anon heeft op GEEN enkele sequence enig recht", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='S' and (case when c.relkind='S' then has_sequence_privilege('anon', c.oid, 'usage,select,update') end))", True)
case("PR24", "PRIVILEGES", "authenticated behoudt SELECT/INSERT/UPDATE/DELETE op alle tabellen behalve restaurants, users en de drie logtabellen", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and c.relname not in ('restaurants','users','activity_log','audit_log','domain_events') and not (has_table_privilege('authenticated', c.oid, 'select') and has_table_privilege('authenticated', c.oid, 'insert') and has_table_privilege('authenticated', c.oid, 'update') and has_table_privilege('authenticated', c.oid, 'delete')))", True)
case("PR25", "PRIVILEGES", "service_role behoudt SELECT/INSERT/UPDATE/DELETE op ALLE tabellen", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and not (has_table_privilege('service_role', c.oid, 'select') and has_table_privilege('service_role', c.oid, 'insert') and has_table_privilege('service_role', c.oid, 'update') and has_table_privilege('service_role', c.oid, 'delete')))", True)
case("PR26", "PRIVILEGES", "authenticated heeft op restaurants alleen SELECT", "postgres", "check",
     "select has_table_privilege('authenticated','public.restaurants','select') and not has_table_privilege('authenticated','public.restaurants','insert,update,delete')", False, True, 2)
case("PR27", "PRIVILEGES", "standaardrechten voor nieuwe tabellen bevatten geen TRUNCATE/TRIGGER/REFERENCES voor anon/authenticated/service_role", "postgres", "check",
     "select not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a where d.defaclnamespace='public'::regnamespace and d.defaclobjtype='r' and a.privilege_type in ('TRUNCATE','TRIGGER','REFERENCES') and a.grantee in (select oid from pg_roles where rolname in ('anon','authenticated','service_role')))", True)
case("PR28", "PRIVILEGES", "elke tabel in public heeft nog RLS aan na stap 2", "postgres", "check",
     "select not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname not like '\\_%' and not c.relrowsecurity)", True)

# ---------------------------------------------------------------- STAP 3 (H2 users)
SECOND_OWNER = f"insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','tweede owner','owner');"
case("US01", "USERS", "authenticated heeft geen INSERT/UPDATE/DELETE-recht op users", "postgres", "check",
     "select not has_table_privilege('authenticated','public.users','insert,update,delete') and has_table_privilege('authenticated','public.users','select')", False, True, 3)
case("US02", "USERS", "users heeft exact twee policies, beide SELECT (own profile + team)", "postgres", "check",
     "select (select count(*) from pg_policies where schemaname='public' and tablename='users') = 2 and not exists (select 1 from pg_policies where schemaname='public' and tablename='users' and cmd <> 'SELECT')", False, True, 3)
case("US03", "USERS", "triggers users_guard en users_keep_owner bestaan (constraint trigger is deferrable)", "postgres", "check",
     "select exists (select 1 from pg_trigger where tgname='users_guard' and not tgisinternal) and exists (select 1 from pg_trigger where tgname='users_keep_owner' and tgdeferrable and tginitdeferred)", False, True, 3)
case("US04", "USERS", "service_role mag id van een gebruiker NIET wijzigen", "service_role", "dml",
     f"update users set id='{ORPH}' where id='{A(14)}'", True, False, 3)
case("US05", "USERS", "service_role mag rol van een gewone gebruiker wijzigen (legitieme server-flow)", "service_role", "dml",
     f"update users set role='manager' where id='{A(13)}'", True)
case("US06", "USERS", "service_role mag een gewone gebruiker deactiveren", "service_role", "dml",
     f"update users set is_active=false where id='{A(14)}'", True)
case("US07", "USERS", "service_role mag de LAATSTE owner niet degraderen", "service_role", "dml",
     f"update users set role='manager' where id='{A(10)}'", True, False, 3)
case("US08", "USERS", "service_role mag een owner degraderen als er een tweede actieve owner is", "service_role", "dml",
     f"update users set role='manager' where id='{A(10)}'", True, True, 0, "", setup=SECOND_OWNER)
case("US09", "USERS", "service_role mag een owner deactiveren als er een tweede actieve owner is", "service_role", "dml",
     f"update users set is_active=false where id='{A(10)}'", True, True, 0, "", setup=SECOND_OWNER)
case("US10", "USERS", "tweede owner is gedeactiveerd: de eerste owner is dan nog de laatste actieve → niet te deactiveren", "service_role", "dml",
     f"update users set is_active=false where id='{A(10)}'", True, False, 3, "", setup=SECOND_OWNER.replace("'owner');", "'owner'); update users set is_active=false where id='" + ORPH + "';"))
case("US11", "USERS", "service_role mag alle owners in één statement niet wegzetten (ook niet gelijktijdig)", "service_role", "dml",
     f"update users set is_active=false where restaurant_id='{RA}' and role='owner'", True, False, 3)
case("US12", "USERS", "restaurant verwijderen (cascade) blijft mogelijk voor service_role ondanks owner-vangnet", "service_role", "dml",
     f"delete from restaurants where id='{RC}'", True)
case("US13", "USERS", "gedeactiveerde owner verwijderen mag (er blijft een actieve owner)", "service_role", "dml",
     f"delete from users where id='{ORPH}'", True, True, 0, "", setup=SECOND_OWNER.replace("'owner');", "'owner'); update users set is_active=false where id='" + ORPH + "';"))
case("US14", "USERS", "service_role kan profiel van een nieuwe gebruiker aanmaken (invite-flow)", "service_role", "dml",
     f"insert into users (id, restaurant_id, full_name, role) values ('{ORPH}','{RA}','Nieuw','keuken')", True)
case("US15", "USERS", "A-owner kan via eigen verbinding geen rol van B-gebruiker wijzigen (privilege + RLS)", OWNER, "dml",
     f"update users set role='keuken' where id='{B(13)}'", False)
case("US16", "USERS", "gedeactiveerde gebruiker leest eigen profiel (middleware moet 'inactief' kunnen zien)", INA, "select",
     "select is_active from users where id = auth.uid()", True)


# ---------------------------------------------------------------- REKENINGEN / BONNEN / GOEDKEURINGEN (H4a, stap 7)
REPL = lambda sql: "set local session_replication_role = replica; " + sql + " set local session_replication_role = origin;"
TAB_INV_EMPTY = REPL(f"update open_tabs set status='invoiced' where id='{A(203)}';")
RC_CHAIN = (f"insert into companies (id, restaurant_id, name) values ('{u('d', 100)}','{RC}','C-bedrijf'); "
            f"insert into open_tabs (id, restaurant_id, company_id) values ('{u('d', 200)}','{RC}','{u('d', 100)}'); "
            f"insert into receipts (id, restaurant_id, open_tab_id, status) values ('{u('d', 300)}','{RC}','{u('d', 200)}','linked'); "
            f"insert into receipt_lines (receipt_id, description, unit_price, line_total) values ('{u('d', 300)}','x',1,1); "
            "")
RC_CHAIN_LOCK = REPL(f"update receipts set status='locked' where id='{u('d', 300)}'; update open_tabs set status='invoiced' where id='{u('d', 200)}'; update receipts set status='locked' where id='{u('d', 300)}';")
TAB_INS = lambda st: f"insert into open_tabs (restaurant_id, company_id, status) values ('{RA}','{A(100)}','{st}')"
RCP_INS = lambda st, tab: f"insert into receipts (restaurant_id, open_tab_id, status, total) values ('{RA}',{('null' if tab is None else repr(tab))},'{st}',5)"
LINE_INS = lambda rid: f"insert into receipt_lines (receipt_id, description, unit_price, line_total) values ('{rid}','extra',1,1)"
APR_INS = lambda rid, extra_cols="", extra_vals="": f"insert into approvals (receipt_id, company_id, method{extra_cols}) values ('{rid}','{A(100)}','pin'{extra_vals})"
H = "REKENINGEN"
# -- rekeningen (open_tabs)
case("H401", H, "bediening opent een rekening (legitiem)", BED, "dml", TAB_INS("open"), True)
case("H402", H, "owner maakt direct een gesloten rekening aan", OWNER, "dml", TAB_INS("closed"), True, False, 7)
case("H403", H, "owner maakt direct een gefactureerde rekening aan", OWNER, "dml", TAB_INS("invoiced"), True, False, 7)
case("H404", H, "service_role maakt direct een gefactureerde rekening aan (geen bypass)", SVC, "dml", TAB_INS("invoiced"), True, False, 7)
case("H405", H, "keuken leest rekeningen (D1: geen leestoegang)", KEU, "select", f"select 1 from open_tabs where restaurant_id='{RA}'", True, False, 7, "besluit D1")
case("H406", H, "keuken opent een rekening", KEU, "dml", TAB_INS("open"), True, False, 7)
case("H407", H, "keuken wijzigt een rekening", KEU, "dml", f"update open_tabs set table_number='9' where id='{A(200)}'", True, False, 7)
case("H408", H, "keuken verwijdert een open lege rekening", KEU, "dml", f"delete from open_tabs where id='{A(204)}'", True, False, 7)
case("H409", H, "administratie factureert gesloten rekening (closed → invoiced, legitiem)", ADM, "dml", f"update open_tabs set status='invoiced' where id='{A(201)}'", True)
case("H410", H, "owner factureert gesloten rekening (legitiem)", OWNER, "dml", f"update open_tabs set status='invoiced' where id='{A(201)}'", True)
case("H411", H, "bediening factureert gesloten rekening (geen MANAGE_INVOICES)", BED, "dml", f"update open_tabs set status='invoiced' where id='{A(201)}'", True, False, 7)
case("H412", H, "owner springt van open direct naar invoiced", OWNER, "dml", f"update open_tabs set status='invoiced' where id='{A(200)}'", True, False, 7)
case("H413", H, "owner heropent een gefactureerde rekening naar closed", OWNER, "dml", f"update open_tabs set status='closed' where id='{A(202)}'", True, False, 7)
case("H414", H, "owner zet gesloten rekening terug naar open", OWNER, "dml", f"update open_tabs set status='open' where id='{A(201)}'", True, False, 7)
case("H415", H, "owner wijzigt tafelnummer van gefactureerde rekening", OWNER, "dml", f"update open_tabs set table_number='9' where id='{A(202)}'", True, False, 7)
case("H416", H, "postgres wijzigt een gefactureerde rekening (geen bypass)", "postgres", "dml", f"update open_tabs set table_number='9' where id='{A(202)}'", True, False, 7)
case("H417", H, "owner wijzigt tafelnummer van gesloten rekening (route staat dit toe)", OWNER, "dml", f"update open_tabs set table_number='9' where id='{A(201)}'", True)
case("H418", H, "owner sluit open rekening (open → closed, legitiem)", OWNER, "dml", f"update open_tabs set status='closed', closed_at=now() where id='{A(200)}'", True)
case("H419", H, "service_role sluit een rekening (service_role heeft geen rekeningovergangen)", SVC, "dml", f"update open_tabs set status='closed' where id='{A(200)}'", True, False, 7)
case("H420", H, "owner verwijdert gefactureerde lege rekening", OWNER, "dml", f"delete from open_tabs where id='{A(203)}'", True, False, 7, setup=TAB_INV_EMPTY)
case("H421", H, "postgres verwijdert gefactureerde lege rekening (geen bypass)", "postgres", "dml", f"delete from open_tabs where id='{A(203)}'", True, False, 7, setup=TAB_INV_EMPTY)
case("H422", H, "owner verwijdert open lege rekening (legitiem)", OWNER, "dml", f"delete from open_tabs where id='{A(204)}'", True)
case("H423", H, "gedeactiveerde gebruiker sluit een rekening", INA, "dml", f"update open_tabs set status='closed' where id='{A(200)}'", True, False, 7, "bevinding 11 / D9")
case("H424", H, "gedeactiveerde gebruiker opent een rekening", INA, "dml", TAB_INS("open"), True, False, 7, "bevinding 11 / D9")
case("H425", H, "anon leest rekeningen", "anon", "select", "select 1 from open_tabs", False)
case("H426", H, "A-owner opent rekening in restaurant B", OWNER, "dml", f"insert into open_tabs (restaurant_id, status) values ('{RB}','open')", False)
# -- bonnen (receipts)
case("H430", H, "bediening koppelt een nieuwe bon aan een open rekening (legitiem)", BED, "dml", RCP_INS("linked", A(200)), True)
case("H431", H, "owner maakt direct een bon met status pending_approval", OWNER, "dml", RCP_INS("pending_approval", A(200)), True, False, 7)
case("H432", H, "owner maakt direct een bon met status approved", OWNER, "dml", RCP_INS("approved", A(200)), True, False, 7)
case("H433", H, "service_role maakt direct een vergrendelde bon (geen bypass)", SVC, "dml", RCP_INS("locked", A(200)), True, False, 7)
case("H434", H, "bon aan een gesloten rekening koppelen", OWNER, "dml", RCP_INS("linked", A(201)), True, False, 7, "route: alleen open rekening")
case("H435", H, "bon aan een gefactureerde rekening koppelen", OWNER, "dml", RCP_INS("linked", A(202)), True, False, 7)
case("H436", H, "bon zonder rekening (draft) aanmaken blijft kunnen", OWNER, "dml", RCP_INS("draft", None), True)
case("H437", H, "keuken leest bonnen", KEU, "select", f"select 1 from receipts where restaurant_id='{RA}'", True, False, 7, "besluit D1")
case("H438", H, "keuken maakt een bon", KEU, "dml", RCP_INS("linked", A(200)), True, False, 7)
case("H439", H, "manager keurt goed: pending_approval → approved", MGR, "dml", f"update receipts set status='approved' where id='{A(301)}'", True)
case("H440", H, "administratie (geen APPROVE_RECEIPTS) vergrendelt bon in wacht", ADM, "dml", f"update receipts set status='locked' where id='{A(301)}'", True, False, 7)
case("H441", H, "manager wijst af: pending_approval → linked", MGR, "dml", f"update receipts set status='linked' where id='{A(301)}'", True)
case("H442", H, "bediening wijst af: pending_approval → linked", BED, "dml", f"update receipts set status='linked' where id='{A(301)}'", True, False, 7)
case("H443", H, "owner zet vergrendelde bon terug naar linked", OWNER, "dml", f"update receipts set status='linked' where id='{A(302)}'", True, False, 7)
case("H444", H, "owner zet vergrendelde bon terug naar pending_approval", OWNER, "dml", f"update receipts set status='pending_approval' where id='{A(302)}'", True, False, 7)
case("H445", H, "manager vergrendelt een goedgekeurde bon (approved → locked)", MGR, "dml", f"update receipts set status='locked' where id='{A(303)}'", True)
case("H446", H, "owner zet goedgekeurde bon terug naar linked", OWNER, "dml", f"update receipts set status='linked' where id='{A(303)}'", True, False, 7)
case("H447", H, "owner wijzigt notitie van goedgekeurde bon", OWNER, "dml", f"update receipts set notes='x' where id='{A(303)}'", True, False, 7)
case("H448", H, "owner wijzigt notitie van bon in wacht op goedkeuring", OWNER, "dml", f"update receipts set notes='x' where id='{A(301)}'", True, False, 7)
case("H449", H, "owner wijzigt totaal van bon in wacht op goedkeuring", OWNER, "dml", f"update receipts set total=1 where id='{A(301)}'", True, False, 7)
case("H450", H, "owner wijzigt totaal van vergrendelde bon", OWNER, "dml", f"update receipts set total=1 where id='{A(302)}'", True, False, 7)
case("H451", H, "postgres wijzigt totaal van vergrendelde bon (geen bypass)", "postgres", "dml", f"update receipts set total=1 where id='{A(302)}'", True, False, 7)
case("H452", H, "service_role zet bon in wacht op approved (publieke link mag alleen locked of linked)", SVC, "dml", f"update receipts set status='approved' where id='{A(301)}'", True, False, 7)
case("H453", H, "service_role zet linked bon op pending_approval", SVC, "dml", f"update receipts set status='pending_approval' where id='{A(300)}'", True, False, 7)
case("H454", H, "service_role verwijdert vergrendelde bon", SVC, "dml", f"delete from receipts where id='{A(302)}'", True, False, 7, setup="delete from invoice_lines where receipt_id='%s'" % A(302))
case("H455", H, "postgres verwijdert vergrendelde bon (geen bypass)", "postgres", "dml", f"delete from receipts where id='{A(302)}'", True, False, 7, setup="delete from invoice_lines where receipt_id='%s'" % A(302))
case("H456", H, "owner verwijdert bon in wacht op goedkeuring", OWNER, "dml", f"delete from receipts where id='{A(301)}'", True, False, 7)
case("H457", H, "owner verwijdert goedgekeurde bon", OWNER, "dml", f"delete from receipts where id='{A(303)}'", True, False, 7)
case("H458", H, "bediening verwijdert gewone bon met regels (legitiem, cascade naar regels)", BED, "dml", f"delete from receipts where id='{A(300)}'", True)
case("H459", H, "bon met afgewezen goedkeuring verwijderen blijft kunnen (cascade naar goedkeuring)", OWNER, "dml", f"delete from receipts where id='{A(300)}'", True,
     setup=REPL(f"insert into approvals (receipt_id, company_id, method, status) values ('{A(300)}','{A(100)}','pin','rejected');"))
case("H460", H, "bediening wijzigt bon op gefactureerde rekening", BED, "dml", f"update receipts set notes='x' where id='{A(300)}'", True, False, 7, setup=REPL(f"update receipts set open_tab_id='{A(202)}' where id='{A(300)}';"))
case("H461", H, "bediening verwijdert bon op gefactureerde rekening", BED, "dml", f"delete from receipts where id='{A(300)}'", True, False, 7, setup=REPL(f"update receipts set open_tab_id='{A(202)}' where id='{A(300)}';"))
case("H462", H, "bon verhuist naar een gesloten rekening", OWNER, "dml", f"update receipts set open_tab_id='{A(201)}' where id='{A(300)}'", True, False, 7)
case("H463", H, "bon verhuist naar een andere open rekening", OWNER, "dml", f"update receipts set open_tab_id='{A(204)}' where id='{A(300)}'", True)
case("H464", H, "owner zet linked bon terug naar draft (vrije status, geen regel)", OWNER, "dml", f"update receipts set status='draft' where id='{A(300)}'", True)
case("H465", H, "gedeactiveerde gebruiker dient bon in voor goedkeuring", INA, "dml", f"update receipts set status='pending_approval' where id='{A(300)}'", True, False, 7, "bevinding 11 / D9")
case("H466", H, "anon leest bonnen", "anon", "select", "select 1 from receipts", False)
# -- bonregels (receipt_lines)
case("H470", H, "bediening voegt regel toe aan linked bon (legitiem)", BED, "dml", LINE_INS(A(300)), True)
case("H471", H, "regel toevoegen aan bon in wacht op goedkeuring", OWNER, "dml", LINE_INS(A(301)), True, False, 7)
case("H472", H, "regel toevoegen aan vergrendelde bon", OWNER, "dml", LINE_INS(A(302)), True, False, 7)
case("H473", H, "service_role voegt regel toe aan vergrendelde bon (geen bypass)", SVC, "dml", LINE_INS(A(302)), True, False, 7)
case("H474", H, "postgres voegt regel toe aan vergrendelde bon (geen bypass)", "postgres", "dml", LINE_INS(A(302)), True, False, 7)
case("H475", H, "owner verwijdert regel van linked bon rechtstreeks (geen policy; app doet dit nooit)", OWNER, "dml", f"delete from receipt_lines where id='{A(310)}'", True, False, 7)
case("H476", H, "owner wijzigt regel van linked bon rechtstreeks (geen policy; app doet dit nooit)", OWNER, "dml", f"update receipt_lines set unit_price=1 where id='{A(310)}'", True, False, 7)
case("H477", H, "postgres wijzigt regel van linked bon (kan nog: ouder is linked)", "postgres", "dml", f"update receipt_lines set unit_price=1 where id='{A(310)}'", True)
case("H478", H, "postgres wijzigt regel van vergrendelde bon", "postgres", "dml", f"update receipt_lines set unit_price=1 where id='{A(311)}'", True, False, 7)
case("H479", H, "postgres verwijdert regel van vergrendelde bon", "postgres", "dml", f"delete from receipt_lines where id='{A(311)}'", True, False, 7)
case("H480", H, "regel verhuist van linked bon naar vergrendelde bon", "postgres", "dml", f"update receipt_lines set receipt_id='{A(302)}' where id='{A(310)}'", True, False, 7)
case("H481", H, "keuken leest bonregels", KEU, "select", f"select 1 from receipt_lines where receipt_id='{A(300)}'", True, False, 7, "besluit D1")
case("H482", H, "manager leest bonregels", MGR, "select", f"select 1 from receipt_lines where receipt_id='{A(300)}'", True)
case("H483", H, "A-owner voegt regel toe aan bon van restaurant B", OWNER, "dml", LINE_INS(B(300)), False)
# -- goedkeuringen (approvals)
case("H490", H, "bediening vraagt goedkeuring aan: pending-record toevoegen (legitiem)", BED, "dml", APR_INS(A(300)), True)
case("H491", H, "goedkeuring direct als rejected aanmaken", OWNER, "dml", APR_INS(A(300), ", status", ",'rejected'"), True, False, 7)
case("H492", H, "goedkeuring aanmaken met goedkeurder al ingevuld", OWNER, "dml", APR_INS(A(300), ", approved_by", ",'ik'"), True, False, 7)
case("H493", H, "keuken maakt een goedkeuring", KEU, "dml", APR_INS(A(300)), True, False, 7)
case("H494", H, "manager handelt goedkeuring af (pending → approved)", MGR, "dml", f"update approvals set status='approved', approved_by='M', approved_at=now() where id='{A(400)}'", True)
case("H495", H, "owner handelt goedkeuring af (pending → approved)", OWNER, "dml", f"update approvals set status='approved', approved_by='O', approved_at=now() where id='{A(400)}'", True)
case("H496", H, "bediening handelt goedkeuring af (geen APPROVE_RECEIPTS)", BED, "dml", f"update approvals set status='approved', approved_by='B', approved_at=now() where id='{A(400)}'", True, False, 7)
case("H497", H, "administratie handelt goedkeuring af (geen APPROVE_RECEIPTS)", ADM, "dml", f"update approvals set status='rejected' where id='{A(400)}'", True, False, 7)
case("H498", H, "service_role wijst af via publieke link (pending → rejected + reden)", SVC, "dml", f"update approvals set status='rejected', approved_by='Klant', approved_at=now(), metadata='{{\"reason\":\"x\"}}' where id='{A(400)}'", True)
case("H499", H, "service_role laat goedkeuring verlopen (pending → expired)", SVC, "dml", f"update approvals set status='expired' where id='{A(400)}'", True)
case("H500", H, "service_role vult goedkeurder in zonder status te wijzigen", SVC, "dml", f"update approvals set approved_by='x' where id='{A(400)}'", True, False, 7)
case("H501", H, "service_role wijzigt de methode van een goedkeuring", SVC, "dml", f"update approvals set method='pin' where id='{A(400)}'", True, False, 7)
case("H502", H, "service_role hangt goedkeuring aan een andere bon", SVC, "dml", f"update approvals set receipt_id='{A(300)}' where id='{A(400)}'", True, False, 7)
case("H503", H, "manager wijzigt afgehandelde goedkeuring", MGR, "dml", f"update approvals set approved_by='x' where id='{A(401)}'", True, False, 7)
case("H504", H, "postgres wijzigt afgehandelde goedkeuring (geen bypass)", "postgres", "dml", f"update approvals set approved_by='x' where id='{A(401)}'", True, False, 7)
case("H505", H, "service_role draait afgehandelde goedkeuring om (approved → rejected)", SVC, "dml", f"update approvals set status='rejected' where id='{A(401)}'", True, False, 7)
case("H506", H, "owner verwijdert een goedkeuring rechtstreeks", OWNER, "dml", f"delete from approvals where id='{A(400)}'", True, False, 7)
case("H507", H, "service_role verwijdert een goedkeuring rechtstreeks", SVC, "dml", f"delete from approvals where id='{A(400)}'", True, False, 7)
case("H508", H, "postgres verwijdert een goedkeuring rechtstreeks", "postgres", "dml", f"delete from approvals where id='{A(401)}'", True, False, 7)
case("H509", H, "manager leest goedkeuringen", MGR, "select", f"select 1 from approvals where receipt_id='{A(301)}'", True)
case("H510", H, "keuken leest goedkeuringen", KEU, "select", f"select 1 from approvals where receipt_id='{A(301)}'", True, False, 7, "besluit D1")
case("H511", H, "gedeactiveerde gebruiker leest goedkeuringen", INA, "select", f"select 1 from approvals where receipt_id='{A(301)}'", True, False, 7, "bevinding 11 / D9")
case("H512", H, "A-owner handelt goedkeuring van restaurant B af", OWNER, "dml", f"update approvals set status='approved' where id='{B(400)}'", False)
case("H513", H, "anon leest goedkeuringen", "anon", "select", "select 1 from approvals", False)
# -- cascade en meerdere stappen
case("H520", H, "restaurant met vergrendelde bon, regel en gefactureerde rekening verwijderen (cascade blijft werken)", "postgres", "dml",
     f"delete from restaurants where id='{RC}'", True, setup=RC_CHAIN + RC_CHAIN_LOCK)
case("H521", H, "zelfde cascade door service_role", SVC, "dml",
     f"delete from restaurants where id='{RC}'", True, setup=RC_CHAIN + RC_CHAIN_LOCK)
case("H522", H, "na het verwijderen van het restaurant zijn rekeningen, bonnen en regels weg", "postgres", "check",
     f"select not exists (select 1 from open_tabs where restaurant_id='{RC}') and not exists (select 1 from receipts where restaurant_id='{RC}') and not exists (select 1 from receipt_lines where receipt_id='{u('d', 300)}')", True,
     setup=RC_CHAIN + RC_CHAIN_LOCK + f" delete from restaurants where id='{RC}';")
# -- vorm van de beveiliging
case("H530", H, "geen 'tenant isolation'-policy meer op de vier tabellen; 13 nieuwe policies; geen delete-policy op receipt_lines/approvals", "postgres", "check",
     "select not exists (select 1 from pg_policies where schemaname='public' and tablename in ('open_tabs','receipts','receipt_lines','approvals') and policyname like 'tenant isolation%') "
     "and (select count(*) from pg_policies where schemaname='public' and tablename in ('open_tabs','receipts','receipt_lines','approvals')) = 13 "
     "and not exists (select 1 from pg_policies where schemaname='public' and tablename in ('receipt_lines','approvals') and cmd in ('ALL','DELETE')) "
     "and not exists (select 1 from pg_policies where schemaname='public' and tablename = 'receipt_lines' and cmd in ('UPDATE')) "
     "and not exists (select 1 from pg_policies where schemaname='public' and tablename in ('open_tabs','receipts','receipt_lines','approvals') and 'public' = any(roles))", False, True, 7)
case("H531", H, "vier guard-triggers actief; functies zijn voor niemand rechtstreeks uitvoerbaar", "postgres", "check",
     "select (select count(*) from pg_trigger where not tgisinternal and tgenabled='O' and tgname in ('receipts_guard','receipt_lines_guard','open_tabs_guard','approvals_guard')) = 4 "
     "and not has_function_privilege('authenticated','public.receipts_guard()','EXECUTE') and not has_function_privilege('service_role','public.approvals_guard()','EXECUTE') "
     "and not has_function_privilege('anon','public.open_tabs_guard()','EXECUTE')", False, True, 7)
case("H532", H, "tabelrechten ongewijzigd (stap 11): authenticated heeft nog DML, service_role nog UPDATE", "postgres", "check",
     "select has_table_privilege('authenticated','public.receipts','DELETE') and has_table_privilege('authenticated','public.approvals','UPDATE') and has_table_privilege('service_role','public.receipts','UPDATE') and has_table_privilege('service_role','public.approvals','UPDATE')", True)
case("H533", H, "bestaande data behouden (restaurant A: 5 rekeningen, 4 bonnen, 2 regels, 2 goedkeuringen)", "postgres", "check",
     f"select (select count(*) from open_tabs where restaurant_id='{RA}') = 5 and (select count(*) from receipts where restaurant_id='{RA}') = 4 and (select count(*) from receipt_lines where receipt_id in (select id from receipts where restaurant_id='{RA}')) = 2 and (select count(*) from approvals where company_id='{A(100)}') = 2", True)

# -- aanscherping approvals_guard (migratie 0022): geen nieuwe/afgewezen regel op goedgekeurde of vergrendelde bon
# Seed: bon 300 linked, 301 pending_approval (goedkeuring 400 pending), 302 locked (401 approved), 303 approved.
PEND_302 = REPL(f"insert into approvals (id, receipt_id, company_id, method) values ('{A(402)}','{A(302)}','{A(100)}','pin');")
PEND_303 = REPL(f"insert into approvals (id, receipt_id, company_id, method) values ('{A(403)}','{A(303)}','{A(100)}','pin');")
U_REJ = lambda i: f"update approvals set status='rejected', approved_by='x', approved_at=now() where id='{A(i)}'"
U_EXP = lambda i: f"update approvals set status='expired' where id='{A(i)}'"
U_APP = lambda i: f"update approvals set status='approved', approved_by='M', approved_at=now() where id='{A(i)}'"
for n, (who, lab) in enumerate([(OWNER, "owner"), (MGR, "manager"), (BED, "bediening"), (SVC, "service_role"), ("postgres", "postgres")]):
    case(f"H54{n}", H, f"{lab} voegt goedkeuringsregel toe aan vergrendelde bon", who, "dml", APR_INS(A(302)), True, False, 7)
    case(f"H55{n}", H, f"{lab} voegt goedkeuringsregel toe aan goedgekeurde bon", who, "dml", APR_INS(A(303)), True, False, 7)
case("H560", H, "manager dient in: goedkeuringsregel op bon in wacht op goedkeuring (legitiem)", MGR, "dml", APR_INS(A(301)), True)
case("H561", H, "service_role voegt goedkeuringsregel toe aan linked bon (legitiem)", SVC, "dml", APR_INS(A(300)), True)
case("H562", H, "owner wijst openstaande regel af op vergrendelde bon", OWNER, "dml", U_REJ(402), True, False, 7, setup=PEND_302)
case("H563", H, "manager wijst openstaande regel af op vergrendelde bon", MGR, "dml", U_REJ(402), True, False, 7, setup=PEND_302)
case("H564", H, "service_role wijst openstaande regel af op vergrendelde bon (geen bypass)", SVC, "dml", U_REJ(402), True, False, 7, setup=PEND_302)
case("H565", H, "postgres wijst openstaande regel af op vergrendelde bon (geen bypass)", "postgres", "dml", U_REJ(402), False)
case("H566", H, "manager laat openstaande regel verlopen op vergrendelde bon", MGR, "dml", U_EXP(402), True, False, 7, setup=PEND_302)
case("H567", H, "service_role laat openstaande regel verlopen op goedgekeurde bon", SVC, "dml", U_EXP(403), True, False, 7, setup=PEND_303)
case("H568", H, "owner wijst openstaande regel af op goedgekeurde bon", OWNER, "dml", U_REJ(403), True, False, 7, setup=PEND_303)
case("H569", H, "manager keurt openstaande regel goed op vergrendelde bon (goedkeur-route, blijft)", MGR, "dml", U_APP(402), True, True, 7, setup=PEND_302)
case("H570", H, "service_role keurt openstaande regel goed op vergrendelde bon (publieke link, blijft)", SVC, "dml", U_APP(402), True, True, 7, setup=PEND_302)
case("H571", H, "service_role keurt openstaande regel goed op goedgekeurde bon (blijft)", SVC, "dml", U_APP(403), True, True, 7, setup=PEND_303)
case("H572", H, "bediening keurt openstaande regel goed op vergrendelde bon (geen APPROVE_RECEIPTS)", BED, "dml", U_APP(402), False, False, 7, setup=PEND_302)
case("H573", H, "service_role wijst af op bon in wacht op goedkeuring (legitiem)", SVC, "dml", U_REJ(400), True)
case("H574", H, "manager wijst af op bon in wacht op goedkeuring (legitiem)", MGR, "dml", U_REJ(400), True)
case("H575", H, "service_role laat verlopen op bon in wacht op goedkeuring (legitiem)", SVC, "dml", U_EXP(400), True)
# -- keten: afwijzen -> opnieuw indienen -> goedkeuren
CH_PEND = REPL(f"update receipts set status='pending_approval' where id='{A(300)}'; insert into approvals (id, receipt_id, company_id, method) values ('{A(404)}','{A(300)}','{A(100)}','qr');")
CH_REJ = REPL(f"update receipts set status='linked' where id='{A(300)}'; insert into approvals (id, receipt_id, company_id, method, status, approved_at) values ('{A(404)}','{A(300)}','{A(100)}','qr','rejected',now());")
CH_PEND2 = REPL(f"update receipts set status='pending_approval' where id='{A(300)}'; insert into approvals (id, receipt_id, company_id, method, status, approved_at) values ('{A(404)}','{A(300)}','{A(100)}','qr','rejected',now()); insert into approvals (id, receipt_id, company_id, method) values ('{A(405)}','{A(300)}','{A(100)}','qr');")
case("H580", H, "keten stap 1: publieke link wijst bon af (bon terug naar linked, regel rejected)", SVC, "dml",
     f"update receipts set status='linked' where id='{A(300)}'; " + U_REJ(404), True, setup=CH_PEND)
case("H581", H, "keten stap 2: bediening dient afgewezen bon opnieuw in (nieuwe regel)", BED, "dml",
     f"update receipts set status='pending_approval' where id='{A(300)}'; " + APR_INS(A(300)), True, setup=CH_REJ)
case("H582", H, "keten stap 3: manager keurt opnieuw ingediende bon goed (na eerdere afwijzing)", MGR, "dml",
     f"update receipts set status='locked' where id='{A(300)}'; " + U_APP(405), True, setup=CH_PEND2)
case("H583", H, "keten stap 4: na goedkeuring geen nieuwe regel meer op de bon", OWNER, "dml",
     APR_INS(A(300)), True, False, 7, setup=CH_PEND2 + REPL(f"update receipts set status='locked' where id='{A(300)}'; update approvals set status='approved', approved_by='M', approved_at=now() where id='{A(405)}';"))
case("H584", H, "keten stap 5: na goedkeuring een nieuwe regel direct als rejected aanmaken (was en blijft geweigerd)", SVC, "dml",
     APR_INS(A(300), ", status", ",'rejected'"), False, setup=CH_PEND2 + REPL(f"update receipts set status='locked' where id='{A(300)}'; update approvals set status='approved', approved_by='M', approved_at=now() where id='{A(405)}';"))
case("H590", H, "approvals_guard bevat beide nieuwe controles; trigger actief; functie niet uitvoerbaar", "postgres", "check",
     "select position('niet meer worden afgewezen of verlopen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0 "
     "and position('geen nieuwe goedkeuring meer krijgen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0 "
     "and (select count(*) from pg_trigger where not tgisinternal and tgenabled='O' and tgname='approvals_guard') = 1 "
     "and not has_function_privilege('authenticated','public.approvals_guard()','EXECUTE') and not has_function_privilege('service_role','public.approvals_guard()','EXECUTE')", False, True, 7)

# -- plan 7b (migratie 0023): afgewezen bon niet factureren. Gedeelde scenariolijst met de app-test.
# Migratie 0023 is voorbereid maar NIET uitgevoerd (besluit 9 okt). Deze cases staan daarom op een eigen stap (99):
# run(n) voor de echte stappen verwacht het gedrag zonder 0023; run(99) toetst een database MET 0023.
STAP_0023 = 99
import json, os
SCEN = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "invoice-block-scenarios.json")))["scenarios"]
def scen_setup(k, sc, close=True):
    """Zet rekening 203 (gesloten) klaar met de bonnen en goedkeuringsgeschiedenis van het scenario.
    Gewone bonnen staan meteen op 203 (triggers uit). Een bon met "moved": true wordt EERST op de open rekening 204
    gezet en daarna ECHT verplaatst naar 203 (triggers aan, dus de guard moet de verplaatsing toestaan);
    daarvoor staat 203 even open. Daarna wordt 203 gesloten. Mislukt de verplaatsing, dan mislukt de hele opzet."""
    moved = any(rc.get("moved") for rc in sc["receipts"])
    sql = REPL(f"update open_tabs set status='open' where id='{A(203)}';") if moved else ""
    pending_moves = []
    for i, rc in enumerate(sc["receipts"]):
        rid = A(7000 + k * 10 + i)
        tab = A(204) if rc.get("moved") else A(203)
        sql += REPL(f"insert into receipts (id, restaurant_id, open_tab_id, status, total) values ('{rid}','{RA}','{tab}','{rc['status']}',5);")
        for j, st in enumerate(rc["approvals"]):
            at = "null" if st == "pending" else f"now() + interval '{j} seconds'"
            sql += REPL(f"insert into approvals (id, receipt_id, company_id, method, status, approved_at) "
                        f"values ('{A(8000 + k * 100 + i * 10 + j)}','{rid}','{A(100)}','qr','{st}',{at});")
        if rc.get("moved"):
            pending_moves.append(rid)
    for rid in pending_moves:   # echte verplaatsing, guards actief
        sql += f"update receipts set open_tab_id='{A(203)}' where id='{rid}'; "
    if moved and close:
        sql += REPL(f"update open_tabs set status='closed' where id='{A(203)}';")
    return sql
INV_TAB = f"update open_tabs set status='invoiced' where id='{A(203)}'"
for k, sc in enumerate(SCEN, start=1):
    blocked = sc["expect"]["rejection"]
    for who, lab, tag in ((OWNER, "owner", "a"), (ADM, "administratie", "b")):
        if blocked:
            # bewijs een weigering MET de juiste reden: een mislukte opzet of andere fout telt niet mee
            case(f"H6{k:02d}{tag}", H, f"7b {sc['id']} {lab} factureert: {sc['title']} -> geweigerd met reden 'afgewezen bon'", who, "check",
                 f"select hardening_test.refused_with({q(INV_TAB)}, 'afgewezen bon')", False, True, STAP_0023, setup=scen_setup(k, sc))
        else:
            case(f"H6{k:02d}{tag}", H, f"7b {sc['id']} {lab} factureert: {sc['title']} -> toegestaan", who, "dml",
                 INV_TAB, True, True, STAP_0023, setup=scen_setup(k, sc))
    if any(rc.get("moved") for rc in sc["receipts"]):
        rid = A(7000 + k * 10)
        case(f"H6{k:02d}m", H, f"7b {sc['id']} de bon is echt verplaatst van open rekening 204 naar 203 (opzet bewijst de verplaatsing)", "postgres", "check",
             f"select (select open_tab_id from receipts where id='{rid}') = '{A(203)}'", True, setup=scen_setup(k, sc, close=False))
# service_role en postgres hebben geen MANAGE_INVOICES (bestaand gedrag, geen bypass): altijd geweigerd, ook zonder afwijzing
for k, sc in enumerate(SCEN, start=1):
    if sc["id"] in ("S04", "S13"):
        for who, lab, tag in ((SVC, "service_role", "c"), ("postgres", "postgres", "d")):
            case(f"H6{k:02d}{tag}", H, f"7b {sc['id']} {lab} zet rekening op invoiced (geen bypass, altijd geweigerd)", who, "dml",
                 INV_TAB, False, setup=scen_setup(k, sc))
case("H690", H, "open_tabs_guard bevat de afwijzingsblokkade; trigger actief; functie niet uitvoerbaar", "postgres", "check",
     "select position('afgewezen bon is nog niet opnieuw goedgekeurd' in pg_get_functiondef('public.open_tabs_guard()'::regprocedure)) > 0 "
     "and (select count(*) from pg_trigger where not tgisinternal and tgenabled='O' and tgname='open_tabs_guard') = 1 "
     "and not has_function_privilege('authenticated','public.open_tabs_guard()','EXECUTE') and not has_function_privilege('service_role','public.open_tabs_guard()','EXECUTE')", False, True, STAP_0023)

# ---------------------------------------------------------------- uitvoer
def b(x): return "null" if x is None else ("true" if x else "false")
print("-- GEGENEREERD door generate_cases.py — niet met de hand bewerken.")
print("truncate hardening_test.cases;")
print("insert into hardening_test.cases (id, category, title, as_user, kind, sql, expect_now, expect_after, step, note, setup) values")
rows = []
for (id_, cat, title, user, kind, sql, now, after, step, note, setup) in cases:
    rows.append(f"  ({q(id_)},{q(cat)},{q(title)},{q(user)},{q(kind)},{q(sql)},{b(now)},{b(after)},{step},{q(note)},{'null' if setup is None else q(setup)})")
print(",\n".join(rows) + ";")

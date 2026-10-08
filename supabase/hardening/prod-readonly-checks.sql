-- ============================================================
-- POLDER — Security Hardening, STAP 0: ALLEEN-LEZEN productiecontrole
-- ============================================================
-- ÉÉN query (één statement) → ÉÉN resultaattabel. Draai in de Supabase SQL Editor
-- (productie) en kopieer het hele resultaat (Copy / Export CSV) terug naar Claude.
--
--   * Alleen SELECT. Wijzigt niets: geen data, geen schema, geen policies, geen grants.
--   * Kolom `niveau`: OK / INFO / WARNING / BLOCKER
--       BLOCKER = hardening-stap kan niet veilig starten zolang dit niet is opgelost/besloten
--       WARNING = bestaande data zou een geplande regel schenden of vraagt een besluit
--   * Draait ook (zonder fouten) op een lege database.
--   * REFERENTIE-FINGERPRINTS (schone keten migraties 0001–0014, lokaal gemeten; productie hoort gelijk te zijn):
--       A04 policies public ........ 6178f1dccb989e83eab539a58f589fef
--       A05 policies storage ....... 556573095b23466d975e1869d7af6889
--       A07 kolommen public ........ b7d294f3d68e254f81422fd867b854bc
--       A08 check-constraints ...... 5c79b05db0e090da5a7f657f036a13ba
--     Afwijking = verschil repo ↔ productie: alleen RAPPORTEREN, niets corrigeren (stap 0-regel).
-- ============================================================

select nr, onderdeel, niveau, detail
from (

-- ---------- A. PRODUCTIE-BASELINE (0.1) ----------
select 'A01' as nr, 'tabellen in public' as onderdeel, 'INFO' as niveau,
  (count(*)::text || ' tabellen: ' || coalesce(string_agg(relname, ', ' order by relname), '-')) as detail
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname not like '\_%'

union all
select 'A02', 'tabellen ZONDER RLS', case when count(*) = 0 then 'OK' else 'BLOCKER' end,
  coalesce(string_agg(relname, ', ' order by relname), 'geen — RLS staat overal aan')
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity and c.relname not like '\_%'

union all
select 'A03', 'policies per tabel (public)', 'INFO',
  coalesce(string_agg(tablename || '=' || n, ', ' order by tablename), 'geen')
from (select tablename, count(*) n from pg_policies where schemaname = 'public' group by tablename) p

union all
select 'A04', 'FINGERPRINT policies (public, excl. email_settings)', 'INFO',
  md5(coalesce(string_agg(tablename || '|' || policyname || '|' || cmd || '|' ||
      coalesce(qual, '') || '|' || coalesce(with_check, ''), E'\n' order by tablename, policyname), ''))
from pg_policies where schemaname = 'public' and tablename <> 'email_settings'

union all
select 'A05', 'FINGERPRINT policies (storage.objects)', 'INFO',
  md5(coalesce(string_agg(policyname || '|' || cmd || '|' ||
      coalesce(qual, '') || '|' || coalesce(with_check, ''), E'\n' order by policyname), ''))
from pg_policies where schemaname = 'storage' and tablename = 'objects'

union all
select 'A06', 'storage-policies (namen)', 'INFO',
  coalesce(string_agg(cmd || ': ' || policyname, '; ' order by policyname), 'geen')
from pg_policies where schemaname = 'storage' and tablename = 'objects'

union all
select 'A07', 'FINGERPRINT kolommen (public, excl. email_settings)', 'INFO',
  md5(coalesce(string_agg(table_name || '.' || column_name || ':' || data_type || ':' ||
      is_nullable || ':' || coalesce(column_default, ''), E'\n' order by table_name, column_name), ''))
from information_schema.columns
where table_schema = 'public' and table_name <> 'email_settings'
  and table_name in (select table_name from information_schema.tables
                     where table_schema = 'public' and table_type = 'BASE TABLE')

union all
select 'A08', 'FINGERPRINT check-constraints (public)', 'INFO',
  md5(coalesce(string_agg(cl.relname || '|' || co.conname || '|' || pg_get_constraintdef(co.oid),
      E'\n' order by cl.relname, co.conname), ''))
from pg_constraint co join pg_class cl on cl.oid = co.conrelid
join pg_namespace n on n.oid = cl.relnamespace
where n.nspname = 'public' and co.contype = 'c' and cl.relname <> 'email_settings'

union all
select 'A09', 'status-check constraints (statuswaarden)', 'INFO',
  coalesce(string_agg(cl.relname || ': ' || pg_get_constraintdef(co.oid), ' || ' order by cl.relname), 'geen')
from pg_constraint co join pg_class cl on cl.oid = co.conrelid
join pg_namespace n on n.oid = cl.relnamespace
where n.nspname = 'public' and co.contype = 'c' and pg_get_constraintdef(co.oid) ilike '%status%'

union all
select 'A10', 'enums in public', 'INFO',
  coalesce(string_agg(t.typname, ', '), 'geen (statussen zijn text + check-constraints)')
from pg_type t join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public' and t.typtype = 'e'

union all
select 'A11', 'triggers in public (niet-intern)', case when count(*) = 0 then 'OK' else 'WARNING' end,
  coalesce(string_agg(c.relname || '.' || t.tgname, ', ' order by c.relname), 'geen')
from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal

union all
select 'A12', 'functies in public (alle) incl. SECURITY DEFINER-vlag en config', 'INFO',
  coalesce(string_agg(p.proname || ' [secdef=' || p.prosecdef || ', config=' ||
      coalesce(p.proconfig::text, 'null') || ', md5(src)=' || md5(p.prosrc) || ']', '; ' order by p.proname), 'geen')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'

union all
select 'A13', 'SECURITY DEFINER-functies zonder vast search_path', case when count(*) = 0 then 'OK' else 'WARNING' end,
  coalesce(string_agg(p.proname, ', '), 'geen')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef and (p.proconfig is null or not exists (
  select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%'))

union all
select 'A14', 'extra indexen/uniques (niet-PK) in public', 'INFO',
  coalesce(string_agg(indexname, ', ' order by indexname), 'geen')
from pg_indexes where schemaname = 'public' and indexname not like '%\_pkey' escape '\'

union all
select 'A15', 'rechten anon op tabellen (INSERT/SELECT/UPDATE/DELETE)',
  case when count(*) = 0 then 'OK' else 'BLOCKER' end,
  coalesce(string_agg(table_name || ':' || privilege_type, ', '), 'geen — anon heeft geen DML-rechten')
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'
  and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')

union all
select 'A16', 'tabellen met TRUNCATE/TRIGGER/REFERENCES voor anon of authenticated', 'INFO',
  count(distinct table_name)::text || ' tabellen (hoort gelijk te zijn aan het aantal tabellen in A01: vóór stap 2/11 hebben alle tabellen deze rechten)'
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated')
  and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')

-- ---------- B. DATA-COMPATIBILITEIT (0.2) ----------
union all
select 'B01', 'users: rol / actief per restaurant', 'INFO',
  coalesce(string_agg(r.name || ' → ' || u.role || (case when u.is_active then '' else ' (INACTIEF)' end) || ' ×' || u.n,
      '; ' order by r.name, u.role), 'geen users')
from (select restaurant_id, role, is_active, count(*) n from users group by 1, 2, 3) u
join restaurants r on r.id = u.restaurant_id

union all
select 'B02', 'users zonder geldig restaurant', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from users u where not exists (select 1 from restaurants r where r.id = u.restaurant_id)

union all
select 'B03', 'users zonder bijbehorend auth-account', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from users u where not exists (select 1 from auth.users a where a.id = u.id)

union all
select 'B04', 'users met onbekende rol', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from users where role not in ('owner', 'manager', 'administratie', 'bediening', 'keuken')

union all
select 'B05', 'restaurants (overzicht)', 'INFO',
  coalesce(string_agg(r.name || ' [' || left(r.id::text, 8) || '] users=' ||
      (select count(*) from users u where u.restaurant_id = r.id), '; ' order by r.name), 'geen restaurants')
from restaurants r

union all
select 'B06', 'OWNER-INTEGRITEIT: restaurants zonder ACTIEVE owner', case when count(*) = 0 then 'OK' else 'BLOCKER' end,
  coalesce(string_agg(r.name, ', '), 'geen')
from restaurants r
where not exists (select 1 from users u where u.restaurant_id = r.id and u.role = 'owner' and u.is_active)

union all
select 'B07', 'OWNER-INTEGRITEIT: restaurants met meerdere actieve owners', 'INFO',
  coalesce(string_agg(r.name || ' ×' || n, ', '), 'geen')
from restaurants r
join (select restaurant_id, count(*) n from users where role = 'owner' and is_active group by 1) o
  on o.restaurant_id = r.id and o.n > 1

union all
select 'B08', 'OWNER-INTEGRITEIT: gedeactiveerde owners', 'INFO',
  coalesce(string_agg(r.name || ' ×' || n, ', '), 'geen')
from restaurants r
join (select restaurant_id, count(*) n from users where role = 'owner' and not is_active group by 1) o
  on o.restaurant_id = r.id

union all
select 'B09', 'status open_tabs', 'INFO',
  coalesce(string_agg(status || '=' || n, ', ' order by status), 'leeg') from (select status, count(*) n from open_tabs group by 1) s
union all
select 'B10', 'status receipts', 'INFO',
  coalesce(string_agg(status || '=' || n, ', ' order by status), 'leeg') from (select status, count(*) n from receipts group by 1) s
union all
select 'B11', 'status approvals (status/methode)', 'INFO',
  coalesce(string_agg(status || '/' || method || '=' || n, ', ' order by status, method), 'leeg')
from (select status, method, count(*) n from approvals group by 1, 2) s
union all
select 'B12', 'status invoices', 'INFO',
  coalesce(string_agg(status || '=' || n, ', ' order by status), 'leeg') from (select status, count(*) n from invoices group by 1) s
union all
select 'B13', 'payments (aantal / som)', 'INFO', count(*)::text || ' betalingen, som ' || coalesce(sum(amount), 0)::text from payments
union all
select 'B14', 'documents (type)', 'INFO',
  coalesce(string_agg(type || '=' || n, ', ' order by type), 'leeg') from (select type, count(*) n from documents group by 1) s
union all
select 'B15', 'daily_closings', 'INFO', count(*)::text || ' dagafsluitingen' from daily_closings

-- toestandscombinaties (state-machine compatibiliteit)
union all
select 'B20', 'receipts met status approved (nooit gelockt)', case when count(*) = 0 then 'OK' else 'WARNING' end,
  count(*)::text || ' — pad bestaat bij auto_lock=false; geplande state machine moet dit toestaan'
from receipts where status = 'approved'
union all
select 'B21', 'receipts locked zonder goedgekeurde approval', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from receipts r where r.status = 'locked'
  and not exists (select 1 from approvals a where a.receipt_id = r.id and a.status = 'approved')
union all
select 'B22', 'receipts pending_approval zonder pending approval', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from receipts r where r.status = 'pending_approval'
  and not exists (select 1 from approvals a where a.receipt_id = r.id and a.status = 'pending')
union all
select 'B23', 'approvals pending bij bon die niet pending_approval is', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from approvals a join receipts r on r.id = a.receipt_id where a.status = 'pending' and r.status <> 'pending_approval'
union all
select 'B24', 'gefactureerde rekeningen met bonnen die niet in een factuurregel staan', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from receipts r join open_tabs t on t.id = r.open_tab_id
where t.status = 'invoiced' and not exists (select 1 from invoice_lines il where il.receipt_id = r.id)
union all
select 'B25', 'invoices paid met betalingen < totaal', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from invoices i where i.status = 'paid'
  and coalesce((select sum(p.amount) from payments p where p.invoice_id = i.id), 0) < i.total - 0.005
union all
select 'B26', 'invoices NIET paid met betalingen ≥ totaal (app zet dit automatisch op paid)', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from invoices i where i.status <> 'paid' and i.total > 0
  and coalesce((select sum(p.amount) from payments p where p.invoice_id = i.id), 0) >= i.total - 0.005
union all
select 'B27', 'betalingen op draft-facturen', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from payments p join invoices i on i.id = p.invoice_id where i.status = 'draft'
union all
select 'B28', 'betalingen met bedrag ≤ 0', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from payments where amount <= 0
union all
select 'B29', 'D6-indicatie: betaalde facturen zonder ooit "sent" in het activiteitenlogboek', 'INFO',
  count(*)::text || ' (facturen die mogelijk draft → paid zijn gegaan; indicatie, geen bewijs)'
from invoices i where i.status = 'paid'
  and not exists (select 1 from activity_log l where l.target_table = 'invoices' and l.target_id = i.id
                  and l.action ilike '%''sent''%')

-- cross-restaurant relaties (H7)
union all
select 'B30', 'X-restaurant: open_tabs → companies/afdelingen/kostenplaatsen/projecten/contacten',
  case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from open_tabs t
where exists (select 1 from companies c where c.id = t.company_id and c.restaurant_id <> t.restaurant_id)
   or exists (select 1 from departments d join companies c on c.id = d.company_id where d.id = t.department_id and c.restaurant_id <> t.restaurant_id)
   or exists (select 1 from cost_centers d join companies c on c.id = d.company_id where d.id = t.cost_center_id and c.restaurant_id <> t.restaurant_id)
   or exists (select 1 from projects d join companies c on c.id = d.company_id where d.id = t.project_id and c.restaurant_id <> t.restaurant_id)
   or exists (select 1 from contacts d join companies c on c.id = d.company_id where d.id = t.contact_id and c.restaurant_id <> t.restaurant_id)
union all
select 'B31', 'X-restaurant: receipts → open_tabs', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from receipts r join open_tabs t on t.id = r.open_tab_id where t.restaurant_id <> r.restaurant_id
union all
select 'B32', 'X-restaurant: invoices → companies', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from invoices i join companies c on c.id = i.company_id where c.restaurant_id <> i.restaurant_id
union all
select 'B33', 'X-restaurant: invoice_lines → receipts', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from invoice_lines il join invoices i on i.id = il.invoice_id join receipts r on r.id = il.receipt_id
where r.restaurant_id <> i.restaurant_id
union all
select 'B34', 'X-restaurant: approvals (bon ↔ bedrijf)', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from approvals a join receipts r on r.id = a.receipt_id join companies c on c.id = a.company_id
where r.restaurant_id <> c.restaurant_id
union all
select 'B35', 'X-restaurant: configurations/workflow_rules → companies', case when x.n = 0 then 'OK' else 'BLOCKER' end, x.n::text
from (select ((select count(*) from configurations c1 join companies c on c.id = c1.company_id where c.restaurant_id <> c1.restaurant_id) +
              (select count(*) from workflow_rules w1 join companies c on c.id = w1.company_id where c.restaurant_id <> w1.restaurant_id)) as n) x
union all
select 'B36', 'X-restaurant: documents → gerelateerd record (invoices)', case when count(*) = 0 then 'OK' else 'BLOCKER' end, count(*)::text
from documents d join invoices i on d.related_table = 'invoices' and i.id = d.related_id where i.restaurant_id <> d.restaurant_id
union all
select 'B37', 'X-restaurant: verwijzingen naar users van een ander restaurant', case when x.n = 0 then 'OK' else 'BLOCKER' end, x.n::text
from (select (
   (select count(*) from receipts t join users u on u.id = t.created_by where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from daily_closings t join users u on u.id = t.closed_by where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from daily_closings t join users u on u.id = t.reopened_by where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from activity_log t join users u on u.id = t.user_id where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from domain_events t join users u on u.id = t.published_by where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from audit_log t join users u on u.id = t.changed_by where u.restaurant_id <> t.restaurant_id) +
   (select count(*) from notifications t join users u on u.id = t.recipient_user_id where u.restaurant_id <> t.restaurant_id)) as n) x

-- cross-company relaties (H7: afdeling/kostenplaats/project/contact moeten bij het bedrijf van de rekening horen)
union all
select 'B40', 'X-bedrijf: open_tabs-afdeling/kostenplaats/project/contact hoort bij ander bedrijf', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from open_tabs t
where t.company_id is not null and (
      exists (select 1 from departments d where d.id = t.department_id and d.company_id <> t.company_id)
   or exists (select 1 from cost_centers d where d.id = t.cost_center_id and d.company_id <> t.company_id)
   or exists (select 1 from projects d where d.id = t.project_id and d.company_id <> t.company_id)
   or exists (select 1 from contacts d where d.id = t.contact_id and d.company_id <> t.company_id))
union all
select 'B41', 'X-bedrijf: open_tabs met afdeling/kostenplaats/project/contact maar ZONDER bedrijf', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from open_tabs t where t.company_id is null
  and (t.department_id is not null or t.cost_center_id is not null or t.project_id is not null or t.contact_id is not null)
union all
select 'B42', 'X-bedrijf: kostenplaats → afdeling van ander bedrijf', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from cost_centers cc join departments d on d.id = cc.department_id where d.company_id <> cc.company_id

-- approval settings
union all
select 'B50', 'approval_settings (aantal / methodes)', 'INFO',
  coalesce(string_agg(coalesce(method, 'geen') || '=' || n, ', ' order by method), 'leeg')
from (select method, count(*) n from approval_settings group by 1) s
union all
select 'B51', 'approval_settings met pin_hash (GEHEIM, nu leesbaar voor elke rol)', case when count(*) = 0 then 'OK' else 'WARNING' end,
  count(*)::text || ' rijen met pin_hash; ' ||
  (select count(*) from approval_settings where pin_hash is not null and pin_salt is null)::text || ' zonder salt; ' ||
  (select count(*) from approval_settings where method = 'pin' and pin_hash is null)::text || ' methode pin zonder hash'
from approval_settings where pin_hash is not null
union all
select 'B52', 'approval_settings: notify_email ingesteld', 'INFO', count(*)::text from approval_settings where notify_email is not null

-- integraties
union all
select 'B60', 'integration_plugins (rijen / met config)', case when count(*) = 0 then 'OK' else 'WARNING' end,
  count(*)::text || ' rijen, waarvan ' || count(*) filter (where config is not null) || ' met config (ingebruik?)'
from integration_plugins

-- storage
union all
select 'B70', 'storage: bestanden in bucket documents', 'INFO', count(*)::text from storage.objects where bucket_id = 'documents'
union all
select 'B71', 'storage: paden die NIET <restaurant-uuid>/invoices/<uuid>.pdf zijn', case when count(*) = 0 then 'OK' else 'WARNING' end,
  coalesce(string_agg(name, ', '), 'geen')
from storage.objects where bucket_id = 'documents'
  and name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/invoices/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$'
union all
select 'B72', 'storage: eerste map is géén bestaand restaurant', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from storage.objects o where o.bucket_id = 'documents'
  and not exists (select 1 from restaurants r where r.id::text = split_part(o.name, '/', 1))
union all
select 'B73', 'documents.storage_path zonder bestand in storage', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from documents d where not exists (select 1 from storage.objects o where o.bucket_id = 'documents' and o.name = d.storage_path)
union all
select 'B74', 'storage-bestanden zonder documents-rij', 'INFO', count(*)::text
from storage.objects o where o.bucket_id = 'documents' and not exists (select 1 from documents d where d.storage_path = o.name)
union all
select 'B75', 'documents met hetzelfde storage_path (pad-hergebruik)', case when count(*) = 0 then 'OK' else 'WARNING' end, count(*)::text
from (select storage_path from documents group by 1 having count(*) > 1) d

-- ---------- C. ACCOUNTS / D4 (0.8) ----------
union all
select 'C01', 'D4: account stuctech@gmail.com', 'INFO',
  coalesce(string_agg('id=' || a.id || ', aangemaakt=' || coalesce(a.created_at::date::text, '?') || ', laatste login=' ||
      coalesce(a.last_sign_in_at::text, 'nooit') || ', bevestigd=' || (a.email_confirmed_at is not null) ||
      ', geblokkeerd=' || (a.banned_until is not null and a.banned_until > now()) ||
      ', profiel=' || coalesce('JA rol=' || u.role || ' actief=' || u.is_active || ' restaurant=' || r.name, 'NEE (wees)'),
      '; '), 'bestaat niet')
from auth.users a left join users u on u.id = a.id left join restaurants r on r.id = u.restaurant_id
where lower(a.email) = 'stuctech@gmail.com'
union all
select 'C02', 'auth-accounts ZONDER profiel (wezen)', case when count(*) = 0 then 'OK' else 'WARNING' end,
  count(*)::text || ': ' || coalesce(string_agg(coalesce(a.email, a.id::text) || ' (' || coalesce(a.created_at::date::text, '?') || ')', ', '), '-')
from auth.users a where not exists (select 1 from users u where u.id = a.id)
union all
select 'C03', 'alle accounts (e-mail → rol/actief/restaurant)', 'INFO',
  coalesce(string_agg(a.email || ' → ' || coalesce(u.role || (case when u.is_active then '' else ' INACTIEF' end) || ' @ ' || r.name, 'GEEN PROFIEL'), '; ' order by a.email), 'geen')
from auth.users a left join users u on u.id = a.id left join restaurants r on r.id = u.restaurant_id

) checks
order by nr;

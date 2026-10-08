-- ============================================================
-- Script: baseline-controle (ALLEEN LEZEN — geen migratie, wijzigt niets)
-- Draai in de Supabase SQL Editor om te controleren dat de database
-- overeenkomt met de baseline (migratie 0014, architecture.md sectie 13).
-- ============================================================

-- 1. RLS moet op ALLE tabellen in public aan staan (verwacht: geen rijen met rls_aan = false)
select c.relname as tabel, c.relrowsecurity as rls_aan
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
order by c.relname;

-- 2. De vier policies op users (verwacht: precies deze vier, geen INSERT)
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'users'
order by policyname;

-- 3. my_restaurant_id (verwacht: prosecdef = true, proconfig = null — ongewijzigd t.o.v. productie)
select proname, prosecdef, proconfig
from pg_proc
where proname = 'my_restaurant_id';

-- 4. Aantal policies per tabel (verwacht: 1 per restaurant-tabel; users = 4)
select tablename, count(*) as aantal_policies
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;

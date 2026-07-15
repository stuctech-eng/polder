-- ============================================================
-- Migratie 0012: GRANT-rechten voor service_role (kritieke bugfix)
-- Zie docs/architecture.md v1.36 voor de volledige diagnose.
--
-- Oorzaak: migratie 0004 (GRANT-fix, v1.5) gaf alleen 'authenticated' de
-- benodigde tabelrechten. De service-role client (gebruikt voor de publieke
-- goedkeuringsflow, Fase C) omzeilt RLS wel, maar heeft nog steeds gewone
-- GRANT-rechten nodig — dat is een aparte laag. Zonder deze migratie: alle
-- tabellen aangemaakt ná migratie 0004 zijn ontoegankelijk voor service_role.
-- ============================================================

grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

alter default privileges in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;

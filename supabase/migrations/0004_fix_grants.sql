-- ============================================================
-- Migratie 0004: GRANT-rechten herstellen (bugfix)
-- Oorzaak: "Automatically expose new tables" stond uit bij projectaanmaak
-- (bewuste keuze, sectie 7.2 beveiliging). Dat voorkwam echter niet alleen
-- ongewenste blootstelling, maar blokkeerde ook de basistoegangsrechten
-- (GRANT) die de 'authenticated' rol nodig heeft om bij tabellen te mogen —
-- los van RLS, dat bepaalt WELKE rijen zichtbaar zijn, niet OF je erbij mag.
-- Resultaat: 42501 permission denied, ondanks correcte RLS-policies.
-- ============================================================

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Zorgt dat toekomstige nieuwe tabellen automatisch de juiste rechten krijgen
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;

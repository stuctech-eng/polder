-- ============================================================
-- Script: testaccount aanmaken (GEEN migratie — niet automatisch draaien,
-- handmatig te gebruiken wanneer nodig, meerdere keren herhaalbaar met
-- andere waarden). Zie README.md "Testaccount aanmaken" voor uitleg.
-- ============================================================

-- Optie A — volledig nieuw account (pas e-mail/wachtwoord/restaurant_id aan):
insert into auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'JOUWADRES+NAAM@gmail.com',
  crypt('KiesEenWachtwoord', gen_salt('bf')),
  now(),
  now(),
  now()
);

insert into users (id, restaurant_id, full_name, role)
select id, 'JOUW-RESTAURANT-ID', 'Naam van tester', 'bediening'
from auth.users
where email = 'JOUWADRES+NAAM@gmail.com';

-- ------------------------------------------------------------
-- Optie B — een bestaand "wees"-account (mislukte uitnodiging, zie v1.24)
-- alsnog bruikbaar maken, i.p.v. een nieuw account aan te maken:
-- ------------------------------------------------------------

-- Stap 1: wachtwoord zetten
-- update auth.users
-- set encrypted_password = crypt('KiesEenWachtwoord', gen_salt('bf')),
--     email_confirmed_at = now()
-- where email = 'BESTAAND-WEES-ADRES@gmail.com';

-- Stap 2: profiel koppelen aan restaurant
-- insert into users (id, restaurant_id, full_name, role)
-- select id, 'JOUW-RESTAURANT-ID', 'Naam van tester', 'bediening'
-- from auth.users
-- where email = 'BESTAAND-WEES-ADRES@gmail.com';

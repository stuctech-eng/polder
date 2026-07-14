-- ============================================================
-- Script: testaccount aanmaken (GEEN migratie — niet automatisch draaien,
-- handmatig te gebruiken wanneer nodig, meerdere keren herhaalbaar met
-- andere waarden). Zie README.md "Testaccount aanmaken" voor uitleg.
--
-- BELANGRIJK (v1.27): auth.users vereist lege strings ('') i.p.v. null voor
-- confirmation_token/recovery_token/email_change*-kolommen, anders lijkt het
-- account te bestaan (wachtwoord-reset/uitnodigen werkt) maar faalt inloggen
-- zelf stilzwijgend met "Inloggen mislukt". Onderstaande insert bevat de fix.
-- ============================================================

-- Optie A — volledig nieuw account (pas e-mail/wachtwoord/restaurant_id aan):
insert into auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  created_at, updated_at,
  confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current,
  raw_app_meta_data, raw_user_meta_data,
  is_super_admin, is_sso_user
)
values (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'JOUWADRES+NAAM@gmail.com',
  crypt('KiesEenWachtwoord', gen_salt('bf')),
  now(),
  now(), now(),
  '', '',
  '', '', '',
  '{"provider":"email","providers":["email"]}',
  '{}',
  false, false
);

insert into users (id, restaurant_id, full_name, role)
select id, 'JOUW-RESTAURANT-ID', 'Naam van tester', 'bediening'
from auth.users
where email = 'JOUWADRES+NAAM@gmail.com';

-- ------------------------------------------------------------
-- Optie B — een bestaand "wees"-account (mislukte uitnodiging, zie v1.24)
-- alsnog bruikbaar maken, i.p.v. een nieuw account aan te maken.
-- LET OP (v1.27): dit werkt alleen als het account daadwerkelijk nog bestaat
-- (auth-aanmaak kan bij een mislukte uitnodiging alsnog teruggedraaid zijn —
-- controleer eerst met een select vóór je hierop vertrouwt).
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

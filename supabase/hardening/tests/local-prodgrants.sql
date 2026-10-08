-- Alleen LOKAAL: nabootsing van de Supabase-standaardrechten zoals de productie-audit liet zien
-- (authenticated heeft DML + TRUNCATE/TRIGGER/REFERENCES; anon alleen REFERENCES/TRIGGER/TRUNCATE).
grant usage on schema public, storage, auth to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all tables in schema storage to authenticated, service_role;
grant select on auth.users to authenticated, service_role;
grant all on all tables in schema public to anon;
revoke select, insert, update, delete on all tables in schema public from anon;
grant execute on all functions in schema public to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;

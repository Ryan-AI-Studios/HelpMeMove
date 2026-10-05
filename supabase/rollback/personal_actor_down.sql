-- Drops only the auth.users trigger and function from 20261005104500_personal_actor.sql.
-- This file stays outside supabase/migrations so the CLI does not apply it.
-- It does not drop core or identity_map.

drop trigger if exists provision_personal_actor on auth.users;
drop function if exists core.provision_personal_actor();

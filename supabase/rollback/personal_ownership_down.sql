-- Drops only the schemas created by 20261005092638_personal_ownership.sql.
-- This file stays outside supabase/migrations so the CLI does not apply it.
drop schema if exists identity_map cascade;
drop schema if exists core cascade;

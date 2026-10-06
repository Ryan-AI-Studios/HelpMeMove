-- Drops only objects created by 20261005220000_owned_document_copy.sql.
-- This file stays outside supabase/migrations so the CLI does not apply it.
-- Do not drop core.reject_ownership_change(), extensions.pgcrypto,
-- core.programs, core.sessions, or the auth trigger.

drop function if exists public.copy_owned_document(text, uuid, text, text);
drop trigger if exists program_documents_reject_ownership_change on core.program_documents;
drop trigger if exists program_documents_reject_document_change on core.program_documents;
drop trigger if exists session_documents_reject_ownership_change on core.session_documents;
drop trigger if exists session_documents_reject_document_change on core.session_documents;
drop function if exists core.reject_document_change();
drop table if exists core.program_documents;
drop table if exists core.session_documents;

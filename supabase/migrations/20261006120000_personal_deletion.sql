-- Deletes one personal actor and leaves a tombstone the client cannot read.
-- Does not grant BYPASSRLS and does not add a tombstone policy.

create table core.deletion_tombstones (
  actor_id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  deleted_at timestamptz not null default pg_catalog.now(),
  primary key (actor_id, subject_id)
);

alter table core.deletion_tombstones enable row level security;
alter table core.deletion_tombstones force row level security;

revoke all on table core.deletion_tombstones from public;
revoke all on table core.deletion_tombstones from anon;
revoke all on table core.deletion_tombstones from authenticated;

create function public.delete_personal_actor()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid;
  copied_tenant uuid;
  copied_subject uuid;
  removed integer;
begin
  actor := auth.uid();
  if actor is null then
    return 'unchanged';
  end if;

  select actor_subjects.tenant_id, actor_subjects.subject_id
    into copied_tenant, copied_subject
  from identity_map.actor_subjects as actor_subjects
  where actor_subjects.actor_id = actor;

  if copied_tenant is null or copied_subject is null then
    return 'unchanged';
  end if;

  insert into core.deletion_tombstones (actor_id, tenant_id, subject_id)
  values (actor, copied_tenant, copied_subject);

  delete from core.sessions as sessions
  where sessions.tenant_id = copied_tenant
    and sessions.subject_id = copied_subject;

  delete from core.programs as programs
  where programs.tenant_id = copied_tenant
    and programs.subject_id = copied_subject;

  delete from core.profiles as profiles
  where profiles.tenant_id = copied_tenant
    and profiles.subject_id = copied_subject;

  delete from core.program_documents as program_documents
  where program_documents.tenant_id = copied_tenant
    and program_documents.subject_id = copied_subject;

  delete from core.session_documents as session_documents
  where session_documents.tenant_id = copied_tenant
    and session_documents.subject_id = copied_subject;

  delete from identity_map.actor_subjects as actor_subjects
  where actor_subjects.actor_id = actor;
  get diagnostics removed = row_count;
  if removed = 0 then
    raise exception 'actor map delete changed zero rows';
  end if;

  delete from core.subjects as subjects
  where subjects.tenant_id = copied_tenant
    and subjects.id = copied_subject;
  get diagnostics removed = row_count;
  if removed = 0 then
    raise exception 'subject delete changed zero rows';
  end if;

  delete from core.tenants as tenants
  where tenants.id = copied_tenant;
  get diagnostics removed = row_count;
  if removed = 0 then
    raise exception 'tenant delete changed zero rows';
  end if;

  delete from auth.refresh_tokens as refresh_tokens
  where refresh_tokens.user_id = actor::text;

  delete from auth.sessions as sessions
  where sessions.user_id = actor;

  delete from auth.identities as identities
  where identities.user_id = actor;

  delete from auth.users as users
  where users.id = actor;
  get diagnostics removed = row_count;
  if removed = 0 then
    raise exception 'auth user delete changed zero rows';
  end if;

  return 'deleted';
end;
$$;

revoke all on function public.delete_personal_actor() from public;
revoke all on function public.delete_personal_actor() from anon;
grant execute on function public.delete_personal_actor() to authenticated;

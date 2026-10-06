-- Owned document copy for program_records and workout_records.
-- Health JSON is stored on these tables, not in marker.
-- Rollback does not drop extensions.pgcrypto.

create extension if not exists pgcrypto with schema extensions;

create table core.program_documents (
  id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  document jsonb not null,
  document_sha256 text not null,
  primary key (tenant_id, id),
  constraint program_documents_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

create table core.session_documents (
  id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  document jsonb not null,
  document_sha256 text not null,
  primary key (tenant_id, id),
  constraint session_documents_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

alter table core.program_documents enable row level security;
alter table core.program_documents force row level security;
alter table core.session_documents enable row level security;
alter table core.session_documents force row level security;

create function core.reject_document_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.document is distinct from old.document
     or new.document_sha256 is distinct from old.document_sha256 then
    raise exception 'document columns cannot change'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function core.reject_document_change() from public;

create trigger program_documents_reject_ownership_change
  before update on core.program_documents
  for each row
  execute function core.reject_ownership_change();

create trigger program_documents_reject_document_change
  before update on core.program_documents
  for each row
  execute function core.reject_document_change();

create trigger session_documents_reject_ownership_change
  before update on core.session_documents
  for each row
  execute function core.reject_ownership_change();

create trigger session_documents_reject_document_change
  before update on core.session_documents
  for each row
  execute function core.reject_document_change();

create policy program_documents_select on core.program_documents
  for select
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = program_documents.tenant_id
        and scope.subject_id = program_documents.subject_id
    )
  );

create policy program_documents_insert on core.program_documents
  for insert
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = program_documents.tenant_id
        and scope.subject_id = program_documents.subject_id
    )
  );

create policy program_documents_update on core.program_documents
  for update
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = program_documents.tenant_id
        and scope.subject_id = program_documents.subject_id
    )
  )
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = program_documents.tenant_id
        and scope.subject_id = program_documents.subject_id
    )
  );

create policy program_documents_delete on core.program_documents
  for delete
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = program_documents.tenant_id
        and scope.subject_id = program_documents.subject_id
    )
  );

create policy session_documents_select on core.session_documents
  for select
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = session_documents.tenant_id
        and scope.subject_id = session_documents.subject_id
    )
  );

create policy session_documents_insert on core.session_documents
  for insert
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = session_documents.tenant_id
        and scope.subject_id = session_documents.subject_id
    )
  );

create policy session_documents_update on core.session_documents
  for update
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = session_documents.tenant_id
        and scope.subject_id = session_documents.subject_id
    )
  )
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = session_documents.tenant_id
        and scope.subject_id = session_documents.subject_id
    )
  );

create policy session_documents_delete on core.session_documents
  for delete
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = session_documents.tenant_id
        and scope.subject_id = session_documents.subject_id
    )
  );

revoke all on table core.program_documents from public, anon, authenticated;
revoke all on table core.session_documents from public, anon, authenticated;

create function public.copy_owned_document(
  p_entity text,
  p_event_id uuid,
  p_document_text text,
  p_document_sha256 text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_subject_id uuid;
  v_expected_sha text;
  v_existing_sha text;
begin
  if auth.uid() is null then
    return 'unavailable';
  end if;

  select scope.tenant_id, scope.subject_id
    into v_tenant_id, v_subject_id
  from core.current_scope() as scope;

  if not found then
    return 'unavailable';
  end if;

  if p_entity is distinct from 'program_records'
     and p_entity is distinct from 'workout_records' then
    return 'rejected';
  end if;

  if p_event_id is null then
    return 'rejected';
  end if;

  if p_document_text is null or p_document_text = '' then
    return 'rejected';
  end if;

  if pg_catalog.octet_length(p_document_text) > 1048576 then
    return 'rejected';
  end if;

  if p_document_sha256 is null
     or p_document_sha256 !~ '^[0-9a-f]{64}$' then
    return 'rejected';
  end if;

  if not (p_document_text is json) then
    return 'rejected';
  end if;

  if position(E'\\u0000' in p_document_text) > 0 then
    return 'rejected';
  end if;

  v_expected_sha := pg_catalog.lower(
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(p_document_text, 'UTF8'),
        'sha256'
      ),
      'hex'
    )
  );

  if p_document_sha256 is distinct from v_expected_sha then
    return 'rejected';
  end if;

  if p_entity = 'program_records' then
    select documents.document_sha256
      into v_existing_sha
    from core.program_documents as documents
    where documents.tenant_id = v_tenant_id
      and documents.id = p_event_id;

    if found then
      if v_existing_sha is not distinct from v_expected_sha then
        return 'confirmed';
      end if;
      return 'rejected';
    end if;

    insert into core.program_documents (
      id,
      tenant_id,
      subject_id,
      document,
      document_sha256
    )
    values (
      p_event_id,
      v_tenant_id,
      v_subject_id,
      cast(p_document_text as pg_catalog.jsonb),
      v_expected_sha
    );

    return 'confirmed';
  end if;

  select documents.document_sha256
    into v_existing_sha
  from core.session_documents as documents
  where documents.tenant_id = v_tenant_id
    and documents.id = p_event_id;

  if found then
    if v_existing_sha is not distinct from v_expected_sha then
      return 'confirmed';
    end if;
    return 'rejected';
  end if;

  insert into core.session_documents (
    id,
    tenant_id,
    subject_id,
    document,
    document_sha256
  )
  values (
    p_event_id,
    v_tenant_id,
    v_subject_id,
    cast(p_document_text as pg_catalog.jsonb),
    v_expected_sha
  );

  return 'confirmed';
end;
$$;

revoke all on function public.copy_owned_document(text, uuid, text, text) from public;
revoke all on function public.copy_owned_document(text, uuid, text, text) from anon;
grant execute on function public.copy_owned_document(text, uuid, text, text) to authenticated;

-- Rollback. Do not apply these statements in this file.
-- drop function if exists public.copy_owned_document(text, uuid, text, text);
-- drop trigger if exists program_documents_reject_ownership_change on core.program_documents;
-- drop trigger if exists program_documents_reject_document_change on core.program_documents;
-- drop trigger if exists session_documents_reject_ownership_change on core.session_documents;
-- drop trigger if exists session_documents_reject_document_change on core.session_documents;
-- drop function if exists core.reject_document_change();
-- drop table if exists core.program_documents;
-- drop table if exists core.session_documents;
-- Do not drop core.reject_ownership_change(), extensions.pgcrypto,
-- core.programs, core.sessions, or the auth trigger.
-- Do not drop the pgcrypto extension.

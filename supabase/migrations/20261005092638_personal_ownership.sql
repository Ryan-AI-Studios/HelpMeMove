-- Personal ownership only. kind is personal. marker values are synthetic.
-- sec-10.3 is open, so these fields stay server-readable. No crypto.
-- Remote projects stay with track 0049. This migration does not link a host.

create schema core;
create schema identity_map;

revoke all on schema core from public;
revoke all on schema identity_map from public;
grant usage on schema core to authenticated;

create table core.tenants (
  id uuid primary key,
  kind text not null,
  constraint tenants_kind_personal check (kind = 'personal')
);

create table core.subjects (
  id uuid not null,
  tenant_id uuid not null,
  primary key (tenant_id, id),
  constraint subjects_tenant_fk foreign key (tenant_id) references core.tenants (id)
);

create table identity_map.actor_subjects (
  actor_id uuid primary key,
  tenant_id uuid not null,
  subject_id uuid not null,
  constraint actor_subjects_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

create index actor_subjects_tenant_subject_idx
  on identity_map.actor_subjects (tenant_id, subject_id);

create table core.profiles (
  id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  marker jsonb not null,
  primary key (tenant_id, id),
  constraint profiles_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

create table core.programs (
  id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  marker jsonb not null,
  primary key (tenant_id, id),
  constraint programs_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

create table core.sessions (
  id uuid not null,
  tenant_id uuid not null,
  subject_id uuid not null,
  marker jsonb not null,
  primary key (tenant_id, id),
  constraint sessions_subject_fk
    foreign key (tenant_id, subject_id) references core.subjects (tenant_id, id)
);

create index profiles_tenant_subject_idx on core.profiles (tenant_id, subject_id);
create index programs_tenant_subject_idx on core.programs (tenant_id, subject_id);
create index sessions_tenant_subject_idx on core.sessions (tenant_id, subject_id);

alter table core.tenants enable row level security;
alter table core.tenants force row level security;
alter table core.subjects enable row level security;
alter table core.subjects force row level security;
alter table identity_map.actor_subjects enable row level security;
alter table identity_map.actor_subjects force row level security;
alter table core.profiles enable row level security;
alter table core.profiles force row level security;
alter table core.programs enable row level security;
alter table core.programs force row level security;
alter table core.sessions enable row level security;
alter table core.sessions force row level security;

-- Empty search_path. auth.uid() and identity_map are schema-qualified.
-- The caller cannot pass a tenant id. The row is the one stored for auth.uid().
create function core.current_scope()
returns table (tenant_id uuid, subject_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select actor_subjects.tenant_id, actor_subjects.subject_id
  from identity_map.actor_subjects as actor_subjects
  where actor_subjects.actor_id = auth.uid()
$$;

revoke all on function core.current_scope() from public;
revoke all on function core.current_scope() from anon;
grant execute on function core.current_scope() to authenticated;

create function core.reject_ownership_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.tenant_id is distinct from old.tenant_id
     or new.subject_id is distinct from old.subject_id then
    raise exception 'ownership columns cannot change'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function core.reject_ownership_change() from public;

create trigger profiles_reject_ownership_change
  before update on core.profiles
  for each row
  execute function core.reject_ownership_change();

create trigger programs_reject_ownership_change
  before update on core.programs
  for each row
  execute function core.reject_ownership_change();

create trigger sessions_reject_ownership_change
  before update on core.sessions
  for each row
  execute function core.reject_ownership_change();

-- Table-level UPDATE would cover every column, so marker is granted alone.
-- The column revoke is the explicit denial. The trigger rejects a change
-- even for the table owner.
revoke all on table core.tenants from public, anon, authenticated;
revoke all on table core.subjects from public, anon, authenticated;
revoke all on table identity_map.actor_subjects from public, anon, authenticated;

revoke all on table core.profiles from public, anon, authenticated;
grant select, insert, delete on table core.profiles to authenticated;
grant update (marker) on table core.profiles to authenticated;
revoke update (tenant_id, subject_id) on table core.profiles from authenticated;

revoke all on table core.programs from public, anon, authenticated;
grant select, insert, delete on table core.programs to authenticated;
grant update (marker) on table core.programs to authenticated;
revoke update (tenant_id, subject_id) on table core.programs from authenticated;

revoke all on table core.sessions from public, anon, authenticated;
grant select, insert, delete on table core.sessions to authenticated;
grant update (marker) on table core.sessions to authenticated;
revoke update (tenant_id, subject_id) on table core.sessions from authenticated;

create policy profiles_select on core.profiles
  for select to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = profiles.tenant_id
        and scope.subject_id = profiles.subject_id
    )
  );

create policy profiles_insert on core.profiles
  for insert to authenticated
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = profiles.tenant_id
        and scope.subject_id = profiles.subject_id
    )
  );

create policy profiles_update on core.profiles
  for update to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = profiles.tenant_id
        and scope.subject_id = profiles.subject_id
    )
  )
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = profiles.tenant_id
        and scope.subject_id = profiles.subject_id
    )
  );

create policy profiles_delete on core.profiles
  for delete to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = profiles.tenant_id
        and scope.subject_id = profiles.subject_id
    )
  );

create policy programs_select on core.programs
  for select to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = programs.tenant_id
        and scope.subject_id = programs.subject_id
    )
  );

create policy programs_insert on core.programs
  for insert to authenticated
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = programs.tenant_id
        and scope.subject_id = programs.subject_id
    )
  );

create policy programs_update on core.programs
  for update to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = programs.tenant_id
        and scope.subject_id = programs.subject_id
    )
  )
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = programs.tenant_id
        and scope.subject_id = programs.subject_id
    )
  );

create policy programs_delete on core.programs
  for delete to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = programs.tenant_id
        and scope.subject_id = programs.subject_id
    )
  );

create policy sessions_select on core.sessions
  for select to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = sessions.tenant_id
        and scope.subject_id = sessions.subject_id
    )
  );

create policy sessions_insert on core.sessions
  for insert to authenticated
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = sessions.tenant_id
        and scope.subject_id = sessions.subject_id
    )
  );

create policy sessions_update on core.sessions
  for update to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = sessions.tenant_id
        and scope.subject_id = sessions.subject_id
    )
  )
  with check (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = sessions.tenant_id
        and scope.subject_id = sessions.subject_id
    )
  );

create policy sessions_delete on core.sessions
  for delete to authenticated
  using (
    exists (
      select 1
      from core.current_scope() as scope
      where scope.tenant_id = sessions.tenant_id
        and scope.subject_id = sessions.subject_id
    )
  );

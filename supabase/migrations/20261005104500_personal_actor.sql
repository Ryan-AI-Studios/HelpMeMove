-- Provisions one personal tenant and subject for each new auth user.
-- Does not copy email, name, or provider metadata.
-- Remote hosts and provider redirects stay outside this track.

create function core.provision_personal_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant uuid;
  subject uuid;
begin
  if exists (
    select 1
    from identity_map.actor_subjects
    where actor_subjects.actor_id = new.id
  ) then
    return new;
  end if;

  tenant := pg_catalog.gen_random_uuid();
  subject := pg_catalog.gen_random_uuid();

  insert into core.tenants (id, kind)
  values (tenant, 'personal');

  insert into core.subjects (id, tenant_id)
  values (subject, tenant);

  insert into identity_map.actor_subjects (actor_id, tenant_id, subject_id)
  values (new.id, tenant, subject);

  return new;
end;
$$;

revoke all on function core.provision_personal_actor() from public;
revoke all on function core.provision_personal_actor() from anon;
revoke all on function core.provision_personal_actor() from authenticated;

create trigger provision_personal_actor
  after insert on auth.users
  for each row
  execute function core.provision_personal_actor();

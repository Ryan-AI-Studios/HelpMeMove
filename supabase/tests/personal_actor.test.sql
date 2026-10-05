begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

select ok(
  exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'core'
      and p.proname = 'provision_personal_actor'
      and p.prosecdef
      and exists (
        select 1
        from unnest(p.proconfig) as cfg
        where cfg = 'search_path='
           or cfg = 'search_path=""'
           or cfg = 'search_path=pg_catalog'
      )
  ),
  'provision_personal_actor is security definer with a fixed search path'
);

select has_trigger(
  'auth',
  'users',
  'provision_personal_actor',
  'auth.users provisions a personal actor'
);

select hasnt_column('identity_map', 'actor_subjects', 'email', 'actor map has no email');
select hasnt_column('identity_map', 'actor_subjects', 'name', 'actor map has no name');
select hasnt_column('identity_map', 'actor_subjects', 'phone', 'actor map has no phone');
select hasnt_column('identity_map', 'actor_subjects', 'provider', 'actor map has no provider');

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'authenticated',
  'authenticated',
  'a@example.test',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'authenticated',
  'authenticated',
  'b@example.test',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

select is(
  (select count(*)::int from identity_map.actor_subjects where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'one actor row for A'
);
select is(
  (select count(*)::int
   from core.subjects as subjects
   join identity_map.actor_subjects as actor_subjects
     on actor_subjects.tenant_id = subjects.tenant_id
    and actor_subjects.subject_id = subjects.id
   where actor_subjects.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'one subject for A'
);
select is(
  (select tenants.kind
   from core.tenants as tenants
   join identity_map.actor_subjects as actor_subjects
     on actor_subjects.tenant_id = tenants.id
   where actor_subjects.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'personal',
  'A tenant is personal'
);

delete from auth.users where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'authenticated',
  'authenticated',
  'a@example.test',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

select is(
  (select count(*)::int from identity_map.actor_subjects where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'inserting A again keeps one actor row'
);
select is(
  (select count(*)::int
   from core.subjects as subjects
   join identity_map.actor_subjects as actor_subjects
     on actor_subjects.tenant_id = subjects.tenant_id
    and actor_subjects.subject_id = subjects.id
   where actor_subjects.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'inserting A again keeps one subject'
);

create temp table expected_scope (
  actor_id uuid,
  tenant_id uuid,
  subject_id uuid
);
insert into expected_scope (actor_id, tenant_id, subject_id)
select actor_id, tenant_id, subject_id
from identity_map.actor_subjects
where actor_id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

select is(
  (select count(*)::int from expected_scope as left_scope
   join expected_scope as right_scope
     on left_scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    and right_scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
   where left_scope.tenant_id = right_scope.tenant_id
      or left_scope.subject_id = right_scope.subject_id),
  0,
  'A and B do not share a tenant or subject'
);

set local role anon;
select throws_ok(
  $$select * from identity_map.actor_subjects$$,
  '42501',
  null,
  'anon cannot select the actor map'
);
select throws_ok(
  $$select core.provision_personal_actor()$$,
  '42501',
  null,
  'anon cannot execute provision'
);

set local role authenticated;
select throws_ok(
  $$select * from identity_map.actor_subjects$$,
  '42501',
  null,
  'authenticated cannot select the actor map'
);
select throws_ok(
  $$select core.provision_personal_actor()$$,
  '42501',
  null,
  'authenticated cannot execute provision'
);

reset role;
grant select on expected_scope to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select results_eq(
  $$select tenant_id, subject_id from core.current_scope()$$,
  $$select tenant_id, subject_id from expected_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'A scope matches the map'
);

set local "request.jwt.claim.sub" to 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local "request.jwt.claims" to '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';
select results_eq(
  $$select tenant_id, subject_id from core.current_scope()$$,
  $$select tenant_id, subject_id from expected_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  'B scope matches the map'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

select ok(
  exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'delete_personal_actor'
      and p.prosecdef
      and pg_catalog.pg_get_function_result(p.oid) = 'text'
      and exists (
        select 1
        from unnest(p.proconfig) as cfg
        where cfg = 'search_path='
           or cfg = 'search_path=""'
      )
  ),
  'delete_personal_actor is security definer text with an empty search path'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'authenticated', 'authenticated', 'a@example.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'authenticated', 'authenticated', 'b@example.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'authenticated', 'authenticated', 'c@example.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

create temp table actor_scope (
  actor_id uuid,
  tenant_id uuid,
  subject_id uuid
);
insert into actor_scope (actor_id, tenant_id, subject_id)
select actor_id, tenant_id, subject_id
from identity_map.actor_subjects
where actor_id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
);

insert into core.profiles (id, tenant_id, subject_id, marker)
select '11111111-1111-4111-8111-111111111111', tenant_id, subject_id, '{"marker":"profile"}'::jsonb
from actor_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into core.programs (id, tenant_id, subject_id, marker)
select '22222222-2222-4222-8222-222222222222', tenant_id, subject_id, '{"marker":"program"}'::jsonb
from actor_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into core.sessions (id, tenant_id, subject_id, marker)
select '33333333-3333-4333-8333-333333333333', tenant_id, subject_id, '{"marker":"session"}'::jsonb
from actor_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into core.program_documents (id, tenant_id, subject_id, document, document_sha256)
select '44444444-4444-4444-8444-444444444444', tenant_id, subject_id, '{"doc":"program"}'::jsonb, 'program-sha'
from actor_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into core.session_documents (id, tenant_id, subject_id, document, document_sha256)
select '55555555-5555-4555-8555-555555555555', tenant_id, subject_id, '{"doc":"session"}'::jsonb, 'session-sha'
from actor_scope where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into core.profiles (id, tenant_id, subject_id, marker)
select '66666666-6666-4666-8666-666666666666', tenant_id, subject_id, '{"marker":"other"}'::jsonb
from actor_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

insert into core.programs (id, tenant_id, subject_id, marker)
select 'b1111111-1111-4111-8111-111111111111', tenant_id, subject_id, '{"marker":"b-program"}'::jsonb
from actor_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

insert into core.sessions (id, tenant_id, subject_id, marker)
select 'b2222222-2222-4222-8222-222222222222', tenant_id, subject_id, '{"marker":"b-session"}'::jsonb
from actor_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

insert into core.program_documents (id, tenant_id, subject_id, document, document_sha256)
select 'b3333333-3333-4333-8333-333333333333', tenant_id, subject_id, '{"doc":"b-program"}'::jsonb, 'b-program-sha'
from actor_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

insert into core.session_documents (id, tenant_id, subject_id, document, document_sha256)
select 'b4444444-4444-4444-8444-444444444444', tenant_id, subject_id, '{"doc":"b-session"}'::jsonb, 'b-session-sha'
from actor_scope where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

insert into auth.identities (id, provider_id, user_id, identity_data, provider)
values (
  'b5555555-5555-4555-8555-555555555555',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}'::jsonb,
  'email'
);

insert into auth.sessions (id, user_id)
values (
  'b6666666-6666-4666-8666-666666666666',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into auth.refresh_tokens (token, user_id, revoked)
values (
  'refresh-b',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  false
);

insert into auth.identities (id, provider_id, user_id, identity_data, provider)
values (
  '77777777-7777-4777-8777-777777777777',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}'::jsonb,
  'email'
);

insert into auth.sessions (id, user_id)
values (
  '88888888-8888-4888-8888-888888888888',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

insert into auth.refresh_tokens (token, user_id, revoked)
values (
  'refresh-a',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  false
);

set local role authenticated;
select is(
  public.delete_personal_actor(),
  'unchanged',
  'a null auth uid returns unchanged'
);

reset role;
delete from identity_map.actor_subjects
where actor_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

set local role authenticated;
set local "request.jwt.claim.sub" to 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
set local "request.jwt.claims" to '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
select is(
  public.delete_personal_actor(),
  'unchanged',
  'a missing map row returns unchanged'
);

reset role;
select is(
  (select count(*)::int from core.tenants as tenants
   join actor_scope as scope on scope.tenant_id = tenants.id
   where scope.actor_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  1,
  'a missing map row leaves the tenant'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select is(
  public.delete_personal_actor(),
  'deleted',
  'a copied actor returns deleted'
);

reset role;

select is(
  (select count(*)::int from core.profiles as profiles
   join actor_scope as scope
     on scope.tenant_id = profiles.tenant_id
    and scope.subject_id = profiles.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A profile marker is gone'
);
select is(
  (select count(*)::int from core.programs as programs
   join actor_scope as scope
     on scope.tenant_id = programs.tenant_id
    and scope.subject_id = programs.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A program marker is gone'
);
select is(
  (select count(*)::int from core.sessions as sessions
   join actor_scope as scope
     on scope.tenant_id = sessions.tenant_id
    and scope.subject_id = sessions.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A session marker is gone'
);
select is(
  (select count(*)::int from core.program_documents as documents
   join actor_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A program document is gone'
);
select is(
  (select count(*)::int from core.session_documents as documents
   join actor_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A session document is gone'
);
select is(
  (select count(*)::int from identity_map.actor_subjects
   where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A actor map row is gone'
);
select is(
  (select count(*)::int from core.subjects as subjects
   join actor_scope as scope
     on scope.tenant_id = subjects.tenant_id
    and scope.subject_id = subjects.id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A subject is gone'
);
select is(
  (select count(*)::int from core.tenants as tenants
   join actor_scope as scope on scope.tenant_id = tenants.id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A tenant is gone'
);
select is(
  (select count(*)::int from auth.users where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A auth user is gone'
);
select is(
  (select count(*)::int from auth.identities where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A identity is gone'
);
select is(
  (select count(*)::int from auth.sessions where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A session is gone'
);
select is(
  (select count(*)::int from auth.refresh_tokens where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'A refresh token is gone'
);
select is(
  (select count(*)::int from core.deletion_tombstones
   where actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'the migration owner can see the tombstone'
);
select is(
  (select count(*)::int from core.profiles as profiles
   join actor_scope as scope
     on scope.tenant_id = profiles.tenant_id
    and scope.subject_id = profiles.subject_id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B profile marker remains'
);
select is(
  (select count(*)::int from core.programs as programs
   join actor_scope as scope
     on scope.tenant_id = programs.tenant_id
    and scope.subject_id = programs.subject_id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B program marker remains'
);
select is(
  (select count(*)::int from core.sessions as sessions
   join actor_scope as scope
     on scope.tenant_id = sessions.tenant_id
    and scope.subject_id = sessions.subject_id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B session marker remains'
);
select is(
  (select count(*)::int from core.program_documents as documents
   join actor_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B program document remains'
);
select is(
  (select count(*)::int from core.session_documents as documents
   join actor_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B session document remains'
);
select is(
  (select count(*)::int from identity_map.actor_subjects
   where actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B actor map row remains'
);
select is(
  (select count(*)::int from core.subjects as subjects
   join actor_scope as scope
     on scope.tenant_id = subjects.tenant_id
    and scope.subject_id = subjects.id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B subject remains'
);
select is(
  (select count(*)::int from core.tenants as tenants
   join actor_scope as scope on scope.tenant_id = tenants.id
   where scope.actor_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B tenant remains'
);
select is(
  (select count(*)::int from auth.users where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B auth user remains'
);
select is(
  (select count(*)::int from auth.identities where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B identity remains'
);
select is(
  (select count(*)::int from auth.sessions where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B session remains'
);
select is(
  (select count(*)::int from auth.refresh_tokens where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'B refresh token remains'
);

set local role anon;
select throws_ok(
  $$select public.delete_personal_actor()$$,
  '42501',
  null,
  'anon cannot execute delete_personal_actor'
);

set local role authenticated;
select throws_ok(
  $$select * from core.deletion_tombstones$$,
  '42501',
  null,
  'authenticated cannot select tombstones'
);
select throws_ok(
  $$insert into core.deletion_tombstones (actor_id, tenant_id, subject_id)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501',
  null,
  'authenticated cannot insert a tombstone'
);
select throws_ok(
  $$update core.deletion_tombstones set tenant_id = tenant_id$$,
  '42501',
  null,
  'authenticated cannot update a tombstone'
);
select throws_ok(
  $$delete from core.deletion_tombstones$$,
  '42501',
  null,
  'authenticated cannot delete a tombstone'
);

select * from finish();
rollback;

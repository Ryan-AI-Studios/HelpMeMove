begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

select has_table('core', 'program_documents', 'program_documents exists');
select has_table('core', 'session_documents', 'session_documents exists');

select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'program_documents'),
  'program_documents forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'session_documents'),
  'session_documents forces row level security'
);

select ok(
  exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'copy_owned_document'
      and p.prosecdef
      and exists (
        select 1
        from unnest(p.proconfig) as cfg
        where cfg = 'search_path='
           or cfg = 'search_path=""'
           or cfg = 'search_path=pg_catalog'
      )
  ),
  'copy_owned_document is security definer with a fixed search path'
);
select has_function(
  'core',
  'reject_document_change',
  'reject_document_change exists'
);
select has_function(
  'public',
  'copy_owned_document',
  array['text', 'uuid', 'text', 'text']::name[],
  'copy_owned_document exists'
);

select policies_are(
  'core',
  'program_documents',
  array[
    'program_documents_select',
    'program_documents_insert',
    'program_documents_update',
    'program_documents_delete'
  ]::name[],
  'program_documents has one policy per operation'
);
select policies_are(
  'core',
  'session_documents',
  array[
    'session_documents_select',
    'session_documents_insert',
    'session_documents_update',
    'session_documents_delete'
  ]::name[],
  'session_documents has one policy per operation'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_policies as policies
    where policies.schemaname = 'core'
      and policies.tablename in ('program_documents', 'session_documents')
      and exists (
        select 1
        from unnest(policies.roles) as role_name
        where role_name is distinct from 'public'
      )
  ),
  'document policies name no role other than PUBLIC'
);
select ok(
  (
    select count(*) = 4
       and bool_and(
         coalesce(policies.qual, '') ilike '%core.current_scope()%'
         or coalesce(policies.with_check, '') ilike '%core.current_scope()%'
       )
    from pg_catalog.pg_policies as policies
    where policies.schemaname = 'core'
      and policies.tablename = 'program_documents'
  ),
  'each program_documents policy calls core.current_scope()'
);
select ok(
  (
    select count(*) = 4
       and bool_and(
         coalesce(policies.qual, '') ilike '%core.current_scope()%'
         or coalesce(policies.with_check, '') ilike '%core.current_scope()%'
       )
    from pg_catalog.pg_policies as policies
    where policies.schemaname = 'core'
      and policies.tablename = 'session_documents'
  ),
  'each session_documents policy calls core.current_scope()'
);

select ok(
  not has_table_privilege('authenticated', 'core.program_documents', 'select'),
  'authenticated cannot select program_documents'
);
select ok(
  not has_table_privilege('authenticated', 'core.program_documents', 'insert'),
  'authenticated cannot insert program_documents'
);
select ok(
  not has_table_privilege('authenticated', 'core.session_documents', 'select'),
  'authenticated cannot select session_documents'
);
select ok(
  not has_table_privilege('authenticated', 'core.session_documents', 'insert'),
  'authenticated cannot insert session_documents'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.copy_owned_document(text, uuid, text, text)',
    'execute'
  ),
  'anon cannot execute copy_owned_document'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.copy_owned_document(text, uuid, text, text)',
    'execute'
  ),
  'authenticated can execute copy_owned_document'
);

set local role anon;
select throws_ok(
  $$select public.copy_owned_document(
    'program_records',
    '10101010-1010-4101-8101-101010101010',
    '{"synthetic":true}',
    '0000000000000000000000000000000000000000000000000000000000000000'
  )$$,
  '42501',
  null,
  'anon cannot execute copy_owned_document'
);

set local role authenticated;
select throws_ok(
  $$select * from core.program_documents$$,
  '42501',
  null,
  'authenticated cannot select program_documents'
);
select throws_ok(
  $$select * from core.session_documents$$,
  '42501',
  null,
  'authenticated cannot select session_documents'
);
select throws_ok(
  $$insert into core.program_documents (id, tenant_id, subject_id, document, document_sha256)
    values (
      '15151515-1515-4515-8515-151515151515',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'::jsonb,
      '0000000000000000000000000000000000000000000000000000000000000000'
    )$$,
  '42501',
  null,
  'authenticated cannot insert program_documents'
);
select throws_ok(
  $$insert into core.session_documents (id, tenant_id, subject_id, document, document_sha256)
    values (
      '15151515-1515-4515-8515-151515151515',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'::jsonb,
      '0000000000000000000000000000000000000000000000000000000000000000'
    )$$,
  '42501',
  null,
  'authenticated cannot insert session_documents'
);
reset role;

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
grant select on expected_scope to authenticated;

create temp table copy_doc (
  kind text primary key,
  event_id uuid not null,
  document_text text not null,
  document_sha256 text not null
);
insert into copy_doc (kind, event_id, document_text, document_sha256)
select kind, event_id, document_text,
  lower(encode(extensions.digest(convert_to(document_text, 'UTF8'), 'sha256'), 'hex'))
from (
  values
    (
      'program',
      '10101010-1010-4101-8101-101010101010'::uuid,
      '{"synthetic":true}'
    ),
    (
      'program_other',
      '10101010-1010-4101-8101-101010101010'::uuid,
      '{"synthetic":true,"other":true}'
    ),
    (
      'bad_sha',
      '20202020-2020-4202-8202-202020202020'::uuid,
      '{"synthetic":true}'
    ),
    (
      'invalid_json',
      '30303030-3030-4303-8303-303030303030'::uuid,
      '{not json'
    ),
    (
      'nul_escape',
      '40404040-4040-4404-8404-404040404040'::uuid,
      '{"x":"\u0000"}'
    ),
    (
      'workout',
      '50505050-5050-4505-8505-505050505050'::uuid,
      '{"synthetic":true}'
    )
) as rows (kind, event_id, document_text);
grant select on copy_doc to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';

select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'program'),
    (select document_text from copy_doc where kind = 'program'),
    (select document_sha256 from copy_doc where kind = 'program')
  ),
  'confirmed',
  'RPC insert as authenticated actor is confirmed'
);
reset role;
select is(
  (select count(*)::int
   from core.program_documents as documents
   join expected_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and documents.id = (select event_id from copy_doc where kind = 'program')),
  1,
  'RPC insert writes one program_documents row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'program'),
    (select document_text from copy_doc where kind = 'program'),
    (select document_sha256 from copy_doc where kind = 'program')
  ),
  'confirmed',
  'same text twice is confirmed'
);
reset role;
select is(
  (select count(*)::int
   from core.program_documents as documents
   join expected_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and documents.id = (select event_id from copy_doc where kind = 'program')),
  1,
  'same text twice stores one row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'program_other'),
    (select document_text from copy_doc where kind = 'program_other'),
    (select document_sha256 from copy_doc where kind = 'program_other')
  ),
  'rejected',
  'different sha for the same event_id is rejected'
);
reset role;
select is(
  (select documents.document
   from core.program_documents as documents
   join expected_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and documents.id = (select event_id from copy_doc where kind = 'program')),
  '{"synthetic":true}'::jsonb,
  'different sha leaves the stored document unchanged'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'bad_sha'),
    (select document_text from copy_doc where kind = 'bad_sha'),
    '0000000000000000000000000000000000000000000000000000000000000000'
  ),
  'rejected',
  'bad client sha is rejected'
);
reset role;
select is(
  (select count(*)::int
   from core.program_documents
   where id = (select event_id from copy_doc where kind = 'bad_sha')),
  0,
  'bad client sha writes no row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select lives_ok(
  $$select public.copy_owned_document(
    'program_records',
    '30303030-3030-4303-8303-303030303030',
    '{not json',
    (select document_sha256 from copy_doc where kind = 'invalid_json')
  )$$,
  'invalid JSON text does not error'
);
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'invalid_json'),
    (select document_text from copy_doc where kind = 'invalid_json'),
    (select document_sha256 from copy_doc where kind = 'invalid_json')
  ),
  'rejected',
  'invalid JSON text is rejected'
);
reset role;
select is(
  (select count(*)::int
   from core.program_documents
   where id = (select event_id from copy_doc where kind = 'invalid_json')),
  0,
  'invalid JSON text writes no row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select lives_ok(
  $$select public.copy_owned_document(
    'program_records',
    '40404040-4040-4404-8404-404040404040',
    '{"x":"\u0000"}',
    (select document_sha256 from copy_doc where kind = 'nul_escape')
  )$$,
  'a document containing the six-character escape does not error'
);
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'nul_escape'),
    (select document_text from copy_doc where kind = 'nul_escape'),
    (select document_sha256 from copy_doc where kind = 'nul_escape')
  ),
  'rejected',
  'a document containing the six-character escape is rejected'
);
reset role;
select is(
  (select count(*)::int
   from core.program_documents
   where id = (select event_id from copy_doc where kind = 'nul_escape')),
  0,
  'a document containing the six-character escape writes no row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select is(
  public.copy_owned_document(
    'workout_records',
    (select event_id from copy_doc where kind = 'workout'),
    (select document_text from copy_doc where kind = 'workout'),
    (select document_sha256 from copy_doc where kind = 'workout')
  ),
  'confirmed',
  'workout RPC insert as authenticated actor is confirmed'
);
reset role;
select is(
  (select count(*)::int
   from core.session_documents as documents
   join expected_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and documents.id = (select event_id from copy_doc where kind = 'workout')),
  1,
  'workout RPC insert writes one session_documents row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local "request.jwt.claims" to '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'program_other'),
    (select document_text from copy_doc where kind = 'program_other'),
    (select document_sha256 from copy_doc where kind = 'program_other')
  ),
  'confirmed',
  'second actor copy does not update the first actor'
);
reset role;
select is(
  (select documents.document
   from core.program_documents as documents
   join expected_scope as scope
     on scope.tenant_id = documents.tenant_id
    and scope.subject_id = documents.subject_id
   where scope.actor_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and documents.id = (select event_id from copy_doc where kind = 'program')),
  '{"synthetic":true}'::jsonb,
  'second actor cannot change first actor row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to '';
set local "request.jwt.claims" to '{}';
select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'bad_sha'),
    (select document_text from copy_doc where kind = 'bad_sha'),
    (select document_sha256 from copy_doc where kind = 'bad_sha')
  ),
  'unavailable',
  'a missing actor is unavailable'
);

set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select is(
  public.copy_owned_document(
    'other_records',
    (select event_id from copy_doc where kind = 'bad_sha'),
    (select document_text from copy_doc where kind = 'bad_sha'),
    (select document_sha256 from copy_doc where kind = 'bad_sha')
  ),
  'rejected',
  'an unknown entity is rejected'
);

select * from finish();
rollback;

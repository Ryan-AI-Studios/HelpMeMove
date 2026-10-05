begin;

create extension if not exists pgtap with schema extensions;

select plan(118);

insert into core.tenants (id, kind) values
  ('11111111-1111-4111-8111-111111111111', 'personal'),
  ('22222222-2222-4222-8222-222222222222', 'personal');

insert into core.subjects (tenant_id, id) values
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333'),
  ('11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444'),
  ('22222222-2222-4222-8222-222222222222', '55555555-5555-4555-8555-555555555555');

insert into identity_map.actor_subjects (actor_id, tenant_id, subject_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '22222222-2222-4222-8222-222222222222', '55555555-5555-4555-8555-555555555555');

insert into core.profiles (id, tenant_id, subject_id, marker) values
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', '{"synthetic":true}');

insert into core.programs (id, tenant_id, subject_id, marker) values
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', '{"synthetic":true}');

insert into core.sessions (id, tenant_id, subject_id, marker) values
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', '{"synthetic":true}');

select has_schema('core', 'core schema exists');
select has_schema('identity_map', 'identity map schema exists');
select hasnt_schema('content', 'content schema is not created');
select hasnt_schema('program', 'program schema is not created');
select hasnt_schema('telemetry', 'telemetry schema is not created');
select hasnt_schema('clinical', 'clinical schema is not created');
select hasnt_schema('audit', 'audit schema is not created');

select has_table('core', 'tenants', 'tenants exists');
select has_table('core', 'subjects', 'subjects exists');
select has_table('identity_map', 'actor_subjects', 'actor map exists');
select has_table('core', 'profiles', 'profiles exists');
select has_table('core', 'programs', 'programs exists');
select has_table('core', 'sessions', 'sessions exists');
select hasnt_table('core', 'memberships', 'memberships are not created');
select hasnt_table('core', 'care_grants', 'care grants are not created');
select hasnt_table('core', 'consents', 'consents are not created');

select hasnt_column('core', 'profiles', 'email', 'profiles have no email');
select hasnt_column('core', 'profiles', 'name', 'profiles have no name');
select hasnt_column('core', 'profiles', 'phone', 'profiles have no phone');
select hasnt_column('core', 'profiles', 'symptom', 'profiles have no symptom');
select hasnt_column('core', 'programs', 'email', 'programs have no email');
select hasnt_column('core', 'programs', 'name', 'programs have no name');
select hasnt_column('core', 'programs', 'phone', 'programs have no phone');
select hasnt_column('core', 'programs', 'symptom', 'programs have no symptom');
select hasnt_column('core', 'sessions', 'email', 'sessions have no email');
select hasnt_column('core', 'sessions', 'name', 'sessions have no name');
select hasnt_column('core', 'sessions', 'phone', 'sessions have no phone');
select hasnt_column('core', 'sessions', 'symptom', 'sessions have no symptom');
select hasnt_column('identity_map', 'actor_subjects', 'email', 'actor map has no email');
select hasnt_column('identity_map', 'actor_subjects', 'name', 'actor map has no name');
select hasnt_column('identity_map', 'actor_subjects', 'provider_id', 'actor map has no provider id');

select has_index('core', 'profiles', 'profiles_tenant_subject_idx', 'profiles ownership index');
select has_index('core', 'programs', 'programs_tenant_subject_idx', 'programs ownership index');
select has_index('core', 'sessions', 'sessions_tenant_subject_idx', 'sessions ownership index');
select has_index('identity_map', 'actor_subjects', 'actor_subjects_tenant_subject_idx', 'actor map ownership index');

select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'tenants'),
  'tenants forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'subjects'),
  'subjects forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'identity_map' and c.relname = 'actor_subjects'),
  'actor map forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'profiles'),
  'profiles forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'programs'),
  'programs forces row level security'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
   from pg_class as c
   join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'core' and c.relname = 'sessions'),
  'sessions forces row level security'
);

select ok(
  exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'core'
      and p.proname = 'current_scope'
      and p.prosecdef
      and exists (
        select 1
        from unnest(p.proconfig) as cfg
        where cfg = 'search_path='
           or cfg = 'search_path=""'
           or cfg = 'search_path=pg_catalog'
      )
  ),
  'current_scope is security definer with a fixed search path'
);

select policies_are('core', 'tenants', array[]::name[], 'tenants has no client policy');
select policies_are('core', 'subjects', array[]::name[], 'subjects has no client policy');
select policies_are('identity_map', 'actor_subjects', array[]::name[], 'actor map has no client policy');
select policies_are(
  'core',
  'profiles',
  array['profiles_select', 'profiles_insert', 'profiles_update', 'profiles_delete']::name[],
  'profiles has one policy per operation'
);
select policies_are(
  'core',
  'programs',
  array['programs_select', 'programs_insert', 'programs_update', 'programs_delete']::name[],
  'programs has one policy per operation'
);
select policies_are(
  'core',
  'sessions',
  array['sessions_select', 'sessions_insert', 'sessions_update', 'sessions_delete']::name[],
  'sessions has one policy per operation'
);

select ok(
  not has_table_privilege('anon', 'identity_map.actor_subjects', 'select'),
  'anon cannot select the actor map'
);
select ok(
  not has_table_privilege('authenticated', 'identity_map.actor_subjects', 'select'),
  'authenticated cannot select the actor map'
);
select ok(
  not has_table_privilege('anon', 'core.profiles', 'select'),
  'anon cannot select profiles'
);
select ok(
  has_table_privilege('authenticated', 'core.profiles', 'select'),
  'authenticated can select profiles through policy'
);
select ok(
  not has_column_privilege('authenticated', 'core.profiles', 'tenant_id', 'update'),
  'authenticated cannot update profile tenant_id'
);
select ok(
  not has_column_privilege('authenticated', 'core.profiles', 'subject_id', 'update'),
  'authenticated cannot update profile subject_id'
);
select ok(
  not has_column_privilege('authenticated', 'core.programs', 'tenant_id', 'update'),
  'authenticated cannot update program tenant_id'
);
select ok(
  not has_column_privilege('authenticated', 'core.programs', 'subject_id', 'update'),
  'authenticated cannot update program subject_id'
);
select ok(
  not has_column_privilege('authenticated', 'core.sessions', 'tenant_id', 'update'),
  'authenticated cannot update session tenant_id'
);
select ok(
  not has_column_privilege('authenticated', 'core.sessions', 'subject_id', 'update'),
  'authenticated cannot update session subject_id'
);
select ok(
  has_column_privilege('authenticated', 'core.profiles', 'marker', 'update'),
  'authenticated can update its profile marker'
);
select ok(
  not has_function_privilege('anon', 'core.current_scope()', 'execute'),
  'anon cannot execute current_scope'
);
select ok(
  has_function_privilege('authenticated', 'core.current_scope()', 'execute'),
  'authenticated can execute current_scope'
);

select throws_ok(
  $$insert into core.tenants (id, kind) values ('16161616-1616-4616-8616-161616161616', 'organization')$$,
  '23514',
  null,
  'kind other than personal fails the check'
);

select throws_ok(
  $$insert into core.profiles (id, tenant_id, subject_id, marker)
    values (
      '15151515-1515-4515-8515-151515151515',
      '11111111-1111-4111-8111-111111111111',
      '55555555-5555-4555-8555-555555555555',
      '{"synthetic":true}'
    )$$,
  '23503',
  null,
  'cross-tenant profile parent fails the foreign key'
);
select throws_ok(
  $$insert into core.programs (id, tenant_id, subject_id, marker)
    values (
      '15151515-1515-4515-8515-151515151515',
      '11111111-1111-4111-8111-111111111111',
      '55555555-5555-4555-8555-555555555555',
      '{"synthetic":true}'
    )$$,
  '23503',
  null,
  'cross-tenant program parent fails the foreign key'
);
select throws_ok(
  $$insert into core.sessions (id, tenant_id, subject_id, marker)
    values (
      '15151515-1515-4515-8515-151515151515',
      '11111111-1111-4111-8111-111111111111',
      '55555555-5555-4555-8555-555555555555',
      '{"synthetic":true}'
    )$$,
  '23503',
  null,
  'cross-tenant session parent fails the foreign key'
);

set local role anon;
select throws_ok($$select * from core.tenants$$, '42501', null, 'anon cannot select tenants');
select throws_ok($$select * from core.subjects$$, '42501', null, 'anon cannot select subjects');
select throws_ok($$select * from core.profiles$$, '42501', null, 'anon cannot select profiles');
select throws_ok($$select * from core.programs$$, '42501', null, 'anon cannot select programs');
select throws_ok($$select * from core.sessions$$, '42501', null, 'anon cannot select sessions');
select throws_ok(
  $$select * from identity_map.actor_subjects$$,
  '42501',
  null,
  'anon cannot select the actor map'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select * from identity_map.actor_subjects$$,
  '42501',
  null,
  'authenticated cannot select the actor map'
);
select throws_ok($$select * from core.tenants$$, '42501', null, 'authenticated cannot select tenants');
select throws_ok($$select * from core.subjects$$, '42501', null, 'authenticated cannot select subjects');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';

select ok(
  (select marker = '{"synthetic":true}'::jsonb
   from core.profiles
   where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'subject 1 selects its profile marker'
);
select ok(
  (select marker = '{"synthetic":true}'::jsonb
   from core.programs
   where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
  'subject 1 selects its program marker'
);
select ok(
  (select marker = '{"synthetic":true}'::jsonb
   from core.sessions
   where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'),
  'subject 1 selects its session marker'
);
select lives_ok(
  $$update core.profiles
    set marker = '{"synthetic":true}'::jsonb
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'subject 1 updates its profile marker'
);
select lives_ok(
  $$update core.programs
    set marker = '{"synthetic":true}'::jsonb
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'$$,
  'subject 1 updates its program marker'
);
select lives_ok(
  $$update core.sessions
    set marker = '{"synthetic":true}'::jsonb
    where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$$,
  'subject 1 updates its session marker'
);
select lives_ok(
  $$insert into core.profiles (id, tenant_id, subject_id, marker)
    values (
      '12121212-1212-4212-8212-121212121212',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'
    )$$,
  'subject 1 inserts its own profile'
);
select lives_ok(
  $$insert into core.programs (id, tenant_id, subject_id, marker)
    values (
      '13131313-1313-4313-8313-131313131313',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'
    )$$,
  'subject 1 inserts its own program'
);
select lives_ok(
  $$insert into core.sessions (id, tenant_id, subject_id, marker)
    values (
      '14141414-1414-4414-8414-141414141414',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'
    )$$,
  'subject 1 inserts its own session'
);
select lives_ok(
  $$delete from core.profiles where id = '12121212-1212-4212-8212-121212121212'$$,
  'subject 1 deletes its extra profile'
);
select lives_ok(
  $$delete from core.programs where id = '13131313-1313-4313-8313-131313131313'$$,
  'subject 1 deletes its extra program'
);
select lives_ok(
  $$delete from core.sessions where id = '14141414-1414-4414-8414-141414141414'$$,
  'subject 1 deletes its extra session'
);
select is_empty(
  $$select 1 from core.profiles where id = '12121212-1212-4212-8212-121212121212'$$,
  'subject 1 no longer sees the deleted profile'
);
select throws_ok(
  $$update core.profiles set tenant_id = tenant_id where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  '42501',
  null,
  'subject 1 cannot update profile tenant_id'
);
select throws_ok(
  $$update core.profiles set subject_id = subject_id where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  '42501',
  null,
  'subject 1 cannot update profile subject_id'
);
select throws_ok(
  $$update core.programs set tenant_id = tenant_id where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'$$,
  '42501',
  null,
  'subject 1 cannot update program tenant_id'
);
select throws_ok(
  $$update core.programs set subject_id = subject_id where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'$$,
  '42501',
  null,
  'subject 1 cannot update program subject_id'
);
select throws_ok(
  $$update core.sessions set tenant_id = tenant_id where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$$,
  '42501',
  null,
  'subject 1 cannot update session tenant_id'
);
select throws_ok(
  $$update core.sessions set subject_id = subject_id where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$$,
  '42501',
  null,
  'subject 1 cannot update session subject_id'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" to 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local "request.jwt.claims" to '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';

select is_empty($$select marker::text from core.profiles$$, 'subject 2 sees no profile rows');
select is_empty($$select marker::text from core.programs$$, 'subject 2 sees no program rows');
select is_empty($$select marker::text from core.sessions$$, 'subject 2 sees no session rows');
select lives_ok(
  $$update core.profiles
    set marker = '{"synthetic":true,"leaked":true}'::jsonb
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'subject 2 update of subject 1 profile does not error'
);
select lives_ok(
  $$delete from core.profiles where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'subject 2 delete of subject 1 profile does not error'
);
select throws_ok(
  $$insert into core.profiles (id, tenant_id, subject_id, marker)
    values (
      '18181818-1818-4818-8818-181818181818',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'
    )$$,
  '42501',
  'new row violates row-level security policy for table "profiles"',
  'subject 2 cannot insert subject 1 profile'
);
select lives_ok(
  $$insert into core.profiles (id, tenant_id, subject_id, marker)
    values (
      '17171717-1717-4717-8717-171717171717',
      '11111111-1111-4111-8111-111111111111',
      '44444444-4444-4444-8444-444444444444',
      '{"synthetic":true}'
    )$$,
  'subject 2 inserts its own profile'
);
select is_empty(
  $$select 1 from core.profiles where subject_id = '33333333-3333-4333-8333-333333333333'$$,
  'subject 2 still does not see subject 1'
);
select ok(
  (select count(*) = 1 from core.profiles),
  'subject 2 sees only its own profile'
);
reset role;

select ok(
  (select marker = '{"synthetic":true}'::jsonb
   from core.profiles
   where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'subject 2 did not change subject 1 marker'
);
select ok(
  (select count(*) = 1
   from core.profiles
   where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'subject 2 did not delete subject 1 profile'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
set local "request.jwt.claims" to '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';

select is_empty($$select marker::text from core.profiles$$, 'tenant B sees no tenant A profiles');
select is_empty($$select marker::text from core.programs$$, 'tenant B sees no tenant A programs');
select is_empty($$select marker::text from core.sessions$$, 'tenant B sees no tenant A sessions');
select lives_ok(
  $$update core.profiles
    set marker = '{"synthetic":true,"leaked":true}'::jsonb
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'tenant B update of tenant A profile does not error'
);
select lives_ok(
  $$delete from core.sessions where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$$,
  'tenant B delete of tenant A session does not error'
);
select throws_ok(
  $$insert into core.profiles (id, tenant_id, subject_id, marker)
    values (
      '19191919-1919-4919-8919-191919191919',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '{"synthetic":true}'
    )$$,
  '42501',
  'new row violates row-level security policy for table "profiles"',
  'tenant B cannot insert tenant A profile'
);
reset role;

select ok(
  (select count(*) = 1
   from core.sessions
   where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'),
  'tenant B did not delete tenant A session'
);

select throws_ok(
  $$update core.profiles
    set tenant_id = '22222222-2222-4222-8222-222222222222'
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  '42501',
  null,
  'owner trigger rejects a profile tenant change'
);
select throws_ok(
  $$update core.profiles
    set subject_id = '44444444-4444-4444-8444-444444444444'
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  '42501',
  null,
  'owner trigger rejects a profile subject change'
);
select throws_ok(
  $$update core.programs
    set tenant_id = '22222222-2222-4222-8222-222222222222'
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'$$,
  '42501',
  null,
  'owner trigger rejects a program tenant change'
);
select throws_ok(
  $$update core.sessions
    set subject_id = '44444444-4444-4444-8444-444444444444'
    where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$$,
  '42501',
  null,
  'owner trigger rejects a session subject change'
);
select lives_ok(
  $$update core.profiles
    set marker = '{"synthetic":true}'::jsonb
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'owner can still update the synthetic marker'
);

select is_empty(
  $$select 1 from pg_publication_tables where schemaname in ('core', 'identity_map')$$,
  'ownership tables are not in a realtime publication'
);
select is_empty($$select id from storage.buckets$$, 'no storage bucket is created');

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

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
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'authenticated',
    'authenticated',
    'a-isolation@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'authenticated',
    'authenticated',
    'b-isolation@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'authenticated',
    'authenticated',
    'c-isolation@example.test',
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
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'authenticated',
  'authenticated',
  'd-isolation@example.test',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

delete from identity_map.actor_subjects
where actor_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

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
      'a_program',
      '61616161-6161-4616-8616-616161616161'::uuid,
      '{"synthetic":true,"tenant_id":"22222222-2222-4222-8222-222222222222"}'
    ),
    (
      'c_workout',
      '62626262-6262-4626-8626-626262626262'::uuid,
      '{"synthetic":true}'
    ),
    (
      'b_program',
      '63636363-6363-4636-8636-636363636363'::uuid,
      '{"synthetic":true}'
    ),
    (
      'd_program',
      '64646464-6464-4646-8646-646464646464'::uuid,
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
    (select event_id from copy_doc where kind = 'a_program'),
    (select document_text from copy_doc where kind = 'a_program'),
    (select document_sha256 from copy_doc where kind = 'a_program')
  ),
  'confirmed',
  'actor A copy is confirmed'
);

reset role;

select is(
  (
    select documents.tenant_id::text || documents.subject_id::text
    from core.program_documents as documents
    where documents.id = '61616161-6161-4616-8616-616161616161'
  ),
  '11111111-1111-4111-8111-111111111111'
    || '33333333-3333-4333-8333-333333333333',
  'json tenant id does not redirect actor A'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';

create temp table replay_result (value text);

insert into replay_result (value)
select public.copy_owned_document(
  'program_records',
  (select event_id from copy_doc where kind = 'a_program'),
  (select document_text from copy_doc where kind = 'a_program'),
  (select document_sha256 from copy_doc where kind = 'a_program')
);

reset role;

select ok(
  (select value from replay_result) = 'confirmed'
    and (
      select count(*)::int
      from core.program_documents as documents
      where documents.id = '61616161-6161-4616-8616-616161616161'
        and documents.tenant_id = '11111111-1111-4111-8111-111111111111'
    ) = 1,
  'actor A replay is confirmed and stores one row'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
set local "request.jwt.claims" to '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';

select is(
  public.copy_owned_document(
    'workout_records',
    (select event_id from copy_doc where kind = 'c_workout'),
    (select document_text from copy_doc where kind = 'c_workout'),
    (select document_sha256 from copy_doc where kind = 'c_workout')
  ),
  'confirmed',
  'actor C workout copy is confirmed'
);

reset role;

select is(
  (
    select documents.tenant_id::text || documents.subject_id::text
    from core.session_documents as documents
    where documents.id = '62626262-6262-4626-8626-626262626262'
  ),
  '22222222-2222-4222-8222-222222222222'
    || '55555555-5555-4555-8555-555555555555',
  'actor C copy stays on actor C'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local "request.jwt.claims" to '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';

select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'b_program'),
    (select document_text from copy_doc where kind = 'b_program'),
    (select document_sha256 from copy_doc where kind = 'b_program')
  ),
  'confirmed',
  'actor B copy is confirmed'
);

reset role;

select ok(
  (
    select documents.subject_id
    from core.program_documents as documents
    where documents.id = '63636363-6363-4636-8636-636363636363'
  ) = '44444444-4444-4444-8444-444444444444'::uuid
    and (
      select documents.tenant_id
      from core.program_documents as documents
      where documents.id = '63636363-6363-4636-8636-636363636363'
    ) = '11111111-1111-4111-8111-111111111111'::uuid
    and (
      select documents.subject_id
      from core.program_documents as documents
      where documents.id = '61616161-6161-4616-8616-616161616161'
    ) = '33333333-3333-4333-8333-333333333333'::uuid,
  'actor B stays on subject B and actor A stays on subject A'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local "request.jwt.claims" to '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';

select throws_ok(
  $$select * from core.program_documents$$,
  '42501',
  null,
  'actor A cannot select program documents'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
set local "request.jwt.claims" to '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';

select throws_ok(
  $$select * from identity_map.actor_subjects$$,
  '42501',
  null,
  'actor C cannot select the actor map'
);

set local role authenticated;
set local "request.jwt.claim.sub" to 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
set local "request.jwt.claims" to '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}';

select is(
  public.copy_owned_document(
    'program_records',
    (select event_id from copy_doc where kind = 'd_program'),
    (select document_text from copy_doc where kind = 'd_program'),
    (select document_sha256 from copy_doc where kind = 'd_program')
  ),
  'unavailable',
  'actor with no subject map is unavailable'
);

reset role;

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'core'
      and table_name = 'program_documents'
      and column_name in ('email', 'name', 'phone')
  ),
  'program documents have no email, name, or phone'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'identity_map'
      and table_name = 'actor_subjects'
      and column_name = 'document'
  ),
  'actor map has no document column'
);

select * from finish();
rollback;

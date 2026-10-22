-- RuangKepo Supabase foundation
-- Apply this file in Supabase Dashboard > SQL Editor.
-- No browser client can read the tables directly. Browser access is via validated RPC functions.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.secret_boxes (
  id uuid primary key default gen_random_uuid(),
  owner_token_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.secret_messages (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.secret_boxes(id) on delete cascade,
  sender_name text not null default 'Anonim',
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists secret_messages_box_created_idx
  on public.secret_messages (box_id, created_at desc);

create table if not exists public.bestie_quizzes (
  id uuid primary key default gen_random_uuid(),
  owner_token_hash text not null,
  title text not null check (char_length(title) between 1 and 100),
  questions jsonb not null check (jsonb_typeof(questions) = 'array'),
  created_at timestamptz not null default now()
);

create table if not exists public.bestie_submissions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.bestie_quizzes(id) on delete cascade,
  participant_name text not null default 'Bestie',
  answers jsonb not null check (jsonb_typeof(answers) = 'array'),
  score integer not null check (score >= 0),
  total integer not null check (total between 1 and 10),
  created_at timestamptz not null default now()
);

create index if not exists bestie_submissions_quiz_created_idx
  on public.bestie_submissions (quiz_id, created_at desc);

alter table public.secret_boxes enable row level security;
alter table public.secret_messages enable row level security;
alter table public.bestie_quizzes enable row level security;
alter table public.bestie_submissions enable row level security;

-- Revoke direct table access from browser roles. Access is only through RPC below.
revoke all on table public.secret_boxes from anon, authenticated;
revoke all on table public.secret_messages from anon, authenticated;
revoke all on table public.bestie_quizzes from anon, authenticated;
revoke all on table public.bestie_submissions from anon, authenticated;

create or replace function public.create_secret_box()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
  v_token text;
begin
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.secret_boxes (owner_token_hash)
  values (encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'))
  returning id into v_id;

  return jsonb_build_object('box_id', v_id, 'owner_token', v_token);
end;
$$;

create or replace function public.send_secret_message(
  p_box_id uuid,
  p_body text,
  p_sender_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_message_id uuid;
  v_name text;
begin
  if p_body is null or char_length(trim(p_body)) < 1 or char_length(p_body) > 1000 then
    raise exception 'Pesan harus berisi 1 sampai 1000 karakter' using errcode = '22023';
  end if;

  if not exists (select 1 from public.secret_boxes where id = p_box_id) then
    raise exception 'Kotak tidak ditemukan' using errcode = 'P0002';
  end if;

  v_name := coalesce(nullif(left(trim(coalesce(p_sender_name, '')), 40), ''), 'Anonim');

  insert into public.secret_messages (box_id, sender_name, body)
  values (p_box_id, v_name, trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object('ok', true, 'message_id', v_message_id);
end;
$$;

create or replace function public.read_secret_messages(
  p_box_id uuid,
  p_owner_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
  v_messages jsonb;
begin
  select owner_token_hash into v_hash
  from public.secret_boxes
  where id = p_box_id;

  if v_hash is null
     or p_owner_token is null
     or v_hash <> encode(extensions.digest(convert_to(p_owner_token, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'Token pemilik tidak valid' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'sender_name', m.sender_name,
        'body', m.body,
        'created_at', m.created_at
      ) order by m.created_at desc
    ),
    '[]'::jsonb
  )
  into v_messages
  from public.secret_messages m
  where m.box_id = p_box_id;

  return jsonb_build_object('messages', v_messages);
end;
$$;

create or replace function public.create_bestie_quiz(
  p_title text,
  p_questions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
  v_token text;
  v_q jsonb;
  v_options jsonb;
  v_correct integer;
begin
  if p_title is null or char_length(trim(p_title)) < 1 or char_length(p_title) > 100 then
    raise exception 'Judul harus berisi 1 sampai 100 karakter' using errcode = '22023';
  end if;

  if p_questions is null or jsonb_typeof(p_questions) <> 'array'
     or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 10 then
    raise exception 'Kuis harus berisi 1 sampai 10 pertanyaan' using errcode = '22023';
  end if;

  for v_q in select value from jsonb_array_elements(p_questions)
  loop
    if jsonb_typeof(v_q) <> 'object'
       or coalesce(char_length(trim(v_q->>'prompt')), 0) < 1
       or char_length(v_q->>'prompt') > 300
       or coalesce(jsonb_typeof(v_q->'options'), '') <> 'array'
       or coalesce(jsonb_array_length(v_q->'options'), 0) < 2
       or coalesce(jsonb_array_length(v_q->'options'), 0) > 4
       or coalesce(v_q->>'correct_index', '') !~ '^[0-3]$' then
      raise exception 'Format pertanyaan tidak valid' using errcode = '22023';
    end if;

    v_options := v_q->'options';
    v_correct := (v_q->>'correct_index')::integer;

    if v_correct >= jsonb_array_length(v_options) then
      raise exception 'Jawaban benar berada di luar pilihan' using errcode = '22023';
    end if;
  end loop;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.bestie_quizzes (owner_token_hash, title, questions)
  values (
    encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'),
    trim(p_title),
    p_questions
  )
  returning id into v_id;

  return jsonb_build_object('quiz_id', v_id, 'owner_token', v_token);
end;
$$;

create or replace function public.get_bestie_quiz(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_title text;
  v_questions jsonb;
begin
  select title, questions into v_title, v_questions
  from public.bestie_quizzes
  where id = p_quiz_id;

  if not found then
    raise exception 'Kuis tidak ditemukan' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'quiz_id', p_quiz_id,
    'title', v_title,
    'questions', (
      select jsonb_agg(
        jsonb_build_object('prompt', q.value->'prompt', 'options', q.value->'options')
        order by q.ordinality
      )
      from jsonb_array_elements(v_questions) with ordinality as q(value, ordinality)
    )
  );
end;
$$;

create or replace function public.submit_bestie_quiz(
  p_quiz_id uuid,
  p_participant_name text,
  p_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_questions jsonb;
  v_q jsonb;
  v_i integer;
  v_answer integer;
  v_score integer := 0;
  v_total integer;
  v_submission_id uuid;
  v_name text;
begin
  select questions into v_questions
  from public.bestie_quizzes
  where id = p_quiz_id;

  if not found then
    raise exception 'Kuis tidak ditemukan' using errcode = 'P0002';
  end if;

  v_total := jsonb_array_length(v_questions);

  if p_answers is null or jsonb_typeof(p_answers) <> 'array'
     or jsonb_array_length(p_answers) <> v_total then
    raise exception 'Jawaban tidak lengkap' using errcode = '22023';
  end if;

  for v_i in 0..(v_total - 1)
  loop
    v_q := v_questions -> v_i;

    if coalesce(p_answers->>v_i, '') !~ '^[0-3]$' then
      raise exception 'Pilihan jawaban tidak valid' using errcode = '22023';
    end if;

    v_answer := (p_answers->>v_i)::integer;

    if v_answer >= jsonb_array_length(v_q->'options') then
      raise exception 'Pilihan jawaban tidak valid' using errcode = '22023';
    end if;

    if v_answer = (v_q->>'correct_index')::integer then
      v_score := v_score + 1;
    end if;
  end loop;

  v_name := coalesce(nullif(left(trim(coalesce(p_participant_name, '')), 40), ''), 'Bestie');

  insert into public.bestie_submissions (quiz_id, participant_name, answers, score, total)
  values (p_quiz_id, v_name, p_answers, v_score, v_total)
  returning id into v_submission_id;

  return jsonb_build_object('submission_id', v_submission_id, 'score', v_score, 'total', v_total);
end;
$$;

create or replace function public.read_bestie_results(
  p_quiz_id uuid,
  p_owner_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
  v_results jsonb;
begin
  select owner_token_hash into v_hash
  from public.bestie_quizzes
  where id = p_quiz_id;

  if v_hash is null
     or p_owner_token is null
     or v_hash <> encode(extensions.digest(convert_to(p_owner_token, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'Token pemilik tidak valid' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'participant_name', s.participant_name,
        'score', s.score,
        'total', s.total,
        'created_at', s.created_at
      ) order by s.created_at desc
    ),
    '[]'::jsonb
  )
  into v_results
  from public.bestie_submissions s
  where s.quiz_id = p_quiz_id;

  return jsonb_build_object('results', v_results);
end;
$$;

-- SECURITY DEFINER functions must not remain executable by PUBLIC by default.
revoke all on function public.create_secret_box() from public;
revoke all on function public.send_secret_message(uuid, text, text) from public;
revoke all on function public.read_secret_messages(uuid, text) from public;
revoke all on function public.create_bestie_quiz(text, jsonb) from public;
revoke all on function public.get_bestie_quiz(uuid) from public;
revoke all on function public.submit_bestie_quiz(uuid, text, jsonb) from public;
revoke all on function public.read_bestie_results(uuid, text) from public;

grant execute on function public.create_secret_box() to anon, authenticated;
grant execute on function public.send_secret_message(uuid, text, text) to anon, authenticated;
grant execute on function public.read_secret_messages(uuid, text) to anon, authenticated;
grant execute on function public.create_bestie_quiz(text, jsonb) to anon, authenticated;
grant execute on function public.get_bestie_quiz(uuid) to anon, authenticated;
grant execute on function public.submit_bestie_quiz(uuid, text, jsonb) to anon, authenticated;
grant execute on function public.read_bestie_results(uuid, text) to anon, authenticated;

comment on table public.secret_boxes is 'RuangKepo private message box metadata; owner token is stored as a SHA-256 hash.';
comment on table public.secret_messages is 'Private messages; no direct browser table access, use validated RPC functions.';
comment on table public.bestie_quizzes is 'Bestie quiz definitions including answer keys; no direct browser table access.';
comment on table public.bestie_submissions is 'Quiz submissions and scores; owner results require owner token validation.';

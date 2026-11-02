-- RuangKepo Kotak Suara: 5 pesan pemilik + maksimal 5 pesan teman (10 kartu).
-- Public clients may only call the RPCs; direct table access remains closed.

create table if not exists public.voice_boxes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  owner_token_hash text not null,
  title text not null check (pg_catalog.char_length(title) between 1 and 60),
  created_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.voice_papers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  box_id uuid not null references public.voice_boxes(id) on delete cascade,
  source text not null check (source in ('owner', 'friend')),
  sender_name text not null default 'Anonim',
  body text not null check (pg_catalog.char_length(body) between 1 and 500),
  created_at timestamptz not null default pg_catalog.now(),
  drawn_at timestamptz
);

create index if not exists voice_papers_box_pending_idx
  on public.voice_papers (box_id, created_at)
  where drawn_at is null;

alter table public.voice_boxes enable row level security;
alter table public.voice_papers enable row level security;

revoke all on table public.voice_boxes from anon, authenticated;
revoke all on table public.voice_papers from anon, authenticated;

create or replace function public.create_voice_box(
  p_title text,
  p_owner_papers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_token text;
  v_item jsonb;
  v_body text;
begin
  if p_title is null
     or pg_catalog.char_length(pg_catalog.btrim(p_title)) < 1
     or pg_catalog.char_length(p_title) > 60 then
    raise exception 'Nama kotak harus berisi 1 sampai 60 karakter' using errcode = '22023';
  end if;

  if p_owner_papers is null
     or pg_catalog.jsonb_typeof(p_owner_papers) <> 'array'
     or pg_catalog.jsonb_array_length(p_owner_papers) <> 5 then
    raise exception 'Kotak harus berisi tepat 5 kertas buatan pemilik' using errcode = '22023';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_owner_papers)
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'string' then
      raise exception 'Semua kertas harus berupa teks' using errcode = '22023';
    end if;
    v_body := pg_catalog.btrim(v_item #>> '{}');
    if pg_catalog.char_length(v_body) < 1 or pg_catalog.char_length(v_body) > 500 then
      raise exception 'Setiap kertas harus berisi 1 sampai 500 karakter' using errcode = '22023';
    end if;
  end loop;

  v_token := pg_catalog.replace(
    pg_catalog.gen_random_uuid()::text || pg_catalog.gen_random_uuid()::text,
    '-',
    ''
  );

  insert into public.voice_boxes (owner_token_hash, title)
  values (
    pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_token, 'UTF8'), 'sha256'), 'hex'),
    pg_catalog.btrim(p_title)
  )
  returning id into v_id;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_owner_papers)
  loop
    insert into public.voice_papers (box_id, source, sender_name, body)
    values (v_id, 'owner', 'Pemilik', pg_catalog.btrim(v_item #>> '{}'));
  end loop;

  return pg_catalog.jsonb_build_object(
    'box_id', v_id,
    'owner_token', v_token,
    'title', pg_catalog.btrim(p_title)
  );
end;
$function$;

create or replace function public.submit_voice_paper(
  p_box_id uuid,
  p_body text,
  p_sender_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_friend_count integer;
  v_sender text;
  v_paper_id uuid;
begin
  if p_body is null
     or pg_catalog.char_length(pg_catalog.btrim(p_body)) < 1
     or pg_catalog.char_length(p_body) > 500 then
    raise exception 'Tulisan harus berisi 1 sampai 500 karakter' using errcode = '22023';
  end if;

  v_sender := coalesce(
    nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_sender_name, '')), 40), ''),
    'Anonim'
  );

  perform 1 from public.voice_boxes where id = p_box_id for update;
  if not found then
    raise exception 'Kotak tidak ditemukan' using errcode = 'P0002';
  end if;

  select pg_catalog.count(*)::integer into v_friend_count
  from public.voice_papers
  where box_id = p_box_id and source = 'friend';

  if v_friend_count >= 5 then
    raise exception 'Kuota 5 kertas dari teman sudah penuh' using errcode = '22023';
  end if;

  insert into public.voice_papers (box_id, source, sender_name, body)
  values (p_box_id, 'friend', v_sender, pg_catalog.btrim(p_body))
  returning id into v_paper_id;

  return pg_catalog.jsonb_build_object('ok', true, 'paper_id', v_paper_id);
end;
$function$;

create or replace function public.read_voice_papers(
  p_box_id uuid,
  p_owner_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hash text;
  v_papers jsonb;
begin
  select owner_token_hash into v_hash
  from public.voice_boxes
  where id = p_box_id;

  if v_hash is null
     or p_owner_token is null
     or v_hash <> pg_catalog.encode(
       extensions.digest(pg_catalog.convert_to(p_owner_token, 'UTF8'), 'sha256'),
       'hex'
     ) then
    raise exception 'Token pemilik tidak valid' using errcode = '42501';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', p.id,
        'source', p.source,
        'sender_name', p.sender_name,
        'body', case when p.drawn_at is not null then p.body else null end,
        'created_at', p.created_at,
        'drawn_at', p.drawn_at
      ) order by case p.source when 'owner' then 0 else 1 end, p.created_at, p.id
    ),
    '[]'::jsonb
  )
  into v_papers
  from public.voice_papers p
  where p.box_id = p_box_id;

  return pg_catalog.jsonb_build_object('papers', v_papers);
end;
$function$;

create or replace function public.draw_voice_paper(
  p_box_id uuid,
  p_owner_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hash text;
  v_total integer;
  v_friend_count integer;
  v_paper_id uuid;
  v_sender text;
  v_body text;
  v_remaining integer;
begin
  select owner_token_hash into v_hash
  from public.voice_boxes
  where id = p_box_id
  for update;

  if v_hash is null
     or p_owner_token is null
     or v_hash <> pg_catalog.encode(
       extensions.digest(pg_catalog.convert_to(p_owner_token, 'UTF8'), 'sha256'),
       'hex'
     ) then
    raise exception 'Token pemilik tidak valid' using errcode = '42501';
  end if;

  select pg_catalog.count(*)::integer into v_total
  from public.voice_papers where box_id = p_box_id;

  select pg_catalog.count(*)::integer into v_friend_count
  from public.voice_papers where box_id = p_box_id and source = 'friend';

  if v_total <> 10 or v_friend_count <> 5 then
    raise exception 'Kotak dapat diacak setelah 5 kertas pemilik dan 5 kertas teman terkumpul' using errcode = '22023';
  end if;

  select id, sender_name, body
  into v_paper_id, v_sender, v_body
  from public.voice_papers
  where box_id = p_box_id and drawn_at is null
  order by pg_catalog.random()
  limit 1
  for update;

  if v_paper_id is null then
    raise exception 'Semua kertas sudah terpilih' using errcode = 'P0002';
  end if;

  update public.voice_papers
  set drawn_at = pg_catalog.now()
  where id = v_paper_id;

  select pg_catalog.count(*)::integer into v_remaining
  from public.voice_papers
  where box_id = p_box_id and drawn_at is null;

  return pg_catalog.jsonb_build_object(
    'paper', pg_catalog.jsonb_build_object('sender_name', v_sender, 'body', v_body),
    'remaining', v_remaining
  );
end;
$function$;

revoke all on function public.create_voice_box(text, jsonb) from public;
revoke all on function public.submit_voice_paper(uuid, text, text) from public;
revoke all on function public.read_voice_papers(uuid, text) from public;
revoke all on function public.draw_voice_paper(uuid, text) from public;

grant execute on function public.create_voice_box(text, jsonb) to anon, authenticated;
grant execute on function public.submit_voice_paper(uuid, text, text) to anon, authenticated;
grant execute on function public.read_voice_papers(uuid, text) to anon, authenticated;
grant execute on function public.draw_voice_paper(uuid, text) to anon, authenticated;

comment on table public.voice_boxes is 'Kotak Suara metadata; owner access is validated with a SHA-256 hashed secret token.';
comment on table public.voice_papers is 'Ten Kotak Suara papers per box: five owner-authored and up to five friend submissions. Undrawn message bodies are hidden from reads.';

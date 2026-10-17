-- Shared server for the Sale Catalog app (Supabase / Postgres).
-- Run once in the Supabase SQL editor. Every table is limited to team members
-- by row-level security; the results reader writes with the service key.

create table teams (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

create table team_members (
  team_id uuid references teams on delete cascade,
  user_id uuid references auth.users on delete cascade,
  display_name text not null,
  primary key (team_id, user_id)
);

create function is_member(t uuid) returns boolean
language sql security definer stable as $$
  select exists (select 1 from team_members where team_id = t and user_id = auth.uid())
$$;

-- Team-wide marks: one short-list and one bid ceiling per hip.
create table hip_marks (
  team_id uuid references teams on delete cascade,
  sale_id text not null,
  hip int not null,
  shortlisted boolean not null default false,
  bid_ceiling numeric,
  updated_by text,
  updated_at timestamptz not null default now(),
  primary key (team_id, sale_id, hip)
);

-- Each person's own favorite and rating; the team sees everyone's.
create table personal_marks (
  team_id uuid references teams on delete cascade,
  user_id uuid references auth.users on delete cascade,
  sale_id text not null,
  hip int not null,
  author text not null,
  favorite boolean not null default false,
  rating int not null default 0 check (rating between 0 and 5),
  updated_at timestamptz not null default now(),
  primary key (team_id, user_id, sale_id, hip)
);

-- Ink notes. The PencilKit drawing goes to storage (bucket "ink"); the text stays here.
create table notes (
  id uuid primary key,
  team_id uuid references teams on delete cascade,
  user_id uuid references auth.users on delete cascade default auth.uid(),
  sale_id text not null,
  hip int not null,
  author text not null,
  location text not null,
  recognized_text text not null default '',
  corrected_text text,
  drawing_path text,
  updated_at timestamptz not null default now()
);
create index on notes (team_id, sale_id, updated_at);

-- Photos and video. Files go to storage (bucket "media").
create table media (
  id uuid primary key,
  team_id uuid references teams on delete cascade,
  user_id uuid references auth.users on delete cascade default auth.uid(),
  sale_id text not null,
  hip int not null,
  author text not null,
  kind text not null check (kind in ('photo', 'video')),
  storage_path text not null,
  created_at timestamptz not null default now()
);

-- Sale results: written by the results reader (source 'feed') or typed in
-- by a team member (source 'manual'). A feed row replaces a manual one.
create table results (
  sale_id text not null,
  hip int not null,
  result text not null check (result in ('sold', 'rna', 'out')),
  price numeric,
  buyer text,
  source text not null default 'manual' check (source in ('feed', 'manual')),
  updated_at timestamptz not null default now(),
  primary key (sale_id, hip)
);

alter table teams enable row level security;
alter table team_members enable row level security;
alter table hip_marks enable row level security;
alter table personal_marks enable row level security;
alter table notes enable row level security;
alter table media enable row level security;
alter table results enable row level security;

create policy "members see their team" on teams for select using (is_member(id));
create policy "members see the roster" on team_members for select using (is_member(team_id));
create policy "team marks" on hip_marks for all using (is_member(team_id)) with check (is_member(team_id));
create policy "read team's personal marks" on personal_marks for select using (is_member(team_id));
create policy "write own personal marks" on personal_marks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and is_member(team_id));
create policy "read team notes" on notes for select using (is_member(team_id));
create policy "write own notes" on notes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and is_member(team_id));
create policy "read team media" on media for select using (is_member(team_id));
create policy "write own media" on media for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and is_member(team_id));
-- Results are public sale information: any signed-in user reads; members type in.
create policy "read results" on results for select using (auth.uid() is not null);
create policy "type in results" on results for insert with check (source = 'manual' and auth.uid() is not null);
create policy "correct manual results" on results for update
  using (source = 'manual' and auth.uid() is not null) with check (source = 'manual');

-- Live updates to every iPad.
alter publication supabase_realtime add table hip_marks, personal_marks, notes, media, results;

-- Storage buckets (private) for ink and media, readable by the team.
insert into storage.buckets (id, name, public) values ('ink', 'ink', false), ('media', 'media', false);
create policy "team reads files" on storage.objects for select
  using (bucket_id in ('ink', 'media') and is_member((storage.foldername(name))[1]::uuid));
create policy "team writes files" on storage.objects for insert
  with check (bucket_id in ('ink', 'media') and is_member((storage.foldername(name))[1]::uuid));

-- Keep updated_at current so devices can pull only what changed.
create function touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger touch before update on hip_marks for each row execute function touch();
create trigger touch before update on personal_marks for each row execute function touch();
create trigger touch before update on notes for each row execute function touch();
create trigger touch before update on results for each row execute function touch();

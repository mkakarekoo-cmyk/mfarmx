-- M-FarmX — schemat bazy (Etap 2, Supabase)
-- Model „dokumentowy": cały stan gospodarstwa jednego użytkownika trzymany jako jsonb.
-- Dzięki temu apka działa bez przepisywania modułów, a RLS izoluje dane każdego rolnika.

create table if not exists public.user_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_state enable row level security;

-- Każdy użytkownik widzi i edytuje TYLKO swój wiersz (własne gospodarstwo)
drop policy if exists "own row select" on public.user_state;
drop policy if exists "own row insert" on public.user_state;
drop policy if exists "own row update" on public.user_state;

create policy "own row select" on public.user_state
  for select using (auth.uid() = user_id);

create policy "own row insert" on public.user_state
  for insert with check (auth.uid() = user_id);

create policy "own row update" on public.user_state
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

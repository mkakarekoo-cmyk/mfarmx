-- ═══════════════════════════════════════════════════════════════════════════════
-- KONTA PRACOWNIKÓW — dostęp do grafiku gospodarstwa (04.09.2026)
-- Uruchom w: Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- PROBLEM, KTÓRY TO ROZWIĄZUJE: cały stan gospodarstwa siedzi w JEDNYM wierszu
-- `user_state`, przypisanym do konta właściciela. Pracownik logujący się na własne konto
-- dostałby puste gospodarstwo — nie zobaczyłby ani grafiku, ani swoich zadań.
--
-- ROZWIĄZANIE: tabela powiązań mówi „to konto pracownika należy do tego gospodarstwa",
-- a polityka na `user_state` pozwala mu CZYTAĆ wiersz właściciela.
--
-- 🔑 WYŁĄCZNIE ODCZYT. Pracownik nie może zapisywać, bo zapis to nadpisanie CAŁEGO
-- dokumentu gospodarstwa — jedna pomyłka kasowałaby pola, maszyny i finanse właściciela.
-- Dopóki stan jest jednym jsonb-em, prawo zapisu dla pracownika jest zbyt niebezpieczne.
-- (Gdy kiedyś zadania wyjdą do osobnej tabeli, pracownik dostanie zapis tylko do swoich.)

create table if not exists public.dostep_pracownika (
  pracownik_id uuid primary key references auth.users(id) on delete cascade,
  wlasciciel_id uuid not null references auth.users(id) on delete cascade,
  imie text,                       -- podpowiedź, komu odpowiada wpis w state.workers
  worker_id text,                  -- id z `state.workers` — po nim filtrujemy jego zadania
  utworzono timestamptz default now()
);

create index if not exists dostep_pracownika_wlasciciel_idx
  on public.dostep_pracownika (wlasciciel_id);

alter table public.dostep_pracownika enable row level security;

-- Pracownik widzi WYŁĄCZNIE swój własny wpis — czyli dowiaduje się, do jakiego
-- gospodarstwa należy, ale nie kto jeszcze w nim pracuje.
drop policy if exists dostep_pracownika_swoj on public.dostep_pracownika;
create policy dostep_pracownika_swoj on public.dostep_pracownika
  for select to authenticated
  using (pracownik_id = auth.uid());

-- Właściciel widzi i zarządza wpisami swojego gospodarstwa.
drop policy if exists dostep_pracownika_wlasciciel on public.dostep_pracownika;
create policy dostep_pracownika_wlasciciel on public.dostep_pracownika
  for all to authenticated
  using (wlasciciel_id = auth.uid())
  with check (wlasciciel_id = auth.uid());

-- ── Odczyt gospodarstwa przez pracownika ──────────────────────────────────────
-- ⚠️ DOKŁADAMY politykę, nie podmieniamy istniejącej. Polityki permisywne sumują się,
-- więc dotychczasowa reguła „każdy widzi swój wiersz" działa dalej bez zmian.
drop policy if exists user_state_odczyt_pracownika on public.user_state;
create policy user_state_odczyt_pracownika on public.user_state
  for select to authenticated
  using (exists (
    select 1 from public.dostep_pracownika d
    where d.wlasciciel_id = user_state.user_id
      and d.pracownik_id  = auth.uid()
  ));

-- ── Sprawdzenie ───────────────────────────────────────────────────────────────
select
  (select count(*) from pg_tables where schemaname='public' and tablename='dostep_pracownika') as tabela_jest,
  (select relrowsecurity from pg_class where relname='dostep_pracownika')                      as rls_wlaczone,
  (select count(*) from pg_policies where tablename='dostep_pracownika')                       as polityk_dostepu,
  (select count(*) from pg_policies where tablename='user_state')                              as polityk_user_state;
-- Poprawnie: 1 / true / 2 / (dotychczasowe + 1)

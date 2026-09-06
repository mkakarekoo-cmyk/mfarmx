-- ═══════════════════════════════════════════════════════════════════════════════
-- ZGŁOSZENIA PRACOWNIKÓW („Do zrobienia") — 05.09.2026
-- Uruchom w: Supabase → SQL Editor.  Wymaga wcześniejszego schema_pracownicy.sql.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- PROBLEM, KTÓRY TO ROZWIĄZUJE: pracownik ma móc zgłosić „w Axionie trzeba wymienić
-- lampę". Całe gospodarstwo siedzi jednak w JEDNYM wierszu `user_state` należącym do
-- właściciela, a pracownik ma do niego prawo wyłącznie do ODCZYTU — bo zapis oznacza
-- nadpisanie całego dokumentu: pól, maszyn, finansów, bydła. Jedna pomyłka i gospodarstwo
-- znika. Dlatego zgłoszenie nie może iść przez `user_state`.
--
-- ROZWIĄZANIE: własna tabela z własnym RLS. To PIERWSZY byt wyjęty z jsonb-a do
-- prawdziwej tabeli i wzorzec dla następnych (zadania, pola, maszyny).
--
-- 🔑 ZASADA: pracownik DOPISUJE swoje wiersze i widzi tylko swoje. Właściciel widzi
-- i zmienia wszystkie wiersze SWOJEGO gospodarstwa. Nikt nie widzi cudzego gospodarstwa.
-- `wlasciciel_id` NIE jest brany na wiarę z przeglądarki — polityka INSERT sprawdza
-- w `dostep_pracownika`, że piszący naprawdę należy do tego gospodarstwa.

create table if not exists public.zgloszenia (
  id            uuid primary key default gen_random_uuid(),
  wlasciciel_id uuid not null references auth.users(id) on delete cascade,
  autor_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  worker_id     text,                          -- id z `state.workers` — kto zgłosił
  zglosil       text,                          -- imię do wyświetlenia, gdy worker_id nic nie mówi
  nazwa         text not null check (length(trim(nazwa)) between 1 and 300),
  kategoria     text not null default 'inne'
                check (kategoria in ('pole','warsztat','transport','gospodarstwo','inne')),
  priorytet     text not null default 'normalny'
                check (priorytet in ('niski','normalny','pilny')),
  maszyna_id    text,
  pole_id       text,
  uwagi         text,
  -- Gospodarz przenosi zgłoszenie do swojej listy „Do zrobienia" w `state.tasks`.
  -- Ten znacznik pilnuje, żeby nie wracało przy każdym odświeżeniu.
  przeniesione  boolean not null default false,
  utworzono     timestamptz not null default now()
);

create index if not exists zgloszenia_wlasciciel_idx
  on public.zgloszenia (wlasciciel_id, przeniesione);
create index if not exists zgloszenia_autor_idx on public.zgloszenia (autor_id);

alter table public.zgloszenia enable row level security;

-- ── Właściciel: pełne władanie zgłoszeniami swojego gospodarstwa ──────────────
drop policy if exists zgloszenia_wlasciciel on public.zgloszenia;
create policy zgloszenia_wlasciciel on public.zgloszenia
  for all to authenticated
  using      (wlasciciel_id = auth.uid())
  with check (wlasciciel_id = auth.uid());

-- ── Pracownik: widzi WYŁĄCZNIE to, co sam zgłosił ────────────────────────────
-- (§21 — „Moje zgłoszenia", bez wglądu w administracyjną listę całego gospodarstwa)
drop policy if exists zgloszenia_autor_odczyt on public.zgloszenia;
create policy zgloszenia_autor_odczyt on public.zgloszenia
  for select to authenticated
  using (autor_id = auth.uid());

-- ── Pracownik: dopisuje zgłoszenie do gospodarstwa, do którego NAPRAWDĘ należy ─
-- ⚠️ `wlasciciel_id` przychodzi z przeglądarki, więc nie wolno mu wierzyć. Warunek
-- sprawdza powiązanie w `dostep_pracownika` — bez tego dowolny zalogowany użytkownik
-- mógłby wrzucać wpisy do cudzego gospodarstwa.
drop policy if exists zgloszenia_autor_zapis on public.zgloszenia;
create policy zgloszenia_autor_zapis on public.zgloszenia
  for insert to authenticated
  with check (
    autor_id = auth.uid()
    and exists (
      select 1 from public.dostep_pracownika d
       where d.pracownik_id = auth.uid()
         and d.wlasciciel_id = zgloszenia.wlasciciel_id
    )
  );

-- Pracownik NIE dostaje UPDATE ani DELETE: zgłoszenie raz wysłane jest śladem zdarzenia.
-- Rozpatruje je gospodarz, a historia „kto zauważył" ma zostać nietknięta.

-- ── Sprawdzenie po wdrożeniu ──────────────────────────────────────────────────
-- select tablename, policyname, cmd from pg_policies where tablename = 'zgloszenia';
-- Oczekiwane 3 polityki: zgloszenia_wlasciciel (ALL), zgloszenia_autor_odczyt (SELECT),
-- zgloszenia_autor_zapis (INSERT).

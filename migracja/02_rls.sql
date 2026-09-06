-- ═══════════════════════════════════════════════════════════════════════════════
-- M-FarmX — RLS: IZOLACJA GOSPODARSTW, krok 2/4
-- Uruchom PO 01_schemat.sql.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- 🔑 TU MIESZKA BEZPIECZEŃSTWO. Ukrywanie elementów w interfejsie nie jest ochroną —
-- przeglądarka jest w rękach użytkownika i każdy zapytanie może podmienić. Jedyne, co
-- naprawdę broni danych, to poniższe polityki.
--
-- ⚠️ ŻADNA polityka nie przyjmuje `farm_id` z żądania jako podstawy dostępu. Przynależność
-- czytamy WYŁĄCZNIE z `farm_members` po `auth.uid()`. Podmiana farm_id w payloadzie kończy
-- się odmową, bo warunek i tak sprawdza członkostwo.

-- ── Funkcje pomocnicze ────────────────────────────────────────────────────────
-- SECURITY DEFINER jest tu konieczne: polityka na `farm_members` musiałaby czytać
-- `farm_members`, co daje nieskończoną rekurencję. Funkcja omija RLS w kontrolowany
-- sposób — zwraca WYŁĄCZNIE farmy wołającego i nic poza tym.
-- `set search_path` zamyka drogę do podstawienia własnych tabel pod te nazwy.

create or replace function public.moje_farmy()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select farm_id from public.farm_members
   where user_id = auth.uid() and is_active
$$;

create or replace function public.jestem_adminem(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.farm_members
     where user_id = auth.uid() and farm_id = f and is_active and role = 'FARM_ADMIN')
$$;

-- Id pracownika zalogowanego użytkownika w danym gospodarstwie — po nim rozstrzygamy
-- „to moje zadanie". Bez tego pracownik widziałby cały grafik gospodarstwa.
create or replace function public.moj_employee(f uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select id from public.employees
   where user_id = auth.uid() and farm_id = f and is_active
   limit 1
$$;

create or replace function public.zarzadzam_grafikiem(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.jestem_adminem(f) or exists (
    select 1 from public.employees
     where user_id = auth.uid() and farm_id = f and is_active and can_manage_schedule)
$$;

-- Uprawnienia finansowe modułu Skup trzymamy osobno od operacyjnych: człowiek na wadze
-- ma wpisywać tony i rejestracje, ale nie musi widzieć cen ani sald klientów (§34).
create or replace function public.widze_finanse(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.jestem_adminem(f) or exists (
    select 1 from public.employees
     where user_id = auth.uid() and farm_id = f and is_active
       and coalesce((module_visibility->>'skupFinanse')::boolean, false))
$$;

create or replace function public.widze_skup(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.jestem_adminem(f) or exists (
    select 1 from public.employees
     where user_id = auth.uid() and farm_id = f and is_active
       and coalesce((module_visibility->>'skup')::boolean, false))
$$;

revoke execute on function public.moje_farmy(), public.jestem_adminem(uuid),
  public.moj_employee(uuid), public.zarzadzam_grafikiem(uuid),
  public.widze_finanse(uuid), public.widze_skup(uuid) from public, anon;
grant execute on function public.moje_farmy(), public.jestem_adminem(uuid),
  public.moj_employee(uuid), public.zarzadzam_grafikiem(uuid),
  public.widze_finanse(uuid), public.widze_skup(uuid) to authenticated;

-- ── Włączenie RLS wszędzie ────────────────────────────────────────────────────
-- ⚠️ Tabela bez RLS w Supabase jest otwarta dla każdego zalogowanego. Lista jest
-- wypisana jawnie, żeby dodanie nowej tabeli bez polityki rzucało się w oczy.
do $$
declare t text;
begin
  foreach t in array array['farms','farm_members','employees','fields','vehicles',
                           'tasks','todos','notifications'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ── FARMS ─────────────────────────────────────────────────────────────────────
drop policy if exists farms_select on public.farms;
create policy farms_select on public.farms for select to authenticated
  using (id in (select public.moje_farmy()));

-- Zmieniać dane gospodarstwa może tylko jego administrator.
drop policy if exists farms_update on public.farms;
create policy farms_update on public.farms for update to authenticated
  using (public.jestem_adminem(id)) with check (public.jestem_adminem(id));

-- ⚠️ Brak polityki INSERT i DELETE. Gospodarstwo zakłada funkcja serwerowa
-- (`admin-uzytkownicy`, akcja `utworz-gospodarstwo`), bo razem z farmą musi powstać
-- członkostwo FARM_ADMIN — inaczej powstałaby farma bez właściciela albo, gorzej,
-- każdy zalogowany mógłby zakładać gospodarstwa bez końca.

-- ── FARM_MEMBERS — najczulsza tabela w systemie ───────────────────────────────
drop policy if exists farm_members_select on public.farm_members;
create policy farm_members_select on public.farm_members for select to authenticated
  using (user_id = auth.uid() or public.jestem_adminem(farm_id));

-- ⚠️ CELOWO ZERO polityk INSERT/UPDATE/DELETE dla `authenticated`.
-- Gdyby administrator mógł robić UPDATE z przeglądarki, nie dałoby się politykami
-- powstrzymać go przed zmianą CUDZEJ roli na FARM_ADMIN: `with check` widzi tylko nowy
-- wiersz, nie stary, więc „wolno zmieniać wszystko oprócz roli" jest w RLS niewyrażalne.
-- Każda zmiana członkostwa idzie przez funkcję serwerową, która sprawdza uprawnienia
-- sama. To jest odpowiedź na §12 specyfikacji.

-- ── EMPLOYEES ─────────────────────────────────────────────────────────────────
-- Pracownik widzi kolegów z gospodarstwa — bez tego nie da się narysować Grafiku ani
-- pokazać, kto wykonuje zadanie. To nie są dane wrażliwe w obrębie jednej farmy.
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees for select to authenticated
  using (farm_id in (select public.moje_farmy()));

drop policy if exists employees_admin_zapis on public.employees;
create policy employees_admin_zapis on public.employees for insert to authenticated
  with check (public.jestem_adminem(farm_id));

drop policy if exists employees_admin_update on public.employees;
create policy employees_admin_update on public.employees for update to authenticated
  using (public.jestem_adminem(farm_id)) with check (public.jestem_adminem(farm_id));

drop policy if exists employees_admin_delete on public.employees;
create policy employees_admin_delete on public.employees for delete to authenticated
  using (public.jestem_adminem(farm_id));

-- ⚠️ Zwykły pracownik NIE dostaje UPDATE na swoim wierszu. Mógłby wtedy ustawić sobie
-- `can_manage_schedule = true` i przejąć grafik całego gospodarstwa.

-- ── FIELDS ────────────────────────────────────────────────────────────────────
drop policy if exists fields_select on public.fields;
create policy fields_select on public.fields for select to authenticated
  using (farm_id in (select public.moje_farmy()));

drop policy if exists fields_zapis on public.fields;
create policy fields_zapis on public.fields for all to authenticated
  using (public.jestem_adminem(farm_id)) with check (public.jestem_adminem(farm_id));

-- ── VEHICLES ──────────────────────────────────────────────────────────────────
drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles for select to authenticated
  using (farm_id in (select public.moje_farmy()));

drop policy if exists vehicles_zapis on public.vehicles;
create policy vehicles_zapis on public.vehicles for all to authenticated
  using (public.jestem_adminem(farm_id)) with check (public.jestem_adminem(farm_id));

-- ── TASKS ─────────────────────────────────────────────────────────────────────
-- Kto widzi zadanie: administrator i osoba z prawem do grafiku — wszystkie w swojej
-- farmie; zwykły pracownik — WYŁĄCZNIE swoje.
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select to authenticated
  using (
    farm_id in (select public.moje_farmy())
    and (public.zarzadzam_grafikiem(farm_id)
         or employee_id = public.moj_employee(farm_id))
  );

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks for insert to authenticated
  with check (public.zarzadzam_grafikiem(farm_id));

drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update to authenticated
  using (public.zarzadzam_grafikiem(farm_id))
  with check (public.zarzadzam_grafikiem(farm_id));

drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks for delete to authenticated
  using (public.zarzadzam_grafikiem(farm_id));

-- Pracownik odhacza SWOJE zadanie (rozpoczęcie, zakończenie, wykonanie) — i tylko swoje.
-- ⚠️ `with check` powtarza warunek na `employee_id`, żeby nie dało się przy okazji
-- przepisać zadania na kogoś innego ani przerzucić go do innej farmy.
drop policy if exists tasks_pracownik_update on public.tasks;
create policy tasks_pracownik_update on public.tasks for update to authenticated
  using (farm_id in (select public.moje_farmy())
         and employee_id = public.moj_employee(farm_id))
  with check (farm_id in (select public.moje_farmy())
         and employee_id = public.moj_employee(farm_id));

-- ── TODOS / ZGŁOSZENIA ────────────────────────────────────────────────────────
drop policy if exists todos_select on public.todos;
create policy todos_select on public.todos for select to authenticated
  using (
    farm_id in (select public.moje_farmy())
    and (public.jestem_adminem(farm_id) or created_by = auth.uid())
  );

-- Pracownik zgłasza do SWOJEGO gospodarstwa i pod SWOIM nazwiskiem. Oba warunki są
-- potrzebne: pierwszy blokuje pisanie do cudzej farmy, drugi — podszycie się pod kolegę.
drop policy if exists todos_insert on public.todos;
create policy todos_insert on public.todos for insert to authenticated
  with check (
    farm_id in (select public.moje_farmy())
    and created_by = auth.uid()
    and (employee_id is null or employee_id = public.moj_employee(farm_id))
  );

drop policy if exists todos_admin on public.todos;
create policy todos_admin on public.todos for update to authenticated
  using (public.jestem_adminem(farm_id)) with check (public.jestem_adminem(farm_id));

drop policy if exists todos_admin_delete on public.todos;
create policy todos_admin_delete on public.todos for delete to authenticated
  using (public.jestem_adminem(farm_id));

-- ⚠️ Pracownik nie dostaje UPDATE ani DELETE na zgłoszeniu. Raz wysłane jest śladem
-- zdarzenia; rozpatruje je gospodarz, a historia „kto zauważył" ma zostać nietknięta.

-- ── NOTIFICATIONS ─────────────────────────────────────────────────────────────
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
  using (
    farm_id in (select public.moje_farmy())
    and (user_id = auth.uid() or (user_id is null and public.jestem_adminem(farm_id)))
  );

-- Oznaczenie „przeczytane" to jedyna zmiana, jakiej odbiorca może dokonać.
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
  using (farm_id in (select public.moje_farmy())
         and (user_id = auth.uid() or (user_id is null and public.jestem_adminem(farm_id))))
  with check (farm_id in (select public.moje_farmy()));

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications for insert to authenticated
  with check (farm_id in (select public.moje_farmy()));

-- ── Kontrola po wdrożeniu ─────────────────────────────────────────────────────
-- 1. Każda tabela ma RLS:
--    select relname, relrowsecurity, relforcerowsecurity from pg_class
--     where relname in ('farms','farm_members','employees','fields','vehicles',
--                       'tasks','todos','notifications');
--    → relrowsecurity musi być true WSZĘDZIE.
--
-- 2. Nigdzie nie ma polityki „dla wszystkich zalogowanych":
--    select tablename, policyname, qual from pg_policies
--     where schemaname='public' and (qual = 'true' or qual is null);
--    → oczekiwany wynik: 0 wierszy.
--
-- 3. Nikt nie może pisać do farm_members z klienta:
--    select policyname, cmd from pg_policies where tablename='farm_members';
--    → wyłącznie jedna pozycja, cmd = SELECT.

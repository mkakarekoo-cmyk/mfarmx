-- ═══════════════════════════════════════════════════════════════════════════════
-- M-FarmX — MIGRACJA DANYCH: user_state.data (jsonb) → tabele, krok 3/4
-- Uruchom PO 01 i 02.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- ⚠️ TEN SKRYPT NICZEGO NIE KASUJE. `user_state` zostaje nietknięty jako kopia na czas
-- pilotażu. Żadnego DROP-a dziś ani jutro — dopóki gospodarstwa nie przepracują na nowych
-- tabelach kilku dni, stary dokument jest jedyną siatką bezpieczeństwa.
--
-- Skrypt jest IDEMPOTENTNY: uruchomiony drugi raz nie zduplikuje danych (rozpoznaje wiersze
-- po `legacy_id`). Można go puścić ponownie po poprawce w danych źródłowych.

-- ── Ślad po starych identyfikatorach ──────────────────────────────────────────
-- Stare id (`uid()` z przeglądarki) NIE są UUID-ami, więc nie mogą zostać kluczami
-- głównymi. Zapamiętujemy je obok — po nich odtwarzamy powiązania zadanie↔pole↔maszyna
-- i po nich aplikacja rozpoznaje wpisy, które już przeniosła.
alter table public.employees add column if not exists legacy_id text;
alter table public.fields    add column if not exists legacy_id text;
alter table public.vehicles  add column if not exists legacy_id text;
alter table public.tasks     add column if not exists legacy_id text;
alter table public.farms     add column if not exists legacy_user_id uuid;

create unique index if not exists employees_legacy_idx on public.employees (farm_id, legacy_id) where legacy_id is not null;
create unique index if not exists fields_legacy_idx    on public.fields    (farm_id, legacy_id) where legacy_id is not null;
create unique index if not exists vehicles_legacy_idx  on public.vehicles  (farm_id, legacy_id) where legacy_id is not null;
create unique index if not exists tasks_legacy_idx     on public.tasks     (farm_id, legacy_id) where legacy_id is not null;
create unique index if not exists farms_legacy_idx     on public.farms     (legacy_user_id) where legacy_user_id is not null;

-- ── Funkcja migrująca jedno gospodarstwo ──────────────────────────────────────
-- SECURITY DEFINER, bo czyta `user_state` wszystkich i pisze do tabel z RLS. Wołana
-- ręcznie z SQL Editora (rola postgres), nigdy z przeglądarki — patrz REVOKE na końcu.
create or replace function public.migruj_gospodarstwo(p_user_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  d          jsonb;
  v_farm     uuid;
  v_nazwa    text;
  el         jsonb;
  n_prac int := 0; n_pol int := 0; n_masz int := 0; n_zad int := 0;
  v_emp uuid; v_pole uuid; v_poj uuid; v_narz uuid;
  v_start timestamptz; v_koniec timestamptz;
  v_typ text;
begin
  select data into d from public.user_state where user_id = p_user_id;
  if d is null or d = '{}'::jsonb then
    return 'POMINIĘTO: brak danych dla '||p_user_id;
  end if;

  v_nazwa := coalesce(nullif(trim(d#>>'{farm,nazwa}'), ''), 'Gospodarstwo');

  -- 1. FARMA -------------------------------------------------------------------
  select id into v_farm from public.farms where legacy_user_id = p_user_id;
  if v_farm is null then
    insert into public.farms (name, created_by, legacy_user_id, settings)
    values (v_nazwa, p_user_id, p_user_id,
            jsonb_build_object('cropColors', coalesce(d->'cropColors','{}'::jsonb),
                               'ui',         coalesce(d->'ui','{}'::jsonb),
                               'settings',   coalesce(d->'settings','{}'::jsonb)))
    returning id into v_farm;
  else
    update public.farms set name = v_nazwa where id = v_farm;
  end if;

  -- 2. CZŁONKOSTWO — właściciel dokumentu zostaje administratorem swojej farmy -----
  insert into public.farm_members (farm_id, user_id, role, is_active)
  values (v_farm, p_user_id, 'FARM_ADMIN', true)
  on conflict (farm_id, user_id) do update set role='FARM_ADMIN', is_active=true;

  -- 3. PRACOWNICY ---------------------------------------------------------------
  for el in select * from jsonb_array_elements(coalesce(d->'workers','[]'::jsonb)) loop
    insert into public.employees (farm_id, legacy_id, first_name, last_name, email, phone,
                                  position, color, is_active, can_manage_schedule, module_visibility)
    values (
      v_farm, el->>'id',
      split_part(coalesce(el->>'imie',''), ' ', 1),
      nullif(regexp_replace(coalesce(el->>'imie',''), '^\S+\s*', ''), ''),
      nullif(el#>>'{konto,email}',''),
      nullif(el->>'telefon',''),
      nullif(el->>'rola',''),
      nullif(el->>'kolor',''),
      coalesce((el->>'aktywny')::boolean, true),
      coalesce((el#>>'{uprawnienia,grafikZarzadza}')::boolean, false),
      coalesce(el->'uprawnienia','{}'::jsonb)
    )
    on conflict (farm_id, legacy_id) where legacy_id is not null
    do update set first_name=excluded.first_name, last_name=excluded.last_name,
                  email=excluded.email, phone=excluded.phone, position=excluded.position,
                  color=excluded.color, is_active=excluded.is_active,
                  can_manage_schedule=excluded.can_manage_schedule,
                  module_visibility=excluded.module_visibility;
    n_prac := n_prac + 1;
  end loop;

  -- 4. POLA ---------------------------------------------------------------------
  -- ⚠️ Obrys przenosimy DOSŁOWNIE, bez przeliczania. Format [[lat,lng],…] jest ten sam,
  -- którego używa Leaflet — każda konwersja to okazja do zgubienia wierzchołka.
  for el in select * from jsonb_array_elements(coalesce(d->'fields','[]'::jsonb)) loop
    insert into public.fields (farm_id, legacy_id, name, area_ha, geometry, location, seasons)
    values (v_farm, el->>'id', coalesce(el->>'nazwa',''),
            nullif(replace(coalesce(el->>'powierzchnia_ha',''), ',', '.'),'')::numeric,
            el->'geo', nullif(el->>'lokalizacja',''),
            coalesce(el->'sezony','[]'::jsonb))
    on conflict (farm_id, legacy_id) where legacy_id is not null
    do update set name=excluded.name, area_ha=excluded.area_ha,
                  geometry=excluded.geometry, location=excluded.location,
                  seasons=excluded.seasons;
    n_pol := n_pol + 1;
  end loop;

  -- 5. MASZYNY ------------------------------------------------------------------
  for el in select * from jsonb_array_elements(coalesce(d->'machines','[]'::jsonb)) loop
    insert into public.vehicles (farm_id, legacy_id, name, brand, model, type,
                                 registration_number, year, manual_status,
                                 machine_hours, service_interval, services, notes)
    values (v_farm, el->>'id', coalesce(el->>'nazwa',''),
            nullif(el->>'marka',''), nullif(el->>'model',''), nullif(el->>'typ',''),
            nullif(el->>'nr_rej',''), nullif(el->>'rok','')::smallint,
            -- Do bazy trafia WYŁĄCZNIE stan ustawiony ręcznie. „pracuje" bywało zapisane
            -- w starym dokumencie jako domyślne — to stan WYLICZANY z zadań i zapisany
            -- kłamałby od pierwszej minuty. Zamieniamy go na NULL.
            case when lower(coalesce(el->>'status','')) in ('awaria','serwis','niedostępna')
                 then lower(el->>'status') end,
            nullif(replace(coalesce(el->>'mth',''), ',', '.'),'')::numeric,
            nullif(el->>'interwal','')::integer,
            coalesce(el->'przeglady','[]'::jsonb),
            nullif(el->>'notatki',''))
    on conflict (farm_id, legacy_id) where legacy_id is not null
    do update set name=excluded.name, brand=excluded.brand, model=excluded.model,
                  type=excluded.type, registration_number=excluded.registration_number,
                  manual_status=excluded.manual_status, machine_hours=excluded.machine_hours,
                  service_interval=excluded.service_interval, services=excluded.services;
    n_masz := n_masz + 1;
  end loop;

  -- 6. ZADANIA ------------------------------------------------------------------
  for el in select * from jsonb_array_elements(coalesce(d->'schedule','[]'::jsonb)) loop
    -- Powiązania odtwarzamy po starych id, w obrębie TEJ farmy. Wskazanie spoza niej
    -- zostaje NULL-em — trigger spójności i tak by go nie przyjął.
    select id into v_emp  from public.employees where farm_id=v_farm and legacy_id = el->>'workerId';
    select id into v_pole from public.fields    where farm_id=v_farm and legacy_id = el->>'poleId';
    select id into v_poj  from public.vehicles  where farm_id=v_farm and legacy_id = el->>'ciagnikId';
    select id into v_narz from public.vehicles  where farm_id=v_farm and legacy_id = el->>'maszynaId';

    -- Data + godzina → znacznik czasu. Brak godzin = praca całodniowa; zostawiamy
    -- samą datę, żeby nie wymyślać godzin, których nikt nie zapisał.
    v_start := case when el->>'date' is null then null
                    else (el->>'date')::date + coalesce(nullif(el->>'od','')::time, '00:00'::time) end;
    v_koniec := case when el->>'date' is null or nullif(el->>'do','') is null then null
                    else (el->>'date')::date + (el->>'do')::time end;

    v_typ := case coalesce(el->>'rodzaj','polowe')
               when 'warsztat' then 'WORKSHOP'
               when 'transport' then 'TRANSPORT'
               when 'gospodarcze' then 'FARM'
               when 'urlop' then 'OTHER'
               when 'inne' then 'OTHER'
               else 'FIELD' end;

    insert into public.tasks (farm_id, legacy_id, title, type, work_kind, employee_id,
                              field_id, vehicle_id, machine_id, planned_start, planned_end,
                              status, priority, description, notes, completion, asset_source, customer)
    values (v_farm, el->>'id',
            coalesce(nullif(el->>'zadanie',''), nullif(el->>'zajecie',''), 'Zadanie'),
            v_typ, nullif(el->>'rodzaj',''), v_emp, v_pole, v_poj, v_narz,
            v_start, v_koniec,
            case when coalesce(el->>'status','zaplanowane')
                      in ('zaplanowane','rozpoczete','wykonane','anulowane')
                 then el->>'status' else 'zaplanowane' end,
            case when coalesce(el->>'priorytet','normalny')
                      in ('niski','normalny','pilny')
                 then el->>'priorytet' else 'normalny' end,
            nullif(el->>'opis',''), nullif(el->>'uwagi',''), el->'wykonanie',
            case when coalesce(el->>'zrodlo','OWN')='CUSTOMER' then 'CUSTOMER' else 'OWN' end,
            nullif(el->>'klient',''))
    on conflict (farm_id, legacy_id) where legacy_id is not null
    do update set title=excluded.title, type=excluded.type, work_kind=excluded.work_kind,
                  employee_id=excluded.employee_id, field_id=excluded.field_id,
                  vehicle_id=excluded.vehicle_id, machine_id=excluded.machine_id,
                  planned_start=excluded.planned_start, planned_end=excluded.planned_end,
                  status=excluded.status, priority=excluded.priority,
                  description=excluded.description, notes=excluded.notes,
                  completion=excluded.completion;
    n_zad := n_zad + 1;
  end loop;

  -- 7. ZGŁOSZENIA („do zrobienia") ---------------------------------------------
  for el in select * from jsonb_array_elements(coalesce(d->'tasks','[]'::jsonb)) loop
    if not exists (select 1 from public.todos
                    where farm_id=v_farm and title = coalesce(el->>'nazwa','')
                      and created_at::date = coalesce((el->>'zgloszono')::timestamptz, now())::date) then
      select id into v_emp from public.employees where farm_id=v_farm and legacy_id = el->>'zglosilWorkerId';
      insert into public.todos (farm_id, employee_id, created_by, title, category, priority, notes, status, created_at)
      values (v_farm, v_emp, p_user_id, coalesce(nullif(el->>'nazwa',''),'—'),
              case coalesce(el->>'kategoria','inne')
                when 'pole' then 'FIELD' when 'warsztat' then 'WORKSHOP'
                when 'transport' then 'TRANSPORT' when 'gospodarstwo' then 'FARM' else 'OTHER' end,
              case when coalesce(el->>'priorytet','normalny') in ('niski','normalny','pilny')
                   then el->>'priorytet' else 'normalny' end,
              nullif(el->>'uwagi',''),
              case when coalesce(el->>'status','NEW') in ('NEW','PLANNED','IN_PROGRESS','DONE','REJECTED')
                   then el->>'status' else 'NEW' end,
              coalesce((el->>'zgloszono')::timestamptz, now()));
    end if;
  end loop;

  -- 8. PRODUKTY SKUPU — zestaw startowy, jeśli tabela istnieje -------------------
  if to_regclass('public.grain_products') is not null then
    insert into public.grain_products (farm_id, name, sort)
    select v_farm, x.n, x.i
      from (values ('Kukurydza',1),('Pszenica',2),('Rzepak',3),('Jęczmień',4),
                   ('Żyto',5),('Owies',6),('Pszenżyto',7),('Soja',8),('Inne',9)) as x(n,i)
    on conflict (farm_id, name) do nothing;
  end if;

  return format('Farma "%s" (%s): %s prac., %s pól, %s maszyn, %s zadań',
                v_nazwa, v_farm, n_prac, n_pol, n_masz, n_zad);
end $$;

revoke execute on function public.migruj_gospodarstwo(uuid) from public, anon, authenticated;

-- ── URUCHOMIENIE ──────────────────────────────────────────────────────────────
-- Migruje KAŻDE konto, które ma niepusty dokument:
--
--   select public.migruj_gospodarstwo(user_id)
--     from public.user_state
--    where data is not null and data <> '{}'::jsonb;
--
-- ── SPRAWDZENIE PO MIGRACJI (zanim aplikacja zacznie czytać nowe tabele) ──────
-- select f.name,
--        (select count(*) from employees e where e.farm_id=f.id) as pracownicy,
--        (select count(*) from fields    x where x.farm_id=f.id) as pola,
--        (select count(*) from vehicles  v where v.farm_id=f.id) as maszyny,
--        (select count(*) from tasks     t where t.farm_id=f.id) as zadania
--   from farms f order by f.created_at;
--
-- Porównaj z liczbami w starym dokumencie:
-- select user_id,
--        jsonb_array_length(data->'workers')  as pracownicy,
--        jsonb_array_length(data->'fields')   as pola,
--        jsonb_array_length(data->'machines') as maszyny,
--        jsonb_array_length(data->'schedule') as zadania
--   from user_state where data <> '{}'::jsonb;
--
-- ⚠️ Zadania bez pola/maszyny są NORMALNE (praca warsztatowa). Ale zadanie, które
-- w dokumencie MIAŁO `poleId`, a w tabeli ma `field_id IS NULL`, znaczy, że pole się
-- nie przeniosło — sprawdź, zanim ruszysz dalej:
-- select count(*) from tasks where field_id is null and legacy_id is not null;

-- ═══════════════════════════════════════════════════════════════════════════════
-- M-FarmX — SCHEMAT WIELODZIERŻAWNY (multi-tenant), krok 1/4
-- Uruchom w: Supabase → SQL Editor. Kolejność: 01 → 02 → 03 → 04.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- CO TO ZMIENIA: dotąd całe gospodarstwo było JEDNYM wierszem `user_state.data` (jsonb),
-- a izolacja opierała się na „twój wiersz = twoje gospodarstwo". Działało dla jednego
-- rolnika na konto, ale nie da się na tym zbudować gospodarstwa z wieloma kontami ani
-- pilotażu kilku gospodarstw naraz.
--
-- ⚠️ TEN PLIK NICZEGO NIE KASUJE. `user_state` zostaje nietknięty jako kopia na czas
-- pilotażu. Skrypt 03 KOPIUJE z niego dane; DROP nie następuje ani dziś, ani jutro.
--
-- 🔑 ZASADA NACZELNA: `farm_id` w każdym wierszu, a przynależność użytkownika wynika
-- WYŁĄCZNIE z `farm_members`. Żadna polityka nie bierze `farm_id` na wiarę z przeglądarki.

-- ── FARMS ─────────────────────────────────────────────────────────────────────
create table if not exists public.farms (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 200),
  address     text,
  postal_code text,
  city        text,
  -- Siedziba gospodarstwa: mapa otwiera się tutaj, gdy nie ma jeszcze żadnych pól.
  latitude    double precision check (latitude between -90 and 90),
  longitude   double precision check (longitude between -180 and 180),
  map_zoom    smallint default 13 check (map_zoom between 1 and 20),
  -- jsonb zostaje TYLKO na drobne ustawienia widoku (kolory upraw, zwinięte sekcje).
  -- ⚠️ Nie wolno tu wracać z polami, maszynami, ludźmi ani zadaniami.
  settings    jsonb not null default '{}'::jsonb,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ── FARM_MEMBERS — JEDYNE źródło prawdy o przynależności ──────────────────────
create table if not exists public.farm_members (
  id         uuid primary key default gen_random_uuid(),
  farm_id    uuid not null references public.farms(id) on delete cascade,
  user_id    uuid not null references auth.users(id)  on delete cascade,
  role       text not null default 'EMPLOYEE' check (role in ('FARM_ADMIN','EMPLOYEE')),
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (farm_id, user_id)          -- jedno członkostwo na parę
);
create index if not exists farm_members_user_idx on public.farm_members (user_id) where is_active;
create index if not exists farm_members_farm_idx on public.farm_members (farm_id);

-- ── EMPLOYEES ─────────────────────────────────────────────────────────────────
-- Pracownik ≠ konto. Employee może istnieć BEZ `user_id` — jest w Grafiku, zanim
-- dostanie zaproszenie. Po założeniu konta dopinamy `user_id`.
create table if not exists public.employees (
  id         uuid primary key default gen_random_uuid(),
  farm_id    uuid not null references public.farms(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete set null,
  first_name text not null default '',
  last_name  text not null default '',
  email      text,
  phone      text,
  position   text,
  color      text,                                    -- kolor w Grafiku
  is_active  boolean not null default true,
  can_manage_schedule boolean not null default false,
  -- Widoczność modułów i drobne uprawnienia. ⚠️ To USTAWIENIA WIDOKU, nie zabezpieczenie —
  -- prawdziwe granice wyznacza RLS niżej. Nie przenoś tu niczego, co ma chronić dane.
  module_visibility jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, user_id)                           -- jedno konto = jeden pracownik w farmie
);
create index if not exists employees_farm_idx on public.employees (farm_id) where is_active;
create index if not exists employees_user_idx on public.employees (user_id);

-- ── FIELDS ────────────────────────────────────────────────────────────────────
create table if not exists public.fields (
  id        uuid primary key default gen_random_uuid(),
  farm_id   uuid not null references public.farms(id) on delete cascade,
  name      text not null default '',
  area_ha   numeric(10,2),
  crop      text,
  variety   text,
  -- Obrys w formacie, którego UŻYWA JUŻ Leaflet: [[lat,lng], …]. Zapisany jako jsonb,
  -- żeby migracja niczego nie przeliczała i nie zgubiła ani jednego wierzchołka.
  -- (PostGIS byłby ładniejszy, ale wymagałby konwersji w obie strony — nie dziś.)
  geometry  jsonb,
  latitude  double precision,
  longitude double precision,
  location  text,
  notes     text,
  -- Sezony (płodozmian, zabiegi, plony) zostają na razie w jsonb: to zagnieżdżona
  -- historia czytana wyłącznie w kontekście pola i nikt nie pyta o nią z zewnątrz.
  -- Wyjdzie do tabel w kroku 2 migracji, po pilotażu.
  seasons   jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fields_farm_idx on public.fields (farm_id);

-- ── VEHICLES ──────────────────────────────────────────────────────────────────
create table if not exists public.vehicles (
  id       uuid primary key default gen_random_uuid(),
  farm_id  uuid not null references public.farms(id) on delete cascade,
  name     text not null default '',
  brand    text,
  model    text,
  type     text,
  registration_number text,
  vin      text,
  year     smallint,
  -- ⚠️ TYLKO stan ustawiony RĘCZNIE (awaria/serwis/niedostępna). Stany „pracuje"
  -- i „warsztat" WYNIKAJĄ z zadań i nie wolno ich tu zapisywać — zapisany stan
  -- rozjedzie się z grafikiem przy pierwszej zmianie. Patrz statusMaszyny() w apce.
  manual_status text check (manual_status in ('dostępna','awaria','serwis','niedostępna')),
  machine_hours numeric(10,1),
  service_interval integer,
  services jsonb not null default '[]'::jsonb,        -- przeglądy; jak seasons — krok 2
  notes    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists vehicles_farm_idx on public.vehicles (farm_id);

-- ── TASKS — centralny obiekt systemu ──────────────────────────────────────────
create table if not exists public.tasks (
  id       uuid primary key default gen_random_uuid(),
  farm_id  uuid not null references public.farms(id) on delete cascade,
  title    text not null default '',
  -- Miejsce pracy. NIE każde zadanie ma pole: naprawa dzieje się w warsztacie.
  type     text not null default 'FIELD'
           check (type in ('FIELD','WORKSHOP','TRANSPORT','FARM','OTHER')),
  work_kind text,                                     -- rodzaj (orka/oprysk/naprawa…)
  employee_id uuid references public.employees(id) on delete set null,
  field_id    uuid references public.fields(id)    on delete set null,
  vehicle_id  uuid references public.vehicles(id)  on delete set null,   -- ciągnik/pojazd
  machine_id  uuid references public.vehicles(id)  on delete set null,   -- narzędzie
  planned_start timestamptz,
  planned_end   timestamptz,
  actual_start  timestamptz,
  actual_end    timestamptz,
  status   text not null default 'zaplanowane'
           check (status in ('zaplanowane','rozpoczete','wykonane','anulowane')),
  priority text default 'normalny' check (priority in ('niski','normalny','pilny')),
  asset_source text default 'OWN' check (asset_source in ('OWN','CUSTOMER')),
  customer text,
  description text,
  notes    text,
  completion jsonb,                                   -- wykonanie (ha, godziny, mth, środek)
  created_by  uuid references auth.users(id) on delete set null,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tasks_farm_date_idx on public.tasks (farm_id, planned_start);
create index if not exists tasks_employee_idx  on public.tasks (employee_id);
create index if not exists tasks_vehicle_idx   on public.tasks (vehicle_id);

-- ⚠️ NAJWAŻNIEJSZY WARUNEK SPÓJNOŚCI (§7 specyfikacji).
-- Sam `tasks.farm_id = moja farma` NIE wystarczy: użytkownik z farmy A mógłby utworzyć
-- zadanie w farmie A wskazujące na maszynę farmy B — i przez join wyciągnąć jej nazwę.
-- Klucz obcy tego nie złapie, bo wskazuje na tabelę, nie na dzierżawcę. Stąd trigger.
create or replace function public.tasks_spojnosc_dzierzawcy()
returns trigger
language plpgsql
as $$
declare obca text;
begin
  select x.co into obca from (
    select 'pracownika' as co where new.employee_id is not null
      and not exists (select 1 from public.employees e where e.id=new.employee_id and e.farm_id=new.farm_id)
    union all
    select 'pole'       where new.field_id is not null
      and not exists (select 1 from public.fields f where f.id=new.field_id and f.farm_id=new.farm_id)
    union all
    select 'pojazd'     where new.vehicle_id is not null
      and not exists (select 1 from public.vehicles v where v.id=new.vehicle_id and v.farm_id=new.farm_id)
    union all
    select 'maszynę'    where new.machine_id is not null
      and not exists (select 1 from public.vehicles v where v.id=new.machine_id and v.farm_id=new.farm_id)
  ) x limit 1;

  if obca is not null then
    raise exception 'Zadanie wskazuje na % z innego gospodarstwa', obca
      using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists tasks_spojnosc on public.tasks;
create trigger tasks_spojnosc before insert or update on public.tasks
  for each row execute function public.tasks_spojnosc_dzierzawcy();

-- ── TODO / ZGŁOSZENIA ─────────────────────────────────────────────────────────
-- Tabela `zgloszenia` już istnieje (schema_zgloszenia.sql) i była pierwszym bytem
-- wyjętym z jsonb-a. Tu przestawiamy ją z `wlasciciel_id` na `farm_id`.
create table if not exists public.todos (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text not null check (length(trim(title)) between 1 and 300),
  category    text not null default 'OTHER'
              check (category in ('FIELD','WORKSHOP','TRANSPORT','FARM','OTHER')),
  priority    text not null default 'normalny' check (priority in ('niski','normalny','pilny')),
  vehicle_id  uuid references public.vehicles(id) on delete set null,
  field_id    uuid references public.fields(id)   on delete set null,
  notes       text,
  status      text not null default 'NEW'
              check (status in ('NEW','PLANNED','IN_PROGRESS','DONE','REJECTED')),
  task_id     uuid references public.tasks(id) on delete set null,   -- powstałe zadanie
  planned_by  uuid references auth.users(id) on delete set null,
  planned_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists todos_farm_idx on public.todos (farm_id, status);
create index if not exists todos_autor_idx on public.todos (created_by);

-- ── NOTIFICATIONS ─────────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id       uuid primary key default gen_random_uuid(),
  farm_id  uuid not null references public.farms(id) on delete cascade,
  -- NULL = powiadomienie dla administratorów gospodarstwa (np. nowe zgłoszenie).
  user_id  uuid references auth.users(id) on delete cascade,
  task_id  uuid references public.tasks(id) on delete cascade,
  todo_id  uuid references public.todos(id) on delete cascade,
  type     text not null default 'info',
  channel  text not null default 'in_app' check (channel in ('in_app','email','whatsapp')),
  title    text not null default '',
  message  text,
  created_at timestamptz not null default now(),
  read_at  timestamptz
);
create index if not exists notifications_odbiorca_idx
  on public.notifications (farm_id, user_id, read_at);

-- ── updated_at ────────────────────────────────────────────────────────────────
create or replace function public.dotknij_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['farms','employees','fields','vehicles','tasks'] loop
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I
                    for each row execute function public.dotknij_updated_at()', t, t);
  end loop;
end $$;

-- Sprawdzenie: 8 tabel
-- select table_name from information_schema.tables where table_schema='public'
--   and table_name in ('farms','farm_members','employees','fields','vehicles','tasks','todos','notifications');

-- ═══════════════════════════════════════════════════════════════════════════════
-- My Agro — MODUŁ SKUP / OBRÓT ZBOŻEM
-- Uruchom PO 01_schemat.sql i 02_rls.sql (korzysta z ich funkcji pomocniczych).
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- Zastępuje dwa zeszyty: „skup i koszenie" oraz „sprzedaż i załadunki".
--
-- TRZY DECYZJE, KTÓRE RZĄDZĄ CAŁYM SCHEMATEM:
--
-- 1. DANE FINANSOWE MIESZKAJĄ W OSOBNYCH TABELACH. Nie da się politykami RLS ukryć
--    JEDNEJ KOLUMNY — polityka działa na wiersz. Gdyby cena leżała obok ton, człowiek
--    na wadze, który ma prawo zapisać dostawę, mógłby ją odczytać zapytaniem do API.
--    Dlatego `grain_deliveries` niesie tony i wilgotność, a `grain_delivery_finance`
--    ceny — z własną polityką wymagającą uprawnienia finansowego.
--
-- 2. STAN MAGAZYNU JEST LICZONY Z LEDGERA `grain_movements`, nigdy zapisany. Nie ma
--    pola `current_stock`. Każde przyjęcie, załadunek, korekta i anulowanie dopisuje
--    ruch. Stan = suma ruchów. Zapisany licznik rozjeżdża się po pierwszym anulowaniu.
--
-- 3. NIE KASUJEMY HISTORII. Anulowanie ustawia status i dopisuje ruch ODWRACAJĄCY,
--    a nie usuwa wiersz. Osierocony ruch magazynowy jest gorszy niż brak danych.

-- ── SEZONY ────────────────────────────────────────────────────────────────────
create table if not exists public.grain_seasons (
  id       uuid primary key default gen_random_uuid(),
  farm_id  uuid not null references public.farms(id) on delete cascade,
  year     smallint not null check (year between 2000 and 2100),
  is_open  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (farm_id, year)
);

-- ── PRODUKTY ──────────────────────────────────────────────────────────────────
create table if not exists public.grain_products (
  id        uuid primary key default gen_random_uuid(),
  farm_id   uuid not null references public.farms(id) on delete cascade,
  name      text not null check (length(trim(name)) between 1 and 60),
  sort      smallint not null default 0,
  is_active boolean not null default true,
  unique (farm_id, name)
);

-- ── KLIENCI ───────────────────────────────────────────────────────────────────
-- ⚠️ Jeden klient, wiele dostaw. Zakładanie klienta przy każdej dostawie rozsypuje
-- sezon na dziesiątki „Jan Kowalski" i saldo przestaje być policzalne.
create table if not exists public.customers (
  id           uuid primary key default gen_random_uuid(),
  farm_id      uuid not null references public.farms(id) on delete cascade,
  name         text not null check (length(trim(name)) between 1 and 200),
  company_name text, nip text, phone text, email text,
  address text, postal_code text, city text, notes text,
  is_active    boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists customers_farm_idx on public.customers (farm_id);
create index if not exists customers_szukaj_idx on public.customers
  using gin (to_tsvector('simple', coalesce(name,'')||' '||coalesce(company_name,'')||' '||coalesce(nip,'')));

-- ── POJAZDY KLIENTÓW ──────────────────────────────────────────────────────────
-- Ten sam samochód wraca kilka razy dziennie; podpowiedź po trzech znakach oszczędza
-- dziesiątki wpisów w czasie żniw.
create table if not exists public.customer_vehicles (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  registration_number  text not null check (length(trim(registration_number)) between 1 and 20),
  trailer_registration text,
  driver_name text,
  last_seen   timestamptz,
  created_at  timestamptz not null default now(),
  unique (farm_id, registration_number)
);
create index if not exists customer_vehicles_rej_idx
  on public.customer_vehicles (farm_id, upper(registration_number));

-- ── PRZYJĘCIA — część OPERACYJNA (bez pieniędzy) ──────────────────────────────
create table if not exists public.grain_deliveries (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_id  uuid not null references public.grain_products(id) on delete restrict,
  delivered_at timestamptz not null default now(),

  -- Waga: dziś wpisywana ręcznie w tonach. `tons` jest zwykłą kolumną, nie generowaną —
  -- kolumna generowana uniemożliwiłaby dzisiejszy tryb, w którym brutto/tara są puste.
  -- Gdy dojdzie waga pomostowa, trigger policzy netto z brutto i tary.
  gross_kg    numeric(10,1) check (gross_kg >= 0),
  tare_kg     numeric(10,1) check (tare_kg >= 0),
  tons        numeric(10,3) not null check (tons > 0),
  weight_note_no text,

  moisture    numeric(5,2) check (moisture between 0 and 100),

  -- Koszenie nie zawsze występuje — klient bywa, że przywozi własne ziarno.
  mowed_by_us boolean not null default false,
  mowing_ha   numeric(10,2) check (mowing_ha >= 0),

  registration_number text,
  status      text not null default 'aktywne' check (status in ('aktywne','anulowane')),
  cancelled_at timestamptz, cancelled_by uuid references auth.users(id) on delete set null,
  notes       text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint koszenie_spojne check (mowed_by_us or mowing_ha is null or mowing_ha = 0)
);
create index if not exists deliveries_farm_sezon_idx on public.grain_deliveries (farm_id, season_id, delivered_at desc);
create index if not exists deliveries_klient_idx on public.grain_deliveries (customer_id);

-- ── PRZYJĘCIA — część FINANSOWA (osobna tabela = osobne uprawnienie) ──────────
-- 🔑 TO JEST ODPOWIEDŹ NA §28. Rozdzielenie tabel to jedyny sposób, żeby pracownik
-- z prawem do wpisywania ton NIE MÓGŁ odczytać ceny bezpośrednio przez API.
create table if not exists public.grain_delivery_finance (
  delivery_id uuid primary key references public.grain_deliveries(id) on delete cascade,
  farm_id     uuid not null references public.farms(id) on delete cascade,
  price_per_ton       numeric(10,2) check (price_per_ton >= 0),
  mowing_price_per_ha numeric(10,2) check (mowing_price_per_ha >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ── SPRZEDAŻ / KONTRAKT ───────────────────────────────────────────────────────
-- Kontrakt na 500 t wyjeżdża kilkunastoma samochodami. Bez tego poziomu nie da się
-- odpowiedzieć „ile jeszcze zostało do wywiezienia".
create table if not exists public.grain_sales (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_id  uuid not null references public.grain_products(id) on delete restrict,
  contract_no text,
  contract_tons numeric(10,3) check (contract_tons >= 0),   -- NULL = sprzedaż bez kontraktu
  sold_at     date not null default current_date,
  status      text not null default 'NOWA'
              check (status in ('NOWA','W_REALIZACJI','ZREALIZOWANA','ANULOWANA')),
  notes       text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.grain_sale_finance (
  sale_id uuid primary key references public.grain_sales(id) on delete cascade,
  farm_id uuid not null references public.farms(id) on delete cascade,
  price_per_ton numeric(10,2) check (price_per_ton >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ── ZAŁADUNKI ─────────────────────────────────────────────────────────────────
-- ⚠️ `sale_id` jest NULLOWALNE świadomie: przy wadze nie ma czasu zakładać kontraktu.
-- Szybki załadunek zapisuje się bez niego i można go podpiąć później.
create table if not exists public.grain_loads (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  sale_id     uuid references public.grain_sales(id) on delete set null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_id  uuid not null references public.grain_products(id) on delete restrict,
  loaded_at   timestamptz not null default now(),
  gross_kg    numeric(10,1) check (gross_kg >= 0),
  tare_kg     numeric(10,1) check (tare_kg >= 0),
  tons        numeric(10,3) not null check (tons > 0),
  weight_note_no text,
  moisture    numeric(5,2) check (moisture between 0 and 100),
  registration_number  text,
  trailer_registration text,
  driver_name text,
  document_no text,
  status      text not null default 'aktywny' check (status in ('aktywny','anulowany')),
  cancelled_at timestamptz, cancelled_by uuid references auth.users(id) on delete set null,
  notes       text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists loads_farm_dzien_idx on public.grain_loads (farm_id, loaded_at desc);
create index if not exists loads_rej_idx on public.grain_loads (farm_id, upper(registration_number));
create index if not exists loads_sprzedaz_idx on public.grain_loads (sale_id);

create table if not exists public.grain_load_finance (
  load_id uuid primary key references public.grain_loads(id) on delete cascade,
  farm_id uuid not null references public.farms(id) on delete cascade,
  price_per_ton numeric(10,2) check (price_per_ton >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ── USŁUGI (koszenie i to, co przyjdzie później) ──────────────────────────────
-- Dziś koszenie zapisuje się przy przyjęciu, ale usługa bywa świadczona bez dostawy.
-- Ta tabela nie blokuje transportu, suszenia ani czyszczenia w przyszłości.
create table if not exists public.customer_services (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  delivery_id uuid references public.grain_deliveries(id) on delete set null,
  service_type text not null default 'KOSZENIE'
               check (service_type in ('KOSZENIE','TRANSPORT','SUSZENIE','CZYSZCZENIE','INNE')),
  quantity    numeric(10,2) not null check (quantity >= 0),
  unit        text not null default 'ha',
  performed_at date not null default current_date,
  status      text not null default 'aktywna' check (status in ('aktywna','anulowana')),
  notes       text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.customer_service_finance (
  service_id uuid primary key references public.customer_services(id) on delete cascade,
  farm_id    uuid not null references public.farms(id) on delete cascade,
  price_per_unit numeric(10,2) check (price_per_unit >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ── PŁATNOŚCI ─────────────────────────────────────────────────────────────────
-- Kierunek jest obowiązkowy: z tym samym człowiekiem robimy interesy w obie strony —
-- kupujemy jego kukurydzę (jesteśmy mu winni) i kosimy mu pole (on jest winien nam).
create table if not exists public.grain_payments (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  paid_at     date not null default current_date,
  amount      numeric(12,2) not null check (amount > 0),
  direction   text not null check (direction in ('TO_CUSTOMER','FROM_CUSTOMER')),
  method      text not null default 'przelew' check (method in ('przelew','gotowka','inne')),
  document_no text, notes text,
  status      text not null default 'aktywna' check (status in ('aktywna','anulowana')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists payments_klient_idx on public.grain_payments (farm_id, customer_id, season_id);

-- ── LEDGER MAGAZYNOWY ─────────────────────────────────────────────────────────
-- 🔑 STAN MAGAZYNU = SUMA RUCHÓW. Nie ma pola `current_stock` i nie wolno go dodać.
-- `quantity` jest ZE ZNAKIEM: przyjęcie dodatnie, wydanie ujemne. Dzięki temu stan to
-- zwykłe `sum(quantity)` i żaden typ ruchu nie wymaga osobnej gałęzi w kodzie.
create table if not exists public.grain_movements (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  season_id   uuid not null references public.grain_seasons(id) on delete restrict,
  product_id  uuid not null references public.grain_products(id) on delete restrict,
  movement_type text not null check (movement_type in
    ('DELIVERY','SALE_LOAD','ADJUSTMENT_PLUS','ADJUSTMENT_MINUS',
     'DRYING','CLEANING','LOSS','TRANSFER','REVERSAL')),
  quantity    numeric(12,3) not null check (quantity <> 0),
  -- Rozróżnienie zboża własnego od skupionego — dziś nieużywane w formularzach,
  -- ale bez tej kolumny późniejsze „ile mamy własnej kukurydzy" byłoby niepoliczalne.
  source_origin text not null default 'PURCHASED' check (source_origin in ('OWN','PURCHASED')),
  source_type text check (source_type in ('DELIVERY','LOAD','MANUAL')),
  source_id   uuid,
  note        text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists movements_stan_idx on public.grain_movements (farm_id, season_id, product_id);
create index if not exists movements_zrodlo_idx on public.grain_movements (source_type, source_id);

-- ── AUDYT zmian wrażliwych ────────────────────────────────────────────────────
-- Tony, wilgotność, cena, klient, rejestracja i płatność to dane handlowe — ma być
-- wiadomo, kto zmienił 25,40 t na 26,10 t.
create table if not exists public.grain_audit_log (
  id         bigserial primary key,
  farm_id    uuid not null references public.farms(id) on delete cascade,
  table_name text not null,
  record_id  uuid not null,
  field_name text not null,
  old_value  text,
  new_value  text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists audit_rekord_idx on public.grain_audit_log (table_name, record_id, changed_at desc);

-- ═══ LOGIKA ═══════════════════════════════════════════════════════════════════

-- Netto z brutto i tary (przygotowanie pod wagę pomostową)
create or replace function public.skup_wylicz_netto()
returns trigger language plpgsql as $$
begin
  if new.gross_kg is not null and new.tare_kg is not null then
    if new.tare_kg > new.gross_kg then
      raise exception 'Tara (% kg) nie może być większa od brutto (% kg)', new.tare_kg, new.gross_kg
        using errcode='23514';
    end if;
    new.tons := round((new.gross_kg - new.tare_kg)::numeric / 1000, 3);
  end if;
  return new;
end $$;

-- Spójność dzierżawcy: `farm_id` się zgadza, ale wskazany klient/produkt/sezon/sprzedaż
-- może należeć do innej farmy. Klucz obcy tego NIE widzi — wskazuje tabelę, nie dzierżawcę.
create or replace function public.skup_spojnosc()
returns trigger language plpgsql as $$
declare j jsonb := to_jsonb(new); zla text;
begin
  if j ? 'customer_id' and new.customer_id is not null and not exists (
      select 1 from public.customers c where c.id=new.customer_id and c.farm_id=new.farm_id)
    then zla := 'klienta'; end if;
  if zla is null and j ? 'product_id' and (j->>'product_id') is not null and not exists (
      select 1 from public.grain_products p where p.id=(j->>'product_id')::uuid and p.farm_id=new.farm_id)
    then zla := 'produkt'; end if;
  if zla is null and j ? 'season_id' and (j->>'season_id') is not null and not exists (
      select 1 from public.grain_seasons s where s.id=(j->>'season_id')::uuid and s.farm_id=new.farm_id)
    then zla := 'sezon'; end if;
  if zla is null and j ? 'sale_id' and (j->>'sale_id') is not null and not exists (
      select 1 from public.grain_sales s where s.id=(j->>'sale_id')::uuid and s.farm_id=new.farm_id)
    then zla := 'sprzedaż'; end if;
  if zla is null and j ? 'delivery_id' and (j->>'delivery_id') is not null and not exists (
      select 1 from public.grain_deliveries d where d.id=(j->>'delivery_id')::uuid and d.farm_id=new.farm_id)
    then zla := 'przyjęcie'; end if;
  if zla is not null then
    raise exception 'Wpis wskazuje na % z innego gospodarstwa', zla using errcode='23514';
  end if;
  return new;
end $$;

-- ── Ruch magazynowy powstaje RAZEM z dokumentem, w tej samej transakcji ───────
-- 🔑 To jest odpowiedź na §35: trigger wykonuje się w transakcji polecenia INSERT,
-- więc nie da się zapisać załadunku bez ruchu. Zewnętrzne „najpierw jedno, potem
-- drugie" z aplikacji zostawiłoby osierocone dokumenty przy zerwaniu połączenia.
create or replace function public.skup_ruch_z_dokumentu()
returns trigger language plpgsql as $$
declare znak int; typ text; zrodlo text;
begin
  if tg_table_name = 'grain_deliveries' then znak := 1;  typ := 'DELIVERY';  zrodlo := 'DELIVERY';
  else                                      znak := -1; typ := 'SALE_LOAD'; zrodlo := 'LOAD';
  end if;

  if tg_op = 'INSERT' then
    insert into public.grain_movements (farm_id, season_id, product_id, movement_type,
                                        quantity, source_type, source_id, created_by)
    values (new.farm_id, new.season_id, new.product_id, typ,
            znak * new.tons, zrodlo, new.id, new.created_by);
    return new;
  end if;

  -- Anulowanie: dopisujemy ruch ODWRACAJĄCY. Nie kasujemy pierwotnego — historia ma
  -- pokazywać, że coś przyjechało i zostało cofnięte, a nie że nigdy nie istniało.
  if tg_op = 'UPDATE' and old.status <> new.status then
    if new.status in ('anulowane','anulowany') then
      insert into public.grain_movements (farm_id, season_id, product_id, movement_type,
                                          quantity, source_type, source_id, note, created_by)
      values (new.farm_id, new.season_id, new.product_id, 'REVERSAL',
              -znak * new.tons, zrodlo, new.id, 'anulowanie dokumentu', new.cancelled_by);
    else
      insert into public.grain_movements (farm_id, season_id, product_id, movement_type,
                                          quantity, source_type, source_id, note, created_by)
      values (new.farm_id, new.season_id, new.product_id, typ,
              znak * new.tons, zrodlo, new.id, 'przywrócenie dokumentu', new.updated_by);
    end if;
    return new;
  end if;

  -- Poprawka tonażu na aktywnym dokumencie: różnicowy ruch korygujący.
  if tg_op = 'UPDATE' and old.tons <> new.tons and new.status in ('aktywne','aktywny') then
    insert into public.grain_movements (farm_id, season_id, product_id, movement_type,
                                        quantity, source_type, source_id, note, created_by)
    values (new.farm_id, new.season_id, new.product_id,
            case when znak*(new.tons-old.tons) > 0 then 'ADJUSTMENT_PLUS' else 'ADJUSTMENT_MINUS' end,
            znak * (new.tons - old.tons), zrodlo, new.id,
            format('korekta %s t → %s t', old.tons, new.tons), new.updated_by);
  end if;
  return new;
end $$;

-- ── Audyt pól wrażliwych ──────────────────────────────────────────────────────
create or replace function public.skup_audyt()
returns trigger language plpgsql as $$
declare pola text[] := array['tons','moisture','customer_id','registration_number',
                             'mowing_ha','amount','price_per_ton','status'];
        p text; stara text; nowa text;
begin
  foreach p in array pola loop
    if to_jsonb(old) ? p then
      stara := to_jsonb(old)->>p; nowa := to_jsonb(new)->>p;
      if stara is distinct from nowa then
        insert into public.grain_audit_log (farm_id, table_name, record_id, field_name,
                                            old_value, new_value, changed_by)
        values (new.farm_id, tg_table_name, new.id, p, stara, nowa, auth.uid());
      end if;
    end if;
  end loop;
  return new;
end $$;

-- ── Podpięcie triggerów ───────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['grain_deliveries','grain_loads'] loop
    execute format('drop trigger if exists %I_netto on public.%I', t, t);
    execute format('create trigger %I_netto before insert or update on public.%I
                    for each row execute function public.skup_wylicz_netto()', t, t);
    execute format('drop trigger if exists %I_ruch on public.%I', t, t);
    execute format('create trigger %I_ruch after insert or update on public.%I
                    for each row execute function public.skup_ruch_z_dokumentu()', t, t);
  end loop;

  foreach t in array array['grain_deliveries','grain_loads','grain_sales','grain_payments',
                           'customer_services','customer_vehicles','grain_movements'] loop
    execute format('drop trigger if exists %I_spojnosc on public.%I', t, t);
    execute format('create trigger %I_spojnosc before insert or update on public.%I
                    for each row execute function public.skup_spojnosc()', t, t);
  end loop;

  foreach t in array array['grain_deliveries','grain_loads','grain_payments'] loop
    execute format('drop trigger if exists %I_audyt on public.%I', t, t);
    execute format('create trigger %I_audyt after update on public.%I
                    for each row execute function public.skup_audyt()', t, t);
  end loop;

  foreach t in array array['customers','grain_deliveries','grain_sales','grain_loads'] loop
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I
                    for each row execute function public.dotknij_updated_at()', t, t);
  end loop;
end $$;

-- ═══ WIDOKI ═══════════════════════════════════════════════════════════════════
-- ⚠️ `security_invoker = true` jest OBOWIĄZKOWE w każdym z nich. Bez tego widok
-- wykonuje się z prawami właściciela i omija RLS tabel źródłowych — czyli oddałby
-- dane WSZYSTKICH gospodarstw każdemu zalogowanemu.

-- STAN MAGAZYNU = suma ruchów
create or replace view public.grain_stock with (security_invoker = true) as
select m.farm_id, m.season_id, m.product_id, p.name as product_name,
       sum(m.quantity)                                        as stock_tons,
       sum(m.quantity) filter (where m.source_origin='OWN')       as own_tons,
       sum(m.quantity) filter (where m.source_origin='PURCHASED') as purchased_tons
  from public.grain_movements m
  join public.grain_products p on p.id = m.product_id
 group by m.farm_id, m.season_id, m.product_id, p.name;

-- POSTĘP SPRZEDAŻY — ile z kontraktu już wyjechało
create or replace view public.grain_sale_progress with (security_invoker = true) as
select s.id as sale_id, s.farm_id, s.season_id, s.customer_id, s.product_id,
       s.contract_tons,
       coalesce(l.loaded, 0)                            as loaded_tons,
       greatest(coalesce(s.contract_tons,0) - coalesce(l.loaded,0), 0) as remaining_tons,
       case when coalesce(s.contract_tons,0) > 0
            then round(100 * coalesce(l.loaded,0) / s.contract_tons, 1) end as progress_pct,
       coalesce(l.trucks, 0)                            as truck_count
  from public.grain_sales s
  left join lateral (
    select sum(tons) as loaded, count(*) as trucks
      from public.grain_loads gl
     where gl.sale_id = s.id and gl.status = 'aktywny') l on true;

-- SALDO KLIENTA — WYLICZANE, nigdy zapisane.
-- ⚠️ Nie ma i nie będzie kolumny `owes_money boolean`. Taki znacznik trzeba by odświeżać
-- przy każdej dostawie, usłudze i wpłacie; po pierwszej pomyłce zaczyna kłamać, a rolnik
-- patrzy na niego wypłacając pieniądze.
-- ZNAK (jeden, opisany raz):
--   saldo > 0 → MY jesteśmy winni klientowi;  < 0 → KLIENT winien nam;  = 0 → rozliczony
-- Widok czyta tabele finansowe, więc pracownik bez uprawnienia finansowego dostanie
-- z niego pustkę — i to jest zamierzone.
create or replace view public.customer_balances with (security_invoker = true) as
select c.farm_id, c.id as customer_id, c.name, s.id as season_id, s.year as season_year,
       coalesce(d.tons,0)        as tons_delivered,
       d.moisture_avg,
       coalesce(d.grain_value,0) as grain_value,
       coalesce(u.qty,0)         as service_qty,
       coalesce(u.value,0)       as service_value,
       coalesce(l.tons,0)        as tons_sold,
       coalesce(l.value,0)       as sales_value,
       coalesce(p.to_customer,0) as paid_to_customer,
       coalesce(p.from_customer,0) as paid_by_customer,
       ( coalesce(d.grain_value,0) - coalesce(u.value,0) - coalesce(l.value,0)
         - coalesce(p.to_customer,0) + coalesce(p.from_customer,0) ) as balance
  from public.customers c
  cross join public.grain_seasons s
  left join lateral (
    select sum(gd.tons) as tons,
           -- Średnia wilgotność WAŻONA TONAMI. Zwykła arytmetyczna z 10 t o 30%
           -- i 30 t o 35% dałaby 32,5% zamiast 33,75% — i na tej liczbie ktoś
           -- ustaliłby potrącenie.
           case when sum(gd.tons) > 0
                then round(sum(gd.tons * gd.moisture) / sum(gd.tons), 2) end as moisture_avg,
           sum(gd.tons * coalesce(f.price_per_ton,0)) as grain_value
      from public.grain_deliveries gd
      left join public.grain_delivery_finance f on f.delivery_id = gd.id
     where gd.customer_id=c.id and gd.season_id=s.id and gd.status='aktywne') d on true
  left join lateral (
    select sum(cs.quantity) as qty,
           sum(cs.quantity * coalesce(sf.price_per_unit,0)) as value
      from public.customer_services cs
      left join public.customer_service_finance sf on sf.service_id = cs.id
     where cs.customer_id=c.id and cs.season_id=s.id and cs.status='aktywna') u on true
  left join lateral (
    select sum(gl.tons) as tons,
           sum(gl.tons * coalesce(coalesce(lf.price_per_ton, sf2.price_per_ton),0)) as value
      from public.grain_loads gl
      left join public.grain_load_finance lf on lf.load_id = gl.id
      left join public.grain_sale_finance sf2 on sf2.sale_id = gl.sale_id
     where gl.customer_id=c.id and gl.season_id=s.id and gl.status='aktywny') l on true
  left join lateral (
    select sum(amount) filter (where direction='TO_CUSTOMER')   as to_customer,
           sum(amount) filter (where direction='FROM_CUSTOMER') as from_customer
      from public.grain_payments gp
     where gp.customer_id=c.id and gp.season_id=s.id and gp.status='aktywna') p on true
 where c.farm_id = s.farm_id;

-- ═══ RLS ══════════════════════════════════════════════════════════════════════
do $$
declare t text;
begin
  foreach t in array array['grain_seasons','grain_products','customers','customer_vehicles',
                           'grain_deliveries','grain_sales','grain_loads','customer_services',
                           'grain_movements','grain_delivery_finance','grain_sale_finance',
                           'grain_load_finance','customer_service_finance','grain_payments',
                           'grain_audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ── Warstwa OPERACYJNA: kto ma moduł Skup, ten widzi tony, wilgotność, rejestracje ──
do $$
declare t text;
begin
  foreach t in array array['grain_seasons','grain_products','customers','customer_vehicles',
                           'grain_deliveries','grain_sales','grain_loads',
                           'customer_services','grain_movements'] loop
    execute format('drop policy if exists %I_sel on public.%I', t, t);
    execute format($p$create policy %I_sel on public.%I for select to authenticated
        using (farm_id in (select public.moje_farmy()) and public.widze_skup(farm_id))$p$, t, t);

    execute format('drop policy if exists %I_ins on public.%I', t, t);
    execute format($p$create policy %I_ins on public.%I for insert to authenticated
        with check (farm_id in (select public.moje_farmy()) and public.widze_skup(farm_id))$p$, t, t);

    execute format('drop policy if exists %I_upd on public.%I', t, t);
    execute format($p$create policy %I_upd on public.%I for update to authenticated
        using (farm_id in (select public.moje_farmy()) and public.widze_skup(farm_id))
        with check (farm_id in (select public.moje_farmy()) and public.widze_skup(farm_id))$p$, t, t);
  end loop;
end $$;

-- ⚠️ ŻADNEJ polityki DELETE na dokumentach handlowych i ruchach magazynowych.
-- Historia finansowa i magazynowa nie kasuje się — anuluje. Usunięcie wiersza
-- osierociłoby ruch magazynowy i stan przestałby się zgadzać.
drop policy if exists customers_del on public.customers;
create policy customers_del on public.customers for delete to authenticated
  using (public.jestem_adminem(farm_id));   -- klienta bez historii wolno usunąć

-- ── Warstwa FINANSOWA: osobne tabele, osobne uprawnienie ─────────────────────
-- 🔑 Tu mieszka odpowiedź na §28. Pracownik na wadze ma politykę na `grain_deliveries`,
-- ale NIE ma żadnej na `grain_delivery_finance` — zapytanie o ceny zwróci mu zero
-- wierszy, niezależnie od tego, co wyśle z przeglądarki.
do $$
declare t text;
begin
  foreach t in array array['grain_delivery_finance','grain_sale_finance',
                           'grain_load_finance','customer_service_finance','grain_payments'] loop
    execute format('drop policy if exists %I_sel on public.%I', t, t);
    execute format($p$create policy %I_sel on public.%I for select to authenticated
        using (farm_id in (select public.moje_farmy()) and public.widze_finanse(farm_id))$p$, t, t);

    execute format('drop policy if exists %I_ins on public.%I', t, t);
    execute format($p$create policy %I_ins on public.%I for insert to authenticated
        with check (farm_id in (select public.moje_farmy()) and public.widze_finanse(farm_id))$p$, t, t);

    execute format('drop policy if exists %I_upd on public.%I', t, t);
    execute format($p$create policy %I_upd on public.%I for update to authenticated
        using (farm_id in (select public.moje_farmy()) and public.widze_finanse(farm_id))
        with check (farm_id in (select public.moje_farmy()) and public.widze_finanse(farm_id))$p$, t, t);
  end loop;
end $$;

-- Audyt: czyta administrator gospodarstwa, nikt go nie zmienia z aplikacji.
drop policy if exists audit_sel on public.grain_audit_log;
create policy audit_sel on public.grain_audit_log for select to authenticated
  using (public.jestem_adminem(farm_id));

-- ── Kontrola po wdrożeniu ─────────────────────────────────────────────────────
-- 1. Tabele finansowe mają polityki wymagające widze_finanse:
--    select tablename, policyname, qual from pg_policies
--     where tablename like '%_finance' or tablename='grain_payments';
--
-- 2. Stan magazynu liczy się z ruchów (nie ma kolumny current_stock nigdzie):
--    select column_name, table_name from information_schema.columns
--     where column_name in ('current_stock','stock','owes_money');
--    → 0 wierszy.
--
-- 3. Dokumentów nie da się skasować z aplikacji:
--    select tablename, cmd from pg_policies
--     where cmd='DELETE' and tablename like 'grain_%';
--    → 0 wierszy.

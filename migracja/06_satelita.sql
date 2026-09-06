-- ═══════════════════════════════════════════════════════════════════════════════
-- M-FarmX — pamięć zobrazowań satelitarnych Sentinel-2
-- Uruchom PO 01_schemat.sql i 02_rls.sql.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- PO CO: korzystamy z DARMOWEGO limitu Copernicus Data Space. Bez zapamiętywania
-- wyników każde otwarcie pola generowałoby te same zapytania od nowa — a przy kilku
-- gospodarstwach i kilkudziesięciu polach limit skończyłby się w kilka dni.
--
-- ⚠️ NIE TRZYMAMY TU RASTRÓW. Obrazy PNG wracają z funkcji serwerowej i żyją w cache
-- przeglądarki. Wrzucanie ich jako bytea rozdęłoby bazę o setki megabajtów i spowolniło
-- każdą kopię zapasową. Tutaj są wyłącznie metadane i policzone wskaźniki — czyli to,
-- co jest małe, a kosztowne do ponownego wyliczenia.

create table if not exists public.field_satellite_scenes (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  field_id    uuid not null references public.fields(id) on delete cascade,
  provider    text not null default 'copernicus',
  satellite   text not null default 'sentinel-2-l2a',
  scene_id    text,
  acquired_at date not null,
  -- Zachmurzenie CAŁEJ sceny bywa mylące dla pola 12 ha: scena może mieć 60% chmur,
  -- a nasza działka leżeć w dziurze między nimi. Dlatego trzymamy obie liczby osobno.
  scene_cloud_coverage smallint check (scene_cloud_coverage between 0 and 100),
  field_cloud_coverage smallint check (field_cloud_coverage between 0 and 100),
  status      text not null default 'DOBRE'
              check (status in ('DOBRE','CZESCIOWE','DUZE_ZACHMURZENIE','BRAK')),
  metadata_json jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  unique (field_id, provider, acquired_at)
);
create index if not exists fss_pole_idx on public.field_satellite_scenes (field_id, acquired_at desc);

create table if not exists public.field_satellite_stats (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farms(id) on delete cascade,
  field_id    uuid not null references public.fields(id) on delete cascade,
  scene_id    uuid references public.field_satellite_scenes(id) on delete cascade,
  observed_at date not null,
  ndvi_mean numeric(5,3), ndvi_min numeric(5,3), ndvi_max numeric(5,3),
  ndre_mean numeric(5,3),
  ndmi_mean numeric(5,3),
  cloud_coverage smallint check (cloud_coverage between 0 and 100),
  created_at timestamptz not null default now(),
  unique (field_id, observed_at)
);
create index if not exists fst_pole_idx on public.field_satellite_stats (field_id, observed_at desc);

-- ── RLS ───────────────────────────────────────────────────────────────────────
-- Te same zasady co reszta systemu: przynależność wyłącznie przez farm_members,
-- nigdy przez farm_id przysłane z przeglądarki.
alter table public.field_satellite_scenes enable row level security;
alter table public.field_satellite_scenes force row level security;
alter table public.field_satellite_stats  enable row level security;
alter table public.field_satellite_stats  force row level security;

do $$
declare t text;
begin
  foreach t in array array['field_satellite_scenes','field_satellite_stats'] loop
    execute format('drop policy if exists %I_sel on public.%I', t, t);
    execute format($p$create policy %I_sel on public.%I for select to authenticated
        using (farm_id in (select public.moje_farmy()))$p$, t, t);

    -- Zapisuje funkcja serwerowa kluczem serwisowym; z przeglądarki tylko odczyt.
    -- ⚠️ Gdyby klient mógł tu pisać, dałoby się podstawić zmyślone NDVI i oglądać je
    -- potem jako „pomiar satelitarny".
    execute format('drop policy if exists %I_del on public.%I', t, t);
    execute format($p$create policy %I_del on public.%I for delete to authenticated
        using (public.jestem_adminem(farm_id))$p$, t, t);
  end loop;
end $$;

-- Kontrola:
-- select tablename, policyname, cmd from pg_policies
--  where tablename like 'field_satellite%' order by 1,3;
-- → wyłącznie SELECT i DELETE. Brak INSERT/UPDATE z klienta jest zamierzony.

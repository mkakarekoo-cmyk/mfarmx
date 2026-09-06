# Wdrożenie wielodzierżawności — checklista

**Stan na 05.09.2026: SQL napisany, NIC nie wdrożone, test izolacji NIE uruchomiony.**
Nie mam dostępu do projektu Supabase, więc żadnego z tych skryptów nie wykonałem ani
nie sprawdziłem na żywej bazie. Poniżej dokładnie to, co trzeba zrobić i w jakiej kolejności.

## Kolejność (Supabase → SQL Editor)

| # | plik | co robi | odwracalne? |
|---|---|---|---|
| 1 | `01_schemat.sql` | 8 tabel + trigger spójności zadań | tak — same CREATE |
| 2 | `02_rls.sql` | funkcje pomocnicze + polityki RLS | tak |
| 3 | `05_skup.sql` | moduł Skup: 7 tabel + widok sald + RLS | tak |
| 4 | `03_migracja_danych.sql` | kopiuje `user_state.data` → tabele | tak, idempotentny |
| 5 | uruchom migrację | `select public.migruj_gospodarstwo(user_id) from public.user_state where data <> '{}'::jsonb;` | — |
| 6 | **sprawdź liczby** | zapytania kontrolne na końcu `03` | — |
| 7 | `04_test_izolacji.sql` | **warunek dopuszczenia do pilotażu** | tak, sprząta po sobie |

⚠️ Przed krokiem 7 wklej do skryptu id **dwóch prawdziwych kont** z Authentication → Users.
Bez tego test się nie uruchomi.

⚠️ Krok 4 **niczego nie kasuje**. `user_state` zostaje jako kopia. Nie rób `DROP` przez
cały pilotaż — dopóki gospodarstwa nie przepracują kilku dni na nowych tabelach, stary
dokument jest jedyną siatką bezpieczeństwa.

## Czego skrypty NIE robią

- **Nie zakładają gospodarstwa dla nowego konta.** `farms` nie ma polityki INSERT — farmę
  musi tworzyć funkcja serwerowa razem z członkostwem FARM_ADMIN, inaczej powstałaby farma
  bez właściciela. Funkcja `admin-uzytkownicy` nie ma jeszcze akcji `utworz-gospodarstwo`.
- **Nie przełączają aplikacji na nowe tabele.** `index.html` dalej czyta i zapisuje
  `user_state`. Migracja bazy i migracja aplikacji to dwa osobne kroki — i drugi nie jest
  zrobiony.

## Zmienne środowiskowe (Edge Function)

| zmienna | gdzie | uwaga |
|---|---|---|
| `SUPABASE_URL` | Edge Function | ustawiane automatycznie |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function | **nigdy** we frontendzie |
| `ADMIN_EMAILS` | Edge Function | lista adresów administratorów platformy |

Sprawdzone: w `index.html` jest wyłącznie klucz `anon` (rola w tokenie = `anon`,
projekt `bmjvfscyosyhmtpskphm`). Żadnego `service_role` w kodzie klienta.

## Weryfikacja po wdrożeniu

```sql
-- 1. RLS wszędzie włączone
select relname, relrowsecurity from pg_class
 where relname in ('farms','farm_members','employees','fields','vehicles','tasks',
                   'todos','notifications','customers','grain_deliveries','grain_loads','payments');

-- 2. Zero polityk otwartych dla wszystkich zalogowanych
select tablename, policyname from pg_policies
 where schemaname='public' and qual = 'true';

-- 3. farm_members niezapisywalne z klienta — dokładnie jedna polityka, SELECT
select policyname, cmd from pg_policies where tablename='farm_members';
```

## Rollback

Skrypty tylko dodają. Żeby się wycofać:

```sql
drop view if exists public.customer_balances;
drop table if exists public.payments, public.grain_loads, public.grain_sales,
  public.grain_deliveries, public.customer_vehicles, public.grain_products,
  public.customers, public.notifications, public.todos, public.tasks,
  public.vehicles, public.fields, public.employees, public.farm_members, public.farms cascade;
```

`user_state` zostaje nietknięty, więc aplikacja działa dalej jak dziś.

-- ═══════════════════════════════════════════════════════════════════════════════
-- M-FarmX — TEST IZOLACJI GOSPODARSTW, krok 4/4
-- Uruchom PO 01, 02, 05. To jest WARUNEK DOPUSZCZENIA DO PILOTAŻU.
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- Test sprawdza jedno pytanie: czy gospodarstwo A może w JAKIKOLWIEK sposób dosięgnąć
-- danych gospodarstwa B. Każda nieudana asercja przerywa skrypt wyjątkiem — brak wyjątku
-- i komunikat „WSZYSTKIE ASERCJE PRZESZŁY" na końcu to jedyny wynik, który się liczy.
--
-- ⚠️ SQL Editor w Supabase pracuje jako `postgres`, który OMIJA RLS. Dlatego każdy test
-- jawnie zakłada tożsamość: `set local role authenticated` + podstawienie `sub` w JWT.
-- Bez tych dwóch linii test zawsze „przechodzi" i niczego nie dowodzi.
--
-- PRZYGOTOWANIE: potrzebne są DWA prawdziwe konta w Supabase Auth. Załóż je w
-- Authentication → Users (albo funkcją admin-uzytkownicy) i wklej ich id niżej.

do $$
declare
  -- ⚠️ WKLEJ TU ID DWÓCH ISTNIEJĄCYCH UŻYTKOWNIKÓW
  u_a uuid := '00000000-0000-0000-0000-00000000000a';   -- Admin gospodarstwa A
  u_b uuid := '00000000-0000-0000-0000-00000000000b';   -- Admin gospodarstwa B

  farm_a uuid; farm_b uuid;
  emp_a uuid;  emp_b uuid;
  pole_a uuid; pole_b uuid;
  poj_a uuid;  poj_b uuid;
  kli_b uuid;
  n int; blad text;
begin
  if not exists (select 1 from auth.users where id=u_a)
     or not exists (select 1 from auth.users where id=u_b) then
    raise exception 'Najpierw załóż dwa konta w Authentication → Users i wklej ich id do skryptu.';
  end if;

  -- ── Dane testowe (jako postgres, z pominięciem RLS) ─────────────────────────
  delete from public.farms where name in ('TEST Farma A','TEST Farma B');

  insert into public.farms (name, created_by) values ('TEST Farma A', u_a) returning id into farm_a;
  insert into public.farms (name, created_by) values ('TEST Farma B', u_b) returning id into farm_b;

  insert into public.farm_members (farm_id,user_id,role) values (farm_a,u_a,'FARM_ADMIN');
  insert into public.farm_members (farm_id,user_id,role) values (farm_b,u_b,'FARM_ADMIN');

  insert into public.employees (farm_id,first_name,last_name) values (farm_a,'Anna','A') returning id into emp_a;
  insert into public.employees (farm_id,first_name,last_name) values (farm_b,'Bogdan','B') returning id into emp_b;
  insert into public.fields   (farm_id,name) values (farm_a,'Pole A') returning id into pole_a;
  insert into public.fields   (farm_id,name) values (farm_b,'Pole B') returning id into pole_b;
  insert into public.vehicles (farm_id,name) values (farm_a,'Ciągnik A') returning id into poj_a;
  insert into public.vehicles (farm_id,name) values (farm_b,'Ciągnik B') returning id into poj_b;
  insert into public.tasks (farm_id,title,employee_id,field_id) values (farm_a,'Orka A',emp_a,pole_a);
  insert into public.tasks (farm_id,title,employee_id,field_id) values (farm_b,'Orka B',emp_b,pole_b);
  insert into public.customers (farm_id,name) values (farm_b,'Klient B') returning id into kli_b;
  insert into public.grain_deliveries (farm_id,season,customer_id,tons,moisture)
    values (farm_b, 2026, kli_b, 24.8, 31.4);

  raise notice 'Dane testowe gotowe. Farma A=% B=%', farm_a, farm_b;

  -- ═══ TOŻSAMOŚĆ: ADMIN A ═══════════════════════════════════════════════════
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',u_a,'role','authenticated')::text, true);

  -- 1. Widzi wyłącznie swoją farmę
  select count(*) into n from public.farms;
  if n <> 1 then raise exception 'FARMS: Admin A widzi % farm, powinien 1', n; end if;

  -- 2. Nie widzi pracowników B
  select count(*) into n from public.employees where farm_id = farm_b;
  if n <> 0 then raise exception 'EMPLOYEES: Admin A widzi % pracowników farmy B', n; end if;

  -- 3. Nie widzi pól B
  select count(*) into n from public.fields where farm_id = farm_b;
  if n <> 0 then raise exception 'FIELDS: Admin A widzi % pól farmy B', n; end if;

  -- 4. Nie widzi maszyn B
  select count(*) into n from public.vehicles where farm_id = farm_b;
  if n <> 0 then raise exception 'VEHICLES: Admin A widzi % maszyn farmy B', n; end if;

  -- 5. Nie widzi zadań B
  select count(*) into n from public.tasks where farm_id = farm_b;
  if n <> 0 then raise exception 'TASKS: Admin A widzi % zadań farmy B', n; end if;

  -- 6. Nie widzi klientów ani dostaw B (moduł Skup)
  select count(*) into n from public.customers where farm_id = farm_b;
  if n <> 0 then raise exception 'CUSTOMERS: Admin A widzi % klientów farmy B', n; end if;
  select count(*) into n from public.grain_deliveries where farm_id = farm_b;
  if n <> 0 then raise exception 'DELIVERIES: Admin A widzi % dostaw farmy B', n; end if;

  -- 7. Nie widzi sald B — widok z security_invoker musi respektować RLS tabel
  select count(*) into n from public.customer_balances where farm_id = farm_b;
  if n <> 0 then raise exception 'BALANCES: widok przecieka — Admin A widzi % sald farmy B', n; end if;

  -- 8. ⛔ Nie może UTWORZYĆ rekordu w farmie B (podmiana farm_id w żądaniu)
  blad := null;
  begin
    insert into public.fields (farm_id,name) values (farm_b,'Wstrzyknięte pole');
    exception when others then blad := sqlstate;
  end;
  if blad is null then
    raise exception 'KRYTYCZNE: Admin A UTWORZYŁ pole w farmie B (podmiana farm_id zadziałała)';
  end if;

  -- 9. ⛔ Nie może utworzyć zadania w SWOJEJ farmie wskazującego maszynę farmy B
  --    (samo farm_id się zgadza — łapie to trigger spójności dzierżawcy)
  blad := null;
  begin
    insert into public.tasks (farm_id,title,vehicle_id) values (farm_a,'Kradzież maszyny',poj_b);
    exception when others then blad := sqlstate;
  end;
  if blad is null then
    raise exception 'KRYTYCZNE: zadanie farmy A przyjęło maszynę farmy B';
  end if;

  -- 10. ⛔ Nie może podmienić farm_id istniejącego rekordu i przenieść go do B
  blad := null;
  begin
    update public.fields set farm_id = farm_b where id = pole_a;
    exception when others then blad := sqlstate;
  end;
  select count(*) into n from public.fields where id = pole_a and farm_id = farm_b;
  if n <> 0 then
    raise exception 'KRYTYCZNE: Admin A przeniósł swoje pole do farmy B';
  end if;

  -- 11. ⛔ Nie może dopisać się do farmy B ani nadać sobie w niej roli
  blad := null;
  begin
    insert into public.farm_members (farm_id,user_id,role) values (farm_b,u_a,'FARM_ADMIN');
    exception when others then blad := sqlstate;
  end;
  if blad is null then
    raise exception 'KRYTYCZNE: Admin A dopisał się jako administrator farmy B';
  end if;

  -- 12. ⛔ Nie może podnieść sobie uprawnień we własnej farmie przez farm_members
  blad := null;
  begin
    update public.farm_members set role='FARM_ADMIN' where farm_id=farm_a and user_id=u_a;
    exception when others then blad := sqlstate;
  end;
  if blad is null then
    raise exception 'UWAGA: farm_members jest zapisywalne z klienta — powinno być tylko przez funkcję serwerową';
  end if;

  raise notice '✓ Admin A: 12 asercji przeszło';

  -- ═══ TOŻSAMOŚĆ: ADMIN B — kontrola w drugą stronę ════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',u_b,'role','authenticated')::text, true);

  select count(*) into n from public.farms;
  if n <> 1 then raise exception 'FARMS: Admin B widzi % farm, powinien 1', n; end if;
  select count(*) into n from public.tasks where farm_id = farm_a;
  if n <> 0 then raise exception 'TASKS: Admin B widzi % zadań farmy A', n; end if;
  select count(*) into n from public.employees where farm_id = farm_a;
  if n <> 0 then raise exception 'EMPLOYEES: Admin B widzi % pracowników farmy A', n; end if;

  -- B widzi SWOJE dane — test bez tego dowodziłby tylko, że nikt nie widzi niczego
  select count(*) into n from public.grain_deliveries where farm_id = farm_b;
  if n <> 1 then raise exception 'REGRESJA: Admin B nie widzi WŁASNEJ dostawy (widzi %)', n; end if;
  select count(*) into n from public.tasks where farm_id = farm_b;
  if n <> 1 then raise exception 'REGRESJA: Admin B nie widzi WŁASNEGO zadania (widzi %)', n; end if;

  raise notice '✓ Admin B: 5 asercji przeszło (w tym dostęp do własnych danych)';

  reset role;
  raise notice '═══ WSZYSTKIE ASERCJE PRZESZŁY — izolacja gospodarstw działa ═══';
  raise notice 'Dane testowe zostają. Sprzątanie:';
  raise notice '  delete from public.farms where name in (''TEST Farma A'',''TEST Farma B'');';
end $$;

-- ── Test dodatkowy: pracownik bez prawa do grafiku widzi TYLKO swoje zadania ──
-- Wymaga konta pracownika powiązanego z employees.user_id. Uruchom osobno:
--
-- do $$
-- declare u_prac uuid := '…'; f uuid := '…'; n int;
-- begin
--   set local role authenticated;
--   perform set_config('request.jwt.claims',
--     json_build_object('sub',u_prac,'role','authenticated')::text, true);
--   select count(*) into n from public.tasks where farm_id=f;
--   raise notice 'Pracownik widzi % zadań (powinien tylko swoje)', n;
--   reset role;
-- end $$;

-- ── Kontrola higieny polityk ──────────────────────────────────────────────────
-- Żadnej polityki „dla każdego zalogowanego":
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and (qual = 'true' or (qual is null and cmd <> 'INSERT'))
 order by tablename;
-- → oczekiwany wynik: 0 wierszy.

-- Każda tabela dzierżawcy ma włączone RLS:
select c.relname,
       c.relrowsecurity  as rls_wlaczone,
       c.relforcerowsecurity as rls_wymuszone,
       (select count(*) from pg_policies p where p.tablename = c.relname) as polityk
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and c.relname in ('farms','farm_members','employees','fields','vehicles','tasks',
                     'todos','notifications','customers','customer_vehicles',
                     'grain_products','grain_deliveries','grain_sales','grain_loads','payments')
 order by c.relname;
-- → rls_wlaczone = true WSZĘDZIE, polityk > 0 wszędzie poza farm_members (tam dokładnie 1).

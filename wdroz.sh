#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# M-FarmX — wdrożenie kompletu do Supabase
# Uruchom PO `supabase login`. Skrypt jest bezpieczny do powtórzenia: wszystkie
# migracje są idempotentne (create table if not exists / drop policy if exists),
# a żadna niczego nie kasuje.
# ═══════════════════════════════════════════════════════════════════════════════
set -u
REF="bmjvfscyosyhmtpskphm"
cd "$(dirname "$0")" || exit 1

krok(){ printf '\n\033[1m── %s\033[0m\n' "$1"; }
ok(){   printf '   \033[32m✓\033[0m %s\n' "$1"; }
zle(){  printf '   \033[31m✗\033[0m %s\n' "$1"; }

krok "1/5 · Sprawdzenie logowania"
if ! supabase projects list >/dev/null 2>&1; then
  zle "Supabase CLI nie jest zalogowany. Uruchom najpierw:  supabase login"
  exit 1
fi
ok "zalogowany"

krok "2/5 · Podłączenie projektu $REF"
# link zapyta o hasło do bazy (Database Password z Settings → Database)
if supabase link --project-ref "$REF" 2>&1 | tail -2; then ok "projekt podłączony"; else zle "nie udało się podłączyć"; exit 1; fi

krok "3/5 · Wysłanie migracji (6 plików)"
# ⚠️ Nic nie kasuje. Tworzy: farms, farm_members, employees, fields, vehicles,
#    tasks, todos, notifications, moduł Skup, dostep_pracownika, zgloszenia + RLS.
if supabase db push 2>&1 | tail -12; then ok "migracje wysłane"; else zle "db push nie przeszedł"; exit 1; fi

krok "4/5 · Przeniesienie istniejących gospodarstw z user_state do tabel"
# Funkcja migruj_gospodarstwo() kopiuje dokument jsonb do nowych tabel i zakłada
# członkostwo FARM_ADMIN. `user_state` ZOSTAJE nietknięty jako kopia.
cat > /tmp/mfarmx_migruj.sql <<'SQL'
select public.migruj_gospodarstwo(user_id) as wynik
  from public.user_state
 where data is not null and data <> '{}'::jsonb;
SQL
if supabase db execute --file /tmp/mfarmx_migruj.sql 2>&1 | tail -8; then
  ok "gospodarstwa przeniesione (jeśli jakieś były)"
else
  zle "przeniesienie nie przeszło — sprawdź komunikat wyżej"
fi

krok "5/5 · Funkcja serwerowa admin-uzytkownicy"
if supabase functions deploy admin-uzytkownicy --project-ref "$REF" 2>&1 | tail -4; then
  ok "funkcja wdrożona"
  printf '   \033[33m!\033[0m Ustaw jeszcze zmienną ADMIN_EMAILS:\n'
  printf '     supabase secrets set ADMIN_EMAILS="twoj@email.pl" --project-ref %s\n' "$REF"
else
  zle "wdrożenie funkcji nie przeszło (można pominąć — potrzebna tylko do kont pracowniczych)"
fi

printf '\n\033[1mGotowe.\033[0m Weryfikację uruchom poleceniem:  node sprawdz_wdrozenie.js\n'

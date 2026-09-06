# ═══════════════════════════════════════════════════════════════════════════════
#  M-FarmX — wdrożenie kompletu do Supabase
#
#  URUCHOM W ZWYKŁYM OKNIE POWERSHELL (nie przez agenta) — skrypt zadaje pytania:
#  logowanie otwiera przeglądarkę, podłączenie projektu pyta o hasło do bazy.
#
#      cd C:\Projekty\Zagon
#      .\wdroz.ps1
#
#  ⚠️ Bezpieczny do powtórzenia. Wszystkie migracje są idempotentne
#     (create table if not exists / drop policy if exists), żadna niczego nie kasuje,
#     a `user_state` zostaje nietknięty jako kopia na czas pilotażu.
# ═══════════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Continue'
$REF = 'bmjvfscyosyhmtpskphm'
Set-Location $PSScriptRoot

function Krok($t) { Write-Host "`n── $t" -ForegroundColor White }
function Ok($t)   { Write-Host "   OK  $t" -ForegroundColor Green }
function Zle($t)  { Write-Host "   ##  $t" -ForegroundColor Red }
function Uwaga($t){ Write-Host "   !   $t" -ForegroundColor Yellow }

Krok '1/6 · Logowanie do Supabase'
supabase projects list *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host '   Otworzy się przeglądarka — potwierdź logowanie i wróć tutaj.'
  supabase login
  if ($LASTEXITCODE -ne 0) { Zle 'Logowanie nie powiodło się.'; exit 1 }
}
Ok 'zalogowany'

Krok "2/6 · Podłączenie projektu $REF"
Write-Host '   Zapyta o Database Password — znajdziesz je w:'
Write-Host "   https://supabase.com/dashboard/project/$REF/settings/database" -ForegroundColor DarkGray
supabase link --project-ref $REF
if ($LASTEXITCODE -ne 0) { Zle 'Nie udało się podłączyć projektu.'; exit 1 }
Ok 'projekt podłączony'

Krok '3/6 · Wysłanie migracji (6 plików)'
Write-Host '   Tworzy: farms, farm_members, employees, fields, vehicles, tasks, todos,'
Write-Host '   notifications, moduł Skup (15 tabel), dostep_pracownika, zgloszenia + RLS.'
supabase db push
if ($LASTEXITCODE -ne 0) { Zle 'db push nie przeszedł — przerwij i pokaż mi komunikat.'; exit 1 }
Ok 'migracje wysłane'

Krok '4/6 · Przeniesienie gospodarstw z user_state do tabel'
# Kopiuje dokument jsonb do nowych tabel i zakłada członkostwo FARM_ADMIN.
# ⚠️ user_state ZOSTAJE — to jedyna siatka bezpieczeństwa na czas pilotażu.
@'
select public.migruj_gospodarstwo(user_id) as wynik
  from public.user_state
 where data is not null and data <> '{}'::jsonb;
'@ | Out-File -Encoding utf8 "$env:TEMP\mfarmx_migruj.sql"
supabase db execute --file "$env:TEMP\mfarmx_migruj.sql"
if ($LASTEXITCODE -eq 0) { Ok 'gospodarstwa przeniesione (jeśli jakieś były)' }
else { Uwaga 'przeniesienie nie przeszło — jeśli nie ma jeszcze żadnych kont, to normalne' }

Krok '5/6 · Funkcja serwerowa admin-uzytkownicy'
supabase functions deploy admin-uzytkownicy --project-ref $REF
if ($LASTEXITCODE -eq 0) {
  Ok 'funkcja wdrożona'
  Uwaga 'Ustaw jeszcze listę administratorów:'
  Write-Host "     supabase secrets set ADMIN_EMAILS=`"twoj@email.pl`" --project-ref $REF" -ForegroundColor DarkGray
} else {
  Uwaga 'funkcja niewdrożona — potrzebna tylko do zakładania kont pracowniczych'
}

Krok '6/6 · Weryfikacja z zewnątrz'
node sprawdz_wdrozenie.js

Write-Host "`nGotowe. Jeśli coś świeci na czerwono — pokaż mi ten fragment." -ForegroundColor White

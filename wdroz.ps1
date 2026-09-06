# ==============================================================================
#  M-FarmX - wdrozenie kompletu do Supabase
#
#  URUCHOM W ZWYKLYM OKNIE POWERSHELL (nie przez agenta) - skrypt zadaje pytania:
#  logowanie otwiera przegladarke, podlaczenie projektu pyta o haslo do bazy.
#
#      cd C:\Projekty\Zagon
#      .\wdroz.ps1
#
#  BEZPIECZNY DO POWTORZENIA. Wszystkie migracje sa idempotentne
#  (create table if not exists / drop policy if exists), zadna niczego nie kasuje,
#  a user_state zostaje nietkniety jako kopia na czas pilotazu.
# ==============================================================================

$ErrorActionPreference = 'Continue'
$REF = 'bmjvfscyosyhmtpskphm'
Set-Location $PSScriptRoot

function Krok($t)  { Write-Host ""; Write-Host "-- $t" -ForegroundColor White }
function Ok($t)    { Write-Host "   OK   $t" -ForegroundColor Green }
function Zle($t)   { Write-Host "   BLAD $t" -ForegroundColor Red }
function Uwaga($t) { Write-Host "   !    $t" -ForegroundColor Yellow }

Krok "1/6 - Logowanie do Supabase"
supabase projects list *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "   Otworzy sie przegladarka - potwierdz logowanie i wroc tutaj."
  supabase login
  if ($LASTEXITCODE -ne 0) { Zle "Logowanie nie powiodlo sie."; exit 1 }
}
Ok "zalogowany"

Krok "2/6 - Podlaczenie projektu $REF"
Write-Host "   Zapyta o Database Password. Znajdziesz je w:"
Write-Host "   https://supabase.com/dashboard/project/$REF/settings/database" -ForegroundColor DarkGray
supabase link --project-ref $REF
if ($LASTEXITCODE -ne 0) { Zle "Nie udalo sie podlaczyc projektu."; exit 1 }
Ok "projekt podlaczony"

Krok "3/6 - Wyslanie migracji (6 plikow)"
Write-Host "   Tworzy: farms, farm_members, employees, fields, vehicles, tasks, todos,"
Write-Host "   notifications, modul Skup (15 tabel), dostep_pracownika, zgloszenia + RLS."
supabase db push
if ($LASTEXITCODE -ne 0) { Zle "db push nie przeszedl - przerwij i pokaz mi komunikat."; exit 1 }
Ok "migracje wyslane"

Krok "4/6 - Przeniesienie gospodarstw z user_state do tabel"
# Kopiuje dokument jsonb do nowych tabel i zaklada czlonkostwo FARM_ADMIN.
# user_state ZOSTAJE - to jedyna siatka bezpieczenstwa na czas pilotazu.
$sql = "select public.migruj_gospodarstwo(user_id) as wynik from public.user_state where data is not null and data <> '{}'::jsonb;"
$plik = Join-Path $env:TEMP "mfarmx_migruj.sql"
[System.IO.File]::WriteAllText($plik, $sql, (New-Object System.Text.UTF8Encoding $false))
supabase db execute --file $plik
if ($LASTEXITCODE -eq 0) { Ok "gospodarstwa przeniesione (jesli jakies byly)" }
else { Uwaga "przeniesienie nie przeszlo - jesli nie ma jeszcze zadnych kont, to normalne" }

Krok "5/6 - Funkcja serwerowa admin-uzytkownicy"
supabase functions deploy admin-uzytkownicy --project-ref $REF
if ($LASTEXITCODE -eq 0) {
  Ok "funkcja wdrozona"
  Uwaga "Ustaw jeszcze liste administratorow:"
  Write-Host ('     supabase secrets set ADMIN_EMAILS="twoj@email.pl" --project-ref ' + $REF) -ForegroundColor DarkGray
} else {
  Uwaga "funkcja niewdrozona - potrzebna tylko do zakladania kont pracowniczych"
}

Krok "6/6 - Weryfikacja z zewnatrz"
node sprawdz_wdrozenie.js

Write-Host ""
Write-Host "Gotowe. Jesli cos swieci na czerwono - pokaz mi ten fragment." -ForegroundColor White

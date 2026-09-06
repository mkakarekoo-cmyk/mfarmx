# ==============================================================================
#  M-FarmX - wypchniecie wersji produkcyjnej na Vercel
#
#  URUCHOM W ZWYKLYM OKNIE POWERSHELL:
#      cd C:\Projekty\Zagon
#      .\deploy.ps1
#
#  Vercel CLI jest zalogowany na konto SLUZBOWE (mksluzbowyy-sys), a mfarmx.vercel.app
#  stoi na koncie prywatnym. Skrypt przelaczy konto i wypchnie biezaca wersje.
# ==============================================================================

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

function Krok($t)  { Write-Host ""; Write-Host "-- $t" -ForegroundColor White }
function Ok($t)    { Write-Host "   OK   $t" -ForegroundColor Green }
function Uwaga($t) { Write-Host "   !    $t" -ForegroundColor Yellow }

Krok "1/4 - Aktualne konto Vercel"
$kto = (vercel whoami 2>&1 | Select-Object -Last 1).ToString().Trim()
Write-Host "   zalogowany jako: $kto"
if ($kto -eq 'mksluzbowyy-sys') {
  Uwaga "To konto SLUZBOWE. M-FarmX to projekt prywatny - przelaczam."
  vercel logout
  Write-Host "   Otworzy sie przegladarka. Wybierz 'Continue with GitHub'"
  Write-Host "   i konto mkakarekoo-cmyk (to samo, na ktorym lezy repo)." -ForegroundColor DarkGray
  vercel login
  $kto = (vercel whoami 2>&1 | Select-Object -Last 1).ToString().Trim()
  Write-Host "   teraz zalogowany jako: $kto"
}
if ($kto -eq 'mksluzbowyy-sys' -or [string]::IsNullOrWhiteSpace($kto)) {
  Write-Host "   Nadal konto sluzbowe albo brak logowania - przerywam." -ForegroundColor Red
  exit 1
}
Ok "konto prywatne"

Krok "2/4 - Projekty na tym koncie"
vercel project ls

Krok "3/4 - Podlaczenie katalogu do projektu"
Write-Host "   Jesli zapyta 'Link to existing project?' - odpowiedz Y"
Write-Host "   i wybierz projekt mfarmx (ten od mfarmx.vercel.app)." -ForegroundColor DarkGray
vercel link
if ($LASTEXITCODE -ne 0) { Write-Host "   Nie udalo sie podlaczyc." -ForegroundColor Red; exit 1 }
Ok "katalog podlaczony"

Krok "4/4 - Wypchniecie na produkcje"
vercel --prod
if ($LASTEXITCODE -eq 0) { Ok "wdrozone" } else { Write-Host "   Deploy nie przeszedl." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Sprawdz wynik komenda:  node sprawdz_deploy.js" -ForegroundColor White

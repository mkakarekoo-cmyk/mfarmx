/* ═══════════════════════════════════════════════════════════════════════════════
   M-FarmX — weryfikacja wdrożenia z ZEWNĄTRZ, kluczem anon.
   Sprawdza to, co widzi zwykły użytkownik internetu — czyli dokładnie to, co
   naprawdę wystawiliśmy na świat. Nie potrzebuje żadnych uprawnień.
   Uruchom:  node sprawdz_wdrozenie.js
   ═══════════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');

const html = fs.readFileSync(__dirname + '/index.html', 'utf8');
const URL  = html.match(/SUPABASE_URL='([^']+)'/)[1];
const ANON = html.match(/SUPABASE_ANON='([^']+)'/)[1];

const zielony = t => '\x1b[32m✓\x1b[0m ' + t;
const czerwony = t => '\x1b[31m✗\x1b[0m ' + t;
const zolty = t => '\x1b[33m!\x1b[0m ' + t;

async function pobierz(sciezka, opcje) {
  const r = await fetch(URL + sciezka, Object.assign({
    headers: { apikey: ANON, 'Content-Type': 'application/json' }
  }, opcje || {}));
  let tresc = null;
  try { tresc = await r.json(); } catch (e) {}
  return { status: r.status, tresc, naglowki: r.headers };
}

(async () => {
  console.log('\nProjekt: ' + URL + '\n');
  let bledy = 0, ostrzezenia = 0;

  // ── 1. Czy projekt żyje ────────────────────────────────────────────────────
  const zdrowie = await pobierz('/auth/v1/health');
  console.log(zdrowie.status === 200 ? zielony('Projekt odpowiada') : czerwony('Projekt nie odpowiada (HTTP ' + zdrowie.status + ')'));
  if (zdrowie.status !== 200) { console.log('\nPrzerywam — bez działającego projektu reszta nie ma sensu.\n'); process.exit(1); }

  // ── 2. Rejestracja ─────────────────────────────────────────────────────────
  // ⚠️ NAJWAŻNIEJSZY punkt. Otwarta rejestracja znaczy, że każdy, kto zna adres
  //    aplikacji, może założyć konto w tym projekcie.
  const ust = await pobierz('/auth/v1/settings');
  if (ust.tresc && ust.tresc.disable_signup === true) {
    console.log(zielony('Rejestracja ZAMKNIĘTA — konta zakłada wyłącznie administrator'));
  } else {
    console.log(czerwony('Rejestracja OTWARTA — każdy może założyć sobie konto!'));
    console.log('   → ' + URL.replace('.supabase.co', '').replace('https://', 'https://supabase.com/dashboard/project/') + '/auth/providers');
    console.log('     Email → odznacz „Enable Sign Ups" → Save');
    bledy++;
  }
  if (ust.tresc && ust.tresc.mailer_autoconfirm === false) {
    console.log(zolty('Potwierdzanie e-mail włączone — zakładając konto zaznacz „Auto Confirm User"'));
  }

  // ── 3. Tabele ──────────────────────────────────────────────────────────────
  // Anon nie zobaczy ŻADNYCH wierszy (tak ma być), ale odróżnimy „tabela jest,
  // tylko pusta dla mnie" (200) od „tabeli nie ma" (PGRST205).
  const tabele = [
    ['user_state',        'gospodarstwa (model dokumentowy)', true],
    ['farms',             'gospodarstwa (model tabelaryczny)', false],
    ['farm_members',      'przynależność użytkowników',        false],
    ['employees',         'pracownicy',                        false],
    ['fields',            'pola',                              false],
    ['vehicles',          'maszyny',                           false],
    ['tasks',             'zadania',                           false],
    ['todos',             'zgłoszenia (nowe)',                 false],
    ['customers',         'klienci skupu',                     false],
    ['grain_deliveries',  'przyjęcia zboża',                   false],
    ['grain_movements',   'ruchy magazynowe',                  false],
    ['dostep_pracownika', 'konta pracownicze (obecny kod)',    false],
    ['zgloszenia',        'zgłoszenia z telefonu (obecny kod)',false],
  ];
  console.log('\nTabele:');
  for (const [nazwa, opis, wymagana] of tabele) {
    const r = await pobierz('/rest/v1/' + nazwa + '?select=*&limit=1');
    const brak = r.tresc && r.tresc.code === 'PGRST205';
    if (brak) {
      console.log('  ' + (wymagana ? czerwony(nazwa.padEnd(20)) : zolty(nazwa.padEnd(20))) + opis + ' — BRAK');
      wymagana ? bledy++ : ostrzezenia++;
    } else {
      const ile = Array.isArray(r.tresc) ? r.tresc.length : '?';
      console.log('  ' + zielony(nazwa.padEnd(20)) + opis
        + (ile === 0 ? '' : '  \x1b[31m← anon widzi ' + ile + ' wierszy!\x1b[0m'));
      if (ile !== 0 && ile !== '?') bledy++;   // wyciek: RLS nie działa
    }
  }

  // ── 4. Izolacja ────────────────────────────────────────────────────────────
  // Anon MUSI dostawać puste listy wszędzie. Niepusta odpowiedź = dziura.
  console.log('\nIzolacja (widok anonimowy):');
  const wrazliwe = ['user_state', 'farms', 'employees', 'customers', 'grain_deliveries'];
  let wyciek = false;
  for (const t of wrazliwe) {
    const r = await pobierz('/rest/v1/' + t + '?select=*');
    if (Array.isArray(r.tresc) && r.tresc.length > 0) {
      console.log('  ' + czerwony(t + ' oddaje ' + r.tresc.length + ' wierszy bez logowania'));
      wyciek = true; bledy++;
    }
  }
  if (!wyciek) console.log('  ' + zielony('żadna tabela nie oddaje danych bez logowania'));

  // ── 5. Funkcja serwerowa ───────────────────────────────────────────────────
  const fn = await pobierz('/functions/v1/admin-uzytkownicy', {
    method: 'POST', body: JSON.stringify({ akcja: 'lista' })
  });
  console.log('\nFunkcja admin-uzytkownicy: ' + (
    fn.status === 404 ? zolty('niewdrożona (potrzebna tylko do kont pracowniczych)')
    : fn.status === 401 || fn.status === 403 ? zielony('wdrożona i odrzuca żądanie bez uprawnień')
    : zolty('odpowiada HTTP ' + fn.status)));

  // ── Podsumowanie ───────────────────────────────────────────────────────────
  console.log('\n' + '─'.repeat(60));
  if (bledy === 0) {
    console.log(zielony('Gotowe do wpuszczenia użytkowników.')
      + (ostrzezenia ? '  (' + ostrzezenia + ' rzeczy opcjonalnych niewdrożonych)' : ''));
  } else {
    console.log(czerwony(bledy + ' problem(ów) do naprawy PRZED wpuszczeniem użytkowników.'));
  }
  console.log('');
  process.exit(bledy ? 1 : 0);
})();

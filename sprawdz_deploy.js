/* ═══════════════════════════════════════════════════════════════════════════════
   Czy na produkcji stoi ta sama wersja, co lokalnie?
   Porównuje markery nowej wersji zamiast ufać komunikatowi „Deployed".
   Uruchom:  node sprawdz_deploy.js
   ═══════════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const ADRES = process.argv[2] || 'https://mfarmx.vercel.app/';

const zielony = t => '\x1b[32m✓\x1b[0m ' + t;
const czerwony = t => '\x1b[31m✗\x1b[0m ' + t;

/* Markery dobrane tak, żeby każdy pochodził z INNEJ części tej sesji — gdyby deploy
   poszedł tylko częściowo albo z cache, część z nich by zniknęła. */
const MARKERY = [
  ['--app-bg',          'design tokens (nowa paleta)'],
  ['naglowekStrony',    'wspólny nagłówek stron'],
  ['REJESTR_UPRAW',     'rejestr upraw + ikony SVG'],
  ['nav-szukaj',        'globalne wyszukiwanie Ctrl K'],
  ['warstwa-dzialki',   'granice działek GUGiK'],
  ['renderSkupModule',  'moduł Skup / zboże'],
  ['maSiedzibe',        'siedziba gospodarstwa na mapie'],
  ['miniaturaPola',     'miniatura satelitarna pola'],
];

(async () => {
  const lokalny = fs.readFileSync(__dirname + '/index.html', 'utf8');
  console.log('\nProdukcja: ' + ADRES);

  let zdalny;
  try {
    const r = await fetch(ADRES, { cache: 'no-store', headers: { 'Cache-Control': 'no-cache' } });
    zdalny = await r.text();
    console.log('HTTP ' + r.status + ' · ' + Math.round(zdalny.length / 1024) + ' kB'
      + '   (lokalnie ' + Math.round(lokalny.length / 1024) + ' kB)');
    const lm = r.headers.get('last-modified'), age = r.headers.get('age');
    if (lm) console.log('Last-Modified: ' + lm + (age ? '   (w cache od ' + Math.round(age / 3600) + ' h)' : ''));
  } catch (e) {
    console.log(czerwony('Nie udało się pobrać: ' + e.message) + '\n');
    process.exit(1);
  }

  console.log('\nSkładniki nowej wersji:');
  let brak = 0;
  for (const [m, opis] of MARKERY) {
    const jest = zdalny.includes(m);
    console.log('  ' + (jest ? zielony(opis) : czerwony(opis + ' — BRAK')));
    if (!jest) brak++;
  }

  console.log('\n' + '─'.repeat(58));
  if (brak === 0) {
    console.log(zielony('Produkcja ma aktualną wersję.'));
    console.log('  Jeśli w przeglądarce dalej widzisz stary wygląd — to jej cache.');
    console.log('  Odśwież twardo: Ctrl+Shift+R (albo Ctrl+F5).');
  } else {
    console.log(czerwony(brak + ' z ' + MARKERY.length + ' składników brakuje — deploy nie doszedł.'));
  }
  console.log('');
  process.exit(brak ? 1 : 0);
})();

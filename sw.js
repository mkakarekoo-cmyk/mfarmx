/* ═══════════════════════════════════════════════════════════════════════════════
   M-FarmX — service worker
   Odpowiada za dwie rzeczy: instalację na telefonie i to, żeby aplikacja otworzyła
   się bez zasięgu (w polu bywa go mało).

   ⚠️ ZASADA: `index.html` bierzemy ZAWSZE Z SIECI, jeśli tylko jest dostępna
   (network-first). Odwrotna kolejność — cache-first — sprawiłaby, że po wdrożeniu
   nowej wersji użytkownicy tygodniami widzieliby starą i nie dałoby się tego naprawić
   zdalnie. Cache jest wyłącznie zapasem na brak zasięgu.

   ⚠️ CZEGO TU NIE MA: nie cache'ujemy zapytań do Supabase ani kafli map. Dane
   gospodarstwa muszą być świeże — pokazanie starego grafiku jako aktualnego byłoby
   gorsze niż komunikat o braku sieci. */

const WERSJA = 'mfarmx-v1';
const SZKIELET = ['./', './index.html', './manifest.webmanifest',
  './icons/app-192.png', './icons/app-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(WERSJA)
      .then(c => c.addAll(SZKIELET).catch(() => {/* brak pliku nie może zablokować instalacji */}))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(k => Promise.all(k.filter(x => x !== WERSJA).map(x => caches.delete(x))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  // Supabase, kafle map, geokoder, GUGiK — zawsze prosto do sieci, nigdy z cache.
  if (/supabase\.co|arcgisonline|openstreetmap|gugik\.gov\.pl|nominatim/.test(url.hostname)) return;
  if (url.origin !== location.origin) return;

  e.respondWith(
    fetch(req)
      .then(odp => {
        // Kopię trzymamy na wypadek braku zasięgu, ale użytkownik dostaje wersję z sieci.
        const kopia = odp.clone();
        caches.open(WERSJA).then(c => c.put(req, kopia)).catch(() => {});
        return odp;
      })
      .catch(() => caches.match(req).then(c => c || caches.match('./index.html')))
  );
});

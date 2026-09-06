// ═══════════════════════════════════════════════════════════════════════════════
// Funkcja serwerowa: zdjęcia satelitarne Sentinel-2 z Copernicus Data Space.
//
// PO CO ISTNIEJE: Copernicus wymaga OAuth client_credentials, czyli CLIENT SECRET.
// Taki sekret nie może trafić do przeglądarki — każdy odczytałby go ze źródła strony
// i wyczerpał limit konta albo używał go we własnych celach. M-FarmX to statyczny HTML
// bez backendu, więc TA FUNKCJA JEST JEDYNYM miejscem, gdzie sekret może zamieszkać.
//
// 🔑 EVALSCRIPTY SĄ ZDEFINIOWANE TUTAJ, po stronie serwera. Przeglądarka wybiera tylko
// NAZWĘ warstwy ('truecolor' | 'ndvi' | 'ndre' | 'ndmi'). Przyjmowanie evalscriptu
// z frontendu oznaczałoby wykonywanie cudzego kodu na koszt naszego konta.
//
// 🔑 WŁASNOŚĆ POLA SPRAWDZA SERWER. Frontend podaje fieldId, a funkcja sama sięga po
// gospodarstwo wołającego i sprawdza, czy to pole do niego należy. Bez tego wystarczyłoby
// podmienić id w żądaniu, żeby oglądać cudze pola.
//
// WDROŻENIE (panel Supabase → Edge Functions → Deploy a new function):
//   nazwa: satelita · wklej ten plik
//   Secrets (Edge Functions → Secrets):
//     COPERNICUS_CLIENT_ID     = z panelu Copernicus
//     COPERNICUS_CLIENT_SECRET = z panelu Copernicus
//   (SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY Supabase podstawia sam)
// ═══════════════════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const URL_BAZY = Deno.env.get('SUPABASE_URL')!;
const KLUCZ_SERWISOWY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CLIENT_ID = Deno.env.get('COPERNICUS_CLIENT_ID') ?? '';
const CLIENT_SECRET = Deno.env.get('COPERNICUS_CLIENT_SECRET') ?? '';

const TOKEN_URL = Deno.env.get('COPERNICUS_TOKEN_URL')
  ?? 'https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token';
const API_BASE = Deno.env.get('COPERNICUS_API_BASE_URL')
  ?? 'https://sh.dataspace.copernicus.eu';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const odpowiedz = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

/* ═══ OAUTH ════════════════════════════════════════════════════════════════════
   ⚠️ Token trzymamy w pamięci instancji i odświeżamy 60 s PRZED wygaśnięciem.
   Pobieranie nowego przy każdym żądaniu to zbędne obciążenie serwera tożsamości
   i realne ryzyko 429 przy kilku polach otwartych naraz. */
let token: { wartosc: string; wygasa: number } | null = null;

async function pobierzToken(): Promise<string> {
  if (token && Date.now() < token.wygasa - 60_000) return token.wartosc;
  if (!CLIENT_ID || !CLIENT_SECRET) throw new BladApi('BRAK_KONFIGURACJI', 'Nie ustawiono danych Copernicus.', 503);

  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'client_credentials', client_id: CLIENT_ID, client_secret: CLIENT_SECRET }),
  });
  if (!r.ok) {
    // ⚠️ NIE logujemy treści odpowiedzi ani sekretu — mogłyby wylądować w logach.
    console.error('copernicus.token', { status: r.status });
    throw new BladApi(r.status === 401 ? 'ZLE_DANE' : 'BLAD_TOKENU',
      r.status === 401 ? 'Dane logowania Copernicus są nieprawidłowe.' : 'Nie udało się pobrać tokenu.', 502);
  }
  const j = await r.json();
  token = { wartosc: j.access_token, wygasa: Date.now() + (j.expires_in ?? 600) * 1000 };
  return token.wartosc;
}

class BladApi extends Error {
  constructor(public kod: string, public opis: string, public status = 400) { super(opis); }
}

/* Wołanie Copernicusa z jednym ponowieniem przy 401 (token mógł wygasnąć w locie). */
async function copernicus(sciezka: string, body: unknown, oczekujObraz = false): Promise<Response> {
  for (let proba = 0; proba < 2; proba++) {
    const t = await pobierzToken();
    const r = await fetch(API_BASE + sciezka, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${t}`,
        'Content-Type': 'application/json',
        Accept: oczekujObraz ? 'image/png' : 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (r.status === 401 && proba === 0) { token = null; continue; }   // wymuś świeży token
    if (r.status === 429) throw new BladApi('LIMIT', 'Przekroczono limit zapytań do Copernicus. Spróbuj za chwilę.', 429);
    if (!r.ok) {
      const tresc = await r.text().catch(() => '');
      console.error('copernicus.api', { sciezka, status: r.status, tresc: tresc.slice(0, 300) });
      throw new BladApi('BLAD_API', 'Serwis zdjęć satelitarnych zwrócił błąd.', 502);
    }
    return r;
  }
  throw new BladApi('BLAD_API', 'Serwis zdjęć satelitarnych nie odpowiada.', 502);
}

/* ═══ GEOMETRIA ════════════════════════════════════════════════════════════════
   ⚠️ M-FarmX trzyma obrys jako [[lat, lng], …]. GeoJSON wymaga [lng, lat] —
   ODWROTNEJ kolejności. Pomylenie ich daje AOI gdzieś na drugiej półkuli, a błąd
   jest cichy: API zwróci poprawny, pusty obraz. */
function naGeoJSON(polygon: number[][]) {
  if (!Array.isArray(polygon) || polygon.length < 3) throw new BladApi('ZLA_GEOMETRIA', 'Pole nie ma poprawnego obrysu.', 400);
  const ring = polygon.map(([lat, lng]) => {
    if (typeof lat !== 'number' || typeof lng !== 'number'
      || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new BladApi('ZLA_GEOMETRIA', 'Obrys pola ma nieprawidłowe współrzędne.', 400);
    }
    return [lng, lat];                       // ← zamiana kolejności
  });
  const p = ring[0], k = ring[ring.length - 1];
  if (p[0] !== k[0] || p[1] !== k[1]) ring.push([p[0], p[1]]);   // GeoJSON wymaga zamknięcia
  return { type: 'Polygon', coordinates: [ring] };
}

function bboxZPolygonu(polygon: number[][], marginesM = 120) {
  const lat = polygon.map((p) => p[0]), lng = polygon.map((p) => p[1]);
  const minLat = Math.min(...lat), maxLat = Math.max(...lat);
  const minLng = Math.min(...lng), maxLng = Math.max(...lng);
  const dLat = marginesM / 111_320;
  const dLng = marginesM / (111_320 * Math.cos((minLat + maxLat) / 2 * Math.PI / 180) || 1);
  return [minLng - dLng, minLat - dLat, maxLng + dLng, maxLat + dLat];
}

/* Rozmiar obrazu: 10 m/piksel to natywna rozdzielczość Sentinel-2 dla B02/B03/B04/B08.
   ⚠️ Generowanie 4000×4000 dla pola 12 ha NIE doda szczegółów — doda tylko koszt
   i czas. Ograniczamy do rozsądnego zakresu. */
function rozmiarObrazu(bbox: number[], maks = 1024) {
  const srodekLat = (bbox[1] + bbox[3]) / 2;
  const mX = (bbox[2] - bbox[0]) * 111_320 * Math.cos(srodekLat * Math.PI / 180);
  const mY = (bbox[3] - bbox[1]) * 111_320;
  const skala = 10;                                   // metry na piksel
  const w = Math.round(mX / skala), h = Math.round(mY / skala);
  const f = Math.min(1, maks / Math.max(w, h));
  return [Math.max(64, Math.round(w * f)), Math.max(64, Math.round(h * f))];
}

/* ═══ EVALSCRIPTY ══════════════════════════════════════════════════════════════
   Definiowane WYŁĄCZNIE tutaj. Frontend podaje nazwę warstwy, nigdy kod.

   Pasma Sentinel-2 L2A:
     B02 niebieski · B03 zielony · B04 czerwony (10 m)
     B05 red-edge (20 m) · B08 NIR (10 m) · B11 SWIR (20 m)
     SCL — klasyfikacja scen (maska chmur)

   ⚠️ NDRE i NDMI korzystają z pasm 20-metrowych (B05, B11). Wynik jest przeskalowany
   do rozdzielczości obrazu, ale NIE staje się przez to dokładniejszy niż 20 m. */
const SKALA_ROSLINNOSCI = `
  function kolor(v){
    if (v < 0.0)  return [0.30, 0.30, 0.35];
    if (v < 0.15) return [0.65, 0.24, 0.16];
    if (v < 0.30) return [0.85, 0.45, 0.18];
    if (v < 0.45) return [0.95, 0.72, 0.24];
    if (v < 0.60) return [0.85, 0.87, 0.30];
    if (v < 0.75) return [0.50, 0.75, 0.28];
    if (v < 0.85) return [0.22, 0.58, 0.24];
    return [0.10, 0.38, 0.16];
  }`;

const EVALSCRIPTY: Record<string, string> = {
  truecolor: `//VERSION=3
    function setup(){ return { input:['B02','B03','B04','dataMask'], output:{bands:4} }; }
    function evaluatePixel(s){
      // 2.5 to standardowe rozjaśnienie odbicia Sentinel-2 do podglądu
      return [2.5*s.B04, 2.5*s.B03, 2.5*s.B02, s.dataMask];
    }`,
  ndvi: `//VERSION=3
    function setup(){ return { input:['B04','B08','dataMask'], output:{bands:4} }; }
    ${SKALA_ROSLINNOSCI}
    function evaluatePixel(s){
      let v=(s.B08-s.B04)/(s.B08+s.B04);
      let c=kolor(v); return [c[0],c[1],c[2], s.dataMask];
    }`,
  ndre: `//VERSION=3
    function setup(){ return { input:['B05','B08','dataMask'], output:{bands:4} }; }
    ${SKALA_ROSLINNOSCI}
    function evaluatePixel(s){
      let v=(s.B08-s.B05)/(s.B08+s.B05);
      let c=kolor(v*1.6); return [c[0],c[1],c[2], s.dataMask];   // NDRE ma węższy zakres
    }`,
  ndmi: `//VERSION=3
    function setup(){ return { input:['B08','B11','dataMask'], output:{bands:4} }; }
    function evaluatePixel(s){
      let v=(s.B08-s.B11)/(s.B08+s.B11);
      // Wilgotność: brąz (sucho) → biały → niebieski (wilgotno)
      let c = v<0 ? [0.65,0.48,0.28] : v<0.2 ? [0.86,0.80,0.62]
            : v<0.4 ? [0.80,0.88,0.90] : v<0.6 ? [0.42,0.66,0.82] : [0.16,0.40,0.68];
      return [c[0],c[1],c[2], s.dataMask];
    }`,
};

/* Statystyki liczymy WYŁĄCZNIE dla pikseli roślinności i gleby (SCL 4,5,6,7),
   z pominięciem chmur, cieni i śniegu — inaczej średnie NDVI kłamałoby przy
   częściowym zachmurzeniu. */
const EVALSCRIPT_STATY = `//VERSION=3
  function setup(){
    return { input:[{bands:['B04','B05','B08','B11','SCL','dataMask']}],
      output:[{id:'ndvi',bands:1,sampleType:'FLOAT32'},
              {id:'ndre',bands:1,sampleType:'FLOAT32'},
              {id:'ndmi',bands:1,sampleType:'FLOAT32'},
              {id:'dataMask',bands:1}] };
  }
  function evaluatePixel(s){
    var czyste = (s.SCL===4 || s.SCL===5 || s.SCL===6 || s.SCL===7);
    var m = (s.dataMask===1 && czyste) ? 1 : 0;
    return { ndvi:[(s.B08-s.B04)/(s.B08+s.B04)],
             ndre:[(s.B08-s.B05)/(s.B08+s.B05)],
             ndmi:[(s.B08-s.B11)/(s.B08+s.B11)],
             dataMask:[m] };
  }`;

/* Zachmurzenie DLA POLA (nie dla całej sceny): udział pikseli sklasyfikowanych
   jako chmura/cień w obrysie działki. */
const EVALSCRIPT_CHMURY = `//VERSION=3
  function setup(){
    return { input:[{bands:['SCL','dataMask']}],
      output:[{id:'chmura',bands:1,sampleType:'FLOAT32'},{id:'dataMask',bands:1}] };
  }
  function evaluatePixel(s){
    var zla = (s.SCL===3 || s.SCL===8 || s.SCL===9 || s.SCL===10 || s.SCL===11);
    return { chmura:[zla?1:0], dataMask:[s.dataMask] };
  }`;

/* ═══ OPERACJE ═════════════════════════════════════════════════════════════════ */

async function szukajScen(polygon: number[][], odDni: number) {
  const do_ = new Date(), od = new Date(Date.now() - odDni * 864e5);
  const r = await copernicus('/api/v1/catalog/1.0.0/search', {
    collections: ['sentinel-2-l2a'],
    intersects: naGeoJSON(polygon),
    datetime: `${od.toISOString()}/${do_.toISOString()}`,
    limit: 60,
    fields: { include: ['id', 'properties.datetime', 'properties.eo:cloud_cover'], exclude: [] },
  });
  const j = await r.json();
  const sceny = (j.features ?? []).map((f: any) => ({
    id: f.id,
    data: (f.properties?.datetime ?? '').slice(0, 10),
    chmuryScena: Math.round(f.properties?.['eo:cloud_cover'] ?? 100),
  }));
  // Jeden wpis na dzień — Sentinel bywa zwraca kilka kafli tej samej sceny.
  const wgDaty = new Map<string, any>();
  for (const s of sceny) if (!wgDaty.has(s.data) || s.chmuryScena < wgDaty.get(s.data).chmuryScena) wgDaty.set(s.data, s);
  return [...wgDaty.values()].sort((a, b) => b.data.localeCompare(a.data));
}

async function chmuryNadPolem(polygon: number[][], data: string): Promise<number | null> {
  try {
    const r = await copernicus('/api/v1/statistics', {
      input: { bounds: { geometry: naGeoJSON(polygon) },
               data: [{ type: 'sentinel-2-l2a', dataFilter: {} }] },
      aggregation: {
        timeRange: { from: `${data}T00:00:00Z`, to: `${data}T23:59:59Z` },
        aggregationInterval: { of: 'P1D' }, resx: 20, resy: 20,
        evalscript: EVALSCRIPT_CHMURY,
      },
    });
    const j = await r.json();
    const st = j?.data?.[0]?.outputs?.chmura?.bands?.B0?.stats;
    return st && typeof st.mean === 'number' ? Math.round(st.mean * 100) : null;
  } catch { return null; }        // brak oceny to nie powód, żeby przerwać całość
}

/* ⚠️ „Najnowsze" NIE znaczy „ostatnie w katalogu". Ostatnia scena bywa w całości pod
   chmurami i pokazanie jej jako aktualnego stanu pola wprowadzałoby w błąd.
   Szukamy najnowszej UŻYTECZNEJ: najpierw ≤20% zachmurzenia nad polem, potem ≤40%,
   a jeśli nic nie ma — oddajemy najnowszą z jawną informacją o zachmurzeniu. */
async function najnowszaUzyteczna(polygon: number[][], odDni: number, progi: number[]) {
  const sceny = await szukajScen(polygon, odDni);
  if (!sceny.length) return { scena: null, sceny: [] };

  for (const prog of progi) {
    for (const s of sceny.slice(0, 8)) {                 // ocena kosztuje — max 8 kandydatów
      if (s.chmuryScena > Math.min(95, prog + 45)) continue;   // odsiew bez pytania API
      const nadPolem = await chmuryNadPolem(polygon, s.data);
      s.chmuryPole = nadPolem;
      if (nadPolem !== null && nadPolem <= prog) {
        return { scena: { ...s, jakosc: prog <= 20 ? 'DOBRE' : 'CZESCIOWE' }, sceny };
      }
    }
  }
  const naj = sceny[0];
  if (naj.chmuryPole === undefined) naj.chmuryPole = await chmuryNadPolem(polygon, naj.data);
  return { scena: { ...naj, jakosc: 'DUZE_ZACHMURZENIE' }, sceny };
}

async function obraz(polygon: number[][], data: string, warstwa: string, maks: number) {
  const evalscript = EVALSCRIPTY[warstwa];
  if (!evalscript) throw new BladApi('ZLA_WARSTWA', 'Nieznana warstwa.', 400);
  const bbox = bboxZPolygonu(polygon);
  const [w, h] = rozmiarObrazu(bbox, maks);
  const r = await copernicus('/api/v1/process', {
    input: {
      bounds: { bbox, properties: { crs: 'http://www.opengis.net/def/crs/EPSG/0/4326' } },
      data: [{ type: 'sentinel-2-l2a',
               dataFilter: { timeRange: { from: `${data}T00:00:00Z`, to: `${data}T23:59:59Z` },
                             mosaickingOrder: 'leastCC' } }],
    },
    output: { width: w, height: h, responses: [{ identifier: 'default', format: { type: 'image/png' } }] },
    evalscript,
  }, true);
  const bin = new Uint8Array(await r.arrayBuffer());
  let s = ''; for (let i = 0; i < bin.length; i++) s += String.fromCharCode(bin[i]);
  return { obraz: 'data:image/png;base64,' + btoa(s), bbox, szerokosc: w, wysokosc: h };
}

async function statystyki(polygon: number[][], data: string) {
  const r = await copernicus('/api/v1/statistics', {
    input: { bounds: { geometry: naGeoJSON(polygon) }, data: [{ type: 'sentinel-2-l2a', dataFilter: {} }] },
    aggregation: {
      timeRange: { from: `${data}T00:00:00Z`, to: `${data}T23:59:59Z` },
      aggregationInterval: { of: 'P1D' }, resx: 10, resy: 10, evalscript: EVALSCRIPT_STATY,
    },
  });
  const j = await r.json();
  const o = j?.data?.[0]?.outputs;
  const we = (k: string) => {
    const st = o?.[k]?.bands?.B0?.stats;
    return st ? { srednia: +st.mean?.toFixed(3), min: +st.min?.toFixed(3), max: +st.max?.toFixed(3),
                  pikseli: st.sampleCount ?? null } : null;
  };
  return { data, ndvi: we('ndvi'), ndre: we('ndre'), ndmi: we('ndmi') };
}

/* ═══ WŁASNOŚĆ POLA ════════════════════════════════════════════════════════════
   ⚠️ Obrys bierzemy Z BAZY po fieldId, nigdy z żądania. Gdyby przeglądarka mogła
   przysłać dowolny wielokąt, każdy oglądałby dowolny fragment Polski na nasz koszt,
   a fieldId z innego gospodarstwa dawałoby wgląd w cudze pola. */
async function obrysPola(jwt: string, fieldId: string): Promise<number[][]> {
  const sb = createClient(URL_BAZY, KLUCZ_SERWISOWY, { auth: { persistSession: false } });
  const { data: u } = await sb.auth.getUser(jwt);
  const user = u?.user;
  if (!user) throw new BladApi('BRAK_AUTORYZACJI', 'Zaloguj się ponownie.', 401);

  // 1. Model tabelaryczny (po migracji): RLS i tak by nas nie wpuścił do cudzego,
  //    ale sprawdzamy przynależność jawnie, bo działamy kluczem serwisowym.
  const { data: pole } = await sb.from('fields')
    .select('id, geometry, farm_id, farm_members!inner(user_id)')
    .eq('id', fieldId).maybeSingle();
  if (pole?.geometry?.polygon) {
    const { data: czlonek } = await sb.from('farm_members')
      .select('id').eq('farm_id', pole.farm_id).eq('user_id', user.id).eq('is_active', true).maybeSingle();
    if (!czlonek) throw new BladApi('BRAK_DOSTEPU', 'To pole nie należy do Twojego gospodarstwa.', 403);
    return pole.geometry.polygon;
  }

  // 2. Model dokumentowy (obecny): szukamy pola w gospodarstwie TEGO użytkownika.
  const { data: stan } = await sb.from('user_state').select('data').eq('user_id', user.id).maybeSingle();
  const f = (stan?.data?.fields ?? []).find((x: any) => x.id === fieldId);
  if (!f) throw new BladApi('BRAK_DOSTEPU', 'To pole nie należy do Twojego gospodarstwa.', 403);
  if (!f.geo?.polygon?.length) throw new BladApi('BRAK_OBRYSU', 'To pole nie ma obrysu na mapie.', 400);
  return f.geo.polygon;
}

/* ═══ WEJŚCIE ══════════════════════════════════════════════════════════════════ */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const start = Date.now();
  let akcja = '?', fieldId = '?';
  try {
    const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return odpowiedz({ blad: 'BRAK_AUTORYZACJI', opis: 'Zaloguj się ponownie.' }, 401);

    const body = await req.json();
    akcja = String(body.akcja ?? '');
    fieldId = String(body.fieldId ?? '');
    if (!fieldId) return odpowiedz({ blad: 'BRAK_POLA', opis: 'Nie podano pola.' }, 400);

    const polygon = await obrysPola(jwt, fieldId);
    const odDni = Math.min(180, Math.max(7, Number(body.dni) || 30));
    let wynik: unknown;

    switch (akcja) {
      case 'sceny':
        wynik = { sceny: await szukajScen(polygon, odDni) }; break;
      case 'najnowsza':
        wynik = await najnowszaUzyteczna(polygon, odDni, [20, 40]); break;
      case 'obraz': {
        const data = String(body.data ?? '');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(data)) throw new BladApi('ZLA_DATA', 'Nieprawidłowa data.', 400);
        const warstwa = String(body.warstwa ?? 'truecolor');
        wynik = await obraz(polygon, data, warstwa, Math.min(1024, Math.max(128, Number(body.maks) || 768)));
        break;
      }
      case 'staty': {
        const data = String(body.data ?? '');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(data)) throw new BladApi('ZLA_DATA', 'Nieprawidłowa data.', 400);
        wynik = await statystyki(polygon, data); break;
      }
      default:
        return odpowiedz({ blad: 'ZLA_AKCJA', opis: 'Nieznana operacja.' }, 400);
    }

    console.log('satelita', { akcja, fieldId, ms: Date.now() - start, status: 'ok' });
    return odpowiedz(wynik);
  } catch (e) {
    const b = e instanceof BladApi ? e : new BladApi('BLAD', 'Nie udało się pobrać danych satelitarnych.', 500);
    console.error('satelita', { akcja, fieldId, ms: Date.now() - start, kod: b.kod });
    return odpowiedz({ blad: b.kod, opis: b.opis }, b.status);
  }
});

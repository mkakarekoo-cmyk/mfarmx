# Zdjęcia satelitarne Sentinel-2 (Copernicus Data Space)

## Jak to uruchomić — 7 kroków

**KROK 1.** Wejdź na **https://dataspace.copernicus.eu** i załóż konto (darmowe).

**KROK 2.** Zaloguj się, kliknij swoją nazwę w prawym górnym rogu → **User Settings**
→ zakładka **OAuth clients** → **Create new client**.

**KROK 3.** Nadaj nazwę (np. `m-farmx`) i zatwierdź. Skopiuj **Client ID**.

**KROK 4.** Skopiuj **Client Secret**. ⚠️ Pokazuje się **tylko raz** — jeśli zamkniesz
okno bez skopiowania, trzeba utworzyć klienta od nowa.

**KROK 5.** Wdróż funkcję serwerową: Supabase → **Edge Functions** → **Deploy a new
function** → nazwa `satelita` → wklej `supabase/functions/satelita/index.ts`.

**KROK 6.** Supabase → **Edge Functions → Secrets** → dodaj:

| nazwa | wartość |
|---|---|
| `COPERNICUS_CLIENT_ID` | z kroku 3 |
| `COPERNICUS_CLIENT_SECRET` | z kroku 4 |

⚠️ **Nie dodawaj ich do Vercela.** Vercel serwuje statyczny plik — cokolwiek tam
trafi, będzie widoczne w źródle strony.

**KROK 7.** Uruchom `migracja/06_satelita.sql` w SQL Editorze, wejdź w dowolne pole
z obrysem i kliknij **Najnowsze**.

---

## Architektura

```
przeglądarka  →  Supabase Edge Function `satelita`  →  Copernicus  →  Sentinel-2 L2A
   (anon key)          (CLIENT SECRET tutaj)
```

M-FarmX to **statyczny HTML bez backendu** — nie ma API routes ani server actions.
Funkcja brzegowa Supabase jest jedynym miejscem w tej architekturze, gdzie sekret
może zamieszkać. Przeglądarka wysyła wyłącznie `fieldId`, datę i **nazwę** warstwy.

### Co jest zabezpieczone

- **Client Secret nie istnieje we frontendzie.** Sprawdzalne: `grep -i copernicus index.html`
  zwraca wyłącznie komentarze.
- **Evalscripty są po stronie serwera.** Przyjmowanie kodu z przeglądarki oznaczałoby
  wykonywanie cudzych obliczeń na koszt naszego konta.
- **Obrys pobierany z bazy po `fieldId`**, nigdy z żądania. Inaczej dowolny wielokąt
  = dowolny fragment Polski na nasz limit.
- **Własność pola sprawdza serwer** — najpierw `farm_members`, potem `user_state`
  zalogowanego użytkownika. Podmiana `fieldId` na cudze pole kończy się `403`.

---

## OAuth

`client_credentials` → token trzymany w pamięci instancji, odświeżany **60 s przed
wygaśnięciem**. Przy `401` token jest kasowany i żądanie ponawiane **raz** — token mógł
wygasnąć w locie. Sekret nigdy nie trafia do logów.

---

## Wyszukiwanie najnowszego zdjęcia

⚠️ **„Najnowsze" ≠ „ostatnie w katalogu".** Ostatnia scena bywa w całości pod chmurami
i pokazanie jej jako aktualnego stanu pola wprowadzałoby w błąd.

Algorytm:

1. Catalog API, ostatnie 30 dni, jedna scena na dzień (najniższe zachmurzenie).
2. Próg **≤ 20%** zachmurzenia **nad polem** → status `DOBRE`.
3. Jeśli nic — próg **≤ 40%** → `CZĘŚCIOWE`.
4. Jeśli nadal nic — najnowsza dostępna + jawne `DUŻE ZACHMURZENIE`.

Oceniamy maksymalnie **8 kandydatów** — każda ocena to osobne zapytanie.

### Zachmurzenie: scena vs pole

`eo:cloud_cover` opisuje **całą scenę** (110 × 110 km). Dla działki 12 ha to bywa
bezużyteczne — scena może mieć 60% chmur, a pole leżeć w dziurze między nimi.

Dlatego liczymy osobno **zachmurzenie nad polem** ze Statistical API: udział pikseli
o klasyfikacji SCL 3, 8, 9, 10, 11 (cień, chmury, cirrus) w obrysie. W interfejsie
pokazujemy tę drugą liczbę.

---

## Wskaźniki

| wskaźnik | wzór | pasma | rozdzielczość |
|---|---|---|---|
| True Color | B04/B03/B02 | czerwony, zielony, niebieski | **10 m** |
| NDVI | (B08 − B04) / (B08 + B04) | NIR, czerwony | **10 m** |
| NDRE | (B08 − B05) / (B08 + B05) | NIR, red-edge | **20 m** (B05) |
| NDMI | (B08 − B11) / (B08 + B11) | NIR, SWIR | **20 m** (B11) |

⚠️ **NDRE i NDMI korzystają z pasm 20-metrowych.** Wynik jest przeskalowany do
rozdzielczości obrazu, ale nie staje się przez to dokładniejszy.

⚠️ **NDMI nie jest pomiarem wilgotności gleby.** To wskaźnik spektralny związany
z zawartością wody w roślinności. W interfejsie nazywa się „Wilgotność" dla czytelności,
ale tooltip mówi wprost, czym jest — i tego nie należy zmieniać.

⚠️ **Nie stawiamy diagnoz.** Pokazujemy liczbę, nie „chorobę" czy „niedobór azotu".

### Statystyki

Liczone **tylko z pikseli SCL 4, 5, 6, 7** (roślinność, gleba, woda, nieklasyfikowane) —
z pominięciem chmur i cieni. Bez tego średnie NDVI kłamałoby przy częściowym zachmurzeniu.

---

## Cache i ochrona limitu

| mechanizm | działanie |
|---|---|
| cache w karcie | klucz `akcja + fieldId + parametry` |
| deduplikacja | pięć równoczesnych próśb o to samo = **jedno** zapytanie |
| cache tokenu | jeden token na ~10 minut zamiast na żądanie |
| `SAT_ODSWIEZ_PO_H` | katalog scen sprawdzany najwyżej raz na **12 h** na pole |
| leniwe warstwy | NDVI/NDRE/NDMI pobierane **dopiero po kliknięciu** |
| rozmiar obrazu | 10 m/piksel, maks. 1024 px |

⚠️ Generowanie PNG 4000×4000 dla pola 12 ha **nie doda szczegółów** — Sentinel-2 ma
10 m/piksel niezależnie od tego, o jaki rozmiar poprosimy.

Lista pól **nie wykonuje** żadnych zapytań satelitarnych — dopiero wejście w konkretne pole.

---

## Koszty

Copernicus Data Space ma **darmowy limit** (Processing Units miesięcznie). Miejsca,
które go zużywają, w kolejności apetytu:

1. **Processing API** (obrazy) — najdroższe, jeden PU za obraz.
2. **Statistical API** (wskaźniki, zachmurzenie pola) — liczone od pikseli.
3. **Catalog API** (wyszukiwanie scen) — najtańsze.

Mechanizmy wyżej istnieją właśnie po to, żeby limit wystarczył. **Nie usuwaj cache
„dla świeżości"** — przy kilku gospodarstwach skończy się w kilka dni.

---

## Diagnostyka

| objaw | przyczyna | co zrobić |
|---|---|---|
| „Funkcja nie jest wdrożona" | brak funkcji `satelita` | KROK 5 |
| `401` w logach | zły Client ID/Secret | sprawdź Secrets, KROK 6 |
| `429` | limit zapytań | odczekaj; sprawdź, czy cache działa |
| „Brak użytecznego zobrazowania" | 30 dni pochmurnych | zwiększ `dni` w żądaniu |
| pusty/czarny obraz | AOI poza sceną | sprawdź kolejność współrzędnych |

⚠️ **Najczęstsza pułapka:** M-FarmX trzyma obrys jako `[[lat, lng], …]`, a GeoJSON
wymaga `[lng, lat]`. Pomylenie ich daje AOI na drugiej półkuli, a błąd jest **cichy** —
API zwróci poprawny, pusty obraz. Zamiana jest w `naGeoJSON()`.

Logi: Supabase → Edge Functions → `satelita` → Logs. Logujemy `akcja`, `fieldId`,
czas i status. **Nigdy** tokenu ani sekretu.

---

## Stan wdrożenia

**Zrobione (P0 + część P1):** OAuth, Catalog, najnowsza użyteczna scena, True Color,
NDVI, NDRE, NDMI, dostępne daty, zachmurzenie pola, statystyki, historia zobrazowań,
porównanie dwóch terminów, cache, deduplikacja, interfejs desktop i mobile, fallback.

**Niezrobione (P2):** wykres NDVI w sezonie, automatyczne odświeżanie cronem,
powiadomienia o nowym zobrazowaniu, porównanie sezonów rok do roku, zapisywanie
scen i statystyk do tabel z `migracja/06_satelita.sql` (tabele istnieją, funkcja
jeszcze do nich nie pisze — dziś cache żyje w karcie przeglądarki).

⚠️ **Integracja nie została przetestowana end-to-end z prawdziwym Copernicusem** —
wymaga Twoich danych OAuth. Sprawdzone: interfejs, obsługa błędów i fallback (mapa
działa normalnie, gdy Sentinel jest niedostępny).

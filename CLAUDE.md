# M-FarmX — system zarządzania gospodarstwem

> Nazwa aplikacji: **M-FarmX**. Folder projektu pozostaje `Zagon/`, klucz localStorage `zagon.v1` (nie zmieniać — dane).

Aplikacja dla brata (gospodarstwo rolne + krowy mleczne). Zastępuje ręczne zapiski na kartkach.
**Aplikacja modułowa z sidebarem** — 4 moduły:
- 🌾 **Pola** — dziennik pól: co/rok/pole było siane, ŚOR (pestycydy), plony, mapa z obrysem.
- 🚜 **Flota** — maszyny (ciągniki, kombajny…): przeglądy, oleje, motogodziny (mth), koszty serwisu.
- 💰 **Finanse** — koszty (ropa, opryski, naprawy, zakupy…) i przychody, miesiąc po miesiącu, kategorie, saldo.
- 🐄 **Bydło** — krowy mleczne: stado, inseminacje, wycielenia (auto termin ~283 dni), stan (na stanie / zdjęte).

Moduły Flota/Finanse/Bydło to na razie **szkielety** — funkcje dobudowywane etapami.

## Wygląd
Styl **John Deere Operations Center** (enterprise/flat/GIS) — na życzenie użytkownika (brief wygrywa nad „almanach").
Paleta: primary `#5E7F54`, dark `#4A6543`, light `#7A9D6A`, tło `#F4F5F6`, karty białe, border `#D8D8D8`,
success `#57B657`, warning `#F0B13A`, danger `#D9534F`. Font **Roboto**. Radius 8px, cień `0 2px 8px rgba(0,0,0,.08)`.
Górny zielony navbar 64px (hamburger zwija sidebar), pasek statystyk, pulpit 2-kol (mapa z kolorowymi obrysami
`FIELD_BORDER` + hover glow, oraz kanał aktywności agregujący zdarzenia ze wszystkich modułów). Motyw dołożony
jako blok „MOTYW ENTERPRISE" na końcu `<style>` (nadpisuje wcześniejsze reguły) + remap zmiennych w `:root`.

## Status
Prototyp lokalny (single-file HTML, offline). Dane w `localStorage` przeglądarki.
Kopia zapasowa przez przycisk **Kopia** (eksport JSON) / **Wczytaj** (import).

## Jak uruchomić
Otwórz `index.html` w przeglądarce (dwuklik). Nie wymaga internetu ani instalacji.
Przy pierwszym wejściu utwórz konto (login+hasło) — patrz `LOGOWANIE.md`.

## Logowanie
Lokalna bramka dostępu (Etap 1): konto w `localStorage` (`mfarmx.auth`), sesja (`mfarmx.session`),
opcja „Zapamiętaj mnie", wylogowanie ikoną w navbarze. **Nie jest silnym zabezpieczeniem** — szczegóły
i plan Etapu 2 (serwer) w `LOGOWANIE.md`. Reset konta = usunięcie klucza `mfarmx.auth` (dane gospodarstwa `zagon.v1` zostają).

## Architektura
- `index.html` — cała aplikacja (HTML + CSS + JS). Fonty systemowe.
- **Mapa:** Leaflet 1.9.4 + Leaflet.draw 1.0.4 (z unpkg CDN), zdjęcia satelitarne **Esri World Imagery** (darmowe, bez klucza API) + warstwa nazw miejscowości. Wyszukiwarka miejscowości: **Nominatim** (OpenStreetMap). Mapa wymaga internetu; reszta dziennika działa offline.
- Stan: obiekt JS w `localStorage` pod kluczem `zagon.v1`.
- Renderowanie: przerysowanie z jednego stanu (prosty re-render). Mapa (`LMAP`) tworzona/niszczona przy wejściu/wyjściu z widoku Mapa.
- `backups/` — eksporty JSON (ręczne kopie danych).

## Model danych
```
{
  farm: { nazwa },
  ui: { mapCenter:[lat,lng], mapZoom },       // zapamiętany widok mapy
  fields: [{
    id, nazwa, powierzchnia_ha, lokalizacja,
    geo: { polygon: [[lat,lng], ...] },         // obrys pola (opcjonalny)
    sezony: [{
      rok, uprawa, odmiana, data_siewu, norma_wysiewu,
      zabiegi: [{ data, rodzaj, srodek, dawka, jednostka, koszt }], // rodzaj: herbicyd|fungicyd|insektycyd|zaprawa|nawoz|regulator|inne; koszt w zł
      plon_t, plon_t_ha, wilgotnosc, data_zbioru, notatki
    }]
  }]
}
```

## Model danych — pozostałe moduły
```
machines: [{ id, nazwa, typ, marka, model, rok, nr_rej, mth, notatki,
             przeglady:[{ data, rodzaj, mth, opis, koszt }] }]   // rodzaj: olejowy|techniczny|naprawa|ogumienie|ubezpieczenie|inne
finance:  [{ id, data, kategoria, opis, kwota, typ }]            // typ: koszt|przychod; kategorie w FIN_CATEGORIES
cattle:   [{ id, kolczyk, imie, plec, rasa, data_urodzenia, matka, status, data_zdjecia, notatki,
             inseminacje:[{ data, nasienie, uwagi }],
             wycielenia:[{ data, cielak, uwagi }] }]             // plec: krowa|jałówka|byk|cielę; status: 'na stanie'|dowolny (zdjęte)
```
- Sidebar (`renderSidebar`) + routing przez `view.module` ('pola'|'flota'|'finanse'|'bydlo'). W module Pola dalej podzakładki (`view.name`).
- Bydło: spodziewane wycielenie = ostatnia inseminacja + `CIAZA_DNI` (283), jeśli po niej nie ma wycielenia.
- Finanse: widok miesięczny (kafelki 12 mies. + filtr), sumy per kategoria, saldo. Kwoty w zł.
- Flota: wpis przeglądu z `mth` aktualizuje bieżące motogodziny maszyny.

## Mapa — jak działa
- Widok **Mapa** = główny (hero). Pola jako kolorowane wielokąty (kolor = bieżąca uprawa) z podpisem (nazwa + ha). Klik pola → dziennik.
- **Narysuj nowe pole** → klikasz narożniki na zdjęciu satelitarnym → **powierzchnia liczy się automatycznie** (funkcja geodezyjna `polygonAreaHa`, spherical excess) → formularz nazwy.
- Edycja kształtu: przeciąganie narożników (Leaflet.draw edit) → auto-przeliczenie ha.
- Detal pola z obrysem pokazuje mini-mapę.

## Reguły biznesowe / rolnicze
- Jednostki: powierzchnia w **ha**, dawki ŚOR zwykle **l/ha** lub **kg/ha**, plon w **t** oraz **t/ha** (auto-liczone z t ÷ ha).
- Płodozmian: kolejność upraw rok po roku ma znaczenie agronomiczne → **pasmo płodozmianu** pokazuje historię wg lat, każdy rok kolorowany wg uprawy.
- Kolory upraw = legenda (patrz `CROP_COLORS` w kodzie). Nowe uprawy dostają kolor domyślny.

## Zasady pracy (WAŻNE)
- **Nigdy nie nadpisuj Write'em pliku z danymi użytkownika** — dane są w localStorage i w eksportach `backups/`.
- Design: stosować skill `design` (almanach polowy, nie „dashboard AI"). Element-podpis = pasmo płodozmianu.

## TODO / pomysły na później
- Widok mapki/szkicu pól (rysowanie konturów).
- Ewidencja kosztów (materiał siewny, ŚOR, paliwo) → bilans na hektar.
- Eksport PDF „karta pola" na sezon.
- Ostrzeżenia płodozmianowe (np. rzepak/buraki za często po sobie, karencja ŚOR).
- Wersja serwerowa (wspólny dostęp) — dopiero po akceptacji brata.

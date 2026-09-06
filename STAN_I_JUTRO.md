# M-FarmX — stan i co dalej

_Ostatnia sesja: 2026-09-04_

Aplikacja: **M-FarmX** — system zarządzania gospodarstwem dla brata. Folder `C:\Projekty\Zagon\`.
Główny plik: `index.html`. Repo: `github.com/mkakarekoo-cmyk/mfarmx`. Prod: `https://mfarmx.vercel.app`.

🔑 **M-FarmX zostaje na Supabase Cloud + Vercel. NIE na firmowym VPS** — VPS cyberfolks jest
infrastrukturą firmy, a to projekt prywatny. Granica ma znaczenie przy Porozumieniu o prawach
autorskich (§11 ust. 3). Nie proponować przenosin.

---

## ✅ Zrobione 04.09.2026

### Tryb lokalny (DEV) — praca bez chmury
Na `localhost` apka **omija logowanie i Supabase w całości**: stan trzyma w localStorage pod
osobnym kluczem `mfarmx.dev`, przy pierwszym wejściu wsypuje dane demo, u dołu żółty pasek
„TRYB LOKALNY". Warunek to WYŁĄCZNIE nazwa hosta — na produkcji nic się nie zmienia.
- ⚠️ Klucz `mfarmx.dev` jest osobny od produkcyjnego `mfarmx.cache.<uid>` — praca lokalna
  nie może nadpisać danych brata.
- `?prod=1` wyłącza tryb DEV na localhoście → podgląd prawdziwego ekranu logowania.
- ⚠️ Pułapka: `seed()` **zwraca** stan, nie ustawia go. Bez przypisania wchodziło puste gospodarstwo.

### Rejestracja zamknięta — konta zakłada administrator
Przełącznik `REJESTRACJA_ZAMKNIETA = true`:
- z ekranu logowania zniknął link „Załóż konto",
- wejście na `renderAuth('signup')` (link, historia) przekierowuje na logowanie,
- `doSignup()` ma **własną blokadę** — inaczej dałoby się ją wywołać z konsoli,
- ekran rejestracji ZOSTAJE w kodzie; powrót = zmiana na `false` + odblokowanie w Supabase.

### Panel „Użytkownicy" w apce (admin: `m.kakarekoo@gmail.com`)
Nowy moduł w sidebarze, widoczny tylko dla admina: lista kont, **nowe konto z hasłem**,
zmiana hasła, usunięcie konta (razem z danymi gospodarstwa).
- Hasło startowe proponowane automatycznie, bez znaków mylących (0/O, 1/l/I).
- Konta zakładane z `email_confirm: true` → **działają od razu, bez maila**. To omija problem
  z limitowanym SMTP Supabase i nieustawionym Site URL.
- ⚠️ `ADMIN_EMAILE` w `index.html` steruje TYLKO widocznością zakładki. Prawdziwą decyzję
  podejmuje funkcja serwerowa. Zmieniając admina — zmień OBA miejsca.

### Telefon — naprawione realne przewijanie w bok
Zmierzone przed poprawką na ekranie 390 px: **dokument miał 489 px**, karty i przyciski były ucięte.
Trzy przyczyny, wszystkie naprawione u źródła (nie samym `overflow:hidden`):
1. **`.sb-foot`** (nazwa gospodarstwa + Kopia/Wczytaj) płynął w bok — prawa krawędź **542 px**.
   Ukryty na telefonie: to czynności „przy komputerze", a nazwa jest w Ustawieniach.
2. **`.sb-item` ma w bazowej regule `width:100%`** — w poziomym pasku każda pozycja zajmowała
   365 px i widać było tylko jedną ikonę. Nadpisane `width:auto`.
3. **Przycisk „Wyloguj" był CAŁKOWICIE poza ekranem** (prawa krawędź 450 px przy 390 px) —
   z telefonu nie dało się wylogować. Profil (imię + rola) ukryty, sezon zwężony.
Do tego: logo `white-space:nowrap` (łamało się na dwie linie), kafle 2 w rzędzie, formularze
jednokolumnowe, okna dialogowe pełnoekranowe, cele dotykowe min. 44 px, mapa 320 px.
📌 Po poprawce: dokument 390 px przy ekranie 390 px, zero elementów poza ekranem.


### ETAP 2 — potwierdzanie wykonania i historia (04.09.2026, ZROBIONE)

🔑 **Sedno: `zapiszWykonanie()` — jedno kliknięcie zasila resztę systemu.**
Zadanie ma teraz **rodzaj pracy** (polowe / oprysk / nawożenie / siew / zbiór / transport / warsztat /
gospodarcze / urlop / inne) i **status** (zaplanowane / rozpoczęte / wykonane / anulowane).
Po oznaczeniu jako wykonane formularz pyta o ha, motogodziny, paliwo i godziny, a przy opryskach,
nawożeniu i siewie także o środek, dawkę i powód. Po zapisaniu system SAM:
- zapisuje wykonanie przy zadaniu,
- **przepisuje motogodziny do karty maszyny** — ⚠️ licznik nie może się cofnąć, niższy odczyt jest
  odrzucany z komunikatem, bo to zawsze pomyłka,
- przy oprysku, nawożeniu i siewie **tworzy wpis w ewidencji zabiegów pola** w istniejącej
  strukturze `sezony[].zabiegi`, ze śladem `zZadania`,
- pokazuje na dole ekranu, co dokładnie zaktualizował.

⚠️ **Nie ma osobnego „rejestru zabiegów"** — istniejący jest w module Pola i to on się zasila.
Drugi byłby dokładnie tym dublowaniem, którego unikamy.
📌 Zużycie liczy się na żywo w formularzu: 12,4 ha × 0,5 l/ha = 6,2 l.

**Historia prac — jedno źródło, trzy widoki.** Pole, maszyna i pracownik NIE mają własnych
dzienników; wszystkie czytają `state.schedule`. Wspólny `historiaPrac(filtr)` + `podsumowanieGodzin()`:
- **karta pola** — prace wykonane na tym polu,
- **karta maszyny** — zadania, w których była ciągnikiem albo narzędziem, plus godziny wg rodzaju,
- **karta pracownika** (klik w wiersz grafiku) — zadania, godziny, użyte maszyny i pola.

📌 Sprawdzone puppeteerem: motogodziny 4820 → 5000, wpis zabiegu utworzony ze śladem źródła,
historia pola filtruje poprawnie (praca z innego pola nie wchodzi), tablica oznacza stany.
📌 Szerokości: ramka 822 px = tabela 822 px, wszystkie 7 dni widoczne bez przewijania.

⏳ **ETAP 3 (następny):** magazyn, zdejmowanie stanu przy zabiegu, koszt materiału na pole.
Formularz wykonania już zbiera środek, dawkę i liczy zużycie — brakuje magazynu, z którego ma schodzić.


### KONTA PRACOWNIKÓW — dostęp do własnego grafiku (04.09.2026)

Pracownik loguje się na własne konto i widzi **wyłącznie swoje zaplanowane prace**, na dużym,
czytelnym ekranie zajmującym całą szerokość strony. Bez sidebara, modułów i panelu administratora.

🔑 **Problem, który to rozwiązywało:** cały stan gospodarstwa siedzi w JEDNYM wierszu `user_state`
przypisanym do właściciela. Pracownik z własnym kontem dostałby puste gospodarstwo.
Rozwiązanie: tabela `dostep_pracownika` wiąże konto z gospodarstwem, a dodatkowa polityka
na `user_state` pozwala mu czytać wiersz właściciela.

⚠️ **WYŁĄCZNIE ODCZYT — i to jest decyzja, nie niedoróbka.** Zapis oznaczałby nadpisanie CAŁEGO
dokumentu gospodarstwa; jedna pomyłka kasowałaby pola, maszyny i finanse właściciela. Dopóki stan
jest jednym jsonb-em, prawo zapisu dla pracownika jest zbyt niebezpieczne. Gdy zadania kiedyś
wyjdą do osobnej tabeli, pracownik dostanie zapis ograniczony do swoich.

**Jak założyć konto:** Użytkownicy → **+ Konto pracownika** → wybierz osobę z listy (wymagane,
bo bez tego nie wiadomo, czyje zadania pokazać), podaj e-mail, hasło proponuje się samo.
Funkcja serwerowa zakłada konto i powiązanie w JEDNYM kroku — gdyby powiązanie padło, konto jest
kasowane, żeby nie zostawały konta bez dostępu.

**Widok pracownika:** „DZIŚ" z dużymi kartami (godziny, zadanie, pole z ha i uprawą, ciągnik,
maszyna, uwagi) oraz „NAJBLIŻSZE DNI". Świadomie inna skala niż panel gospodarza — ma być czytelne
z odległości i w rękawicach.
⚠️ `auto-fit`, nie `auto-fill` w siatce kart: przy `auto-fill` dwie karty zostawiały puste kolumny
i widok wyglądał na wciśnięty w lewy róg.

📌 Sprawdzone puppeteerem: pracownik widzi 2 zadania na dziś i 2 nadchodzące, **zadania drugiego
pracownika nie są widoczne**, sidebara nie ma, karty wypełniają szerokość (668 + 668 = 1352 px),
zero przewijania w bok.

⏳ **DO WDROŻENIA, inaczej konta pracowników nie zadziałają:**
1. `schema_pracownicy.sql` → Supabase → SQL Editor (tabela + polityki).
2. Zaktualizowana funkcja `admin-uzytkownicy` (doszła akcja `dodaj-pracownika`) → Edge Functions.


### GRAFIK — układ na całą szerokość (05.09.2026)

Poprawiony **wyłącznie wygląd i responsywność** — logika, drag & drop i struktura danych nietknięte.

🔑 **Główna przyczyna „małego widgetu na środku": `.content` miał `max-width:1180px`.**
Na Full HD tablica zajmowała ułamek ekranu, a po bokach zostawały puste pasy.
Rozwiązanie: klasa `pelna` na `<main class="content">` **tylko dla Grafiku** — pozostałe moduły
zostają w kolumnie 1180 px, bo tam długie linijki tekstu byłyby nieczytelne.

Układ: `grid-template-columns: minmax(0,1fr) 340px`.
⚠️ `minmax(0,1fr)`, nie `1fr` — bez tego zawartość tabeli rozpycha kolumnę ponad dostępną szerokość.

**Zmierzone po zmianie** (te trzy rozdzielczości, o które prosiłeś):
| ekran | obszar treści | tabela + panel | wiersz | przewijanie w bok |
|---|---:|---|---:|---|
| 1920×1080 | 1684 | 1282 + 340 | 132 px | nie |
| 1600×900 | 1364 | 962 + 340 | 132 px | nie |
| 1366×768 | 1130 | 768 + 300 | 146 px | nie |

**Co jeszcze doszło w warstwie wizualnej:**
- **Toolbar** — jeden spójny pasek (‹ · zakres · › · Dzisiaj · + Zadanie · + Pracownik) zamiast
  kontrolek rozrzuconych po szerokości.
- **Kolumna pracownika**: avatar z inicjałami + nazwisko + **godziny w tygodniu** (z zaplanowanych
  zakresów, a dla odhaczonych prac z wykonania).
  ⚠️ `display:flex` NA `th` odbiera komórce wysokość wiersza — tło kończyło się w połowie kratki.
  Flex musi siedzieć w wrapperze `.prac-w` w środku.
- **Karty**: tło i obwódka wg rodzaju pracy (blade kolory, bez gradientów), nazwa `600`, reszta
  mniejsza; karta wypełnia szerokość komórki.
- **Weekend** i **dzisiaj** mają delikatnie inne tło.
- **Podsumowanie tygodnia** — jedna kompaktowa linia, nie kafle dashboardu.
- **Panel** 340 px, `position:sticky` z własnym scrollem; wszystkie trzy sekcje otwarte domyślnie
  (accordion pozwala teraz mieć otwartych kilka naraz, nie jedną).
- **Flota**: nazwa po lewej, status kropką i słowem po prawej; szczegóły w dymku, żeby wiersz
  nie puchł do trzech linijek.

**Breakpointy:** >1400 px panel 340 · 1100–1400 panel 300 · <1100 panel schodzi pod tablicę,
tabela ma własny scroll poziomy z przyklejoną kolumną pracownika.

📌 Przy okazji dołożone **zmienne CSS układu** w `:root` (`--u-skala`, `--u-szer`, `--u-gestosc`,
`--u-krata`, `--u-prac`, `--u-panel`, `--u-rog`) — wszystkie kluczowe wymiary Grafiku są przez nie
sterowane. ⚠️ Wpisanie liczby na sztywno w te reguły cicho odłączy odpowiednie pokrętło.
⏳ Panel z suwakami do strojenia tych wartości na żywo — zaczęty, niedokończony.


### FLOTA — panel maszyn zamiast galerii kart (05.09.2026)

Poprawiony **wyłącznie widok** — backend, modele i logika nietknięte.

🔑 **Ta sama przyczyna co w Grafiku: `.content` z `max-width:1180px`.** Trzy duże kafle na środku
zostawiały ~70% ekranu pustego, a niosły mniej informacji, niż zajmowały miejsca.
Flota dołączyła do listy modułów z klasą `pelna` (razem z Grafikiem).

**Widok listy** (domyślny) z kolumnami: maszyna · typ · status · mth · serwis · OC · badanie · akcje.
Wiersz ~69 px. Do tego **widok kartowy** jako opcja (przełącznik ☷ / ▦) — kompaktowe karty,
`auto-fill` od 212 px, czyli 5–7 kolumn na Full HD zamiast trzech na środku.

**Toolbar**: wyszukiwarka (nazwa, typ, marka, model, rejestracja, VIN) · filtr typu (z realnych
typów we flocie, nie z listy wpisanej na sztywno) · filtr statusu · sortowanie (nazwa /
najbliższy serwis / motogodziny).
**Podsumowanie** jako jeden pasek: ile maszyn, dostępnych, pracuje, serwis, awaria, ile wymaga serwisu.
⚠️ Usunięta duża pusta karta „+ Dodaj maszynę" ze środka ekranu — został jeden przycisk w prawym górnym rogu.

**Alerty** liczone, nie wpisywane: `✓ 300 mth do serwisu` · `⚠ 50 mth do serwisu` (≤50) ·
`🔴 przekroczony o N mth`. Terminy OC i badania: zielone, pomarańczowe przy ≤30 dniach, czerwone po terminie.

⚠️ **Model danych rozszerzony ADDYTYWNIE**, nie zmieniony: `vin`, `status`, `interwal`, `oc`,
`badanie` są opcjonalne. Maszyny sprzed tej zmiany działają dalej i pokazują „—" tam, gdzie danych
nie ma. Bez `interwal` lista pisze wprost „brak interwału" zamiast zgadywać termin serwisu.

**Responsywność:** <1400 px znika kolumna typu · <1200 px OC i badanie · <900 px akcje,
a wyszukiwarka zajmuje całą szerokość paska.

📌 Zmierzone: 1920×1080 → treść 1684, tabela 1640; 1366×768 → treść 1130, tabela 1086.
Zero przewijania w bok, 5 alertów wykrytych na 8 maszynach testowych.


### INTEGRACJA: FLOTA ↔ GRAFIK ↔ MAPA ↔ POLA (05.09.2026)

🔑 **Zasada: ZADANIE JEST JEDYNYM ŹRÓDŁEM.** Flota, mapa i karta pola nie trzymają własnych
informacji o tym, gdzie maszyna pracuje — wszystko wylicza się z `state.schedule`.
⚠️ **Nie dodawaj `maszyna.aktualnePole`, `aktualnyPracownik` ani `aktualneZadanie`.** Każde takie
pole trzeba by odświeżać w kilku miejscach i po pierwszej pomyłce zacznie kłamać.

**Funkcje warstwy integracyjnej** (blok „INTEGRACJA" w `index.html`):
- `zadanieTrwa(z)` — czy praca dzieje się TERAZ. Zadanie bez godzin = całodniowe, inaczej wpis
  „na dziś, bez godzin" nigdy nie pokazałby maszyny jako pracującej.
- `aktywneZadanieMaszyny(id)` — trwające, a jak nie ma, to najbliższe dzisiejsze (żeby Flota
  o 6 rano pokazywała plan dnia, a nie pustkę).
- `statusMaszyny(m)` — **status WYLICZANY, nigdy zapisywany.** Kolejność: ręczny
  (awaria / serwis / niedostępna) wygrywa zawsze → potem trwające zadanie → „pracuje" → inaczej
  „dostępna". Słowo „pracuje" nie istnieje w danych.
- `maszynyNaPolu(id)` · `pozycjaMaszyny(m,pole)` — centroid obrysu pola.

**Flota**: kolumna **Aktualna praca** (zadanie + pole + operator, wszystko klikalne), filtr
**W pracy**, menu **⋯** (Szczegóły · Pokaż aktualne zadanie · Pokaż na mapie · Historia prac ·
Dodaj serwis · **+ Przypisz zadanie**). Pozycje niedostępne są wyszarzone, nie ukryte — inaczej
menu zmieniałoby kształt przy każdej maszynie.
**+ Przypisz zadanie** otwiera ten sam formularz co Grafik, z maszyną już wybraną — jedna
ścieżka zapisu, nie druga.

**Mapa**: znaczniki maszyn generowane z aktywnych zadań na dziś, w centroidzie pola.
Dymek: maszyna, stan, zadanie, pracownik, pole, godziny, narzędzie + przyciski „Otwórz maszynę"
i „Otwórz zadanie". Kilka zadań na jednym polu dostaje lekki rozstrzał, żeby się nie zasłaniały.
„Pokaż na mapie" z Floty przechodzi na Pulpit, kadruje pole i otwiera dymek.

**Karta pola**: sekcja **AKTUALNIE** (przy kilku maszynach „Aktualnie — 2 maszyny") z linkami
do maszyny, pracownika i zadania.

⚠️ **GPS — przygotowane, nie zaimplementowane.** `pozycjaMaszyny()` jest JEDYNYM miejscem
ustalającym pozycję znacznika; dołożenie GPS-u to jeden warunek na jej początku (zakomentowany
w kodzie): świeża pozycja z urządzenia → użyj jej, brak → centroid pola z aktywnego zadania.

📌 **Sprawdzone puppeteerem, scenariusz po scenariuszu:**
| krok | wynik |
|---|---|
| start: Axion na polu A | ax `pracuje`, pole A: 2 maszyny |
| zadanie przeniesione na pole B | pole A: 0, pole B: 2 — **bez żadnej ręcznej zmiany** |
| ciągnik podmieniony Axion→Arion | ax `dostępna`, ar `pracuje` — automatycznie |
| Arion ustawiony ręcznie na awarię | ar `awaria` **mimo trwającego zadania** (ręczny wygrywa) |
| mapa | 1 znacznik maszyny |
| karta pola B | „Aktualnie — 2 maszyny" |
| Flota, filtr „W pracy" | 3 wiersze → 1 |

---

## ⏳ DO ZROBIENIA (kolejność)

### 1. Wdrożyć funkcję serwerową — BEZ TEGO PANEL NIE DZIAŁA
Plik gotowy: `supabase/functions/admin-uzytkownicy/index.ts`.
Panel Supabase → **Edge Functions → Deploy a new function**:
- nazwa: **`admin-uzytkownicy`**, wklej całą zawartość pliku,
- **Edge Functions → Secrets**: `ADMIN_EMAILS` = `m.kakarekoo@gmail.com`
  (`SUPABASE_URL` i `SUPABASE_SERVICE_ROLE_KEY` Supabase podstawia sam).

### 2. Zablokować rejestrację po stronie serwera
Authentication → Providers → Email → **wyłącz „Enable Sign Ups"**.
Apka już jej nie pokazuje, ale bez tego da się założyć konto strzelając prosto do API.

### 3. Site URL (dotąd nigdy nieustawiony)
Authentication → URL Configuration → Site URL = `https://mfarmx.vercel.app`,
Redirect URLs: `https://mfarmx.vercel.app`, `https://mfarmx.vercel.app/**`, `http://localhost:*`.
Bez tego „Nie pamiętam hasła" wysyła link prowadzący na localhost.

### 4. Wygaszanie projektu Supabase
Darmowy plan usypia projekt po ~7 dniach bezczynności — **to się już zdarzyło**: 04.09 auth
zwracał 502, REST 521, a potem „nie znaleziono tabeli `user_state`". Wróciło samo po obudzeniu.
Do decyzji: plan Pro (nie usypia) albo codzienny ping utrzymujący projekt przy życiu.

### 5. „Zmień hasło" dla zwykłego użytkownika
Admin ustala hasło i przekazuje je — użytkownik powinien móc je zmienić sam.
Dla zalogowanego to jedno wywołanie `updateUser`, bez poczty.

---

## 📌 Fakty / dostępy
| Co | Wartość |
|----|---------|
| Repo GitHub | `github.com/mkakarekoo-cmyk/mfarmx` (push tokenem `mkakarekoo-cmyk`) |
| Prod URL | `https://mfarmx.vercel.app` |
| Supabase URL | `https://bmjvfscyosyhmtpskphm.supabase.co` |
| Supabase tabela | `public.user_state` (jsonb per user + RLS) |
| Administrator | `m.kakarekoo@gmail.com` |
| Token PAT | `C:\Users\mkaka\Documents\Token.txt` (⚠️ jawny) |
| Serwer lokalny | `npx http-server -p 5500 -c-1` → `http://localhost:5500` |

## 🧭 Roadmapa funkcji (dalej)
Rejestr zabiegów ARiMR (PDF) · porównanie plonów przez lata · magazyn ŚOR ze zdejmowaniem
stanu · przypomnienia bydła i floty · własna domena + branded SMTP.

## Push (przypomnienie komendy)
```bash
cd C:/Projekty/Zagon
TOKEN=$(tr -d ' \t\r\n' < /c/Users/mkaka/Documents/Token.txt)
B64=$(printf 'mkakarekoo-cmyk:%s' "$TOKEN" | base64 -w0)
git -c credential.helper= -c http.extraHeader="Authorization: Basic $B64" push origin main
```

### PULPIT — centrum operacyjne (05.09.2026)

Pulpit ma odpowiadać na pięć pytań w kilka sekund: **KTO pracuje · CO robi · GDZIE · CZYM ·
CO JESZCZE zostało.** Mapa niesie „gdzie", panel po prawej całą resztę.

🔑 **Nie ma tu drugiego systemu zadań.** Panel, mapa, Flota i Grafik czytają to samo
`state.schedule`. „+ Zadanie" z Pulpitu i z dymka pola otwierają **ten sam** `openZadanieForm()`
co Grafik — jedna ścieżka zapisu, więc zadanie natychmiast widać we wszystkich czterech miejscach.

**Układ.** `render()` nadaje Pulpitowi klasę `pelna` (razem z Grafikiem i Flotą), która zdejmuje
`.content{max-width:1180px}`. Bez tego mapa zostawała wąskim widżetem na 2/3 ekranu — ta sama
przyczyna, co wcześniej w Grafiku i we Flocie. Siatka: `minmax(0,1fr) 360px`, mapa
`clamp(560px,74vh,760px)`.
⚠️ **Panel schodzi pod mapę już przy 1400 px, nie przy 1180.** Przy 1366 px sidebar + panel 360 px
zostawiały mapie 706 px szerokości przy 666 px wysokości — prawie kwadrat, w którym pola przestają
być czytelne. Próg jest o szerokość sidebara wyższy niż wynikałoby z samej mapy.

**Panel operacyjny** (`renderPanelOperacyjny`), sekcje zwijane, stan w `state.ui.pulpit.otwarte`:
- **DZISIAJ** — zadania z dziś (wykonane zostają, wyszarzone; wypadają tylko anulowane),
  godzina + kolor rodzaju pracy + pole · pracownik · ciągnik. Klik → karta zadania.
- **MASZYNY W PRACY** — z `statusMaszyny()`, czyli **wyliczane, nigdzie nie zapisane**.
  Każdy człon to odnośnik: maszyna → Flota, pole → kadr mapy, operator → karta pracownika.
- **DO ZROBIENIA** — ta sama lista `state.tasks` co w Grafiku, z tym samym `dragZadanie`.
- **AKTYWNOŚĆ** — pozycje z `feedItemsHtml()` (wydzielone z dawnego `renderActivityFeed`,
  które zniknęło razem z dwukolumnowym pulpitem). Startuje zwinięta — to historia, nie „teraz".

**Mapa.** Wypełnienie pola dalej znaczy **uprawę** (pasmo płodozmianu to znak firmowy apki);
stan operacyjny niesie **obwódka**: bursztyn = praca w toku, morski = zaplanowane dziś,
zielony = zrobione dziś, biały = nic na dziś. Legenda jest pod mapą.
⚠️ Wcześniej pola bez zadań brały kolor z palety `FIELD_BORDER`, której pierwszy odcień to
`#F0B13A` — **dokładnie ten sam bursztyn, co „praca w toku"**. Dwa sąsiednie pola wyglądały
identycznie, choć jedno było w robocie, a drugie nie. Dlatego neutralne pola mają teraz jedną
białą obwódkę (`POLE_OBWODKA_NEUTRALNA`), a kolor na obwódce znaczy wyłącznie stan.

**Klik w pole otwiera dymek**, nie od razu dziennik: z mapy częściej planuje się pracę, niż czyta
historię. W dymku: ha, uprawa, stan, maszyny obecnie na polu + „+ Zadanie" (z polem już wybranym)
i „Dziennik pola" — więc do dziennika dalej prowadzi jedno kliknięcie.

⚠️ **Znacznik maszyny kotwiczy się 29 px NAD centroidem** (`iconAnchor:[17,46]`). Podpis pola to
tooltip, a warstwa tooltipów w Leaflecie leży **nad** warstwą znaczników — znacznik zakotwiczony
w centroidzie chował się pod nazwą pola i wyglądał jak brak markera. `zIndexOffset` tu nie pomoże,
bo problem jest między panes, nie w obrębie jednego.

📱 **Telefon:** siedem kafelków jeden pod drugim zabierało cały pierwszy ekran, więc pasek
statystyk zjeżdża w jeden przewijany poziomo rząd — na Pulpicie najpierw ma być widać mapę.

📌 **Sprawdzone puppeteerem (1920 / 1366 / 390 px):**
| co | wynik |
|---|---|
| `main.content.pelna` | tak — 1684 px zamiast 1180 |
| mapa | 1260 × 760 px, panel 360 px |
| pasek statystyk | 7 kafelków, w tym „Zadania dzisiaj 2" i „Maszyny w pracy 1" |
| sekcje panelu | DZISIAJ 2 · MASZYNY W PRACY 1 · DO ZROBIENIA 6 · AKTYWNOŚĆ (20 pozycji) |
| zadanie trwające / wykonane | 1 z klasą `trwa`, 1 z `zrobione` |
| znacznik maszyny na mapie | 1, widoczny nad podpisem pola |
| klik w pole „Za stodołą" | obwódka `#F0B13A` gr. 4, dymek „● praca w toku" |
| „+ Zadanie" z dymka | formularz Grafiku z **ustawionym** polem |
| zwijanie sekcji | zapamiętane po przejściu Flota → Pulpit |
| 1366 px | panel pod mapą, mapa 1086 px, bez przewijania w poziomie |
| 390 px | mapa 320 px, bez przewijania w poziomie |
| błędy JS | brak |

### WARSZTAT W GRAFIKU — jeden grafik dla wszystkich prac (05.09.2026)

Ci sami ludzie pracują na polu, w warsztacie, w transporcie i w obejściu, więc jest **jeden
Grafik**, nie cztery. Miejsce pracy **nie jest osobnym polem zadania** — wynika z `rodzaj`,
który zadanie ma od zawsze (`MIEJSCA_PRACY` + `miejsce` w `RODZAJE_PRAC`).

⚠️ **Nie dokładaj `taskType` ani `workLocationType` obok `rodzaj`.** Dwa pola opisujące to
samo rozjeżdżają się przy pierwszej edycji i potem nie wiadomo, któremu wierzyć — ten sam
błąd, przed którym broni się Flota (status maszyny liczony, nie zapisany).

**Formularz jest dwuetapowy:** najpierw „Co chcesz zaplanować?" (🚜 pole · 🔧 warsztat ·
🚚 transport · 🏠 gospodarstwo · ● inne), potem tylko pasujące pola. Przy warsztacie nie ma
pola uprawnego, przy pracy polowej nie ma priorytetu naprawy. Szkic (`_zadanieSzkic`)
przeżywa przełączenie miejsca, więc wpisane dane nie giną.

**Warsztat naprawia też cudze maszyny** (`zrodlo: OWN | CUSTOMER`). Pełnego CRM klientów tu
nie ma i nie udajemy, że jest — przy maszynie klienta wystarczy nazwa w jednym polu.
Architektura tego nie blokuje.

**Rodzaje prac warsztatowych** (`state.rodzajeWarsztatowe`) siedzą w stanie, nie w kodzie —
lista podpowiada, nie więzi, a zmienia się bez wydania nowej wersji apki.

**Maszyna zadania**: `ciagnikId` i `maszynaId` to dwa gniazda na sprzęt (pojazd + narzędzie).
Praca warsztatowa używa tych samych: ciągnik trafia do `ciagnikId`, reszta do `maszynaId`.
Dzięki temu konflikty, historia maszyny i Flota działają **bez żadnych zmian**.

**Hierarchia stanu maszyny** (`statusMaszyny`), od najsilniejszego:
1. ręczna AWARIA / NIEDOSTĘPNA — człowiek stwierdził fakt,
2. trwające zadanie **warsztatowe** → `warsztat` (maszyna stoi u mechanika, nie orze),
3. ręczny SERWIS — zapowiedź bez wpisu w grafiku,
4. trwające zadanie polowe / transportowe → `pracuje`,
5. inaczej → `dostępna`.

⚠️ Warsztat wyprzedza ręczny serwis świadomie: zadanie niesie KTO, CO i DO KIEDY, ręczny
status niesie samo słowo. `STATUSY_MASZYN` (do ręcznego wyboru) **nie zawiera** `pracuje`
ani `warsztat` — te dwa wynikają z grafiku i wpisane z ręki zaraz by skłamały.

**Konflikty**: doszedł `konfliktPracownika()`. Wcześniej pilnowaliśmy tylko maszyn, a odkąd
w grafiku są naprawy obok orki, kolizja „naprawa 07–12" z „orką 10–14" zdarza się realnie.
Sprawdzany przy zapisie i przy przeciągnięciu karty (upuszczenie zmienia naraz pracownika
i dzień, więc sprawdzamy w NOWYM terminie u NOWEGO człowieka).

**Mapa i karta pola pokazują wyłącznie prace polowe.** Naprawa w warsztacie nie odbywa się
na polu, więc znacznik w centroidzie działki byłby kłamstwem — nawet gdyby zadanie miało
pole wpisane.

📌 Usunięty przy okazji **martwy drugi formularz zadania** (`openShiftForm`/`saveShift`/
`delShift`) — zapisywał `zajecie` bez rodzaju pracy, więc takie wpisy nie trafiały ani do
Floty, ani na mapę. Nie był wołany z żadnego miejsca.

⚠️ **Pułapka szablonów:** `title="${...}"` **wewnątrz** zwykłego ciągu w apostrofach nie
interpoluje — zagnieżdżenie `${}` w `'...'` w środku `${}` to składniowy błąd, który wywala
CAŁY skrypt (aplikacja przestaje się ładować, `goModule is not defined`). Buduj taki
fragment do zmiennej przed użyciem.

### Mapa „Dodaj nowe pole" na pełną szerokość
Rysowanie obrysu to praca na mapie, nie czytanie formularza — `pelnaSzerokosc()` obejmuje
teraz także `pola/nowePole`, mapa 1240 × 740 px zamiast wąskiej kolumny. Warunek wyjechał
z linijki `render()`, bo zaczynał być nieczytelny.

### Pracownicy, konta i zgłoszenia
Osobny dokument: [PRACOWNICY_I_ZGLOSZENIA.md](PRACOWNICY_I_ZGLOSZENIA.md) — role, uprawnienia,
cykl życia zgłoszenia, powiadomienia, granica „to nie jest zabezpieczenie" i lista rzeczy
do wdrożenia w Supabase.

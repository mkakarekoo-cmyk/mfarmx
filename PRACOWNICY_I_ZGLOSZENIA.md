# Pracownicy, konta, uprawnienia i zgłoszenia (05.09.2026)

## Zasada: pracownik ≠ konto

**Pracownik** to osoba w gospodarstwie. **Konto** to sposób logowania. Nie są tym samym:
pracownik może być w Grafiku, zanim dostanie zaproszenie, a konto dopina się później
(`w.konto = {email, userId, utworzono}`).

Dlatego jest **jedna lista** `state.workers`, a nie osobno „użytkownicy" i „pracownicy"
do ręcznego zestawiania. Dodanie pracownika = od razu wiersz w Grafiku; **nie ma drugiego
kroku „dodaj do grafiku"**, bo Grafik czyta tę samą listę ludzi.

Dezaktywacja (`w.aktywny = false`) zdejmuje człowieka z tablicy, ale **jego zadania zostają
w danych** — historia prac i rozliczenie godzin muszą się zgadzać także po odejściu.

## Role i uprawnienia

```
w.typKonta   FARM_ADMIN | EMPLOYEE      ← typ użytkownika
w.uprawnienia { grafikCaly, grafikTworzy, grafikZarzadza,
                flotaWidzi, flotaEdytuje, polaWidzi, polaEdytuje,
                warsztatWidzi, todoDodaje, todoZarzadza }
```

`FARM_ADMIN` ma wszystko (`maUprawnienie()` zwraca `true` bez sprawdzania mapy). Nowy
pracownik dostaje **minimum**: `{todoDodaje: true}`. Reszta jest świadomym gestem
administratora na karcie pracownika. Pracownik z `grafikZarzadza` zarządza Grafikiem,
ale **nie staje się administratorem** — nie nadaje uprawnień ani nie zakłada kont.

W interfejsie nie ma nazw technicznych. Administrator widzi „Może zmieniać zadania innych",
nie `MANAGE_SCHEDULE`; klucz techniczny zostaje w kodzie i to on pojedzie kiedyś do RLS.

## ⚠️ Granica: to nie jest zabezpieczenie

**Uprawnienia sterują wyłącznie tym, co widać w przeglądarce.** Całe gospodarstwo to
**jeden dokument `jsonb`** w `user_state`, więc każdy zalogowany pracownik pobiera go
w całości — z finansami i bydłem włącznie. Ukrycie modułu w menu jest wygodą, nie ochroną
danych. Ostrzeżenie jest wypisane wprost na karcie pracownika, żeby nikt się nie pomylił.

Prawdziwe egzekwowanie (§7 i §25 specyfikacji) wymaga rozbicia dokumentu na tabele
z `farm_id` i politykami RLS. **Nie da się tego dołożyć bez migracji** — to nie jest
kwestia dopisania polityki.

Kolejność wychodzenia z jsonb-a, gdyby do tego doszło:
1. ✅ `zgloszenia` — zrobione, patrz niżej
2. `zadania` (grafik) — najwięcej zysku: pracownik mógłby wtedy odhaczać SWOJE zadania
3. `pracownicy` + `uprawnienia` — dopiero wtedy uprawnienia zaczynają cokolwiek znaczyć
4. `pola`, `maszyny`, reszta

## Zgłoszenia („Do zrobienia") — pierwsza prawdziwa tabela

**Problem:** pracownik ma móc zgłosić „w Axionie trzeba wymienić lampę". Ale `dostep_pracownika`
daje mu do `user_state` **tylko odczyt** — zapis oznaczałby nadpisanie całego dokumentu
gospodarstwa. Jedna pomyłka i znikają pola, maszyny, finanse.

**Rozwiązanie:** `schema_zgloszenia.sql` — własna tabela z własnym RLS:
- pracownik **dopisuje** swoje wiersze i widzi **wyłącznie swoje** (§21),
- właściciel widzi i zmienia wszystkie wiersze **swojego** gospodarstwa,
- pracownik **nie ma** UPDATE ani DELETE — zgłoszenie to ślad zdarzenia.

⚠️ `wlasciciel_id` przychodzi z przeglądarki, więc polityka INSERT **nie bierze go na wiarę** —
sprawdza w `dostep_pracownika`, że piszący naprawdę należy do tego gospodarstwa. Bez tego
warunku dowolny zalogowany użytkownik wrzucałby wpisy do cudzego gospodarstwa.

Gospodarz klika **„↻ Pobierz z telefonów"**, wiersze lądują w `state.tasks` i dostają
`przeniesione = true`, żeby nie wracały przy każdym odświeżeniu.

## Cykl życia zgłoszenia

```
NEW → PLANNED → IN_PROGRESS → DONE
 └──→ REJECTED
```

⚠️ **Status jest WYLICZANY** z powiązanego zadania (`statusZgloszenia()`), nie zapisywany —
ta sama zasada co przy statusie maszyny. Skasowanie zadania cofa zgłoszenie do `NEW`,
bo praca dalej czeka.

**Zgłoszenia nie kasujemy po zaplanowaniu.** Zostaje ślad: kto zauważył → kto zaplanował →
kto wykonuje. „Odrzuć" zachowuje historię, „Usuń" ją niszczy — i tylko to drugie pyta
o potwierdzenie.

`ZAPLANUJ` otwiera **ten sam** `openZadanieForm()` co reszta aplikacji, z wypełnionymi
danymi. Powiązanie (`t.zadanieId`) dopina się **dopiero po zapisaniu zadania** — gdyby
użytkownik się rozmyślił, zgłoszenie musi zostać w kolejce jako `NEW`.

## Powiadomienia

W aplikacji, bez maila i WhatsAppa — te wymagają serwera; w formularzu pracownika zapisujemy
na razie samą zgodę. `workerId === null` znaczy „dla administratora".

Pracownik dostaje sygnał o rzeczach, które zmieniają **jego dzień**:

| zdarzenie | powiadomienie |
|---|---|
| nowe zadanie | `nowe` |
| zmiana daty / godzin / pola / maszyny / rodzaju | `zmiana` |
| zmiana samych uwag albo opisu | **żadne** — nie budzimy nikogo literówką |
| przepisanie na kogo innego | staremu `anulowane`, nowemu `nowe` |
| anulowanie / usunięcie | `anulowane` |
| jego zgłoszenie zaplanowane / odrzucone | `zgloszenie` |

⚠️ **Pułapka, na którą się nadziałem:** nazwałem funkcję `powiadom()`, a w projekcie
**już istniała** `powiadom(tekst)` — toast u dołu ekranu. Deklaracja zdefiniowana niżej
w pliku wygrywa, więc moja funkcja po cichu nie istniała i **żadne powiadomienie nie
powstawało, bez jednego błędu w konsoli**. Nowa nazwa: `dodajPowiadomienie()`.
W jednym pliku na 4000 linii sprawdzaj nazwę, zanim ją zajmiesz.

## Audyt

Zadanie: `utworzylKto` / `utworzono`, `przypisalKto`, `zmienilKto` / `zmieniono`.
Zgłoszenie: `zglosilWorkerId` / `zgloszono`, `zaplanowalKto` / `zaplanowano`,
`rozpatrzylKto` / `rozpatrzono`.

## Zakładanie konta pracownikowi

Wymaga klucza `service_role`, którego **nigdy** nie wolno wpuścić do przeglądarki. Robi to
funkcja serwerowa `admin-uzytkownicy` (akcja `dodaj-pracownika`), która **sama sprawdza**,
czy woła ją administrator — przeglądarce w tej sprawie nie wolno wierzyć.

## Do wdrożenia przez użytkownika

| krok | plik / miejsce | stan |
|---|---|---|
| tabela zgłoszeń + RLS | `schema_zgloszenia.sql` → Supabase SQL Editor | **niewdrożone** |
| powiązania kont pracowników | `schema_pracownicy.sql` | **niewdrożone** |
| funkcja zakładania kont | `supabase/functions/admin-uzytkownicy` | **niewdrożone** |
| wyłączenie rejestracji | Supabase → Auth → Enable Sign Ups | do zrobienia |

Dopóki pierwsze trzy nie są wdrożone: moduły Pracownicy i Do zrobienia działają lokalnie,
„Załóż konto" i „Pobierz z telefonów" powiedzą wprost, czego brakuje.

## Sprawdzone puppeteerem (oba przepływy z §30)

| krok | wynik |
|---|---|
| dodanie pracownika | aktywny, `EMPLOYEE`, uprawnienia = `todoDodaje` |
| pojawienie się w Grafiku | 1 wiersz — **bez drugiego kroku** |
| nadanie „zarządza Grafikiem" | `zarzadzaGrafikiem` false → true |
| formularz polowy | pole uprawne jest, priorytetu nie ma |
| zapis zadania | audyt zapisany, powiadomienie „Nowe zadanie" |
| zmiana godziny | powiadomienie `zmiana` |
| zmiana samej uwagi | **brak** nowego powiadomienia |
| konflikt pracownika 10:00–14:00 z 09:00–15:00 | wykryty |
| zgłoszenie warsztatowe | `NEW`, licznik w menu = 1 |
| ZAPLANUJ | formularz warsztatowy, nazwa i priorytet przeniesione, **bez pola uprawnego** |
| po zapisaniu | `PLANNED`, powiązane, zgłoszenie **zostało** |
| status maszyny | zadanie warsztatowe → `warsztat`, polowe → `pracuje`, ręczna awaria → `awaria` |
| dezaktywacja | 0 wierszy w Grafiku, 2 zadania dalej w danych |
| błędy JS | brak |

# M-FarmX — Logowanie (dostęp)

Dokument planu funkcji logowania. Aktualizować przy zmianach.

## Cel
Zabezpieczyć dostęp do danych gospodarstwa (pola, flota, finanse, bydło) ekranem logowania.
Docelowo: konta użytkowników, role, wspólny dostęp wielu osób.

## Etap 1 — lokalna bramka (TERAZ)
Apka jest **single-file HTML offline**, więc na tym etapie logowanie jest **lokalne**:
- Konto (login + hasło) tworzone przy pierwszym uruchomieniu, zapisane w `localStorage` tej przeglądarki.
- Kolejne wejścia wymagają hasła. Opcja **„Zapamiętaj mnie"** trzyma sesję do wylogowania.
- Wylogowanie z górnego paska (ikona wyjścia).

⚠️ **To NIE jest silne zabezpieczenie.** Hasło jest tylko haszowane prostą funkcją i trzymane lokalnie —
chroni przed przypadkowym wglądem, ale nie przed kimś z dostępem do plików przeglądarki.
Prawdziwe uwierzytelnianie (serwer, szyfrowanie, reset hasła) dochodzi w Etapie 2.

## Etap 2 — konta serwerowe (PÓŹNIEJ)
Gdy przejdziemy na wersję serwerową (jak inne projekty: Supabase/VPS):
- Prawdziwe konta, hasła haszowane po stronie serwera, sesje/tokeny.
- Role: właściciel / pracownik / księgowość — różny zakres modułów.
- Reset hasła mailem, zaproszenia, wspólny dostęp telefon↔komputer.

## Model danych (Etap 1)
```
localStorage 'mfarmx.auth'    = { user, salt, hash, created }   // konto (osobno od danych gospodarstwa)
localStorage 'mfarmx.session' = <token>                         // sesja „zapamiętaj mnie"
sessionStorage 'mfarmx.session' = <token>                       // sesja bez zapamiętania (do zamknięcia karty)
```
Dane gospodarstwa dalej pod kluczem `zagon.v1` — **eksport/Kopia NIE zawiera hasła** (auth trzymany osobno).

## Przepływ (Etap 1)
1. Brak konta → ekran **„Utwórz konto administratora"** (login + hasło + powtórz) → zapis → wejście.
2. Jest konto, brak sesji → ekran **„Zaloguj się"** (login + hasło + „Zapamiętaj mnie").
3. Poprawne dane → sesja + wejście do apki (Pulpit).
4. **Wyloguj** (ikona w navbarze) → kasuje sesję → wraca ekran logowania.

## TODO / dalej
- „Zmień hasło" w apce.
- Odzyskiwanie dostępu (na razie: usunięcie `mfarmx.auth` = reset konta, bez utraty danych gospodarstwa).
- PIN zamiast hasła na telefonie (szybsze wejście w polu).
- Etap 2: przenieść na serwer (patrz `project_self_host_vps` w pamięci).

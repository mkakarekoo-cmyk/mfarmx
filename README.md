# M-FarmX

System zarządzania gospodarstwem rolnym (pola, flota, finanse, bydło) — jednoplikowa aplikacja webowa,
działająca offline, z danymi w przeglądarce (`localStorage`).

**Live:** _(uzupełnić po podpięciu domeny)_ · deploy: Vercel (statyczny hosting z tego repo).

## Moduły
- 🌾 **Pola** — płodozmian, zabiegi ŚOR, plony, mapa satelitarna z obrysem działek (auto-hektary).
- 🚜 **Flota** — maszyny, przeglądy/oleje, motogodziny (mth), koszty serwisu.
- 💰 **Finanse** — koszty i przychody miesiąc po miesiącu, kategorie, saldo.
- 🐄 **Bydło** — stado, inseminacje, wycielenia (auto termin ~283 dni), stan.

## Technologia
- Jeden plik `index.html` (HTML + CSS + JS, bez frameworka).
- Mapa: Leaflet + zdjęcia satelitarne Esri (bez klucza API). Font Roboto (Google Fonts + fallback).
- Wygląd: styl John Deere Operations Center (enterprise/flat).
- Dane: `localStorage` (`zagon.v1`), kopia/wczytaj przez eksport JSON.
- Logowanie: lokalna bramka (Etap 1) — patrz `LOGOWANIE.md`.

> ⚠️ Etap 1: dane trzymane są w przeglądarce (osobno na każdym urządzeniu, bez synchronizacji),
> a logowanie działa po stronie klienta (nie jest silnym zabezpieczeniem). Konta serwerowe + synchronizacja
> to Etap 2 (backend).

## Uruchomienie lokalne
Otwórz `index.html` w przeglądarce (dwuklik). Nie wymaga instalacji; internet potrzebny tylko do mapy.

## Deploy (Vercel)
Repo podpięte do projektu Vercel — każdy push do `main` publikuje statyczną apkę.
Konfiguracja w `vercel.json`. Dokumentacja projektu: `CLAUDE.md`.

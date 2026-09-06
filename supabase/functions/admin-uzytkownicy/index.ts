// Funkcja serwerowa: zarządzanie kontami M-FarmX (lista / dodaj / zmień hasło / usuń).
//
// PO CO ISTNIEJE: zakładanie kont wymaga klucza SERWISOWEGO (service_role), który daje pełny
// dostęp do bazy z pominięciem RLS. Taki klucz NIE MOŻE trafić do przeglądarki — każdy mógłby
// go odczytać ze źródła strony i przejąć wszystkie dane. Dlatego panel w apce woła tę funkcję,
// a klucz zostaje wyłącznie tutaj, po stronie serwera.
//
// 🔑 KTO JEST ADMINEM decyduje SERWER, nie przeglądarka. Aplikacja ukrywa panel przed innymi,
// ale to tylko wygoda — gdyby ktoś wywołał funkcję ręcznie, i tak odbije się o ten warunek.
// Lista adresów w zmiennej ADMIN_EMAILS (rozdzielone przecinkami).
//
// ⚠️ Konta zakładamy z `email_confirm: true` — czyli AKTYWNE OD RAZU, bez maila potwierdzającego.
// To celowe: domyślny SMTP Supabase jest mocno limitowany, a Site URL bywał nieustawiony, więc
// link z maila prowadziłby donikąd. Hasło ustala administrator i przekazuje je użytkownikowi.
//
// WDROŻENIE (panel Supabase → Edge Functions → Deploy a new function):
//   nazwa: admin-uzytkownicy · wklej ten plik
//   Secrets (Edge Functions → Secrets):
//     ADMIN_EMAILS = m.kakarekoo@gmail.com
//   (SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY Supabase podstawia sam)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const URL_BAZY = Deno.env.get('SUPABASE_URL')!;
const KLUCZ_SERWISOWY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ADMINI = (Deno.env.get('ADMIN_EMAILS') ?? '')
  .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const odpowiedz = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const admin = createClient(URL_BAZY, KLUCZ_SERWISOWY, { auth: { persistSession: false } });

  // ── Kto woła? Token z nagłówka sprawdzamy po stronie serwera. ──────────────
  const naglowek = req.headers.get('Authorization') ?? '';
  const token = naglowek.replace(/^Bearer\s+/i, '');
  if (!token) return odpowiedz({ error: 'Brak tokenu — zaloguj się ponownie.' }, 401);

  const { data: kto, error: bladTokenu } = await admin.auth.getUser(token);
  if (bladTokenu || !kto?.user) return odpowiedz({ error: 'Sesja wygasła — zaloguj się ponownie.' }, 401);

  const email = (kto.user.email ?? '').toLowerCase();
  if (!ADMINI.includes(email)) {
    // Świadomie NIE mówimy, czego brakuje — komu nie wolno, ten nie musi wiedzieć, jak to obejść.
    return odpowiedz({ error: 'Brak uprawnień.' }, 403);
  }

  let ciało: Record<string, unknown>;
  try { ciało = await req.json(); } catch { return odpowiedz({ error: 'Nieprawidłowe żądanie.' }, 400); }

  const akcja = String(ciało.akcja ?? '');

  try {
    // ── LISTA KONT ───────────────────────────────────────────────────────────
    if (akcja === 'lista') {
      const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
      if (error) throw error;
      return odpowiedz({
        uzytkownicy: data.users.map((u) => ({
          id: u.id,
          email: u.email,
          utworzono: u.created_at,
          ostatnie_logowanie: u.last_sign_in_at,
          potwierdzony: !!u.email_confirmed_at,
          admin: ADMINI.includes((u.email ?? '').toLowerCase()),
        })),
      });
    }

    // ── NOWE KONTO ───────────────────────────────────────────────────────────
    if (akcja === 'dodaj') {
      const nowyEmail = String(ciało.email ?? '').trim().toLowerCase();
      const haslo = String(ciało.haslo ?? '');
      if (!nowyEmail.includes('@')) return odpowiedz({ error: 'Podaj poprawny adres e-mail.' }, 400);
      if (haslo.length < 8) return odpowiedz({ error: 'Hasło musi mieć co najmniej 8 znaków.' }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email: nowyEmail,
        password: haslo,
        email_confirm: true,   // aktywne od razu — patrz uwaga na górze pliku
      });
      if (error) throw error;
      return odpowiedz({ ok: true, id: data.user?.id, email: data.user?.email });
    }

    // ── KONTO PRACOWNIKA ─────────────────────────────────────────────────────
    // Konto + powiązanie z gospodarstwem w jednym kroku. Rozdzielenie tego na dwa
    // wywołania kończyłoby się kontami bez dostępu, gdyby drugie padło.
    if (akcja === 'dodaj-pracownika') {
      const nowyEmail = String(ciało.email ?? '').trim().toLowerCase();
      const haslo = String(ciało.haslo ?? '');
      const imie = String(ciało.imie ?? '').trim();
      const workerId = String(ciało.workerId ?? '').trim();
      if (!nowyEmail.includes('@')) return odpowiedz({ error: 'Podaj poprawny adres e-mail.' }, 400);
      if (haslo.length < 8) return odpowiedz({ error: 'Hasło musi mieć co najmniej 8 znaków.' }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email: nowyEmail, password: haslo, email_confirm: true,
      });
      if (error) throw error;

      const nowyId = data.user!.id;
      const { error: bladLinku } = await admin.from('dostep_pracownika').upsert({
        pracownik_id: nowyId,
        wlasciciel_id: kto.user.id,     // gospodarstwo tego, kto zakłada konto
        imie, worker_id: workerId,
      });
      if (bladLinku) {
        // Konto bez powiązania jest bezużyteczne i myli — sprzątamy po sobie.
        await admin.auth.admin.deleteUser(nowyId);
        throw new Error('Konto nie zostało powiązane z gospodarstwem: ' + bladLinku.message);
      }
      return odpowiedz({ ok: true, id: nowyId, email: nowyEmail });
    }

    // ── ZMIANA HASŁA ─────────────────────────────────────────────────────────
    if (akcja === 'haslo') {
      const id = String(ciało.id ?? '');
      const haslo = String(ciało.haslo ?? '');
      if (!id) return odpowiedz({ error: 'Brak konta do zmiany.' }, 400);
      if (haslo.length < 8) return odpowiedz({ error: 'Hasło musi mieć co najmniej 8 znaków.' }, 400);

      const { error } = await admin.auth.admin.updateUserById(id, { password: haslo });
      if (error) throw error;
      return odpowiedz({ ok: true });
    }

    // ── USUNIĘCIE KONTA ──────────────────────────────────────────────────────
    if (akcja === 'usun') {
      const id = String(ciało.id ?? '');
      if (!id) return odpowiedz({ error: 'Brak konta do usunięcia.' }, 400);
      // ⚠️ Administrator nie może usunąć samego siebie — zostalibyśmy bez nikogo, kto zakłada konta,
      // a odzyskanie dostępu wymagałoby wtedy grzebania w panelu Supabase.
      if (id === kto.user.id) return odpowiedz({ error: 'Nie możesz usunąć własnego konta.' }, 400);

      // Dane gospodarstwa giną razem z kontem — kasujemy je jawnie, żeby nie zostawały sieroty
      // w `user_state` po użytkowniku, którego już nie ma.
      await admin.from('user_state').delete().eq('user_id', id);
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw error;
      return odpowiedz({ ok: true });
    }

    return odpowiedz({ error: 'Nieznana akcja.' }, 400);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // Najczęstszy przypadek nazywamy po ludzku — „duplicate key” nic nikomu nie mówi.
    if (/already been registered|duplicate/i.test(msg)) {
      return odpowiedz({ error: 'Konto z tym adresem już istnieje.' }, 400);
    }
    return odpowiedz({ error: msg }, 500);
  }
});

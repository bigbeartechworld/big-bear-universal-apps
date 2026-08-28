# SONOZZ

Self-hosted music studio & library manager (Astro + Turso). Demo: https://sonozz.briseteia.me

## English — Install notes

1. **Turso database is required.** Create a free DB at https://turso.tech and copy the database URL and auth token.
2. Set the environment variables before starting the container:
   - `TURSO_DATABASE_URL` (required)
   - `TURSO_AUTH_TOKEN` (required)
   - `AUTH_EMAIL` (default `admin@example.com`)
   - `AUTH_PASSWORD` (change from `changeme`)
   - `AUTH_SECRET` (long random string)
   - `AUTH_SECURE` (`0` for plain HTTP on the LAN, `1` behind HTTPS)
3. Open `http://<server-ip>:4321`. The public player is available at `/play` without login; `/login` is the studio (team only).
4. A Google Gemini API key can be added in-app after the first login for the AI features.

## Français — Notes d'installation

1. **Une base Turso est obligatoire.** Créez-la sur https://turso.tech puis récupérez l'URL et le token.
2. Renseignez les variables d'environnement avant le démarrage :
   - `TURSO_DATABASE_URL` (obligatoire)
   - `TURSO_AUTH_TOKEN` (obligatoire)
   - `AUTH_EMAIL` (défaut `admin@example.com`)
   - `AUTH_PASSWORD` (à changer, défaut `changeme`)
   - `AUTH_SECRET` (chaîne aléatoire longue)
   - `AUTH_SECURE` (`0` en HTTP sur le réseau local, `1` derrière HTTPS)
3. Accédez à `http://<ip-du-serveur>:4321`. Le lecteur public est sur `/play` (aucune connexion requise), `/login` est réservé au studio.
4. Une clé API Google Gemini peut être configurée dans l'application après la première connexion.

## Démo / Demo

https://sonozz.briseteia.me — page `/login` (bouton « Ouvrir le lecteur ») et lecteur public `/play`.

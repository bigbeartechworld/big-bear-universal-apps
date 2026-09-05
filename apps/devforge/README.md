# DevForge

Self-hosted PaaS platform (Git integration, Docker deployments, server management, AI agents / MCP).

## English — Install notes

1. Deploy the stack; the proxy exposes the UI on `http://<server-ip>:8080`.
2. Services: proxy, web (`bobdivx/devforge:web-4.1.3`), api (`bobdivx/devforge:4.1.3`), realtime, plus the internal network `big_bear_devforge_network`.
3. On first start, open the UI and create the initial admin account.
4. Docker socket access is required for deployments — keep the instance on a trusted network.

## Français — Notes d'installation

1. Déployez la stack ; le proxy expose l'interface sur `http://<ip-du-serveur>:8080`.
2. Services : proxy, web (`bobdivx/devforge:web-4.1.3`), api (`bobdivx/devforge:4.1.3`), realtime, et le réseau interne `big_bear_devforge_network`.
3. Au premier démarrage, ouvrez l'interface et créez le compte administrateur initial.
4. L'accès au socket Docker est nécessaire pour les déploiements — gardez l'instance sur un réseau de confiance.

## Notes

- Screenshots/thumbnail: no public demo instance is available yet; they will be added once a public URL exists.

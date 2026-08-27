# Service Dash

Turns an existing Uptime Kuma status page into a homelab dashboard: every
service's **local and public URL on one card**, beside live host CPU, RAM,
storage and network throughput from a bundled Netdata Agent.

Try it before installing: <https://cvaghela.github.io/service-dash/demo/>
(sign in as `test` / `Test`).

## Requires Uptime Kuma on the same host

Service Dash reads monitors from Uptime Kuma and does not install it. Leave Kuma
on port `3001`, or change `KUMA_PORT` and `KUMA_URL` to match.

## Local and public URLs come from monitor names

| Monitor in Uptime Kuma | Points at | Shows on the card as |
| --- | --- | --- |
| `Plex` | your public URL | **External** |
| `Plex local` | your LAN URL | **Local** |

They pair by name into a single card carrying both. `Plex (local)`,
`Plex - local` and `Plex.local` are read the same way. A service with one
monitor shows one address.

## Why it needs rootful Docker

The bundled Netdata Agent uses `pid: host`, `SYS_PTRACE`, `SYS_ADMIN` and
read-only mounts of the host root, `/proc` and `/sys`. That is what produces
real host metrics rather than the container's own, and rootless Docker cannot
grant it.

Nothing else in the stack is privileged. The Docker socket goes only to
[CetusGuard](https://github.com/hectorm/cetusguard), restricted to two
read-only network endpoints, and never to the dashboard.

## Platforms

Marked supported for **CasaOS, Portainer and Dockge**, which are Docker Compose
underneath. Runtipi, Cosmos and Umbrel are marked unsupported: they sandbox
containers in ways that cannot give the Netdata Agent host PID and host root,
so the app would install and then report the wrong machine.

- Source: <https://github.com/cvaghela/service-dash>
- Licence: GPL-3.0-or-later

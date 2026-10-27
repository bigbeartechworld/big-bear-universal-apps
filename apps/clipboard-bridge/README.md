# Clipboard Bridge

Self-hosted text, photo and file sharing between Windows, Android and Apple
Shortcuts, using a trusted LAN or private VPN. The standalone host adds browser
access, persistent history, grouped files and optional isolated accounts.

- Web/API: TCP `5088`, browser path `/`, health check `/health`.
- Preserve the `/data` volume for history, files and the persistent session key.
- Default auth settings are empty: configure the optional general web password
  and API token separately, or add isolated accounts. URL values remain readable;
  HTTP is unencrypted. Do not publish the port directly to the internet.
- Linux `amd64` / `arm64`; no database or privileged host integration required.
- The image does not implement LinuxServer.io's PUID/PGID initialization.

This is the universal source definition. Big Bear's converter adds CasaOS metadata
and maps the named volume to `/DATA/AppData/$AppID/data`. Other platform conversions
are not enabled in this initial proposal.

[Project](https://github.com/Mattboxx/Clipboard-Bridge) |
[Docker guide](https://github.com/Mattboxx/Clipboard-Bridge/blob/main/DOCKER.md) |
[Device setup](https://github.com/Mattboxx/Clipboard-Bridge/blob/main/GUIDE.md) |
[Support](https://github.com/Mattboxx/Clipboard-Bridge/issues)

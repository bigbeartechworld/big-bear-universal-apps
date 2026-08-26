# Big Bear Universal Apps

Single source of truth for Big Bear app definitions. Each store listing is a Universal App that converts to CasaOS, Portainer, Runtipi, Dockge, Cosmos, and Umbrel.

## Language

**Universal App**:
An app definition under `apps/<id>/` made of `app.json` plus a clean `docker-compose.yml`. This is what authors edit.
_Avoid_: CasaOS app, compose app, listing, package

**Converted artifact**:
Platform-specific output under `converted/` produced by `scripts/convert-to-platforms.sh`. Generated, gitignored, not authored.
_Avoid_: platform app, export

**PXE app**:
A Universal App that serves network boot (TFTP and usually a boot menu). It is not a DHCP server unless the compose explicitly runs one.
_Avoid_: PXEboot server (when used to mean "DHCP + TFTP + menu in one container")

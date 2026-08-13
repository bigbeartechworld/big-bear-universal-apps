#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO/scripts/convert-to-platforms.sh" --source-only 2>/dev/null || true

fail=0
assert_eq() { # $1=actual $2=expected $3=label
  if [[ "$1" != "$2" ]]; then echo "FAIL: $3 — got '$1' want '$2'"; fail=1; else echo "ok: $3"; fi
}

# --- unit: resolver over synthetic compose fixtures ---
UNIT_DIR="$(mktemp -d)"

cat > "$UNIT_DIR/single.yml" <<'YAML'
services:
  app:
    image: louislam/uptime-kuma:2@sha256:aaaa
  db:
    image: postgres:14-alpine@sha256:bbbb
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/single.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0")" \
  "louislam/uptime-kuma:2@sha256:aaaa" "single match verbatim"

cat > "$UNIT_DIR/multisame.yml" <<'YAML'
services:
  app:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
  worker:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/multisame.yml" "ghcr.io/goauthentik/server" testapp "ghcr.io/goauthentik/server:9.9")" \
  "ghcr.io/goauthentik/server:2026.2.2@sha256:cccc" "multi identical verbatim"

cat > "$UNIT_DIR/multidiff.yml" <<'YAML'
services:
  app:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
  worker:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:dddd
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/multidiff.yml" "ghcr.io/goauthentik/server" testapp "ghcr.io/goauthentik/server:9.9" 2>/dev/null)" \
  "ghcr.io/goauthentik/server:9.9" "multi differing falls back"

cat > "$UNIT_DIR/nomatch.yml" <<'YAML'
services:
  app:
    image: linuxserver/bookstack:1@sha256:eeee
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>/dev/null)" \
  "lscr.io/linuxserver/bookstack:26.05" "no match falls back"

cat > "$UNIT_DIR/registryport.yml" <<'YAML'
services:
  app:
    image: registry:5000/foo@sha256:ffff
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/registryport.yml" "registry:5000/foo" testapp "registry:5000/foo:1.0")" \
  "registry:5000/foo@sha256:ffff" "registry port not mangled"

cat > "$UNIT_DIR/digestnotag.yml" <<'YAML'
services:
  app:
    image: alpine/socat@sha256:gggg
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/digestnotag.yml" "alpine/socat" testapp "alpine/socat:1.0")" \
  "alpine/socat@sha256:gggg" "digest without tag normalizes to bare repo"

cat > "$UNIT_DIR/buildonly.yml" <<'YAML'
services:
  builder:
    build: .
  app:
    image: louislam/uptime-kuma:2@sha256:aaaa
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/buildonly.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0")" \
  "louislam/uptime-kuma:2@sha256:aaaa" "build-only service skipped"

cat > "$UNIT_DIR/unpinned.yml" <<'YAML'
services:
  app:
    image: ghcr.io/imagegenius/immich:2.0.0-alpine
YAML
UNPINNED_OUT="$(resolve_runtipi_main_image "$UNIT_DIR/unpinned.yml" "ghcr.io/imagegenius/immich" immich-aio-alpine "ghcr.io/imagegenius/immich:2.0.0")"
assert_eq "$UNPINNED_OUT" "ghcr.io/imagegenius/immich:2.0.0-alpine" "unpinned match verbatim"

WARN_ON_MATCH="$(resolve_runtipi_main_image "$UNIT_DIR/unpinned.yml" "ghcr.io/imagegenius/immich" immich-aio-alpine "x:1" 2>&1 | grep -c 'WARNING' || true)"
assert_eq "$WARN_ON_MATCH" "0" "no warning on successful match"

WARN_ON_FALLBACK="$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>&1 | grep -c 'WARNING' || true)"
assert_eq "$WARN_ON_FALLBACK" "1" "one warning on fallback"

STDOUT_CLEAN="$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$STDOUT_CLEAN" "1" "fallback stdout is exactly one line"

VERBOSE_CLEAN="$(VERBOSE=true resolve_runtipi_main_image "$UNIT_DIR/single.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$VERBOSE_CLEAN" "1" "VERBOSE stdout is exactly one line"

MISSING_FILE="$(resolve_runtipi_main_image "$UNIT_DIR/does-not-exist.yml" "foo/bar" testapp "foo/bar:1.0" 2>/dev/null)"
assert_eq "$MISSING_FILE" "foo/bar:1.0" "missing compose file falls back"

rm -rf "$UNIT_DIR"

exit $fail

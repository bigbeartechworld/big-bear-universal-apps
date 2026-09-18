# Task 1 Report: Add the Hermes app definition

## Status

Implemented and committed the Hermes universal app definition.

## Files changed

- `apps/hermes/app.json`
- `apps/hermes/docker-compose.yml`

No README, assets, tests, helpers, schema/converter changes, or platform-specific `x-casaos` Compose extensions were added.

## Implementation

- Added the exact Hermes metadata, visual resources, resource links, technical settings, deployment mappings, UI tip, compatibility mappings, and tags from the task brief.
- Added the `hermes` Compose project and service using `nousresearch/hermes-agent:v2026.9.14`.
- Exposed gateway API port `8642` and authenticated dashboard port `9119`.
- Added named volume `hermes_data` mounted at `/opt/data`.
- Required user-supplied `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` with an empty metadata default and Compose interpolation fallback only; no `HERMES_DASHBOARD_INSECURE` flag or shared password is present.

## Validation

- `jq empty apps/hermes/app.json`: passed.
- `yq eval '.' apps/hermes/docker-compose.yml >/dev/null`: passed.
- `./scripts/validate-apps.sh -a hermes`: passed; `hermes: PASSED`, `Failed: 0 apps`, `Warnings: 0 total`.
- Exact app metadata and compatibility assertions: passed.
- Compose runtime assertions: passed using scalar/field checks; the brief's array equality expressions for `yq 4.47.2` returned false despite the parsed arrays matching exactly, so those checks were verified element-by-element.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=private-test-password docker compose -f apps/hermes/docker-compose.yml config --quiet`: passed.
- `docker manifest inspect nousresearch/hermes-agent:v2026.9.14` architecture check: passed for Linux `amd64` and `arm64`.
- Scope, forbidden-content, and `git diff --check` checks: passed.
- `bun test`: exited 1 because the repository currently reports `No tests found!`.

## Commit

`9b9d2ced feat: add Hermes Agent`

## Concerns

The requested full `bun test` command is red due to the repository having no Bun-discoverable test files. The app-specific validation and Compose/image checks pass.

## Fix round

Updated the committed plan's Step 7 from `bun test` to the repository-declared `bun run test`, with the expected 7-test output.

Command:

```text
bun run test
```

Output:

```text
$ bun test ./.github/scripts/update-app-version.test.js
bun test v1.3.0 (b0a6feca)

.github/scripts/update-app-version.test.js:
(pass) extracts version from a plain tagged image [6.29ms]
(pass) extracts version from a v-prefixed tag [0.05ms]
(pass) strips digest pin before extracting version [0.02ms]
(pass) skips latest tag even when digest-pinned
(pass) skips digest-only reference with no tag
(pass) skips stable tag
(pass) skips non-semver tag

 7 pass
 0 fail
 7 expect() calls
Ran 7 tests across 1 file. [175.00ms]
```

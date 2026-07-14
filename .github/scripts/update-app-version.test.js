const { test, expect } = require('bun:test');
const { extractVersion } = require('./update-app-version.js');

test('extracts version from a plain tagged image', () => {
  expect(extractVersion('budibase/budibase:3.22.4')).toBe('3.22.4');
});

test('extracts version from a v-prefixed tag', () => {
  expect(extractVersion('amir20/dozzle:v10.6.9')).toBe('v10.6.9');
});

test('strips digest pin before extracting version', () => {
  expect(
    extractVersion(
      'baserow/baserow:2.3.1@sha256:496889c4fe22ee6b632698c3c74f7ccaee734c8002b5ebc8d194c5fcacffc98a'
    )
  ).toBe('2.3.1');
});

test('skips latest tag even when digest-pinned', () => {
  expect(
    extractVersion('ente/server:latest@sha256:77f2a5244e8e515e66c3d737ed2ed89907e440d51d22435d7cf55e9c33623632')
  ).toBe(null);
});

test('skips digest-only reference with no tag', () => {
  expect(
    extractVersion('ghcr.io/org/app@sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789')
  ).toBe(null);
});

test('skips stable tag', () => {
  expect(extractVersion('someorg/someapp:stable')).toBe(null);
});

test('skips non-semver tag', () => {
  expect(extractVersion('someorg/someapp:nightly')).toBe(null);
});

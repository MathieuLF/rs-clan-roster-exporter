const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'docs/assets/site.js'), 'utf8');
async function render(fetch) {
  const nodes = new Map();
  const get = selector => {
    if (!nodes.has(selector)) nodes.set(selector, { textContent: '', hidden: false, href: '', querySelector: get });
    return nodes.get(selector);
  };
  vm.runInNewContext(source, { document: { querySelector: get }, fetch });
  await new Promise(resolve => setImmediate(resolve));
  return get;
}
test('local HTML references and anchors exist', () => {
  const html = fs.readFileSync(path.join(root, 'docs/index.html'), 'utf8');
  for (const [, ref] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (/^https?:/.test(ref)) continue;
    if (ref.startsWith('#')) assert.ok(html.includes(`id="${ref.slice(1)}"`), ref);
    else assert.ok(fs.existsSync(path.join(root, 'docs', ref)), ref);
  }
  assert.match(html, /<html lang="en">/);
  assert.match(fs.readFileSync(path.join(root, 'docs/legal-notice.md'), 'utf8'), /Google Analytics/);
});
test('network failure uses repository fallback', async () => {
  const get = await render(async () => { throw Error('offline'); });
  assert.equal(get('#release-title').textContent, 'Release not verified');
  assert.match(get('[data-primary-download]').href, /raw\.githubusercontent\.com/);
});
test('HTTP error uses fallback', async () => {
  const get = await render(async () => ({ ok: false }));
  assert.equal(get('#release-title').textContent, 'Release not verified');
});
test('invalid JSON uses fallback instead of leaving a pending card', async () => {
  const get = await render(async () => ({ ok: true, json: async () => { throw Error('invalid JSON'); } }));
  assert.equal(get('#release-title').textContent, 'Release not verified');
});
test('no stable release has an explicit state', async () => {
  const get = await render(async () => ({ ok: true, json: async () => [{ draft: true }, { prerelease: true }] }));
  assert.equal(get('#release-title').textContent, 'No release published');
});
test('stable release selects its script and matching checksum', async () => {
  const sha = 'a'.repeat(64);
  const get = await render(async () => ({ ok: true, json: async () => [{ name: 'Fixture release', published_at: '2026-07-09', assets: [{ name: 'script.ps1', browser_download_url: 'https://example.test/script.ps1', digest: `sha256:${sha}` }] }] }));
  assert.equal(get('#release-title').textContent, 'Fixture release');
  assert.equal(get('[data-primary-download]').href, 'https://example.test/script.ps1');
  assert.equal(get('[data-release-sha]').textContent, sha.toUpperCase());
});
test('checksum file is used when asset digest is absent', async () => {
  const sha = 'b'.repeat(64);
  const get = await render(async url => url.endsWith('.sha256')
    ? { ok: true, text: async () => `${sha}  fixture.ps1` }
    : { ok: true, json: async () => [{ assets: [{ name: 'fixture.ps1', browser_download_url: 'https://example.test/fixture.ps1' }, { name: 'fixture.ps1.sha256', browser_download_url: 'https://example.test/fixture.ps1.sha256' }] }] });
  assert.equal(get('[data-release-sha]').textContent, sha.toUpperCase());
});
test('release with no assets links to its release page', async () => {
  const get = await render(async () => ({ ok: true, json: async () => [{ html_url: 'https://example.test/release', assets: [] }] }));
  assert.equal(get('[data-primary-download]').href, 'https://example.test/release');
});

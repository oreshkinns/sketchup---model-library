const {test} = require('node:test');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const {pathToFileURL} = require('node:url');
const path = require('node:path');

test('offline React views receive SketchUp reports and render subsequent updates', async () => {
  const browser = await chromium.launch({headless:true});
  try {
    const page = await browser.newPage();
    const network = [], errors = [];
    page.on('request', request => {if (/^https?:/.test(request.url())) network.push(request.url());});
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.reactRenderers = [];
      window.reactCommits = 0;
      window.__REACT_DEVTOOLS_GLOBAL_HOOK__ = {
        supportsFiber: true,
        inject(renderer) {window.reactRenderers.push(renderer.version);return 1;},
        onCommitFiberRoot() {window.reactCommits++;},
        onCommitFiberUnmount() {},
      };
      window.sketchup = new Proxy({}, {get: () => () => {}});
    });
    await page.goto(pathToFileURL(process.env.MAF_UI_FILE || path.join(__dirname, '../preview.html')).href);
    await page.waitForFunction(() => window.MAF);
    const report = {summary:{}, models:[], hierarchy:[], duplicates:[], catalog:[], sections:[], settings:{}, cleanup:{}};
    await page.evaluate(data => MAF.receive({data, report_stale:false}), report);
    await page.locator('.nav [data-page="catalog"]').click();
    const initial = await page.evaluate(() => reactCommits);
    assert.ok((await page.evaluate(() => reactRenderers)).some(version => /^18\./.test(version)), 'must mount real React');
    const card = {id:'react-local',scope:'personal',name:'React & <bench> "offline"',category:'Скамейки'};
    await page.evaluate(card => MAF.receive({catalog_update:{catalog:[card]}}), card);
    await page.locator('[data-card-key="personal:react-local"]').waitFor();
    assert.match(await page.locator('[data-card-key="personal:react-local"]').innerText(), /React & <bench> "offline"/);
    assert.equal(await page.locator('[data-card-key="personal:react-local"] bench').count(), 0, 'model names stay text');
    assert.ok(await page.evaluate(initial => reactCommits > initial, initial), 'data updates must commit through React');
    await page.evaluate(card => MAF.receive({catalog_update:{catalog:[{...card,name:'Updated component'}]}}), card);
    assert.match(await page.locator('[data-card-key="personal:react-local"]').innerText(), /Updated component/);
    await page.evaluate(() => MAF.receive({catalog_update:{catalog:[]}}));
    assert.equal(await page.locator('[data-card-key="personal:react-local"]').count(), 0);
    assert.deepEqual(network, [], 'installed UI must not fetch React, fonts or other runtime dependencies');
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});

test('preview jobs preserve images, scope identity, cancellation and retry', async () => {
  const browser = await chromium.launch({headless:true});
  try {
    const page = await browser.newPage();
    await page.addInitScript(() => { window.calls=[]; window.sketchup=new Proxy({}, {get:(_,name)=>(...args)=>window.calls.push([name,...args])}); });
    await page.goto(pathToFileURL(path.join(__dirname,'../preview.html')).href);
    await page.waitForFunction(() => window.MAF);
    await page.evaluate(() => MAF.receive({catalog_update:{catalog:[{id:'same',scope:'personal',name:'Bench',category:'Other',thumbnail:'data:image/png;base64,old'}]}}));
    const card=page.locator('[data-card-key="personal:same"]');
    await card.waitFor();
    const emit=job=>page.evaluate(job=>MAF.receive({preview_event:job}),job);
    await emit({scope:'personal',id:'same',request_id:'one',state:'queued'});
    await page.waitForFunction(() => document.querySelector('[data-thumb-auto]').textContent.includes('Отменить'));
    await card.locator('[data-thumb-auto]').evaluate(button => button.click());
    assert.deepEqual(await page.evaluate(()=>calls.at(-1)),['cancel_preview','one']);
    await emit({scope:'personal',id:'same',request_id:'two',state:'queued'});
    await emit({scope:'personal',id:'same',request_id:'one',state:'failed',error:'stale'});
    assert.match(await card.textContent(),/Отменить превью/);
    await emit({scope:'shared',id:'same',request_id:'other',state:'failed',error:'wrong scope'});
    assert.match(await card.textContent(),/Отменить превью/);
    await emit({scope:'personal',id:'same',request_id:'two',state:'failed',error:'Renderer failed'});
    assert.match(await card.textContent(),/Повторить превью/);
    assert.match(await card.textContent(),/Renderer failed/);
    await card.locator('[data-thumb-auto]').evaluate(button => button.click());
    assert.deepEqual(await page.evaluate(()=>calls.at(-1)),['regenerate_thumbnail','personal:same']);
  } finally { await browser.close(); }
});

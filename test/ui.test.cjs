const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const {pathToFileURL} = require('node:url');
const path = require('node:path');
let browser;
before(async () => { browser = await chromium.launch({headless:true});
});
after(async () => { await browser?.close();
});
const row = (id, extra={}) => ({id:`definition:${id}`,definition_ids:[id],name:`Модель ${id}`,kind:'component',instances:1,definitions:1,category:'Скамейки',is_maf:true,recognition_source:'manual',recognition_reason:'manual_confirmed',paths:[`Двор / ${id}`,`Парк / ${id}`],...extra});
const node = (id, definition, extra={}) => ({id,definition_id:definition,row_id:`definition:${definition}`,name:`Модель ${definition}`,kind:'component',instances:1,is_maf:true,children:[],...extra});
function fixture(){return {
summary:{all_component_instances:10,all_component_definitions:4,maf_instances:8,maf_definitions:4},
models:[row('1',{instances:3,recognized_catalog:true,catalog_id:'same',recognized_catalog_scope:'personal',recognition_warnings:['catalog_geometry_drift']}),row('2',{instances:2,recognized_catalog:true,catalog_id:'same',recognized_catalog_scope:'personal'}),row('3',{is_maf:false,recognition_source:'candidate',recognition_reason:'component_flags',recognition_warnings:['catalog_match_ambiguous'],names:['Кандидат','Имя экземпляра'],tags:['парк'],metadata:{bbox_mm:[1800,500,900],faces_count:12,edges_count:24,materials_count:2,nesting_depth:3,behavior_flags:{dynamic:true,glued:false},extension_attributes:{category:'Скамейки'}}}),row('4',{kind:'group',instances:2}),row('5',{instances:1})],
hierarchy:[node('yard','container',{row_id:null,name:'Двор',kind:'group',is_maf:false,has_maf_descendant:true,instances:2,children:[node('yard/1','1',{instances:2}),node('yard/3','3',{is_maf:false})]}),node('park','4',{name:'Парк',kind:'group',instances:2,children:[node('park/1','1'),node('park/5','5')]})],
catalog:[{id:'same',scope:'personal',name:'Скамья',category:'Скамейки',project_placements:5,version:2,sha256:'a'.repeat(64),bbox_mm:[1800,500,900],faces_count:12,edges_count:24,materials_count:2,file_size_bytes:2048,recognition_source:'manual'},{id:'same',scope:'shared',name:'Общая скамья',project_placements:0}],sections:['Скамейки'],settings:{},cleanup:{},catalog_sync_errors:[{row_id:'definition:3',code:'catalog_sync_failed',message:'Нет доступа к папке'}]
};
}
async function open(t, data=fixture(), demo=false){const page=await browser.newPage({viewport:{width:1440,height:1100}});
page.setDefaultTimeout(1800);
t.after(()=>page.close());
const errors=[];
page.on('pageerror',e=>errors.push(e.message));
t.after(()=>assert.deepEqual(errors,[]));
if(!demo)await page.addInitScript(()=>{window.calls=[];
window.sketchup=new Proxy({},{get:(_,name)=>(...args)=>window.calls.push([name,...args])});
});
await page.goto(pathToFileURL(process.env.MAF_UI_FILE||path.join(__dirname,'../preview.html')).href);
if(!demo)await page.evaluate(data=>MAF.receive({data}),data);
return page;
}
async function calls(page,name){return page.evaluate(name=>window.calls.filter(x=>x[0]===name),name);
}
test('library is first navigation and initial page, with separate add controls',async t=>{
const p=await open(t);
assert.equal(await p.locator('.nav [data-page]').first().getAttribute('data-page'),'catalog');
assert.equal(await p.locator('#catalog').isVisible(),true);
assert.equal(await p.locator('#page-title').textContent(),'Библиотека МАФ');
assert.equal(await p.locator('#add-selected').textContent(),'Добавить выделенный в SketchUp');
assert.match(await p.locator('#import').textContent(),/Добавить файл .skp/);
});
test('hierarchy preserves branch counts, collapse and MAF ancestor paths',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
assert.equal(await p.locator('[data-node="yard/1"] [data-branch-count]').textContent(),'2');
assert.equal(await p.locator('[data-node="park/1"] [data-branch-count]').textContent(),'1');
assert.equal(await p.locator('[data-node="yard"].model-row').count(),0);
await p.locator('[data-toggle-node="yard"]').click();
assert.equal(await p.locator('[data-node="yard/1"]').count(),0);
assert.equal(await p.locator('[data-node="park/1"]').count(),1);
await p.locator('[data-toggle-node="yard"]').click();
await p.locator('#maf-filter').check();
assert.equal(await p.locator('[data-node="yard"]').count(),1);
assert.equal(await p.locator('[data-node="yard/3"]').count(),0);
await p.locator('[data-node="park/1"]').click();
assert.equal(await p.locator('[data-node="park/1"]').getAttribute('aria-selected'),'true');
assert.equal(await p.locator('[data-node="yard/1"]').getAttribute('aria-selected'),'false');
});
test('component and MAF counters include manually confirmed unlinked definitions',async t=>{
const p=await open(t);
assert.match(await p.locator('#all-component-count').textContent(),/10 размещений.*4 определений/);
assert.match(await p.locator('#maf-count').textContent(),/8 размещений.*4 определений/);
await p.locator('.nav [data-page="overview"]').click();
assert.match(await p.locator('[data-node="park/5"]').textContent(),/МАФ/);
});
test('cards show summed scope-specific counts, zero, metadata and marker-only stale',async t=>{
const p=await open(t);
const card=p.locator('[data-card-key="personal:same"]');
assert.equal(await card.locator('[data-placement-count]').textContent(),'В текущем проекте: 5 размещений');
assert.equal(await p.locator('[data-card-key="shared:same"] [data-placement-count]').textContent(),'В текущем проекте: 0 размещений');
assert.match(await card.textContent(),/24 рёбер/);
assert.match(await card.textContent(),/2 материалов/);
assert.match(await card.textContent(),/Версия: 2/);
assert.match(await card.textContent(),/a{64}/);
await p.evaluate(()=>MAF.receive({catalog_update:{catalog:[{id:'same',scope:'personal',name:'Новое имя'}]}}));
assert.equal(await card.locator('[data-placement-count]').textContent(),'В текущем проекте: 5 размещений');
await p.evaluate(()=>MAF.receive({report_stale:true}));
assert.equal(await card.locator('[data-placement-count]').textContent(),'В текущем проекте: —');
await p.evaluate(data=>MAF.receive({data}),fixture());
assert.equal(await card.locator('[data-placement-count]').textContent(),'В текущем проекте: 5 размещений');
});
test('candidate parameters, reasons and warnings are separate, decisions preview global scope',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
const candidate=p.locator('[data-candidate="definition:3"]');
assert.match(await candidate.textContent(),/1800 × 500 × 900/);
assert.match(await candidate.textContent(),/12 граней.*24 рёбер.*2 материалов/s);
assert.match(await candidate.textContent(),/Вложенность: 3/);
assert.match(await candidate.textContent(),/Имя экземпляра/);
assert.match(await candidate.textContent(),/dynamic: да/);
assert.match(await candidate.locator('[data-reason]').textContent(),/особенност/i);
assert.match(await candidate.locator('[data-warnings]').textContent(),/Несколько точных карточек/);
await candidate.locator('[data-decision="confirmed"]').click();
assert.match(await p.locator('#action-scope').textContent(),/со всеми размещениями.*Двор \/ 3.*Парк \/ 3/s);
await p.locator('#confirm').click();
assert.deepEqual((await calls(p,'set_maf_decision')).at(-1),['set_maf_decision',['definition:3'],'confirmed']);
});
test('global rename/delete scope previews all paths; replacement retains server preview gate',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
await p.locator('[data-node="yard/1"]').click();
await p.locator('#selected-menu').click();
await p.locator('[data-action="delete"]').click();
assert.match(await p.locator('#action-scope').textContent(),/со всеми размещениями.*3.*Двор \/ 1.*Парк \/ 1/s);
await p.locator('#cancel').click();
await p.locator('#replace-selected').click();
assert.equal(await p.locator('#confirm').isDisabled(),true);
const c=(await calls(p,'preview_replace_rows')).at(-1);
await p.evaluate(token=>MAF.receive({replacement_preview:{token,plan:{sources:['Модель 1'],target:'Эталон',entities:3,placements:3,paths:['Двор','Парк'],blockers:[]}}}),c[3]);
assert.equal(await p.locator('#confirm').isEnabled(),true);
});
test('direct selection needs no scan; existing card opens; explicit copy uses separate callback',async t=>{
const p=await open(t,{models:[],catalog:fixture().catalog,sections:['Скамейки'],summary:{}});
await p.locator('#add-selected').click();
assert.deepEqual((await calls(p,'add_selected_to_library')).at(-1),['add_selected_to_library','personal']);
assert.equal((await calls(p,'scan')).length,0);
await p.locator('#copy-selected').click();
assert.match(await p.locator('#modal-description').textContent(),/Исходная карточка останется/);
await p.locator('#modal-input').fill('Копия');
await p.locator('#modal-select').selectOption('shared');
await p.locator('#confirm').click();
assert.deepEqual((await calls(p,'copy_selected_to_library')).at(-1),['copy_selected_to_library','shared','Копия','Скамейки']);
await p.evaluate(()=>MAF.receive({open_catalog_id:'same',open_catalog_scope:'shared'}));
assert.equal(await p.locator('[data-card-key="shared:same"]').getAttribute('tabindex'),'0');
assert.equal(await p.locator('[data-card-key="shared:same"]').evaluate(el=>el===document.activeElement),true);
});
test('sync failure retry and explicit drift version update, placement preserved',async t=>{
const p=await open(t);
assert.match(await p.locator('#catalog-sync-errors').textContent(),/Нет доступа к папке/);
await p.locator('#retry-catalog-sync').click();
assert.equal((await calls(p,'retry_catalog_sync')).length,1);
await p.locator('[data-card-key="personal:same"] [data-update-version]').click();
assert.match(await p.locator('#modal-description').textContent(),/новую версию/);
await p.locator('#confirm').click();
assert.deepEqual((await calls(p,'update_catalog_version')).at(-1),['update_catalog_version','same','1']);
await p.locator('[data-card-key="personal:same"] [data-place]').click();
assert.deepEqual((await calls(p,'place_model')).at(-1),['place_model','same']);
});
test('demo has hierarchy, candidate, confirmed MAF and counts without a bridge',async t=>{
const p=await open(t,null,true);
assert.equal(await p.locator('#catalog').isVisible(),true);
assert.match(await p.locator('[data-placement-count]').first().textContent(),/\d+ размещений/);
await p.locator('.nav [data-page="overview"]').click();
assert.ok(await p.locator('[data-node]').count()>2);
assert.ok(await p.locator('[data-candidate]').count()>0);
});
test('unknown counts stay unknown before report and after stale catalog refresh',async t=>{
const data=fixture();
data.catalog.forEach(card=>card.project_placements=null);
const p=await open(t,data);
assert.deepEqual(await p.locator('[data-placement-count]').allTextContents(),['В текущем проекте: —','В текущем проекте: —']);
await p.evaluate(data=>MAF.receive({data}),fixture());
await p.evaluate(()=>MAF.receive({report_stale:true}));
await p.evaluate(()=>MAF.receive({catalog_update:{catalog:[{id:'same',scope:'personal',project_placements:5}]}}));
assert.equal(await p.locator('[data-placement-count]').textContent(),'В текущем проекте: —');
});
test('stale marker blocks an already open global action; fresh data does not revive an old confirmation',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
await p.locator('[data-node="yard/1"]').click();
await p.locator('#selected-menu').click();
await p.locator('[data-action="delete"]').click();
assert.equal(await p.locator('#confirm').isEnabled(),true);
await p.evaluate(()=>MAF.receive({report_stale:true}));
assert.equal(await p.locator('#confirm').isDisabled(),true);
assert.match(await p.locator('#action-scope').textContent(),/устарел/);
await p.evaluate(data=>MAF.receive({data}),fixture());
assert.equal(await p.locator('#confirm').isDisabled(),true);
});
test('candidate reject and reset dispatch exact decisions; sections count only confirmed MAF',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
for(const decision of ['rejected','clear']){await p.locator('[data-candidate="definition:3"] [data-decision="'+decision+'"]').click();
await p.locator('#confirm').click();
assert.deepEqual((await calls(p,'set_maf_decision')).at(-1),['set_maf_decision',['definition:3'],decision]);
}await p.locator('.nav [data-page="sections"]').click();
assert.match(await p.locator('#sections-list').textContent(),/МАФ в проекте: 8 размещений/);
});
test('keyboard expands the chosen branch and the section filter retains its ancestors',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
await p.locator('[data-toggle-node="yard"]').focus();
await p.keyboard.press('Enter');
assert.equal(await p.locator('[data-node="yard/1"]').count(),0);
await p.keyboard.press('Enter');
await p.locator('#model-section').selectOption('Скамейки');
assert.equal(await p.locator('[data-node="yard"]').count(),1);
assert.equal(await p.locator('[data-node="yard/1"]').count(),1);
assert.equal((await calls(p,'select_rows')).length,0);
});
test('Ctrl and Shift preserve multi-selection by branch and external selection clears old branch identity',async t=>{
const p=await open(t);
await p.locator('.nav [data-page="overview"]').click();
await p.locator('[data-node="yard/1"]').click();
await p.locator('[data-node="park/5"]').click({modifiers:['Control']});
assert.equal(await p.locator('[data-node="yard/1"]').getAttribute('aria-selected'),'true');
assert.equal(await p.locator('[data-node="park/5"]').getAttribute('aria-selected'),'true');
await p.evaluate(()=>MAF.receive({selected_rows:['definition:4']}));
assert.equal(await p.locator('[data-node="park"]').getAttribute('aria-selected'),'true');
await p.locator('[data-node="yard/1"]').click();
await p.locator('[data-node="yard/3"]').click({modifiers:['Shift']});
assert.equal(await p.locator('[data-node="yard/1"]').getAttribute('aria-selected'),'true');
assert.equal(await p.locator('[data-node="yard/3"]').getAttribute('aria-selected'),'true');
});
test('renaming all duplicate definitions previews every affected path', async t=>{
const data=fixture();
data.duplicates=[{id:'dupe',label:'Скамья',confidence:'Точный матч',definitions:[{id:'1',name:'Модель 1',instances:3},{id:'2',name:'Модель 2',instances:2}]}];
const p=await open(t,data);
await p.locator('.nav [data-page="overview"]').click();
await p.locator('[data-node="yard/1"]').click();
await p.locator('#selected-menu').click();
await p.locator('[data-action="rename"]').click();
await p.locator('#modal-select').selectOption('all_names');
assert.match(await p.locator('#action-scope').textContent(),/5.*Двор \/ 2.*Парк \/ 2/s);
});

for (const [action, callback] of [
  ['delete', 'delete_rows'], ['rename', 'rename_rows'], ['section', 'move_rows'],
  ['add-library', 'add_rows_to_library'], ['decision-confirmed', 'set_maf_decision'],
  ['decision-rejected', 'set_maf_decision'], ['decision-clear', 'set_maf_decision']
]) {
  test(`review: ${action} keeps the previewed targets after external selection changes`, async t => {
    const p = await open(t);
    await p.locator('.nav [data-page="overview"]').click();
    await p.locator('[data-node="yard/1"]').click();
    await p.locator('#selected-menu').click();
    await p.locator(`[data-action="${action}"]`).click();
    const scope = await p.locator('#action-scope').textContent();
    await p.evaluate(() => MAF.receive({selected_rows:['definition:3']}));
    if (action === 'rename') await p.locator('#modal-input').fill('Новое имя');
    assert.equal(await p.locator('#action-scope').textContent(), scope);
    await p.locator('#confirm').click();
    assert.deepEqual((await calls(p, callback)).at(-1)[1], ['definition:1']);
  });
}

test('review: replacement previews and submission bind the same original targets', async t => {
  const data = fixture();
  data.definitions = [{id:'target-a',name:'Эталон A',kind:'component'}, {id:'target-b',name:'Эталон B',kind:'component'}];
  const p = await open(t, data);
  await p.locator('.nav [data-page="overview"]').click();
  await p.locator('[data-node="yard/1"]').click();
  await p.locator('#replace-selected').click();
  await p.evaluate(() => MAF.receive({selected_rows:['definition:3']}));
  await p.locator('#modal-select').selectOption('target-b');
  const previews = await calls(p, 'preview_replace_rows');
  assert.deepEqual(previews.map(call => call[1]), [['definition:1'], ['definition:1']]);
  await p.evaluate(token => MAF.receive({replacement_preview:{token,plan:{sources:['Модель 1'],target:'Эталон B',entities:3,placements:3,paths:['Двор / 1','Парк / 1'],blockers:[]}}}), previews.at(-1)[3]);
  await p.locator('#confirm').click();
  assert.deepEqual((await calls(p,'replace_rows')).at(-1), ['replace_rows',['definition:1'],'target-b']);
});

test('review: Ctrl toggles separate branches of one definition independently', async t => {
  const p = await open(t);
  await p.locator('.nav [data-page="overview"]').click();
  const a = p.locator('[data-node="yard/1"]'), b = p.locator('[data-node="park/1"]');
  await a.click();
  await b.click({modifiers:['Control']});
  assert.equal(await a.getAttribute('aria-selected'), 'true');
  assert.equal(await b.getAttribute('aria-selected'), 'true');
  assert.deepEqual((await calls(p,'select_rows')).at(-1)[1], ['definition:1']);
  await a.click({modifiers:['Control']});
  assert.equal(await a.getAttribute('aria-selected'), 'false');
  assert.equal(await b.getAttribute('aria-selected'), 'true');
  assert.deepEqual((await calls(p,'select_rows')).at(-1)[1], ['definition:1']);
  await b.click({modifiers:['Control']});
  assert.equal(await b.getAttribute('aria-selected'), 'false');
  assert.deepEqual((await calls(p,'select_rows')).at(-1)[1], []);
});

test('review: demo rename updates the visible hierarchy', async t => {
  const p = await open(t, null, true);
  await p.locator('.nav [data-page="overview"]').click();
  await p.locator('[data-node="yard/3"]').click();
  await p.locator('#selected-menu').click();
  await p.locator('[data-action="rename"]').click();
  await p.locator('#modal-input').fill('Новые качели');
  await p.locator('#confirm').click();
  assert.match(await p.locator('[data-node="yard/3"]').textContent(), /Новые качели/);
  assert.doesNotMatch(await p.locator('#models-body').textContent(), /Качели Дуэт/);
});

test('review: demo delete removes tree rows and updates component, MAF and card counts', async t => {
  const p = await open(t, null, true);
  await p.locator('.nav [data-page="overview"]').click();
  await p.locator('[data-node="yard/3"]').click();
  await p.locator('#selected-menu').click();
  await p.locator('[data-action="delete"]').click();
  await p.locator('#confirm').click();
  assert.equal(await p.locator('[data-node="yard/3"]').count(), 0);
  assert.match(await p.locator('#all-component-count').textContent(), /41 размещений.*5 определений/);
  assert.match(await p.locator('#maf-count').textContent(), /29 размещений.*4 определений/);
  await p.locator('.nav [data-page="catalog"]').click();
  assert.equal(await p.locator('[data-card-key="personal:d"] [data-placement-count]').textContent(), 'В текущем проекте: 0 размещений');
});

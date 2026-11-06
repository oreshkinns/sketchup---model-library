const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
test('metadata card updates merge only matching scope and preserve other cards', async()=>{
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage();
  await page.addInitScript(()=>window.sketchup=new Proxy({},{get:()=>()=>{}}));
  await page.goto(pathToFileURL(path.join(__dirname,'../preview.html')).href);
  await page.waitForFunction(()=>window.MAF);
  await page.evaluate(()=>MAF.receive({data:{summary:{},models:[],hierarchy:[],duplicates:[],sections:[],settings:{},cleanup:{},catalog:[{scope:'personal',id:'same',name:'Personal'},{scope:'shared',id:'same',name:'Shared'}]}}));
  await page.evaluate(()=>MAF.receive({catalog_card_update:{scope:'personal',id:'same',name:'Changed',favorite:true}}));
  assert.match(await page.locator('[data-card-key="personal:same"]').innerText(),/Changed/);
  assert.match(await page.locator('[data-card-key="shared:same"]').innerText(),/Shared/);
 } finally {await browser.close();}
});

const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
test('preview completion merges scoped cards and ignores stale requests',async()=>{
 const browser=await chromium.launch({headless:true});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>window.sketchup=new Proxy({},{get:()=>()=>{}}));
  await page.goto(pathToFileURL(path.join(__dirname,'../preview.html')).href);
  await page.waitForFunction(()=>window.MAF);
  await page.evaluate(()=>MAF.receive({data:{summary:{},models:[],hierarchy:[],duplicates:[],sections:[],settings:{},cleanup:{},catalog:[{scope:'personal',id:'same',name:'Personal'},{scope:'shared',id:'same',name:'Shared'}]}}));
  const send=async(state,request_id,name)=>page.evaluate(({state,request_id,name})=>MAF.receive({preview_event:{scope:'personal',id:'same',state,request_id},preview_card:{scope:'personal',id:'same',name}}),{state,request_id,name});
  await send('queued','new');await send('succeeded','old','STALE');
  assert.equal(await page.getByText('STALE',{exact:true}).count(),0);
  await send('succeeded','new','Completed');
  assert.match(await page.locator('[data-card-key="personal:same"]').innerText(),/Completed/);
  assert.match(await page.locator('[data-card-key="shared:same"]').innerText(),/Shared/);
  await send('failed','new','FAILED');
  assert.match(await page.locator('[data-card-key="personal:same"]').innerText(),/Completed/);
 }finally{await browser.close()}
});

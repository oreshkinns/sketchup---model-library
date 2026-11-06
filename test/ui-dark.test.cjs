const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
test('dark menus retain readable interaction states and baked white previews are subdued',async()=>{
 const browser=await chromium.launch({headless:true});
 try {
 const page=await browser.newPage({viewport:{width:900,height:600}});
 await page.setContent('<html data-theme="dark"><body><div class="catalog-art"><img width="360" height="240" alt="Bench model" src="data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="360" height="240"><path fill="white" d="M0 0h360v240H0z"/><path fill="#765538" d="M50 95h260v35H50zm20 35h20v60H70zm200 0h20v60h-20z"/></svg>')+'"></div><div class="catalog-context-menu" style="top:40px;left:400px"><button>Insert model</button><button class="catalog-context-danger">Delete model</button></div></body></html>');
 await page.addStyleTag({content:fs.readFileSync(path.join(__dirname,'../frontend/styles.css'),'utf8')});
 await page.addStyleTag({content:'*{transition:none!important}'});
 const contrast=async()=>page.locator('.catalog-context-menu button').evaluateAll(nodes=>{
 const rgb=s=>s.match(/[\d.]+/g).slice(0,3).map(Number);
 const lum=c=>rgb(c).map(v=>{v/=255;return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4)}).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0);
 return nodes.map(n=>{let b=(n.matches(':hover,:focus-visible')?n:n.parentElement);const a=lum(getComputedStyle(n).color),c=lum(getComputedStyle(b).backgroundColor);return (Math.max(a,c)+.05)/(Math.min(a,c)+.05)});
 });
 for(const state of ['normal','hover','focus']){
 if(state==='hover')await page.locator('button').first().hover();
 if(state==='focus') {await page.mouse.move(850,550);await page.keyboard.press('Tab');}
 assert.ok((await contrast()).every(v=>v>=4.5),state+' menu contrast '+JSON.stringify(await contrast()));
 }
 assert.equal(await page.locator('img').evaluate(n=>getComputedStyle(n).filter),'brightness(0.75)');
 await page.screenshot({path:path.join(__dirname,'../tmp/dark-menu-preview.png')});
 await page.evaluate(()=>document.documentElement.dataset.theme='light');
 assert.equal(await page.locator('img').evaluate(n=>getComputedStyle(n).filter),'none');
 } finally {await browser.close()}
});







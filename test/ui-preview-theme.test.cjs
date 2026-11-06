const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
test('preview surfaces follow explicit and system themes without dimming model colors',async()=>{
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage();
  await page.setContent('<div class="catalog-art"><img alt="model" src="data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' width=\'10\' height=\'10\'%3E%3Crect width=\'5\' height=\'5\' fill=\'%23cc5500\'/%3E%3C/svg%3E"></div>');
  await page.addStyleTag({content:fs.readFileSync(path.join(__dirname,'../frontend/styles.css'),'utf8')});
  for(const system of ['light','dark'])for(const theme of ['light','dark',null]){
   await page.emulateMedia({colorScheme:system});
   await page.evaluate(t=>t?document.documentElement.dataset.theme=t:delete document.documentElement.dataset.theme,theme);
   const actual=await page.locator('.catalog-art').evaluate(n=>({background:getComputedStyle(n).backgroundColor,filter:getComputedStyle(n.querySelector('img')).filter}));
   assert.equal(actual.background,(theme||system)==='dark'?'rgb(53, 69, 76)':'rgb(245, 246, 246)',`${system}/${theme}`);
   assert.equal(actual.filter,'none',`${system}/${theme} preserves model colors`);
  }
 }finally{await browser.close()}
});

const {test}=require('node:test');
const assert=require('node:assert/strict');
const {indexCatalogLinks}=require('../frontend/catalogLinks.cjs');
test('catalog link index keeps strict scopes, identity and warnings in one pass',()=>{
 let visits=0;
 const rows=Array.from({length:10000},(_,i)=>({get recognized_catalog(){visits++;return true},catalog_id:String(i%100),recognized_catalog_scope:i%2?'personal':'shared',recognition_warnings:['w'+i]}));
 rows.push({recognized_catalog:false,catalog_id:'1',recognized_catalog_scope:'personal'});
 const index=indexCatalogLinks(rows);
 assert.equal(visits,10000);
 assert.deepEqual(index.get('personal').get('1'),rows.filter(r=>r.recognized_catalog&&r.catalog_id==='1'&&r.recognized_catalog_scope==='personal'));
 assert.equal(index.get('shared').has('1'),false);
 assert.equal(index.get('personal').has(1),false);
});

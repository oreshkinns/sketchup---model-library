// Nested maps retain the strict scope/id identity used by catalog actions.
function indexCatalogLinks(rows) {
  const scopes = new Map();
  rows.forEach((row) => {
    if (!row.recognized_catalog) return;
    let ids = scopes.get(row.recognized_catalog_scope);
    if (!ids) { ids = new Map(); scopes.set(row.recognized_catalog_scope, ids); }
    let linked = ids.get(row.catalog_id);
    if (!linked) { linked = []; ids.set(row.catalog_id, linked); }
    linked.push(row);
  });
  return scopes;
}
module.exports = { indexCatalogLinks };

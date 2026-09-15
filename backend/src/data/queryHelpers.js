/**
 * Shared query helpers used by both store implementations.
 *
 * Keeping these in one place means the in-memory store and Firestore apply
 * exactly the same filtering and ordering semantics, so switching
 * DATA_BACKEND does not silently change query behaviour.
 */

/**
 * Flat equality match. `where` is a plain object of field -> expected value.
 * @param {object} doc
 * @param {object|undefined} where
 * @returns {boolean}
 */
function matchesWhere(doc, where) {
  if (!where) return true;
  return Object.entries(where).every(([field, value]) => doc[field] === value);
}

/**
 * Sort by a single field.
 * @param {object[]} docs
 * @param {{field: string, dir?: 'asc'|'desc'}|undefined} orderBy
 * @returns {object[]}
 */
function sortDocs(docs, orderBy) {
  if (!orderBy) return docs;
  const { field, dir = 'asc' } = orderBy;
  const sign = dir === 'desc' ? -1 : 1;
  return [...docs].sort((a, b) => {
    const av = a[field];
    const bv = b[field];
    if (av === bv) return 0;
    // Missing values sort last regardless of direction, so incomplete
    // documents never jump to the top of a result list.
    if (av == null) return 1;
    if (bv == null) return -1;
    return av > bv ? sign : -sign;
  });
}

/**
 * Apply the parts of a query that cannot be pushed down to the engine:
 * every `where` clause after the first, plus ordering and limit.
 * @param {object[]} docs
 * @param {object} query
 * @param {object} [residualWhere] clauses already handled by the engine
 * @returns {object[]}
 */
function applyResidual(docs, query = {}, residualWhere = query.where) {
  let result = docs.filter((doc) => matchesWhere(doc, residualWhere));
  result = sortDocs(result, query.orderBy);
  if (query.limit != null) result = result.slice(0, query.limit);
  return result;
}

module.exports = { matchesWhere, sortDocs, applyResidual };

const { randomUUID } = require('crypto');
const { matchesWhere, applyResidual } = require('./queryHelpers');

/**
 * In-process document store used when DATA_BACKEND=memory.
 *
 * Data lives for the lifetime of the process only. This exists so the whole
 * application can be run and demonstrated without a Firebase project.
 * It implements exactly the same interface as firestoreStore.
 */

/** @type {Map<string, Map<string, object>>} collection name -> id -> document */
const collections = new Map();

function table(collection) {
  if (!collections.has(collection)) collections.set(collection, new Map());
  return collections.get(collection);
}

function clone(doc) {
  return doc == null ? doc : structuredClone(doc);
}

const memoryStore = {
  async insert(collection, doc) {
    const id = doc.id || randomUUID();
    const stored = { ...clone(doc), id };
    table(collection).set(id, stored);
    return clone(stored);
  },

  async insertMany(collection, docs) {
    const stored = [];
    for (const doc of docs) {
      stored.push(await memoryStore.insert(collection, doc));
    }
    return stored;
  },

  async findById(collection, id) {
    return clone(table(collection).get(id) ?? null);
  },

  async find(collection, query = {}) {
    const docs = [...table(collection).values()];
    // Clone on the way out so callers can never mutate stored documents.
    return applyResidual(docs, query).map(clone);
  },

  async update(collection, id, patch) {
    const current = table(collection).get(id);
    if (!current) return null;
    const updated = { ...current, ...clone(patch), id };
    table(collection).set(id, updated);
    return clone(updated);
  },

  async remove(collection, id) {
    return table(collection).delete(id);
  },

  async removeWhere(collection, query = {}) {
    const doomed = [...table(collection).values()].filter((doc) =>
      matchesWhere(doc, query.where),
    );
    for (const doc of doomed) table(collection).delete(doc.id);
    return doomed.length;
  },

  /** Test-only helper: wipe every collection. */
  async reset() {
    collections.clear();
  },
};

module.exports = memoryStore;

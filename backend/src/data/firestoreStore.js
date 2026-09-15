const { getDb } = require('../config/firebase');
const { applyResidual } = require('./queryHelpers');

/**
 * Firestore-backed document store used when DATA_BACKEND=firestore.
 * Implements exactly the same interface as memoryStore.
 *
 * Timestamps are stored as ISO 8601 strings rather than Firestore Timestamps.
 * That keeps the two stores interchangeable (a document written by one is
 * readable by the other) and makes ordering work identically, since ISO strings
 * sort chronologically as plain strings.
 */

function database() {
  const db = getDb();
  if (!db) {
    throw new Error(
      'Firestore is not initialised. Set DATA_BACKEND=firestore and provide ' +
        'credentials (see .env.example), or use DATA_BACKEND=memory.',
    );
  }
  return db;
}

function fromDoc(doc) {
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

const firestoreStore = {
  async insert(collection, doc) {
    const { id, ...data } = doc;
    const ref = id
      ? database().collection(collection).doc(id)
      : database().collection(collection).doc();
    await ref.set(data);
    return { id: ref.id, ...data };
  },

  async insertMany(collection, docs) {
    // Firestore caps a batch at 500 writes; chunk to stay under it.
    const chunks = [];
    for (let i = 0; i < docs.length; i += 450) {
      chunks.push(docs.slice(i, i + 450));
    }

    const written = [];
    for (const chunk of chunks) {
      const batch = database().batch();
      const refs = chunk.map(() => database().collection(collection).doc());
      refs.forEach((ref, index) => {
        const { id, ...data } = chunk[index];
        batch.set(ref, data);
      });
      // eslint-disable-next-line no-await-in-loop
      await batch.commit();
      refs.forEach((ref, index) => {
        const { id, ...data } = chunk[index];
        written.push({ id: ref.id, ...data });
      });
    }
    return written;
  },

  async findById(collection, id) {
    const snap = await database().collection(collection).doc(id).get();
    return fromDoc(snap);
  },

  async find(collection, query = {}) {
    const whereEntries = Object.entries(query.where || {});
    let ref = database().collection(collection);

    // Push at most ONE equality filter down to Firestore. Chaining two equality
    // filters on different fields requires a composite index, which would make
    // this fail at runtime against a fresh project. These collections are small
    // (a classroom's worth of documents), so the remaining clauses are applied
    // in memory instead, via applyResidual.
    if (whereEntries.length > 0) {
      const [field, value] = whereEntries[0];
      ref = ref.where(field, '==', value);
    }

    const snapshot = await ref.get();
    const docs = snapshot.docs.map(fromDoc).filter(Boolean);
    const residualWhere = Object.fromEntries(whereEntries.slice(1));
    return applyResidual(docs, query, residualWhere);
  },

  async update(collection, id, patch) {
    const ref = database().collection(collection).doc(id);
    const existing = await ref.get();
    if (!existing.exists) return null;
    const { id: _ignored, ...data } = patch;
    await ref.set(data, { merge: true });
    const updated = await ref.get();
    return fromDoc(updated);
  },

  async remove(collection, id) {
    const ref = database().collection(collection).doc(id);
    const existing = await ref.get();
    if (!existing.exists) return false;
    await ref.delete();
    return true;
  },

  async removeWhere(collection, query = {}) {
    const docs = await firestoreStore.find(collection, { where: query.where });
    if (docs.length === 0) return 0;

    for (let i = 0; i < docs.length; i += 450) {
      const batch = database().batch();
      docs.slice(i, i + 450).forEach((doc) => {
        batch.delete(database().collection(collection).doc(doc.id));
      });
      // eslint-disable-next-line no-await-in-loop
      await batch.commit();
    }
    return docs.length;
  },
};

module.exports = firestoreStore;

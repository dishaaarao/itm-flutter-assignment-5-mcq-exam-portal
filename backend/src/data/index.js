const { config } = require('../config/env');
const memoryStore = require('./memoryStore');

/**
 * Selects the data store implementation.
 *
 * firestoreStore is required lazily so that `firebase-admin` is never loaded
 * when DATA_BACKEND=memory — that package throws while initialising without
 * credentials, which would break the credential-free demo path at import time.
 */
function selectStore() {
  if (config.dataBackend === 'firestore') {
    // eslint-disable-next-line global-require
    return require('./firestoreStore');
  }
  return memoryStore;
}

module.exports = { store: selectStore() };

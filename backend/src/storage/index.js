const { config } = require('../config/env');
const localStorage = require('./localStorage');

/**
 * Selects the storage implementation.
 *
 * cloudinaryStorage is required lazily so the `cloudinary` package is never
 * loaded when STORAGE_BACKEND=local.
 */
function selectStorage() {
  if (config.storageBackend === 'cloudinary') {
    // eslint-disable-next-line global-require
    return require('./cloudinaryStorage');
  }
  return localStorage;
}

module.exports = { storage: selectStorage() };

const { config } = require('./env');

/**
 * Cloudinary client setup.
 *
 * Lazy for the same reason as firebase.js: the `cloudinary` package is only
 * needed when STORAGE_BACKEND=cloudinary, and the credential-free demo path
 * must never touch it.
 */

let client = null;

/** @returns {import('cloudinary').v2} */
function getCloudinary() {
  if (!client) {
    if (!config.cloudinary.isConfigured) {
      throw new Error(
        'Cloudinary credentials are missing. Set CLOUDINARY_CLOUD_NAME, ' +
          'CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET (see .env.example), ' +
          'or use STORAGE_BACKEND=local to store files on disk instead.',
      );
    }

    // eslint-disable-next-line global-require
    const cloudinary = require('cloudinary');
    cloudinary.v2.config({
      cloud_name: config.cloudinary.cloudName,
      api_key: config.cloudinary.apiKey,
      api_secret: config.cloudinary.apiSecret,
      secure: true,
    });
    client = cloudinary.v2;
  }
  return client;
}

module.exports = { getCloudinary };

const { getCloudinary } = require('../config/cloudinary');

/**
 * Cloudinary-backed storage used when STORAGE_BACKEND=cloudinary.
 * Implements the same interface as localStorage.
 *
 * The browser/Flutter client never talks to Cloudinary directly — uploads are
 * proxied through this backend so the API secret stays server-side and no
 * unsigned upload preset has to be shipped in the app.
 */

const IMAGE_MIME_PREFIX = 'image/';

function resourceTypeFor(mimetype) {
  // Cloudinary treats images and video as media, everything else as 'raw'.
  return String(mimetype || '').startsWith(IMAGE_MIME_PREFIX) ? 'image' : 'raw';
}

function uploadStream(buffer, options) {
  return new Promise((resolve, reject) => {
    const stream = getCloudinary().uploader.upload_stream(options, (error, result) => {
      if (error) reject(error);
      else resolve(result);
    });
    stream.end(buffer);
  });
}

const cloudinaryStorage = {
  /**
   * @param {Buffer} buffer
   * @param {{folder: string, filename: string, mimetype?: string}} options
   * @returns {Promise<{url: string, publicId: string, resourceType: string}>}
   */
  async upload(buffer, { folder, filename, mimetype }) {
    const resourceType = resourceTypeFor(mimetype);
    const publicId = String(filename || 'file').replace(/\.[^.]+$/, '');

    const result = await uploadStream(buffer, {
      folder,
      public_id: `${publicId}_${Date.now()}`,
      resource_type: resourceType,
    });

    return {
      url: result.secure_url,
      publicId: result.public_id,
      resourceType,
    };
  },

  /**
   * @param {string} publicId
   * @param {{resourceType?: string}} [options] Cloudinary needs the resource
   *   type to know which store to delete from; defaults to 'raw'.
   */
  async destroy(publicId, { resourceType = 'raw' } = {}) {
    if (!publicId) return;
    await getCloudinary().uploader.destroy(publicId, { resource_type: resourceType });
  },

  /** Cloudinary URLs are already absolute. */
  resolveUrl(url) {
    return url;
  },
};

module.exports = cloudinaryStorage;

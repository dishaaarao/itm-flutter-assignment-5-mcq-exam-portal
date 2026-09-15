const fs = require('fs/promises');
const path = require('path');
const { config } = require('../config/env');

/**
 * Filesystem-backed storage used when STORAGE_BACKEND=local.
 *
 * Files are written under <backend>/uploads/<folder>/ and served by
 * express.static at /uploads. URLs are returned as root-relative paths
 * (e.g. "/uploads/excel-sheets/exam_123.xlsx"); clients resolve them against
 * the API origin, which keeps stored URLs host-independent.
 *
 * Implements the same interface as cloudinaryStorage.
 */

/** Strip any path separators so a crafted filename cannot escape the uploads dir. */
function safeName(filename) {
  const base = path.basename(String(filename || 'file'));
  return base.replace(/[^\w.\-]+/g, '_');
}

const localStorage = {
  /**
   * @param {Buffer} buffer
   * @param {{folder: string, filename: string, mimetype?: string}} options
   * @returns {Promise<{url: string, publicId: string, resourceType: string}>}
   */
  async upload(buffer, { folder, filename }) {
    const safeFolder = folder
      .split('/')
      .map((segment) => segment.replace(/[^\w.\-]+/g, '_'))
      .join('/');

    const destinationDir = path.join(config.uploadsDir, safeFolder);
    await fs.mkdir(destinationDir, { recursive: true });

    const unique = `${Date.now()}_${safeName(filename)}`;
    await fs.writeFile(path.join(destinationDir, unique), buffer);

    const relativePath = `/uploads/${safeFolder}/${unique}`;
    return {
      url: relativePath,
      publicId: `${safeFolder}/${unique}`,
      resourceType: 'local',
    };
  },

  /**
   * @param {string} publicId the value returned from upload()
   */
  async destroy(publicId) {
    if (!publicId) return;
    const target = path.join(config.uploadsDir, publicId);
    // Guard against a publicId containing traversal segments.
    if (!path.resolve(target).startsWith(path.resolve(config.uploadsDir))) return;
    await fs.rm(target, { force: true });
  },

  /** Local paths are already servable; nothing to resolve. */
  resolveUrl(url) {
    return url;
  },
};

module.exports = localStorage;

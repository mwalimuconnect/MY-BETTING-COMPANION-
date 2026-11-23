// backend/models/FootballCache.js
const mongoose = require('mongoose');

const footballCacheSchema = new mongoose.Schema(
  {
    cacheKey: {
      type: String,
      required: true,
      unique: true,
      index: true,
    },
    endpoint: {
      type: String,
      required: true,
    },
    payload: {
      type: mongoose.Schema.Types.Mixed,
      required: true,
    },
    fetchedAt: {
      type: Date,
      required: true,
      default: Date.now,
    },
    freshUntil: {
      type: Date,
      required: true,
      index: true,
    },
    expiresAt: {
      type: Date,
      required: true,
      index: { expires: 0 },
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('FootballCache', footballCacheSchema);

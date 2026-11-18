const mongoose = require('mongoose');

const userAccessSchema = new mongoose.Schema({
  phone: { type: String, required: true, unique: true, trim: true },
  name: { type: String, default: '' },
  role: { type: String, enum: ['user', 'admin'], default: 'user' },
  waiverExpiry: { type: Date, required: true },
  subscriptionExpiry: { type: Date, default: null },
  lastMpesaReceipt: { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('UserAccess', userAccessSchema);

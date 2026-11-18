const express = require('express');
const router = express.Router();
const UserAccess = require('../models/UserAccess');

const ADMIN_PHONES = ['254712345678']; // Replace with your admin phone

function normalizePhone(phone) {
  let cleaned = phone.replace(/\s+/g, '').replace(/^\+/, '');
  if (cleaned.startsWith('0')) cleaned = '254' + cleaned.slice(1);
  return cleaned;
}

router.post('/check', async (req, res) => {
  try {
    const rawPhone = req.body.phone;
    const name = req.body.name || '';
    if (!rawPhone) return res.status(400).json({ error: 'Phone number required' });

    const phone = normalizePhone(rawPhone);
    const isAdminPhone = ADMIN_PHONES.includes(phone);

    let user = await UserAccess.findOne({ phone });

    if (!user) {
      const waiverExpiry = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7-day waiver
      user = await UserAccess.create({
        phone,
        name,
        role: isAdminPhone ? 'admin' : 'user',
        waiverExpiry,
      });
    } else if (isAdminPhone && user.role !== 'admin') {
      user.role = 'admin';
      await user.save();
    }

    const now = new Date();
    const isAdmin = user.role === 'admin';
    const inWaiver = now < user.waiverExpiry;
    const inSubscription = user.subscriptionExpiry && now < user.subscriptionExpiry;
    const hasAccess = isAdmin || inWaiver || inSubscription;

    const remainingWaiverDays = inWaiver
      ? Math.ceil((user.waiverExpiry - now) / (24 * 60 * 60 * 1000))
      : 0;

    res.json({
      hasAccess,
      isAdmin,
      inWaiver,
      remainingWaiverDays,
      waiverExpiry: user.waiverExpiry,
      subscriptionExpiry: user.subscriptionExpiry,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error checking access' });
  }
});

router.post('/grant', async (req, res) => {
  try {
    const { phone: rawPhone, planType, mpesaReceipt } = req.body;
    const phone = normalizePhone(rawPhone);

    const daysMap = { daily: 1, weekly: 7, monthly: 30 };
    const daysToAdd = daysMap[planType] || 1;

    const user = await UserAccess.findOne({ phone });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const baseTime = (user.subscriptionExpiry && user.subscriptionExpiry > new Date())
      ? user.subscriptionExpiry.getTime()
      : Date.now();

    user.subscriptionExpiry = new Date(baseTime + daysToAdd * 24 * 60 * 60 * 1000);
    if (mpesaReceipt) user.lastMpesaReceipt = mpesaReceipt;
    await user.save();

    res.json({
      success: true,
      hasAccess: true,
      subscriptionExpiry: user.subscriptionExpiry,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to update subscription' });
  }
});

module.exports = router;

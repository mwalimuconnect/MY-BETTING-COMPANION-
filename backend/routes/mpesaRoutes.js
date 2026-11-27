const express = require('express');
const router = express.Router();
const UserAccess = require('../models/UserAccess');

const SANDBOX_BASE_URL = 'https://sandbox.safaricom.co.ke';

const DAYS_MAP = {
  daily: 1,
  weekly: 7,
  monthly: 30,
};

function normalizePhone(phone = '') {
  let cleaned = String(phone).replace(/\s+/g, '').replace(/^\+/, '');
  if (cleaned.startsWith('0')) cleaned = '254' + cleaned.slice(1);
  return cleaned;
}

function resolvePlanType(planType, accountReference) {
  const candidate = String(planType || accountReference || 'daily')
    .trim()
    .toLowerCase();
  return DAYS_MAP[candidate] ? candidate : 'daily';
}

function getTimestamp() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return (
    now.getFullYear().toString() +
    pad(now.getMonth() + 1) +
    pad(now.getDate()) +
    pad(now.getHours()) +
    pad(now.getMinutes()) +
    pad(now.getSeconds())
  );
}

async function getSandboxAccessToken() {
  const key = process.env.MPESA_CONSUMER_KEY;
  const secret = process.env.MPESA_CONSUMER_SECRET;
  if (!key || !secret) {
    throw new Error('Missing MPESA_CONSUMER_KEY or MPESA_CONSUMER_SECRET');
  }

  const auth = Buffer.from(`${key}:${secret}`).toString('base64');
  const res = await fetch(
    `${SANDBOX_BASE_URL}/oauth/v1/generate?grant_type=client_credentials`,
    {
      method: 'GET',
      headers: { Authorization: `Basic ${auth}` },
    }
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Daraja OAuth failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  if (!data.access_token) {
    throw new Error('No access_token in Daraja OAuth response');
  }
  return data.access_token;
}

async function grantSubscriptionToUser({ phone, planType, receipt }) {
  const normalizedPhone = normalizePhone(phone);
  if (!normalizedPhone) return null;

  const resolvedPlan = resolvePlanType(planType);
  const daysToAdd = DAYS_MAP[resolvedPlan] || 1;
  let user = await UserAccess.findOne({ phone: normalizedPhone });

  if (!user) {
    user = await UserAccess.create({
      phone: normalizedPhone,
      role: 'user',
    });
  }

  const now = Date.now();
  const baseTime =
    user.subscriptionExpiry && user.subscriptionExpiry.getTime() > now
      ? user.subscriptionExpiry.getTime()
      : now;

  user.subscriptionExpiry = new Date(baseTime + daysToAdd * 24 * 60 * 60 * 1000);
  if (receipt) user.lastMpesaReceipt = receipt;
  await user.save();

  return user;
}

// POST /api/mpesa/stk-push
router.post('/stk-push', async (req, res) => {
  try {
    const { phone, amount, accountReference, planType } = req.body || {};
    const normalizedPhone = normalizePhone(phone);
    const parsedAmount = Math.round(Number(amount));
    const resolvedPlan = resolvePlanType(planType, accountReference);

    if (!normalizedPhone) {
      return res.status(400).json({ success: false, message: 'Phone number required' });
    }
    if (!parsedAmount || parsedAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid amount' });
    }

    const shortcode = process.env.MPESA_SHORTCODE || '174379';
    const passkey = process.env.MPESA_PASSKEY;
    const callbackUrl = process.env.MPESA_CALLBACK_URL;

    if (!passkey || !callbackUrl) {
      return res.status(500).json({
        success: false,
        message: 'Missing MPESA_PASSKEY or MPESA_CALLBACK_URL on server',
      });
    }

    const token = await getSandboxAccessToken();
    const timestamp = getTimestamp();
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

    const stkRes = await fetch(`${SANDBOX_BASE_URL}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: parsedAmount,
        PartyA: normalizedPhone,
        PartyB: shortcode,
        PhoneNumber: normalizedPhone,
        CallBackURL: callbackUrl,
        AccountReference: String(accountReference || resolvedPlan).slice(0, 12),
        TransactionDesc: 'SlipAccess',
      }),
    });

    const stkData = await stkRes.json();
    const accepted = stkRes.ok && stkData.ResponseCode === '0';

    if (!accepted) {
      return res.status(400).json({
        success: false,
        message: stkData.errorMessage || stkData.ResponseDescription || 'STK Push rejected',
        data: stkData,
      });
    }

    if (req.app.locals.MpesaTransaction) {
      await req.app.locals.MpesaTransaction.findOneAndUpdate(
        { checkoutRequestId: stkData.CheckoutRequestID },
        {
          checkoutRequestId: stkData.CheckoutRequestID,
          phone: normalizedPhone,
          planType: resolvedPlan,
          amount: parsedAmount,
          status: 'pending',
        },
        { upsert: true, new: true }
      );
    }

    return res.status(200).json({
      success: true,
      checkoutRequestId: stkData.CheckoutRequestID,
      merchantRequestId: stkData.MerchantRequestID,
      customerMessage: stkData.CustomerMessage,
    });
  } catch (err) {
    console.error('STK push error:', err);
    return res.status(500).json({ success: false, message: 'Server error initiating STK push' });
  }
});

// POST /api/mpesa/callback
router.post('/callback', async (req, res) => {
  try {
    const stkCallback = req.body?.Body?.stkCallback;
    if (!stkCallback) {
      return res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
    }

    const { CheckoutRequestID, ResultCode, ResultDesc, CallbackMetadata } = stkCallback;
    const isPaid = Number(ResultCode) === 0;

    let receipt = '';
    let phone = '';
    const items = CallbackMetadata?.Item || [];
    for (const item of items) {
      if (item.Name === 'MpesaReceiptNumber') receipt = String(item.Value || '');
      if (item.Name === 'PhoneNumber') phone = normalizePhone(item.Value);
    }

    let txDoc = null;
    if (req.app.locals.MpesaTransaction) {
      txDoc = await req.app.locals.MpesaTransaction.findOneAndUpdate(
        { checkoutRequestId: CheckoutRequestID },
        {
          status: isPaid ? 'paid' : 'failed',
          resultCode: Number(ResultCode),
          resultDesc: ResultDesc || '',
          receipt,
        },
        { new: true }
      );
    }

    const targetPhone = phone || txDoc?.phone;
    const resolvedPlan = resolvePlanType(txDoc?.planType);

    if (isPaid && targetPhone) {
      await grantSubscriptionToUser({
        phone: targetPhone,
        planType: resolvedPlan,
        receipt,
      });
    }

    return res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
  } catch (err) {
    console.error('M-Pesa callback error:', err);
    return res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' });
  }
});

module.exports = router;

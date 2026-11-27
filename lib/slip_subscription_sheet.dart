import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'mpesa_service.dart';
import 'slip_access_manager.dart';

const Color _teal = Color(0xFF008080);

const Map<String, int> _planAmounts = {
  'daily': 50,
  'weekly': 200,
  'monthly': 500,
};

String _normalizePhone(String raw) {
  var cleaned = raw.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
  if (cleaned.startsWith('0')) cleaned = '254${cleaned.substring(1)}';
  return cleaned;
}

void showSlipSubscriptionSheet(
  BuildContext context,
  Future<void> Function() onUnlocked,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unlock Prolific System Slips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _teal,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a plan to initiate an M-Pesa STK Push and unlock system slips:',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Daily Plan
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: _teal, width: 0.8),
            ),
            title: const Text(
              'Daily Plan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('1 Day Access'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _startMpesaPayment(context, 'daily', onUnlocked);
              },
              child: const Text('Ksh 50'),
            ),
          ),
          const SizedBox(height: 10),

          // Weekly Plan
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: _teal, width: 0.8),
            ),
            title: const Text(
              'Weekly Plan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('7 Days Access (Best Value)'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _startMpesaPayment(context, 'weekly', onUnlocked);
              },
              child: const Text('Ksh 200'),
            ),
          ),
          const SizedBox(height: 10),

          // Monthly Plan
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: _teal, width: 0.8),
            ),
            title: const Text(
              'Monthly Plan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('30 Days Full Access'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _startMpesaPayment(context, 'monthly', onUnlocked);
              },
              child: const Text('Ksh 500'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

Future<void> _startMpesaPayment(
  BuildContext context,
  String planType,
  Future<void> Function() onUnlocked,
) async {
  final prefs = await SharedPreferences.getInstance();
  final phone = _normalizePhone(prefs.getString('profile_phone') ?? '');
  final amount = (_planAmounts[planType] ?? 50).toDouble();

  if (phone.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please set your phone number in your profile first.'),
      ),
    );
    return;
  }

  final statusText = ValueNotifier<String>('Sending M-Pesa STK Push...');

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: ValueListenableBuilder<String>(
        valueListenable: statusText,
        builder: (_, msg, __) => Row(
          children: [
            const CircularProgressIndicator(color: _teal),
            const SizedBox(width: 20),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    ),
  );

  final sent = await MpesaService.initiateStkPush(
    phone: phone,
    amount: amount,
    accountReference: planType,
    planType: planType,
  );

  if (!context.mounted) {
    statusText.dispose();
    return;
  }

  if (!sent) {
    Navigator.pop(context);
    statusText.dispose();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not send STK Push. Check connection or phone.'),
      ),
    );
    return;
  }

  statusText.value = 'Waiting for M-Pesa confirmation...';

  bool unlocked = false;
  for (int i = 0; i < 10; i++) {
    await Future.delayed(const Duration(seconds: 3));
    if (!context.mounted) {
      statusText.dispose();
      return;
    }

    final access = await SlipAccessManager.checkAccess(overridePhone: phone);
    if (access.hasAccess) {
      unlocked = true;
      break;
    }
  }

  if (!context.mounted) {
    statusText.dispose();
    return;
  }

  Navigator.pop(context);
  statusText.dispose();

  if (unlocked) {
    await onUnlocked();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment confirmed! System slips unlocked.')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment still pending or not confirmed yet. Tap Unlock Slip to re-check.',
        ),
      ),
    );
  }
}

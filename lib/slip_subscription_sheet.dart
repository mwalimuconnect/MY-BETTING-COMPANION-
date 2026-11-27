import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'slip_access_manager.dart';

const Color _teal = Color(0xFF008080);

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
            'Choose a plan to instantly unlock AI-powered value accumulators:',
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
                await _simulateMpesaPayment(context, 'daily', onUnlocked);
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
                await _simulateMpesaPayment(context, 'weekly', onUnlocked);
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
                await _simulateMpesaPayment(context, 'monthly', onUnlocked);
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

Future<void> _simulateMpesaPayment(
  BuildContext context,
  String planType,
  Future<void> Function() onUnlocked,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(color: _teal),
          SizedBox(width: 20),
          Expanded(
            child: Text('Simulating M-Pesa STK Push...'),
          ),
        ],
      ),
    ),
  );

  await Future.delayed(const Duration(seconds: 3));
  if (!context.mounted) return;
  Navigator.pop(context); // close loading

  await SlipAccessManager.activatePlan(planType);
  await onUnlocked();

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Payment successful! System slips unlocked.')),
  );
}

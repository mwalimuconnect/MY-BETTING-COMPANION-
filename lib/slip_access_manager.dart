import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SlipAccessStatus {
  final bool hasAccess;
  final bool isAdmin;
  final int remainingWaiverDays;
  final String serverPin;

  SlipAccessStatus({
    required this.hasAccess,
    required this.isAdmin,
    this.remainingWaiverDays = 0,
    this.serverPin = '',
  });
}

class SlipAccessManager {
  // Replace with your deployed Render backend base URL
  static const String _baseUrl =
      'https://my-betting-companion.onrender.com/api/access';
  static const String _cachedAccessKey = 'cached_has_access';
  static const String _cachedAdminKey = 'cached_is_admin';

  /// Syncs phone, name, and PIN with MongoDB backend and returns access status.
  static Future<SlipAccessStatus> checkAccess({
    String? overridePhone,
    String? pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = overridePhone ?? prefs.getString('profile_phone') ?? '';
    final name = prefs.getString('profile_name') ?? '';
    final storedPin = pin ?? prefs.getString('bankroll_pin') ?? '';

    if (phone.isEmpty) {
      return SlipAccessStatus(hasAccess: false, isAdmin: false);
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'name': name,
              'pin': storedPin,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool hasAccess = data['hasAccess'] == true;
        final bool isAdmin = data['isAdmin'] == true;
        final int waiverDays =
            (data['remainingWaiverDays'] as num?)?.toInt() ?? 0;
        final String serverPin = data['pin']?.toString() ?? '';

        await prefs.setBool(_cachedAccessKey, hasAccess);
        await prefs.setBool(_cachedAdminKey, isAdmin);
        if (serverPin.isNotEmpty && storedPin.isEmpty) {
          await prefs.setString('bankroll_pin', serverPin);
        }

        return SlipAccessStatus(
          hasAccess: hasAccess,
          isAdmin: isAdmin,
          remainingWaiverDays: waiverDays,
          serverPin: serverPin,
        );
      }
    } catch (_) {}

    return SlipAccessStatus(
      hasAccess: prefs.getBool(_cachedAccessKey) ?? false,
      isAdmin: prefs.getBool(_cachedAdminKey) ?? false,
    );
  }

  /// Verifies registered phone on backend and updates the user's 4-digit PIN.
  static Future<bool> resetPin(String phone, String newPin) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/reset-pin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'newPin': newPin,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bankroll_pin', newPin);
        await prefs.setString('profile_phone', phone);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Calls backend to activate subscription plan after M-Pesa payment.
  static Future<bool> activatePlan(
    String planType, {
    String receipt = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('profile_phone') ?? '';
    if (phone.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/grant'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'planType': planType,
          'mpesaReceipt': receipt,
        }),
      );

      if (response.statusCode == 200) {
        await prefs.setBool(_cachedAccessKey, true);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

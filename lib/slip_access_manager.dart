import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SlipAccessStatus {
  final bool hasAccess;
  final bool isAdmin;
  final int remainingWaiverDays;

  SlipAccessStatus({
    required this.hasAccess,
    required this.isAdmin,
    this.remainingWaiverDays = 0,
  });
}

class SlipAccessManager {
  // TODO: Replace with your actual deployed Render backend URL
  static const String _baseUrl = 'https://my-betting-companion.onrender.com/api/access';
  static const String _cachedAccessKey = 'cached_has_access';
  static const String _cachedAdminKey = 'cached_is_admin';

  /// Syncs with MongoDB backend using the user's saved phone number.
  /// If no phone is saved yet, returns false (prompts user to set phone in profile).
  static Future<SlipAccessStatus> checkAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('profile_phone') ?? '';
    final name = prefs.getString('profile_name') ?? '';

    if (phone.isEmpty) {
      return SlipAccessStatus(hasAccess: false, isAdmin: false);
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'name': name}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool hasAccess = data['hasAccess'] == true;
        final bool isAdmin = data['isAdmin'] == true;
        final int waiverDays = (data['remainingWaiverDays'] as num?)?.toInt() ?? 0;

        // Cache locally for offline/fast UI fallback
        await prefs.setBool(_cachedAccessKey, hasAccess);
        await prefs.setBool(_cachedAdminKey, isAdmin);

        return SlipAccessStatus(
          hasAccess: hasAccess,
          isAdmin: isAdmin,
          remainingWaiverDays: waiverDays,
        );
      }
    } catch (_) {
      // Fallback to cached status if network is temporarily unavailable
    }

    return SlipAccessStatus(
      hasAccess: prefs.getBool(_cachedAccessKey) ?? false,
      isAdmin: prefs.getBool(_cachedAdminKey) ?? false,
    );
  }

  /// Calls backend to activate plan (hook this to your M-Pesa STK Push verification)
  static Future<bool> activatePlan(String planType, {String receipt = ''}) async {
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

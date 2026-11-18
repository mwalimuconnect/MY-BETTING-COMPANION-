import 'package:shared_preferences/shared_preferences.dart';

class SlipAccessManager {
  static const String _expiryKey = 'slip_access_expiry';
  static const String _installKey = 'app_install_timestamp';

  /// Checks if the user has active access (Admin, active subscription, or 1-week new user waiver).
  static Future<bool> hasActiveAccess(bool isAdmin) async {
    if (isAdmin) return true;

    final prefs = await SharedPreferences.getInstance();
    
    // 1. Check 1-week new user waiver
    int installTime = prefs.getInt(_installKey) ?? 0;
    if (installTime == 0) {
      installTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_installKey, installTime);
    }
    
    final waiverExpiry = installTime + (7 * 24 * 60 * 60 * 1000); // 7 days in milliseconds
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    
    if (nowMillis < waiverExpiry) {
      return true; // Active new user waiver
    }

    // 2. Check paid subscription expiry
    final expiryMillis = prefs.getInt(_expiryKey) ?? 0;
    return nowMillis < expiryMillis;
  }

  /// Returns remaining waiver days for new users, or 0 if expired
  static Future<int> getRemainingWaiverDays() async {
    final prefs = await SharedPreferences.getInstance();
    int installTime = prefs.getInt(_installKey) ?? 0;
    if (installTime == 0) {
      installTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_installKey, installTime);
    }
    
    final waiverExpiry = installTime + (7 * 24 * 60 * 60 * 1000);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    
    if (nowMillis < waiverExpiry) {
      final diff = waiverExpiry - nowMillis;
      return (diff / (24 * 60 * 60 * 1000)).ceil();
    }
    return 0;
  }

  /// Grant access based on the selected plan duration (daily, weekly, monthly)
  static Future<void> grantAccess(String planType) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    DateTime expiryDate;

    if (planType == 'daily') {
      expiryDate = now.add(const Duration(days: 1));
    } else if (planType == 'weekly') {
      expiryDate = now.add(const Duration(days: 7));
    } else { // monthly
      expiryDate = now.add(const Duration(days: 30));
    }

    await prefs.setInt(_expiryKey, expiryDate.millisecondsSinceEpoch);
  }
}

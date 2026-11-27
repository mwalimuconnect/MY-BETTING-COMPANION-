import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MpesaService {
  static const String baseUrl = 'https://my-betting-companion.onrender.com';

  static Future<bool> initiateStkPush({
    required String phone,
    required double amount,
    required String accountReference,
    String planType = 'daily',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mpesa/stk-push'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'amount': amount.toInt(),
              'accountReference': accountReference,
              'planType': planType,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data['success'] == true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('M-Pesa Error: $e');
      return false;
    }
  }
}

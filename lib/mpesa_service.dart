import 'dart:convert';
import 'package:http/http.dart' as http;

class MpesaService {
  // Replace with your actual backend URL (e.g., your Render or Vercel URL)
  static const String baseUrl = 'https://your-backend-api.com';

  static Future<bool> initiateStkPush({
    required String phone,
    required double amount,
    required String accountReference,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/mpesa/stk-push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'amount': amount.toInt(),
          'accountReference': accountReference,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Returns true if the STK push request was successfully sent to the user's phone
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('M-Pesa Error: $e');
      return false;
    }
  }
}

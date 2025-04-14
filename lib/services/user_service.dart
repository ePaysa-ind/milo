import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const String _userIdKey = 'user_id_key';

  // Get the user ID, creating a new one if it doesn't exist
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if we already have a user ID
    String? userId = prefs.getString(_userIdKey);

    if (userId == null) {
      // Create a new user ID
      userId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      // Save it for future use
      await prefs.setString(_userIdKey, userId);
    }

    return userId;
  }
}
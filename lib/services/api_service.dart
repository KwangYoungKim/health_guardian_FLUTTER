import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String id;
  final String nickname;
  final String pin;

  AppUser({required this.id, required this.nickname, required this.pin});

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'],
      nickname: json['nickname'],
      pin: json['pin'],
    );
  }
}

class ApiService {
  static const String baseUrl = 'http://116.123.208.138:8099/api';
  static const String uploadUrl = 'http://116.123.208.138:8099/api/upload';

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_user_id');
  }

  static Future<AppUser?> login(String nickname, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': nickname, 'pin': pin}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final user = AppUser.fromJson(data);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('api_user_id', user.id);
        await prefs.setString('api_nickname', user.nickname);
        await prefs.setString('api_pin', user.pin);
        return user;
      }
    } catch (e) {
      print('Login error: $e');
    }
    return null;
  }

  static Future<bool> register(String id, String nickname, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'nickname': nickname, 'pin': pin}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Register error: $e');
    }
    return false;
  }

  static Future<bool> syncAlarms(String userId, List<Map<String, dynamic>> alarms) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/alarms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(alarms),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getAlarms(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/alarms'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getAlarms error: $e');
    }
    return [];
  }

  static Future<bool> syncRichMemos(String userId, List<Map<String, dynamic>> memos) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/richmemos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(memos),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getRichMemos(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/richmemos'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getRichMemos error: $e');
    }
    return [];
  }

  static Future<bool> syncSteps(String userId, List<Map<String, dynamic>> steps) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/steps'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(steps),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getSteps(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/steps'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getSteps error: $e');
    }
    return [];
  }

  static Future<bool> syncPaths(String userId, List<Map<String, dynamic>> paths) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/paths'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(paths),
      );
      print("syncPaths status: ${res.statusCode}, body: ${res.body}");
      return res.statusCode == 200;
    } catch (e) {
      print("syncPaths exception: $e");
      return false;
    }
  }

  static Future<List<dynamic>> getPaths(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/paths'));
      print("getPaths status: ${res.statusCode}, body: ${res.body}");
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getPaths error: $e');
    }
    return [];
  }

  static Future<bool> syncMedications(String userId, List<Map<String, dynamic>> items, List<Map<String, dynamic>> logs) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/medications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'items': items, 'logs': logs}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getMedications(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/medications'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getMedications error: $e');
    }
    return null;
  }

  static Future<bool> syncHospitals(String userId, List<Map<String, dynamic>> hospitals) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/hospitals'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(hospitals),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getHospitals(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/hospitals'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getHospitals error: $e');
    }
    return [];
  }

  static Future<bool> syncMemos(String userId, List<Map<String, dynamic>> memos) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sync/$userId/memos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(memos),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getMemos(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sync/$userId/memos'));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      print('getMemos error: $e');
    }
    return [];
  }

  static Future<bool> uploadImage(String nickname, File imageFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$uploadUrl/$nickname'));
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      var res = await request.send();
      return res.statusCode == 200;
    } catch (e) {
      print('uploadImage error: $e');
      return false;
    }
  }

  static Future<bool> deleteUser(String userId, String nickname) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {'Content-Type': 'application/json'},
      );
      print('deleteUser status: ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      print('deleteUser error: $e');
      return false;
    }
  }

  static Future<bool> deleteUserByNickname(String nickname) async {
    try {
      final encoded = Uri.encodeComponent(nickname.trim());
      final res = await http.delete(
        Uri.parse('$baseUrl/users/nickname/$encoded'),
        headers: {'Accept': 'application/json'},
      );
      print('deleteUserByNickname status: ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      print('deleteUserByNickname error: $e');
      return false;
    }
  }
}

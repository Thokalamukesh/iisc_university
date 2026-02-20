import 'dart:io';
import 'package:path_provider/path_provider.dart';

class TokenStorage {
  final String _fileName = "kiosk_token.txt";

  Future<String> _getFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return "${dir.path}/$_fileName";
  }

  Future<void> saveToken(String token) async {
    final filePath = await _getFilePath();
    final file = File(filePath);
    await file.writeAsString(token, flush: true);
  }

  Future<String?> loadToken() async {
    final filePath = await _getFilePath();
    final file = File(filePath);

    if (!file.existsSync()) return null;

    final token = await file.readAsString();
    if (token.trim().isEmpty) return null;

    return token;
  }

  Future<void> clear() async {
    final filePath = await _getFilePath();
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

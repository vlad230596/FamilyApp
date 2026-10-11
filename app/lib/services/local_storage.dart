import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small durable documents shared by foreground and background isolates.
class LocalStorage {
  final _storage = const FlutterSecureStorage();
  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  Future<void> delete(String key) => _storage.delete(key: key);
}

final localStorageProvider = Provider((ref) => LocalStorage());

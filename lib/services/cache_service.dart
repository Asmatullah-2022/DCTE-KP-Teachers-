import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';

/// Lightweight offline cache: stores JSON-encodable snapshots of Firestore
/// query results (curriculum, academic calendar, recently viewed documents,
/// favorites) keyed by a query signature, plus the last-synchronized time.
class CacheService {
  Box? _box;

  Future<void> init() async {
    _box = await Hive.openBox(AppConstants.boxCache);
  }

  Box get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('CacheService.init() must be called before use.');
    }
    return box;
  }

  Future<void> put(String key, dynamic jsonEncodable) async {
    await _requireBox.put(key, jsonEncode(jsonEncodable));
    await _requireBox.put(AppConstants.keyLastSyncedAt, DateTime.now().toIso8601String());
  }

  T? get<T>(String key, T Function(dynamic decoded) decode) {
    final raw = _requireBox.get(key);
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw as String));
    } catch (_) {
      return null;
    }
  }

  DateTime? get lastSyncedAt {
    final raw = _requireBox.get(AppConstants.keyLastSyncedAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw as String);
  }
}

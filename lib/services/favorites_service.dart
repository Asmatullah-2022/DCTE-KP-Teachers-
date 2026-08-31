import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';

enum FavoriteType { grade, subject, unit, document, notification }

/// Local-first favorites (no mandatory login in v1). Keys are
/// "{type}:{id}" so all favorite kinds share one box.
class FavoritesService {
  Box? _box;

  Future<void> init() async {
    _box = await Hive.openBox(AppConstants.boxFavorites);
  }

  Box get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('FavoritesService.init() must be called before use.');
    }
    return box;
  }

  String _key(FavoriteType type, String id) => '${type.name}:$id';

  bool isFavorite(FavoriteType type, String id) =>
      _requireBox.get(_key(type, id), defaultValue: false) as bool;

  Future<void> toggle(FavoriteType type, String id) async {
    final key = _key(type, id);
    final current = _requireBox.get(key, defaultValue: false) as bool;
    await _requireBox.put(key, !current);
  }

  List<String> idsFor(FavoriteType type) {
    final prefix = '${type.name}:';
    return _requireBox.keys
        .cast<String>()
        .where((k) => k.startsWith(prefix) && _requireBox.get(k) == true)
        .map((k) => k.substring(prefix.length))
        .toList();
  }
}

import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_idb_factory.dart';

/// Persists the catalog snapshot. On web this uses IndexedDB so the ~2MB blob
/// does not sit in localStorage's 5MB quota. Other platforms keep using
/// SharedPreferences. Existing localStorage copies are migrated once.
class CatalogSnapshotCache {
  static const prefsSnapshotKey = 'cp7_catalog_snapshot_v3';
  static const prefsVersionKey = 'cp7_catalog_snapshot_version_v3';
  static const _dbName = 'cp7-map';
  static const _storeName = 'catalog';
  static const _recordKey = 'snapshot_v3';

  Database? _db;

  Future<String?> read() async {
    final fromIdb = await _readIdb();
    if (fromIdb != null) return fromIdb;

    final fromPrefs = await _readPrefs();
    if (fromPrefs == null) return null;

    await _writeIdb(fromPrefs);
    if (await _readIdb() != null) {
      await _clearPrefs();
    }
    return fromPrefs;
  }

  Future<void> write(String raw) async {
    final storedInIdb = await _writeIdb(raw);
    if (storedInIdb) {
      await _clearPrefs();
      return;
    }
    await _writePrefs(raw);
  }

  Future<void> clear() async {
    await _clearIdb();
    await _clearPrefs();
  }

  Future<String?> _readIdb() async {
    try {
      final db = await _openIdb();
      if (db == null) return null;
      final txn = db.transaction(_storeName, idbModeReadOnly);
      final value = await txn.objectStore(_storeName).getObject(_recordKey);
      await txn.completed;
      return value is String && value.isNotEmpty ? value : null;
    } catch (error) {
      if (kDebugMode) print('Could not read catalog IndexedDB cache: $error');
      return null;
    }
  }

  Future<bool> _writeIdb(String raw) async {
    try {
      final db = await _openIdb();
      if (db == null) return false;
      final txn = db.transaction(_storeName, idbModeReadWrite);
      await txn.objectStore(_storeName).put(raw, _recordKey);
      await txn.completed;
      return true;
    } catch (error) {
      if (kDebugMode) print('Could not write catalog IndexedDB cache: $error');
      return false;
    }
  }

  Future<void> _clearIdb() async {
    try {
      final db = await _openIdb();
      if (db == null) return;
      final txn = db.transaction(_storeName, idbModeReadWrite);
      await txn.objectStore(_storeName).delete(_recordKey);
      await txn.completed;
    } catch (error) {
      if (kDebugMode) print('Could not clear catalog IndexedDB cache: $error');
    }
  }

  Future<Database?> _openIdb() async {
    final cached = _db;
    if (cached != null) return cached;
    final factory = catalogIdbFactory();
    if (factory == null) return null;
    final db = await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );
    _db = db;
    return db;
  }

  Future<String?> _readPrefs() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(prefsSnapshotKey);
    } catch (error) {
      if (kDebugMode) print('Could not read catalog preferences cache: $error');
      return null;
    }
  }

  Future<void> _writePrefs(String raw) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(prefsSnapshotKey, raw);
    } catch (error) {
      if (kDebugMode) {
        print('Could not write catalog preferences cache: $error');
      }
    }
  }

  Future<void> _clearPrefs() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(prefsSnapshotKey);
      await preferences.remove(prefsVersionKey);
    } catch (error) {
      if (kDebugMode) {
        print('Could not clear catalog preferences cache: $error');
      }
    }
  }
}

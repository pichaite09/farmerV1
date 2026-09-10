import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'farmer_api.dart';
import 'offline_queue.dart';
import '../models/api_models.dart';

class ApiSession extends ChangeNotifier {
  final FarmerApi api;
  final OfflineQueue offlineQueue;
  ApiUser? user;
  bool initialized = false;
  int pendingQueueCount = 0;
  int blockedQueueCount = 0;
  String? queueStatus;
  ApiSession({FarmerApi? api, OfflineQueue? offlineQueue})
    : offlineQueue = offlineQueue ?? OfflineQueue(),
      api = api ?? FarmerApi() {
    this.api.offlineQueue ??= this.offlineQueue;
    this.api.onQueued = () async {
      await _refreshQueue();
      notifyListeners();
    };
  }
  bool get isAuthenticated => api.token != null && user != null;
  Future<void> _refreshQueue() async {
    if (user == null) return;
    final entries = await offlineQueue.entriesForUser(user!.id);
    pendingQueueCount = entries.length;
    blockedQueueCount = entries.where((e) => e.status == 'blocked').length;
  }

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString('farmer_api_token');
    if (t != null) {
      api.token = t;
      try {
        user = ApiUser.fromJson(await api.me());
        api.queueUserId = user!.id;
        await syncOfflineQueue();
      } catch (_) {
        await logout();
      }
    }
    await _refreshQueue();
    initialized = true;
    notifyListeners();
  }

  Future<void> login(String e, String p) async => _save(await api.login(e, p));
  Future<void> register(String e, String p, String _) async =>
      _save(await api.register(e, p));
  Future<void> _save(Map<String, dynamic> r) async {
    api.token = r['access_token'] as String;
    user = ApiUser.fromJson(Map<String, dynamic>.from(r['user']));
    api.queueUserId = user!.id;
    final p = await SharedPreferences.getInstance();
    await p.setString('farmer_api_token', api.token!);
    await syncOfflineQueue();
    notifyListeners();
  }

  void updateUser(ApiUser value) {
    user = value;
    notifyListeners();
  }

  Future<void> syncOfflineQueue() async {
    if (user == null) return;
    queueStatus = null;
    await offlineQueue.flush(
      user!.id,
      api.replayQueued,
      isBlocked: (e) =>
          e is ApiException &&
          (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 422),
    );
    await _refreshQueue();
    notifyListeners();
  }

  Future<void> logout() async {
    if (api.token != null) {
      try {
        await api.logout();
      } catch (_) {}
    }
    api.token = null;
    api.queueUserId = null;
    user = null;
    pendingQueueCount = 0;
    blockedQueueCount = 0;
    final p = await SharedPreferences.getInstance();
    await p.remove('farmer_api_token');
    notifyListeners();
  }
}

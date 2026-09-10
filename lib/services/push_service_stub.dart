import 'farmer_api.dart';
import 'push_service_types.dart';

abstract class BrowserPushService {
  bool get supported;
  Future<PushServiceStatus> status();
  Future<PushServiceStatus> enable(FarmerApi api);
  Future<void> disable(FarmerApi api);
}

BrowserPushService createBrowserPushService() =>
    _UnsupportedBrowserPushService();

class _UnsupportedBrowserPushService implements BrowserPushService {
  @override
  bool get supported => false;

  @override
  Future<PushServiceStatus> status() async =>
      const PushServiceStatus(supported: false, enabled: false);

  @override
  Future<PushServiceStatus> enable(FarmerApi api) async =>
      throw UnsupportedError('Browser notifications are only available on web');

  @override
  Future<void> disable(FarmerApi api) async {}
}

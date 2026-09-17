import '../../../core/storage/device_id_provider.dart';
import 'models/scan_result.dart';
import 'scan_api.dart';

/// Resolves scanned codes. Thin wrapper that attaches the persisted device id
/// (for the server's `ScanEvent` audit row) so the cubit stays free of storage
/// concerns.
class ScanRepository {
  ScanRepository(this._api, this._deviceIds);

  final ScanApi _api;
  final DeviceIdProvider _deviceIds;

  Future<ScanResult> resolve(String rawCode) async {
    final deviceId = await _deviceIds.getDeviceId();
    return _api.resolve(
      rawCode: rawCode,
      deviceId: deviceId,
      scannedAtUtc: DateTime.now().toUtc(),
    );
  }
}

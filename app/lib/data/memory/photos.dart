part of 'memory_backend.dart';

/// [PhotoData] of a [MemoryChurchData].
class _MemoryPhotos implements PhotoData {
  _MemoryPhotos(this._c);

  final MemoryChurchData _c;

  @override
  Future<PhotoQuota> quota() async {
    _c._b.functionAccess(_c.churchId);
    return PhotoQuota(
      remaining: max(0, _c._b.photoLimit - (_c._b.photosUsed[_c.churchId] ?? 0)),
      limit: _c._b.photoLimit,
      platformOpen: _c._b.photoPlatformOpen,
    );
  }

  @override
  Future<List<dynamic>> recognize(String serviceType, List<PhotoInput> images) async {
    _c._rosterEditorOf(serviceType);
    if (images.any((i) => i.bytes.length > Limits.photoBytes)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.tooLarge);
    }
    if (!_c._b.photoPlatformOpen) {
      throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.platform);
    }
    final used = _c._b.photosUsed[_c.churchId] ?? 0;
    if (used >= _c._b.photoLimit) throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.church);
    _c._b.photosUsed[_c.churchId] = used + 1;
    await _c._b.recognizing;
    if (_c._b.recognizeFailure case final failure?) {
      _c._b.photosUsed[_c.churchId] = used;
      throw failure;
    }
    return _c._b.recognized;
  }

  /// A short stand-in for the backend's prompt, with what it is built from.
  @override
  Future<String> prompt(String serviceType) async {
    _c._rosterEditorOf(serviceType);
    final service = _c._b.services[_c.churchId]!.byId(serviceType)!;
    final names = [for (final m in _c._b.members[_c.churchId]!.values) m.name];
    return '把「${service.name}」的服事表照片轉成 JSON。\n${service.duties.join('、')}\n${names.join('、')}';
  }
}

part of 'memory_backend.dart';

/// [MemoryChurchData]'s church itself: its name, time zone and logo, as
/// firestore.rules lets an admin write them; closing and reopening it as
/// functions/src/church.ts does; its 首頁連結 as churchLink.ts.
mixin _MemoryChurch on _MemoryChurchBase {
  @override
  Future<void> setHomeName(String? name) async {
    _requireAdmin();
    if (name != null && (name.isEmpty || !withinTextLimit(name, TextLimits.homeName))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    await _b.write(() => _b.churches[churchId] = _b.churches[churchId]!.copyWith(homeName: () => name));
  }

  /// Its calendar's events are kept on the church's clock: unlike Google's,
  /// they do not move with it.
  @override
  Future<void> setTimeZone(ChurchTimeZone timeZone) async {
    _functionAdmin();
    _b.churches[churchId] = _b.churches[churchId]!.copyWith(timeZone: timeZone);
    _b.notify();
  }

  @override
  Future<void> uploadLogo(List<int> bytes) async {
    _requireAdmin();
    await _b.write(() {
      _b.churches[churchId] = _b.churches[churchId]!.copyWith(
        logoUrl: 'memory://logo/$churchId/${bytes.length}',
      );
    });
  }

  @override
  Future<void> deleteChurch() async {
    // Only an open church: deleting and restoring a suspended one would
    // reopen it.
    _functionAdmin();
    _b.churches[churchId] = _deleted(_b.churches[churchId]!, _b.clock());
    _b.notify();
  }

  @override
  Future<void> restoreChurch() async {
    _functionAdmin(allowClosed: true);
    final c = _b.churches[churchId]!;
    if (c.isActive) return;
    final until = c.restorableUntil;
    if (c.status != ChurchStatus.deleted || (until != null && _b.clock().isAfter(until))) {
      throw const CloudException(CloudErrorCode.churchClosed);
    }
    _b.churches[churchId] = Church(
      id: c.id,
      name: c.name,
      logoUrl: c.logoUrl,
      hasLogo: c.hasLogo,
      homeName: c.homeName,
      timeZone: c.timeZone,
    );
    _b.notify();
  }

  /// The setLinkSource function.
  Future<LinkSourceResult> _setLinkSource(String? source, int fetchMinute, {bool refresh = false}) async {
    _functionAdmin();
    final link = _b.churchLinks[churchId];
    if (link == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noLink);
    ChurchLink next(String? s, int m) =>
        ChurchLink(title: link.title, body: link.body, url: link.url, source: s, fetchMinute: m);
    if (source == null) {
      _b.churchLinks[churchId] = next(null, ChurchLink.defaultFetchMinute);
      _b.linkContents.remove(churchId);
      _b.notify();
      return const LinkSourceResult();
    }
    if (source.length > Limits.url || !ChurchLink.validUrl(source)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.notHttps);
    }
    final changed = link.source != source;
    if (!refresh) _b.churchLinks[churchId] = next(source, fetchMinute);
    if (!changed && !refresh) {
      _b.notify();
      return const LinkSourceResult();
    }
    // A new source is fetched at once; what it gives is scripted.
    _b.linkSourceFetches.add(source);
    final scripted = _b.nextLinkResult;
    _b.nextLinkResult = null;
    final answer = scripted?.content ?? _b.linkSourceAnswers[source] ?? LinkFetchError.network;
    final now = _b.clock();
    final today = _b.churches[churchId]!.timeZone.today(now).key;
    var error = scripted?.error;
    if (scripted != null && error == null && scripted.content == null) error = LinkFetchError.badFormat;
    if (answer is LinkContent && error == null && answer.date != null && answer.date != today) {
      error = LinkFetchError.notToday;
    }
    if (answer is LinkContent && scripted != null && answer.date == null && error == null) {
      error = LinkFetchError.badFormat;
    }
    final LinkSourceResult result;
    if (answer is LinkContent && error == null) {
      _b.linkContents[churchId] = LinkContent(
        source: source,
        date: answer.date ?? today,
        title: answer.title,
        body: answer.body,
        link: answer.link,
        fetchedAt: now,
      );
      result = LinkSourceResult(content: _b.linkContents[churchId]);
    } else {
      final failed = error ?? answer as LinkFetchError;
      _b.linkContents[churchId] = LinkContent(
        source: source,
        error: failed,
        errorStatus: scripted?.status,
        errorAt: now,
      );
      result = LinkSourceResult(error: failed, status: scripted?.status);
    }
    _b.notify();
    return result;
  }
}

/// [ChurchLinkData] of a [MemoryChurchData].
class _MemoryChurchLink implements ChurchLinkData {
  _MemoryChurchLink(this._c);

  final MemoryChurchData _c;

  @override
  Stream<ChurchLink?> watch() => _c._b.watch(() {
    _c._requireMember();
    return _c._b.churchLinks[_c.churchId];
  });

  @override
  Future<LinkSourceResult> save(ChurchLink? link) async {
    _c._requireAdmin();
    if (link != null &&
        (link.title.isEmpty ||
            !withinTextLimit(link.title, TextLimits.linkTitle) ||
            !withinTextLimit(link.body, TextLimits.linkBody) ||
            link.url.length > Limits.url ||
            !ChurchLink.validUrl(link.url))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    final saved = _c._b.churchLinks[_c.churchId];
    await _c._b.write(() {
      if (link == null) {
        _c._b.churchLinks.remove(_c.churchId);
        return;
      }
      // Like the merge in Firestore: the source is set by the function below.
      _c._b.churchLinks[_c.churchId] = ChurchLink(
        title: link.title,
        body: link.body,
        url: link.url,
        source: saved?.source,
        fetchMinute: saved?.fetchMinute ?? ChurchLink.defaultFetchMinute,
      );
    });
    if (link == null || !link.changesSourceOf(saved)) return const LinkSourceResult();
    return _c._setLinkSource(link.source, link.fetchMinute);
  }

  @override
  Future<LinkSourceResult> refresh() async {
    _c._functionAdmin();
    final link = _c._b.churchLinks[_c.churchId];
    if (link == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noLink);
    if (link.source == null) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.noSource);
    return _c._setLinkSource(link.source, link.fetchMinute, refresh: true);
  }

  @override
  Stream<LinkContent?> content() {
    final content = _c._b.watch(() {
      _c._requireMember();
      return _c._b.linkContents[_c.churchId];
    });
    final held = _c._b.linkContentHeld;
    if (held == null) return content;
    return Stream.fromFuture(held.future).asyncExpand((_) => content);
  }
}

/// [WebhookData] of a [MemoryChurchData].
class _MemoryWebhook implements WebhookData {
  _MemoryWebhook(this._c);

  final MemoryChurchData _c;

  @override
  Stream<WebhookSettings?> watch() => _c._b.watch(() {
    _c._requireAdmin();
    return _c._b.webhooks[_c.churchId];
  });

  @override
  Future<String?> save({
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  }) async {
    _c._functionAdmin();
    if (url == null) {
      _c._b.webhooks.remove(_c.churchId);
      _c._b.webhookSecrets.remove(_c.churchId);
      _c._b.notify();
      return null;
    }
    if (url.length > Limits.url || !ChurchLink.validUrl(url)) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.notHttps);
    }
    _checkSecret(secret);
    String? generated;
    if (secret != null) {
      _c._b.webhookSecrets[_c.churchId] = secret;
    } else if (!_c._b.webhookSecrets.containsKey(_c.churchId)) {
      generated = _c._b.newWebhookSecret();
      _c._b.webhookSecrets[_c.churchId] = generated;
    }
    _c._b.webhooks[_c.churchId] = WebhookSettings(
      url: url.trim(),
      calendar: calendar,
      roster: roster,
      lastDelivery: _c._b.webhooks[_c.churchId]?.lastDelivery,
    );
    _c._b.notify();
    return generated;
  }

  @override
  Future<String?> rotateSecret({String? secret}) async {
    _c._functionAdmin();
    if (!_c._b.webhooks.containsKey(_c.churchId)) throw const CloudException(CloudErrorCode.unknown);
    _checkSecret(secret);
    final next = secret ?? _c._b.newWebhookSecret();
    _c._b.webhookSecrets[_c.churchId] = next;
    return secret == null ? next : null;
  }

  @override
  Future<WebhookDelivery> test() async {
    _c._functionAdmin();
    final hook = _c._b.webhooks[_c.churchId];
    if (hook == null) throw const CloudException(CloudErrorCode.unknown);
    _c._b.webhookSent.add((_c.churchId, 'ping'));
    final a = _c._b.webhookAnswer;
    final delivery = WebhookDelivery(ok: a.ok, status: a.status, error: a.error, event: 'ping', at: _c._b.clock());
    _c._b.webhooks[_c.churchId] = WebhookSettings(
      url: hook.url,
      calendar: hook.calendar,
      roster: hook.roster,
      lastDelivery: delivery,
    );
    _c._b.notify();
    return delivery;
  }
}

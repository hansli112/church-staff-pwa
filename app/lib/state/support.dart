import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'providers.dart';

/// 支持平台: one-off tips and a monthly subscription, through the App Store
/// and Google Play. Nothing changes for supporters except a badge only they
/// see and a choice of app icon. Supporter status lives on this device only
/// (no backend, no Firestore): restoring purchases brings it back.
/// The web build never shows any of this.
abstract final class SupportProducts {
  static const tips = ['tip_small', 'tip_medium', 'tip_large'];
  static const subscription = 'supporter_monthly';
  static const all = {...tips, subscription};
}

class SupportItem {
  const SupportItem({required this.id, required this.title, required this.price, required this.subscription});

  final String id;
  final String title;
  final String price;
  final bool subscription;
}

enum PurchaseOutcome { thanks, pending, cancelled, failed }

abstract interface class SupportStore {
  /// Whether this platform sells anything (false on the web).
  bool get available;
  Future<List<SupportItem>> products();
  Future<void> buy(SupportItem item);
  Future<void> restore();

  /// Purchases finished, from any earlier buy or restore.
  Stream<({String productId, PurchaseOutcome outcome})> get results;
}

class NoStore implements SupportStore {
  const NoStore();

  @override
  bool get available => false;

  @override
  Future<List<SupportItem>> products() async => const [];

  @override
  Future<void> buy(SupportItem item) async {}

  @override
  Future<void> restore() async {}

  @override
  Stream<({String productId, PurchaseOutcome outcome})> get results => const Stream.empty();
}

class StoreKitPlayStore implements SupportStore {
  StoreKitPlayStore() {
    _sub = _iap.purchaseStream.listen(_onPurchases);
  }

  final _iap = InAppPurchase.instance;
  final _results = StreamController<({String productId, PurchaseOutcome outcome})>.broadcast();
  final _details = <String, ProductDetails>{};
  late final StreamSubscription<List<PurchaseDetails>> _sub;

  @override
  bool get available => !kIsWeb;

  @override
  Future<List<SupportItem>> products() async {
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(SupportProducts.all);
    _details
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
    final items = [
      for (final p in response.productDetails)
        SupportItem(id: p.id, title: p.title, price: p.price, subscription: p.id == SupportProducts.subscription),
    ]..sort((a, b) => (_details[a.id]!.rawPrice).compareTo(_details[b.id]!.rawPrice));
    return items;
  }

  @override
  Future<void> buy(SupportItem item) async {
    final details = _details[item.id];
    if (details == null) return;
    final param = PurchaseParam(productDetails: details);
    if (item.subscription) {
      await _iap.buyNonConsumable(purchaseParam: param);
    } else {
      await _iap.buyConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final outcome = switch (p.status) {
        PurchaseStatus.purchased || PurchaseStatus.restored => PurchaseOutcome.thanks,
        PurchaseStatus.pending => PurchaseOutcome.pending,
        PurchaseStatus.canceled => PurchaseOutcome.cancelled,
        PurchaseStatus.error => PurchaseOutcome.failed,
      };
      _results.add((productId: p.productID, outcome: outcome));
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  @override
  Stream<({String productId, PurchaseOutcome outcome})> get results => _results.stream;

  void dispose() {
    _sub.cancel();
    _results.close();
  }
}

/// Overridden in main() with the real store on iOS and Android.
final supportStoreProvider = Provider<SupportStore>((ref) => const NoStore());

/// Whether this device has seen an active subscription (purchased or
/// restored). Kept in local preferences only.
class Supporter extends Notifier<bool> {
  static const _key = 'supporter_since';

  @override
  bool build() {
    final store = ref.watch(supportStoreProvider);
    final sub = store.results.listen((r) {
      if (r.productId == SupportProducts.subscription && r.outcome == PurchaseOutcome.thanks) mark();
    });
    ref.onDispose(sub.cancel);
    return ref.watch(prefsProvider).getString(_key) != null;
  }

  void mark() {
    ref.read(prefsProvider).setString(_key, DateTime.now().toIso8601String());
    state = true;
  }
}

final supporterProvider = NotifierProvider<Supporter, bool>(Supporter.new);

/// The alternate app icons, bundled at build time (store rules: no
/// downloaded or user-supplied icons). `null` is the default icon.
const appIcons = <String?>[null, 'Green', 'Purple', 'Night'];

/// Switches the home-screen icon through a small platform channel: iOS
/// setAlternateIconName, Android enabling one activity-alias.
abstract interface class AppIconSwitcher {
  Future<String?> current();
  Future<void> set(String? name);
}

class ChannelIconSwitcher implements AppIconSwitcher {
  static const _channel = MethodChannel('martha/app_icon');

  @override
  Future<String?> current() => _channel.invokeMethod<String>('current');

  @override
  Future<void> set(String? name) => _channel.invokeMethod('set', name);
}

class NoIconSwitcher implements AppIconSwitcher {
  const NoIconSwitcher();

  @override
  Future<String?> current() async => null;

  @override
  Future<void> set(String? name) async {}
}

final appIconSwitcherProvider = Provider<AppIconSwitcher>((ref) => const NoIconSwitcher());

final currentAppIconProvider = FutureProvider<String?>((ref) => ref.watch(appIconSwitcherProvider).current());

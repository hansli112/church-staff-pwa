import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/backend.dart';
import 'providers.dart';

/// 支持平台: one-off tips and a monthly subscription, through the App Store
/// and Google Play. Nothing changes for supporters except a badge only they
/// see and a choice of app icon, while the subscription is paid. Supporter
/// status lives on this device only (no backend, no Firestore): restoring
/// purchases brings it back.
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

/// A finished purchase. [paidAt]: when a subscription was last paid, as far
/// as the store says; null for anything else.
typedef PurchaseResult = ({String productId, PurchaseOutcome outcome, DateTime? paidAt});

abstract interface class SupportStore {
  /// Whether this platform sells anything (false on the web).
  bool get available;
  Future<List<SupportItem>> products();
  Future<void> buy(SupportItem item);
  Future<void> restore();

  /// Asks the store, without any prompt, whether the subscription is still
  /// paid. Google Play reports it only when asked; the App Store delivers
  /// each renewal at launch by itself.
  Future<void> refresh();

  /// Purchases finished, from any earlier buy, restore or renewal.
  Stream<PurchaseResult> get results;

  /// The store's name, where people cancel the subscription.
  String get name;

  /// The store's page for managing the subscription.
  Uri get manageSubscription;
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
  Future<void> refresh() async {}

  @override
  Stream<PurchaseResult> get results => const Stream.empty();

  @override
  String get name => '';

  @override
  Uri get manageSubscription => Uri();
}

class StoreKitPlayStore implements SupportStore {
  StoreKitPlayStore() {
    _sub = _iap.purchaseStream.listen(_onPurchases);
  }

  final _iap = InAppPurchase.instance;
  final _results = StreamController<PurchaseResult>.broadcast();
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

  // Play's restore is silent and lists only subscriptions still paid.
  @override
  Future<void> refresh() async {
    if (defaultTargetPlatform == TargetPlatform.android && await _iap.isAvailable()) await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final outcome = switch (p.status) {
        PurchaseStatus.purchased || PurchaseStatus.restored => PurchaseOutcome.thanks,
        PurchaseStatus.pending => PurchaseOutcome.pending,
        PurchaseStatus.canceled => PurchaseOutcome.cancelled,
        PurchaseStatus.error => PurchaseOutcome.failed,
      };
      _results.add((productId: p.productID, outcome: outcome, paidAt: _paidAt(p)));
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  /// The App Store dates each renewal; Play dates only the first purchase,
  /// but lists a subscription only while it is paid, so now.
  static DateTime? _paidAt(PurchaseDetails p) {
    if (p.productID != SupportProducts.subscription) return null;
    final ms = int.tryParse(p.transactionDate ?? '');
    if (defaultTargetPlatform == TargetPlatform.iOS && ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now();
  }

  @override
  Stream<PurchaseResult> get results => _results.stream;

  static bool get _apple => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  String get name => _apple ? 'App Store' : 'Google Play';

  @override
  Uri get manageSubscription => _apple
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.https('play.google.com', '/store/account/subscriptions', {
          'sku': SupportProducts.subscription,
          'package': 'app.marthasit',
        });

  void dispose() {
    _sub.cancel();
    _results.close();
  }
}

/// Overridden in main() with the real store on iOS and Android.
final supportStoreProvider = Provider<SupportStore>((ref) => const NoStore());

/// Whether the website's support page takes payments (NewebPay), so the web
/// app, which sells nothing itself, can send people there. The same switch
/// as the website's: `SUPPORT_PAYMENTS=on scripts/deploy.sh …` builds both.
final sitePaymentsProvider = Provider<bool>((ref) => const String.fromEnvironment('SUPPORT_PAYMENTS') == 'on');

/// Whether the subscription is paid: until a month and a few days after
/// the store last said so (a purchase, a restore, a renewal). Kept in local
/// preferences only. Once lapsed, the badge goes and the icon is the default
/// again (sessionEffectsProvider).
class Supporter extends Notifier<bool> {
  static const _key = 'supporter_until';

  /// A month, and a few days for the store's renewal to come in.
  static const paidFor = Duration(days: 35);

  @override
  bool build() {
    final store = ref.watch(supportStoreProvider);
    final sub = store.results.listen((r) {
      if (r.productId == SupportProducts.subscription && r.outcome == PurchaseOutcome.thanks) {
        _paid(r.paidAt ?? ref.read(clockProvider)());
      }
    });
    ref.onDispose(sub.cancel);
    final until = DateTime.tryParse(ref.watch(prefsProvider).getString(_key) ?? '');
    // Only someone who has subscribed has anything to ask the store about.
    if (until != null) unawaited(store.refresh());
    return until != null && ref.read(clockProvider)().isBefore(until);
  }

  /// Paid on [at]: good until [paidFor] later, unless already longer.
  void _paid(DateTime at) {
    final prefs = ref.read(prefsProvider);
    final known = DateTime.tryParse(prefs.getString(_key) ?? '');
    var until = at.add(paidFor);
    if (known != null && known.isAfter(until)) until = known;
    prefs.setString(_key, until.toIso8601String());
    state = ref.read(clockProvider)().isBefore(until);
  }
}

final supporterProvider = NotifierProvider<Supporter, bool>(Supporter.new);

/// 雲端費用進度, live: everyone sees a payment as soon as the store reports it.
final fundingProvider = StreamProvider.autoDispose<Funding?>((ref) => ref.watch(backendProvider).platform.funding());

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

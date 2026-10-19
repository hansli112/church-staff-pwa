import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../data/backend.dart';
import 'providers.dart';

/// 支持平台: one-off tips and two monthly plans, through the App Store and
/// Google Play. Nothing changes for supporters except a badge only they see
/// and a choice of app icon, while a plan is paid; both plans give the same.
/// Supporter status lives on this device only (no backend, no Firestore):
/// restoring purchases brings it back.
/// The web build never shows any of this.
abstract final class SupportProducts {
  static const tips = ['tip_small', 'tip_medium', 'tip_large'];

  /// The monthly plans, cheapest first, in one subscription group: taking
  /// one replaces the other.
  static const plans = ['supporter_monthly', 'supporter_monthly_plus'];
  static const all = {...tips, ...plans};
}

class SupportItem {
  const SupportItem({required this.id, required this.price, required this.subscription});

  final String id;
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

  /// What the store sells; none until the products are set up there.
  /// Throws when the store can't be reached.
  Future<List<SupportItem>> products();
  Future<void> buy(SupportItem item);
  Future<void> restore();

  /// Asks the store, without any prompt, whether a plan is still
  /// paid. Google Play reports it only when asked; the App Store delivers
  /// each renewal at launch by itself.
  Future<void> refresh();

  /// Purchases finished, from any earlier buy, restore or renewal.
  Stream<PurchaseResult> get results;

  /// The store's name, where people cancel the subscription.
  String get name;

  /// The store's page for managing [plan].
  Uri manageSubscription(String plan);
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
  Uri manageSubscription(String plan) => Uri();
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
    // Can't reach the store: an error. Reached, with nothing on sale yet: none.
    // Google Play's plugin drops a failed query's code, so offline there can
    // look like nothing on sale.
    if (!await _iap.isAvailable()) throw StateError('The store is unavailable');
    final response = await _iap.queryProductDetails(SupportProducts.all);
    if (response.error case final error? when response.productDetails.isEmpty) throw error;
    _details
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
    final items = [
      for (final p in response.productDetails)
        SupportItem(id: p.id, price: p.price, subscription: SupportProducts.plans.contains(p.id)),
    ]..sort((a, b) => (_details[a.id]!.rawPrice).compareTo(_details[b.id]!.rawPrice));
    return items;
  }

  @override
  Future<void> buy(SupportItem item) async {
    final details = _details[item.id];
    if (details == null) return;
    final param = PurchaseParam(productDetails: details);
    if (item.subscription) {
      // Play: another plan replaces the paid one, the time left credited,
      // rather than being a second subscription. The App Store does the
      // same by itself within the subscription group.
      final old = await _paidPlayPlan(other: item.id);
      await _iap.buyNonConsumable(
        purchaseParam: old != null && old.productID != item.id
            ? GooglePlayPurchaseParam(
                productDetails: details,
                changeSubscriptionParam: ChangeSubscriptionParam(
                  oldPurchaseDetails: old,
                  replacementMode: ReplacementMode.withTimeProration,
                ),
              )
            : param,
      );
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

  /// The plan other than [other] that Google Play says is paid, asked then:
  /// a reinstalled app may not have heard from Play yet. None on iOS.
  Future<GooglePlayPurchaseDetails?> _paidPlayPlan({required String other}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final owned = await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().queryPastPurchases();
    return owned.pastPurchases
        .where((p) => p.productID != other && SupportProducts.plans.contains(p.productID))
        .firstOrNull;
  }

  /// The App Store dates each renewal; Play dates only the first purchase,
  /// but lists a subscription only while it is paid, so now.
  static DateTime? _paidAt(PurchaseDetails p) {
    if (!SupportProducts.plans.contains(p.productID)) return null;
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
  Uri manageSubscription(String plan) => _apple
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.https('play.google.com', '/store/account/subscriptions', {
          'sku': plan,
          'package': 'app.marthasit',
        });

  void dispose() {
    _sub.cancel();
    _results.close();
  }
}

/// Overridden in main() with the real store on iOS and Android.
final supportStoreProvider = Provider<SupportStore>((ref) => const NoStore());

/// Whether the website's support page takes payments (ECPay), so the web
/// app, which sells nothing itself, can send people there. The same switch
/// as the website's: `SUPPORT_PAYMENTS=on scripts/deploy.sh …` builds both.
final sitePaymentsProvider = Provider<bool>((ref) => const String.fromEnvironment('SUPPORT_PAYMENTS') == 'on');

/// The plan paid for, if any: until a month and a few days after the store
/// last said so (a purchase, a restore, a renewal). Kept in local
/// preferences only. Once lapsed, the badge goes and the icon is the default
/// again (sessionEffectsProvider).
class Supporter extends Notifier<String?> {
  static const _key = 'supporter_until';
  static const _planKey = 'supporter_plan';

  /// A month, and a few days for the store's renewal to come in.
  static const paidFor = Duration(days: 35);

  @override
  String? build() {
    final store = ref.watch(supportStoreProvider);
    final sub = store.results.listen((r) {
      if (SupportProducts.plans.contains(r.productId) && r.outcome == PurchaseOutcome.thanks) {
        _paid(r.productId, r.paidAt ?? ref.read(clockProvider)());
      }
    });
    ref.onDispose(sub.cancel);
    final prefs = ref.watch(prefsProvider);
    final until = DateTime.tryParse(prefs.getString(_key) ?? '');
    // Only someone who has subscribed has anything to ask the store about.
    if (until != null) unawaited(store.refresh());
    return until != null && ref.read(clockProvider)().isBefore(until) ? _plan(prefs.getString(_planKey)) : null;
  }

  /// One of [SupportProducts.plans]; the first for anything else.
  static String _plan(String? id) => SupportProducts.plans.contains(id) ? id! : SupportProducts.plans.first;

  /// [plan] paid on [at]: good until [paidFor] later, unless already longer.
  void _paid(String plan, DateTime at) {
    final prefs = ref.read(prefsProvider);
    final known = DateTime.tryParse(prefs.getString(_key) ?? '');
    var until = at.add(paidFor);
    if (known != null && known.isAfter(until)) {
      until = known;
    } else {
      prefs.setString(_planKey, plan);
    }
    prefs.setString(_key, until.toIso8601String());
    state = ref.read(clockProvider)().isBefore(until) ? _plan(prefs.getString(_planKey)) : null;
  }
}

final supporterPlanProvider = NotifierProvider<Supporter, String?>(Supporter.new);

/// Whether a plan is paid.
final supporterProvider = Provider<bool>((ref) => ref.watch(supporterPlanProvider) != null);

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

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:martha/state/support.dart';

void main() {
  test("Google Play's titles end with the app's name; the support page shows the product's own name", () {
    const play = ProductDetailsWrapper(
      productId: 'tip_small',
      productType: ProductType.inapp,
      name: '小額支持',
      title: '小額支持 (馬大別忙 Martha, sit：專為教會打造的服事 App)',
      description: '',
      oneTimePurchaseOfferDetails: OneTimePurchaseOfferDetailsWrapper(
        formattedPrice: r'NT$50.00',
        priceAmountMicros: 50000000,
        priceCurrencyCode: 'TWD',
      ),
    );
    expect(storeTitle(GooglePlayProductDetails.fromProductDetails(play).single), '小額支持');
  });

  test("the App Store's title is already the product's name", () {
    final apple = ProductDetails(
      id: 'tip_small',
      title: '小額支持',
      description: '',
      price: r'NT$50',
      rawPrice: 50,
      currencyCode: 'TWD',
    );
    expect(storeTitle(apple), '小額支持');
  });
}

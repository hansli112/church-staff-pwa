import 'package:church_staff_pwa/core/services/install_hint_service.dart';
import 'package:church_staff_pwa/features/dashboard/presentation/widgets/add_to_home_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHints extends InstallHintService {
  _FakeHints(this.hint, {this.accept = true});

  InstallHint hint;
  final bool accept;
  int prompts = 0;

  @override
  InstallHint read() => hint;

  @override
  Future<bool> prompt() async {
    prompts += 1;
    return accept;
  }
}

InstallHint _hint(
  InstallPlatform platform, {
  bool standalone = false,
  bool canPrompt = false,
}) => InstallHint(
  platform: platform,
  isStandalone: standalone,
  canPrompt: canPrompt,
);

Future<void> _pump(WidgetTester tester, InstallHintService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AddToHomeCard(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('iPhone 在瀏覽器裡：教他用 Safari 加入主畫面，沒有安裝按鈕', (tester) async {
    await _pump(tester, _FakeHints(_hint(InstallPlatform.ios)));
    expect(find.text('加到手機主畫面'), findsOneWidget);
    expect(find.textContaining('加入主畫面'), findsOneWidget);
    expect(find.text('安裝到手機'), findsNothing);
  });

  testWidgets('Android 有 beforeinstallprompt：按安裝，接受後卡片消失', (tester) async {
    final hints = _FakeHints(_hint(InstallPlatform.android, canPrompt: true));
    await _pump(tester, hints);
    await tester.tap(find.text('安裝到手機'));
    await tester.pumpAndSettle();
    expect(hints.prompts, 1);
    expect(find.text('加到手機主畫面'), findsNothing);
  });

  testWidgets('Android 按了安裝又取消：卡片留著', (tester) async {
    final hints = _FakeHints(
      _hint(InstallPlatform.android, canPrompt: true),
      accept: false,
    );
    await _pump(tester, hints);
    await tester.tap(find.text('安裝到手機'));
    await tester.pumpAndSettle();
    expect(find.text('加到手機主畫面'), findsOneWidget);
  });

  testWidgets('Android 沒有安裝事件：改教他用 Chrome 選單', (tester) async {
    await _pump(tester, _FakeHints(_hint(InstallPlatform.android)));
    expect(find.textContaining('右上角的「⋮」'), findsOneWidget);
    expect(find.text('安裝到手機'), findsNothing);
  });

  testWidgets('已經從主畫面打開、或是桌機：不顯示', (tester) async {
    await _pump(
      tester,
      _FakeHints(_hint(InstallPlatform.ios, standalone: true)),
    );
    expect(find.text('加到手機主畫面'), findsNothing);
    await _pump(tester, _FakeHints(_hint(InstallPlatform.other)));
    expect(find.text('加到手機主畫面'), findsNothing);
  });

  testWidgets('按「不用了」之後，這台裝置就不再提醒', (tester) async {
    final hints = _FakeHints(_hint(InstallPlatform.ios));
    await _pump(tester, hints);
    await tester.tap(find.text('不用了'));
    await tester.pumpAndSettle();
    expect(find.text('加到手機主畫面'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AddToHomeCard.dismissedKey), isTrue);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, hints);
    expect(find.text('加到手機主畫面'), findsNothing);
  });
}

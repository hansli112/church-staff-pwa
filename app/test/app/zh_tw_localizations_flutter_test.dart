import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/zh_tw_localizations.dart';

// Next to Flutter's own delegates, which load every locale's date data: kept
// apart from zh_tw_localizations_test.dart, whose date checks need it absent.

const _zhTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

/// Ours for [T], loaded for zh-TW.
Future<T> _load<T>() async {
  final delegate = zhTwLocalizationsDelegates.whereType<LocalizationsDelegate<T>>().single;
  expect(delegate.isSupported(_zhTw), isTrue);
  return delegate.load(_zhTw);
}

void main() {
  test('Flutter’s own labels are its Traditional Chinese (Taiwan) ones', () async {
    final material = await _load<MaterialLocalizations>();
    final flutterMaterial = await GlobalMaterialLocalizations.delegate.load(_zhTw);
    expect(material.runtimeType, flutterMaterial.runtimeType);
    for (final (a, b) in [
      (material.okButtonLabel, flutterMaterial.okButtonLabel),
      (material.cancelButtonLabel, flutterMaterial.cancelButtonLabel),
      (material.backButtonTooltip, flutterMaterial.backButtonTooltip),
      (material.closeButtonTooltip, flutterMaterial.closeButtonTooltip),
      (material.datePickerHelpText, flutterMaterial.datePickerHelpText),
      (material.timePickerDialHelpText, flutterMaterial.timePickerDialHelpText),
      (material.searchFieldLabel, flutterMaterial.searchFieldLabel),
      (material.copyButtonLabel, flutterMaterial.copyButtonLabel),
      (material.pasteButtonLabel, flutterMaterial.pasteButtonLabel),
    ]) {
      expect(a, b);
    }
    expect(material.narrowWeekdays, flutterMaterial.narrowWeekdays);
    expect(material.firstDayOfWeekIndex, flutterMaterial.firstDayOfWeekIndex);
    expect(
      material.formatTimeOfDay(const TimeOfDay(hour: 14, minute: 5)),
      flutterMaterial.formatTimeOfDay(const TimeOfDay(hour: 14, minute: 5)),
    );
    expect(material.formatDecimal(1234), flutterMaterial.formatDecimal(1234));

    final cupertino = await _load<CupertinoLocalizations>();
    final flutterCupertino = await GlobalCupertinoLocalizations.delegate.load(_zhTw);
    expect(cupertino.runtimeType, flutterCupertino.runtimeType);
    expect(cupertino.alertDialogLabel, flutterCupertino.alertDialogLabel);
    expect(cupertino.todayLabel, flutterCupertino.todayLabel);
    expect(cupertino.datePickerHourSemanticsLabel(9), flutterCupertino.datePickerHourSemanticsLabel(9));

    final widgets = await _load<WidgetsLocalizations>();
    final flutterWidgets = await GlobalWidgetsLocalizations.delegate.load(_zhTw);
    expect(widgets.runtimeType, flutterWidgets.runtimeType);
    expect(widgets.textDirection, TextDirection.ltr);
    expect(widgets.reorderItemUp, flutterWidgets.reorderItemUp);
  });
}

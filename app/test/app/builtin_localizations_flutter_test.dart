import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/builtin_localizations.dart';
import 'package:martha/core/languages.dart';

// Next to Flutter's own delegates, which load every locale's date data: kept
// apart from builtin_localizations_test.dart, whose date checks need it absent.

/// Ours for [T], loaded for [locale].
Future<T> _load<T>(Locale locale) async {
  final delegate = builtinLocalizationsDelegates.whereType<LocalizationsDelegate<T>>().single;
  expect(delegate.isSupported(locale), isTrue);
  return delegate.load(locale);
}

void main() {
  for (final language in AppLanguage.values) {
    final locale = language.locale;
    test('Flutter’s own labels in $locale are its own', () async {
      final material = await _load<MaterialLocalizations>(locale);
      final flutterMaterial = await GlobalMaterialLocalizations.delegate.load(locale);
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

      final cupertino = await _load<CupertinoLocalizations>(locale);
      final flutterCupertino = await GlobalCupertinoLocalizations.delegate.load(locale);
      expect(cupertino.runtimeType, flutterCupertino.runtimeType);
      expect(cupertino.alertDialogLabel, flutterCupertino.alertDialogLabel);
      expect(cupertino.todayLabel, flutterCupertino.todayLabel);
      expect(cupertino.datePickerHourSemanticsLabel(9), flutterCupertino.datePickerHourSemanticsLabel(9));

      final widgets = await _load<WidgetsLocalizations>(locale);
      final flutterWidgets = await GlobalWidgetsLocalizations.delegate.load(locale);
      expect(widgets.runtimeType, flutterWidgets.runtimeType);
      expect(widgets.textDirection, TextDirection.ltr);
      expect(widgets.reorderItemUp, flutterWidgets.reorderItemUp);
    });
  }
}

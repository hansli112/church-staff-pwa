import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import 'calendar_screen.dart';

final _calendarListProvider = FutureProvider.autoDispose<List<CalendarChoice>>(
  (ref) => openChurch(ref).calendarList(),
);

/// Says so when the picked calendar keeps another time zone than the
/// church's: its times look different in Google Calendar than here.
String? _timeZoneDiffers(L10n l10n, String? calendarTimeZone, ChurchTimeZone church) {
  if (calendarTimeZone == null || calendarTimeZone == church.id) return null;
  final known = ChurchTimeZone.byId(calendarTimeZone);
  // Another name for the same clock, winter and summer (Taipei and Hong Kong).
  final sameClock =
      known != null &&
      [DateTime.utc(2026), DateTime.utc(2026, 7)].every((t) => known.offsetAt(t) == church.offsetAt(t));
  if (sameClock) return null;
  return l10n.calendarTimeZoneDiffers(
    known == null ? calendarTimeZone : timeZoneCity(l10n, known),
    timeZoneCity(l10n, church),
  );
}

/// Admins connect the church's Google Calendar here and pick which calendar
/// it shows. The consent screen opens in a browser sheet over the phone app
/// (the web app's own tab on the web); the backend stores the grant and this
/// page updates when it arrives, closing the sheet where the phone lets it
/// (iOS; on Android its last page says to close it).
class CalendarSettingsScreen extends ConsumerWidget {
  const CalendarSettingsScreen({super.key, this.result});

  /// `connected`, `denied`, `expired`, … when the OAuth redirect lands here.
  final String? result;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    try {
      final url = await ref.churchData.calendarAuthUrl();
      await launchUrl(
        url,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final settings = ref.watch(calendarSettingsProvider).value;
    ref.listen(calendarSettingsProvider, (before, now) {
      final was = before?.value;
      // Only a change seen here: not the settings arriving as the page opens.
      if (!kIsWeb && was != null && !was.usable && (now.value?.usable ?? false)) closeInAppWebView();
    });
    final church = ref.watch(churchDataProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendarSetting)),
      body: ListView(
        children: [
          if (result != null && result != 'connected')
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: BalancedText(
                result == 'scopes' ? l10n.calConnectScopes : l10n.calConnectFailed,
                textAlign: TextAlign.start,
                style: AppText.subheadline.copyWith(color: c.destructive),
              ),
            ),
          if (settings == null || !settings.usable)
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BalancedText(
                    l10n.calUnverifiedNote,
                    textAlign: TextAlign.start,
                    style: AppText.subheadline.copyWith(color: c.secondaryLabel),
                  ),
                  const SizedBox(height: Space.m),
                  PrimaryButton(
                    label: settings?.needsReconnect ?? false ? l10n.calReconnect : l10n.calConnect,
                    onPressed: () => _connect(context, ref),
                  ),
                ],
              ),
            )
          else ...[
            Consumer(
              builder: (context, ref, _) {
                final list = ref.watch(_calendarListProvider);
                return list.when(
                  // The first call after a while can wait on a cold start.
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Space.xl),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  ),
                  error: (e, _) =>
                      ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(_calendarListProvider)),
                  data: (calendars) => ListSection(
                    header: l10n.calPickCalendar,
                    footer: _timeZoneDiffers(
                      l10n,
                      calendars.where((cal) => cal.id == settings.calendarId).firstOrNull?.timeZone,
                      ref.watch(churchTimeZoneProvider),
                    ),
                    children: [
                      for (final cal in calendars)
                        ListRow(
                          title: cal.name,
                          selected: settings.calendarName == cal.name,
                          onTap: () => church!.calendarSelect(cal.id, cal.name),
                        ),
                    ],
                  ),
                );
              },
            ),
            ListSection(
              children: [
                ListRow(
                  title: l10n.calDisconnect,
                  destructive: true,
                  onTap: () async {
                    final ok = await confirmDestructive(
                      context,
                      title: l10n.calDisconnectTitle,
                      message: l10n.calDisconnectBody,
                      action: l10n.calDisconnect,
                    );
                    if (ok) await church!.calendarDisconnect();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

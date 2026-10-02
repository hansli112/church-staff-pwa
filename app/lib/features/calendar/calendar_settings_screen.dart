import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'calendar_screen.dart';

final _calendarListProvider = FutureProvider.autoDispose<List<({String id, String name})>>((ref) {
  final cid = ref.watch(currentChurchIdProvider)!;
  return ref.watch(backendProvider).cloud.calendarList(cid);
});

/// Admins connect the church's Google Calendar here and pick which calendar
/// it shows. The consent screen opens in the browser; the backend stores the
/// grant and this page updates when it arrives.
class CalendarSettingsScreen extends ConsumerWidget {
  const CalendarSettingsScreen({super.key, this.result});

  /// `connected`, `denied`, `expired`, … when the OAuth redirect lands here.
  final String? result;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    try {
      final url = await ref.read(backendProvider).cloud.calendarAuthUrl(ref.read(currentChurchIdProvider)!);
      await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_self');
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final settings = ref.watch(calendarSettingsProvider).value;
    final cid = ref.watch(currentChurchIdProvider);
    final cloud = ref.read(backendProvider).cloud;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendarSetting)),
      body: ListView(
        children: [
          if (result != null && result != 'connected')
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Text(l10n.calConnectFailed, style: AppText.subheadline.copyWith(color: c.destructive)),
            ),
          if (settings == null || !settings.connected || settings.needsReconnect)
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.calUnverifiedNote, style: AppText.subheadline.copyWith(color: c.secondaryLabel)),
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
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) =>
                      ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(_calendarListProvider)),
                  data: (calendars) => ListSection(
                    header: l10n.calPickCalendar,
                    children: [
                      for (final cal in calendars)
                        ListRow(
                          title: cal.name,
                          selected: settings.calendarName == cal.name,
                          onTap: () => cloud.calendarSelect(cid!, cal.id, cal.name),
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
                    if (ok) await cloud.calendarDisconnect(cid!);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/links.dart';
import '../common/errors.dart';
import 'services_screen.dart' show promptText;

final webhookProvider = StreamProvider.autoDispose<WebhookSettings?>((ref) => ref.watch(churchDataProvider)!.webhook());

/// 外部通知: admins point the church's webhook at an https URL (e.g. n8n),
/// pick which changes it reports, send a test and see how the last notice
/// went. The secret is shown once, when it is made.
class WebhookScreen extends ConsumerWidget {
  const WebhookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final hook = ref.watch(webhookProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.webhook)),
      body: switch (hook) {
        AsyncData(value: null) => const _Setup(),
        AsyncData(:final value?) => _Configured(hook: value),
        AsyncError() => ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(webhookProvider)),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// Shows a new secret once, with a way to copy it.
Future<void> _showSecret(BuildContext context, String secret) {
  final l10n = L10n.of(context);
  return showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.webhookSecretTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(secret, style: AppText.body.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: Space.s),
          Text(l10n.webhookSecretOnce, style: AppText.footnote),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => copyText(context, secret, copied: l10n.webhookSecretCopied),
          child: Text(l10n.webhookCopySecret),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.done)),
      ],
    ),
  );
}

/// First time: URL, an optional secret, which events.
class _Setup extends ConsumerStatefulWidget {
  const _Setup();

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  final _url = TextEditingController(text: 'https://');
  final _secret = TextEditingController();
  bool _calendar = true;
  bool _roster = true;
  bool _tried = false;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  String? get _urlError => ChurchLink.validUrl(_url.text) ? null : L10n.of(context).webhookNeedsHttps;
  String? get _secretError {
    final s = _secret.text.trim();
    return s.isEmpty || s.length >= 16 ? null : L10n.of(context).webhookSecretTooShort;
  }

  Future<void> _save() async {
    final l10n = L10n.of(context);
    setState(() => _tried = true);
    if (_urlError != null || _secretError != null) return;
    setState(() => _busy = true);
    try {
      final secret = _secret.text.trim();
      final generated = await ref
          .read(backendProvider)
          .cloud
          .webhookSave(
            ref.read(currentChurchIdProvider)!,
            url: _url.text.trim(),
            calendar: _calendar,
            roster: _roster,
            secret: secret.isEmpty ? null : secret,
          );
      Haptics.success();
      if (generated != null && mounted) await _showSecret(context, generated);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.webhookUrl, errorText: _tried ? _urlError : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.s),
              TextField(
                controller: _secret,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.webhookSecretOptional,
                  errorText: _tried ? _secretError : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.s),
              Text(l10n.webhookFooter, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
            ],
          ),
        ),
        ListSection(
          children: [
            SwitchRow(
              title: l10n.webhookCalendar,
              subtitle: l10n.webhookCalendarHint,
              value: _calendar,
              onChanged: (v) => setState(() => _calendar = v),
            ),
            SwitchRow(
              title: l10n.webhookRoster,
              subtitle: l10n.webhookRosterHint,
              value: _roster,
              onChanged: (v) => setState(() => _roster = v),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(Space.m),
          child: PrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
        ),
      ],
    );
  }
}

/// Set up: the URL, the two switches, a test, the secret, turning it off.
class _Configured extends ConsumerStatefulWidget {
  const _Configured({required this.hook});

  final WebhookSettings hook;

  @override
  ConsumerState<_Configured> createState() => _ConfiguredState();
}

class _ConfiguredState extends ConsumerState<_Configured> {
  bool _testing = false;

  String get _cid => ref.read(currentChurchIdProvider)!;

  Future<void> _save({String? url, bool? calendar, bool? roster}) async {
    final l10n = L10n.of(context);
    try {
      await ref
          .read(backendProvider)
          .cloud
          .webhookSave(
            _cid,
            url: url ?? widget.hook.url,
            calendar: calendar ?? widget.hook.calendar,
            roster: roster ?? widget.hook.roster,
          );
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  Future<void> _editUrl() async {
    final l10n = L10n.of(context);
    final url = await promptText(context, title: l10n.webhookUrl, hint: 'https://', initial: widget.hook.url);
    if (url == null || url == widget.hook.url || !mounted) return;
    if (!ChurchLink.validUrl(url)) {
      showToast(context, l10n.webhookNeedsHttps);
      return;
    }
    await _save(url: url);
  }

  Future<void> _test() async {
    final l10n = L10n.of(context);
    setState(() => _testing = true);
    try {
      final r = await ref.read(backendProvider).cloud.webhookTest(_cid);
      if (mounted) showToast(context, deliveryText(l10n, r));
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _rotate() async {
    final l10n = L10n.of(context);
    final generate = await askChoice(
      context,
      title: l10n.webhookRotate,
      message: l10n.webhookRotateMessage,
      yes: l10n.webhookGenerate,
      no: l10n.webhookTypeOwn,
    );
    if (generate == null || !mounted) return;
    String? typed;
    if (!generate) {
      typed = await promptText(context, title: l10n.webhookSecretTitle, hint: l10n.webhookSecretTooShort);
      if (typed == null || !mounted) return;
      if (typed.length < 16) {
        showToast(context, l10n.webhookSecretTooShort);
        return;
      }
    }
    try {
      final secret = await ref.read(backendProvider).cloud.webhookRotateSecret(_cid, secret: typed);
      if (!mounted) return;
      if (secret != null) {
        await _showSecret(context, secret);
      } else {
        showToast(context, l10n.webhookSecretChanged);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  Future<void> _turnOff() async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.webhookOffTitle,
      message: l10n.webhookOffMessage,
      action: l10n.webhookOffAction,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(backendProvider).cloud.webhookSave(_cid, url: null);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final hook = widget.hook;
    final last = hook.lastDelivery;
    return ListView(
      children: [
        ListSection(
          footer: l10n.webhookFooter,
          children: [ListRow(title: l10n.webhookUrl, subtitle: displayUrl(hook.url), onTap: _editUrl)],
        ),
        ListSection(
          children: [
            SwitchRow(
              title: l10n.webhookCalendar,
              subtitle: l10n.webhookCalendarHint,
              value: hook.calendar,
              onChanged: (v) => _save(calendar: v),
            ),
            SwitchRow(
              title: l10n.webhookRoster,
              subtitle: l10n.webhookRosterHint,
              value: hook.roster,
              onChanged: (v) => _save(roster: v),
            ),
          ],
        ),
        ListSection(
          footer: last?.at == null
              ? null
              : l10n.webhookLast(DateFormat('M/d HH:mm').format(last!.at!), deliveryText(l10n, last)),
          children: [
            ListRow(
              title: l10n.webhookTest,
              trailing: _testing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _testing ? null : _test,
            ),
            ListRow(title: l10n.webhookRotate, onTap: _rotate),
          ],
        ),
        ListSection(
          children: [ListRow(title: l10n.webhookOff, destructive: true, onTap: _turnOff)],
        ),
      ],
    );
  }
}

/// 成功, 對方回應 500, 逾時 or 連不上.
String deliveryText(L10n l10n, WebhookDelivery d) {
  if (d.ok) return l10n.webhookOk;
  return switch (d.error) {
    WebhookDeliveryError.timeout => l10n.webhookTimeout,
    WebhookDeliveryError.network => l10n.webhookNetwork,
    _ => l10n.webhookHttp('${d.status ?? ''}'),
  };
}

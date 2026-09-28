import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/install_hint_service.dart';

/// 提醒還在瀏覽器裡用的同工把網站加到手機主畫面。
///
/// 沒加的話每次都要找那則 LINE 訊息、關掉分頁常常就登出了，同工只會覺得
/// 「這個 App 很難用」。按「不用了」之後這台裝置就不再提醒。
class AddToHomeCard extends StatefulWidget {
  const AddToHomeCard({super.key, this.service = const InstallHintService()});

  final InstallHintService service;

  static const dismissedKey = 'add_to_home_dismissed';

  @override
  State<AddToHomeCard> createState() => _AddToHomeCardState();
}

class _AddToHomeCardState extends State<AddToHomeCard> {
  // 讀到 SharedPreferences 之前先不顯示，免得已經按過「不用了」的人看到閃一下。
  bool _dismissed = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _dismissed = prefs.getBool(AddToHomeCard.dismissedKey) ?? false,
    );
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AddToHomeCard.dismissedKey, true);
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    final accepted = await widget.service.prompt();
    if (!mounted) return;
    setState(() {
      _installing = false;
      // 裝好了就不用再提醒；按了取消就留著卡片，說明文字還是有用。
      if (accepted) _dismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.service.read();
    if (_dismissed || !hint.shouldSuggest) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final canInstall =
        hint.platform == InstallPlatform.android && hint.canPrompt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.add_to_home_screen,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '把這個網站加到手機桌面',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('桌面會多一個圖示，之後點一下就能打開，不用再去 LINE 找連結。'),
              const SizedBox(height: 12),
              if (canInstall)
                const Text('按下面的「安裝到手機」，再按「安裝」就好了。')
              else
                ..._steps(hint, theme),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _dismiss, child: const Text('不用了')),
                  if (canInstall) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _installing ? null : _install,
                      child: const Text('安裝到手機'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 照著點就會的步驟。圖示直接畫出來，因為「分享鈕」是哪一個很多人不知道。
  List<Widget> _steps(InstallHint hint, ThemeData theme) {
    WidgetSpan icon(IconData data) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(data, size: 20, color: theme.colorScheme.primary),
    );
    final share = icon(Icons.ios_share);
    final List<List<InlineSpan>> steps = switch (hint.platform) {
      InstallPlatform.ios => [
        switch (hint.browser) {
          InstallBrowser.chrome => [
            const TextSpan(text: '點網址列右邊的分享圖示 '),
            share,
          ],
          InstallBrowser.safari => [
            const TextSpan(text: '點畫面下方的分享圖示 '),
            share,
            const TextSpan(text: '（沒看到的話，先點右下角的「⋯」）'),
          ],
          InstallBrowser.other => [const TextSpan(text: '點瀏覽器的分享圖示 '), share],
        },
        [const TextSpan(text: '往下滑，點「加入主畫面」')],
        [const TextSpan(text: '點右上角的「加入」，之後從桌面的圖示打開')],
      ],
      _ => [
        [const TextSpan(text: '點瀏覽器右上角的選單 '), icon(Icons.more_vert)],
        [const TextSpan(text: '點「安裝應用程式」或「加到主畫面」')],
        [const TextSpan(text: '點「安裝」，之後從桌面的圖示打開')],
      ],
    };
    return [
      for (final (index, spans) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(child: Text.rich(TextSpan(children: spans))),
            ],
          ),
        ),
    ];
  }
}

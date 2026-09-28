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
    final instructions = switch (hint.platform) {
      InstallPlatform.ios => '用 Safari 開啟這個網站，按下方的「分享」按鈕，往下找「加入主畫面」。',
      _ when hint.canPrompt => '按下面的「安裝到手機」，之後就能從主畫面直接打開。',
      _ => '用 Chrome 開啟這個網站，按右上角的「⋮」，選「安裝應用程式」或「加到主畫面」。',
    };

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
                    '加到手機主畫面',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('加了之後就像 App 一樣從桌面點開，也不用每次重新登入。'),
              const SizedBox(height: 4),
              Text(instructions),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _dismiss, child: const Text('不用了')),
                  if (hint.platform == InstallPlatform.android &&
                      hint.canPrompt) ...[
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
}

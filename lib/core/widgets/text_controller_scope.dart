import 'package:flutter/widgets.dart';

/// 讓 [TextEditingController] 的生命週期綁在它所在的子樹上。
///
/// `showDialog` / `showModalBottomSheet` 回傳的 future 在 `Navigator.pop` 當下
/// 就同步完成，但退場動畫還要再跑約 250 ms，這段期間 `TextField` 仍掛在樹上。
/// 若在 future 完成後（例如 `finally` 裡）馬上 dispose controller，之後 route
/// 的 focus scope 拆除時 `EditableText._handleFocusChanged` 會寫入已經 dispose
/// 的 controller，觸發
/// `A TextEditingController was used after being disposed`，debug build 直接紅屏。
///
/// 把 controller 交給這個 widget，dispose 就會發生在子樹真的被卸載之後 ——
/// 也就是動畫結束、TextField 已經離開樹的時候。
class TextControllerScope extends StatefulWidget {
  const TextControllerScope({
    super.key,
    required this.controller,
    required this.child,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

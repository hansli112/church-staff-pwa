import 'package:flutter/material.dart';

import '../../../core/utils/error_messages.dart';
import 'providers/roster_provider.dart';

/// 寫入失敗時給人看的一句話。
///
/// [RosterProvider] 的寫入失敗一律往上丟（見 [RosterProvider.updateRoster]），
/// 由各個畫面就地顯示。收在這裡是為了讓每個畫面的講法一致 —— 尤其是「部分
/// 失敗」：那不是「失敗」，有幾天已經寫進去了，照一般失敗講會讓人以為全部
/// 都要重來。
///
/// [action] 是動詞（「更新」「刪除」「儲存」）。[partialNote] 只接在部分失敗
/// 後面，給那個畫面自己知道的補充（例如「設定本身已儲存」）。
String writeFailureMessage(String action, Object error, {String? partialNote}) {
  if (error is PartialUpdateException) {
    return [
      '有 ${error.failureCount} 天的服事表沒有$action成功，'
          '其餘 ${error.successCount} 天已完成',
      ?partialNote,
    ].join('。');
  }
  return '$action失敗：${mapErrorToUserMessage(error)}';
}

/// 把 [writeFailureMessage] 用 snackbar 顯示出來。
///
/// 收 [ScaffoldMessengerState] 而不是 BuildContext：呼叫端都是在 await 之後
/// 才知道失敗，那時 context 可能已經不在樹上了，要在 await 之前先拿好。
void showWriteFailure(
  ScaffoldMessengerState messenger,
  String action,
  Object error, {
  String? partialNote,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        writeFailureMessage(action, error, partialNote: partialNote),
      ),
    ),
  );
}

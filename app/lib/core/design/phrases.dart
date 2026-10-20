import 'dart:ui';

import 'balanced_text.dart' show keepQuotesWhole;
import 'phrase_code_native.dart' if (dart.library.js_interop) 'phrase_code_web.dart' as models;

/// Where Chinese or Japanese text may break between phrases, by BudouX
/// (https://github.com/google/budoux, Apache License 2.0), which Chrome uses
/// for Japanese: a small model scores each gap between two characters by
/// the characters around it. Left alone, both languages break between any
/// two characters and split words: 「管理／員」.
class PhraseModel {
  PhraseModel._(this._weights, this._terms)
    : _base = -0.5 * _weights.values.expand((w) => w.values).fold<int>(0, (sum, w) => sum + w);

  // The app's own terms (docs/i18n-glossary.md), which the model, trained on
  // news, may split: 「服事｜表」.
  static const _zhHantTerms = [
    '教會', '同工', '一般同工', '管理員', '服事', '服事表', '聚會', '服事項目', '牧區', '小組', '小組長', '組員', //
    '特別活動', '外請', '活動', '行事曆', '支持', '雲端費用', '線上支持', '待定', '身分', '權限群組', '搬家檔', //
    '外部通知', '密鑰', '邀請碼', '邀請連結', '教會連結', '主畫面', '時區', '取消', '登入', '帳號', //
    '事工', '負責人', '行政', '牧者', '全教會', //
  ];
  static const _zhHansTerms = [
    '教会', '同工', '一般同工', '管理员', '事奉', '事奉表', '聚会', '事奉项目', '所属聚会', '小组', '小组长', '组员', //
    '特别活动', '外来人员', '活动', '行事历', '支持', '云端费用', '在线支持', '待定', '身份', '权限组', '迁移文件', //
    '外部通知', '密钥', '邀请码', '邀请链接', '教会链接', '主屏幕', '时区', '取消', '登录', '账号', //
    '事工', '负责人', '行政', '牧者', '全教会', //
  ];
  static const _jaTerms = [
    '教会', '管理者', '奉仕', '奉仕表', '集会', '担当', '所属集会', '特別行事', '行事', '応援', '未定', '役割', //
    '権限グループ', '移行ファイル', '外部通知', '招待コード', '招待リンク', //
  ];

  /// Fetches the models: on the web a part of their own (some 100 KB),
  /// downloaded alongside the rest of startup rather than in the app's first
  /// download. Should it fail (offline, or a deploy replaced the part), there
  /// is no model and lines break by punctuation alone.
  static Future<void> load() async {
    try {
      await models.loadPhraseModels();
      _loaded = true;
    } catch (_) {}
  }

  static var _loaded = false;

  static PhraseModel get zhHant => _zhHant ??= PhraseModel._(models.zhHantModel, _zhHantTerms);
  static PhraseModel get zhHans => _zhHans ??= PhraseModel._(models.zhHansModel, _zhHansTerms);
  static PhraseModel get ja => _ja ??= PhraseModel._(models.jaModel, _jaTerms);
  static PhraseModel? _zhHant, _zhHans, _ja;

  /// The model for [locale]'s language; null where words are spaced.
  static PhraseModel? of(Locale? locale) => !_loaded
      ? null
      : switch (locale?.languageCode) {
          'zh' when locale!.scriptCode == 'Hant' => zhHant,
          'zh' when locale!.scriptCode == null && const {'TW', 'HK', 'MO'}.contains(locale.countryCode) => zhHant,
          'zh' => zhHans,
          'ja' => ja,
          _ => null,
        };

  final Map<String, Map<String, int>> _weights;
  final List<String> _terms;
  final double _base;

  /// Offsets in [text] where one phrase ends and the next begins, as
  /// BudouX's parseBoundaries works them out.
  List<int> boundaries(String text) {
    int weight(String feature, int from, int to) => _weights[feature]?[_substring(text, from, to)] ?? 0;
    return [
      for (var i = 1; i < text.length; i++)
        if (_base +
                weight('UW1', i - 3, i - 2) +
                weight('UW2', i - 2, i - 1) +
                weight('UW3', i - 1, i) +
                weight('UW4', i, i + 1) +
                weight('UW5', i + 1, i + 2) +
                weight('UW6', i + 2, i + 3) +
                weight('BW1', i - 2, i) +
                weight('BW2', i - 1, i + 1) +
                weight('BW3', i, i + 2) +
                weight('TW1', i - 3, i) +
                weight('TW2', i - 2, i + 1) +
                weight('TW3', i - 1, i + 2) +
                weight('TW4', i, i + 3) >
            0)
          i,
    ];
  }

  /// [text] with an invisible WORD JOINER (U+2060) between the characters of
  /// each phrase in Chinese or Japanese script and inside each 「」 or 『』,
  /// so a line breaks only between phrases. Punctuation, Latin words and
  /// spaces are left as they are; a phrase longer than a line still breaks
  /// where it must.
  String keepWhole(String text) {
    final cuts = boundaries(text).toSet();
    for (final term in _terms) {
      for (var at = text.indexOf(term); at >= 0; at = text.indexOf(term, at + 1)) {
        cuts.removeAll([for (var i = at + 1; i < at + term.length; i++) i]);
      }
    }
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && !cuts.contains(i) && _isHanOrKana(text.codeUnitAt(i - 1)) && _isHanOrKana(text.codeUnitAt(i))) {
        out.write('\u2060');
      }
      out.write(text[i]);
    }
    return keepQuotesWhole(out.toString());
  }
}

/// JavaScript's String.substring, which BudouX's lookups rely on: out-of-range
/// ends are clamped, and reversed ones swapped.
String _substring(String s, int from, int to) {
  final a = from.clamp(0, s.length);
  final b = to.clamp(0, s.length);
  return a <= b ? s.substring(a, b) : s.substring(b, a);
}

/// A Han character (with 々 and 〇) or kana, in the Basic Multilingual Plane.
bool _isHanOrKana(int unit) =>
    (unit >= 0x3400 && unit <= 0x4DBF) ||
    (unit >= 0x4E00 && unit <= 0x9FFF) ||
    (unit >= 0xF900 && unit <= 0xFAFF) ||
    (unit >= 0x3041 && unit <= 0x30FF && unit != 0x30FB) ||
    (unit >= 0x31F0 && unit <= 0x31FF) ||
    unit == 0x3005 || // 々
    unit == 0x3007; // 〇

import 'package:flutter/material.dart';

/// 捲動成本的微型基準測試，用 `?bench=1` 開啟（會一併打開 PerfHud）。
///
/// 帳號管理捲動時 UI thread 要 20~30ms，但那個畫面已經是最精簡的形式了
/// （固定 itemExtent、無陰影、每列就頭像＋兩行字＋一個按鈕）。要知道錢花在
/// 哪一層，只能把變因拆開一個一個量：
///
///   1 純文字 ASCII —— Flutter Web 在這台裝置上的地板價
///   2 純文字 中文   —— 中文排版比 ASCII 貴多少
///   3 現行列        —— Card + ListTile + CircleAvatar + IconButton
///   4 精簡列        —— 同樣外觀，但用手寫 Row 取代 ListTile
///
/// 判讀：
///   1 就很貴        → 平台天花板，改 widget 沒用，要換執行環境（--wasm）
///   2 遠大於 1      → 成本在中文排版
///   3 遠大於 2      → 成本在 widget 組成，值得改寫成 4
///   4 明顯小於 3    → 直接照著改帳號管理與服事表
///
/// 不需要登入，這樣在手機上量測不用先打帳密。
class ScrollBenchScreen extends StatefulWidget {
  const ScrollBenchScreen({super.key});

  @override
  State<ScrollBenchScreen> createState() => _ScrollBenchScreenState();
}

enum _Variant {
  asciiText('1 純文字 ASCII'),
  cjkText('2 純文字 中文'),
  currentRow('3 現行列'),
  slimRow('4 精簡列');

  const _Variant(this.label);
  final String label;
}

class _ScrollBenchScreenState extends State<ScrollBenchScreen> {
  static const int _itemCount = 400;
  static const double _itemExtent = 88;

  // 字池刻意用常見姓氏與服事名稱，貼近真實資料的用字範圍。
  static const String _pool =
      '王李張陳林黃吳劉蔡楊許鄭謝洪郭邱曾廖賴徐周葉蘇莊呂江何蕭羅高'
      '敬拜主領司琴音控投影招待司事關懷兒童青年主日崇拜聖餐洗禮見證分享';

  _Variant _variant = _Variant.asciiText;

  String _cjkName(int i) =>
      '${_pool[i % _pool.length]}'
      '${_pool[(i * 7) % _pool.length]}'
      '${_pool[(i * 13) % _pool.length]}';

  String _title(int i) =>
      _variant == _Variant.asciiText ? 'Member number $i' : _cjkName(i);

  String _subtitle(int i) => _variant == _Variant.asciiText
      ? 'staff | group $i'
      : '同工 | ${_cjkName(i + 3)}小組';

  @override
  Widget build(BuildContext context) {
    final cardBorderSide = BorderSide(
      color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
    );

    return Scaffold(
      // 不放 AppBar：HUD 疊在畫面最上層會把它蓋掉。
      body: Column(
        children: [
          // 讓出 HUD 的高度，選項才點得到。
          const SizedBox(height: 88),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: _Variant.values.map((variant) {
                return ChoiceChip(
                  label: Text(variant.label),
                  selected: _variant == variant,
                  onSelected: (_) => setState(() => _variant = variant),
                );
              }).toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '每個選項連續捲 3 秒以上，記下 UI 那行的 avg',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: ListView.builder(
              // 換選項時重建整份清單，避免沿用上一個變體的 element。
              key: ValueKey(_variant),
              itemExtent: _itemExtent,
              itemCount: _itemCount,
              itemBuilder: (context, index) => switch (_variant) {
                _Variant.asciiText || _Variant.cjkText => _PlainRow(
                  title: _title(index),
                  subtitle: _subtitle(index),
                ),
                _Variant.currentRow => _CurrentRow(
                  title: _title(index),
                  subtitle: _subtitle(index),
                  borderSide: cardBorderSide,
                ),
                _Variant.slimRow => _SlimRow(
                  title: _title(index),
                  subtitle: _subtitle(index),
                  borderSide: cardBorderSide,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 地板價：兩個 Text，沒有 Material 元件。
class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// 帳號管理現在的列組成。
class _CurrentRow extends StatelessWidget {
  const _CurrentRow({
    required this.title,
    required this.subtitle,
    required this.borderSide,
  });

  final String title;
  final String subtitle;
  final BorderSide borderSide;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: borderSide,
      ),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () {},
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {},
        ),
      ),
    );
  }
}

/// 提案中的精簡列：外觀幾乎相同，但少掉 ListTile / CircleAvatar / IconButton
/// 各自的 Material、InkWell 與 layout 邏輯。
class _SlimRow extends StatelessWidget {
  const _SlimRow({
    required this.title,
    required this.subtitle,
    required this.borderSide,
  });

  final String title;
  final String subtitle;
  final BorderSide borderSide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(borderSide),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(
                  Icons.person,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.delete, color: Colors.red),
            ],
          ),
        ),
      ),
    );
  }
}

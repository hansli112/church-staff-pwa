part of 'roster_card.dart';

// ---------------------------------------------------------------------------
// 交換服事
//
// 換班在教會裡是最常見的異動（「1/1 的破冰跟 1/8 換一下」），但在編輯畫面上
// 它原本要拆成兩次獨立的編輯：找到 1/1、取消勾自己、勾對方、存檔，再捲到
// 1/8 反過來做一次。中間任一步失敗，就會留下一個人被排兩天、另一個人的那天
// 空著的狀態。
//
// 這個 sheet 把它壓成一次操作，並且交給 [RosterProvider.swapDutyPeople] 以
// 單一 batch 寫入 —— 要嘛兩天都換好，要嘛兩天都沒動。
// ---------------------------------------------------------------------------

/// 一個可以換過去的對象：某一天、某個服事項目上的某個人。
///
/// 刻意攤平到「人」這一層而不是「那一天」：一個項目上可能排了兩個人，若以天
/// 為單位，使用者選完日期還要再選一次人。攤平之後清單直接就是可選的結果。
class _SwapCandidate {
  final ServiceRoster roster;
  final int dutyIndex;
  final String person;

  const _SwapCandidate({
    required this.roster,
    required this.dutyIndex,
    required this.person,
  });
}

class _SwapDutyDialog extends StatefulWidget {
  final ServiceRoster roster;
  final int dutyIndex;
  final RosterEntry duty;
  final List<_SwapCandidate> candidates;

  const _SwapDutyDialog({
    required this.roster,
    required this.dutyIndex,
    required this.duty,
    required this.candidates,
  });

  @override
  State<_SwapDutyDialog> createState() => _SwapDutyDialogState();
}

class _SwapDutyDialogState extends State<_SwapDutyDialog> {
  static final _shortDateFormat = DateFormat('MM/dd (EEEEE)', 'zh_TW');

  late String _sourcePerson;
  int? _selectedIndex;
  bool _isSubmitting = false;
  String? _errorText;

  List<String> get _sourcePeople => widget.duty.people.isEmpty
      ? const [RosterProvider.placeholderPerson]
      : widget.duty.people;

  @override
  void initState() {
    super.initState();
    _sourcePerson = _sourcePeople.first;
  }

  Future<void> _submit() async {
    final index = _selectedIndex;
    if (index == null) return;
    final target = widget.candidates[index];

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final summary =
        '${_shortDateFormat.format(widget.roster.date)} $_sourcePerson'
        ' ⇄ '
        '${_shortDateFormat.format(target.roster.date)} ${target.person}';

    try {
      await context.read<RosterProvider>().swapDutyPeople(
        sourceRosterId: widget.roster.id,
        sourceDutyIndex: widget.dutyIndex,
        sourcePerson: _sourcePerson,
        targetRosterId: target.roster.id,
        targetDutyIndex: target.dutyIndex,
        targetPerson: target.person,
      );
    } catch (e, st) {
      log('交換服事失敗', error: e, stackTrace: st);
      if (!mounted) return;
      // 留在 sheet 上顯示錯誤，不 pop：關掉之後使用者得從頭再選一次日期。
      setState(() {
        _isSubmitting = false;
        _errorText = '交換失敗：${mapErrorToUserMessage(e)}';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('已交換：$summary')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = widget.duty.role;
    final hasCandidates = widget.candidates.isNotEmpty;

    return SettingsBottomSheet(
      title: '交換服事',
      submitLabel: '交換',
      isSubmitting: _isSubmitting,
      onSubmit: (!hasCandidates || _selectedIndex == null || _isSubmitting)
          ? null
          : _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${RosterCard._dateFormat.format(widget.roster.date)} · $role',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          // 一個項目只排一個人時不必問「要換誰」—— 那顆 chip 沒有第二個選項，
          // 只是多一行要讀的東西。
          if (_sourcePeople.length > 1) ...[
            Text(
              '要換誰',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _sourcePeople.map((person) {
                return ChoiceChip(
                  label: Text(person),
                  selected: _sourcePerson == person,
                  onSelected: _isSubmitting
                      ? null
                      : (_) => setState(() => _sourcePerson = person),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '換到哪一天的「$role」',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          if (!hasCandidates)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '其他日期沒有可以交換的「$role」',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            )
          else
            SizedBox(
              height: 280,
              child: ListView.builder(
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final candidate = widget.candidates[index];
                  final selected = _selectedIndex == index;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.grey.shade500,
                    ),
                    title: Text(_shortDateFormat.format(candidate.roster.date)),
                    trailing: Text(
                      candidate.person,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: _isSubmitting
                        ? null
                        : () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
          if (_selectedIndex != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_shortDateFormat.format(widget.roster.date)} $_sourcePerson'
                '   ⇄   '
                '${_shortDateFormat.format(widget.candidates[_selectedIndex!].roster.date)}'
                ' ${widget.candidates[_selectedIndex!].person}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

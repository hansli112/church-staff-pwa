import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/service_roster.dart';

class RosterViewCard extends StatelessWidget {
  final ServiceRoster roster;
  final bool initiallyExpanded;
  final int Function(String event) resolveEventColor;

  const RosterViewCard({
    super.key,
    required this.roster,
    required this.resolveEventColor,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        key: PageStorageKey(roster.id),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(Icons.event_note, color: Theme.of(context).colorScheme.primary),
        title: Text(
          dateFormat.format(roster.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(roster.serviceName),
            if (roster.specialEvents.isNotEmpty) const SizedBox(width: 8),
            if (roster.specialEvents.isNotEmpty)
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    ...roster.specialEvents.map((event) {
                      final colorValue =
                          roster.customEventColors[event] ?? resolveEventColor(event);
                      final color = Color(colorValue);
                      return Chip(
                        label: Text(
                          event,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: color.withValues(alpha: 0.12),
                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -3,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                ...roster.duties.asMap().entries.map((entry) {
                  final RosterEntry duty = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            duty.role,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            duty.people.join('、'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

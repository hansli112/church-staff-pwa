import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/service_roster.dart';

class RosterCard extends StatelessWidget {
  final ServiceRoster roster;
  final bool initiallyExpanded; // 新增參數

  const RosterCard({
    super.key, 
    required this.roster,
    this.initiallyExpanded = false, // 預設為 false
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded, // 使用參數
        leading: const Icon(Icons.event_note, color: Colors.blueAccent),
        title: Text(
          dateFormat.format(roster.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(roster.serviceName),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: roster.duties.map((duty) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        duty.role,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        duty.personName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
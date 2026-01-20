import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教會同工中心'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '歡迎回來，同工！',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildFeatureCard(
              context,
              icon: Icons.notifications_active,
              title: '最新公告',
              description: '查看教會本週重要事項',
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: 16),
            _buildFeatureCard(
              context,
              icon: Icons.calendar_month,
              title: '行事曆',
              description: '教會年度活動一覽',
              color: Colors.purpleAccent,
            ),
             const SizedBox(height: 16),
            _buildFeatureCard(
              context,
              icon: Icons.folder_shared,
              title: '資源下載',
              description: '週報、獻詩譜、會議記錄',
              color: Colors.teal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('此功能即將推出！')),
          );
        },
      ),
    );
  }
}

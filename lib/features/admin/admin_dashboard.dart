import 'package:afrinova_academy/features/admin/approve_teachers_screen.dart';
import 'package:flutter/material.dart';
import '../teacher/teacher_dashboard.dart';
import 'settlements_screen.dart';

class AdminDashboard extends StatelessWidget {
  final String userName;
  final VoidCallback onLogout;

  const AdminDashboard({
    super.key,
    required this.userName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return TeacherDashboard(
      userName: userName,
      userRole: 'admin',
      onLogout: onLogout,
      extraActions: [
        _AdminAction(
          icon: Icons.verified_user_rounded,
          title: 'Approve Teacher Requests',
          subtitle: 'View and approve teacher enrollment requests',
          color: const Color(0xFF4CAF50),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApproveTeachersScreen())),
        ),
        _AdminAction(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Teacher Settlements',
          subtitle: 'View balances and settle teacher payouts',
          color: const Color(0xFF4CAF50),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettlementsScreen())),
        ),
        _AdminAction(
          icon: Icons.settings_rounded,
          title: 'Platform Settings',
          subtitle: 'Manage pricing, commission rates, and integrations',
          color: const Color(0xFF607D8B),
          onTap: () {
            // Future: Platform settings screen
          },
        ),
        _AdminAction(
          icon: Icons.people_rounded,
          title: 'All Users',
          subtitle: 'View and manage all students and teachers',
          color: const Color(0xFF3F51B5),
          onTap: () {
            // Future: User management screen
          },
        ),
      ],
    );
  }
}

class _AdminAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1A237E))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.chevron_right_rounded, color: color, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
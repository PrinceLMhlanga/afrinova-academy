import 'package:flutter/material.dart';
import '../teacher/teacher_dashboard.dart'; // This imports AdminActionData
import 'settlements_screen.dart';
import 'manage_platform_subjects_screen.dart';
import 'question_bank_entry_screen.dart';
import 'question_bank_overview_screen.dart';
import 'manage_users_screen.dart';
import 'platform_settings_screen.dart';
import 'teacher_management_screen.dart';
import 'approve_teachers_screen.dart';

class AdminDashboard extends StatelessWidget {
  final String userName;
  final String? userDisplayName;
  final VoidCallback onLogout;

  const AdminDashboard({
    super.key,
    required this.userName,
    this.userDisplayName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return TeacherDashboard(
      userName: userName,
      userDisplayName: userDisplayName,
      userRole: 'admin',
      onLogout: onLogout,
      extraActions: [
        AdminActionData(
          icon: Icons.verified_user_rounded,
          title: 'Approve Teacher Requests',
          subtitle: 'View and approve teacher enrollment requests',
          color: const Color(0xFF4CAF50),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ApproveTeachersScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Teacher Settlements',
          subtitle: 'View balances and settle teacher payouts',
          color: const Color(0xFF4CAF50),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettlementsScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.settings_rounded,
          title: 'Platform Settings',
          subtitle: 'Manage pricing, commission rates, and integrations',
          color: const Color(0xFF607D8B),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlatformSettingsScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.people_rounded,
          title: 'All Users',
          subtitle: 'View and manage all students and teachers',
          color: const Color(0xFF3F51B5),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.topic_rounded,
          title: 'Platform Topics',
          subtitle: 'Manage subjects and their topics',
          color: const Color(0xFF00897B),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManagePlatformSubjectsScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.manage_accounts,
          title: 'Teacher Subjects',
          subtitle: 'Manage assignments & view stats',
          color: const Color(0xFF00897B),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeacherSubjectManagerScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.quiz_rounded,
          title: 'Question Bank',
          subtitle: 'Add questions from exam papers',
          color: const Color(0xFFFF9800),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QuestionBankEntryScreen()),
          ),
        ),
        AdminActionData(
          icon: Icons.quiz_rounded,
          title: 'Question Bank Overview',
          subtitle: 'View question statistics & counts',
          color: const Color(0xFFFF9800),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QuestionBankOverviewScreen()),
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Map<String, int> _stats = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  String _levelFilter = 'all';
  List<Map<String, dynamic>> _levels = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load levels
      final levels = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order', ascending: true);

      // Load all users with their details
      final users = await Supabase.instance.client
          .from('profiles')
          .select('*, levels(name)')
          .order('created_at', ascending: false);

      int totalStudents = 0;
      int totalTeachers = 0;
      int totalAdmins = 0;
      int approvedTeachers = 0;
      int pendingTeachers = 0;
      int subscribed = 0;

      for (final u in users) {
        final role = u['role'] as String?;
        if (role == 'student') totalStudents++;
        if (role == 'teacher') {
          totalTeachers++;
          if (u['approval_status'] == 'approved') approvedTeachers++;
          if (u['approval_status'] == 'pending') pendingTeachers++;
        }
        if (role == 'admin') totalAdmins++;
        if (u['is_subscribed'] == true) subscribed++;
      }

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(users);
          _filteredUsers = List<Map<String, dynamic>>.from(users);
          _levels = List<Map<String, dynamic>>.from(levels);
          _stats = {
            'total': users.length,
            'students': totalStudents,
            'teachers': totalTeachers,
            'admins': totalAdmins,
            'approved_teachers': approvedTeachers,
            'pending_teachers': pendingTeachers,
            'subscribed': subscribed,
          };
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_users);

    // Search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        final name = (u['full_name'] as String? ?? '').toLowerCase();
        final email = (u['email'] as String? ?? '').toLowerCase();
        final phone = (u['phone_number'] as String? ?? '').toLowerCase();
        return name.contains(query) || email.contains(query) || phone.contains(query);
      }).toList();
    }

    // Role filter
    if (_roleFilter != 'all') {
      filtered = filtered.where((u) => u['role'] == _roleFilter).toList();
    }

    // Status filter
    if (_statusFilter == 'subscribed') {
      filtered = filtered.where((u) => u['is_subscribed'] == true).toList();
    } else if (_statusFilter == 'unsubscribed') {
      filtered = filtered.where((u) => u['is_subscribed'] != true).toList();
    } else if (_statusFilter == 'approved') {
      filtered = filtered.where((u) => u['approval_status'] == 'approved').toList();
    } else if (_statusFilter == 'pending') {
      filtered = filtered.where((u) => u['approval_status'] == 'pending' || u['approval_status'] == null).toList();
    }

    // Level filter
    if (_levelFilter != 'all') {
      filtered = filtered.where((u) => u['level_id'] == _levelFilter).toList();
    }

    setState(() => _filteredUsers = filtered);
  }

  Future<void> _showEnrollmentManager(Map<String, dynamic> user) async {
  final enrollments = await Supabase.instance.client
      .from('enrollments')
      .select('*, subjects(name), profiles!teacher_id(full_name)')
      .eq('student_id', user['id'])
      .inFilter('status', ['paid', 'approved', 'pending']);

  if (!mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _EnrollmentManagerSheet(
      student: user,
      enrollments: List<Map<String, dynamic>>.from(enrollments),
      onUpdate: _loadData,
    ),
  );
}

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final newStatus = user['is_active'] == true ? false : true;
    await Supabase.instance.client
        .from('profiles')
        .update({'is_active': newStatus})
        .eq('id', user['id']);
    _loadData();
  }

  Future<void> _viewUserDetails(Map<String, dynamic> user) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _UserDetailSheet(
      user: user,
      onUpdate: _loadData,
      onManageSubscriptions: _showEnrollmentManager,  // ✅ Pass callback
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 130,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: const Text('Manage Users',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Stats cards
                  Row(
                    children: [
                      Expanded(child: _StatsCard(label: 'Total Users', count: _stats['total'] ?? 0, color: const Color(0xFF1A237E), icon: Icons.people)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatsCard(label: 'Students', count: _stats['students'] ?? 0, color: Colors.blue, icon: Icons.school)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatsCard(label: 'Teachers', count: _stats['teachers'] ?? 0, color: const Color(0xFFFF9800), icon: Icons.person)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _StatsCard(label: 'Subscribed', count: _stats['subscribed'] ?? 0, color: const Color(0xFF4CAF50), icon: Icons.check_circle)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatsCard(label: 'Pending Teachers', count: _stats['pending_teachers'] ?? 0, color: Colors.red, icon: Icons.pending)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatsCard(label: 'Admins', count: _stats['admins'] ?? 0, color: Colors.purple, icon: Icons.admin_panel_settings)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, or phone...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 12),

                  // Filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterDropdown(
                          label: 'Role',
                          value: _roleFilter,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Roles')),
                            DropdownMenuItem(value: 'student', child: Text('Students')),
                            DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                            DropdownMenuItem(value: 'admin', child: Text('Admins')),
                          ],
                          onChanged: (v) {
                            _roleFilter = v ?? 'all';
                            _applyFilters();
                          },
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown(
                          label: 'Status',
                          value: _statusFilter,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Status')),
                            DropdownMenuItem(value: 'subscribed', child: Text('Subscribed')),
                            DropdownMenuItem(value: 'unsubscribed', child: Text('Unsubscribed')),
                            DropdownMenuItem(value: 'approved', child: Text('Approved Teachers')),
                            DropdownMenuItem(value: 'pending', child: Text('Pending Teachers')),
                          ],
                          onChanged: (v) {
                            _statusFilter = v ?? 'all';
                            _applyFilters();
                          },
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown(
                          label: 'Level',
                          value: _levelFilter,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All Levels')),
                            ..._levels.map((l) => DropdownMenuItem(
                              value: l['id'] as String,
                              child: Text(l['name'] ?? ''),
                            )),
                          ],
                          onChanged: (v) {
                            _levelFilter = v ?? 'all';
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${_filteredUsers.length} user(s) found',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),

                  // User list
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                    ))
                  else if (_filteredUsers.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('No users found', style: TextStyle(color: Colors.grey)),
                    ))
                  else
                    ..._filteredUsers.map((user) {
                      final role = user['role'] as String? ?? 'student';
                      final isSubscribed = user['is_subscribed'] == true;
                      final isApproved = user['approval_status'] == 'approved';
                      final levelName = user['levels']?['name'] as String?;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _viewUserDetails(user),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: _getRoleColor(role).withOpacity(0.1),
                                    child: Text(
                                      (user['full_name'] as String? ?? 'U')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: _getRoleColor(role),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(user['full_name'] ?? 'Unknown',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        Text(user['email'] ?? '',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            // Role badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: _getRoleColor(role).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                role.toUpperCase(),
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _getRoleColor(role)),
                                              ),
                                            ),
                                            if (levelName != null) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: _getLevelColor(levelName).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(levelName, style: TextStyle(fontSize: 9, color: _getLevelColor(levelName))),
                                              ),
                                            ],
                                            const SizedBox(width: 4),
                                            if (isSubscribed)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('Subscribed', style: TextStyle(fontSize: 9, color: Color(0xFF4CAF50))),
                                              ),
                                            if (role == 'teacher' && !isApproved)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('Pending', style: TextStyle(fontSize: 9, color: Colors.orange)),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'student': return Colors.blue;
      case 'teacher': return const Color(0xFFFF9800);
      case 'admin': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Form 1': return Colors.blue;
      case 'Form 2': return Colors.teal;
      case 'O-Level': return const Color(0xFFFF9800);
      case 'A-Level': return Colors.purple;
      default: return Colors.grey;
    }
  }
}

// ===== STATS CARD =====
class _StatsCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatsCard({required this.label, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ===== FILTER DROPDOWN =====
class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>>? items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({required this.label, this.value, this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: items,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12, color: Color(0xFF1A237E)),
        ),
      ),
    );
  }
}

// ===== USER DETAIL BOTTOM SHEET =====
class _UserDetailSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onUpdate;
  final Function(Map<String, dynamic>)? onManageSubscriptions;

  const _UserDetailSheet({
    required this.user,
    required this.onUpdate,
    this.onManageSubscriptions,
  });

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  bool _isSaving = false;

  

  Future<void> _updateField(String field, dynamic value) async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({field: value})
          .eq('id', widget.user['id']);
      widget.onUpdate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text('Permanently delete ${widget.user['full_name']}?\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // ✅ Call Edge Function to delete auth user + profile
      await Supabase.instance.client.functions.invoke('delete-user', body: {
        'userId': widget.user['id'],
      });
      
      widget.onUpdate();
      if (mounted) Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted ✅'), backgroundColor: Color(0xFF4CAF50)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final role = user['role'] as String? ?? 'student';
    final isSubscribed = user['is_subscribed'] == true;
    final isApproved = user['approval_status'] == 'approved';

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: _getRoleColor(role).withOpacity(0.1),
                child: Text((user['full_name'] as String? ?? 'U')[0].toUpperCase(),
                    style: TextStyle(color: _getRoleColor(role), fontWeight: FontWeight.bold, fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['full_name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(user['email'] ?? '', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Details
          // Details - conditional based on role
_DetailRow(label: 'Role', value: role.toUpperCase(), color: _getRoleColor(role)),
_DetailRow(label: 'Phone', value: user['phone_number'] ?? 'Not set'),
// ✅ Only show level for students
if (role == 'student')
  _DetailRow(label: 'Level', value: user['levels']?['name'] ?? 'Not set'),
_DetailRow(label: 'School', value: user['school_name'] ?? 'Not set'),
_DetailRow(label: 'Country', value: user['country'] ?? 'Zimbabwe'),
_DetailRow(label: 'Joined', value: _formatDate(user['created_at'] as String?)),
// ✅ Only show subscribed for students
if (role == 'student')
  _DetailRow(label: 'Subscribed', value: isSubscribed ? 'Yes ✅' : 'No'),
// ✅ Only show approval for teachers
if (role == 'teacher')
  _DetailRow(label: 'Approval', value: isApproved ? 'Approved' : 'Pending', 
      color: isApproved ? const Color(0xFF4CAF50) : Colors.orange),

const SizedBox(height: 20),
const Divider(),
const SizedBox(height: 12),

// Actions - conditional based on role
if (_isSaving)
  const Center(child: CircularProgressIndicator())
else
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      // ✅ Only show approve/revoke for teachers
      if (role == 'teacher')
        _ActionChip(
          label: isApproved ? 'Revoke Approval' : 'Approve Teacher',
          icon: isApproved ? Icons.cancel : Icons.check_circle,
          color: isApproved ? Colors.orange : const Color(0xFF4CAF50),
          onTap: () => _updateField('approval_status', isApproved ? 'pending' : 'approved'),
        ),
      
      // ✅ Only show subscription toggle for students
      // In the actions section, replace the subscription chip:
if (role == 'student')
  _ActionChip(
    label: 'Manage Subscriptions',
    icon: Icons.card_giftcard,
    color: const Color(0xFF4CAF50),
    onTap: () {
      Navigator.pop(context); // Close detail sheet
      widget.onManageSubscriptions?.call(widget.user); // ✅ Call parent
    },
  ),
      
      // ✅ Only show delete for non-admins
      if (role != 'admin')
        _ActionChip(
          label: 'Delete User',
          icon: Icons.delete,
          color: Colors.red,
          onTap: _deleteUser,
        ),
    ],
  ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'student': return Colors.blue;
      case 'teacher': return const Color(0xFFFF9800);
      case 'admin': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  
}

class _EnrollmentManagerSheet extends StatefulWidget {
  final Map<String, dynamic> student;
  final List<Map<String, dynamic>> enrollments;
  final VoidCallback onUpdate;

  const _EnrollmentManagerSheet({
    required this.student,
    required this.enrollments,
    required this.onUpdate,
  });

  @override
  State<_EnrollmentManagerSheet> createState() => _EnrollmentManagerSheetState();
}

class _EnrollmentManagerSheetState extends State<_EnrollmentManagerSheet> {
  bool _isSaving = false;

  Future<void> _grantSubscription(Map<String, dynamic> enrollment, int days) async {
    setState(() => _isSaving = true);
    try {
      final expiresAt = DateTime.now().add(Duration(days: days)).toIso8601String();
      
      await Supabase.instance.client
          .from('enrollments')
          .update({
            'is_subscribed': true,
            'subscription_expires_at': expiresAt,
            'status': 'paid',
            'amount_paid': 0, // Manual grant
          })
          .eq('id', enrollment['id']);

      // Also update profile
      await Supabase.instance.client
          .from('profiles')
          .update({
            'is_subscribed': true,
            'subscription_expires_at': expiresAt,
            'subscription_plan': 'paid',
          })
          .eq('id', widget.student['id']);

      widget.onUpdate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription granted for $days days ✅'), backgroundColor: const Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _revokeSubscription(Map<String, dynamic> enrollment) async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('enrollments')
          .update({
            'is_subscribed': false,
            'subscription_expires_at': null,
            'status': 'approved',
          })
          .eq('id', enrollment['id']);

      widget.onUpdate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription revoked'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
Widget build(BuildContext context) {
  return Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.8,  // ✅ Max 80% of screen
    ),
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 20),
        Text('${widget.student['full_name']} - Enrollments',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        if (_isSaving)
          const Center(child: CircularProgressIndicator())
        else if (widget.enrollments.isEmpty)
          const Center(child: Text('No enrollments found', style: TextStyle(color: Colors.grey)))
        else
          // ✅ Make the list scrollable
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.enrollments.length,
              itemBuilder: (context, index) {
                final e = widget.enrollments[index];
                final subjectName = e['subjects']?['name'] ?? 'Unknown';
                final teacherName = e['profiles']?['full_name'] ?? 'Unknown';
                final isSubscribed = e['is_subscribed'] == true;
                final expiresAt = e['subscription_expires_at'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subjectName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('Teacher: $teacherName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                if (isSubscribed && expiresAt != null)
                                  Text('✅ Subscribed until ${_formatDate(expiresAt)}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50)))
                                else
                                  const Text('❌ Not subscribed', style: TextStyle(fontSize: 11, color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (isSubscribed)
                            _SmallActionButton(label: 'Revoke', color: Colors.red, onTap: () => _revokeSubscription(e))
                          else ...[
                            _SmallActionButton(label: '30 Days', color: const Color(0xFF4CAF50), onTap: () => _grantSubscription(e, 30)),
                            const SizedBox(width: 8),
                            _SmallActionButton(label: '90 Days', color: Colors.blue, onTap: () => _grantSubscription(e, 90)),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

  String _formatDate(String dateStr) {
    try {
      return '${DateTime.parse(dateStr).day}/${DateTime.parse(dateStr).month}/${DateTime.parse(dateStr).year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _DetailRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color))),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}
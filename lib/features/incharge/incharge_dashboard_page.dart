import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/staff.dart';
import '../../core/models/food.dart';
import '../../core/models/salary_disbursement.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class InchargeDashboardPage extends StatefulWidget {
  const InchargeDashboardPage({super.key});

  @override
  State<InchargeDashboardPage> createState() => _InchargeDashboardPageState();
}

class _InchargeDashboardPageState extends State<InchargeDashboardPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;

  final _staffNameController = TextEditingController();
  final _staffRoleController = TextEditingController();
  final _staffPhoneController = TextEditingController();

  final _taskTitleController = TextEditingController();
  final _taskDescController = TextEditingController();
  final _timeToCompleteController = TextEditingController(text: '2 Hours');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _staffNameController.dispose();
    _staffRoleController.dispose();
    _staffPhoneController.dispose();
    _taskTitleController.dispose();
    _taskDescController.dispose();
    _timeToCompleteController.dispose();
    super.dispose();
  }

  void _addStaffMember(String resortId, String inchargeId) {
    if (_staffNameController.text.isEmpty || _staffRoleController.text.isEmpty) return;

    final newStaff = StaffMember(
      id: 'staff-new-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      inchargeId: inchargeId,
      name: _staffNameController.text.trim(),
      roleTitle: _staffRoleController.text.trim(),
      phone: _staffPhoneController.text.trim().isEmpty ? '+91 99000 00000' : _staffPhoneController.text.trim(),
      status: 'active',
      joinDate: DateTime.now(),
    );

    setState(() {
      final list = _store.resortStaff[resortId] ?? [];
      list.add(newStaff);
      _store.resortStaff[resortId] = list;
    });

    _staffNameController.clear();
    _staffRoleController.clear();
    _staffPhoneController.clear();

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Staff member ${newStaff.name} added successfully.')),
    );
  }

  void _addTaskAndSendMessage(String resortId, String inchargeId, String? assignedStaffId, String resortName) {
    if (_taskTitleController.text.trim().isEmpty) return;

    final staffMembers = _store.resortStaff[resortId] ?? [];
    final targetStaff = staffMembers.firstWhere(
      (s) => s.id == assignedStaffId,
      orElse: () => staffMembers.isNotEmpty
          ? staffMembers.first
          : StaffMember(
              id: 'staff-default',
              resortId: resortId,
              inchargeId: inchargeId,
              name: 'Staff Member',
              roleTitle: 'Operational Staff',
              phone: '+91 98765 00000',
              status: 'active',
              joinDate: DateTime.now(),
            ),
    );

    final timeToComplete = _timeToCompleteController.text.trim().isEmpty ? '2 Hours' : _timeToCompleteController.text.trim();
    final taskTitle = _taskTitleController.text.trim();
    final taskDesc = _taskDescController.text.trim();

    final newTask = StaffTask(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      inchargeId: inchargeId,
      assignedToStaffId: targetStaff.id,
      title: taskTitle,
      description: taskDesc.isEmpty ? 'Complete assigned operational duty' : taskDesc,
      priority: 'high',
      status: 'pending',
      timeToComplete: timeToComplete,
      dueDate: DateTime.now().add(const Duration(hours: 2)),
      createdAt: DateTime.now(),
    );

    setState(() {
      final list = _store.resortTasks[resortId] ?? [];
      list.insert(0, newTask); // Add newest task at top
      _store.resortTasks[resortId] = list;
    });

    _taskTitleController.clear();
    _taskDescController.clear();

    _showStaffNotificationDialog(newTask, targetStaff, resortName);
  }

  void _showStaffNotificationDialog(StaffTask task, StaffMember staff, String resortName) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isCompleted = task.status == 'completed';

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Simulated SMS Header Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sms_outlined, color: Color(0xFFFEBB02), size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SMS / Message to Staff Member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text('To: ${staff.name} (${staff.phone})', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Message Card Content
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.assignment_ind, size: 16, color: Colors.blue),
                            const SizedBox(width: 6),
                            Text('NEW WORK ASSIGNMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📌 Work Assigned: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Expanded(child: Text(task.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
                          ],
                        ),
                        if (task.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('   Detail: ${task.description}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('⏱️ Time to Complete: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Text(
                                task.timeToComplete ?? '2 Hours',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('🏢 From: Resort Incharge ($resortName)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Interactive Completed Button
                  if (isCompleted)
                    Container(
                      padding: const EdgeInsets.all(12),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Text('Task Completed & Incharge Notified!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: const Text('COMPLETED TASK (Send Update to Incharge)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          final list = _store.resortTasks[task.resortId] ?? [];
                          final idx = list.indexWhere((t) => t.id == task.id);
                          if (idx != -1) {
                            list[idx] = list[idx].copyWith(status: 'completed');
                          }
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('📩 Message Sent to Incharge: Task "${task.title}" marked COMPLETED by ${staff.name}!'),
                            backgroundColor: Colors.green.shade800,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _store.currentUser;
    final resortId = user?.resortId ?? 'resort-grand-palms';
    final resort = _store.resorts[resortId];

    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textMuted = AppTheme.textMuted(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cardBg,
        foregroundColor: textPrimary,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: border, width: 1)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Incharge Operations Portal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Resort: ${resort?.name ?? "Resort Operations"}',
              style: TextStyle(fontSize: 11, color: isDark ? AppTheme.resortCoral : const Color(0xFFFF5A36), fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: textMuted),
            tooltip: 'Logout',
            onPressed: () {
              MockDataStore.instance.logout();
              context.go('/login');
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFFFF5A36),
          indicatorWeight: 3,
          labelColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFFFF5A36),
          unselectedLabelColor: textMuted,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Staff Management'),
            Tab(icon: Icon(Icons.payments_outlined), text: 'Staff Payroll'),
            Tab(icon: Icon(Icons.task_alt_outlined), text: 'Operational Tasks'),
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Work Schedules'),
            Tab(icon: Icon(Icons.fastfood_outlined), text: 'Food Fulfillment'),
            Tab(icon: Icon(Icons.build_circle_outlined), text: 'Maintenance'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStaffTab(resortId, user?.id ?? 'usr-incharge'),
          _buildStaffPayrollTab(resortId, user?.id ?? 'usr-incharge'),
          _buildTasksTab(resortId, user?.id ?? 'usr-incharge', resort?.name ?? 'Resort'),
          _buildSchedulesTab(resortId),
          _buildFoodOrdersTab(resortId),
          _buildMaintenanceTab(resortId),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildStaffTab(String resortId, String inchargeId) {
    final staffList = _store.resortStaff[resortId] ?? [];

    void openAddStaffDialog() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Operational Staff Member', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _staffNameController, decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 8),
              TextField(controller: _staffRoleController, decoration: const InputDecoration(labelText: 'Role Title (e.g. Housekeeper, Chef) *', prefixIcon: Icon(Icons.badge))),
              const SizedBox(height: 8),
              TextField(controller: _staffPhoneController, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
              onPressed: () => _addStaffMember(resortId, inchargeId),
              child: const Text('Add Staff'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tab Header Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Staff Roster', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                  Text('${staffList.length} operational staff members', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
                ],
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Staff Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: openAddStaffDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: staffList.isEmpty
              ? const Center(child: Text('No operational staff members registered yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final s = staffList[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0F172A),
                          child: Text(s.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Role: ${s.roleTitle} | Phone: ${s.phone}', style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12)),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Remove Staff',
                          onPressed: () {
                            setState(() {
                              staffList.removeAt(index);
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTasksTab(String resortId, String inchargeId, String resortName) {
    final tasksList = _store.resortTasks[resortId] ?? [];
    final staffList = _store.resortStaff[resortId] ?? [];

    void openAssignTaskDialog() {
      String? selectedStaffId = staffList.isNotEmpty ? staffList.first.id : null;

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.assignment_turned_in_outlined, color: Color(0xFF0F172A)),
                  SizedBox(width: 10),
                  Text('Assign Work to Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _taskTitleController,
                      decoration: const InputDecoration(
                        labelText: 'Work Assigned / Task Title *',
                        hintText: 'e.g. Clean & Inspect Villa 102',
                        prefixIcon: Icon(Icons.assignment_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _taskDescController,
                      decoration: const InputDecoration(labelText: 'Description / Instructions', prefixIcon: Icon(Icons.description_outlined)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _timeToCompleteController,
                      decoration: const InputDecoration(
                        labelText: 'Time to Complete *',
                        hintText: 'e.g. 2 Hours, or Today by 5:00 PM',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Assign Task To (Staff Member):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedStaffId,
                          items: staffList.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Text('${s.name} (${s.roleTitle}) — ${s.phone}'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedStaffId = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Assign & Send Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    if (_taskTitleController.text.trim().isEmpty) return;
                    Navigator.pop(context);
                    _addTaskAndSendMessage(resortId, inchargeId, selectedStaffId, resortName);
                  },
                ),
              ],
            );
          },
        ),
      );
    }

    return Column(
      children: [
        // Tab Header Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Operational Tasks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                  Text('${tasksList.length} tasks recorded', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
                ],
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Assign Work to Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: openAssignTaskDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: tasksList.isEmpty
              ? const Center(child: Text('No operational tasks assigned yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: tasksList.length,
                  itemBuilder: (context, index) {
                    final t = tasksList[index];
                    final assignedStaff = staffList.firstWhere(
                      (s) => s.id == t.assignedToStaffId,
                      orElse: () => StaffMember(
                        id: '',
                        resortId: resortId,
                        inchargeId: inchargeId,
                        name: 'Assigned Staff',
                        roleTitle: 'Operational Staff',
                        phone: '+91 98765 00000',
                        status: 'active',
                        joinDate: DateTime.now(),
                      ),
                    );
                    final isCompleted = t.status == 'completed';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isCompleted ? Icons.check_circle : Icons.pending_actions, color: isCompleted ? Colors.green : Colors.amber.shade900, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCompleted ? Colors.green.shade50 : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isCompleted ? Colors.green.shade300 : Colors.amber.shade300),
                                  ),
                                  child: Text(
                                    isCompleted ? 'COMPLETED' : 'IN PROGRESS',
                                    style: TextStyle(
                                      color: isCompleted ? Colors.green.shade900 : Colors.amber.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(t.description, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_outline, size: 14, color: Colors.blueGrey),
                                    const SizedBox(width: 4),
                                    Text('Staff: ${assignedStaff.name} (${assignedStaff.roleTitle})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text('Time: ${t.timeToComplete ?? "2 Hours"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.sms_outlined, size: 16),
                                  label: const Text('View Staff Message', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F172A),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _showStaffNotificationDialog(t, assignedStaff, resortName),
                                ),
                                Row(
                                  children: [
                                    Checkbox(
                                      value: isCompleted,
                                      activeColor: Colors.green,
                                      onChanged: (val) {
                                        setState(() {
                                          tasksList[index] = t.copyWith(status: val == true ? 'completed' : 'pending');
                                        });
                                      },
                                    ),
                                    Text(isCompleted ? 'Completed' : 'Mark Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isCompleted ? Colors.green : Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSchedulesTab(String resortId) {
    final staff = _store.resortStaff[resortId] ?? [];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: staff.length,
      itemBuilder: (context, index) {
        final s = staff[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.access_time, color: Color(0xFF0F172A)),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Shift: 08:00 AM - 05:00 PM (${s.roleTitle})'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('PRESENT', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFoodOrdersTab(String resortId) {
    final orders = _store.resortFoodOrders[resortId] ?? [];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final o = orders[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.restaurant, color: Colors.white)),
            title: Text('Order #${o.id} - ${o.roomNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Items: ${o.items.map((i) => "${i['quantity']}x ${i['name']}").join(", ")}'),
            trailing: DropdownButton<String>(
              value: o.status,
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'preparing', child: Text('Preparing')),
                DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    orders[index] = FoodOrder(
                      id: o.id,
                      resortId: o.resortId,
                      roomNumber: o.roomNumber,
                      items: o.items,
                      totalAmount: o.totalAmount,
                      status: val,
                      createdAt: o.createdAt,
                    );
                  });
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaintenanceTab(String resortId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resort Maintenance Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.plumbing, color: Colors.amber),
                title: Text('Plunge pool filter replacement - Villa 101'),
                subtitle: Text('Reported by Incharge | Cost: ₹350.00'),
                trailing: Text('COMPLETED', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffPayrollTab(String resortId, String inchargeId) {
    final staffList = _store.resortStaff[resortId] ?? [];
    final payments = _store.staffSalaryPayments[resortId] ?? [];

    final totalDisbursed = payments.fold(0.0, (sum, p) => sum + p.amount);
    final paidCount = staffList.where((s) => payments.any((p) => p.staffId == s.id && p.monthYear == 'September 2026')).length;
    final pendingCount = staffList.length - paidCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payroll Overview Header
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.blue.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people, color: Colors.blue.shade800, size: 20),
                            const SizedBox(width: 8),
                            Text('Ground Staff', style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${staffList.length} Members', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$paidCount Paid / $pendingCount Pending', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payments, color: Colors.green.shade800, size: 20),
                            const SizedBox(width: 8),
                            Text('Wages Disbursed', style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('₹${totalDisbursed.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                        const SizedBox(height: 2),
                        Text('${payments.length} Salary Receipts', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Staff Payroll Funding Status & Request from Admin
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_wallet, color: AppTheme.resortCoral, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Staff Payroll Funding (from Admin)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.resortDarkText),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.request_quote, size: 16),
                        label: const Text('Request Funds from Admin'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.resortCoral,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => _openRequestStaffSalaryFundsDialog(resortId, staffList),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Funds Received: ₹${_store.getTotalFundedStaffPayroll(resortId, 'September 2026').toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _store.getAvailableStaffPayrollFunds(resortId, 'September 2026') >= 0 ? Colors.green.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Available Balance: ₹${_store.getAvailableStaffPayrollFunds(resortId, 'September 2026').toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _store.getAvailableStaffPayrollFunds(resortId, 'September 2026') >= 0 ? Colors.green.shade900 : Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  () {
                    final reqs = _store.getStaffSalaryFundRequests(resortId);
                    final latest = reqs.where((r) => r.monthYear == 'September 2026').firstOrNull;
                    if (latest == null) return const SizedBox.shrink();

                    final isPending = latest.status == StaffFundRequestStatus.pending;
                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPending ? Colors.amber.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPending ? Colors.amber.shade300 : Colors.green.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPending ? Icons.hourglass_top : Icons.verified,
                            color: isPending ? Colors.orange : Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPending
                                  ? 'Request for ₹${latest.requestedAmount.toStringAsFixed(0)} is pending Admin transfer.'
                                  : 'Admin transferred ₹${(latest.fundedAmount ?? latest.requestedAmount).toStringAsFixed(0)} via ${latest.paymentMode ?? "Bank"} (UTR: ${latest.transactionRef ?? "Completed"}).',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isPending ? Colors.amber.shade900 : Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Ground Staff Payroll Disbursal (Responsive header with Wrap)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Staff Roster & Wage Disbursal',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: const Text('Cycle: September 2026', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (staffList.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('No operational staff registered yet. Add staff under "Staff Management".',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            )
          else
            ...staffList.map((staff) {
              final isPaid = payments.any((p) => p.staffId == staff.id && p.monthYear == 'September 2026');
              final paymentRecord = payments.where((p) => p.staffId == staff.id && p.monthYear == 'September 2026').firstOrNull;

              double defaultWage = 15000.0;
              if (staff.roleTitle.toLowerCase().contains('chef') || staff.roleTitle.toLowerCase().contains('cook')) {
                defaultWage = 18000.0;
              } else if (staff.roleTitle.toLowerCase().contains('housekeep')) {
                defaultWage = 12000.0;
              } else if (staff.roleTitle.toLowerCase().contains('security')) {
                defaultWage = 14000.0;
              } else if (staff.roleTitle.toLowerCase().contains('maintenance') || staff.roleTitle.toLowerCase().contains('electric')) {
                defaultWage = 16000.0;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1.5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: isPaid ? Colors.green.shade100 : Colors.blueGrey.shade100,
                            child: Icon(Icons.person, color: isPaid ? Colors.green.shade900 : Colors.blueGrey.shade800),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPaid ? Colors.green.shade100 : Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isPaid ? 'PAID (SEP)' : 'PENDING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isPaid ? Colors.green.shade900 : Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Role: ${staff.roleTitle} | Phone: ${staff.phone}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Standard Monthly Wage: ₹${defaultWage.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isPaid ? 'Payment Status: Settled' : 'Cycle Action',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          if (isPaid && paymentRecord != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('₹${paymentRecord.amount.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                                const SizedBox(width: 6),
                                Text('(${paymentRecord.paymentMode})', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            )
                          else
                            ElevatedButton.icon(
                              icon: const Icon(Icons.payments_outlined, size: 16),
                              label: const Text('Disburse Salary'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _openDisburseStaffSalaryDialog(resortId, staff, defaultWage),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 24),
          const Text(
            'Staff Salary Receipts & Disbursal History',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),

          if (payments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text('No staff salary payments disbursed yet.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            )
          else
            ...payments.map((p) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade50,
                      child: const Icon(Icons.receipt_long, color: Colors.green),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${p.staffName} (${p.roleTitle})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('₹${p.amount.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    subtitle: Text('Cycle: ${p.monthYear} | Mode: ${p.paymentMode} | Ref: ${p.transactionRef}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PAID & EXPENSED',
                        style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  void _openDisburseStaffSalaryDialog(String resortId, StaffMember staff, double suggestedAmount) {
    final monthCtrl = TextEditingController(text: 'September 2026');
    final amountCtrl = TextEditingController(text: suggestedAmount.toStringAsFixed(2));
    final refCtrl = TextEditingController(text: 'VOUCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    String paymentMode = 'UPI Transfer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.payments, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Disburse Wage: ${staff.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 500 ? 460 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE7E5E4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.badge, color: AppTheme.resortCharcoal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Role: ${staff.roleTitle} | Phone: ${staff.phone}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.resortDarkText)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: monthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payroll Cycle / Month *',
                      prefixIcon: Icon(Icons.calendar_month),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Wage / Salary Amount (₹) *',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: const InputDecoration(
                      labelText: 'Disbursal Mode',
                      prefixIcon: Icon(Icons.payment),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'UPI Transfer', child: Text('UPI Transfer')),
                      DropdownMenuItem(value: 'Cash Voucher', child: Text('Cash Voucher')),
                      DropdownMenuItem(value: 'Direct Bank Transfer', child: Text('Direct Bank Transfer')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => paymentMode = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Receipt / Voucher Reference *',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '⚠️ Disbursing staff wage automatically records an expense under "staff_salary" in the resort financial ledger.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Disburse Wage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final month = monthCtrl.text.trim();
                final ref = refCtrl.text.trim();

                if (amt <= 0 || month.isEmpty || ref.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields.')),
                  );
                  return;
                }

                _store.disburseStaffSalary(
                  resortId: resortId,
                  staffId: staff.id,
                  staffName: staff.name,
                  roleTitle: staff.roleTitle,
                  amount: amt,
                  monthYear: month,
                  paymentMode: paymentMode,
                  transactionRef: ref,
                );

                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Salary of ₹${amt.toStringAsFixed(2)} disbursed to ${staff.name} and logged in ledger.'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openRequestStaffSalaryFundsDialog(String resortId, List<StaffMember> staffList) {
    // Calculate total standard wages needed
    double calculatedTotal = 0;
    for (final staff in staffList) {
      if (staff.roleTitle.toLowerCase().contains('chef') || staff.roleTitle.toLowerCase().contains('cook')) {
        calculatedTotal += 18000.0;
      } else if (staff.roleTitle.toLowerCase().contains('housekeep')) {
        calculatedTotal += 12000.0;
      } else if (staff.roleTitle.toLowerCase().contains('security')) {
        calculatedTotal += 14000.0;
      } else if (staff.roleTitle.toLowerCase().contains('maintenance') || staff.roleTitle.toLowerCase().contains('electric')) {
        calculatedTotal += 16000.0;
      } else {
        calculatedTotal += 15000.0;
      }
    }
    if (calculatedTotal == 0) calculatedTotal = 60000.0;

    final monthCtrl = TextEditingController(text: 'September 2026');
    final amountCtrl = TextEditingController(text: calculatedTotal.toStringAsFixed(2));
    final notesCtrl = TextEditingController(text: 'Monthly payroll for ${staffList.length} operational ground staff members.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.request_quote, color: AppTheme.resortCoral),
            SizedBox(width: 10),
            Text('Request Staff Funds from Admin'),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width > 500 ? 460 : double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submit your monthly ground staff wage bill to the Resort Admin. Once Admin reviews and transfers the amount, funds will be credited to your payroll pool.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: monthCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Salary Cycle Month & Year *',
                    hintText: 'e.g. September 2026',
                    prefixIcon: Icon(Icons.calendar_month, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total Salary Amount Required (₹) *',
                    prefixIcon: Icon(Icons.currency_rupee, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Justification to Admin *',
                    hintText: 'e.g. Wages for Chef, Housekeeping, Security',
                    prefixIcon: Icon(Icons.note_alt_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.resortCoral,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
              final month = monthCtrl.text.trim();
              if (amt <= 0 || month.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid month and amount.')),
                );
                return;
              }
              final user = _store.currentUser;
              _store.requestStaffSalaryFunds(
                resortId: resortId,
                inchargeEmail: user?.email ?? 'incharge@resorthub.com',
                inchargeName: user?.fullName ?? 'Operations Incharge',
                monthYear: month,
                requestedAmount: amt,
                staffCount: staffList.length,
                notes: notesCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Staff salary fund request of ₹${amt.toStringAsFixed(2)} submitted to Admin!'),
                  backgroundColor: Colors.blue.shade800,
                ),
              );
            },
            child: const Text('Submit Request to Admin'),
          ),
        ],
      ),
    );
  }
}

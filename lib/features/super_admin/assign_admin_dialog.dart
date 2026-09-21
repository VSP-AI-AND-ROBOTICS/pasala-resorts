import 'package:flutter/material.dart';
import '../../core/models/resort.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';

class AssignAdminDialog extends StatefulWidget {
  final Resort resort;

  const AssignAdminDialog({super.key, required this.resort});

  @override
  State<AssignAdminDialog> createState() => _AssignAdminDialogState();
}

class _AssignAdminDialogState extends State<AssignAdminDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MockDataStore _store = MockDataStore.instance;

  String? _selectedAdminEmail;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController(text: 'password123');
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final currentAdmin = _store.getAssignedAdminForResort(widget.resort.id);
    _selectedAdminEmail = currentAdmin?.email;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleAssignExisting() {
    if (_selectedAdminEmail == null) {
      _store.unassignAdminFromResort(widget.resort.id);
    } else {
      _store.assignAdminToResort(_selectedAdminEmail!, widget.resort.id);
    }
    Navigator.of(context).pop(true);
  }

  void _handleCreateNew() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (_store.profiles.containsKey(email)) {
      setState(() => _errorMessage = 'An account with this email already exists.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    _store.createAndAssignAdmin(
      fullName: name,
      email: email,
      resortId: widget.resort.id,
      phone: phone.isNotEmpty ? phone : null,
      password: password.isNotEmpty ? password : 'password123',
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final allAdmins = _store.profiles.values.where((p) => p.role == AppRole.admin).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
        color: Theme.of(context).cardColor,
        child: Column(
          children: [
            // BookMyShow Style Header
            Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF1F2533),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE23744).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings, color: Color(0xFFE23744), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Assign Resort Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(widget.resort.name, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFE23744),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFE23744),
              indicatorWeight: 3,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Registered Admins'),
                Tab(text: 'Register New Admin'),
              ],
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // --- TAB 1: SELECT & AUTO-FILL UNASSIGNED ADMIN ---
                    Column(
                      children: [
                        Expanded(
                          child: allAdmins.isEmpty
                              ? const Center(child: Text('No admin accounts registered yet.'))
                              : ListView.builder(
                                  itemCount: allAdmins.length,
                                  itemBuilder: (context, index) {
                                    final admin = allAdmins[index];
                                    final isAssignedToOther = admin.resortId != null && admin.resortId != widget.resort.id;
                                    final otherResortName = isAssignedToOther ? _store.resorts[admin.resortId]?.name ?? 'Another Resort' : null;
                                    final isCurrentlyAssigned = admin.resortId == widget.resort.id;
                                    final isSelected = _selectedAdminEmail == admin.email;

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      elevation: isSelected ? 2 : 0,
                                      color: isAssignedToOther
                                          ? Colors.grey.shade100
                                          : (isSelected ? const Color(0xFFFFF1F2) : Colors.white),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: isSelected ? const Color(0xFFE23744) : Colors.grey.shade300,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: isAssignedToOther
                                            ? null
                                            : () {
                                                setState(() {
                                                  _selectedAdminEmail = admin.email;
                                                });
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                                    color: isAssignedToOther
                                                        ? Colors.grey.shade400
                                                        : (isSelected ? const Color(0xFFE23744) : Colors.grey),
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      admin.fullName,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                        color: isAssignedToOther ? Colors.grey : const Color(0xFF1F2533),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isAssignedToOther)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.shade50,
                                                        border: Border.all(color: Colors.red.shade200),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: const Text(
                                                        'Assigned',
                                                        style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                                      ),
                                                    )
                                                  else if (isCurrentlyAssigned)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.shade50,
                                                        border: Border.all(color: Colors.green.shade300),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: const Text(
                                                        'Current Manager',
                                                        style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.shade50,
                                                        border: Border.all(color: Colors.blue.shade200),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: const Text(
                                                        'Unassigned',
                                                        style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 30),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.email_outlined, size: 12, color: Colors.grey),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            admin.email,
                                                            style: TextStyle(color: isAssignedToOther ? Colors.grey : Colors.blueGrey.shade700, fontSize: 11),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (isAssignedToOther && otherResortName != null) ...[
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        'Assigned to: $otherResortName',
                                                        style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontStyle: FontStyle.italic),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _handleAssignExisting,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE23744),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CONFIRM ADMIN ASSIGNMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),

                    // --- TAB 2: REGISTER NEW ADMIN ---
                    SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Register a new Resort Manager profile and bind them to ${widget.resort.name}.',
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Full Name *',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Full Name is required *' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email Address *',
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Email Address is required *';
                                if (!val.contains('@')) return 'Please enter a valid email address';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Mobile Number *',
                                prefixIcon: const Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Mobile Number is required *' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password *',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Password is required *';
                                if (val.trim().length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleCreateNew,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE23744),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('REGISTER & ASSIGN ADMIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

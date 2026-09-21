import 'package:flutter/material.dart';
import '../../core/models/resort.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';

class AssignInchargeDialog extends StatefulWidget {
  final Resort resort;

  const AssignInchargeDialog({super.key, required this.resort});

  @override
  State<AssignInchargeDialog> createState() => _AssignInchargeDialogState();
}

class _AssignInchargeDialogState extends State<AssignInchargeDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MockDataStore _store = MockDataStore.instance;

  String? _selectedInchargeEmail;

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
    final currentIncharge = _store.getInchargeForResort(widget.resort.id);
    _selectedInchargeEmail = currentIncharge?.email;
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
    if (_selectedInchargeEmail == null) {
      _store.unassignInchargeFromResort(widget.resort.id);
    } else {
      _store.assignInchargeToResort(_selectedInchargeEmail!, widget.resort.id);
    }
    Navigator.of(context).pop(true);
  }

  void _handleCreateNew() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (_store.profiles.containsKey(email.toLowerCase())) {
      setState(() => _errorMessage = 'An account with this email address already exists.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    _store.addInchargeForResort(
      resortId: widget.resort.id,
      fullName: name,
      email: email,
      phone: phone,
      password: password,
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final allIncharges = _store.profiles.values.where((p) => p.role == AppRole.incharge).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 660),
        color: Theme.of(context).cardColor,
        child: Column(
          children: [
            // Dark Header
            Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF1F2533),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF003580).withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.badge, color: Color(0xFFFEBB02), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Assign / Change Operations Incharge',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Resort: ${widget.resort.name}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              labelColor: const Color(0xFF003580),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF003580),
              indicatorWeight: 3,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Registered Incharges'),
                Tab(text: 'Register New Incharge'),
              ],
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // --- TAB 1: SELECT REGISTERED INCHARGE ---
                    Column(
                      children: [
                        Expanded(
                          child: allIncharges.isEmpty
                              ? const Center(child: Text('No Operations Incharge profiles registered yet.'))
                              : ListView.builder(
                                  itemCount: allIncharges.length,
                                  itemBuilder: (context, index) {
                                    final incharge = allIncharges[index];
                                    final isAssignedToOther = incharge.resortId != null && incharge.resortId != widget.resort.id;
                                    final otherResortName = isAssignedToOther ? _store.resorts[incharge.resortId]?.name ?? 'Another Resort' : null;
                                    final isCurrentlyAssigned = incharge.resortId == widget.resort.id;
                                    final isSelected = _selectedInchargeEmail == incharge.email;

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      elevation: isSelected ? 2 : 0,
                                      color: isAssignedToOther
                                          ? Colors.grey.shade100
                                          : (isSelected ? Colors.blue.shade50 : Colors.white),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: isSelected ? const Color(0xFF003580) : Colors.grey.shade300,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: isAssignedToOther
                                            ? null
                                            : () {
                                                setState(() {
                                                  _selectedInchargeEmail = incharge.email;
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
                                                        : (isSelected ? const Color(0xFF003580) : Colors.grey),
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      incharge.fullName,
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
                                                        'Current Incharge',
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
                                                            'Work Mail: ${incharge.email}',
                                                            style: TextStyle(
                                                              color: isAssignedToOther ? Colors.grey : Colors.blueGrey.shade700,
                                                              fontSize: 11,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.phone_outlined, size: 12, color: Colors.grey),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Mobile: ${incharge.phone}',
                                                          style: TextStyle(
                                                            color: isAssignedToOther ? Colors.grey : Colors.blueGrey.shade700,
                                                            fontSize: 11,
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
                            backgroundColor: const Color(0xFF003580),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CONFIRM INCHARGE ASSIGNMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),

                    // --- TAB 2: REGISTER NEW INCHARGE ---
                    SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Register a new Operations Incharge profile with Work Mail & Password, then assign them to ${widget.resort.name}.',
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
                                labelText: 'Work Email / Mail *',
                                hintText: 'incharge@resorthub.com',
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Work Email is required *';
                                if (!val.contains('@')) return 'Please enter a valid work email address';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Mobile Number *',
                                hintText: '+91 98765 22222',
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
                                backgroundColor: const Color(0xFF003580),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('REGISTER & ASSIGN INCHARGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

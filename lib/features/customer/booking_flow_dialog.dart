import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/resort.dart';
import '../../core/models/unit.dart';
import '../../core/models/reservation.dart';
import '../../core/models/payment.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../payments/payment_service.dart';

class BookingFlowDialog extends StatefulWidget {
  final Resort resort;
  final ResortUnit unit;

  const BookingFlowDialog({
    super.key,
    required this.resort,
    required this.unit,
  });

  @override
  State<BookingFlowDialog> createState() => _BookingFlowDialogState();
}

class _BookingFlowDialogState extends State<BookingFlowDialog> {
  late final TextEditingController _guestNameController;
  late final TextEditingController _guestEmailController;
  late final TextEditingController _guestPhoneController;
  
  DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOutDate = DateTime.now().add(const Duration(days: 3));
  int _guestCount = 2;
  PaymentKind _selectedPaymentKind = PaymentKind.advance;
  
  bool _isProcessing = false;
  String? _statusMessage;
  
  final DemoPaymentGateway _paymentGateway = DemoPaymentGateway();
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final user = MockDataStore.instance.currentUser;
    _guestNameController = TextEditingController(text: user?.fullName ?? 'Rahul Verma');
    _guestEmailController = TextEditingController(text: user?.email ?? 'customer@example.com');
    _guestPhoneController = TextEditingController(text: user?.phone ?? '+91 98765 44444');
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _guestEmailController.dispose();
    _guestPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectBookingDates() async {
    final isDark = AppTheme.isDark(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _checkInDate, end: _checkOutDate),
      builder: (context, child) {
        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.resortEmerald,
              brightness: isDark ? Brightness.dark : Brightness.light,
              primary: AppTheme.resortEmerald,
              surface: isDark ? const Color(0xFF16221D) : Colors.white,
              onSurface: isDark ? Colors.white : const Color(0xFF1C1917),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _checkInDate = picked.start;
        _checkOutDate = picked.end;
      });
    }
  }

  double get _totalNights => _checkOutDate.difference(_checkInDate).inDays.toDouble();
  double get _totalAmount => widget.unit.pricePerNight * (_totalNights <= 0 ? 1 : _totalNights);
  double get _advanceAmount => _totalAmount * 0.35; // 35% advance requirement

  void _processBookingAndPayment() async {
    final store = MockDataStore.instance;

    final isAvailable = store.isUnitAvailable(
      resortId: widget.resort.id,
      unitId: widget.unit.id,
      checkIn: _checkInDate,
      checkOut: _checkOutDate,
    );

    if (!isAvailable) {
      setState(() {
        _statusMessage = '⚠️ Selected dates are already reserved by another guest.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Creating reservation hold...';
    });

    final reservation = Reservation(
      id: 'res-${_uuid.v4().substring(0, 8)}',
      resortId: widget.resort.id,
      customerId: store.currentUser?.id ?? 'usr-customer',
      unitId: widget.unit.id,
      unitName: widget.unit.name,
      checkIn: _checkInDate,
      checkOut: _checkOutDate,
      totalAmount: _totalAmount,
      advanceAmount: _advanceAmount,
      status: ReservationStatus.pending,
      guestName: _guestNameController.text.trim(),
      guestPhone: _guestPhoneController.text.trim(),
      guestEmail: _guestEmailController.text.trim(),
      guestCount: _guestCount,
      createdAt: DateTime.now(),
    );

    // Save initial reservation
    store.reservations.add(reservation);

    setState(() {
      _statusMessage = 'Processing secure payment via Demo Gateway...';
    });

    final payAmount = _selectedPaymentKind == PaymentKind.advance ? _advanceAmount : _totalAmount;
    final idempotencyKey = 'idemp-bkg-${reservation.id}';

    final result = await _paymentGateway.processBookingPayment(
      reservation: reservation,
      amount: payAmount,
      paymentKind: _selectedPaymentKind,
      idempotencyKey: idempotencyKey,
      paymentMethod: 'card',
    );

    setState(() {
      _isProcessing = false;
    });

    if (result.isSuccess) {
      if (mounted) {
        _showBookingNotificationsDialog(reservation, payAmount, result.transactionRef);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment Failed: ${result.message}')),
        );
      }
    }
  }

  void _showBookingNotificationsDialog(Reservation reservation, double payAmount, String transactionRef) {
    final qrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=RES_${reservation.id}_${reservation.guestName.replaceAll(' ', '_')}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isDark = AppTheme.isDark(dialogCtx);
        final cardBg = AppTheme.cardBg(dialogCtx);
        final border = AppTheme.border(dialogCtx);
        final textPrimary = AppTheme.textPrimary(dialogCtx);
        final textMuted = AppTheme.textMuted(dialogCtx);

        return DefaultTabController(
          length: 2,
          child: Dialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // Top Banner Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF14241E) : AppTheme.resortCharcoal,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.green,
                          radius: 20,
                          child: Icon(Icons.check_circle, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Booking Confirmed!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('2 Notifications Dispatched by Admin (Ref: ${reservation.id})', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab Selection Bar
                  Container(
                    color: isDark ? const Color(0xFF192822) : Colors.grey.shade100,
                    child: TabBar(
                      labelColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFF075E54),
                      unselectedLabelColor: isDark ? textMuted : Colors.grey,
                      indicatorColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFF075E54),
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(icon: Icon(Icons.chat), text: 'WhatsApp Message'),
                        Tab(icon: Icon(Icons.email), text: 'Gmail Confirmation'),
                      ],
                    ),
                  ),

                  // Tab Contents
                  Expanded(
                    child: TabBarView(
                      children: [
                        // --- TAB 1: WHATSAPP MESSAGE ---
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF075E54),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('WhatsApp Message from Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text('To: ${reservation.guestName} (${reservation.guestPhone})', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF132820) : const Color(0xFFE7F7E8),
                                  border: Border.all(color: isDark ? const Color(0xFF224838) : Colors.green.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🙏 Thank You Message:',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF6EE7B7) : Colors.green.shade900, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Dear ${reservation.guestName}, thank you for choosing ${widget.resort.name}! We look forward to providing you with a memorable luxury stay experience.',
                                      style: TextStyle(fontSize: 12, height: 1.4, color: textPrimary),
                                    ),
                                    Divider(height: 18, color: border),
                                    Text('📋 Booking Summary:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textPrimary)),
                                    const SizedBox(height: 6),
                                    Text('• Reservation ID: ${reservation.id}', style: TextStyle(fontSize: 12, color: textPrimary)),
                                    Text('• Unit Booked: ${reservation.unitName}', style: TextStyle(fontSize: 12, color: textPrimary)),
                                    Text('• Check-in: ${reservation.checkIn.toString().split(' ')[0]}', style: TextStyle(fontSize: 12, color: textPrimary)),
                                    Text('• Check-out: ${reservation.checkOut.toString().split(' ')[0]}', style: TextStyle(fontSize: 12, color: textPrimary)),
                                    Text('• Paid Amount: ₹${payAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF34D399) : Colors.teal)),
                                    Divider(height: 18, color: border),
                                    Center(
                                      child: Text('📲 Express Check-in QR Code:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textPrimary)),
                                    ),
                                    const SizedBox(height: 8),
                                    Center(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          qrUrl,
                                          width: 140,
                                          height: 140,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => Container(
                                            width: 140,
                                            height: 140,
                                            color: isDark ? const Color(0xFF263A32) : Colors.grey.shade300,
                                            child: const Icon(Icons.qr_code, size: 60),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Center(
                                      child: Text('Present this QR code at front desk upon arrival.', style: TextStyle(fontSize: 10, color: textMuted)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- TAB 2: GMAIL CONFIRMATION ---
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD93025),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mail, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Gmail Confirmation Email', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text('To: ${reservation.guestEmail}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1B2722) : Colors.grey.shade50,
                                  border: Border.all(color: border),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Subject: Booking Confirmation - ${widget.resort.name} [Ref: ${reservation.id}]',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textPrimary),
                                    ),
                                    Divider(height: 16, color: border),
                                    Text('Dear ${reservation.guestName},', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Thank you for booking with ${widget.resort.name}! Your reservation has been successfully confirmed. Below are your official stay details and entry pass QR code.',
                                      style: TextStyle(fontSize: 12, height: 1.4, color: textPrimary),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E2E3E) : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('• Resort: ${widget.resort.name} (${widget.resort.city})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                          Text('• Room: ${reservation.unitName}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                          Text('• Total Stay Amount: ₹${reservation.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                          Text('• Paid Advance: ₹${payAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF34D399) : Colors.teal)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Center(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          qrUrl,
                                          width: 130,
                                          height: 130,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => Container(
                                            width: 130,
                                            height: 130,
                                            color: isDark ? const Color(0xFF263A32) : Colors.grey.shade300,
                                            child: const Icon(Icons.qr_code, size: 50),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Center(
                                      child: Text('Official Reservation Pass QR Code', style: TextStyle(fontSize: 10, color: textMuted)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Action Button
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.resortCoral,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          Navigator.pop(context);
                          context.go('/customer/my-bookings');
                        },
                        child: const Text('View My Bookings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textMuted = AppTheme.textMuted(context);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.beach_access, color: isDark ? AppTheme.resortMintPrimary : Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Book ${widget.unit.name}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textMuted),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              Divider(color: border),
              const SizedBox(height: 12),
              TextField(
                controller: _guestNameController,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: const InputDecoration(labelText: 'Guest Full Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _guestEmailController,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _guestPhoneController,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date Range Picker Row
              InkWell(
                onTap: _selectBookingDates,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261D19) : const Color(0xFFFFF1EE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF4A3026) : const Color(0xFFFFCCBF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, color: Color(0xFFFF5A36), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dates of Stay (Tap to Change)', style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              '${_checkInDate.toString().split(' ')[0]}  ➔  ${_checkOutDate.toString().split(' ')[0]} (${_totalNights.toInt()} nights)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_calendar, color: Color(0xFFFF5A36), size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Date Availability Check
              Builder(
                builder: (context) {
                  final isAvailable = MockDataStore.instance.isUnitAvailable(
                    resortId: widget.resort.id,
                    unitId: widget.unit.id,
                    checkIn: _checkInDate,
                    checkOut: _checkOutDate,
                  );

                  if (!isAvailable) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.red.shade700, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'BLOCKED: These dates are already reserved by another customer. Please tap above to select alternative dates.',
                              style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Guest Count Selector Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Number of Guests:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _guestCount > 1 ? () => setState(() => _guestCount--) : null,
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFFF5A36)),
                      ),
                      Text('$_guestCount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textPrimary)),
                      IconButton(
                        onPressed: _guestCount < 10 ? () => setState(() => _guestCount++) : null,
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF5A36)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: isDark ? const Color(0xFF162E25) : const Color(0xFFE6F4F1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: isDark ? const Color(0xFF234C3E) : const Color(0xFFB2DFDB)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Total Stay Amount:', style: TextStyle(fontSize: 13, color: textPrimary)),
                          ),
                          Text('₹${_totalAmount.toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Advance Required (35%):', style: TextStyle(fontSize: 13, color: textPrimary)),
                          ),
                          Text('₹${_advanceAmount.toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF34D399) : const Color(0xFF0F4A40), fontSize: 15)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Payment Kind Option:', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
              RadioListTile<PaymentKind>(
                activeColor: const Color(0xFFFF5A36),
                title: Text('Pay Advance Only (₹${_advanceAmount.toStringAsFixed(2)})'),
                value: PaymentKind.advance,
                groupValue: _selectedPaymentKind,
                onChanged: (val) => setState(() => _selectedPaymentKind = val!),
              ),
              RadioListTile<PaymentKind>(
                activeColor: const Color(0xFFFF5A36),
                title: Text('Pay Full Amount (₹${_totalAmount.toStringAsFixed(2)})'),
                value: PaymentKind.full,
                groupValue: _selectedPaymentKind,
                onChanged: (val) => setState(() => _selectedPaymentKind = val!),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(_statusMessage!, style: const TextStyle(color: Color(0xFF0F4A40), fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final isAvailable = MockDataStore.instance.isUnitAvailable(
                    resortId: widget.resort.id,
                    unitId: widget.unit.id,
                    checkIn: _checkInDate,
                    checkOut: _checkOutDate,
                  );

                  return ElevatedButton(
                    onPressed: (_isProcessing || !isAvailable) ? null : _processBookingAndPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAvailable ? const Color(0xFFFF5A36) : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: isAvailable ? 2 : 0,
                    ),
                    child: _isProcessing
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            isAvailable
                                ? 'Confirm & Pay ₹${(_selectedPaymentKind == PaymentKind.advance ? _advanceAmount : _totalAmount).toStringAsFixed(2)}'
                                : 'Selected Dates Blocked / Unavailable',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

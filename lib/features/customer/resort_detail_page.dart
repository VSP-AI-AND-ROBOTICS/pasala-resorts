import 'package:flutter/material.dart';
import '../../core/models/unit.dart';
import '../../core/services/mock_data_store.dart';
import 'booking_flow_dialog.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class ResortDetailPage extends StatelessWidget {
  final String resortId;

  const ResortDetailPage({super.key, required this.resortId});

  @override
  Widget build(BuildContext context) {
    final store = MockDataStore.instance;
    final resort = store.resorts[resortId];

    if (resort == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Property Not Found')),
        body: const Center(child: Text('Requested resort property is unavailable.')),
      );
    }

    final rawUnits = store.resortUnits[resortId] ?? [];
    final units = rawUnits.isNotEmpty
        ? rawUnits
        : [
            ResortUnit(
              id: 'unit-default-${resort.id}',
              resortId: resort.id,
              name: 'Standard Guest Room',
              type: 'room',
              capacity: 2,
              pricePerNight: 100.00,
              description: 'Comfortable guest room with air conditioning, ensuite bath, and free Wi-Fi.',
              status: 'available',
              amenities: const ['Air Conditioning', 'Free Wi-Fi', 'Ensuite Bath'],
              imageUrls: const [],
            )
          ];

    final primaryUnit = units.first;
    final scoreText = resort.rating >= 4.8 ? 'Superb' : (resort.rating >= 4.5 ? 'Fabulous' : 'Very Good');

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(resort.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Property Hero Image
            Stack(
              children: [
                if (resort.imageUrls.isNotEmpty)
                  Image.network(
                    resort.imageUrls.first,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 240,
                      color: Colors.blueGrey.shade800,
                      child: const Icon(Icons.hotel, size: 64, color: Colors.white),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF003580),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${resort.rating}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(scoreText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        const Text(' (1,480 reviews)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resort.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF003580))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Color(0xFF006CE4)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('${resort.address}, ${resort.city}, ${resort.state}', style: const TextStyle(color: Color(0xFF006CE4), fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.green.shade900.withOpacity(0.3) : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade400),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Free cancellation • No prepayment needed – pay at the property', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(resort.description, style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800)),
                  const SizedBox(height: 24),
                  Text('Most popular facilities', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: resort.amenities.map((a) => Chip(
                      label: Text(a),
                      backgroundColor: Theme.of(context).cardColor,
                      side: const BorderSide(color: Color(0xFF006CE4)),
                      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF006CE4)),
                    )).toList(),
                  ),
                  const SizedBox(height: 28),
                  Text('Select your room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF003580))),
                  const SizedBox(height: 14),
                  ...units.map((unit) => Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        color: Theme.of(context).cardColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(unit.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF003580))),
                                  ),
                                  Text('₹${unit.pricePerNight.toStringAsFixed(2)} / night',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFFEBB02) : const Color(0xFF1A1A1A))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(unit.description, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700)),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF006CE4),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => BookingFlowDialog(resort: resort, unit: unit),
                                  );
                                },
                                child: const Text('Select room', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Price per night', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  '₹${primaryUnit.pricePerNight.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006CE4), // Booking.com Blue
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => BookingFlowDialog(resort: resort, unit: primaryUnit),
                );
              },
              child: const Text('Reserve your stay', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),

      floatingActionButton: const AIAssistantFAB(),
    );
  }
}

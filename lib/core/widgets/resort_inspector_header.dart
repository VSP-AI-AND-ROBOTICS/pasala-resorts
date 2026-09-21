import 'package:flutter/material.dart';
import '../services/mock_data_store.dart';

class ResortInspectorHeader extends StatefulWidget {
  final VoidCallback onResortChanged;

  const ResortInspectorHeader({
    super.key,
    required this.onResortChanged,
  });

  @override
  State<ResortInspectorHeader> createState() => _ResortInspectorHeaderState();
}

class _ResortInspectorHeaderState extends State<ResortInspectorHeader> {
  final MockDataStore _store = MockDataStore.instance;

  @override
  Widget build(BuildContext context) {
    final selectedId = _store.superAdminSelectedResortId;
    final selectedResort = selectedId != null ? _store.resorts[selectedId] : null;

    return Container(
      color: Colors.teal.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.location_city, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              selectedResort != null ? 'Inspecting Resort: ${selectedResort.name}' : 'All Resorts Overview',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(width: 12),
            DropdownButton<String?>(
              value: selectedId,
              dropdownColor: Colors.teal.shade900,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              underline: const SizedBox(),
              hint: const Text('All Resorts', style: TextStyle(color: Colors.white70, fontSize: 12)),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Resorts Overview', style: TextStyle(color: Colors.white)),
                ),
                ..._store.resorts.values.map((r) => DropdownMenuItem<String?>(
                      value: r.id,
                      child: Text('${r.name} (${r.subscriptionTier.badgeText})', style: const TextStyle(color: Colors.white)),
                    )),
              ],
              onChanged: (newId) {
                setState(() {
                  _store.superAdminSelectedResortId = newId;
                });
                widget.onResortChanged();
              },
            ),
            if (selectedId != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _store.superAdminSelectedResortId = null;
                  });
                  widget.onResortChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Exit Inspection', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

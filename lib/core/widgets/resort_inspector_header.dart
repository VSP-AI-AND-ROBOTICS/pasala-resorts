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

    return Container(
      color: Colors.teal.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, color: Color(0xFFFEBB02), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Resort:',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedId,
                isExpanded: true,
                dropdownColor: const Color(0xFF00382E),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFEBB02)),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('🌐 All Resorts Overview', overflow: TextOverflow.ellipsis),
                  ),
                  ..._store.resorts.values.map((r) => DropdownMenuItem<String?>(
                        value: r.id,
                        child: Text('${r.name} (${r.subscriptionTier.badgeText})', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (newId) {
                  setState(() {
                    _store.superAdminSelectedResortId = newId;
                  });
                  widget.onResortChanged();
                },
              ),
            ),
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
                    Text('Reset', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

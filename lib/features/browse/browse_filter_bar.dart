import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/resort_search.dart';

/// The browse screen's search box, sort menu, "Clear filters" and amenity
/// chips. Stateless: `BrowseScreen` owns every value and hears about every
/// change through a callback, so there is one place that decides what to
/// search.
class BrowseFilterBar extends StatelessWidget {
  const BrowseFilterBar({
    super.key,
    required this.controller,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.sort,
    required this.sortOptions,
    required this.onSortChanged,
    required this.amenities,
    required this.selectedAmenity,
    required this.onAmenitySelected,
    required this.showClear,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;

  /// Always one of [sortOptions].
  final ResortSort sort;
  final List<ResortSort> sortOptions;
  final ValueChanged<ResortSort> onSortChanged;
  final List<String> amenities;
  final String? selectedAmenity;
  final ValueChanged<String?> onAmenitySelected;
  final bool showClear;
  final VoidCallback onClear;

  /// `search_resorts` refuses anything longer (P0041).
  static const maxQueryLength = 100;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('browse-search'),
            controller: controller,
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
            textInputAction: TextInputAction.search,
            maxLength: maxQueryLength,
            decoration: InputDecoration(
              labelText: 'Search resorts',
              hintText: 'Name, city or amenity',
              prefixIcon: const Icon(Icons.search),
              counterText: '',
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onSearchSubmitted('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              Icon(Icons.sort, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              DropdownButton<ResortSort>(
                key: const Key('browse-sort'),
                value: sort,
                underline: const SizedBox.shrink(),
                items: [
                  for (final option in sortOptions)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
              const Spacer(),
              if (showClear)
                TextButton(
                  key: const Key('browse-clear-filters'),
                  onPressed: onClear,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          if (amenities.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: selectedAmenity == null,
                    onSelected: (_) => onAmenitySelected(null),
                  ),
                  const SizedBox(width: Spacing.xs),
                  for (final amenity in amenities) ...[
                    FilterChip(
                      label: Text(amenity),
                      selected: selectedAmenity == amenity,
                      onSelected: (selected) =>
                          onAmenitySelected(selected ? amenity : null),
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/saved_address.dart';

/// Result returned by [SaveAddressDialog].
class SaveAddressResult {
  final String label;
  final bool didSave;

  const SaveAddressResult({required this.label, required this.didSave});
}

/// A bottom sheet / dialog that asks the user whether they want to save the
/// pinned location as a named address (Home, Work, or custom).
Future<SaveAddressResult?> showSaveAddressDialog(
  BuildContext context, {
  required String currentAddress,
  required double latitude,
  required double longitude,
  List<SavedAddress> existingAddresses = const [],
}) {
  return showModalBottomSheet<SaveAddressResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SaveAddressSheet(
      currentAddress: currentAddress,
      latitude: latitude,
      longitude: longitude,
      existingAddresses: existingAddresses,
    ),
  );
}

class _SaveAddressSheet extends StatefulWidget {
  final String currentAddress;
  final double latitude;
  final double longitude;
  final List<SavedAddress> existingAddresses;

  const _SaveAddressSheet({
    required this.currentAddress,
    required this.latitude,
    required this.longitude,
    required this.existingAddresses,
  });

  @override
  State<_SaveAddressSheet> createState() => _SaveAddressSheetState();
}

class _SaveAddressSheetState extends State<_SaveAddressSheet> {
  final _customController = TextEditingController();
  String? _selectedLabel;
  bool _showCustomField = false;

  // Labels that are already taken
  Set<String> get _takenLabels =>
      widget.existingAddresses.map((a) => a.label.toLowerCase()).toSet();

  // Standard labels minus 'Other' (handled separately via the custom field).
  List<String> get _availableLabels =>
      SavedAddress.labelOptions
          .where((l) =>
              l.toLowerCase() != 'other' &&
              !_takenLabels.contains(l.toLowerCase()))
          .toList();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Save this location?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            widget.currentAddress,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // Quick-label chips
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._availableLabels.map((label) => _buildLabelChip(label)),
              if (!_showCustomField &&
                  !_takenLabels.contains('other'))
                _buildLabelChip(
                  'Other',
                  icon: Icons.add,
                  onTap: () => setState(() => _showCustomField = true),
                ),
            ],
          ),

          // Custom label text field
          if (_showCustomField) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter a label (e.g. Gym, Parents)',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
          ],

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const SaveAddressResult(
                        label: '',
                        didSave: false,
                      )),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'No thanks',
                    style: TextStyle(color: Color(0xFF666666)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _canSave ? _onSave : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF5222D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Save Address',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  bool get _canSave =>
      _selectedLabel != null || _customController.text.trim().isNotEmpty;

  void _onSave() {
    final label = _selectedLabel ?? _customController.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(
      context,
      SaveAddressResult(label: label, didSave: true),
    );
  }

  Widget _buildLabelChip(
    String label, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedLabel == label;
    return GestureDetector(
      onTap: onTap ??
          () => setState(() {
                _selectedLabel = isSelected ? null : label;
                if (label == 'Other') _showCustomField = true;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFF1F0)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF5222D)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16,
                  color: isSelected
                      ? const Color(0xFFF5222D)
                      : const Color(0xFF666666)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? const Color(0xFFF5222D)
                    : const Color(0xFF333333),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

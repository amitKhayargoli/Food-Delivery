import 'package:flutter/material.dart';

/// A named address the user has explicitly saved (e.g. Home, Work).
class SavedAddress {
  final String label;
  final String address;
  final double latitude;
  final double longitude;
  final IconData icon;

  const SavedAddress({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.icon = Icons.home_outlined,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'iconCodePoint': icon.codePoint,
        'iconFontFamily': icon.fontFamily,
      };

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      label: json['label'] as String,
      address: json['address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      icon: iconForLabel(json['label'] as String? ?? ''),
    );
  }

  /// Pre-defined label options shown in the save dialog.
  static const List<String> labelOptions = ['Home', 'Work', 'Other'];

  /// Icon for a given label.
  static IconData iconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_outlined;
      case 'work':
        return Icons.work_outline;
      default:
        return Icons.location_on_outlined;
    }
  }
}

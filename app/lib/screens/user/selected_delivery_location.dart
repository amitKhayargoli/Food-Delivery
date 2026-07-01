class SelectedDeliveryLocation {
  final String address;
  final double latitude;
  final double longitude;

  const SelectedDeliveryLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory SelectedDeliveryLocation.fromJson(Map<String, dynamic> json) =>
      SelectedDeliveryLocation(
        address: json['address'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}

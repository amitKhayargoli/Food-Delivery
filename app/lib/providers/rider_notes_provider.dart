import 'package:flutter/foundation.dart';
import '../core/services/api_service.dart' as api;

/// Manages rider quick notes sent from delivery boys to customers.
/// Each note is associated with a specific order and sent via the API.
class RiderNotesProvider extends ChangeNotifier {
  final api.ApiService _apiService;

  RiderNotesProvider(this._apiService);

  /// In-flight note sending state per order ID
  final Set<String> _sendingOrderIds = {};

  /// The latest rider note for each order ID (client-side cache)
  final Map<String, String> _notesByOrderId = {};

  // ── Getters ──

  bool isSending(String orderId) => _sendingOrderIds.contains(orderId);

  String? getNote(String orderId) => _notesByOrderId[orderId];

  // ── Actions ──

  /// Send a rider note for the given order.
  /// Updates local cache optimistically, then sends via API.
  Future<void> sendRiderNote({
    required String orderId,
    required String note,
    required String token,
  }) async {
    if (note.trim().isEmpty) return;

    // Optimistic update
    _notesByOrderId[orderId] = note.trim();
    _sendingOrderIds.add(orderId);
    notifyListeners();

    try {
      await _apiService.addRiderNote(
        orderId: orderId,
        note: note.trim(),
        token: token,
      );
    } on api.ApiException catch (e) {
      debugPrint('[RiderNotes] Failed to send note: ${e.message}');
    } catch (e) {
      debugPrint('[RiderNotes] Unexpected error: $e');
    } finally {
      _sendingOrderIds.remove(orderId);
      notifyListeners();
    }
  }
}

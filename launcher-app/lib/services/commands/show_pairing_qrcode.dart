import '../bluetooth_service.dart';
import '../logger.dart';
import '../switcher_service.dart';
import 'command_repository.dart';

class ShowPairingQRCodeHandler implements CommandHandler {
  final SwitcherService _switcherService = SwitcherService();

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final show = data['show'] as bool;

      // When show is true, force FeralFile focus
      // When show is false, disable force focus to allow normal switching
      await _switcherService.forceFeralFileFocus(show);

      // Send success response if replyId is provided
      if (replyId != null) {
        bluetoothService.notify(replyId, {'success': true});
      }
    } catch (e) {
      logger.severe('Error in ShowPairingQRCodeHandler: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to manage QR code window: ${e.toString()}'
        });
      }
    }
  }
}

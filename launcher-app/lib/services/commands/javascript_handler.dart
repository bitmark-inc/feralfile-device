import '../logger.dart';
import '../cdp_client.dart';
import 'command_repository.dart';

class JavaScriptHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    try {
      final jsCode = "local_command('${data['command']}', '${data['data']}')";

      final result = await CDPClient.evaluateJavaScript(jsCode);

      if (result != null) {
        logger.info(
            'Command executed in Chromium: ${data['command']}, response: $result');
      } else {
        logger.warning(
            'Failed to execute command in Chromium: ${data['command']}');
      }
    } catch (e) {
      logger.severe('Error executing command in Chromium: $e');
    }
  }
}

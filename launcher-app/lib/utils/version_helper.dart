import 'package:feralfile/services/logger.dart';
import 'package:process_run/stdio.dart';

class VersionHelper {
  static String? _installedVersion;
  static DateTime? _lastUpdated;

  static Future<String?> getInstalledVersion() async {
    _installedVersion ??= await _getInstalledVersion();
    return _installedVersion;
  }

  static Future<String?> getLatestVersion(
      {bool forceUpdatePackageList = false}) async {
    try {
      await updatePackageList(forceUpdate: forceUpdatePackageList);
      ProcessResult result =
          await Process.run('apt-cache', ['policy', 'feralfile-launcher']);
      if (result.exitCode == 0) {
        String output = result.stdout.toString();
        RegExp regex = RegExp(r'Candidate:\s([^\s]+)');
        Match? match = regex.firstMatch(output);
        final version = match?.group(1);
        logger.info('[getLatestVersion] Latest version: $version');
        return version;
      } else {
        logger.info("Error fetching latest version: ${result.stderr}");
        return null;
      }
    } catch (e) {
      logger.info("Exception: $e");
      return null;
    }
  }

  static Future<String?> _getInstalledVersion() async {
    try {
      ProcessResult result =
          await Process.run('apt-cache', ['policy', 'feralfile-launcher']);
      if (result.exitCode == 0) {
        String output = result.stdout.toString();
        RegExp regex = RegExp(r'Installed:\s([^\s]+)');
        Match? match = regex.firstMatch(output);
        final version = match?.group(1);
        logger.info('[getInstalledVersion] Installed version: $version');
        return version;
      } else {
        logger.info("Error fetching latest version: ${result.stderr}");
        return null;
      }
    } catch (e) {
      logger.info("Exception: $e");
      return null;
    }
  }

  /// Update system package list
  static Future<void> updatePackageList({bool forceUpdate = false}) async {
    try {
      final sinceLastUpdate =
          DateTime.now().difference(_lastUpdated ?? DateTime(0));
      if (sinceLastUpdate.inMinutes < 15 && !forceUpdate) {
        logger.info(
            "Package list updated less than an hour ago. Skipping update.");
        return;
      }

      logger.info("Clearing apt cache...");
      ProcessResult clearCacheResult =
          await Process.run('sudo', ['apt-get', 'clean']);
      if (clearCacheResult.exitCode != 0) {
        logger.info("Error clearing apt cache: ${clearCacheResult.stderr}");
      } else {
        logger.info("Apt cache cleared successfully.");
      }

      logger.info("Updating package list...");
      ProcessResult result = await Process.run('sudo', ['apt-get', 'update']);

      if (result.exitCode == 0) {
        logger.info("Package list updated successfully.");
        _lastUpdated = DateTime.now();
      } else {
        logger.info("Error updating package list: ${result.stderr}");
      }
    } catch (e) {
      logger.info("Exception during package update: $e");
    }
  }

  static Future<ProcessResult> _updateSystem() async {
    logger.info("Updating the system...");
    ProcessResult result = await Process.run(
      'sudo',
      ['/home/feralfile/services/feralfile-updater.sh'],
    );

    if (result.exitCode == 0) {
      logger.info("Successfully installed latest version.");
      await getInstalledVersion();
    } else {
      // if there was an error, clear apt cache, update package list and try again
      logger.info("Error installing latest version: ${result.stderr}");
    }
    return result;
  }

  // update to latest version
  static Future<void> updateToLatestVersion() async {
    final latestVersion = await getLatestVersion(forceUpdatePackageList: true);
    final installedVersion = await getInstalledVersion();
    logger.info('[updateToLatestVersion] Latest version: $latestVersion');
    logger.info('[updateToLatestVersion] Installed version: $installedVersion');
    if (latestVersion == installedVersion) {
      logger.info("Already on the latest version: $latestVersion");
      return;
    }
    if (latestVersion != null) {
      try {
          logger.info("Trying to update the system...");
          await _updateSystem();
      } catch (e) {
        logger.info("Exception during system upgrade: $e");
      }
    } else {
      logger.info("Failed to get latest version.");
    }
  }
}

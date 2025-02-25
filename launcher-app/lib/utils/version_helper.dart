import 'package:feralfile/services/logger.dart';
import 'package:process_run/stdio.dart';

class VersionHelper {
  static String? _installedVersion;
  static DateTime? _lastUpdated;

  static Future<String?> getInstalledVersion() async {
    if (_installedVersion == null) {
      _installedVersion = await _getInstalledVersion();
    }
    return _installedVersion;
  }

  static Future<String?> getLatestVersion() async {
    try {
      await updatePackageList();
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
  static Future<void> updatePackageList() async {
    try {
      final sinceLastUpdate =
          DateTime.now().difference(_lastUpdated ?? DateTime(0));
      if (sinceLastUpdate.inHours < 3) {
        logger.info(
            "Package list updated less than an hour ago. Skipping update.");
        return;
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

  /// Install a specific version of feralfile-launcher
  static Future<void> updateToVersion(String version) async {
    try {
      await updatePackageList(); // First, update the package list

      logger.info("Installing feralfile-launcher version: $version");
      ProcessResult result = await Process.run(
        'sudo',
        ['apt-get', 'install', 'feralfile-launcher=$version'],
      );

      if (result.exitCode == 0) {
        logger.info("Successfully installed version $version.");
        _installedVersion = version;
      } else {
        logger.info("Error installing package: ${result.stderr}");
      }
    } catch (e) {
      logger.info("Exception during installation: $e");
    }
  }

  // update to latest version
  static Future<void> updateToLatestVersion() async {
    final latestVersion = await getLatestVersion();
    final installedVersion = await getInstalledVersion();
    logger.info('[updateToLatestVersion] Latest version: $latestVersion');
    logger.info('[updateToLatestVersion] Installed version: $installedVersion');
    if (latestVersion == installedVersion) {
      logger.info("Already on the latest version: $latestVersion");
      return;
    }
    if (latestVersion != null) {
      await updateToVersion(latestVersion);
    } else {
      logger.info("Failed to get latest version.");
    }
  }
}

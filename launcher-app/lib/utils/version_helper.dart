import 'package:feralfile/services/logger.dart';
import 'package:process_run/stdio.dart';

class VersionHelper {
  static Future<String?> getLatestVersion() async {
    try {
      ProcessResult result =
          await Process.run('apt-cache', ['policy', 'feralfile-launcher']);
      if (result.exitCode == 0) {
        String output = result.stdout.toString();
        logger.info('[getLatestVersion] Output: $output');
        RegExp regex = RegExp(r'Candidate:\s([^\s]+)');
        Match? match = regex.firstMatch(output);
        final version = match?.group(1);
        logger.info('[getLatestVersion] Latest version: $version');
        return version;
      } else {
        print("Error fetching latest version: ${result.stderr}");
        return null;
      }
    } catch (e) {
      print("Exception: $e");
      return null;
    }
  }

  static Future<String?> getInstalledVersion() async {
    try {
      ProcessResult result =
          await Process.run('apt-cache', ['policy', 'feralfile-launcher']);
      if (result.exitCode == 0) {
        String output = result.stdout.toString();
        logger.info('[getInstalledVersion] Output: $output');
        RegExp regex = RegExp(r'Installed:\s([^\s]+)');
        Match? match = regex.firstMatch(output);
        final version = match?.group(1);
        logger.info('[getInstalledVersion] Installed version: $version');
        return version;
      } else {
        print("Error fetching latest version: ${result.stderr}");
        return null;
      }
    } catch (e) {
      print("Exception: $e");
      return null;
    }
  }

  /// Update system package list
  static Future<void> updatePackageList() async {
    try {
      print("Updating package list...");
      ProcessResult result = await Process.run('sudo', ['apt-get', 'update']);

      if (result.exitCode == 0) {
        print("Package list updated successfully.");
      } else {
        print("Error updating package list: ${result.stderr}");
      }
    } catch (e) {
      print("Exception during package update: $e");
    }
  }

  /// Install a specific version of feralfile-launcher
  static Future<void> updateToVersion(String version) async {
    try {
      await updatePackageList(); // First, update the package list

      print("Installing feralfile-launcher version: $version");
      ProcessResult result = await Process.run(
        'sudo',
        ['apt-get', 'install', '-y', 'feralfile-launcher=$version'],
      );

      if (result.exitCode == 0) {
        print("Successfully installed version $version.");
      } else {
        print("Error installing package: ${result.stderr}");
      }
    } catch (e) {
      print("Exception during installation: $e");
    }
  }

  // update to latest version
  static Future<void> updateToLatestVersion() async {
    final latestVersion = await getLatestVersion();
    if (latestVersion != null) {
      await updateToVersion(latestVersion);
    } else {
      print("Failed to get latest version.");
    }
  }
}

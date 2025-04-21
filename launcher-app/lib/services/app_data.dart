import 'dart:io';

import 'package:feralfile/services/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ArtworkCrashData {
  final DateTime timestamp;
  final String? artworkName;

  ArtworkCrashData({
    required this.timestamp,
    this.artworkName,
  });

  factory ArtworkCrashData.fromJson(Map<String, dynamic> json) {
    return ArtworkCrashData(
      timestamp:
          DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      artworkName: json['artworkName'],
    );
  }
}

class CrashReportService {
  static CrashReportService? _instance;

  final String _rawDataFileName = 'artwork_crash_raw.csv';
  final String _reportFileName = 'artwork_crash_report.csv';
  File? _rawDataFile;
  File? _reportFile;

  // Singleton pattern
  factory CrashReportService() {
    _instance ??= CrashReportService._internal();
    return _instance!;
  }

  CrashReportService._internal();

  /// Initialize the service
  Future<void> init() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _rawDataFile = File('${appDocDir.path}/$_rawDataFileName');
      _reportFile = File('${appDocDir.path}/$_reportFileName');

      // Create raw data file with header if it doesn't exist
      if (!await _rawDataFile!.exists()) {
        await _rawDataFile!.create(recursive: true);
        await _rawDataFile!.writeAsString('Timestamp,ArtworkName\n');
      }
    } catch (e, s) {
      logger.severe('Failed to initialize CrashReportService: $e\n$s');
    }
  }

  /// Record a new crash
  Future<void> recordCrash(String? artworkName) async {
    try {
      if (_rawDataFile == null) {
        await init();
      }

      final crashData = ArtworkCrashData(
        timestamp: DateTime.now(),
        artworkName: artworkName,
      );

      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
      final csvRow =
          '${formatter.format(crashData.timestamp)},${_escapeCsv(artworkName ?? '')}';

      await _rawDataFile!.writeAsString('$csvRow\n', mode: FileMode.append);
      logger.info('Recorded artwork crash: artworkName=$artworkName');
    } catch (e, s) {
      logger.severe('Failed to record artwork crash: $e\n$s');
    }
  }

  /// Generate the hourly crash report
  Future<void> generateHourlyReport({DateTime? forDate}) async {
    try {
      if (_rawDataFile == null || _reportFile == null) {
        await init();
      }

      final targetDate = forDate ?? DateTime.now();
      final startOfDay =
          DateTime(targetDate.year, targetDate.month, targetDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Read raw crash data
      final rawData = await _getRawCrashData();

      // Filter data for the requested date
      final filteredData = rawData.where((crash) {
        return crash.timestamp.isAfter(startOfDay) &&
            crash.timestamp.isBefore(endOfDay);
      }).toList();

      // Group crashes by hour and artwork
      final hourlyReport = _groupByHourAndArtwork(filteredData);

      // Format as CSV in the requested layout
      final formattedReport = _formatHourlyReport(hourlyReport, startOfDay);

      // Write to report file
      await _reportFile!.writeAsString(formattedReport);

      logger.info(
          'Generated hourly crash report for ${DateFormat('yyyy-MM-dd').format(targetDate)}');
    } catch (e, s) {
      logger.severe('Failed to generate hourly report: $e\n$s');
    }
  }

  /// Get raw crash data from CSV
  Future<List<ArtworkCrashData>> _getRawCrashData() async {
    if (!await _rawDataFile!.exists()) {
      return [];
    }

    final content = await _rawDataFile!.readAsString();
    final lines = content.split('\n');

    // Skip header and parse each line
    final crashes = <ArtworkCrashData>[];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      try {
        final parts = _parseCsvLine(line);
        if (parts.length >= 2) {
          final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').parse(parts[0]);
          final artworkName = parts[1];

          crashes.add(ArtworkCrashData(
            timestamp: timestamp,
            artworkName: artworkName.isEmpty ? null : artworkName,
          ));
        }
      } catch (e) {
        logger.warning('Failed to parse crash data line: $line');
      }
    }

    return crashes;
  }

  /// Group crashes by hour interval and artwork name
  Map<String, Map<String, int>> _groupByHourAndArtwork(
      List<ArtworkCrashData> crashes) {
    final hourlyData = <String, Map<String, int>>{};

    for (final crash in crashes) {
      // Get hour interval (e.g., "1h-2h")
      final hour = crash.timestamp.hour;
      final hourInterval = '${hour}h-${hour + 1}h';

      // Initialize hour map if not exists
      hourlyData[hourInterval] ??= {};

      // Increment count for this artwork
      final artworkName = crash.artworkName ?? 'Unknown';
      hourlyData[hourInterval]![artworkName] =
          (hourlyData[hourInterval]![artworkName] ?? 0) + 1;
    }

    return hourlyData;
  }

  /// Format the hourly report according to the requested layout
  String _formatHourlyReport(
      Map<String, Map<String, int>> hourlyData, DateTime date) {
    final buffer = StringBuffer();
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final dateStr = dateFormatter.format(date);

    // Add header
    buffer.writeln('Date | Time | ArtworkName | Number of crashes');

    // Sort hours chronologically
    final sortedHours = hourlyData.keys.toList()
      ..sort((a, b) {
        final hourA = int.parse(a.split('h')[0]);
        final hourB = int.parse(b.split('h')[0]);
        return hourA.compareTo(hourB);
      });

    // Format each hour's data
    bool firstHour = true;
    for (final hourInterval in sortedHours) {
      final artworks = hourlyData[hourInterval]!;
      final sortedArtworks = artworks.keys.toList()..sort();

      bool firstArtwork = true;
      for (final artwork in sortedArtworks) {
        final count = artworks[artwork];

        if (firstHour && firstArtwork) {
          // First row has date, hour, artwork, count
          buffer.writeln('$dateStr | $hourInterval | $artwork | $count');
          firstArtwork = false;
        } else if (firstArtwork) {
          // First artwork in new hour has empty date cell
          buffer.writeln('          | $hourInterval | $artwork | $count');
          firstArtwork = false;
        } else {
          // Additional artworks have empty date and hour cells
          buffer.writeln('          |        | $artwork | $count');
        }
      }

      firstHour = false;
    }

    return buffer.toString();
  }

  /// Escape CSV values
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Parse a CSV line handling quoted values
  List<String> _parseCsvLine(String line) {
    // This is a simple parser and doesn't handle all CSV edge cases
    final result = <String>[];
    bool inQuotes = false;
    int startIndex = 0;

    for (int i = 0; i < line.length; i++) {
      if (line[i] == '"') {
        inQuotes = !inQuotes;
      } else if (line[i] == ',' && !inQuotes) {
        result.add(line.substring(startIndex, i).trim().replaceAll('"', ''));
        startIndex = i + 1;
      }
    }

    // Add the last part
    result.add(line.substring(startIndex).trim().replaceAll('"', ''));

    return result;
  }

  /// Get the path to the generated report file
  Future<String> get reportFilePath async {
    if (_reportFile == null) {
      await init();
    }
    return _reportFile!.path;
  }

  /// Clear all crash data
  Future<void> clearAllData() async {
    try {
      if (_rawDataFile == null) {
        await init();
      }

      await _rawDataFile!.writeAsString('Timestamp,ArtworkName\n');
      logger.info('Cleared all artwork crash data');
    } catch (e, s) {
      logger.severe('Failed to clear crash data: $e\n$s');
    }
  }
}

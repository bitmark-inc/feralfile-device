import 'dart:async';
import 'dart:io';

import 'package:feralfile/services/internet_connectivity_service.dart';
import 'logger.dart';

class SwitcherService {
  // Singleton instance.
  static final SwitcherService _instance = SwitcherService._internal();
  factory SwitcherService() => _instance;

  bool internetConnected = InternetConnectivityService().isOnline;
  bool _isChromiumRetrying = false;
  bool _forceFeralFileFocus = false;

  SwitcherService._internal() {
    // First focus
    if (internetConnected) {
      _focusChromium();
    } else {
      _focusFeralfile();
    }
    // Subscribe to connectivity changes.
    InternetConnectivityService().onStatusChange.listen((status) async {
      if (_forceFeralFileFocus) {
        // Changed condition
        await _focusFeralfile(); // Keep FeralFile focused when forced
        return;
      }

      if (status && !internetConnected) {
        logger.info('Connectivity online. Focusing Chromium.');
        await _focusChromium();
        internetConnected = true;
      } else if (!status && internetConnected) {
        // don't focus to launcher when the internet is off
        internetConnected = false;
      }
    });
  }

  // Environment variables required for xdotool.
  final Map<String, String> _env = {
    'DISPLAY': ':0',
    'XAUTHORITY': '/home/feralfile/.Xauthority',
    'XDG_RUNTIME_DIR': '/run/user/1000',
  };

  /// Forces FeralFile to be focused regardless of internet connectivity
  Future<void> forceFeralFileFocus(bool force) async {
    _forceFeralFileFocus = force;
    if (force) {
      logger.info(
          'Force mode enabled. Focusing FeralFile regardless of connectivity.');
      await _focusFeralfile();
    } else {
      logger.info(
          'Force mode disabled. Returning to normal connectivity-based switching.');
      // Return to normal behavior based on current connectivity
      if (internetConnected) {
        await _focusChromium();
      }
    }
  }

  /// Focuses Chromium using xdotool.
  /// If focusing fails, retries every 5 seconds until successful.
  Future<void> _focusChromium() async {
    if (_isChromiumRetrying || _forceFeralFileFocus)
      return; // Don't focus Chromium if FeralFile is forced
    _isChromiumRetrying = true;
    while (InternetConnectivityService().isOnline && !_forceFeralFileFocus) {
      try {
        // Get the currently active window.
        ProcessResult activeRes = await Process.run(
          'xdotool',
          ['getactivewindow'],
          environment: _env,
        );
        String activeWin = activeRes.stdout.toString().trim();

        // Find Chromium window (first visible instance).
        ProcessResult searchRes = await Process.run(
          'xdotool',
          ['search', '--onlyvisible', '--class', 'chromium'],
          environment: _env,
        );
        String output = searchRes.stdout.toString().trim();
        if (output.isEmpty) {
          logger.info('Chromium window not found. Retrying in 5 seconds...');
        } else {
          // Use the first found window.
          String winId = output.split('\n').first;
          if (winId != activeWin) {
            await Process.run(
              'xdotool',
              ['windowactivate', '--sync', winId],
              environment: _env,
            );
            logger.info('Activated Chromium window with id $winId.');
          }
          _isChromiumRetrying = false;
          return;
        }
      } catch (e) {
        logger.warning('Error focusing Chromium: $e');
      }
      // Wait 5 seconds before trying again.
      await Future.delayed(Duration(seconds: 5));
    }
    _isChromiumRetrying = false;
  }

  /// Focuses FeralFile using xdotool.
  Future<void> _focusFeralfile() async {
    try {
      // Get the currently active window.
      ProcessResult activeRes = await Process.run(
        'xdotool',
        ['getactivewindow'],
        environment: _env,
      );
      String activeWin = activeRes.stdout.toString().trim();

      // Find FeralFile window (first visible instance).
      ProcessResult searchRes = await Process.run(
        'xdotool',
        ['search', '--onlyvisible', '--class', 'feralfile'],
        environment: _env,
      );
      String output = searchRes.stdout.toString().trim();
      if (output.isEmpty) {
        logger.info('FeralFile window not found.');
        return;
      }
      // Use the first found window.
      String winId = output.split('\n').first;
      if (winId != activeWin) {
        await Process.run(
          'xdotool',
          ['windowactivate', '--sync', winId],
          environment: _env,
        );
        logger.info('Activated FeralFile window with id $winId.');
      }
    } catch (e) {
      logger.warning('Error focusing FeralFile: $e');
    }
  }
}

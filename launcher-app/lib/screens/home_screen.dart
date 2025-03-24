import 'package:feralfile/services/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../cubits/ble_connection_cubit.dart';
import '../cubits/ble_connection_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                builder: (context, state) {
                  String instructionText = '';
                  bool showLogInfo = false;
                  switch (state.status) {
                    case BLEConnectionStatus.initial:
                      instructionText = '';
                    case BLEConnectionStatus.connecting:
                      instructionText = 'Received Wi-Fi credentials.\n'
                          'Connecting to network "${state.ssid}"...';
                    case BLEConnectionStatus.connected:
                      instructionText = 'Connected successfully!\n'
                          'Launching display interface...';
                      showLogInfo = true;
                    case BLEConnectionStatus.failed:
                      instructionText =
                          'Failed to connect to network "${state.ssid}".\n\n'
                          'Please check your Wi-Fi credentials and try again.\n'
                          'Make sure the network is available and within range.';
                  }

                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        if (state.isProcessing) ...[
                          const SizedBox(height: 20),
                          const CircularProgressIndicator(),
                        ],
                        // Right panel instruction text moved here
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                instructionText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'PPMori',
                                  fontSize: 42,
                                  color: Colors.grey[300],
                                  height: 1.4,
                                ),
                              ),
                              if (state.status ==
                                  BLEConnectionStatus.initial) ...[
                                const SizedBox(height: 60),
                                Container(
                                  padding: const EdgeInsets.all(40),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: QrImageView(
                                    data:
                                        'https://link.feralfile.com/device_connect/${state.deviceId}',
                                    version: QrVersions.auto,
                                    size: 600,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Device ID: ${state.deviceId}',
                                  style: TextStyle(
                                    fontFamily: 'PPMori',
                                    fontSize: 24,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (state.version.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Version: ${state.version}',
                                    style: TextStyle(
                                      fontFamily: 'PPMori',
                                      fontSize: 16,
                                      color: Colors.grey[400],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        if (showLogInfo) ...[
                          const Divider(color: Colors.grey),
                          const SizedBox(height: 20),
                          Text(
                            'To access device logs, visit:',
                            style: TextStyle(
                              fontFamily: 'PPMori',
                              fontSize: 16,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'http://${state.localIp}:8080/logs.html',
                            style: const TextStyle(
                              fontFamily: 'PPMori',
                              fontSize: 20,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                        const Spacer(),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          // Log output overlay in bottom left
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 600,
              height: 400,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                border: Border(
                  top: BorderSide(color: Colors.grey[800]!),
                  right: BorderSide(color: Colors.grey[800]!),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[800]!),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'System Logs',
                          style: TextStyle(
                            fontFamily: 'PPMori',
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                        BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                          builder: (context, state) {
                            if (state.localIp.isNotEmpty) {
                              return Text(
                                'http://${state.localIp}:8080/logs.html',
                                style: const TextStyle(
                                  fontFamily: 'PPMori',
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LogView(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogView extends StatelessWidget {
  final ScrollController _scrollController = ScrollController();

  LogView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: _getLogStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final log = snapshot.data![index];
            return Text(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _getLogColor(log),
                height: 1.5,
              ),
            );
          },
        );
      },
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('SEVERE:')) return Colors.red;
    if (log.contains('WARNING:')) return Colors.orange;
    if (log.contains('INFO:')) return Colors.blue;
    return Colors.grey[400]!;
  }

  Stream<List<String>> _getLogStream() {
    return Stream.periodic(const Duration(seconds: 1)).map((_) => logBuffer);
  }
}

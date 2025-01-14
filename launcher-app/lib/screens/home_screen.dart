import 'package:feralfile/services/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../cubits/ble_connection_cubit.dart';
import '../cubits/ble_connection_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => BLEConnectionCubit()..startListening(),
      child: Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                // Left panel
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SvgPicture.asset(
                          'assets/images/ff-logo.svg',
                          height: 60,
                        ),
                        const SizedBox(height: 120),
                        const Text(
                          'Display exhibitions\nand your collection\nto any screen',
                          style: TextStyle(
                            fontFamily: 'PPMori',
                            fontSize: 72,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 100),
                        BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                          builder: (context, state) {
                            String instructionText = '';
                            bool showLogInfo = false;

                            switch (state.status) {
                              case BLEConnectionStatus.initial:
                                instructionText =
                                    'Open the Feral File app, go to the Profile tab,\n'
                                    'and select Wi-Fi. Wait until it finds a\n'
                                    'Feral File Display device and tap to connect.\n\n'
                                    'Make sure your phone is connected to the Wi-Fi\n'
                                    'network you want to use for the display.';
                              case BLEConnectionStatus.connecting:
                                instructionText =
                                    'Received Wi-Fi credentials.\n'
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

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Feral File Display',
                                  style: TextStyle(
                                    fontFamily: 'PPMori',
                                    fontSize: 28,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (state.isProcessing) ...[
                                  const SizedBox(height: 20),
                                  const CircularProgressIndicator(),
                                ],
                                // Right panel instruction text moved here
                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: Text(
                                      instructionText,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'PPMori',
                                        fontSize: 42,
                                        color: Colors.grey[300],
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
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
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Right panel remains the same
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

import 'package:feralfile/services/logger.dart';
import 'package:feralfile/utils/response_layout.dart';
import 'package:feralfile_app_theme/feral_file_app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../cubits/ble_connection_cubit.dart';
import '../cubits/ble_connection_state.dart';
import 'launch_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                      builder: (context, state) {
                        if (state.status == BLEConnectionStatus.connecting) {
                          return _connectingToWifiView(context, state.ssid);
                        }

                        if (state.status == BLEConnectionStatus.connected) {
                          return _connectedToWifiView(context, state.ssid);
                        }

                        return _qrCodeView(
                          context,
                          state.deviceId,
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(
                  height: 20.responsiveSize,
                ),
                versionTag(context),
                SizedBox(
                  height: 40.responsiveSize,
                ),
              ],
            ),
            // Log output overlay in bottom left
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: 600.responsiveSize,
                height: 400.responsiveSize,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(200),
                  border: const Border(
                    top: BorderSide(color: AppColor.greyMedium),
                    right: BorderSide(color: AppColor.greyMedium),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.responsiveSize),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColor.greyMedium),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'System Logs',
                            style: theme.textTheme.ppMori400Grey24Responsive,
                          ),
                          BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                            builder: (context, state) {
                              if (state.localIp.isNotEmpty) {
                                return Text(
                                  'http://${state.localIp}:8080/logs.html',
                                  style:
                                      theme.textTheme.ppMori400Grey24Responsive,
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

  Widget _connectingToWifiView(BuildContext context, String ssid) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Connecting to $ssid',
          style: theme.textTheme.ppMori400White24Responsive.copyWith(
            fontSize: 36.responsiveSize,
          ),
        ),
      ],
    );
  }

  Widget _connectedToWifiView(BuildContext context, String ssid) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Connected to $ssid',
          style: theme.textTheme.ppMori400White24Responsive.copyWith(
            fontSize: 36.responsiveSize,
          ),
        ),
      ],
    );
  }

  Widget _qrCodeView(BuildContext context, String deviceId) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        QrImageView(
          data: 'https://link.feralfile.com/device_connect/$deviceId',
          version: QrVersions.auto,
          size: ResponsiveLayout.qrCodeSize,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.white,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 20.responsiveSize),
        Text(
          deviceId,
          style: theme.textTheme.ppMori400Grey24Responsive,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class LogView extends StatelessWidget {
  final ScrollController _scrollController = ScrollController();

  LogView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          padding: EdgeInsets.all(8.responsiveSize),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final log = snapshot.data![index];
            return Text(
              log,
              style: theme.textTheme.ppMori400White24Responsive.copyWith(
                fontSize: 14.responsiveSize,
                color: _getLogColor(log),
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

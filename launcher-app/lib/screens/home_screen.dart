import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../cubits/ble_connection_cubit.dart';
import '../cubits/ble_connection_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
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

                      switch (state.status) {
                        case BLEConnectionStatus.initial:
                          instructionText =
                              'Open the Feral File app, go to the Profile tab,\n'
                              'and select Wi-Fi. Wait until it finds a\n'
                              'Feral File Display device and tap to connect.\n\n'
                              'Make sure your phone is connected to the Wi-Fi\n'
                              'network you want to use for the display.(TESTv1)';
                        case BLEConnectionStatus.connecting:
                          instructionText = 'Received Wi-Fi credentials.\n'
                              'Connecting to network "${state.ssid}"...';
                        case BLEConnectionStatus.connected:
                          instructionText = 'Connected successfully!\n'
                              'Launching display interface...';
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
                        ],
                      );
                    },
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

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
              padding: const EdgeInsets.all(40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/images/ff-logo.svg',
                    height: 60,
                  ),
                  const SizedBox(height: 80),
                  const Text(
                    'Display exhibitions\nand your collection\nto any screen',
                    style: TextStyle(
                      fontFamily: 'PPMori',
                      fontSize: 72,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 60),
                  Text(
                    'Open the Feral File app on your\nphone to sync your collection.',
                    style: TextStyle(
                      fontFamily: 'PPMori',
                      fontSize: 28,
                      color: Colors.grey[300],
                    ),
                  ),
                  const SizedBox(height: 20),
                  BlocBuilder<BLEConnectionCubit, BLEConnectionState>(
                    builder: (context, state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Display Name: ${state.displayName}',
                            style: TextStyle(
                              fontFamily: 'PPMori',
                              fontSize: 28,
                              color: Colors.grey[300],
                            ),
                          ),
                          if (state.isProcessing) ...[
                            const SizedBox(height: 20),
                            const CircularProgressIndicator(),
                            const SizedBox(height: 10),
                            Text(
                              state.statusMessage,
                              style: TextStyle(
                                fontFamily: 'PPMori',
                                fontSize: 24,
                                color: Colors.grey[400],
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
          // Right panel - Empty black background
          const Expanded(
            flex: 3,
            child: ColoredBox(
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

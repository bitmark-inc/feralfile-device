import 'dart:math';

import 'package:feralfile_app_theme/extensions/extensions.dart';
import 'package:flutter/material.dart';

class ResponsiveLayout {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static BuildContext get _context => navigatorKey.currentContext!;

  static double responsiveSize(double width) {
    final size = MediaQuery.of(_context).size;
    final minSize = min(
      size.width,
      size.height,
    );
    return width * (minSize / 1080);
  }

  static double get textSize {
    // 24 size for full hd screen
    // make the size linear with the screen size
    return responsiveSize(24);
  }

  static double get qrCodeSize {
    final size = MediaQuery.of(_context).size;
    final minSize = min(
      size.width,
      size.height,
    );
    return minSize * 0.25;
  }
}

extension TextThemeExtension on TextTheme {
  TextStyle get ppMori400WhiteResponsive {
    return ppMori400White16.copyWith(fontSize: ResponsiveLayout.textSize);
  }

  TextStyle get ppMori700WhiteResponsive {
    return ppMori700White16.copyWith(fontSize: ResponsiveLayout.textSize);
  }

  TextStyle get ppMori400GreyResponsive {
    return ppMori400Grey16.copyWith(fontSize: ResponsiveLayout.textSize);
  }
}

extension doubleExtension on double {
  // responsive size for 24
  double get responsiveSize {
    return ResponsiveLayout.responsiveSize(toDouble());
  }
}

extension intExtension on int {
  // responsive size for 24
  double get responsiveSize {
    return toDouble().responsiveSize;
  }
}

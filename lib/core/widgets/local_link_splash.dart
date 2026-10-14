import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

/// Branded startup screen shown while the app initializes.
///
/// Visually continuous with the native launch screen: same hero gradient and
/// the same splash logo asset, so the handoff from the OS window to Flutter's
/// first frame is seamless. The wordmark and progress bar fade in with a short
/// non-repeating entrance (skipped when the platform disables animations).
class LocalLinkSplashScreen extends StatefulWidget {
  const LocalLinkSplashScreen({super.key});

  static const logoAsset = 'assets/brand/splash_logo.png';

  @override
  State<LocalLinkSplashScreen> createState() => _LocalLinkSplashScreenState();
}

class _LocalLinkSplashScreenState extends State<LocalLinkSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The splash can be mounted before a Scaffold/Material ancestor exists.
    // Without Material, Text falls back to the engine's debug style which
    // paints the infamous yellow double underline. Own the Material here.
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(gradient: LocalLinkBrand.heroGradient),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
          child: Center(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Image.asset(
                  LocalLinkSplashScreen.logoAsset,
                  width: 148,
                  height: 148,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _fade,
              child: const Text(
                'LocalLink',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fade,
              child: Text(
                'Secure, local-first messaging',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 44),
            const SizedBox(
              width: 132,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0x33FFFFFF),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

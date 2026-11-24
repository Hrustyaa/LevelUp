import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Animated startup screen for LevelUp.
class LevelUpSplashScreen extends StatefulWidget {
  const LevelUpSplashScreen({
    super.key,
    required this.nextPage,
    this.animationDuration = const Duration(milliseconds: 1450),
  });

  /// Pass Welcome for first-time users, or Home for users who finished setup.
  final Widget nextPage;

  final Duration animationDuration;

  @override
  State<LevelUpSplashScreen> createState() => _LevelUpSplashScreenState();
}

class _LevelUpSplashScreenState extends State<LevelUpSplashScreen>
    with SingleTickerProviderStateMixin {
  static const String _markPath = 'assets/images/levelup_mark.png';

  late final AnimationController _controller;
  bool _started = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _openNextPage();
        return;
      }
      await precacheImage(const AssetImage(_markPath), context);
      if (mounted) _controller.forward();
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNextPage());
  }

  void _openNextPage() {
    if (!mounted || _navigated) return;
    _navigated = true;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.nextPage,
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  // Normalizes a section of the 0..1 master timeline.
  double _section(double t, double from, double to) {
    return ((t - from) / (to - from)).clamp(0.0, 1.0).toDouble();
  }

  Widget _mark({required double opacity, Offset offset = Offset.zero}) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(
        offset: offset,
        child: Image.asset(
          _markPath,
          width: 190,
          height: 127,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _markPiece({
    required bool isLeft,
    required double opacity,
    required Offset offset,
  }) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(
        offset: offset,
        child: ClipPath(
          clipper: _MarkHalfClipper(isLeft: isLeft),
          child: Image.asset(
            _markPath,
            width: 190,
            height: 127,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A0F10),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F10),
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            final backgroundIn = Curves.easeOut.transform(
              _section(t, 0.0, 0.45),
            );
            final assemble = Curves.easeOutCubic.transform(
              _section(t, 0.12, 0.53),
            );
            final piecesVisible =
                _section(t, 0.08, 0.19) * (1.0 - _section(t, 0.49, 0.67));
            final completeMarkVisible = _section(t, 0.52, 0.69);
            final wordIn = Curves.easeOutCubic.transform(
              _section(t, 0.55, 0.79),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _SplashBackgroundPainter(progress: backgroundIn),
                ),
                SafeArea(
                  child: Align(
                    alignment: const Alignment(0, -0.10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 210,
                          height: 132,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              _markPiece(
                                isLeft: true,
                                opacity: piecesVisible,
                                offset: Offset(
                                  -31 * (1.0 - assemble),
                                  17 * (1.0 - assemble),
                                ),
                              ),
                              _markPiece(
                                isLeft: false,
                                opacity: piecesVisible,
                                offset: Offset(
                                  24 * (1.0 - assemble),
                                  -16 * (1.0 - assemble),
                                ),
                              ),
                              // The exact approved mark takes over seamlessly.
                              Transform.scale(
                                scale: 0.985 + 0.015 * completeMarkVisible,
                                child: _mark(opacity: completeMarkVisible),
                              ),
                            ],
                          ),
                        ),
                        Opacity(
                          opacity: wordIn,
                          child: Transform.translate(
                            offset: Offset(0, 9 * (1.0 - wordIn)),
                            child: const Text(
                              'LevelUp',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFF8FAFB),
                                fontSize: 39,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                letterSpacing: -1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }
}

class _MarkHalfClipper extends CustomClipper<Path> {
  const _MarkHalfClipper({required this.isLeft});

  final bool isLeft;

  @override
  Path getClip(Size size) {
    final boundary = size.width * 0.51;
    return Path()..addRect(
      isLeft
          ? Rect.fromLTWH(0, 0, boundary, size.height)
          : Rect.fromLTWH(boundary, 0, size.width - boundary, size.height),
    );
  }

  @override
  bool shouldReclip(_MarkHalfClipper oldClipper) => isLeft != oldClipper.isLeft;
}

class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;

    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0F10));

    // The very subtle curved band from the approved storyboard.
    final curve = Path()
      ..moveTo(-w * 0.10, h * 1.04)
      ..cubicTo(w * 0.22, h * 0.95, w * 0.65, h * 0.86, w * 1.06, h * 0.755);

    final belowCurve = Path.from(curve)
      ..lineTo(w * 1.10, h * 1.10)
      ..lineTo(-w * 0.10, h * 1.10)
      ..close();

    canvas.drawPath(
      belowCurve,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            const Color(0x00122C09),
            Color.fromRGBO(31, 98, 12, 0.16 * progress),
            Color.fromRGBO(12, 40, 10, 0.16 * progress),
          ],
        ).createShader(rect),
    );

    canvas.drawPath(
      curve,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            const Color(0x00000000),
            Color.fromRGBO(98, 207, 31, 0.10 * progress),
            Color.fromRGBO(162, 252, 55, 0.71 * progress),
          ],
          stops: const [0.0, 0.54, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SplashBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

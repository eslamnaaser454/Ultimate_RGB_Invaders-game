import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/telemetry_provider.dart';
import '../utils/constants.dart';
import 'main_shell.dart';

/// Initial screen for entering ESP32 IP address and connecting.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  final _ipController = TextEditingController(text: '192.168.4.1');
  final _portController = TextEditingController(text: '81');
  late AnimationController _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _glowAnim.dispose();
    super.dispose();
  }

  void _connect() async {
    final provider = context.read<TelemetryProvider>();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 81;
    if (ip.isEmpty) return;
    await provider.connect(ip, port: port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: SafeArea(
        child: Consumer<TelemetryProvider>(
          builder: (context, prov, _) {
            if (prov.isConnected) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                );
              });
            }

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title with glow animation
                    AnimatedBuilder(
                      listenable: _glowAnim,
                      builder: (ctx, _) => Text(
                        'ULTIMATE\nRGB INVADERS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          height: 1.2,
                          color: AppConstants.neonCyan,
                          shadows: [
                            Shadow(
                              color: AppConstants.neonCyan.withValues(
                                  alpha: 0.3 + _glowAnim.value * 0.4),
                              blurRadius: 20 + _glowAnim.value * 20,
                            ),
                            Shadow(
                              color: AppConstants.neonMagenta.withValues(
                                  alpha: 0.2 + _glowAnim.value * 0.2),
                              blurRadius: 30,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('TELEMETRY DASHBOARD', style: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 13,
                      fontWeight: FontWeight.w600, letterSpacing: 6,
                    )),
                    const SizedBox(height: 48),

                    // Connection card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppConstants.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppConstants.neonCyan.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CONNECT TO ESP32', style: TextStyle(
                            color: AppConstants.neonCyan, fontSize: 12,
                            fontWeight: FontWeight.w700, letterSpacing: 2,
                          )),
                          const SizedBox(height: 20),
                          _buildField('IP ADDRESS', _ipController,
                              'e.g. 192.168.4.1'),
                          const SizedBox(height: 14),
                          _buildField('PORT', _portController, 'e.g. 81',
                              keyboardType: TextInputType.number),
                          const SizedBox(height: 24),

                          // Connect button
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: ElevatedButton(
                              onPressed: prov.isConnecting ? null : _connect,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.neonCyan,
                                foregroundColor: AppConstants.bgPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: prov.isConnecting
                                  ? SizedBox(width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppConstants.bgPrimary,
                                      ))
                                  : const Text('CONNECT', style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                    )),
                            ),
                          ),

                          // Error message
                          if (prov.lastError != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppConstants.neonRed
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppConstants.neonRed
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline,
                                      color: AppConstants.neonRed, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(prov.lastError!,
                                      style: TextStyle(
                                        color: AppConstants.neonRed,
                                        fontSize: 12,
                                      ))),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const MainShell()),
                        );
                      },
                      child: Text('SKIP TO DASHBOARD →', style: TextStyle(
                        color: AppConstants.textDim, fontSize: 12,
                        letterSpacing: 1,
                      )),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint,
      {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(
          color: AppConstants.textDim, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: TextStyle(color: AppConstants.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppConstants.textDim),
            filled: true,
            fillColor: AppConstants.bgSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppConstants.borderDim),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppConstants.borderDim),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppConstants.neonCyan),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reusable AnimatedWidget wrapper.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) => builder(context, child);
}

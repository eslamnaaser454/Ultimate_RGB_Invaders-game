import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/command_provider.dart';
import '../providers/telemetry_provider.dart';
import '../services/command_service.dart';
import '../utils/constants.dart';

/// Phase 6: Bot Control Dashboard + Input Injection + Runtime Parameters.
class BotControlScreen extends StatelessWidget {
  const BotControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CommandProvider>(builder: (context, prov, _) {
      return ListView(
        padding: const EdgeInsets.all(AppConstants.screenPadding),
        children: [
          _buildBotStatus(prov),
          const SizedBox(height: 12),
          _buildBotControls(context, prov),
          const SizedBox(height: 12),
          _buildBotMetrics(prov),
          const SizedBox(height: 12),
          _buildInputInjection(context, prov),
          const SizedBox(height: 12),
          _buildRuntimeParameters(context, prov),
          const SizedBox(height: 12),
          _buildStressControls(context, prov),
          const SizedBox(height: 80),
        ],
      );
    });
  }

  // ─── 1. Bot Status ────────────────────────────────────────────

  Widget _buildBotStatus(CommandProvider prov) {
    final bot = prov.botStatus;
    final modeColor = _botModeColor(bot.botMode);
    return _SectionCard(
      title: 'BOT STATUS',
      icon: Icons.smart_toy,
      accentColor: bot.active ? AppConstants.neonGreen : AppConstants.textDim,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (bot.active ? AppConstants.neonGreen : AppConstants.neonRed).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (bot.active ? AppConstants.neonGreen : AppConstants.neonRed).withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: bot.active ? AppConstants.neonGreen : AppConstants.neonRed)),
          const SizedBox(width: 6),
          Text(bot.active ? 'ACTIVE' : 'INACTIVE', style: TextStyle(color: bot.active ? AppConstants.neonGreen : AppConstants.neonRed, fontSize: 9, fontWeight: FontWeight.bold)),
        ]),
      ),
      child: Column(children: [
        Row(children: [
          _StatusTile('MODE', bot.botMode, modeColor),
          _StatusTile('TARGET', bot.target, AppConstants.neonCyan),
        ]),
        const SizedBox(height: 8),
        if (bot.activeActions.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: bot.activeActions.map((a) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppConstants.neonCyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(a, style: const TextStyle(color: AppConstants.neonCyan, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          )).toList()),
      ]),
    );
  }

  // ─── 2. Bot Controls ──────────────────────────────────────────

  Widget _buildBotControls(BuildContext context, CommandProvider prov) {
    return _SectionCard(
      title: 'BOT CONTROLS',
      icon: Icons.gamepad,
      accentColor: AppConstants.neonMagenta,
      child: Column(children: [
        Row(children: [
          _BotActionButton('START BOT', Icons.play_arrow, AppConstants.neonGreen, () => _sendCmd(context, 'start bot')),
          const SizedBox(width: 8),
          _BotActionButton('STOP BOT', Icons.stop, AppConstants.neonRed, () => _sendCmd(context, 'stop bot')),
        ]),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Text('BOT MODE', style: TextStyle(color: AppConstants.textDim, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1))),
        const SizedBox(height: 6),
        Row(children: [
          _ModeChip('AGGRESSIVE', AppConstants.neonRed, prov.botStatus.botMode == 'AGGRESSIVE', () => _sendCmd(context, 'set bot_mode AGGRESSIVE')),
          _ModeChip('DEFENSIVE', AppConstants.neonBlue, prov.botStatus.botMode == 'DEFENSIVE', () => _sendCmd(context, 'set bot_mode DEFENSIVE')),
          _ModeChip('CHAOS', AppConstants.neonMagenta, prov.botStatus.botMode == 'CHAOS', () => _sendCmd(context, 'set bot_mode CHAOS')),
          _ModeChip('PERFECT', AppConstants.neonGreen, prov.botStatus.botMode == 'PERFECT', () => _sendCmd(context, 'set bot_mode PERFECT')),
        ]),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Text('TARGET', style: TextStyle(color: AppConstants.textDim, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1))),
        const SizedBox(height: 6),
        Row(children: [
          _ModeChip('BOSS', AppConstants.neonRed, prov.botStatus.target == 'BOSS', () => _sendCmd(context, 'set bot_target BOSS')),
          _ModeChip('ENEMIES', AppConstants.neonOrange, prov.botStatus.target == 'ENEMIES', () => _sendCmd(context, 'set bot_target ENEMIES')),
          _ModeChip('PROJECTILES', AppConstants.neonYellow, prov.botStatus.target == 'PROJECTILES', () => _sendCmd(context, 'set bot_target PROJECTILES')),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              final telProv = context.read<TelemetryProvider>();
              final payload = prov.buildEmergencyStopPayload();
              telProv.sendCommand(payload);
              prov.recordSentCommand('emergency_stop');
            },
            icon: const Icon(Icons.emergency, size: 16),
            label: const Text('EMERGENCY STOP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.neonRed.withValues(alpha: 0.2),
              foregroundColor: AppConstants.neonRed,
              side: BorderSide(color: AppConstants.neonRed.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── 3. Bot Metrics ───────────────────────────────────────────

  Widget _buildBotMetrics(CommandProvider prov) {
    final bot = prov.botStatus;
    return _SectionCard(
      title: 'BOT METRICS',
      icon: Icons.speed,
      accentColor: AppConstants.neonCyan,
      child: Column(children: [
        Row(children: [
          _GaugeMetric('ACCURACY', bot.accuracy, AppConstants.neonGreen),
          _GaugeMetric('DODGE RATE', bot.dodgeRate, AppConstants.neonCyan),
          _GaugeMetric('COMBO RATE', bot.comboRate, AppConstants.neonMagenta),
        ]),
      ]),
    );
  }

  // ─── 4. Input Injection ───────────────────────────────────────

  Widget _buildInputInjection(BuildContext context, CommandProvider prov) {
    return _SectionCard(
      title: 'INPUT INJECTION',
      icon: Icons.touch_app,
      accentColor: AppConstants.neonYellow,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _InputButton('GREEN', Icons.circle, AppConstants.neonGreen, () => _injectInput(context, prov, 'SHOOT_GREEN')),
        _InputButton('RED', Icons.circle, AppConstants.neonRed, () => _injectInput(context, prov, 'SHOOT_RED')),
        _InputButton('BLUE', Icons.circle, AppConstants.neonBlue, () => _injectInput(context, prov, 'SHOOT_BLUE')),
        _InputButton('COMBO', Icons.auto_awesome, AppConstants.neonMagenta, () => _injectInput(context, prov, 'COMBO')),
        _InputButton('RAPID FIRE', Icons.bolt, AppConstants.neonOrange, () => _injectInput(context, prov, 'RAPID_FIRE')),
        _InputButton('RANDOM', Icons.shuffle, AppConstants.neonGreen, () => _injectInput(context, prov, 'RANDOM_MOVEMENT')),
      ]),
    );
  }

  // ─── 5. Runtime Parameters ────────────────────────────────────

  Widget _buildRuntimeParameters(BuildContext context, CommandProvider prov) {
    return _SectionCard(
      title: 'RUNTIME PARAMETERS',
      icon: Icons.tune,
      accentColor: AppConstants.neonBlue,
      child: Column(
        children: prov.runtimeParams.entries.map((e) {
          final param = e.value;
          return _ParameterSlider(
            paramKey: e.key,
            param: param,
            onChanged: (v) {
              prov.updateLocalParameter(e.key, v);
              final telProv = context.read<TelemetryProvider>();
              final payload = prov.buildParameterPayload(e.key, v);
              telProv.sendCommand(payload);
              prov.recordSentCommand('set ${e.key} ${v.toStringAsFixed(1)}');
            },
          );
        }).toList(),
      ),
    );
  }

  // ─── 6. Stress Controls ───────────────────────────────────────

  Widget _buildStressControls(BuildContext context, CommandProvider prov) {
    return _SectionCard(
      title: 'STRESS GAMEPLAY CONTROLS',
      icon: Icons.whatshot,
      accentColor: AppConstants.neonOrange,
      child: Column(children: [
        Row(children: [
          _BotActionButton('STRESS TEST', Icons.speed, AppConstants.neonOrange, () => _sendCmd(context, 'run stress_test')),
          const SizedBox(width: 8),
          _BotActionButton('SPAWN BOSS', Icons.dangerous, AppConstants.neonRed, () => _sendCmd(context, 'spawn boss')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _BotActionButton('RESTART', Icons.refresh, AppConstants.neonCyan, () => _sendCmd(context, 'restart game')),
          const SizedBox(width: 8),
          _BotActionButton('LEVEL 10', Icons.trending_up, AppConstants.neonGreen, () => _sendCmd(context, 'set level 10')),
        ]),
      ]),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────

  void _sendCmd(BuildContext context, String cmd) {
    final telProv = context.read<TelemetryProvider>();
    final cmdProv = context.read<CommandProvider>();
    final payload = cmdProv.buildCommandPayload(cmd);
    telProv.sendCommand(payload);
    cmdProv.recordSentCommand(cmd);
  }

  void _injectInput(BuildContext context, CommandProvider prov, String action) {
    final telProv = context.read<TelemetryProvider>();
    final payload = prov.buildInputPayload(action);
    telProv.sendCommand(payload);
    prov.recordInputInjection(action);
  }

  Color _botModeColor(String mode) {
    switch (mode) {
      case 'AGGRESSIVE': return AppConstants.neonRed;
      case 'DEFENSIVE': return AppConstants.neonBlue;
      case 'CHAOS': return AppConstants.neonMagenta;
      case 'PERFECT': return AppConstants.neonGreen;
      default: return AppConstants.textDim;
    }
  }
}

// ─── Reusable Widgets ────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.icon, required this.accentColor, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppConstants.bgCard, borderRadius: BorderRadius.circular(AppConstants.cardRadius), border: Border.all(color: accentColor.withValues(alpha: 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: Row(children: [
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: accentColor.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const Spacer(),
          if (trailing != null) trailing!,
        ])),
        const Divider(color: AppConstants.borderDim, height: 1),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatusTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppConstants.textDim, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ]),
    ));
  }
}

class _BotActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BotActionButton(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ]),
        ),
      ),
    ));
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ModeChip(this.label, this.color, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.fastAnim,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : AppConstants.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color.withValues(alpha: 0.6) : AppConstants.borderDim),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? color : AppConstants.textDim, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
      ),
    ));
  }
}

class _GaugeMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _GaugeMetric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Column(children: [
      Stack(alignment: Alignment.center, children: [
        SizedBox(width: 50, height: 50, child: CircularProgressIndicator(
          value: value / 100,
          strokeWidth: 4,
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation(color),
        )),
        Text('$value%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: AppConstants.textDim, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    ]));
  }
}

class _InputButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _InputButton(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 90, height: 50,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  final String paramKey;
  final RuntimeParameter param;
  final ValueChanged<double> onChanged;
  const _ParameterSlider({required this.paramKey, required this.param, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 100, child: Text(param.label, style: const TextStyle(color: AppConstants.textSecondary, fontSize: 11))),
        Expanded(child: SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppConstants.neonCyan,
            inactiveTrackColor: AppConstants.neonCyan.withValues(alpha: 0.1),
            thumbColor: AppConstants.neonCyan,
            overlayColor: AppConstants.neonCyan.withValues(alpha: 0.1),
            trackHeight: 3,
          ),
          child: Slider(
            value: param.value.clamp(param.min, param.max),
            min: param.min,
            max: param.max,
            divisions: ((param.max - param.min) / param.step).round(),
            onChanged: onChanged,
          ),
        )),
        SizedBox(width: 40, child: Text(param.value.toStringAsFixed(1), style: const TextStyle(color: AppConstants.neonCyan, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'), textAlign: TextAlign.right)),
      ]),
    );
  }
}

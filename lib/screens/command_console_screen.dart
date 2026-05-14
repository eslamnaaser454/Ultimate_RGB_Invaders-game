import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/command_provider.dart';
import '../providers/telemetry_provider.dart';
import '../utils/constants.dart';

/// Phase 6: Command Console Screen — terminal-style command interface.
class CommandConsoleScreen extends StatefulWidget {
  const CommandConsoleScreen({super.key});

  @override
  State<CommandConsoleScreen> createState() => _CommandConsoleScreenState();
}

class _CommandConsoleScreenState extends State<CommandConsoleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _cmdController = TextEditingController();
  final _scrollController = ScrollController();
  final _scriptController = TextEditingController();
  final _searchController = TextEditingController();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cmdController.dispose();
    _scrollController.dispose();
    _scriptController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _sendCommand(BuildContext context) {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;

    final telProv = context.read<TelemetryProvider>();
    final cmdProv = context.read<CommandProvider>();

    final warning = cmdProv.validateCommand(cmd);
    if (warning != null && warning.startsWith('WARNING:')) {
      _showDangerDialog(context, cmd, warning);
      return;
    }
    if (warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(warning), backgroundColor: AppConstants.neonRed),
      );
      return;
    }

    final payload = cmdProv.buildCommandPayload(cmd);
    telProv.sendCommand(payload);
    cmdProv.recordSentCommand(cmd);
    _cmdController.clear();
    setState(() => _showSuggestions = false);
  }

  void _showDangerDialog(BuildContext context, String cmd, String warning) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppConstants.bgCard,
        title: Row(children: [
          const Icon(Icons.warning_amber, color: AppConstants.neonOrange, size: 22),
          const SizedBox(width: 8),
          const Text('DANGEROUS COMMAND', style: TextStyle(color: AppConstants.neonOrange, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        content: Text(warning, style: const TextStyle(color: AppConstants.textSecondary, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: AppConstants.textDim))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final telProv = context.read<TelemetryProvider>();
              final cmdProv = context.read<CommandProvider>();
              final payload = cmdProv.buildCommandPayload(cmd);
              telProv.sendCommand(payload);
              cmdProv.recordSentCommand(cmd);
              _cmdController.clear();
            },
            child: const Text('EXECUTE', style: TextStyle(color: AppConstants.neonRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CommandProvider>(builder: (context, prov, _) {
      return Column(children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(controller: _tabController, children: [
            _buildConsoleTab(prov),
            _buildScriptTab(prov),
            _buildHistoryTab(prov),
            _buildPacketInspectorTab(prov),
          ]),
        ),
      ]);
    });
  }

  Widget _buildTabBar() {
    return Container(
      color: AppConstants.bgCard,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppConstants.neonCyan,
        labelColor: AppConstants.neonCyan,
        unselectedLabelColor: AppConstants.textDim,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        tabs: const [
          Tab(text: 'CONSOLE', icon: Icon(Icons.terminal, size: 16)),
          Tab(text: 'SCRIPTS', icon: Icon(Icons.code, size: 16)),
          Tab(text: 'HISTORY', icon: Icon(Icons.history, size: 16)),
          Tab(text: 'PACKETS', icon: Icon(Icons.receipt_long, size: 16)),
        ],
      ),
    );
  }

  // ─── Console Tab ──────────────────────────────────────────────

  Widget _buildConsoleTab(CommandProvider prov) {
    return Column(children: [
      _buildConsoleMetrics(prov),
      Expanded(child: _buildConsoleOutput(prov)),
      if (_showSuggestions) _buildSuggestions(prov),
      _buildCommandInput(),
    ]);
  }

  Widget _buildConsoleMetrics(CommandProvider prov) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppConstants.bgSurface,
      child: Row(children: [
        _MiniStat('SENT', '${prov.totalCommandsSent}', AppConstants.neonCyan),
        _MiniStat('OK', '${prov.successResponses}', AppConstants.neonGreen),
        _MiniStat('ERR', '${prov.errorResponses}', AppConstants.neonRed),
        _MiniStat('BOT', prov.botStatus.active ? 'ON' : 'OFF', prov.botStatus.active ? AppConstants.neonGreen : AppConstants.textDim),
      ]),
    );
  }

  Widget _buildConsoleOutput(CommandProvider prov) {
    final history = prov.commandHistory;
    if (history.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.terminal, color: AppConstants.neonCyan.withValues(alpha: 0.2), size: 48),
        const SizedBox(height: 12),
        Text('COMMAND CONSOLE READY', style: TextStyle(color: AppConstants.neonCyan.withValues(alpha: 0.4), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Text('Type a command below to begin...', style: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.5), fontSize: 11)),
      ]));
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(10),
      itemCount: history.length,
      itemBuilder: (_, i) {
        final entry = history[i];
        final isOut = entry.direction == 'OUT';
        final statusColor = _statusColor(entry.status);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.formattedTime, style: const TextStyle(color: AppConstants.textDim, fontSize: 10, fontFamily: 'monospace')),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: (isOut ? AppConstants.neonCyan : AppConstants.neonGreen).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
              child: Text(isOut ? '>' : '<', style: TextStyle(color: isOut ? AppConstants.neonCyan : AppConstants.neonGreen, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(entry.command, style: TextStyle(color: isOut ? AppConstants.neonCyan : AppConstants.textPrimary, fontSize: 12, fontFamily: 'monospace'))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
              child: Text(entry.status, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildSuggestions(CommandProvider prov) {
    final suggestions = prov.getSuggestions(_cmdController.text);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      color: AppConstants.bgCard,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (_, i) => InkWell(
          onTap: () {
            _cmdController.text = suggestions[i];
            _cmdController.selection = TextSelection.fromPosition(TextPosition(offset: suggestions[i].length));
            setState(() => _showSuggestions = false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(suggestions[i], style: const TextStyle(color: AppConstants.neonCyan, fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
      ),
    );
  }

  Widget _buildCommandInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppConstants.bgCard, border: Border(top: BorderSide(color: AppConstants.neonCyan.withValues(alpha: 0.2)))),
      child: Row(children: [
        Text('> ', style: TextStyle(color: AppConstants.neonCyan.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        Expanded(
          child: TextField(
            controller: _cmdController,
            style: const TextStyle(color: AppConstants.neonCyan, fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'Enter command...',
              hintStyle: TextStyle(color: AppConstants.textDim, fontSize: 13),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) => setState(() => _showSuggestions = v.isNotEmpty),
            onSubmitted: (_) => _sendCommand(context),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send_rounded, color: AppConstants.neonCyan, size: 20),
          onPressed: () => _sendCommand(context),
        ),
      ]),
    );
  }

  // ─── Script Tab ───────────────────────────────────────────────

  Widget _buildScriptTab(CommandProvider prov) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      _SectionCard(title: 'MACROS', icon: Icons.flash_on, accentColor: AppConstants.neonMagenta, child: _buildMacros(prov)),
      const SizedBox(height: 12),
      _SectionCard(title: 'SCRIPT EDITOR', icon: Icons.code, accentColor: AppConstants.neonCyan, child: _buildScriptEditor(prov)),
      const SizedBox(height: 80),
    ]);
  }

  Widget _buildMacros(CommandProvider prov) {
    return Wrap(spacing: 8, runSpacing: 8, children: prov.macros.entries.map((e) {
      return _MacroButton(
        name: e.key,
        commands: e.value,
        onExecute: () => _executeMacro(e.key, e.value),
      );
    }).toList());
  }

  void _executeMacro(String name, List<String> commands) {
    final telProv = context.read<TelemetryProvider>();
    final cmdProv = context.read<CommandProvider>();
    for (final cmd in commands) {
      final payload = cmdProv.buildCommandPayload(cmd);
      telProv.sendCommand(payload);
      cmdProv.recordSentCommand('[macro:$name] $cmd');
    }
  }

  Widget _buildScriptEditor(CommandProvider prov) {
    return Column(children: [
      TextField(
        controller: _scriptController,
        maxLines: 6,
        style: const TextStyle(color: AppConstants.neonGreen, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: '# Enter script commands...\nfire every 100ms\nmove left every 500ms',
          hintStyle: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.4), fontSize: 12),
          filled: true,
          fillColor: AppConstants.bgSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppConstants.neonCyan.withValues(alpha: 0.2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppConstants.neonCyan.withValues(alpha: 0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppConstants.neonCyan)),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              final commands = prov.parseScript(_scriptController.text);
              final telProv = context.read<TelemetryProvider>();
              for (final cmd in commands) {
                final payload = prov.buildCommandPayload(cmd);
                telProv.sendCommand(payload);
                prov.recordSentCommand('[script] $cmd');
              }
            },
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('RUN SCRIPT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.neonGreen.withValues(alpha: 0.2), foregroundColor: AppConstants.neonGreen),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(icon: const Icon(Icons.clear, color: AppConstants.textDim, size: 18), onPressed: () => _scriptController.clear()),
      ]),
    ]);
  }

  // ─── History Tab ──────────────────────────────────────────────

  Widget _buildHistoryTab(CommandProvider prov) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: AppConstants.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Search commands...',
            hintStyle: const TextStyle(color: AppConstants.textDim, fontSize: 12),
            prefixIcon: const Icon(Icons.search, color: AppConstants.textDim, size: 18),
            filled: true,
            fillColor: AppConstants.bgSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Expanded(child: _buildHistoryList(prov)),
    ]);
  }

  Widget _buildHistoryList(CommandProvider prov) {
    final filtered = prov.searchHistory(_searchController.text);
    if (filtered.isEmpty) {
      return Center(child: Text('No commands found', style: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.5), fontSize: 12)));
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final entry = filtered[i];
        final sc = _statusColor(entry.status);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppConstants.bgSurface, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(entry.direction == 'OUT' ? Icons.arrow_upward : Icons.arrow_downward, color: entry.direction == 'OUT' ? AppConstants.neonCyan : AppConstants.neonGreen, size: 14),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.command, style: const TextStyle(color: AppConstants.textPrimary, fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
              Text(entry.formattedTime, style: const TextStyle(color: AppConstants.textDim, fontSize: 9)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)), child: Text(entry.status, style: TextStyle(color: sc, fontSize: 8, fontWeight: FontWeight.bold))),
          ]),
        );
      },
    );
  }

  // ─── Packet Inspector Tab ─────────────────────────────────────

  Widget _buildPacketInspectorTab(CommandProvider prov) {
    final log = prov.packetLog;
    if (log.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long, color: AppConstants.textDim.withValues(alpha: 0.2), size: 40),
        const SizedBox(height: 8),
        Text('No packets captured', style: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.5), fontSize: 12)),
      ]));
    }
    return ListView.builder(
      itemCount: log.length,
      itemBuilder: (_, i) {
        final p = log[i];
        final isIn = p.direction == 'IN';
        final dirColor = isIn ? AppConstants.neonGreen : AppConstants.neonCyan;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppConstants.bgSurface, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Container(width: 20, alignment: Alignment.center, child: Text(isIn ? '◄' : '►', style: TextStyle(color: dirColor, fontSize: 10, fontFamily: 'monospace'))),
            const SizedBox(width: 4),
            Text(p.formattedTime, style: const TextStyle(color: AppConstants.textDim, fontSize: 9, fontFamily: 'monospace')),
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: dirColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)), child: Text(p.type, style: TextStyle(color: dirColor, fontSize: 8, fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            Expanded(child: Text(p.summary, style: const TextStyle(color: AppConstants.textSecondary, fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
          ]),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'SUCCESS': return AppConstants.neonGreen;
      case 'ERROR': case 'FAIL': return AppConstants.neonRed;
      case 'WARNING': return AppConstants.neonOrange;
      case 'SENT': return AppConstants.neonCyan;
      default: return AppConstants.textDim;
    }
  }
}

// ─── Reusable Widgets ────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: AppConstants.textDim, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    ]));
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.accentColor, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppConstants.bgCard, borderRadius: BorderRadius.circular(AppConstants.cardRadius), border: Border.all(color: accentColor.withValues(alpha: 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: Row(children: [
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: accentColor.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ])),
        const Divider(color: AppConstants.borderDim, height: 1),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]),
    );
  }
}

class _MacroButton extends StatelessWidget {
  final String name;
  final List<String> commands;
  final VoidCallback onExecute;
  const _MacroButton({required this.name, required this.commands, required this.onExecute});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: commands.join('\n'),
      child: Material(
        color: AppConstants.neonMagenta.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onExecute,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.flash_on, color: AppConstants.neonMagenta, size: 14),
              const SizedBox(width: 6),
              Text(name.toUpperCase(), style: const TextStyle(color: AppConstants.neonMagenta, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

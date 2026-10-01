import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/machine_resources.dart';
import '../shared/theme/app_icons.dart';
import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';
import '../state/machine_resource_monitor.dart';
import 'desktop_chrome.dart';

/// An anchored, read-only comparison; choosing a row pins the footer's scope.
class MachineResourcePanel extends StatefulWidget {
  const MachineResourcePanel({
    super.key,
    required this.monitor,
    required this.onClose,
  });
  final MachineResourceMonitor monitor;
  final VoidCallback onClose;

  @override
  State<MachineResourcePanel> createState() => _MachineResourcePanelState();
}

class _MachineResourcePanelState extends State<MachineResourcePanel> {
  final _scroll = ScrollController();
  final _rows = <String, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : event.logicalKey == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    final monitor = widget.monitor, machines = widget.monitor.machines;
    if (direction == 0 || machines.isEmpty) return KeyEventResult.ignored;
    final current = machines.indexWhere((m) => identical(m, monitor.selected));
    final next = (current + direction).clamp(0, machines.length - 1);
    final id = machines[next].machine.machineId;
    monitor.selectMachine(id);
    final context = _rows[id]?.currentContext;
    if (context != null) Scrollable.ensureVisible(context);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    child: Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: DesktopDialogSurface(
        radius: DesktopChrome.menuRadius,
        child: ListenableBuilder(
          listenable: widget.monitor,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final monitor = widget.monitor,
                  machines = widget.monitor.machines;
              final selected = monitor.selected,
                  reading = monitor.reading(selected);
              final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
              final compact = constraints.maxWidth < 420 * scale;
              final width = 58.0 * scale;
              _rows.removeWhere(
                (id, _) => !machines.any((m) => m.machine.machineId == id),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Machine',
                              style: DesktopChrome.metadata(),
                            ),
                          ),
                          if (!compact) ...[
                            for (final title in ['CPU', 'RAM', 'GPU'])
                              SizedBox(
                                width: width,
                                child: Text(
                                  title,
                                  textAlign: TextAlign.right,
                                  style: DesktopChrome.metadata(),
                                ),
                              ),
                            const SizedBox(width: 28),
                          ],
                        ],
                      ),
                    ),
                    Flexible(
                      child: Scrollbar(
                        controller: _scroll,
                        child: ListView(
                          controller: _scroll,
                          shrinkWrap: true,
                          children: [
                            if (machines.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'No machines connected',
                                  style: DesktopChrome.control(),
                                ),
                              ),
                            for (final state in machines)
                              _machine(
                                state,
                                identical(state, selected),
                                compact,
                                width,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('resource-follow-focus'),
                          onPressed: () => monitor.selectMachine(null),
                          style: TextButton.styleFrom(side: BorderSide.none),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Flexible(
                                child: Text('Follow focused pane'),
                              ),
                              if (monitor.followsFocus) ...[
                                const SizedBox(width: 8),
                                const Icon(AppIcons.check, size: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (selected != null) ...[
                      Divider(height: 16, color: AppPalette.divider),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected.machine.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopChrome.control(medium: true),
                                ),
                                const SizedBox(height: 8),
                                if (!monitor.available(selected))
                                  Text(
                                    'Disconnected',
                                    style: DesktopChrome.metadata(),
                                  ),
                                _detail(
                                  'Memory pressure',
                                  switch (reading?.memoryPressure) {
                                    'normal' => 'Normal',
                                    'warning' => 'High',
                                    'critical' => 'Critical',
                                    _ => '--',
                                  },
                                ),
                                _detail(
                                  'Memory used',
                                  reading?.memoryUsedBytes == null
                                      ? '--'
                                      : '${resourceBytes(reading!.memoryUsedBytes)} / ${resourceBytes(reading.memoryTotalBytes)}',
                                ),
                                _detail(
                                  'Swap',
                                  resourceBytes(reading?.swapUsedBytes),
                                ),
                                _detail(
                                  'Disk free',
                                  resourceBytes(reading?.diskFreeBytes),
                                ),
                                for (final gpu
                                    in reading?.gpus ?? <MachineGpu>[])
                                  _detail(
                                    gpu.name,
                                    resourcePercent(gpu.utilizationPercent),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _machine(
    MachineState state,
    bool selected,
    bool compact,
    double width,
  ) {
    final monitor = widget.monitor, value = widget.monitor.reading(state);
    final values = [
      resourcePercent(value?.cpuPercent),
      resourcePercent(value?.memoryPercent),
      resourcePercent(value?.busiestGpu?.utilizationPercent),
    ];
    final id = state.machine.machineId;
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.25,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final cells = [
      for (var i = 0; i < values.length; i++)
        if (compact)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              '${['CPU', 'RAM', 'GPU'][i]} ${values[i]}',
              style: style,
            ),
          )
        else
          SizedBox(
            width: width,
            child: Text(values[i], textAlign: TextAlign.right, style: style),
          ),
    ];
    final numbers = compact
        ? Wrap(runSpacing: 4, children: cells)
        : Row(mainAxisSize: MainAxisSize.min, children: cells);
    return Semantics(
      selected: selected,
      child: Tooltip(
        message:
            '${state.machine.displayName}${monitor.available(state) ? '' : ' — Disconnected'}',
        child: TextButton(
          key: _rows.putIfAbsent(id, GlobalKey.new),
          onPressed: () => monitor.selectMachine(id),
          style: ButtonStyle(
            side: const WidgetStatePropertyAll(BorderSide.none),
            alignment: Alignment.centerLeft,
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesktopChrome.rowRadius),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? AppDesktop.selection
                  : selected
                  ? AppSurface.accentWash
                  : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? AppDesktop.onSelection
                  : AppPalette.textPrimary,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.machine.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  if (!compact) numbers,
                  SizedBox(
                    width: 28,
                    child: selected
                        ? const Icon(AppIcons.check, size: 16)
                        : null,
                  ),
                ],
              ),
              if (compact) ...[const SizedBox(height: 6), numbers],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth <
            280 * MediaQuery.textScalerOf(context).scale(13) / 13;
        final name = Tooltip(
          message: label,
          child: Text(
            label,
            maxLines: stacked ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopChrome.metadata(),
          ),
        );
        final amount = Text(
          value,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: DesktopChrome.control(),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [name, const SizedBox(height: 2), amount],
              )
            : Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 12),
                  Flexible(fit: FlexFit.tight, child: amount),
                ],
              );
      },
    ),
  );
}

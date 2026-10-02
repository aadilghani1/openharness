// Native release regression for flutter/flutter#193410. The runner builds this
// in a disposable app; it never loads Harness state or opens a transport.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harness/core/connected_semantics.dart';

const _host = MethodChannel('harness/accessibility_regression');
final _selected = ValueNotifier<int>(0);
final _values = [ValueNotifier<double>(.5), ValueNotifier<double>(.5)];
int _actions = 0;

Widget _slider(int index) => Center(
  child: ValueListenableBuilder<double>(
    valueListenable: _values[index],
    builder: (_, value, _) => Slider(
      value: value,
      onChanged: (value) {
        _values[index].value = value;
        _actions++;
      },
    ),
  ),
);

Future<void> _run() async {
  // The unguarded build is an explicit diagnostic mode, not a product setting.
  if (const bool.fromEnvironment('AX_REGRESSION_UNGUARDED')) {
    WidgetsFlutterBinding.ensureInitialized();
  } else {
    HarnessWidgetsBinding();
  }
  final binding = WidgetsBinding.instance;
  final semantics = binding.ensureSemantics();
  await _host.invokeMethod<void>('semantics', true);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: _selected,
          builder: (_, selected, _) =>
              IndexedStack(index: selected, children: [_slider(0), _slider(1)]),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  for (var step = 0; step < 160; step++) {
    if (step % 5 == 4) {
      await _host.invokeMethod<void>('semantics', false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _host.invokeMethod<void>('semantics', true);
    }
    _selected.value = step % 2;
    await _host.invokeMethod<void>('resize', step);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    // Ask AppKit to invoke the real Flutter AX node, verifying more than mere
    // process survival. The action must travel back through the native bridge.
    final before = _actions;
    final result = await _host.invokeMethod<bool>('increment');
    await Future<void>.delayed(const Duration(milliseconds: 15));
    if (result != true || _actions != before + 1) {
      throw StateError(
        'Native slider action failed at step $step: $result, $_actions vs $before',
      );
    }
    // Keep the slider below its maximum so every increment remains actionable.
    _values[_selected.value].value = .5;
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  semantics.dispose();
  stdout.writeln(
    'ACCESSIBILITY_REGRESSION_PASS cycles=160 native_actions=$_actions',
  );
  exit(0);
}

void main() {
  runZonedGuarded(() => unawaited(_run()), (Object error, StackTrace stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  });
}

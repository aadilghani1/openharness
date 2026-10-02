import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../logging/app_log.dart';

/// Flutter 3.47 can serialize dirty semantics nodes from hidden subtrees, even
/// though they are not reachable from the view's semantics root. The desktop
/// AX bridge rejects that update after partially changing its tree; a later
/// reparent then dereferences a null parent and terminates the process.
///
/// Filter at Flutter's public builder seam, before the native update is made.
/// Use the current framework tree, not a second retained tree: this also handles
/// removals, view changes, and disabling/re-enabling semantics without stale IDs.
/// https://github.com/flutter/flutter/issues/193410
mixin ConnectedSemanticsBinding on RendererBinding {
  bool _reportedDisconnectedSemantics = false;

  @protected
  ui.SemanticsUpdateBuilder createPlatformSemanticsUpdateBuilder() =>
      super.createSemanticsUpdateBuilder();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final delegate = createPlatformSemanticsUpdateBuilder();
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.macOS &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return delegate;
    }
    final connected = <int>{};
    for (final view in renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      // OverlayPortal has different paint and accessibility parents. In the
      // failing Slider/IndexedStack case the hidden portal's child is still
      // in paint order, but its traversal parent is no longer in the tree.
      final portals = <Object, List<SemanticsNode>>{};
      void collect(SemanticsNode node) {
        final identifier = node.traversalChildIdentifier;
        if (node.traversalParentIdentifier == null && identifier != null) {
          portals.putIfAbsent(identifier, () => []).add(node);
        }
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(root);
      final visited = <SemanticsNode>{};
      void visit(SemanticsNode node) {
        if (!visited.add(node)) return;
        connected.add(node.id);
        if (!node.mergeAllDescendantsIntoThisNode) {
          node.visitChildren((child) {
            if (child.traversalChildIdentifier == null ||
                node.traversalParentIdentifier != null) {
              visit(child);
            }
            return true;
          });
        }
        for (final child
            in portals[node.traversalParentIdentifier] ??
                const <SemanticsNode>[]) {
          if (child.attached) visit(child);
        }
      }

      visit(root);
    }
    return ConnectedSemanticsUpdateBuilder(
      delegate,
      connected: connected,
      onDiscard: (id) {
        if (_reportedDisconnectedSemantics) return;
        _reportedDisconnectedSemantics = true;
        appLog.warn(
          'accessibility',
          'Filtered disconnected semantics node $id before the native update',
        );
      },
    );
  }
}

/// Used by the production entry point; native/widget fixtures mix the same
/// protection into their test binding so they exercise the real boundary.
class HarnessWidgetsBinding extends WidgetsFlutterBinding
    with ConnectedSemanticsBinding {}

@visibleForTesting
class ConnectedSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  ConnectedSemanticsUpdateBuilder(
    this._delegate, {
    required this.connected,
    this.onDiscard,
  });

  final ui.SemanticsUpdateBuilder _delegate;
  final Set<int> connected;
  final void Function(int id)? onDiscard;

  // Root 0 can never be another node's child. Leave traversal/hit-test order
  // otherwise intact: OverlayPortal legitimately uses different lists.
  Int32List _children(Int32List ids) {
    if (ids.every((id) => id != 0 && connected.contains(id))) return ids;
    return Int32List.fromList(
      ids.where((id) => id != 0 && connected.contains(id)).toList(),
    );
  }

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    if (!connected.contains(id)) {
      onDiscard?.call(id);
      return;
    }
    _delegate.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: label,
      labelAttributes: labelAttributes,
      value: value,
      valueAttributes: valueAttributes,
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes,
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes,
      hint: hint,
      hintAttributes: hintAttributes,
      tooltip: tooltip,
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: _children(childrenInTraversalOrder),
      childrenInHitTestOrder: _children(childrenInHitTestOrder),
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl,
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() => _delegate.build();
}

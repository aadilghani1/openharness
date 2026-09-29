// `PaneMenuRow` and `paneMenuItem` on their own terms.
//
// These assertions used to live in `grid_model_picker_test`, because the model picker was the only
// thing drawing these rows. It is not any more — it has its own panel — but the find bar and the
// New Harness box still use them, and the two bugs pinned here were real: a hover the eye could
// not tell from a selection, and trailing columns that landed at a different offset on every row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/theme/app_theme.dart';
import 'package:harness/widgets/desktop_chrome.dart';
import 'package:harness/widgets/pane_menu.dart';

void main() {
  Future<void> show(WidgetTester tester, List<Widget> rows) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 420, child: Column(children: rows)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget item(Widget row) => paneMenuItem(onTap: () {}, child: row);

  testWidgets(
    'hover stays distinct from selection and focus has a stable rim',
    (tester) async {
      // Two rows looked equally chosen: one was SELECTED and the other was merely under the pointer
      // or holding focus, and all three states painted the same fill.
      await show(tester, [
        item(
          const PaneMenuRow(selected: true, title: 'chosen', status: 'here'),
        ),
        item(
          const PaneMenuRow(selected: false, title: 'other', status: 'there'),
        ),
      ]);

      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(
          button.style!.overlayColor!.resolve({WidgetState.hovered}),
          AppColors.rowHover,
        );
        expect(
          button.style!.overlayColor!.resolve({WidgetState.focused}),
          Colors.transparent,
        );
      }
      expect(AppColors.rowHover, isNot(AppColors.selected));
      expect(AppColors.rowHover.a, lessThan(AppColors.selected.a));

      final other = find.widgetWithText(TextButton, 'other');
      final before = tester.getRect(other);
      Focus.of(tester.element(find.text('other'))).requestFocus();
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find.descendant(of: other, matching: find.byType(Material)),
      );
      final rim = (material.shape! as OutlinedBorder).side;
      expect(rim.color, DesktopChrome.accent);
      expect(rim.width, greaterThan(0));
      expect(tester.getRect(other), before);
    },
  );

  testWidgets('only the chosen row is filled', (tester) async {
    await show(tester, [
      item(const PaneMenuRow(selected: true, title: 'chosen', status: 'here')),
      item(const PaneMenuRow(selected: false, title: 'other', status: 'there')),
    ]);

    BoxDecoration? fillOf(String text) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(text),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration?;
    expect(fillOf('chosen')?.color, AppColors.selected);
    expect(fillOf('other')?.color, isNull);
  });

  testWidgets(
    'trailing metadata shares one right edge, whatever the row holds',
    (tester) async {
      // Every trailing field was a `Flexible`, whose flex is ONE — so a row's spare width was split
      // evenly between the title and each field beside it. A row with two fields put them a third
      // and two thirds across; a row with one put it halfway. Three columns, three offsets.
      await show(tester, [
        item(const PaneMenuRow(selected: false, title: 'one', status: 'a')),
        item(
          const PaneMenuRow(
            selected: false,
            title: 'two',
            status: 'firmware-engineer-daniel',
          ),
        ),
        item(
          const PaneMenuRow(
            selected: false,
            title: 'three',
            detail: '7f0c59',
            status: '11% remaining',
          ),
        ),
      ]);

      final edges = [
        tester.getRect(find.text('a')).right,
        tester.getRect(find.text('firmware-engineer-daniel')).right,
        tester.getRect(find.text('11% remaining')).right,
      ];
      for (final edge in edges) {
        expect((edge - edges.first).abs(), lessThan(0.5));
      }
    },
  );

  testWidgets('a long trailing field ellipsizes instead of eating the title', (
    tester,
  ) async {
    const long =
        'a-machine-name-far-longer-than-any-column-should-ever-be-allowed-to-grow';
    await show(tester, [
      item(const PaneMenuRow(selected: false, title: 'model', status: long)),
    ]);

    expect(
      tester.getRect(find.text(long)).width,
      lessThanOrEqualTo(kPaneMenuMetaMaxWidth + 0.5),
    );
    // The row is named after its title, so that is the text that keeps its width.
    expect(tester.getRect(find.text('model')).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

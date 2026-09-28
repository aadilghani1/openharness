# Session work previews

Synthetic widget-test captures of the desktop work dialog and phone work page.
The session, repository, branches and pull requests are fixtures, not live data.

- [Desktop, 1000 × 720](desktop.png)
- [Phone, 390 × 760](phone.png)
- [Desktop with unconfirmed newer activity, 1000 × 720](recovered.png)

The original desktop and phone captures show the offline state to demonstrate retained work and pull-request
history. Generate fresh captures by setting `HARNESS_GIT_CONTEXT_CAPTURE_DIR`
when running `desktop/test/session_work_dialog_test.dart` or
`mobile/test/session_work_page_test.dart` with `flutter test` in the respective
application directory.

The recovery capture is online and keeps its last observed branch and PR while
newer activity is unconfirmed. It comes from the recorded-receipt regression
fix; the displayed session and PR remain synthetic widget fixtures.

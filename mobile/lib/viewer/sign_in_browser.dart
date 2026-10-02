import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the SSO page opens: in the app — SFSafariViewController on iOS, a Custom Tab on Android —
/// as the desktop's viewer build opens it on a phone (`desktop/lib/viewer/sign_in_browser.dart`).
///
/// Never the Safari or Chrome app: handing the person over suspends this app, and with it the
/// loopback listener the page redirects back to (`direct_login.dart`).
///
/// ⚠️ **Android is the weak side.** A Custom Tab covers the app, the process behind it can be
/// frozen, and the redirect then finds nobody listening — the Play review's "127.0.0.1 took too
/// long to respond" (`email_code_api.dart`). And only iOS can take the page down by itself
/// ([closeSignInPage]): on Android the page's last screen goes back to the app through
/// [signInReturnUrl] instead.
///
/// True once the page is up; false when iOS's sheet was closed before its first page loaded.
Future<bool> openSignInPage(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.inAppBrowserView);
  } on PlatformException catch (error) {
    // ⚠️ **The sheet is up — this is the sign-in page working, not failing.** Named a provider,
    // auth-service's page replaces itself with Google's or Apple's (`location.replace`) before
    // its own load finishes, so SFSafariViewController reports the first load as failed, and
    // url_launcher_ios throws exactly this (`_failedSafariViewControllerLoadException`) while
    // leaving the sheet where it is. Taking it as "could not open" cancelled every iOS sign-in
    // and pulled the sheet out from under Google's account picker. A page that truly failed to
    // load is still on screen, saying so, for the person to close.
    if (error.code == 'Error' &&
        (error.message ?? '').startsWith('Error while launching')) {
      return true;
    }
    rethrow;
  }
}

/// Where the Custom Tab's last page sends the person back to the app on Android: the scheme
/// `SignInReturnActivity` takes (`android/app/src/main/AndroidManifest.xml`), which brings the app
/// back over the tab and takes the tab down — the one thing [closeSignInPage] cannot do there.
const signInReturnUrl = 'ai.autonomous.harness.signin://signed-in';

/// Takes down what [openSignInPage] put up, where the platform can. Best effort.
Future<void> closeSignInPage() async {
  try {
    if (await supportsCloseForLaunchMode(LaunchMode.inAppBrowserView)) {
      await closeInAppWebView();
    }
  } catch (_) {}
}

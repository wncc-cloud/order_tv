/// Build-time config (previously the Google Drive idle-screen slideshow's
/// config, ported from `billing_cafe`'s web Kitchen Display — see that
/// repo's `app/lib/config/env.dart` for the original).
class Env {
  Env._();

  // Google Drive idle-screen slideshow config — DISABLED. The idle screen
  // now shows a static logo instead (see
  // `lib/screens/kitchen_display_screen.dart`'s `_IdleView`), and
  // `lib/widgets/idle_media_slideshow.dart` / `lib/services/drive_media.dart`
  // are commented out to match. Left here, commented out, in case the
  // slideshow needs to come back.
  //
  // /// Google Drive API key for the idle-screen slideshow
  // /// (`IdleMediaSlideshow`). Empty by default: the slideshow fails closed
  // /// to the plain idle view rather than ever attempting a request with no
  // /// key.
  // ///
  // /// IMPORTANT: this must be a DIFFERENT key from the one billing_cafe's
  // /// web app uses. That key is restricted in Google Cloud Console to the
  // /// `cafecountrysidekot.web.app` HTTP referrer — a native Android app
  // /// never sends a `Referer` header, so that key would be rejected here.
  // /// Create a separate key restricted to "Android apps" (this app's
  // /// package name + signing certificate SHA-1) instead, then supply it via
  // /// `--dart-define=DRIVE_API_KEY=...` at build time.
  // static const String driveApiKey = String.fromEnvironment('DRIVE_API_KEY', defaultValue: '');
  //
  // /// The same shared Drive folder the web Kitchen Display's idle
  // /// slideshow rotates through — folder IDs aren't platform-restricted
  // /// (only the API key is), so this default is safe to reuse as-is.
  // static const String driveIdleMediaFolderId = String.fromEnvironment(
  //   'DRIVE_IDLE_MEDIA_FOLDER_ID',
  //   defaultValue: '1novwK5rSXckPNSgyYvpnF53cS8saseAJ',
  // );
}

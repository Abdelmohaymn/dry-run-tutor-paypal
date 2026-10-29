/// The 21-screen route inventory (contracts/routes.md): the prototype's 12
/// plus the 9 the spec names as needing to be built in the same language.
/// A named `AppRoute` constant is what "typed routes" means here — every
/// call site names a route through this enum rather than a literal path
/// string scattered through the app.
///
/// **No route resolves to a past day.** There is no `/session/:id`, no
/// `/history`, no `/archive`, and no parameterised path that could name a
/// retained session other than today's (FR-039d) — this enum is finite and
/// closed on purpose.
enum AppRoute {
  seeding('/seeding'),
  update('/update'),
  welcome('/welcome'),
  welcomePractice('/welcome/practice'),
  daily('/'),
  problemPicker('/problems'),
  sessionRecord('/session/record'),
  sessionReview('/session/review'),
  sessionMicRationale('/session/mic-rationale'),
  sessionRecognitionUnavailable('/session/recognition-unavailable'),
  sessionConfirmSolution('/session/confirm-solution'),
  sessionVerdict('/session/verdict'),
  sessionReveal('/session/reveal'),
  sessionReviewDay('/session/review-day'),
  streak('/streak'),
  keysWall('/keys/wall'),
  keysEntry('/keys/entry'),
  settings('/settings'),
  settingsKey('/settings/key'),
  settingsPlan('/settings/plan'),
  settingsReminder('/settings/reminder'),
  settingsWipe('/settings/wipe'),
  withdrawn('/withdrawn');

  const AppRoute(this.path);

  /// The literal path segment `go_router` matches against. Also doubles
  /// as the route's `name:` for `context.goNamed`.
  final String path;
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String appTitle(String appName) {
    return '$appName';
  }

  @override
  String get problemPickerTitle => 'Choose a problem';

  @override
  String get seedingTitle => 'Setting up';

  @override
  String get seedingBody =>
      'Getting today\'s problem and your settings. This happens once, and it keeps retrying on its own.';

  @override
  String get updateRequiredTitle => 'A fresh update is ready';

  @override
  String updateRequiredBody(String appName) {
    return 'We\'ve made $appName better. Update to keep your streak going.';
  }

  @override
  String get updateRequiredAction => 'Update';

  @override
  String get withdrawnTitle => 'Swapping in a different problem';

  @override
  String get withdrawnBody =>
      'Today\'s problem isn\'t available. We\'re getting you another one.';

  @override
  String get withdrawnRetryAction => 'Try again';

  @override
  String get dailyStreakTooltip => 'Streak';

  @override
  String get dailySettingsTooltip => 'Settings';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get settingsKeyManagementLabel => 'Provider key';

  @override
  String get settingsReminderLabel => 'Daily reminder';

  @override
  String get settingsWipeLabel => 'Delete all data';

  @override
  String get keyManagementTitle => 'Provider key';

  @override
  String get keyManagementNoKey =>
      'No key saved. Add one now, or after your next session.';

  @override
  String get keyManagementAddAction => 'Add key';

  @override
  String keyManagementProviderLabel(String provider) {
    return 'Saved for $provider';
  }

  @override
  String get keyManagementReplaceAction => 'Replace key';

  @override
  String get keyManagementDeleteAction => 'Delete key';

  @override
  String get keyManagementDeletedNotice =>
      'Key deleted. Add one again to use your own allowance.';

  @override
  String get reminderScreenTitle => 'Daily reminder';

  @override
  String get reminderScreenBody =>
      'One notification a day, made on this phone. It\'s cancelled once that day\'s session is done.';

  @override
  String get reminderEnabledToggle => 'Remind me daily';

  @override
  String get reminderTimeLabel => 'Time';

  @override
  String get wipeScreenTitle => 'Delete all data';

  @override
  String get wipeScreenWarning =>
      'Deletes every conversation, assessment and cached problem on this phone, and ends your streak. It won\'t give back your free taster or reset your device identity.';

  @override
  String get wipeConfirmAction => 'Delete everything';

  @override
  String get wipeConfirmDialogTitle => 'Are you sure?';

  @override
  String get wipeConfirmDialogBody =>
      'Your conversations, assessments and streak all go. This can\'t be undone.';

  @override
  String get wipeCancelAction => 'Cancel';

  @override
  String get wipeDoneNotice => 'All data deleted.';

  @override
  String get errRateLimited =>
      'The provider is catching up. This continues in a moment.';

  @override
  String get errInvalidKey =>
      'The provider rejected that key. Try a different one. Your conversation is safe.';

  @override
  String get errQuotaExhausted =>
      'Your daily allowance with this provider is spent. It resets on its own, and nothing was charged.';

  @override
  String get errUnclearRetry =>
      'That didn\'t come through. Try sending it again.';

  @override
  String get errTurnCapReached =>
      'That\'s today\'s conversation length. Hints still work, and you can finish to see how it went.';

  @override
  String get errTrialConsumed =>
      'Your free taster is used up. Add your own key to keep going. You can\'t be charged.';

  @override
  String get errAlreadyJudgedRepeat =>
      'This session was already assessed. Tap Try again to load it.';

  @override
  String get errSessionClosed =>
      'This session is closed and the verdict is in. You can review the assessment or the reveal.';

  @override
  String get errEmptyTurn => 'Nothing was heard. Re-record, or type instead.';

  @override
  String errorCodeLabel(String code) {
    return 'Code: $code';
  }

  @override
  String get errTrialIpLimited =>
      'Free sessions from this network are used up for today. Add your own Nebius key to keep going.';

  @override
  String get errTrialUnavailable =>
      'The free taster is full today. Add your key and start now. You can\'t be charged.';

  @override
  String get errProblemKilled =>
      'Today\'s problem has been withdrawn — here is another one.';

  @override
  String get errBadRequest =>
      'Something failed on our side. Try again, and update the app if it keeps happening.';

  @override
  String get errOfflineQueued =>
      'No connection. Try again once you\'re back online.';

  @override
  String get crashTitle => 'Something broke';

  @override
  String crashBody(String code) {
    return 'If it keeps happening, send us this code: $code';
  }

  @override
  String get crashCopyAction => 'Copy details';

  @override
  String get crashCloseAction => 'Close';

  @override
  String get crashCopied => 'Copied';

  @override
  String get retryAction => 'Try again';

  @override
  String get composerMicSemanticLabel => 'Speak your turn';

  @override
  String get composerTypeInsteadLink => 'Type instead';

  @override
  String get textComposerLabel => 'Type your turn…';

  @override
  String get textComposerSendLabel => 'Send';

  @override
  String get recordingTitle => 'Listening in English…';

  @override
  String get recordingWarningNotice => '15 seconds left';

  @override
  String get recordingStopLabel => 'Done speaking';

  @override
  String get recordingCancelLabel => 'Cancel';

  @override
  String get recordingWaveformSemanticLabel => 'Microphone input level';

  @override
  String get micRationaleTitle => 'Why we ask for the microphone';

  @override
  String get micRationaleBody =>
      'When you speak, Dry Run records a short clip and sends it to our server, which passes it to Groq\'s speech service to turn it into text. We don\'t keep your clips: each one is deleted from your phone once it\'s transcribed or discarded, and our server never stores it. If voice transcription is busy or today\'s allowance is used up, your phone\'s own speech recognition takes over, and it may send audio to its maker\'s service. Speaking works in English for now.';

  @override
  String get recordingCloudLabel => 'Recording';

  @override
  String get recordingCloudRetryTitle => 'That didn\'t go through.';

  @override
  String get recordingCloudRetryBody =>
      'Your recording is saved, so there\'s no need to say it again. Check your connection and tap Try again.';

  @override
  String get recordingCloudDiscardAction => 'Discard recording';

  @override
  String get recordingCloudFailedNotice =>
      'Sorry, we couldn\'t transcribe that one. Please tap the mic and say it again.';

  @override
  String get recordingCloudFallbackNotice =>
      'Sorry, we couldn\'t transcribe that one. Please tap the mic and say it again; your phone\'s speech recognition will take it from here.';

  @override
  String get micRationaleContinue => 'Continue';

  @override
  String get reviewTitle => 'Review before sending';

  @override
  String get reviewEditHint => 'Edit anything that was misheard, then send.';

  @override
  String get reviewEditHintTyped =>
      'Check it reads the way you meant, then send.';

  @override
  String get reviewDiscardLabel => 'Back';

  @override
  String get reviewSendLabel => 'Send';

  @override
  String get reviewReRecordLabel => 'Re-record';

  @override
  String get reviewRevertLabel => 'Show what I said';

  @override
  String get problemExpandLabel => 'Read the full problem';

  @override
  String get problemCollapseLabel => 'Show less';

  @override
  String get problemConstraintsLabel => 'Constraints';

  @override
  String get conversationEmptyBody =>
      'Say how you\'d start. Think out loud, half-formed is fine.';

  @override
  String get recordingNothingHeardNotice =>
      'Didn\'t catch that. Try again in English, or type.';

  @override
  String get messageListYouLabel => 'You';

  @override
  String get messageListTutorLabel => 'Tutor';

  @override
  String get messageListFailedRetryLabel => 'Not sent — tap to retry';

  @override
  String turnGaugeLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count turns left today',
      one: '1 turn left today',
      zero: 'No turns left today',
    );
    return '$_temp0';
  }

  @override
  String get finishOfferTitle => 'Sounds like you\'ve got it';

  @override
  String get finishOfferBody =>
      'You\'ve explained the key idea. Finish now and see how you did, or keep going to dig deeper.';

  @override
  String get finishOfferFinish => 'Finish';

  @override
  String get finishOfferKeepGoing => 'Keep going';

  @override
  String get wrapUpBannerTitle => 'Wrapping up';

  @override
  String get wrapUpBannerBody =>
      'You\'re near today\'s limit. A few more, then finish and see how it went.';

  @override
  String get capReachedTitle => 'Today\'s conversation is complete';

  @override
  String get capReachedBody =>
      'You can still pull a hint or end the session to see how it went.';

  @override
  String get recognitionUnavailableTitleLanguage =>
      'Speech recognition doesn\'t cover this language yet';

  @override
  String get recognitionUnavailableBodyLanguage =>
      'Your phone\'s speech recognition doesn\'t handle this language. You can still type.';

  @override
  String get recognitionUnavailableTitleUnsupported =>
      'Speech recognition isn\'t available on this device';

  @override
  String get recognitionUnavailableBodyUnsupported =>
      'You can still take part by typing.';

  @override
  String get spokenLanguageSheetTitle => 'Which language will you speak?';

  @override
  String get spokenLanguageSearchHint => 'Search languages';

  @override
  String get spokenLanguageNoMatches => 'No language matches that.';

  @override
  String get recognitionUnavailableTypeInstead => 'Type instead';

  @override
  String get errorReEnterKeyAction => 'Enter key';

  @override
  String get wallCannotBeCharged => 'You cannot be charged';

  @override
  String wallBody(String appName) {
    return 'Your free taster is done. Add your own Nebius key to keep going; new accounts get \$1 of free credit. $appName never charges you.';
  }

  @override
  String get wallAddKey => 'Add your key';

  @override
  String get wallNotNow => 'Not now';

  @override
  String get keyEntryTitle => 'Add your key';

  @override
  String get keyEntryIntro =>
      'Paste a Nebius Token Factory API key. New accounts get \$1 of free credit. The key stays on this phone.';

  @override
  String get keyEntryNoProviders =>
      'No providers available right now. Try again shortly.';

  @override
  String keyEntryDisclosure(String provider) {
    return '$provider receives the text of your conversation. Never your key, never the hidden solution. Check $provider\'s terms for whether it trains on free-tier content.';
  }

  @override
  String keyEntryGetFreeKey(String provider) {
    return 'Get a $provider key (\$1 free credit)';
  }

  @override
  String get keyEntryFieldLabel => 'API key';

  @override
  String get keyEntrySave => 'Save and continue';

  @override
  String get keyEntryAllowanceGrew =>
      'Key saved. Same conversation, more room.';

  @override
  String get keyPromptTrialTitle => 'Your free taster is done';

  @override
  String keyPromptTrialBody(String appName) {
    return 'You\'ve used the free sessions $appName provides. Add your own Nebius key to keep going; new accounts get \$1 of free credit. It stays on this phone, and $appName never charges you.';
  }

  @override
  String get keyPromptTrialUnavailableTitle => 'The free taster is at capacity';

  @override
  String keyPromptTrialUnavailableBody(String appName) {
    return 'Today\'s free taster is full, for everyone using $appName today. Add your own Nebius key and start now; new accounts get \$1 of free credit. It stays on this phone, and $appName never charges you.';
  }

  @override
  String get keyPromptTrialIpLimitedTitle =>
      'Today\'s free sessions are used up';

  @override
  String keyPromptTrialIpLimitedBody(String appName) {
    return 'Free sessions from this network are used up for today. Add your own Nebius key to keep going; new accounts get \$1 of free credit. It stays on this phone, and $appName never charges you.';
  }

  @override
  String get keyPromptQuotaTitle => 'Your provider allowance is spent';

  @override
  String get keyPromptQuotaBody =>
      'Your Nebius credit or rate limit is used up. Add credit in your Nebius account, or wait a bit and try again.';

  @override
  String get keyPromptAddAction => 'Add your key';

  @override
  String get keyPromptReplaceAction => 'Use a different key';

  @override
  String get keyPromptDismissAction => 'Not now';

  @override
  String get keyPromptQuotaDismissAction => 'Wait for the reset';

  @override
  String get rateLimitTitle => 'Your key hit its limit';

  @override
  String rateLimitBody(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other:
          'Too many messages this minute. Yours sends again in $seconds seconds.',
      one: 'Too many messages this minute. Yours sends again in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitOkAction => 'OK';

  @override
  String get hintActionLabel => 'Hint';

  @override
  String hintMessageLabel(int index, int count) {
    return 'Hint $index of $count';
  }

  @override
  String get hintLadderExhaustedLabel => 'Hints';

  @override
  String get endSessionLabel => 'End session';

  @override
  String get askForAnswerLabel => 'Answer';

  @override
  String get confirmSolutionTitle => 'One more thing before that';

  @override
  String get confirmSolutionWarning =>
      'This ends today\'s session. You still get your assessment and the write-up, for the work up to now.';

  @override
  String get confirmSolutionCancel => 'Keep going instead';

  @override
  String get confirmSolutionProceed => 'Yes, show me the solution';

  @override
  String get verdictStrongPass => 'Strong approach';

  @override
  String get verdictPass => 'Solid approach';

  @override
  String get verdictBorderline => 'Getting there';

  @override
  String get verdictFail => 'Worth another pass';

  @override
  String get verdictUnclear => 'Hard to call';

  @override
  String get matchedApproachOptimal =>
      'This matched the strongest approach on file.';

  @override
  String get matchedApproachAcceptable =>
      'This matched a solid, accepted approach.';

  @override
  String get matchedApproachSuboptimal =>
      'This matched a workable approach, though not the strongest one.';

  @override
  String get matchedApproachWrong =>
      'This took a different direction than the problem intended.';

  @override
  String get matchedApproachNone => 'Nothing here matched an approach on file.';

  @override
  String get complexityMatch => 'matches the reference';

  @override
  String get complexityMismatch => 'differs from the reference';

  @override
  String get complexityNotStated => 'wasn\'t stated';

  @override
  String get verdictScreenTitle => 'How it went';

  @override
  String get verdictInsightsHitLabel => 'Reached';

  @override
  String get verdictInsightAssistedTag => 'with a nudge';

  @override
  String get verdictInsightsMissedLabel => 'Not reached';

  @override
  String get verdictComplexityLabel => 'Complexity';

  @override
  String get verdictDisputeAction => 'Dispute this assessment';

  @override
  String get verdictDisputedNotice =>
      'Noted. Flagged as disputed on this phone.';

  @override
  String get verdictReadEditorialAction => 'Read the full write-up';

  @override
  String get verdictPracticeAgainAction => 'Practice this problem again';

  @override
  String get verdictSolutionReleaseNotice =>
      'This covers only the work before the solution was shown. Asking for it isn\'t held against you.';

  @override
  String get revealScreenTitle => 'The write-up';

  @override
  String get sessionClosedTitle => 'This session is closed';

  @override
  String get sessionClosedReviewAction => 'Review the assessment';

  @override
  String get streakScreenTitle => 'Streak';

  @override
  String streakCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
      zero: 'No streak yet',
    );
    return '$_temp0';
  }

  @override
  String get streakPerInstallNotice =>
      'This streak lives on this phone. It won\'t follow you to another device or survive a reinstall.';

  @override
  String get streakReviewTodayAction => 'Review today';

  @override
  String get reviewDayScreenTitle => 'Today';

  @override
  String shareCardInsightsLine(int hit, int total) {
    return '$hit of $total key insights reached';
  }

  @override
  String shareCardComplexityLine(String time, String space) {
    return '$time time, $space space';
  }

  @override
  String shareCardStreakLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Day $count of the streak',
      one: 'Day 1 of the streak',
    );
    return '$_temp0';
  }

  @override
  String get shareCardAction => 'Share';

  @override
  String get composerUseMicLabel => 'Use the mic instead';

  @override
  String get recordingListeningLabel => 'Listening · EN';

  @override
  String get recordingTranscribingLabel => 'Transcribing…';

  @override
  String get reviewInlineTitle => 'Check before sending';

  @override
  String get examplesActionLabel => 'Example';

  @override
  String get examplesSheetTitle => 'Examples';

  @override
  String exampleIndexLabel(int index) {
    return 'Example $index';
  }

  @override
  String get exampleInputLabel => 'Input';

  @override
  String get exampleOutputLabel => 'Output';

  @override
  String get exampleExplanationLabel => 'Why';

  @override
  String get backAction => 'Back';

  @override
  String get judgingNotice => 'Working out how it went…';

  @override
  String get assessmentReadyTitle => 'Your assessment is ready';

  @override
  String get assessmentReadyAction => 'See how it went';

  @override
  String get assessmentPracticeAgainAction => 'Solve it again';

  @override
  String exampleMessageLabel(int index, int count) {
    return 'Example $index of $count';
  }

  @override
  String get dailyEndSessionTooltip => 'Finish and see how it went';

  @override
  String get wrapUpFinishAction => 'Finish and see how it went';

  @override
  String get endSessionExplainer =>
      'Nothing ends it for you. Tap Finish and you get your assessment.';

  @override
  String get verdictDisputeExplainer =>
      'Flags it on this phone so you can find it again. Nothing is uploaded.';

  @override
  String get verdictDisputedAction => 'Disputed';

  @override
  String get verdictComplexityYoursLabel => 'You said';

  @override
  String get verdictComplexityReferenceLabel => 'Reference';

  @override
  String get verdictComplexityUnlistedNotice =>
      'Your approach isn\'t one on file. It was judged on the insights you reached, not marked down for being unlisted.';

  @override
  String get reminderPermissionNeededNotice =>
      'Android needs permission to show notifications. Turn the reminder on and allow it when asked.';

  @override
  String get reminderPermissionDeniedNotice =>
      'Notifications are blocked for this app. Turn them on in Android\'s app settings.';

  @override
  String reminderScheduledNotice(String time) {
    return 'Armed. The next one lands at $time.';
  }

  @override
  String get reminderInexactNotice =>
      'Android can hold this back up to an hour. Allow exact alarms and it lands on time.';

  @override
  String get reminderExactAlarmAction => 'Allow exact alarms';

  @override
  String get shareCardTitle => 'Today’s result';

  @override
  String get shareCardApproachLabel => 'Approach';

  @override
  String get shareCardInsightsLabel => 'Insights';

  @override
  String get reminderOpenSettingsAction => 'Open notification settings';

  @override
  String get welcomeSlide1Title => 'Keep your own mind sharp';

  @override
  String get welcomeSlide1Body =>
      'AI can write the code now. It can\'t sit in the interview for you, or explain why you chose this over that. Ten minutes a day keeps that muscle yours.';

  @override
  String get welcomeSlide2Title => 'Say it out loud';

  @override
  String get welcomeSlide2Body =>
      'Tap the mic and talk through your idea the way you would to a colleague. Messy is fine. No code, no typing, no multiple choice.';

  @override
  String get welcomeSlide3Title => 'One problem a day';

  @override
  String get welcomeSlide3Body =>
      'No feed. No backlog to fall behind on. One problem, a few minutes, done.';

  @override
  String get welcomeSlide4Title => 'It asks. It never tells.';

  @override
  String get welcomeSlide4Body =>
      'The tutor pushes back instead of answering. That\'s the point, and yes, it can feel stubborn. Stuck? Tap Hint or Example. Neither costs you a turn.';

  @override
  String get welcomeSlide5Title => 'You say when you are done';

  @override
  String get welcomeSlide5Body =>
      'It\'ll keep asking forever if you let it. Tap Finish when you\'ve said your piece. That\'s what gets you the write-up.';

  @override
  String get welcomeSlide6Title => 'Make it a habit';

  @override
  String get welcomeSlide6Body =>
      'A new problem lands every day. Pick a time and we\'ll nudge you: one reminder, made on this phone. Miss a day and the streak just starts again.';

  @override
  String get welcomeSlide7Title => 'Free to use';

  @override
  String get welcomeSlide7Body =>
      'Start with sessions on us. After that, paste a free API key. Groq and Google both give one away, no card. It stays on this phone.';

  @override
  String get welcomeNextAction => 'Next';

  @override
  String get welcomeSkipAction => 'Skip';

  @override
  String get welcomeEnableRemindersAction => 'Turn the reminder on';

  @override
  String get welcomeRemindersOnNotice => 'On — you will get one each morning.';

  @override
  String get welcomeRemindersBlockedNotice =>
      'Android has notifications blocked for this app. Turn them on later in Settings → Reminder.';

  @override
  String get welcomeTryAction => 'Try a practice problem';

  @override
  String get welcomeSkipPracticeAction => 'Skip to today’s problem';

  @override
  String get practiceTitle => 'Practice run';

  @override
  String get practiceSkipAction => 'Skip';

  @override
  String get practiceProblemTitle => 'Largest in the list';

  @override
  String get practiceProblemStatement =>
      'You are given a list of numbers. Find the largest one and return it.';

  @override
  String get practiceTypedNotice =>
      'Nothing here is graded, and no turn is spent.';

  @override
  String get practiceTutorOpener =>
      'A warm-up, so you can see how this goes. How would you find the largest number in that list? Say it however it comes out, half-formed is fine.';

  @override
  String get practiceTutorReply1 =>
      'Okay. Now the question you\'ll get asked a lot here: how much work does that do as the list gets longer?';

  @override
  String get practiceTutorReply2 =>
      'That\'s the loop: you talk, it asks, you sharpen. Nothing here was graded, and no turn was spent.';

  @override
  String get practiceHintText =>
      'You don\'t need to sort anything. You only ever need the best one so far.';

  @override
  String get practiceDoneTitle => 'That is the whole app';

  @override
  String get practiceDoneBody =>
      'Today\'s real problem is waiting. Talk it through and finish when you\'re ready.';

  @override
  String get practiceStartTodayAction => 'Start today’s problem';

  @override
  String get shareCardOpener => 'Still thinking for myself in the age of AI.';

  @override
  String get shareCardStreakLabel => 'Streak';

  @override
  String get finishActionLabel => 'Finish';

  @override
  String get finishNudgeBody =>
      'Said what you wanted? Tap Finish for your assessment. The tutor will keep asking otherwise.';

  @override
  String get welcomeSlide8Title => 'Then show it off';

  @override
  String get welcomeSlide8Body =>
      'A card with the problem, how it went, and your streak. What you actually said stays on this phone.';

  @override
  String get practiceMicHint => 'Tap the mic and talk, or type instead.';

  @override
  String get practiceRecognitionUnavailableNotice =>
      'This phone will not do speech right now, so type your answer instead.';

  @override
  String get shareCardInvite =>
      'Think you can explain it? Try today’s problem.';

  @override
  String get notificationNudgeTitle => 'Make it a daily habit';

  @override
  String get notificationNudgeBody =>
      'Turn on notifications and we\'ll remind you of each day\'s problem at a time you pick.';

  @override
  String get notificationNudgeAction => 'Turn on';

  @override
  String get notificationNudgeDismiss => 'Not now';

  @override
  String get messageCopyAction => 'Copy';

  @override
  String get messageCopiedNotice => 'Copied';

  @override
  String get settingsPlanLabel => 'Plan';

  @override
  String get planTitle => 'Plan';

  @override
  String get planFreeName => 'Free';

  @override
  String get planProName => 'Pro Plus';

  @override
  String get planOwnKey => 'Your own key';

  @override
  String get planOwnKeyProNote =>
      'Your own key is in use. Pro Plus is an alternative if you\'d rather not use a key.';

  @override
  String get planUsageHeading => 'Usage';

  @override
  String planSessionsUsage(int used, int limit) {
    return 'Sessions today: $used of $limit';
  }

  @override
  String planSessionsUsageLifetime(int used, int limit) {
    return 'Free sessions used: $used of $limit';
  }

  @override
  String planVoiceUsage(int used, int limit) {
    return 'Voice today: $used of $limit min';
  }

  @override
  String planRenews(String date) {
    return 'Renews on $date';
  }

  @override
  String planEnds(String date) {
    return 'Ends on $date';
  }

  @override
  String get planEndedNotice => 'Your Pro Plus subscription is not active.';

  @override
  String get planProSessionsUsed =>
      'Today\'s Pro sessions are used. They come back tomorrow (UTC).';

  @override
  String get planProCapacity =>
      'Pro Plus is at capacity for now. Try again later, or add your own key.';

  @override
  String get planOfferTitle => 'Pro Plus';

  @override
  String planOfferLimits(int sessions, int minutes) {
    return '$sessions sessions a day and $minutes minutes of voice a day, with no key needed.';
  }

  @override
  String get planOfferPayPal =>
      'Billed through PayPal. This build uses PayPal\'s test environment, so no real money is charged.';

  @override
  String get planSubscribe => 'Subscribe';

  @override
  String get planManage => 'Manage or cancel in PayPal';

  @override
  String planLastChecked(String date) {
    return 'Last checked $date';
  }

  @override
  String get planConfirming => 'Confirming with PayPal…';

  @override
  String get planAwaitingReturn => 'Finish in PayPal, then come back here.';

  @override
  String get planActivated => 'Pro Plus is active.';

  @override
  String get planNotCompleted => 'Subscription not completed.';

  @override
  String get planPayPalUnavailable => 'PayPal is unavailable. Try again later.';

  @override
  String get planAlreadyActive => 'Pro Plus is already active on this device.';

  @override
  String get planUnavailable => 'The plan can\'t be loaded right now.';

  @override
  String get planRetry => 'Try again';

  @override
  String get proBadgeLabel => 'Pro';

  @override
  String get keyPromptProSessionsTitle => 'Today\'s Pro sessions are used';

  @override
  String get keyPromptProSessionsBody =>
      'Today\'s Pro sessions are used. They come back tomorrow (UTC). Add your own key to keep going now.';

  @override
  String get keyPromptProCapacityTitle => 'Pro Plus is at capacity';

  @override
  String get keyPromptProCapacityBody =>
      'Pro Plus is at capacity for now. Add your own key to keep going.';

  @override
  String get keyPromptProAction => 'Get Pro Plus';

  @override
  String get keyPromptReplayLockedTitle => 'Practice again is part of Pro Plus';

  @override
  String get keyPromptReplayLockedBody =>
      'Free practice is today\'s problem, once. Pro Plus adds Practice again and the other problems. Your own key unlocks them too.';
}

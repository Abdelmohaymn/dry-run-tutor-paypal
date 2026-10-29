import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The application title, shown as the OS task/app label. The brand name is a placeholder, not a literal: lib/core/config/brand.dart is the single source of truth for it, and a product name is not translated.
  ///
  /// In en, this message translates to:
  /// **'{appName}'**
  String appTitle(String appName);

  /// Title for the evergreen problem picker.
  ///
  /// In en, this message translates to:
  /// **'Choose a problem'**
  String get problemPickerTitle;

  /// /seeding heading — first-launch waiting screen (FR-047a).
  ///
  /// In en, this message translates to:
  /// **'Setting up'**
  String get seedingTitle;

  /// /seeding body: plain words for what it fetches and why it's needed once. No manual retry button — retries by itself as connectivity changes (SC-022).
  ///
  /// In en, this message translates to:
  /// **'Getting today\'s problem and your settings. This happens once, and it keeps retrying on its own.'**
  String get seedingBody;

  /// /update heading — FR-048's blocking update prompt.
  ///
  /// In en, this message translates to:
  /// **'A fresh update is ready'**
  String get updateRequiredTitle;

  /// /update body. Upbeat on purpose: the update is required, but it should read as something good, not a wall. Updating keeps all local data, so the streak line is true.
  ///
  /// In en, this message translates to:
  /// **'We\'ve made {appName} better. Update to keep your streak going.'**
  String updateRequiredBody(String appName);

  /// /update's direct route to the Play Store listing.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateRequiredAction;

  /// /withdrawn heading — FR-040, reached only when every cached problem is withdrawn.
  ///
  /// In en, this message translates to:
  /// **'Swapping in a different problem'**
  String get withdrawnTitle;

  /// /withdrawn body — a swap, not a broken problem.
  ///
  /// In en, this message translates to:
  /// **'Today\'s problem isn\'t available. We\'re getting you another one.'**
  String get withdrawnBody;

  /// /withdrawn's one affordance: retry the manifest fetch.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get withdrawnRetryAction;

  /// Icon-button tooltip on the daily screen routing to /streak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get dailyStreakTooltip;

  /// Icon-button tooltip on the daily screen routing to /settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get dailySettingsTooltip;

  /// /settings heading.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// /settings row routing to /settings/key (FR-006).
  ///
  /// In en, this message translates to:
  /// **'Provider key'**
  String get settingsKeyManagementLabel;

  /// /settings row routing to /settings/reminder (FR-048a).
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get settingsReminderLabel;

  /// /settings row routing to /settings/wipe (FR-039f).
  ///
  /// In en, this message translates to:
  /// **'Delete all data'**
  String get settingsWipeLabel;

  /// /settings/key heading (FR-006).
  ///
  /// In en, this message translates to:
  /// **'Provider key'**
  String get keyManagementTitle;

  /// Shown when KeyRepository.read() returns null, above the add-key action.
  ///
  /// In en, this message translates to:
  /// **'No key saved. Add one now, or after your next session.'**
  String get keyManagementNoKey;

  /// Opens the inline entry flow from settings when no key is stored yet (FR-006).
  ///
  /// In en, this message translates to:
  /// **'Add key'**
  String get keyManagementAddAction;

  /// Names the provider the stored key belongs to, never the key value itself (FR-003).
  ///
  /// In en, this message translates to:
  /// **'Saved for {provider}'**
  String keyManagementProviderLabel(String provider);

  /// Opens the inline replace flow, reusing KeyEntryCubit (FR-006).
  ///
  /// In en, this message translates to:
  /// **'Replace key'**
  String get keyManagementReplaceAction;

  /// FR-006's delete.
  ///
  /// In en, this message translates to:
  /// **'Delete key'**
  String get keyManagementDeleteAction;

  /// Shown after a successful delete.
  ///
  /// In en, this message translates to:
  /// **'Key deleted. Add one again to use your own allowance.'**
  String get keyManagementDeletedNotice;

  /// /settings/reminder heading (FR-048a).
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get reminderScreenTitle;

  /// FR-048a/b explained plainly.
  ///
  /// In en, this message translates to:
  /// **'One notification a day, made on this phone. It\'s cancelled once that day\'s session is done.'**
  String get reminderScreenBody;

  /// Toggle on /settings/reminder.
  ///
  /// In en, this message translates to:
  /// **'Remind me daily'**
  String get reminderEnabledToggle;

  /// Label for the time picker row.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get reminderTimeLabel;

  /// /settings/wipe heading (FR-039f).
  ///
  /// In en, this message translates to:
  /// **'Delete all data'**
  String get wipeScreenTitle;

  /// Clear warning the streak ends, and honest about what a wipe cannot undo (FR-039f).
  ///
  /// In en, this message translates to:
  /// **'Deletes every conversation, assessment and cached problem on this phone, and ends your streak. It won\'t give back your free taster or reset your device identity.'**
  String get wipeScreenWarning;

  /// The one destructive action on this screen.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get wipeConfirmAction;

  /// Confirmation dialog raised by the wipe action — the last step before an irreversible delete (FR-039f).
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get wipeConfirmDialogTitle;

  /// Restates the consequence at the moment of the decision, rather than relying on the warning read further up the screen.
  ///
  /// In en, this message translates to:
  /// **'Your conversations, assessments and streak all go. This can\'t be undone.'**
  String get wipeConfirmDialogBody;

  /// Dismisses the confirmation dialog with nothing deleted; the default action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get wipeCancelAction;

  /// Shown after a successful wipe, before returning to the daily screen.
  ///
  /// In en, this message translates to:
  /// **'All data deleted.'**
  String get wipeDoneNotice;

  /// RATE_LIMITED. Not an error: the conversation catching up. No red, no failure icon, no apology (FR-045a).
  ///
  /// In en, this message translates to:
  /// **'The provider is catching up. This continues in a moment.'**
  String get errRateLimited;

  /// INVALID_KEY. A repairable interruption; the conversation is preserved (FR-005c).
  ///
  /// In en, this message translates to:
  /// **'The provider rejected that key. Try a different one. Your conversation is safe.'**
  String get errInvalidKey;

  /// QUOTA_EXHAUSTED. Must say it is the learner's own allowance and that no charge occurred (FR-008d).
  ///
  /// In en, this message translates to:
  /// **'Your daily allowance with this provider is spent. It resets on its own, and nothing was charged.'**
  String get errQuotaExhausted;

  /// UNCLEAR_RETRY. A hiccup. The practice run has already retried once silently by the time this shows; the daily chat offers a retry on the failed message.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t come through. Try sending it again.'**
  String get errUnclearRetry;

  /// TURN_CAP_REACHED. A normal ending, never styled as a failure (FR-023, FR-028).
  ///
  /// In en, this message translates to:
  /// **'That\'s today\'s conversation length. Hints still work, and you can finish to see how it went.'**
  String get errTurnCapReached;

  /// TRIAL_CONSUMED. Not an error, not an outage — straight into key entry (FR-007).
  ///
  /// In en, this message translates to:
  /// **'Your free taster is used up. Add your own key to keep going. You can\'t be charged.'**
  String get errTrialConsumed;

  /// SESSION_ALREADY_JUDGED, repeat judge call. The assessment repository recovers from this itself, so it is a fallback; it still offers Try again.
  ///
  /// In en, this message translates to:
  /// **'This session was already assessed. Tap Try again to load it.'**
  String get errAlreadyJudgedRepeat;

  /// SESSION_ALREADY_JUDGED, turn or hint after verdict. A closed door, plainly (FR-034 scenario 4).
  ///
  /// In en, this message translates to:
  /// **'This session is closed and the verdict is in. You can review the assessment or the reveal.'**
  String get errSessionClosed;

  /// EMPTY_TURN. A prompt, not a failure; costs no turn.
  ///
  /// In en, this message translates to:
  /// **'Nothing was heard. Re-record, or type instead.'**
  String get errEmptyTurn;

  /// Small caption under every error message, so a learner can quote the exact failure when they contact support. The code is the relay catalogue name (e.g. EMPTY_TURN) and is never translated.
  ///
  /// In en, this message translates to:
  /// **'Code: {code}'**
  String errorCodeLabel(String code);

  /// TRIAL_IP_LIMIT. This network hit its daily free-session cap; not an outage.
  ///
  /// In en, this message translates to:
  /// **'Free sessions from this network are used up for today. Add your own Nebius key to keep going.'**
  String get errTrialIpLimited;

  /// TRIAL_UNAVAILABLE. Capacity, never an outage or a fault of the learner's (FR-007 scenario 4).
  ///
  /// In en, this message translates to:
  /// **'The free taster is full today. Add your key and start now. You can\'t be charged.'**
  String get errTrialUnavailable;

  /// PROBLEM_KILLED. A swap, not a message, wherever the UI can make it invisible (FR-040).
  ///
  /// In en, this message translates to:
  /// **'Today\'s problem has been withdrawn — here is another one.'**
  String get errProblemKilled;

  /// BAD_REQUEST. Our fault, said plainly. Never echoes a field from the request.
  ///
  /// In en, this message translates to:
  /// **'Something failed on our side. Try again, and update the app if it keeps happening.'**
  String get errBadRequest;

  /// Client-side transport failure (never reached the relay). A retryable bubble in the conversation, never a lost thought (FR-042).
  ///
  /// In en, this message translates to:
  /// **'No connection. Try again once you\'re back online.'**
  String get errOfflineQueued;

  /// Title of the popup shown when the app hits an error it did not expect (a bug, not a relay error).
  ///
  /// In en, this message translates to:
  /// **'Something broke'**
  String get crashTitle;

  /// Body of the unexpected-error popup. The code (e.g. APP-3F2A1C) is the same for the same bug, so reports can be grouped. Never translated.
  ///
  /// In en, this message translates to:
  /// **'If it keeps happening, send us this code: {code}'**
  String crashBody(String code);

  /// Copies the code, app version, time and redacted error details to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get crashCopyAction;

  /// Dismisses the unexpected-error popup.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get crashCloseAction;

  /// Snackbar after the error details were copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get crashCopied;

  /// Generic retry control on a Failure state — resends the same text for a transport/relay failure.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryAction;

  /// Semantic label on the mic — the composer's primary, single large target (FR-009).
  ///
  /// In en, this message translates to:
  /// **'Speak your turn'**
  String get composerMicSemanticLabel;

  /// The small underlined link beneath the mic. Less prominent, never less reachable (FR-009).
  ///
  /// In en, this message translates to:
  /// **'Type instead'**
  String get composerTypeInsteadLink;

  /// Text field label on the keyboard-only composer path (FR-010, FR-053).
  ///
  /// In en, this message translates to:
  /// **'Type your turn…'**
  String get textComposerLabel;

  /// Send control on the typed-turn composer.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get textComposerSendLabel;

  /// Recording screen heading (prototype screen 2).
  ///
  /// In en, this message translates to:
  /// **'Listening in English…'**
  String get recordingTitle;

  /// FR-013a's warning at 15 seconds remaining in the 90-second cap.
  ///
  /// In en, this message translates to:
  /// **'15 seconds left'**
  String get recordingWarningNotice;

  /// Ends the listen session normally, producing a final transcript.
  ///
  /// In en, this message translates to:
  /// **'Done speaking'**
  String get recordingStopLabel;

  /// Abandons the listen session with no final transcript.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get recordingCancelLabel;

  /// The waveform is labelled, not read out loud value-by-value (design-tokens.md accessibility section).
  ///
  /// In en, this message translates to:
  /// **'Microphone input level'**
  String get recordingWaveformSemanticLabel;

  /// Mic rationale screen heading (prototype screen 9), shown at first record, never at launch (FR-014).
  ///
  /// In en, this message translates to:
  /// **'Why we ask for the microphone'**
  String get micRationaleTitle;

  /// Honest about the cloud path (clip uploaded to our server and forwarded to Groq, deleted after use, never stored server-side) and the on-device fallback, where the platform recognizer may stream audio to its maker's service (Android's docs say it 'is likely to stream audio to remote servers'). Matches amended Principle VII and the voice-groq-stt design (FR-014, owner decision D3).
  ///
  /// In en, this message translates to:
  /// **'When you speak, Dry Run records a short clip and sends it to our server, which passes it to Groq\'s speech service to turn it into text. We don\'t keep your clips: each one is deleted from your phone once it\'s transcribed or discarded, and our server never stores it. If voice transcription is busy or today\'s allowance is used up, your phone\'s own speech recognition takes over, and it may send audio to its maker\'s service. Speaking works in English for now.'**
  String get micRationaleBody;

  /// Status label shown while a clip is being recorded for cloud transcription.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recordingCloudLabel;

  /// Heading of the retry notice after a retryable cloud upload failure (offline, timeout, or the speech service busy). The saved clip is kept for Try again.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t go through.'**
  String get recordingCloudRetryTitle;

  /// Body of the retry notice; reassures the learner the clip is kept so they need not speak again. The Try again button reuses retryAction.
  ///
  /// In en, this message translates to:
  /// **'Your recording is saved, so there\'s no need to say it again. Check your connection and tap Try again.'**
  String get recordingCloudRetryBody;

  /// Button that deletes the saved clip after a failed cloud upload instead of retrying.
  ///
  /// In en, this message translates to:
  /// **'Discard recording'**
  String get recordingCloudDiscardAction;

  /// Notice after a non-retryable cloud transcription failure where cloud voice stays available (BAD_REQUEST). Not a judgement on the learner.
  ///
  /// In en, this message translates to:
  /// **'Sorry, we couldn\'t transcribe that one. Please tap the mic and say it again.'**
  String get recordingCloudFailedNotice;

  /// Notice when cloud voice is unavailable or the daily allowance is used up (VOICE_UNAVAILABLE, VOICE_EXHAUSTED); the next mic tap uses on-device speech recognition.
  ///
  /// In en, this message translates to:
  /// **'Sorry, we couldn\'t transcribe that one. Please tap the mic and say it again; your phone\'s speech recognition will take it from here.'**
  String get recordingCloudFallbackNotice;

  /// Proceeds to the system microphone permission prompt.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get micRationaleContinue;

  /// Transcript review screen heading (prototype screen 3) — the mandatory, unskippable step (Principle V).
  ///
  /// In en, this message translates to:
  /// **'Review before sending'**
  String get reviewTitle;

  /// Explains why the review step exists without ever implying the transcript is wrong to have needed it.
  ///
  /// In en, this message translates to:
  /// **'Edit anything that was misheard, then send.'**
  String get reviewEditHint;

  /// The same mandatory review step reached from the typed composer. Nothing was heard on that path, so the spoken-path wording about mishearing would be nonsense (found on device).
  ///
  /// In en, this message translates to:
  /// **'Check it reads the way you meant, then send.'**
  String get reviewEditHintTyped;

  /// The typed path's peer of send: returns to the composer to keep editing. Re-record would open the microphone, which is not what a typed turn asked for.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get reviewDiscardLabel;

  /// Sends the reviewed turn — the one call path into SessionRepository.sendTurn.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reviewSendLabel;

  /// A peer of send, not a fallback (FR-012b).
  ///
  /// In en, this message translates to:
  /// **'Re-record'**
  String get reviewReRecordLabel;

  /// Restores the unmodified recogniser output after transcript repair changed the draft (FR-005, US2). Shown only when repair changed something and the learner has not already reverted.
  ///
  /// In en, this message translates to:
  /// **'Show what I said'**
  String get reviewRevertLabel;

  /// Opens the collapsed problem card. The statement is clipped to three lines on the daily screen so the conversation owns the rest of it; without this there was no way to read the rest at all (found on device).
  ///
  /// In en, this message translates to:
  /// **'Read the full problem'**
  String get problemExpandLabel;

  /// Collapses the problem card back to its three-line summary.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get problemCollapseLabel;

  /// Heading for the authored constraints list, revealed with the full statement.
  ///
  /// In en, this message translates to:
  /// **'Constraints'**
  String get problemConstraintsLabel;

  /// Stands in for the conversation before the first turn, where the screen was otherwise a large empty void that read as a loading failure (found on device).
  ///
  /// In en, this message translates to:
  /// **'Say how you\'d start. Think out loud, half-formed is fine.'**
  String get conversationEmptyBody;

  /// Shown when a listen session ends with no transcript at all. Returning to the idle composer in silence made the recording screen look like it had crashed (found on device).
  ///
  /// In en, this message translates to:
  /// **'Didn\'t catch that. Try again in English, or type.'**
  String get recordingNothingHeardNotice;

  /// Sender label for a learner turn in the conversation.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get messageListYouLabel;

  /// Sender label for a tutor turn in the conversation.
  ///
  /// In en, this message translates to:
  /// **'Tutor'**
  String get messageListTutorLabel;

  /// A retryable bubble in the conversation, never a lost thought (FR-042).
  ///
  /// In en, this message translates to:
  /// **'Not sent — tap to retry'**
  String get messageListFailedRetryLabel;

  /// Worded as remaining allowance, never as a score (FR-022a) — the same wording is used as the semantic label so screen readers announce it the same way.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No turns left today} =1{1 turn left today} other{{count} turns left today}}'**
  String turnGaugeLabel(int count);

  /// Finish-offer card heading (feature 005): the finish check says every required key idea has been explained.
  ///
  /// In en, this message translates to:
  /// **'Sounds like you\'ve got it'**
  String get finishOfferTitle;

  /// Finish-offer card body. An offer, never a verdict; the assessment still decides.
  ///
  /// In en, this message translates to:
  /// **'You\'ve explained the key idea. Finish now and see how you did, or keep going to dig deeper.'**
  String get finishOfferBody;

  /// Finish-offer card primary action: ends the session and starts the assessment.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finishOfferFinish;

  /// Finish-offer card secondary action: hides the card for the rest of the session.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get finishOfferKeepGoing;

  /// Entered at config.chat.wrap_up_at_turn — the conversation winds down rather than stopping dead (FR-022).
  ///
  /// In en, this message translates to:
  /// **'Wrapping up'**
  String get wrapUpBannerTitle;

  /// Protects the learner's own free allowance rather than scoring them (FR-022a).
  ///
  /// In en, this message translates to:
  /// **'You\'re near today\'s limit. A few more, then finish and see how it went.'**
  String get wrapUpBannerBody;

  /// A normal ending, never styled as a failure (FR-023, FR-028).
  ///
  /// In en, this message translates to:
  /// **'Today\'s conversation is complete'**
  String get capReachedTitle;

  /// Hints and end-session remain live — the cap bounds conversation, not either of those (FR-028).
  ///
  /// In en, this message translates to:
  /// **'You can still pull a hint or end the session to see how it went.'**
  String get capReachedBody;

  /// FR-011a — a recognizer exists, but not for the language being spoken. No in-app fix, so no action is offered beyond the keyboard.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition doesn\'t cover this language yet'**
  String get recognitionUnavailableTitleLanguage;

  /// Says plainly that there is nothing to install — the app uses the platform's default recognizer, which needs no language pack (FR-011a).
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s speech recognition doesn\'t handle this language. You can still type.'**
  String get recognitionUnavailableBodyLanguage;

  /// FR-011a — no recognizer on the device at all.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition isn\'t available on this device'**
  String get recognitionUnavailableTitleUnsupported;

  /// The keyboard path is fully capable, not a lesser substitute (FR-053).
  ///
  /// In en, this message translates to:
  /// **'You can still take part by typing.'**
  String get recognitionUnavailableBodyUnsupported;

  /// FR-011b picker heading. The platform recognizer takes one language per session and cannot auto-detect, so the learner must say which.
  ///
  /// In en, this message translates to:
  /// **'Which language will you speak?'**
  String get spokenLanguageSheetTitle;

  /// FR-011b search field. The list spans every locale the platform knows, so it needs filtering.
  ///
  /// In en, this message translates to:
  /// **'Search languages'**
  String get spokenLanguageSearchHint;

  /// Shown when the FR-011b search filters everything out.
  ///
  /// In en, this message translates to:
  /// **'No language matches that.'**
  String get spokenLanguageNoMatches;

  /// The keyboard path, permitted only while recognition is unavailable (FR-011a).
  ///
  /// In en, this message translates to:
  /// **'Type instead'**
  String get recognitionUnavailableTypeInstead;

  /// INVALID_KEY / QUOTA_EXHAUSTED next action on a Failure notice — routes to key entry rather than retrying with the same key (FR-005c, FR-008d).
  ///
  /// In en, this message translates to:
  /// **'Enter key'**
  String get errorReEnterKeyAction;

  /// The wall's lead line (prototype screen 10) — the one fact most likely to matter first (FR-005a).
  ///
  /// In en, this message translates to:
  /// **'You cannot be charged'**
  String get wallCannotBeCharged;

  /// Explains the free-forever model without pressuring an immediate decision.
  ///
  /// In en, this message translates to:
  /// **'Your free taster is done. Add your own Nebius key to keep going; new accounts get \$1 of free credit. {appName} never charges you.'**
  String wallBody(String appName);

  /// Routes to /keys/entry.
  ///
  /// In en, this message translates to:
  /// **'Add your key'**
  String get wallAddKey;

  /// Returns to the daily screen — hints and ending the session are still available at the cap (FR-028).
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get wallNotNow;

  /// Key entry screen heading (prototype screen 11).
  ///
  /// In en, this message translates to:
  /// **'Add your key'**
  String get keyEntryTitle;

  /// States where the key lives (FR-005d) before asking for it.
  ///
  /// In en, this message translates to:
  /// **'Paste a Nebius Token Factory API key. New accounts get \$1 of free credit. The key stays on this phone.'**
  String get keyEntryIntro;

  /// config.keyed_providers came back empty — a fail-open case, not a crash.
  ///
  /// In en, this message translates to:
  /// **'No providers available right now. Try again shortly.'**
  String get keyEntryNoProviders;

  /// FR-008a/e — names the provider actually chosen and points at its own policy rather than asserting one that could go stale.
  ///
  /// In en, this message translates to:
  /// **'{provider} receives the text of your conversation. Never your key, never the hidden solution. Check {provider}\'s terms for whether it trains on free-tier content.'**
  String keyEntryDisclosure(String provider);

  /// Link to the chosen provider's own key console.
  ///
  /// In en, this message translates to:
  /// **'Get a {provider} key (\$1 free credit)'**
  String keyEntryGetFreeKey(String provider);

  /// The key input field. obscureText — never shown in the clear once pasted.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get keyEntryFieldLabel;

  /// Probes before persisting (FR-005b) — this label covers both.
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get keyEntrySave;

  /// FR-007b — says the allowance grew rather than silently giving more (SC-020).
  ///
  /// In en, this message translates to:
  /// **'Key saved. Same conversation, more room.'**
  String get keyEntryAllowanceGrew;

  /// TRIAL_CONSUMED prompt dialog heading (FR-007). Shown over the conversation instead of dropping the learner on the key form unannounced.
  ///
  /// In en, this message translates to:
  /// **'Your free taster is done'**
  String get keyPromptTrialTitle;

  /// Explains why the key is being asked for, and that it cannot cost anything, before the form is offered.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used the free sessions {appName} provides. Add your own Nebius key to keep going; new accounts get \$1 of free credit. It stays on this phone, and {appName} never charges you.'**
  String keyPromptTrialBody(String appName);

  /// TRIAL_UNAVAILABLE prompt dialog heading — the shared taster is full for everyone today, not this learner's allowance.
  ///
  /// In en, this message translates to:
  /// **'The free taster is at capacity'**
  String get keyPromptTrialUnavailableTitle;

  /// Must never borrow QUOTA_EXHAUSTED copy — this is capacity, not an allowance the learner spent.
  ///
  /// In en, this message translates to:
  /// **'Today\'s free taster is full, for everyone using {appName} today. Add your own Nebius key and start now; new accounts get \$1 of free credit. It stays on this phone, and {appName} never charges you.'**
  String keyPromptTrialUnavailableBody(String appName);

  /// TRIAL_IP_LIMIT prompt dialog heading — this network started its daily allowance of free sessions.
  ///
  /// In en, this message translates to:
  /// **'Today\'s free sessions are used up'**
  String get keyPromptTrialIpLimitedTitle;

  /// TRIAL_IP_LIMIT prompt body. Not capacity for everyone, and not the learner's own key allowance.
  ///
  /// In en, this message translates to:
  /// **'Free sessions from this network are used up for today. Add your own Nebius key to keep going; new accounts get \$1 of free credit. It stays on this phone, and {appName} never charges you.'**
  String keyPromptTrialIpLimitedBody(String appName);

  /// QUOTA_EXHAUSTED popup heading (FR-008d) — the learner's own key hit its provider limit.
  ///
  /// In en, this message translates to:
  /// **'Your provider allowance is spent'**
  String get keyPromptQuotaTitle;

  /// Leads with the reset and the no-charge fact before offering the replace action (ErrorNextAction.waitOrReplaceKey).
  ///
  /// In en, this message translates to:
  /// **'Your Nebius credit or rate limit is used up. Add credit in your Nebius account, or wait a bit and try again.'**
  String get keyPromptQuotaBody;

  /// Primary action on the trial prompts — pushes /keys/entry so the conversation is still behind it.
  ///
  /// In en, this message translates to:
  /// **'Add your key'**
  String get keyPromptAddAction;

  /// Primary action on the QUOTA_EXHAUSTED popup — replacing the key is the only way to continue before the reset.
  ///
  /// In en, this message translates to:
  /// **'Use a different key'**
  String get keyPromptReplaceAction;

  /// Dismisses a key prompt. The same explanation stays on the daily screen as an inline notice, so nothing is lost by declining.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get keyPromptDismissAction;

  /// Dismisses the QUOTA_EXHAUSTED popup. Named after what it actually does rather than a bare OK.
  ///
  /// In en, this message translates to:
  /// **'Wait for the reset'**
  String get keyPromptQuotaDismissAction;

  /// RATE_LIMITED popup heading. The learner's own key sent too many messages this minute.
  ///
  /// In en, this message translates to:
  /// **'Your key hit its limit'**
  String get rateLimitTitle;

  /// RATE_LIMITED popup body. The turn resends by itself; seconds is the provider's retry-after.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Too many messages this minute. Yours sends again in 1 second.} other{Too many messages this minute. Yours sends again in {seconds} seconds.}}'**
  String rateLimitBody(int seconds);

  /// Closes the RATE_LIMITED popup. The resend happens either way.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get rateLimitOkAction;

  /// The explicit hint control (FR-025), distinct from asking for a hint in conversation.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get hintActionLabel;

  /// Label above a hintRung message bubble (FR-026).
  ///
  /// In en, this message translates to:
  /// **'Hint {index} of {count}'**
  String hintMessageLabel(int index, int count);

  /// Label above the fixed ladder-exhausted closing line — the session stays open, this is not an error.
  ///
  /// In en, this message translates to:
  /// **'Hints'**
  String get hintLadderExhaustedLabel;

  /// The end-session affordance kept live in CapReached (FR-023) — the cap bounds conversation, not the learner's ability to close the session.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSessionLabel;

  /// Entry point to the solution-request flow. The tutor never says correct or wrong on its own, so without this the learner has no way to stop being asked questions. The first tap is an ordinary turn; a second routes through confirmSolutionWarning (FR-021) before anything is sent.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get askForAnswerLabel;

  /// Confirm-solution screen heading — the only route a second solution request can be sent from (FR-021).
  ///
  /// In en, this message translates to:
  /// **'One more thing before that'**
  String get confirmSolutionTitle;

  /// FR-021's warning, shown before the second solution request is sendable at all.
  ///
  /// In en, this message translates to:
  /// **'This ends today\'s session. You still get your assessment and the write-up, for the work up to now.'**
  String get confirmSolutionWarning;

  /// Backs out without sending anything.
  ///
  /// In en, this message translates to:
  /// **'Keep going instead'**
  String get confirmSolutionCancel;

  /// The only button that can send a second solution request.
  ///
  /// In en, this message translates to:
  /// **'Yes, show me the solution'**
  String get confirmSolutionProceed;

  /// Hedged word for Verdict.strongPass — paired with a hue, never hue alone (FR-030).
  ///
  /// In en, this message translates to:
  /// **'Strong approach'**
  String get verdictStrongPass;

  /// Hedged word for Verdict.pass.
  ///
  /// In en, this message translates to:
  /// **'Solid approach'**
  String get verdictPass;

  /// Hedged word for Verdict.borderline.
  ///
  /// In en, this message translates to:
  /// **'Getting there'**
  String get verdictBorderline;

  /// Hedged word for Verdict.fail — never the word "fail" or "wrong" itself (FR-030).
  ///
  /// In en, this message translates to:
  /// **'Worth another pass'**
  String get verdictFail;

  /// Hedged word for Verdict.unclear.
  ///
  /// In en, this message translates to:
  /// **'Hard to call'**
  String get verdictUnclear;

  /// MatchedVerdict.optimal.
  ///
  /// In en, this message translates to:
  /// **'This matched the strongest approach on file.'**
  String get matchedApproachOptimal;

  /// MatchedVerdict.acceptable.
  ///
  /// In en, this message translates to:
  /// **'This matched a solid, accepted approach.'**
  String get matchedApproachAcceptable;

  /// MatchedVerdict.suboptimal.
  ///
  /// In en, this message translates to:
  /// **'This matched a workable approach, though not the strongest one.'**
  String get matchedApproachSuboptimal;

  /// MatchedVerdict.wrong — hedged; never the word "wrong" itself (FR-030).
  ///
  /// In en, this message translates to:
  /// **'This took a different direction than the problem intended.'**
  String get matchedApproachWrong;

  /// MatchedVerdict.none — a designed state (Principle II), not an error.
  ///
  /// In en, this message translates to:
  /// **'Nothing here matched an approach on file.'**
  String get matchedApproachNone;

  /// Complexity.assessment == correct.
  ///
  /// In en, this message translates to:
  /// **'matches the reference'**
  String get complexityMatch;

  /// Complexity.assessment == mismatched — hedged, not "wrong".
  ///
  /// In en, this message translates to:
  /// **'differs from the reference'**
  String get complexityMismatch;

  /// Complexity.assessment == not_stated.
  ///
  /// In en, this message translates to:
  /// **'wasn\'t stated'**
  String get complexityNotStated;

  /// Verdict screen heading (prototype screen 6).
  ///
  /// In en, this message translates to:
  /// **'How it went'**
  String get verdictScreenTitle;

  /// Label over the insights-hit glyph list.
  ///
  /// In en, this message translates to:
  /// **'Reached'**
  String get verdictInsightsHitLabel;

  /// Muted tag after a Reached insight the learner got by accepting an idea the tutor put into words — PLAN_07.
  ///
  /// In en, this message translates to:
  /// **'with a nudge'**
  String get verdictInsightAssistedTag;

  /// Label over the insights-missed glyph list — a distinct glyph, not a red dot (design-tokens.md).
  ///
  /// In en, this message translates to:
  /// **'Not reached'**
  String get verdictInsightsMissedLabel;

  /// Section heading for the complexity comparison.
  ///
  /// In en, this message translates to:
  /// **'Complexity'**
  String get verdictComplexityLabel;

  /// The dispute affordance, present on every assessment screen, one tap away (FR-031).
  ///
  /// In en, this message translates to:
  /// **'Dispute this assessment'**
  String get verdictDisputeAction;

  /// Shown after disputing. No consent prompt: nothing is uploaded (FR-031a/b).
  ///
  /// In en, this message translates to:
  /// **'Noted. Flagged as disputed on this phone.'**
  String get verdictDisputedNotice;

  /// Routes to the reveal screen — the editorial, gated on this assessment existing (FR-032).
  ///
  /// In en, this message translates to:
  /// **'Read the full write-up'**
  String get verdictReadEditorialAction;

  /// No description provided for @verdictPracticeAgainAction.
  ///
  /// In en, this message translates to:
  /// **'Practice this problem again'**
  String get verdictPracticeAgainAction;

  /// FR-033: shown when the session ended by a solution request. Never worded to penalise asking.
  ///
  /// In en, this message translates to:
  /// **'This covers only the work before the solution was shown. Asking for it isn\'t held against you.'**
  String get verdictSolutionReleaseNotice;

  /// Reveal screen heading (prototype screen 7) — the only place the editorial appears (FR-032).
  ///
  /// In en, this message translates to:
  /// **'The write-up'**
  String get revealScreenTitle;

  /// SessionClosed state heading — a stray turn or hint landed after the verdict (FR-034 scenario 4).
  ///
  /// In en, this message translates to:
  /// **'This session is closed'**
  String get sessionClosedTitle;

  /// SessionClosed's one affordance: show the verdict already held.
  ///
  /// In en, this message translates to:
  /// **'Review the assessment'**
  String get sessionClosedReviewAction;

  /// Streak screen heading (prototype screen 8).
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get streakScreenTitle;

  /// The current streak length, mono (design-tokens.md — anything numeric).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No streak yet} =1{1 day} other{{count} days}}'**
  String streakCountLabel(int count);

  /// Spec edge case, FR-039 — a plain statement the learner will see, not a warning.
  ///
  /// In en, this message translates to:
  /// **'This streak lives on this phone. It won\'t follow you to another device or survive a reinstall.'**
  String get streakPerInstallNotice;

  /// Routes to the current day's completed session — reachable in ≤3 taps (SC-013), no second problem offered.
  ///
  /// In en, this message translates to:
  /// **'Review today'**
  String get streakReviewTodayAction;

  /// Review-day screen heading — the current day's completed session and assessment only, never a second problem (FR-039).
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get reviewDayScreenTitle;

  /// Share card body line — never any part of the conversation itself (FR-039b).
  ///
  /// In en, this message translates to:
  /// **'{hit} of {total} key insights reached'**
  String shareCardInsightsLine(int hit, int total);

  /// The learner’s own complexity on the share card, in place of a verdict on it.
  ///
  /// In en, this message translates to:
  /// **'{time} time, {space} space'**
  String shareCardComplexityLine(String time, String space);

  /// Share card body line.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Day 1 of the streak} other{Day {count} of the streak}}'**
  String shareCardStreakLine(int count);

  /// Invokes the platform share sheet with the text-only card (FR-039b).
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareCardAction;

  /// Returns the composer to the mic from the inline keyboard field.
  ///
  /// In en, this message translates to:
  /// **'Use the mic instead'**
  String get composerUseMicLabel;

  /// Compact label beside the live waveform in the chat composer. EN says the mic is English-only for now, in the least width; typing works in any language.
  ///
  /// In en, this message translates to:
  /// **'Listening · EN'**
  String get recordingListeningLabel;

  /// Shown while the recogniser resolves the final transcript.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get recordingTranscribingLabel;

  /// Header on the inline review strip inside the chat screen.
  ///
  /// In en, this message translates to:
  /// **'Check before sending'**
  String get reviewInlineTitle;

  /// Opens the worked examples for today’s problem.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get examplesActionLabel;

  /// Title of the worked-examples sheet.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get examplesSheetTitle;

  /// Ordinal heading for one worked example.
  ///
  /// In en, this message translates to:
  /// **'Example {index}'**
  String exampleIndexLabel(int index);

  /// Label above an example’s input.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get exampleInputLabel;

  /// Label above an example’s expected output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get exampleOutputLabel;

  /// Label above an example’s explanation.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get exampleExplanationLabel;

  /// Generic back affordance where there is no navigation stack to pop.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backAction;

  /// Shown on the daily screen while the judge request is in flight.
  ///
  /// In en, this message translates to:
  /// **'Working out how it went…'**
  String get judgingNotice;

  /// Shown on the daily screen once a verdict exists for today.
  ///
  /// In en, this message translates to:
  /// **'Your assessment is ready'**
  String get assessmentReadyTitle;

  /// Reopens the verdict screen from the daily screen.
  ///
  /// In en, this message translates to:
  /// **'See how it went'**
  String get assessmentReadyAction;

  /// Secondary action beside the assessment result that resets the current problem for another attempt.
  ///
  /// In en, this message translates to:
  /// **'Solve it again'**
  String get assessmentPracticeAgainAction;

  /// Ordinal label on a revealed worked example in the conversation, the peer of hintMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Example {index} of {count}'**
  String exampleMessageLabel(int index, int count);

  /// App-bar action that closes the session and asks for the assessment (FR-023).
  ///
  /// In en, this message translates to:
  /// **'Finish and see how it went'**
  String get dailyEndSessionTooltip;

  /// Primary action inside the wrap-up card: ends the session and requests the assessment.
  ///
  /// In en, this message translates to:
  /// **'Finish and see how it went'**
  String get wrapUpFinishAction;

  /// Says plainly that the assessment is learner-triggered, not automatic.
  ///
  /// In en, this message translates to:
  /// **'Nothing ends it for you. Tap Finish and you get your assessment.'**
  String get endSessionExplainer;

  /// FR-031a/b: what disputing actually does, said before the learner taps it.
  ///
  /// In en, this message translates to:
  /// **'Flags it on this phone so you can find it again. Nothing is uploaded.'**
  String get verdictDisputeExplainer;

  /// The dispute control once it has been used.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get verdictDisputedAction;

  /// Label for the complexity the learner claimed.
  ///
  /// In en, this message translates to:
  /// **'You said'**
  String get verdictComplexityYoursLabel;

  /// Label for the reference approach’s complexity.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get verdictComplexityReferenceLabel;

  /// Shown when matched_approach is "none" — an unlisted approach is not thereby wrong.
  ///
  /// In en, this message translates to:
  /// **'Your approach isn\'t one on file. It was judged on the insights you reached, not marked down for being unlisted.'**
  String get verdictComplexityUnlistedNotice;

  /// Shown when POST_NOTIFICATIONS has not been granted.
  ///
  /// In en, this message translates to:
  /// **'Android needs permission to show notifications. Turn the reminder on and allow it when asked.'**
  String get reminderPermissionNeededNotice;

  /// Shown when the runtime notification permission was refused.
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked for this app. Turn them on in Android\'s app settings.'**
  String get reminderPermissionDeniedNotice;

  /// Confirms the reminder is actually scheduled.
  ///
  /// In en, this message translates to:
  /// **'Armed. The next one lands at {time}.'**
  String reminderScheduledNotice(String time);

  /// Shown when SCHEDULE_EXACT_ALARM is not granted — the reminder still arrives, just inside a window Android picks.
  ///
  /// In en, this message translates to:
  /// **'Android can hold this back up to an hour. Allow exact alarms and it lands on time.'**
  String get reminderInexactNotice;

  /// Opens Android’s “Alarms & reminders” page, the only place SCHEDULE_EXACT_ALARM can be granted.
  ///
  /// In en, this message translates to:
  /// **'Allow exact alarms'**
  String get reminderExactAlarmAction;

  /// Heading on the shareable result card.
  ///
  /// In en, this message translates to:
  /// **'Today’s result'**
  String get shareCardTitle;

  /// Label above the approach class on the share card.
  ///
  /// In en, this message translates to:
  /// **'Approach'**
  String get shareCardApproachLabel;

  /// Label above the insight tally on the share card.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get shareCardInsightsLabel;

  /// Takes the learner to Android’s settings page for this app, the only place a refused notification permission can still be granted.
  ///
  /// In en, this message translates to:
  /// **'Open notification settings'**
  String get reminderOpenSettingsAction;

  /// One slide of the welcome carousel: the premise — why reasoning is the thing worth practising.
  ///
  /// In en, this message translates to:
  /// **'Keep your own mind sharp'**
  String get welcomeSlide1Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'AI can write the code now. It can\'t sit in the interview for you, or explain why you chose this over that. Ten minutes a day keeps that muscle yours.'**
  String get welcomeSlide1Body;

  /// One slide of the welcome carousel: the shape of the product.
  ///
  /// In en, this message translates to:
  /// **'Say it out loud'**
  String get welcomeSlide2Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic and talk through your idea the way you would to a colleague. Messy is fine. No code, no typing, no multiple choice.'**
  String get welcomeSlide2Body;

  /// One slide of the welcome carousel: why the tutor is Socratic.
  ///
  /// In en, this message translates to:
  /// **'One problem a day'**
  String get welcomeSlide3Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'No feed. No backlog to fall behind on. One problem, a few minutes, done.'**
  String get welcomeSlide3Body;

  /// One slide of the welcome carousel: the assessment is learner-triggered.
  ///
  /// In en, this message translates to:
  /// **'It asks. It never tells.'**
  String get welcomeSlide4Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'The tutor pushes back instead of answering. That\'s the point, and yes, it can feel stubborn. Stuck? Tap Hint or Example. Neither costs you a turn.'**
  String get welcomeSlide4Body;

  /// One slide of the welcome carousel: the daily reminder, enabled inline.
  ///
  /// In en, this message translates to:
  /// **'You say when you are done'**
  String get welcomeSlide5Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'It\'ll keep asking forever if you let it. Tap Finish when you\'ve said your piece. That\'s what gets you the write-up.'**
  String get welcomeSlide5Body;

  /// One slide of the welcome carousel: the BYOK model.
  ///
  /// In en, this message translates to:
  /// **'Make it a habit'**
  String get welcomeSlide6Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'A new problem lands every day. Pick a time and we\'ll nudge you: one reminder, made on this phone. Miss a day and the streak just starts again.'**
  String get welcomeSlide6Body;

  /// One slide of the welcome carousel: what the share card carries.
  ///
  /// In en, this message translates to:
  /// **'Free to use'**
  String get welcomeSlide7Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'Start with sessions on us. After that, paste a free API key. Groq and Google both give one away, no card. It stays on this phone.'**
  String get welcomeSlide7Body;

  /// Advances the welcome carousel.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get welcomeNextAction;

  /// Leaves the welcome carousel for the practice offer.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get welcomeSkipAction;

  /// Requests notification permission from the welcome carousel.
  ///
  /// In en, this message translates to:
  /// **'Turn the reminder on'**
  String get welcomeEnableRemindersAction;

  /// Confirms the reminder was armed from onboarding.
  ///
  /// In en, this message translates to:
  /// **'On — you will get one each morning.'**
  String get welcomeRemindersOnNotice;

  /// Shown when the permission request is refused during onboarding.
  ///
  /// In en, this message translates to:
  /// **'Android has notifications blocked for this app. Turn them on later in Settings → Reminder.'**
  String get welcomeRemindersBlockedNotice;

  /// Starts the scripted walkthrough.
  ///
  /// In en, this message translates to:
  /// **'Try a practice problem'**
  String get welcomeTryAction;

  /// Leaves onboarding without the walkthrough.
  ///
  /// In en, this message translates to:
  /// **'Skip to today’s problem'**
  String get welcomeSkipPracticeAction;

  /// The scripted practice walkthrough: screen title.
  ///
  /// In en, this message translates to:
  /// **'Practice run'**
  String get practiceTitle;

  /// Leaves the scripted practice walkthrough for today's real problem. Always available — the walkthrough is an offer, not a gate.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get practiceSkipAction;

  /// The scripted practice walkthrough: the throwaway warm-up problem.
  ///
  /// In en, this message translates to:
  /// **'Largest in the list'**
  String get practiceProblemTitle;

  /// The scripted practice walkthrough: statement. Deliberately trivial and not from the real catalogue.
  ///
  /// In en, this message translates to:
  /// **'You are given a list of numbers. Find the largest one and return it.'**
  String get practiceProblemStatement;

  /// The scripted practice walkthrough: why this walkthrough has no microphone.
  ///
  /// In en, this message translates to:
  /// **'Nothing here is graded, and no turn is spent.'**
  String get practiceTypedNotice;

  /// The scripted practice walkthrough: the tutor’s opening question.
  ///
  /// In en, this message translates to:
  /// **'A warm-up, so you can see how this goes. How would you find the largest number in that list? Say it however it comes out, half-formed is fine.'**
  String get practiceTutorOpener;

  /// The scripted practice walkthrough: the tutor’s reply to the first turn.
  ///
  /// In en, this message translates to:
  /// **'Okay. Now the question you\'ll get asked a lot here: how much work does that do as the list gets longer?'**
  String get practiceTutorReply1;

  /// The scripted practice walkthrough: the tutor’s reply to the second turn.
  ///
  /// In en, this message translates to:
  /// **'That\'s the loop: you talk, it asks, you sharpen. Nothing here was graded, and no turn was spent.'**
  String get practiceTutorReply2;

  /// The scripted practice walkthrough: the one canned hint, so the affordance is learned before it matters.
  ///
  /// In en, this message translates to:
  /// **'You don\'t need to sort anything. You only ever need the best one so far.'**
  String get practiceHintText;

  /// The scripted practice walkthrough: closing heading.
  ///
  /// In en, this message translates to:
  /// **'That is the whole app'**
  String get practiceDoneTitle;

  /// The scripted practice walkthrough: closing body.
  ///
  /// In en, this message translates to:
  /// **'Today\'s real problem is waiting. Talk it through and finish when you\'re ready.'**
  String get practiceDoneBody;

  /// The scripted practice walkthrough: leaves onboarding for the daily loop.
  ///
  /// In en, this message translates to:
  /// **'Start today’s problem'**
  String get practiceStartTodayAction;

  /// First line of the shared text — the reason a friend would care, before any of the facts.
  ///
  /// In en, this message translates to:
  /// **'Still thinking for myself in the age of AI.'**
  String get shareCardOpener;

  /// Label above the streak count on the share card.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get shareCardStreakLabel;

  /// The app-bar action that ends the session — labelled, not an icon, because a learner has to recognise it without tapping it.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finishActionLabel;

  /// One-time nudge in the conversation once the learner has been talking a while, so ending the session is not something they have to guess at.
  ///
  /// In en, this message translates to:
  /// **'Said what you wanted? Tap Finish for your assessment. The tutor will keep asking otherwise.'**
  String get finishNudgeBody;

  /// One slide of the welcome carousel: the share card.
  ///
  /// In en, this message translates to:
  /// **'Then show it off'**
  String get welcomeSlide8Title;

  /// One slide of the welcome carousel: body.
  ///
  /// In en, this message translates to:
  /// **'A card with the problem, how it went, and your streak. What you actually said stays on this phone.'**
  String get welcomeSlide8Body;

  /// The practice walkthrough: how to answer.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic and talk, or type instead.'**
  String get practiceMicHint;

  /// The practice walkthrough: shown when the recogniser is unavailable.
  ///
  /// In en, this message translates to:
  /// **'This phone will not do speech right now, so type your answer instead.'**
  String get practiceRecognitionUnavailableNotice;

  /// Closing line of the shared text: the reason for the person receiving it to open the app.
  ///
  /// In en, this message translates to:
  /// **'Think you can explain it? Try today’s problem.'**
  String get shareCardInvite;

  /// Popup raised once, after the first daily verdict, when notifications are off.
  ///
  /// In en, this message translates to:
  /// **'Make it a daily habit'**
  String get notificationNudgeTitle;

  /// Why the popup asks: the daily reminder cannot reach a phone with notifications blocked.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications and we\'ll remind you of each day\'s problem at a time you pick.'**
  String get notificationNudgeBody;

  /// Asks for the permission, opens Android's notification settings if it was already refused, then shows the reminder screen to pick a time.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get notificationNudgeAction;

  /// Closes the popup. It is not shown again.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notificationNudgeDismiss;

  /// Long-press menu item on a chat message. Copies its text.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get messageCopyAction;

  /// Snackbar after a message is copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get messageCopiedNotice;

  /// Settings row that opens the Plan screen (Pro Plus, feature 009).
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get settingsPlanLabel;

  /// Plan screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planTitle;

  /// Plan screen: the learner is on the free taster.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get planFreeName;

  /// Plan screen: the learner has an active Pro Plus subscription.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus'**
  String get planProName;

  /// Plan screen: the learner is using their own provider key, which takes precedence over any plan.
  ///
  /// In en, this message translates to:
  /// **'Your own key'**
  String get planOwnKey;

  /// Shown under 'Your own key' only while Pro Plus is on offer (FR-013).
  ///
  /// In en, this message translates to:
  /// **'Your own key is in use. Pro Plus is an alternative if you\'d rather not use a key.'**
  String get planOwnKeyProNote;

  /// Plan screen heading above the sessions and voice usage lines.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get planUsageHeading;

  /// Pro sessions used today (UTC) out of the daily allowance.
  ///
  /// In en, this message translates to:
  /// **'Sessions today: {used} of {limit}'**
  String planSessionsUsage(int used, int limit);

  /// Free-taster sessions used out of the lifetime allowance.
  ///
  /// In en, this message translates to:
  /// **'Free sessions used: {used} of {limit}'**
  String planSessionsUsageLifetime(int used, int limit);

  /// Cloud voice minutes used today out of the allowance, rounded up.
  ///
  /// In en, this message translates to:
  /// **'Voice today: {used} of {limit} min'**
  String planVoiceUsage(int used, int limit);

  /// Pro Plus is active; the date PayPal will bill next. The date is preformatted.
  ///
  /// In en, this message translates to:
  /// **'Renews on {date}'**
  String planRenews(String date);

  /// Pro Plus was cancelled in PayPal but is paid up until this preformatted date.
  ///
  /// In en, this message translates to:
  /// **'Ends on {date}'**
  String planEnds(String date);

  /// Shown when the subscription is suspended, expired, ended, or a payment failed.
  ///
  /// In en, this message translates to:
  /// **'Your Pro Plus subscription is not active.'**
  String get planEndedNotice;

  /// Pro limit line: the day's Pro session allowance is spent.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Pro sessions are used. They come back tomorrow (UTC).'**
  String get planProSessionsUsed;

  /// Pro limit line: the operator's Pro allowance is full; this is not the learner's doing.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus is at capacity for now. Try again later, or add your own key.'**
  String get planProCapacity;

  /// Heading of the Pro Plus offer card.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus'**
  String get planOfferTitle;

  /// What Pro Plus adds, from the relay's own levers.
  ///
  /// In en, this message translates to:
  /// **'{sessions} sessions a day and {minutes} minutes of voice a day, with no key needed.'**
  String planOfferLimits(int sessions, int minutes);

  /// Says plainly that subscribing here is a sandbox payment (FR-002).
  ///
  /// In en, this message translates to:
  /// **'Billed through PayPal. This build uses PayPal\'s test environment, so no real money is charged.'**
  String get planOfferPayPal;

  /// Primary button on the offer card. Opens PayPal in the system browser.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get planSubscribe;

  /// Opens PayPal's own manage page in the system browser.
  ///
  /// In en, this message translates to:
  /// **'Manage or cancel in PayPal'**
  String get planManage;

  /// Shown when the plan came from the cache; the date is the relay's time, preformatted.
  ///
  /// In en, this message translates to:
  /// **'Last checked {date}'**
  String planLastChecked(String date);

  /// Spinner caption while the checkout is created or the approval is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirming with PayPal…'**
  String get planConfirming;

  /// Shown while PayPal is open in the browser.
  ///
  /// In en, this message translates to:
  /// **'Finish in PayPal, then come back here.'**
  String get planAwaitingReturn;

  /// Notice after the subscription is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus is active.'**
  String get planActivated;

  /// Notice when the learner backed out of PayPal. Not an error.
  ///
  /// In en, this message translates to:
  /// **'Subscription not completed.'**
  String get planNotCompleted;

  /// Notice when the checkout could not be started.
  ///
  /// In en, this message translates to:
  /// **'PayPal is unavailable. Try again later.'**
  String get planPayPalUnavailable;

  /// Notice when the relay says the device is already subscribed.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus is already active on this device.'**
  String get planAlreadyActive;

  /// Plan screen when the first load failed and nothing is cached.
  ///
  /// In en, this message translates to:
  /// **'The plan can\'t be loaded right now.'**
  String get planUnavailable;

  /// Retry button under planUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get planRetry;

  /// Small chip shown on Settings and the Plan screen while Pro Plus is active. Never on the conversation screen.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get proBadgeLabel;

  /// Key prompt heading for a Pro device whose day's sessions are spent.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Pro sessions are used'**
  String get keyPromptProSessionsTitle;

  /// Key prompt body: names the reset and offers the key as the way to continue today.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Pro sessions are used. They come back tomorrow (UTC). Add your own key to keep going now.'**
  String get keyPromptProSessionsBody;

  /// Key prompt heading for a Pro device when the operator's Pro allowance is full.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus is at capacity'**
  String get keyPromptProCapacityTitle;

  /// Key prompt body: capacity, not anything the learner spent.
  ///
  /// In en, this message translates to:
  /// **'Pro Plus is at capacity for now. Add your own key to keep going.'**
  String get keyPromptProCapacityBody;

  /// Third button on a key prompt when Pro Plus is on offer. Opens the Plan screen.
  ///
  /// In en, this message translates to:
  /// **'Get Pro Plus'**
  String get keyPromptProAction;

  /// Prompt shown when a free learner taps Practice again or the problem picker and replay is off (FR-027).
  ///
  /// In en, this message translates to:
  /// **'Practice again is part of Pro Plus'**
  String get keyPromptReplayLockedTitle;

  /// Explains the free tier on the PayPal deployment before anything is spent.
  ///
  /// In en, this message translates to:
  /// **'Free practice is today\'s problem, once. Pro Plus adds Practice again and the other problems. Your own key unlocks them too.'**
  String get keyPromptReplayLockedBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

import '../screens/levelup_focus_setup_screen.dart'
    show FocusCapabilities, FocusMode, FocusSetupDraft;

/// UI-side validation of a draft. A draft can be edited before selecting an app;
/// enabling Focus still requires the engine-side capability/permission checks.
abstract final class FocusRulesPolicy {
  static const sessionChoices = <int>[15, 30, 60, 120];
  static const accessChoices = <int>[3, 5, 10, 15];

  static bool validSchedule(FocusSetupDraft draft) =>
      draft.weekdays.isNotEmpty &&
      draft.weekdays.every((day) => day >= 1 && day <= 7) &&
      draft.startMinute >= 0 &&
      draft.endMinute < 1440 &&
      draft.startMinute < draft.endMinute;

  static bool validRules(FocusSetupDraft draft) =>
      accessChoices.contains(draft.unlockMinutes) &&
      (draft.mode != FocusMode.timedSession ||
          sessionChoices.contains(draft.sessionMinutes)) &&
      (draft.mode != FocusMode.customSchedule || validSchedule(draft));

  /// Saving an editor draft is NOT activation. This deliberately checks only
  /// rule validity, because application selection may be performed later.
  static bool canSaveDraft(FocusSetupDraft draft) => validRules(draft);

  /// Only a valid, single-target supported draft is eligible for a *separate*
  /// native enable operation. This must never be used as native state itself.
  static bool eligibleForActivation(
    FocusSetupDraft draft,
    FocusCapabilities capabilities,
  ) => capabilities.supports(draft);

  static bool unsupportedMode(
    FocusSetupDraft draft,
    FocusCapabilities capabilities,
  ) => switch (draft.mode) {
    FocusMode.alwaysOn => false,
    FocusMode.timedSession => !capabilities.timedSession,
    FocusMode.customSchedule => !capabilities.customSchedule,
  };

  static bool unsupportedAccess(
    FocusSetupDraft draft,
    FocusCapabilities capabilities,
  ) => !capabilities.configurableAccess && draft.unlockMinutes != 5;

  static String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

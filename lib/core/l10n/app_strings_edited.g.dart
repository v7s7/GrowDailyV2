// GENERATED FILE. Do not edit by hand.
//
// Rebuilt from app_strings.dart by
//   cd docs/wording/generator && dart run bin/gen_wording_edits.dart
// Rerun it whenever a string in S is added, removed or renamed, or a
// method's parameters change. This file overrides every editable string
// by name, so until it is rerun the build stops here with an "isn't a
// valid override" or "isn't defined" error on the stale line.
//
// What it does: lays the admin's wording edits (see wording_edits.dart)
// over the built-in text. An editable string returns its edit when there
// is one and the built-in text otherwise. The {parts} of an edit are
// filled with the very values the built-in sentence uses, and an edit
// naming a part the string no longer has falls back to the built-in
// text (see wordingPartsKnown in wording_edits.dart).

part of 'app_strings.dart';

/// Every S string the admin tool can edit, in the order app_strings.dart
/// declares them.
const List<String> kEditableWordingKeys = [
  'appTitle',
  'tagline',
  'signIn',
  'createAccount',
  'signInAction',
  'createAccountAction',
  'email',
  'password',
  'confirmPassword',
  'continueWithGoogle',
  'continueWithApple',
  'authOrDivider',
  'continueWithEmail',
  'authOtherWays',
  'authAccountLead',
  'authAccountFact',
  'authGuestLead',
  'authGuestFact',
  'tryAsGuest',
  'guestDescription',
  'guestLimitTitle',
  'guestLimitBody',
  'guestFreshStartWarning',
  'reconnectTitle',
  'reconnectFound',
  'reconnectNotYours',
  'reconnectKeep',
  'reconnectFresh',
  'reconnectWorking',
  'reconnectDone',
  'reconnectPartial',
  'reconnectGrace',
  'reconnectBannerTitle',
  'reconnectBannerBody',
  'reconnectBannerDismiss',
  'guestLimitCta',
  'guestLimitMaybeLater',
  'guestDataWarning',
  'authForgotPassword',
  'authResetSent',
  'errEnterEmailForReset',
  'setPasswordTitle',
  'setPasswordSubject',
  'setPasswordChecking',
  'setPasswordSave',
  'setPasswordHint',
  'setPasswordNote',
  'setPasswordDone',
  'resetLinkDeadTitle',
  'resetLinkDeadBody',
  'resetLinkDeadCta',
  'addPasswordTitle',
  'addPasswordBody',
  'addPasswordLater',
  'addPasswordDone',
  'addPasswordAlready',
  'signInMethodsTitle',
  'signInMethodsIntro',
  'signInMethodPassword',
  'signInMethodConnect',
  'signInMethodRemove',
  'signInMethodSetPassword',
  'signInMethodConnectHint',
  'signInMethodPasswordHint',
  'signInMethodPasswordHidden',
  'signInMethodOnlyWayIn',
  'signInMethodsFooter',
  'signInMethodRemoveTitle',
  'signInMethodRemoveBody',
  'signInMethodConnected',
  'signInMethodRemoved',
  'signInMethodInUse',
  'signInMethodRemoveStale',
  'errFillAll',
  'errPasswordsMismatch',
  'errPasswordTooShort',
  'errInvalidCredential',
  'errEmailInUse',
  'errInvalidEmail',
  'errWeakPassword',
  'errNetwork',
  'errAccountExistsWithEmail',
  'errSignInMethodUnavailable',
  'errAppleAccountRequired',
  'errTooManyRequests',
  'errGeneric',
  'todaysHabits',
  'addHabit',
  'signOut',
  'signOutConfirmTitle',
  'signOutConfirmBody',
  'signOutConfirmCancel',
  'deleteAccount',
  'deleteAccountWarningTitle',
  'deleteAccountWarningBody',
  'deleteAccountPasswordLabel',
  'deleteAccountVerifyGoogle',
  'deleteAccountVerifyApple',
  'deleteAccountConfirmCta',
  'deleteAccountWrongPassword',
  'deleteAccountSuccess',
  'level',
  'totalXp',
  'streak',
  'freeze',
  'gold',
  'active',
  'activeCount',
  'statsUnavailableTitle',
  'statsUnavailableBody',
  'statsUnavailableRetry',
  'habitsNotLoadedNotice',
  'todaysIntention',
  'pickTinyWin',
  'pickOneGoal',
  'streakFreezeProtected',
  'claimComeback',
  'welcomeBack',
  'welcomeBackNoName',
  'comebackNoErase',
  'comebackBonusLabel',
  'comebackEitherWay',
  'restoreStreakOffer',
  'restoreStreakCta',
  'freshStreakInstead',
  'keepGrowing',
  'streakMilestoneLabel',
  'milestoneUnbroken',
  'milestoneNextStop',
  'milestoneLastStop',
  'milestoneBonusXp',
  'achievementUnlocked',
  'bonusTag',
  'claimReward',
  'levelUpMsg',
  'profile',
  'achievements',
  'achievementsViewAll',
  'achievementsShowLess',
  'achievementsMedalsEarned',
  'achievementsNextUp',
  'achievementsRemaining',
  'achievementsAllDone',
  'achievementsMastered',
  'achievementsEarned',
  'achievementsTapTierHint',
  'profileSection',
  'achievementsRowTitle',
  'progressStreakTitle',
  'progressTitle',
  'dashboardViewFullInsights',
  'dashboardViewFullJournal',
  'profileDashboardSection',
  'settings',
  'settingsScreenTitle',
  'darkMode',
  'appearance',
  'appearanceSheetTitle',
  'appearancePremiumHint',
  'appFont',
  'appFontSheetTitle',
  'preview',
  'themePreviewApply',
  'themePreviewUnlock',
  'themeSectionFree',
  'themeSectionPremium',
  'themeCustomPitch',
  'themeCustomReadyMade',
  'themeCustomName',
  'themeCustomTitle',
  'themeCustomHint',
  'themeCustomAccent',
  'themeCustomAccentHint',
  'themeCustomGrid',
  'themeCustomGridHint',
  'themeCustomDone',
  'themeCustomTabPalette',
  'themeCustomTabPicker',
  'themeCustomSaved',
  'themeCustomSavedEmpty',
  'themeCustomSavedTapHint',
  'themeCustomSaveTooltip',
  'themeCustomSavedFull',
  'themeCustomPreview',
  'themeCustomPreviewHabit',
  'themeCustomPreviewAction',
  'previewingTheme',
  'language',
  'languageAr',
  'languageEn',
  'cumulativeXp',
  'xpToLevel',
  'xpProgress',
  'best',
  'total',
  'statInfoStreakTitle',
  'statInfoStreakDesc',
  'statInfoBestTitle',
  'statInfoBestDesc',
  'statInfoTotalTitle',
  'statInfoTotalDesc',
  'statInfoGoldTitle',
  'statInfoGoldDesc',
  'statInfoXpTitle',
  'statInfoXpDesc',
  'progressDayByDay',
  'holdingStrong',
  'startAgain',
  'noProgressYet',
  'loadingReport',
  'activeDays',
  'bestDay',
  'progressStatRate',
  'progressToday',
  'progressYesterday',
  'progressDayBreakdown',
  'progressChartLegend',
  'progressDayScore',
  'progressScoreFraction',
  'progressNothingDueShort',
  'progressRestedShort',
  'progressDayRested',
  'progressDayNothingDue',
  'streakFreeze',
  'streakFreezeStatus',
  'freezeSlotTitle',
  'freezeSlotBody',
  'freezeSlotLocked',
  'hubTitle',
  'hubTitleQuit',
  'plansTab',
  'choosePlan',
  'choosePlanSubtitle',
  'startPlan',
  'deactivatePlan',
  'planPickHabitsHint',
  'addRemainingPlanHabits',
  'browsePlans',
  'dailyReminder',
  'dailyReminderPromptTitle',
  'dailyReminderPromptBody',
  'dailyReminderPromptAfterIsha',
  'dailyReminderPromptOtherTime',
  'dailyReminderPromptLater',
  'dailyReminderPromptNever',
  'dailyReminderPromptSettingsHint',
  'dailyReminderPromptLastAsk',
  'dailyReminderPromptLastHint',
  'dailyReminderSetToast',
  'tapToSetReminder',
  'reminderPermissionDenied',
  'noHabitsYet',
  'noHabitsDesc',
  'allDoneTitle',
  'allDoneSubtitle',
  'removeHabit',
  'editHabitAction',
  'newHabit',
  'editHabit',
  'saveChanges',
  'habitNameHint',
  'afterWhatRoutine',
  'routineHint',
  'cueAfterOption',
  'cueBeforeOption',
  'pickATime',
  'category',
  'frequency',
  'daily',
  'weekly',
  'times',
  'createHabit',
  'smartStarters',
  'addGoalTitle',
  'whatImprove',
  'whatHabitBuild',
  'whatReduce',
  'goalTitleHint',
  'smartSuggestions',
  'quickestStart',
  'goalTypeBuildOption',
  'goalTypeQuitOption',
  'categoryPickHint',
  'limitAmountRequired',
  'quitLimitRule',
  'readyPlansLink',
  'timingBuildTitle',
  'timingQuitTitle',
  'whenQuestion',
  'customTime',
  'customText',
  'cuePrayerOption',
  'pickAPrayer',
  'remindMeSection',
  'reminderStyleSection',
  'reminderStyleNotification',
  'reminderStyleAlarm',
  'reminderStyleAlarmHint',
  'alarmPermissionDenied',
  'alarmNeedsNewerIos',
  'leadAtTime',
  'leadCustomOption',
  'leadCustomMinutesHint',
  'offsetBeforeMinutes',
  'offsetAfterMinutes',
  'offsetBeforeLabel',
  'offsetAfterLabel',
  'quietHoursConflictWarning',
  'quietHoursOverrideOn',
  'quietHoursAllowAnywayAction',
  'quietHoursRespectAction',
  'remindAtTimePreview',
  'remindPreviewNeedsLocation',
  'timingToggle',
  'timingToggleQuit',
  'repeat',
  'repeatPickOne',
  'goalStyle',
  'customizeTiming',
  'avoidCompletely',
  'setLimit',
  'maxAmount',
  'customUnitPrompt',
  'customUnitHint',
  'customTriggerOptional',
  'threeTimesWeek',
  'specificDays',
  'timesPerWeek',
  'createGoal',
  'continueAction',
  'back',
  'tinyHintDefault',
  'tinyHintQuran',
  'tinyHintAthkar',
  'tinyHintFitness',
  'tinyHintSleep',
  'focus',
  'focusTitle',
  'focusDailyTitle',
  'focusTagline',
  'focusRitualProgress',
  'focusMostImportantTask',
  'focusMitSubtitle',
  'focusIfThenPlan',
  'focusTopTaskHint',
  'focusTopTaskLabel',
  'focusCuePrefix',
  'focusCueHint',
  'focusCueLabel',
  'focusActionPrefix',
  'focusActionHint',
  'focusActionLabel',
  'focusSavePlan',
  'focusPlanSaved',
  'focusTimerTitle',
  'focusTimerSubtitle',
  'focusPauseSprint',
  'focusStartSprint',
  'focusResetTimer',
  'focusReady',
  'focusFocusing',
  'focusComplete',
  'focusMinutesLabel',
  'focusXpOnCompletion',
  'focusSessionCompleteTitle',
  'focusDeepWorkDone',
  'focusStayedFocused',
  'focusGreatWork',
  'focusRitualTitle',
  'focusRitualSubtitle',
  'focusRitualPlanWin',
  'focusRitualChooseTask',
  'focusRitualRunSprint',
  'focusRitualSprintsLogged',
  'focusRitualReview',
  'focusRitualReviewSubtitle',
  'focusLogSprint',
  'focusResetToday',
  'focusWhyTitle',
  'focusWhySubtitle',
  'focusIfThenCueTitle',
  'focusIfThenCueBody',
  'focusOneTaskTitle',
  'focusOneTaskBody',
  'focusSprintTitle',
  'focusSprintBody',
  'habitDaily',
  'habitWeeklyTimes',
  'goals',
  'goalsMatrix',
  'matrixSubtitle',
  'matrixUrgent',
  'matrixNotUrgent',
  'matrixImportant',
  'matrixNotImportant',
  'matrixToday',
  'matrixFav',
  'matrixCarriedOverCount',
  'matrixUpcomingCount',
  'matrixAll',
  'matrixTapToAdd',
  'matrixAddAnother',
  'matrixAddTask',
  'matrixWhatToDo',
  'matrixMoveToQuadrant',
  'taskMoveAction',
  'taskFavAction',
  'taskUnfavAction',
  'taskDetailsAction',
  'matrixExpandQuadrant',
  'matrixCollapseQuadrant',
  'matrixDeleteTask',
  'matrixDeleteSelected',
  'matrixSelectedCount',
  'matrixCompletedTitle',
  'matrixNoCompletedTasks',
  'matrixNoCompletedTasksDesc',
  'matrixRestoreTask',
  'matrixAddMultipleHint',
  'matrixAddDetails',
  'matrixHideDetails',
  'matrixDescriptionHint',
  'matrixTaskDetails',
  'matrixNoDescription',
  'matrixReminderLabel',
  'matrixReminderPast',
  'matrixReminderTimeTitle',
  'matrixReminderEarliest',
  'matrixReminderAddAnother',
  'matrixReminderRemove',
  'matrixReminderOffsetPast',
  'matrixExtraRemindersSection',
  'matrixExtraRemindersHint',
  'customReminderTitle',
  'customReminderValueHint',
  'habitDuplicateTime',
  'habitOffsetFromTime',
  'habitOffsetTooLarge',
  'customReminderAdd',
  'habitOffsetSave',
  'habitReminderAtPrayer',
  'habitReminderBeforePrayer',
  'habitReminderAfterPrayer',
  'habitReminderRowSemantics',
  'habitReminderRemove',
  'customReminderAlreadyAdded',
  'unitMinutes',
  'unitHours',
  'unitDays',
  'matrixReminderMaxReached',
  'reminderGateTitle',
  'reminderGateBody',
  'reminderGateHabitBody',
  'habitAddAnotherReminder',
  'habitAddReminderRow',
  'habitReminderMaxReached',
  'habitReminderKeepOne',
  'matrixDone',
  'matrixUndo',
  'undo',
  'matrixTaskDeleted',
  'matrixPickADay',
  'matrixNoTasksThisDay',
  'matrixEditQuadrantTitle',
  'matrixEditQuadrantBody',
  'matrixEditQuadrantSave',
  'matrixEditQuadrantCancel',
  'matrixQuadrantColorTitle',
  'matrixQuadrantColorHint',
  'closetProfileRow',
  'closetCustomize',
  'closetTitle',
  'closetSubtitle',
  'closetCharacterSection',
  'closetOwned',
  'closetEquipped',
  'closetEquip',
  'closetUnequip',
  'closetBuy',
  'closetBuyConfirmTitle',
  'closetBuyConfirmBody',
  'closetNotEnoughGold',
  'closetPurchaseFailed',
  'closetPurchased',
  'closetCancel',
  'closetBandOwned',
  'closetBandReach',
  'closetBandGoal',
  'closetCharacterEarned',
  'closetCharacterLocked',
  'closetMen',
  'closetWomen',
  'closetNoAccessory',
  'closetUnlockedByProgress',
  'closetShortBy',
  'closetBalanceIs',
  'closetBalanceAfter',
  'closetBalanceOf',
  'closetProgress',
  'closetPriceLater',
  'closetSeenByRooms',
  'rewardsTitle',
  'rewardsCardTitle',
  'rewardsCardEmpty',
  'rewardsCardClosest',
  'rewardsEmptyTitle',
  'rewardsEmptyBody',
  'rewardsStarterTitle',
  'rewardsWriteMyOwn',
  'rewardsAdd',
  'rewardsEditTitle',
  'rewardsSheetBody',
  'rewardsNameHint',
  'rewardsPriceLabel',
  'rewardsPriceInvalid',
  'rewardsSave',
  'rewardsCancel',
  'rewardsDelete',
  'rewardsLimitReached',
  'rewardsListUnavailable',
  'rewardsBalanceUnavailable',
  'rewardsClaimTitle',
  'rewardsClaimBody',
  'rewardsClaimConfirm',
  'rewardsFailed',
  'rewardsClaimedEyebrow',
  'rewardsPaid',
  'rewardsBalanceNow',
  'rewardsEarnedIt',
  'rewardsGoEnjoy',
  'rewardsSemantic',
  'rewardsDeleteTitle',
  'rewardsDeleteBody',
  'rewardsDeleteConfirm',
  'rewardsDeleted',
  'profileEditNameTitle',
  'profileEditNameBody',
  'profileEditNameHint',
  'profileEditNameSave',
  'profileEditNameCancel',
  'profileEditNameError',
  'navToday',
  'navGrid',
  'navMatrix',
  'navProfile',
  'navRooms',
  'navProgress',
  'navSettings',
  'navTasbih',
  'navRewards',
  'navCloset',
  'navNightReview',
  'navYearRecord',
  'navHeatmap',
  'navBarSettingsTitle',
  'navBarSettingsIntro',
  'navBarYourTabs',
  'navBarAddTabs',
  'navBarFull',
  'navBarPinned',
  'navBarRemove',
  'navBarAdd',
  'navBarReset',
  'navBarLockedTitle',
  'navBarLockedBody',
  'navBarLockedCta',
  'navBarHintTitle',
  'navBarHintBody',
  'navBadgesTitle',
  'navBadgesDesc',
  'navBadgeReviewPending',
  'appIconTitle',
  'appIconNow',
  'appIconPreviewing',
  'appIconShapeSection',
  'appIconColourSection',
  'appIconMoreColours',
  'appIconFollowTitle',
  'appIconFollowBody',
  'appIconUse',
  'appIconInUse',
  'appIconFailed',
  'appIconShapeSeedling',
  'appIconShapeSprout',
  'appIconShapeGrown',
  'appIconShapeBloom',
  'appIconShapeGrownInSentence',
  'appIconShapeBloomInSentence',
  'appIconColourOriginal',
  'appIconColourRed',
  'appIconColourYellow',
  'appIconColourGreen',
  'appIconColourBrown',
  'appIconColourGrey',
  'appIconFullDaysLeft',
  'appIconNextShape',
  'appIconAllShapes',
  'appIconFullDayRule',
  'appIconSeasonSection',
  'appIconRamadan',
  'appIconRamadanLocked',
  'appIconRamadanOpen',
  'appIconRamadanSoon',
  'appIconRamadanNote',
  'appIconOfferTitle',
  'appIconOfferBody',
  'appIconOfferBodyOriginal',
  'appIconOfferBodyCustom',
  'appIconOfferAlways',
  'appIconOfferYes',
  'appIconOfferNo',
  'plantGrewTitle',
  'plantBloomedTitle',
  'plantGrewBody',
  'plantGrewUse',
  'plantGrewLater',
  'ramadanCardTitle',
  'ramadanCardBody',
  'getStartedTitle',
  'guideStepCount',
  'getStartedAddHabit',
  'getStartedAddTask',
  'coachMarkSkip',
  'guideNeedsHabitFirst',
  'guideHiddenUndoHint',
  'squareNotReadyYet',
  'firstRunOfferTitle',
  'firstRunOfferBodyLead',
  'firstRunOfferBodyEmphasis',
  'firstRunOfferYes',
  'firstRunOfferLater',
  'rankUpEyebrow',
  'rankUpLadderPosition',
  'rankUpMarkGrew',
  'rankUpNextAtLevel',
  'rankUpSummitLine',
  'rankUpSemantic',
  'gridTitle',
  'gridSlogan',
  'gridThisWeek',
  'gridGreenSquares',
  'gridPoints',
  'gridComplete',
  'gridWeekFilled',
  'gridPerfectDay',
  'gridGreensToday',
  'gridOfHabitsToday',
  'gridGreenSquaresThisWeek',
  'gridTapHint',
  'tasbihTitle',
  'tasbihTapHint',
  'tasbihCustom',
  'tasbihCustomTitle',
  'tasbihCustomCancel',
  'tasbihCustomSet',
  'tasbihReset',
  'tasbihResetDone',
  'tasbihMarkHabit',
  'tasbihMarked',
  'gridRewardHint',
  'gridPastDayHint',
  'gridRestorableDayHint',
  'gridMarkRestored',
  'gridClearMarkTitle',
  'gridClearMarkBody',
  'gridClearPastMarkTitle',
  'gridClearPastMarkBody',
  'gridClearMarkBodyNoReward',
  'gridClearMarkConfirm',
  'gridMarkCleared',
  'gridNotYetActiveHint',
  'gridEmptyTitle',
  'gridEmptyDesc',
  'gridEditSquare',
  'gridNoteLabel',
  'gridNoteLocked',
  'gridNoteHint',
  'gridSave',
  'gridFutureDay',
  'gridSquareDoneFromToday',
  'gridSquareKeptToday',
  'gridSquarePartlyDoneFromToday',
  'gridJournalTitle',
  'gridJournalEmpty',
  'gridJournalSearchHint',
  'gridJournalNoResults',
  'gridJournalFilterAll',
  'gridJournalDeletedHabit',
  'heatmapTitle',
  'heatmapSubtitle',
  'heatmapTotalGreen',
  'heatmapActiveDays',
  'heatmapBestDay',
  'heatmapWeakestDay',
  'heatmapLess',
  'heatmapMore',
  'gridSectionBuild',
  'gridSectionQuit',
  'gridFullRow',
  'perfectDayMsg',
  'weeklyRecapTitle',
  'weeklyNoteOfferAsk',
  'weeklyNoteOfferYes',
  'weeklyNoteOfferNo',
  'weeklyRecapThisWeek',
  'weeklyRecapLastWeek',
  'weeklyRecapNeedsLove',
  'weeklyRecapUp',
  'weeklyRecapSame',
  'weeklyRecapDown',
  'weeklyRecapFirst',
  'weeklyRecapPerHabit',
  'weeklyRecapTrend',
  'weeklyRecapPremiumTeaser',
  'insightsTitle',
  'insightsWindow',
  'insightsPerHabitTitle',
  'insightWeekdayMiss',
  'insightStrongestDay',
  'insightMostConsistent',
  'insightNeedsPush',
  'insightsEmpty',
  'insightsPremiumTitle',
  'insightsPremiumBody',
  'insightsBreakdownTeaser',
  'insightDetailByDay',
  'insightDetailOwnDays',
  'insightDetailByWeek',
  'insightCountOf',
  'insightQuotaWeeks',
  'insightQuotaAverage',
  'insightTipQuotaWeeks',
  'insightDetailCompare',
  'insightTipMostConsistent',
  'insightTipNeedsPush',
  'insightTipWeekdayMiss',
  'insightTipStrongestDay',
  'insightWindowWithDates',
  'insightPerfectRecord',
  'insightMostConsistentCompare',
  'insightNeedsPushCompare',
  'insightOnlyHabitTracked',
  'historyLockedCta',
  'roomLobbyPill',
  'roomStartsTomorrowPill',
  'roomLobbyBanner',
  'roomLobbyLeaderHint',
  'roomPickStartTimeAction',
  'roomWaitingForLeaderSchedule',
  'roomScheduleTitle',
  'roomScheduleBody',
  'roomScheduleQuick1Hour',
  'roomScheduleTomorrowMorning',
  'roomScheduleTomorrowEvening',
  'roomScheduleCustomAction',
  'roomScheduleNotFuture',
  'roomCountdownTitle',
  'roomCountdownAt',
  'roomCountdownDaysLabel',
  'roomCountdownHoursLabel',
  'roomCountdownMinLabel',
  'roomCountdownSecLabel',
  'roomChangeTimeAction',
  'roomStartNowAction',
  'roomStartsInCompact',
  'roomStartAction',
  'roomStartConfirmTitle',
  'roomStartConfirmBody',
  'roomStartsTomorrowBanner',
  'roomEndedTitle',
  'roomEndedBody',
  'roomPlaceFirst',
  'roomPlaceFirstTied',
  'roomPlaceTied',
  'roomPlaceNone',
  'notifLocationResolving',
  'notifLocationSetGeneric',
  'roomBoostHint',
  'historyLockedBody',
  'demoGateExample',
  'demoGateMonthTitle',
  'demoGatePerfectStamp',
  'demoGateCta',
  'demoGateNotNow',
  'heatmapDayEmpty',
  'heatmapUpgradeTitle',
  'heatmapUpgradeBody',
  'nightReviewTitle',
  'nightReviewHistoryTitle',
  'nightReviewHistoryEmpty',
  'nightReviewPromptTitle',
  'nightReviewPromptDesc',
  'nightReviewMoodQuestion',
  'nightReviewReflectionLabel',
  'nightReviewReflectionHint',
  'nightReviewSummaryTitle',
  'nightReviewXpEarned',
  'nightReviewHabitsDoneLabel',
  'nightReviewTasksDoneLabel',
  'nightReviewGreenSquares',
  'nightReviewStreak',
  'nightReviewSave',
  'nightReviewSaved',
  'nightReviewDoneBadge',
  'nightReviewEditedHint',
  'premiumTitle',
  'premiumHeadline',
  'premiumSubhead',
  'premiumBenefitHabitsTitle',
  'premiumBenefitHabitsDesc',
  'premiumBenefitHistoryTitle',
  'premiumBenefitHistoryDesc',
  'premiumBenefitInsightsTitle',
  'premiumBenefitInsightsDesc',
  'premiumBenefitAppearanceTitle',
  'premiumBenefitAppearanceDesc',
  'premiumBenefitTaskRemindersTitle',
  'premiumBenefitTaskRemindersDesc',
  'premiumBenefitVoiceTitle',
  'premiumBenefitVoiceDesc',
  'premiumBenefitNavBarTitle',
  'premiumBenefitNavBarDesc',
  'premiumBenefitFutureTitle',
  'premiumBenefitFutureDesc',
  'premiumMonthly',
  'premiumYearly',
  'premiumLifetime',
  'premiumPerMonth',
  'premiumPerYear',
  'premiumOneTime',
  'premiumSave',
  'premiumBestValueBadge',
  'premiumCta',
  'premiumWelcomeTitle',
  'premiumWelcomeEndsIn',
  'premiumSaleEndsIn',
  'premiumCountdownDays',
  'premiumCountdownHours',
  'premiumCountdownMinutes',
  'premiumCountdownSeconds',
  'premiumCountdownSpoken',
  'premiumThenPrice',
  'premiumRegularPriceSpoken',
  'premiumWelcomeFinePrint',
  'premiumSaleFinePrint',
  'premiumHaveCode',
  'premiumLifetimeOwned',
  'premiumLifetimeStillRenewing',
  'premiumUpgradeTitle',
  'premiumUpgradeCancelNote',
  'premiumUpgradeCta',
  'premiumPurchasePending',
  'premiumRestore',
  'premiumRetry',
  'premiumComingSoon',
  'premiumBuyOnIphone',
  'premiumActive',
  'premiumManageSubscription',
  'premiumPurchaseError',
  'premiumRestoreSuccess',
  'premiumRestoreNothingFound',
  'premiumFinePrintMonthly',
  'premiumFinePrintMonthlyPlay',
  'premiumFinePrintLifetime',
  'premiumPurchaseNotEntitled',
  'notifRoomPushReady',
  'notifRoomPushNoPermission',
  'notifRoomPushNoToken',
  'notifRoomPushCategoryOff',
  'notifOpenSystemSettings',
  'premiumTermsOfUse',
  'premiumPrivacyPolicy',
  'premiumLinkOpenError',
  'helpSupportRowTitle',
  'helpFaqSectionTitle',
  'helpContactSectionTitle',
  'helpContactEmailLabel',
  'helpContactWhatsAppLabel',
  'helpContactInstagramLabel',
  'helpGuidesSectionTitle',
  'habitLimitTitle',
  'habitLimitBody',
  'voiceNoteGateTitle',
  'voiceNoteGateBody',
  'voiceNoteRecording',
  'voiceNoteTapToRecord',
  'voiceNoteTapToStop',
  'voiceNoteMicPermissionDenied',
  'voiceNoteAttached',
  'voiceNotePlay',
  'voiceNotePause',
  'voiceNoteSkipBack',
  'voiceNoteSkipForward',
  'voiceNoteSpeedLabel',
  'voiceNotesTitle',
  'voiceNoteDefaultName',
  'voiceNoteRenameTitle',
  'voiceNoteRenameHint',
  'voiceNoteRenameSave',
  'voiceNoteClosePlayer',
  'streakAtRiskTitle',
  'streakAtRiskBody',
  'onboardingGridTitle',
  'onboardingGridBody',
  'onboardingHabitsTitle',
  'onboardingHabitsBody',
  'onboardingTasksTitle',
  'onboardingTasksBody',
  'onboardingRoomsTitle',
  'onboardingRoomsBody',
  'onboardingSkip',
  'onboardingNext',
  'onboardingGetStarted',
  'habitIconColor',
  'habitIconColorHint',
  'hexCode',
  'useDefaultColor',
  'colorPickerDone',
  'roomsTitle',
  'roomGenericError',
  'roomsEmptyTitle',
  'roomsEmptyBody',
  'roomCreateAction',
  'roomJoinAction',
  'roomGuestGateTitle',
  'roomGuestGateBody',
  'roomGuestGateAction',
  'roomStarTooltip',
  'roomUnstarTooltip',
  'roomCreateTitle',
  'roomNameLabel',
  'roomNameHint',
  'roomNameIdeas',
  'roomHabitModeLabel',
  'roomHabitModeShared',
  'roomHabitModeSharedHint',
  'roomHabitModeOwn',
  'roomHabitModeOwnHint',
  'roomYourHabitLabel',
  'roomCompeteModeLabel',
  'roomCompeteModeCompetitive',
  'roomCompeteModeCompetitiveHint',
  'roomCompeteModeTeam',
  'roomCompeteModeTeamHint',
  'roomOwnHabitsLabel',
  'roomOwnHabitsHint',
  'roomPlanHabitsLabel',
  'roomPlanHabitsHint',
  'roomDurationLabel',
  'roomDurationOpenEnded',
  'roomDurationCustomOption',
  'roomDurationCustomHint',
  'roomDurationCustomRange',
  'roomDurationCustomInvalid',
  'roomCreateSubmit',
  'roomDurationExtendHint',
  'roomCreateStepOne',
  'roomCreateStepTwo',
  'roomCreateStepHabitsTitle',
  'roomCreateNext',
  'roomCreateBack',
  'roomCreateNeedsName',
  'roomCreateNeedsHabit',
  'roomCreateNeedsDuration',
  'roomHabitModeOwnShort',
  'roomCreatedTitle',
  'roomShareCode',
  'roomCodeCopied',
  'roomCopyAction',
  'roomShareAction',
  'roomDoneAction',
  'roomCreatedPrivateNote',
  'roomCreatedNextTitle',
  'roomCreatedNextBody',
  'roomOpenAction',
  'roomJoinTitle',
  'roomCodeLabel',
  'roomCodeHint',
  'roomFindAction',
  'roomNotFound',
  'roomAlreadyEndedJoin',
  'roomAlreadyMemberJoin',
  'roomPreviewOwnMode',
  'roomPreviewSharedHabit',
  'roomPreviewSharedHabitsLabel',
  'roomPickHabitLabel',
  'roomPickHabitHint',
  'roomPickHabitsLabel',
  'roomNoHabitsYet',
  'roomPlanReviewLabel',
  'roomPlanAddAsNew',
  'roomPlanLinkExisting',
  'roomPlanTornHint',
  'roomRelinkTitle',
  'roomRelinkHint',
  'roomRelinkConfirm',
  'roomRelinkAction',
  'roomRelinkNone',
  'roomRelinkDone',
  'roomRelinkFailed',
  'roomJoinSubmit',
  'roomShowAllMembers',
  'roomLargeRoomMutedNote',
  'roomFinaleDialogBody',
  'roomFinaleShow',
  'roomFinaleDismiss',
  'roomClaimPrize',
  'roomPrizeClaimed',
  'roomOngoing',
  'roomEnded',
  'roomDaysLeft',
  'roomMarkedToday',
  'roomNotDoneToday',
  'roomPartialToday',
  'roomQuotaWeekProgress',
  'roomQuotaNeededToday',
  'roomStripStart',
  'roomStripDetails',
  'roomStripOpenCalendar',
  'roomCalendarTitle',
  'roomCalendarDone',
  'roomCalendarMissed',
  'roomCalendarPartial',
  'roomCalendarRestDay',
  'roomCalendarStoodDown',
  'roomCalendarPaused',
  'roomCalendarHabitPaused',
  'roomCalendarFirstDayNote',
  'roomCalendarFirstDayNoteOther',
  'roomCalendarTotalOf',
  'roomCalendarNothingAsked',
  'roomCalendarChipDone',
  'roomCalendarChipPartial',
  'roomCalendarChipMissed',
  'roomCalendarChipRest',
  'roomCalendarGroupPool',
  'roomCalendarSlotDeclined',
  'roomCalendarStillOpen',
  'roomCalendarTotal',
  'roomSheetClose',
  'roomStartedOn',
  'roomStartsOn',
  'notifSystemPermissionOff',
  'notifSystemPermissionOffAction',
  'roomRuleChangedWarning',
  'roomRuleChangedAction',
  'roomRuleChangedApplied',
  'roomSkipSharedHabit',
  'roomSkippedLabel',
  'roomSkippedHint',
  'roomCancel',
  'roomRemoveHabitAction',
  'roomRemoveHabitPickerTitle',
  'roomRemoveHabitPickerHint',
  'roomRemoveHabitConfirmTitle',
  'roomRemoveHabitConfirmBody',
  'roomRemoveHabitConfirmBodyNow',
  'roomRemoveHabitConfirmAction',
  'roomHabitRemovedSnack',
  'roomRemoveLastHabitTitle',
  'roomRemoveLastHabitBody',
  'roomRemoveHabitAlreadyRemoved',
  'roomPlanLockedEnded',
  'roomLastDayLabel',
  'roomHabitRestoredSnack',
  'roomPlanNoticeTitle',
  'roomPlanNoticeRemovedToday',
  'roomPlanNoticeRemoved',
  'roomPlanNoticeKeptHabit',
  'roomPlanNoticeDaysKept',
  'roomPlanNoticeRestored',
  'roomPlanNoticeOk',
  'roomPlanNoticeOpenRoom',
  'roomPlanPartialCreditHint',
  'roomTeamProgressTitle',
  'roomTeamProgressDays',
  'roomTeamAllDoneToday',
  'roomTeamBonusHint',
  'roomTeamBonusClaimAction',
  'roomTeamBonusClaimedLabel',
  'roomTeamDayTitle',
  'roomTeamDayWon',
  'roomTeamWaitingOn',
  'roomTeamWaitingCount',
  'roomTeamNobodyYet',
  'roomTeamNextMilestone',
  'roomTeamMilestoneReached',
  'roomTeamMilestoneClaimed',
  'roomTeamMilestonePrize',
  'roomTeamDaysToGo',
  'roomTeamAllMilestonesDone',
  'roomTeamClaimAction',
  'roomTodayFinished',
  'roomLastSevenDays',
  'roomRowsViewTitle',
  'roomRowsFull',
  'roomSoloTitle',
  'roomFaceDone',
  'roomFaceWaiting',
  'roomFaceExcused',
  'roomFacesMore',
  'roomFacesSheetHint',
  'roomFacesAll',
  'roomTeamRankingTitle',
  'roomTeamRankingShow',
  'roomTeamRankingHide',
  'roomTeamFinaleScore',
  'roomTeamFinaleCaption',
  'roomTeamFinaleBestStreak',
  'roomDetailsHidden',
  'roomDetailsVisible',
  'roomAddHabitAction',
  'roomAddHabitPickerTitle',
  'roomAddHabitPickerHint',
  'roomHabitAddedConfirmation',
  'roomHabitAlreadyInPlan',
  'roomAddAnotherHabitAction',
  'roomAddAnotherHabitPickerTitle',
  'roomAddAnotherHabitPickerHint',
  'roomMuteAction',
  'roomUnmuteAction',
  'roomMutedConfirmation',
  'roomUnmutedConfirmation',
  'roomNoMoreHabitsToAdd',
  'roomCreateNewHabitAction',
  'roomCreateNewHabitSharedNote',
  'roomPossibleDuplicateWarning',
  'roomNewHabitBannerTitle',
  'roomNewHabitBannerBody',
  'roomNewHabitBannerAction',
  'roomResolveHabitsSheetTitle',
  'roomLinkedHabitDeletedHint',
  'habitLinkedRoomWarningTitle',
  'habitDeleteAnywayAction',
  'habitDeleteLinkedRoomCancel',
  'roomSoleLinkedHabitPausedHint',
  'habitPauseAnywayAction',
  'habitEdit',
  'habitActionsCancel',
  'restDayTitle',
  'restDayOffPlan',
  'restDayCoveredBySession',
  'restDayQuotaMet',
  'restDayNotNeeded',
  'restDayCovers',
  'restDayExtra',
  'restDayQuotaCounts',
  'restDayNoPoints',
  'restDayWithPoints',
  'restDayConfirm',
  'habitPause',
  'habitPauseHint',
  'pauseUntilTitle',
  'pauseUntilSubtitle',
  'pauseUntilManual',
  'pauseUntilManualHint',
  'pauseUntilCustom',
  'pauseUntilCustomHint',
  'pauseUntilOn',
  'resumesOnBadge',
  'autoResumedConfirmation',
  'autoResumeBlockedByLimit',
  'habitResume',
  'habitResumeHint',
  'habitPausedConfirmation',
  'habitResumedConfirmation',
  'habitPausedSection',
  'roomPausedTag',
  'roomStoodDownToday',
  'habitPausedShowAll',
  'habitPausedShowLess',
  'gridSelectPrompt',
  'habitDeleteForever',
  'habitDeleteForeverBody',
  'habitDeleteForeverConfirm',
  'habitDeletedConfirmation',
  'habitActionsTitle',
  'habitSelectMultiple',
  'habitArchivedConfirmation',
  'roomStatDays',
  'roomOwnRate',
  'roomLeaveKeepsRecordBody',
  'roomYouLabel',
  'roomLeaderLabel',
  'roomLeaveAction',
  'roomLeaveConfirmTitle',
  'roomLeaveConfirmBody',
  'roomLeaveConfirmBodyLeader',
  'roomLeaveConfirmCancel',
  'roomDeleteAction',
  'roomDeleteConfirmTitle',
  'roomDeleteConfirmBody',
  'roomGoneMessage',
  'roomExtendAction',
  'roomExtendTitle',
  'roomCadenceWeekly',
  'roomCadenceDaily',
  'roomExtendBody',
  'roomExtended',
  'roomFinaleExtendAction',
  'roomFinaleExtendHint',
  'roomFinaleMemberHint',
  'notificationsTitle',
  'notifMasterTitle',
  'notifMasterDesc',
  'notifWhatSection',
  'notifHabitReminders',
  'notifHabitRemindersDesc',
  'notifStreakRisk',
  'notifStreakRiskDesc',
  'notifMatrixNudge',
  'notifMatrixNudgeDesc',
  'notifBundle',
  'notifBundleDesc',
  'notifWeeklyDigest',
  'notifWeeklyDigestDesc',
  'notifRoomActivity',
  'notifRoomActivityDesc',
  'notifLocationNotSet',
  'notifDetectingLocation',
  'notifLocationDetectFailed',
  'notifCalcMethod',
  'notifQuietHoursSection',
  'notifQuietHours',
  'notifQuietHoursDesc',
  'notifQuietStart',
  'notifQuietEnd',
  'notifQuietAppliesToPrayer',
  'notifQuietAppliesToPrayerDesc',
  'notifTimingSection',
  'notifSendTest',
  'notifTestSent',
  'prayerPlaceTitle',
  'prayerPlaceNotSet',
  'prayerPlaceNeeded',
  'prayerPlaceFromPhone',
  'prayerPlacePicked',
  'prayerPlaceUses',
  'prayerPlaceAuto',
  'prayerPlaceAutoBody',
  'prayerPlaceCity',
  'prayerPlaceCityBody',
  'prayerPlaceBahrainTable',
  'prayerLocationTitle',
  'prayerLocationPrivacyNote',
  'citySearchHint',
  'citySearchNoResults',
  'citySearchPrompt',
  'citySearchEnterManually',
  'citySearchBackToSearch',
  'locationLabelHint',
  'latitude',
  'longitude',
  'useTheseCoordinates',
  'journeyTitle',
  'journeyEmptyTitle',
  'journeyEmptyBody',
  'journeyMemberSince',
  'lifeTimelineTitle',
  'lifeTimelineSubtitle',
  'lifeTimelineSince',
  'lifeTimelineYearTotal',
  'lifeTimelineOpenHeatmap',
  'lifeTimelineUpgradeBody',
  'roomMemberActions',
  'roomReportAction',
  'roomBlockAction',
  'roomReportMemberMenu',
  'roomReportPickMember',
  'roomReportNobodyYet',
  'roomUnblockAction',
  'roomReportTitle',
  'roomReportSubtitle',
  'roomReportReasonName',
  'roomReportReasonHarassment',
  'roomReportReasonSpam',
  'roomReportReasonOther',
  'roomReportNoteHint',
  'roomReportSubmit',
  'roomReportThanks',
  'roomReportAlsoBlock',
  'roomBlockedConfirm',
  'roomUnblockedConfirm',
  'roomBlockExplain',
  'roomBlockedShow',
  'roomNameNotAllowed',
  'roomReactionJoined',
  'roomReactionFinished',
  'matrixRewardFloatXp',
  'matrixRewardFloatGold',
  'matrixAddedForLater',
  'monthlyStoryTitle',
  'monthlyStoryEmpty',
  'monthlyStoryHeadline',
  'monthlyStoryGreenSquares',
  'monthlyStoryShareAction',
  'monthlyStoryShareText',
  'yearRecordTitle',
  'yearRecordEmpty',
  'yearRecordDaysCount',
  'yearRecordCleanDaysCount',
  'yearRecordArchivedSection',
  'monthPickerTitle',
  'weekPickerTitle',
  'yearPickerTitle',
  'monthPickerLocked',
  'monthlyStoryLoadFailed',
  'prestigeTitle',
  'prestigeSubtitle',
  'prestigeAutoOption',
  'prestigeAutoOptionDesc',
  'prestigeUnlockedAt',
  'prestigeLockedUntil',
  'categoryBreakdownTitle',
  'reportsTitle',
  'reportsWeekly',
  'reportsMonthly',
  'reportsYearly',
  'recordTitle',
  'recordTabWeek',
  'recordTabMonth',
  'recordTabYear',
  'recordTabAll',
  'reportsRate',
  'reportsTotalDone',
  'reportsLongestRun',
  'shareMonthButton',
  'shareYearButton',
  'shareCardShare',
  'shareCardCaption',
  'shareCardFailed',
  'reportsPerfect',
  'reportsHabitsSection',
  'reportsRhythmTitle',
  'reportsRhythmBest',
  'reportsRhythmWorst',
  'reportsEmptyWeek',
  'reportsEmptyMonth',
  'reportsEmptyYear',
  'habitStatsThisPeriod',
  'habitStatsCurrentStreak',
  'habitStatsBestStreak',
  'habitStatsDayHint',
  'reportsDayDone',
  'reportsDayNothing',
  'reportsDayScheduled',
  'reportsDayNotDue',
  'timesPerDayNote',
  'timesPerDayDecrease',
  'timesPerDayIncrease',
  'stepLinkRecap',
  'stepLinkGoal',
  'stepGoalCustom',
  'stepGoalFieldLabel',
  'stepGoalOutOfRange',
  'helpEmailSubject',
  'helpEmailBodyLead',
  'stepLinkSwitch',
  'stepLinkedBadge',
  'stepLinkDenied',
  'stepLinkUnsupported',
  'stepsUnit',
  'stepsGoalShort',
  'stepsLinkBlocked',
  'stepsLinkNoProvider',
  'gridMoreActions',
  'reorderHabitsTitle',
  'reorderHabitsHint',
  'reorderHabitsMenuHint',
  'gridSelectMultiple',
  'gridSelectMultipleHint',
  'notifLocationSearchAction',
  'gridNoteSaved',
  'gridNoteCleared',
  'gridNoteSaveFailed',
  'gridNoteSemantics',
  'gridNoteSeeAll',
  'gridNotesMenuHint',
  'gridJournalFilterHasNote',
  'heatDayNoteLabel',
  'gridJournalSearchThisMonth',
  'gridJournalSearchProgress',
  'gridJournalSearchBackToMonth',
];

/// Every other S string. Each picks between several wordings in code (a
/// number, a state, a case), so only a code change can reword it.
const List<String> kBuiltInOnlyWordingKeys = [
  'reconnectDonePaused',
  'daysInSentence',
  'habitsCount',
  'comebackBonusAmount',
  'daysCount',
  'achievementsTierOf',
  'progressRangeLabel',
  'quitSquareLabel',
  'quitSquareStateEffect',
  'limitUnitLabel',
  'habitOffsetFromPrayer',
  'matrixTasksDeleted',
  'rewardsCardReady',
  'rewardsCardCount',
  'rewardsEffort',
  'fullDaysInSentence',
  'appIconFullDaysSoFar',
  'gridGreenSquaresCount',
  'squareStateEffect',
  'heatmapDaysOfMonth',
  'insightDetailRate',
  'premiumLifetimeBreakEven',
  'premiumOfferPercent',
  'premiumTrialLine',
  'roomNameSuggestions',
  'roomPlanSelectedCount',
  'roomCreateRoomSummary',
  'roomShareMessage',
  'roomMemberCount',
  'roomCalendarScoreOf',
  'roomTeamStreakPill',
  'roomTeamDaysWon',
  'roomLinkedHabitPausedHint',
  'habitLinkedRoomWarningBody',
  'habitPauseLinkedRoomBody',
  'habitPauseSoleRoomHabitBody',
  'roomLinkedHabitAllPausedHint',
  'pauseUntilPreset',
  'habitPausedDaysBadge',
  'habitsArchivedConfirmation',
  'roomDayCount',
  'roomPlanCoverage',
  'roomCadenceMixed',
  'journeyMilestoneCount',
  'roomBlockedHidden',
  'habitStatsDayLine',
  'timesPerDayLabel',
  'timesPerDayPhrase',
  'timesPerDayHint',
  'timesPerDayProgress',
  'roomCountedHabitRule',
  'stepLinkTitle',
  'stepLinkBody',
  'stepLinkAskNext',
  'faqGroupTitle',
  'stepsProgressLine',
  'stepsWalkedLine',
  'stepsSourceLine',
  'stepsNotArrivingHint',
  'pausedElsewhereRow',
  'gridJournalSearchAllMonths',
];

/// [S] with the edits for its language laid over it. Built only by
/// [S.edited], and only when that language has at least one edit.
class _EditedS extends S {
  _EditedS(super.locale, this._edits);

  /// Edited text by S member name, for this language only.
  final Map<String, String> _edits;

  @override
  String get appTitle => plainWording(_edits['appTitle']) ?? super.appTitle;

  @override
  String get tagline => plainWording(_edits['tagline']) ?? super.tagline;

  @override
  String get signIn => plainWording(_edits['signIn']) ?? super.signIn;

  @override
  String get createAccount => plainWording(_edits['createAccount']) ?? super.createAccount;

  @override
  String get signInAction => plainWording(_edits['signInAction']) ?? super.signInAction;

  @override
  String get createAccountAction => plainWording(_edits['createAccountAction']) ?? super.createAccountAction;

  @override
  String get email => plainWording(_edits['email']) ?? super.email;

  @override
  String get password => plainWording(_edits['password']) ?? super.password;

  @override
  String get confirmPassword => plainWording(_edits['confirmPassword']) ?? super.confirmPassword;

  @override
  String get continueWithGoogle => plainWording(_edits['continueWithGoogle']) ?? super.continueWithGoogle;

  @override
  String get continueWithApple => plainWording(_edits['continueWithApple']) ?? super.continueWithApple;

  @override
  String get authOrDivider => plainWording(_edits['authOrDivider']) ?? super.authOrDivider;

  @override
  String get continueWithEmail => plainWording(_edits['continueWithEmail']) ?? super.continueWithEmail;

  @override
  String get authOtherWays => plainWording(_edits['authOtherWays']) ?? super.authOtherWays;

  @override
  String get authAccountLead => plainWording(_edits['authAccountLead']) ?? super.authAccountLead;

  @override
  String get authAccountFact => plainWording(_edits['authAccountFact']) ?? super.authAccountFact;

  @override
  String get authGuestLead => plainWording(_edits['authGuestLead']) ?? super.authGuestLead;

  @override
  String get authGuestFact => plainWording(_edits['authGuestFact']) ?? super.authGuestFact;

  @override
  String get tryAsGuest => plainWording(_edits['tryAsGuest']) ?? super.tryAsGuest;

  @override
  String get guestDescription => plainWording(_edits['guestDescription']) ?? super.guestDescription;

  @override
  String get guestLimitTitle => plainWording(_edits['guestLimitTitle']) ?? super.guestLimitTitle;

  @override
  String get guestLimitBody => plainWording(_edits['guestLimitBody']) ?? super.guestLimitBody;

  @override
  String get guestFreshStartWarning => plainWording(_edits['guestFreshStartWarning']) ?? super.guestFreshStartWarning;

  @override
  String get reconnectTitle => plainWording(_edits['reconnectTitle']) ?? super.reconnectTitle;

  @override
  String reconnectFound(int habits, int days, int level) {
    final wordingEdit = _edits['reconnectFound'];
    if (wordingEdit == null) return super.reconnectFound(habits, days, level);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitsCount(habits)': () => '${habitsCount(habits)}',
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                  'level': () => '$level',
                }
              : <String, String Function()>{
                  'habitsCount(habits)': () => '${habitsCount(habits)}',
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                  'level': () => '$level',
                },
        ) ??
        super.reconnectFound(habits, days, level);
  }

  @override
  String get reconnectNotYours => plainWording(_edits['reconnectNotYours']) ?? super.reconnectNotYours;

  @override
  String get reconnectKeep => plainWording(_edits['reconnectKeep']) ?? super.reconnectKeep;

  @override
  String get reconnectFresh => plainWording(_edits['reconnectFresh']) ?? super.reconnectFresh;

  @override
  String get reconnectWorking => plainWording(_edits['reconnectWorking']) ?? super.reconnectWorking;

  @override
  String get reconnectDone => plainWording(_edits['reconnectDone']) ?? super.reconnectDone;

  @override
  String reconnectPartial(int days) {
    final wordingEdit = _edits['reconnectPartial'];
    if (wordingEdit == null) return super.reconnectPartial(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                }
              : <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                },
        ) ??
        super.reconnectPartial(days);
  }

  @override
  String reconnectGrace(int days) {
    final wordingEdit = _edits['reconnectGrace'];
    if (wordingEdit == null) return super.reconnectGrace(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                }
              : <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                },
        ) ??
        super.reconnectGrace(days);
  }

  @override
  String get reconnectBannerTitle => plainWording(_edits['reconnectBannerTitle']) ?? super.reconnectBannerTitle;

  @override
  String reconnectBannerBody(int days) {
    final wordingEdit = _edits['reconnectBannerBody'];
    if (wordingEdit == null) return super.reconnectBannerBody(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                }
              : <String, String Function()>{
                  'daysInSentence(days)': () => '${daysInSentence(days)}',
                },
        ) ??
        super.reconnectBannerBody(days);
  }

  @override
  String get reconnectBannerDismiss => plainWording(_edits['reconnectBannerDismiss']) ?? super.reconnectBannerDismiss;

  @override
  String get guestLimitCta => plainWording(_edits['guestLimitCta']) ?? super.guestLimitCta;

  @override
  String get guestLimitMaybeLater => plainWording(_edits['guestLimitMaybeLater']) ?? super.guestLimitMaybeLater;

  @override
  String get guestDataWarning => plainWording(_edits['guestDataWarning']) ?? super.guestDataWarning;

  @override
  String get authForgotPassword => plainWording(_edits['authForgotPassword']) ?? super.authForgotPassword;

  @override
  String get authResetSent => plainWording(_edits['authResetSent']) ?? super.authResetSent;

  @override
  String get errEnterEmailForReset => plainWording(_edits['errEnterEmailForReset']) ?? super.errEnterEmailForReset;

  @override
  String get setPasswordTitle => plainWording(_edits['setPasswordTitle']) ?? super.setPasswordTitle;

  @override
  String get setPasswordSubject => plainWording(_edits['setPasswordSubject']) ?? super.setPasswordSubject;

  @override
  String get setPasswordChecking => plainWording(_edits['setPasswordChecking']) ?? super.setPasswordChecking;

  @override
  String get setPasswordSave => plainWording(_edits['setPasswordSave']) ?? super.setPasswordSave;

  @override
  String get setPasswordHint => plainWording(_edits['setPasswordHint']) ?? super.setPasswordHint;

  @override
  String get setPasswordNote => plainWording(_edits['setPasswordNote']) ?? super.setPasswordNote;

  @override
  String get setPasswordDone => plainWording(_edits['setPasswordDone']) ?? super.setPasswordDone;

  @override
  String get resetLinkDeadTitle => plainWording(_edits['resetLinkDeadTitle']) ?? super.resetLinkDeadTitle;

  @override
  String get resetLinkDeadBody => plainWording(_edits['resetLinkDeadBody']) ?? super.resetLinkDeadBody;

  @override
  String get resetLinkDeadCta => plainWording(_edits['resetLinkDeadCta']) ?? super.resetLinkDeadCta;

  @override
  String get addPasswordTitle => plainWording(_edits['addPasswordTitle']) ?? super.addPasswordTitle;

  @override
  String get addPasswordBody => plainWording(_edits['addPasswordBody']) ?? super.addPasswordBody;

  @override
  String get addPasswordLater => plainWording(_edits['addPasswordLater']) ?? super.addPasswordLater;

  @override
  String addPasswordDone(String name) {
    final wordingEdit = _edits['addPasswordDone'];
    if (wordingEdit == null) return super.addPasswordDone(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.addPasswordDone(name);
  }

  @override
  String get addPasswordAlready => plainWording(_edits['addPasswordAlready']) ?? super.addPasswordAlready;

  @override
  String get signInMethodsTitle => plainWording(_edits['signInMethodsTitle']) ?? super.signInMethodsTitle;

  @override
  String get signInMethodsIntro => plainWording(_edits['signInMethodsIntro']) ?? super.signInMethodsIntro;

  @override
  String get signInMethodPassword => plainWording(_edits['signInMethodPassword']) ?? super.signInMethodPassword;

  @override
  String get signInMethodConnect => plainWording(_edits['signInMethodConnect']) ?? super.signInMethodConnect;

  @override
  String get signInMethodRemove => plainWording(_edits['signInMethodRemove']) ?? super.signInMethodRemove;

  @override
  String get signInMethodSetPassword => plainWording(_edits['signInMethodSetPassword']) ?? super.signInMethodSetPassword;

  @override
  String get signInMethodConnectHint => plainWording(_edits['signInMethodConnectHint']) ?? super.signInMethodConnectHint;

  @override
  String get signInMethodPasswordHint => plainWording(_edits['signInMethodPasswordHint']) ?? super.signInMethodPasswordHint;

  @override
  String get signInMethodPasswordHidden => plainWording(_edits['signInMethodPasswordHidden']) ?? super.signInMethodPasswordHidden;

  @override
  String get signInMethodOnlyWayIn => plainWording(_edits['signInMethodOnlyWayIn']) ?? super.signInMethodOnlyWayIn;

  @override
  String get signInMethodsFooter => plainWording(_edits['signInMethodsFooter']) ?? super.signInMethodsFooter;

  @override
  String signInMethodRemoveTitle(String name) {
    final wordingEdit = _edits['signInMethodRemoveTitle'];
    if (wordingEdit == null) return super.signInMethodRemoveTitle(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.signInMethodRemoveTitle(name);
  }

  @override
  String get signInMethodRemoveBody => plainWording(_edits['signInMethodRemoveBody']) ?? super.signInMethodRemoveBody;

  @override
  String signInMethodConnected(String name) {
    final wordingEdit = _edits['signInMethodConnected'];
    if (wordingEdit == null) return super.signInMethodConnected(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.signInMethodConnected(name);
  }

  @override
  String signInMethodRemoved(String name) {
    final wordingEdit = _edits['signInMethodRemoved'];
    if (wordingEdit == null) return super.signInMethodRemoved(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.signInMethodRemoved(name);
  }

  @override
  String signInMethodInUse(String name) {
    final wordingEdit = _edits['signInMethodInUse'];
    if (wordingEdit == null) return super.signInMethodInUse(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.signInMethodInUse(name);
  }

  @override
  String get signInMethodRemoveStale => plainWording(_edits['signInMethodRemoveStale']) ?? super.signInMethodRemoveStale;

  @override
  String get errFillAll => plainWording(_edits['errFillAll']) ?? super.errFillAll;

  @override
  String get errPasswordsMismatch => plainWording(_edits['errPasswordsMismatch']) ?? super.errPasswordsMismatch;

  @override
  String get errPasswordTooShort => plainWording(_edits['errPasswordTooShort']) ?? super.errPasswordTooShort;

  @override
  String get errInvalidCredential => plainWording(_edits['errInvalidCredential']) ?? super.errInvalidCredential;

  @override
  String get errEmailInUse => plainWording(_edits['errEmailInUse']) ?? super.errEmailInUse;

  @override
  String get errInvalidEmail => plainWording(_edits['errInvalidEmail']) ?? super.errInvalidEmail;

  @override
  String get errWeakPassword => plainWording(_edits['errWeakPassword']) ?? super.errWeakPassword;

  @override
  String get errNetwork => plainWording(_edits['errNetwork']) ?? super.errNetwork;

  @override
  String get errAccountExistsWithEmail => plainWording(_edits['errAccountExistsWithEmail']) ?? super.errAccountExistsWithEmail;

  @override
  String get errSignInMethodUnavailable => plainWording(_edits['errSignInMethodUnavailable']) ?? super.errSignInMethodUnavailable;

  @override
  String get errAppleAccountRequired => plainWording(_edits['errAppleAccountRequired']) ?? super.errAppleAccountRequired;

  @override
  String get errTooManyRequests => plainWording(_edits['errTooManyRequests']) ?? super.errTooManyRequests;

  @override
  String get errGeneric => plainWording(_edits['errGeneric']) ?? super.errGeneric;

  @override
  String get todaysHabits => plainWording(_edits['todaysHabits']) ?? super.todaysHabits;

  @override
  String get addHabit => plainWording(_edits['addHabit']) ?? super.addHabit;

  @override
  String get signOut => plainWording(_edits['signOut']) ?? super.signOut;

  @override
  String get signOutConfirmTitle => plainWording(_edits['signOutConfirmTitle']) ?? super.signOutConfirmTitle;

  @override
  String get signOutConfirmBody => plainWording(_edits['signOutConfirmBody']) ?? super.signOutConfirmBody;

  @override
  String get signOutConfirmCancel => plainWording(_edits['signOutConfirmCancel']) ?? super.signOutConfirmCancel;

  @override
  String get deleteAccount => plainWording(_edits['deleteAccount']) ?? super.deleteAccount;

  @override
  String get deleteAccountWarningTitle => plainWording(_edits['deleteAccountWarningTitle']) ?? super.deleteAccountWarningTitle;

  @override
  String get deleteAccountWarningBody => plainWording(_edits['deleteAccountWarningBody']) ?? super.deleteAccountWarningBody;

  @override
  String get deleteAccountPasswordLabel => plainWording(_edits['deleteAccountPasswordLabel']) ?? super.deleteAccountPasswordLabel;

  @override
  String get deleteAccountVerifyGoogle => plainWording(_edits['deleteAccountVerifyGoogle']) ?? super.deleteAccountVerifyGoogle;

  @override
  String get deleteAccountVerifyApple => plainWording(_edits['deleteAccountVerifyApple']) ?? super.deleteAccountVerifyApple;

  @override
  String get deleteAccountConfirmCta => plainWording(_edits['deleteAccountConfirmCta']) ?? super.deleteAccountConfirmCta;

  @override
  String get deleteAccountWrongPassword => plainWording(_edits['deleteAccountWrongPassword']) ?? super.deleteAccountWrongPassword;

  @override
  String get deleteAccountSuccess => plainWording(_edits['deleteAccountSuccess']) ?? super.deleteAccountSuccess;

  @override
  String get level => plainWording(_edits['level']) ?? super.level;

  @override
  String get totalXp => plainWording(_edits['totalXp']) ?? super.totalXp;

  @override
  String get streak => plainWording(_edits['streak']) ?? super.streak;

  @override
  String get freeze => plainWording(_edits['freeze']) ?? super.freeze;

  @override
  String get gold => plainWording(_edits['gold']) ?? super.gold;

  @override
  String get active => plainWording(_edits['active']) ?? super.active;

  @override
  String activeCount(int n) {
    final wordingEdit = _edits['activeCount'];
    if (wordingEdit == null) return super.activeCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.activeCount(n);
  }

  @override
  String get statsUnavailableTitle => plainWording(_edits['statsUnavailableTitle']) ?? super.statsUnavailableTitle;

  @override
  String get statsUnavailableBody => plainWording(_edits['statsUnavailableBody']) ?? super.statsUnavailableBody;

  @override
  String get statsUnavailableRetry => plainWording(_edits['statsUnavailableRetry']) ?? super.statsUnavailableRetry;

  @override
  String get habitsNotLoadedNotice => plainWording(_edits['habitsNotLoadedNotice']) ?? super.habitsNotLoadedNotice;

  @override
  String get todaysIntention => plainWording(_edits['todaysIntention']) ?? super.todaysIntention;

  @override
  String get pickTinyWin => plainWording(_edits['pickTinyWin']) ?? super.pickTinyWin;

  @override
  String get pickOneGoal => plainWording(_edits['pickOneGoal']) ?? super.pickOneGoal;

  @override
  String streakFreezeProtected(int remaining) {
    final wordingEdit = _edits['streakFreezeProtected'];
    if (wordingEdit == null) return super.streakFreezeProtected(remaining);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'remaining': () => '$remaining',
                }
              : <String, String Function()>{
                  'remaining': () => '$remaining',
                },
        ) ??
        super.streakFreezeProtected(remaining);
  }

  @override
  String get claimComeback => plainWording(_edits['claimComeback']) ?? super.claimComeback;

  @override
  String welcomeBack(String name) {
    final wordingEdit = _edits['welcomeBack'];
    if (wordingEdit == null) return super.welcomeBack(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.welcomeBack(name);
  }

  @override
  String get welcomeBackNoName => plainWording(_edits['welcomeBackNoName']) ?? super.welcomeBackNoName;

  @override
  String get comebackNoErase => plainWording(_edits['comebackNoErase']) ?? super.comebackNoErase;

  @override
  String get comebackBonusLabel => plainWording(_edits['comebackBonusLabel']) ?? super.comebackBonusLabel;

  @override
  String get comebackEitherWay => plainWording(_edits['comebackEitherWay']) ?? super.comebackEitherWay;

  @override
  String restoreStreakOffer(int days) {
    final wordingEdit = _edits['restoreStreakOffer'];
    if (wordingEdit == null) return super.restoreStreakOffer(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'days': () => '$days',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.restoreStreakOffer(days);
  }

  @override
  String restoreStreakCta(int left) {
    final wordingEdit = _edits['restoreStreakCta'];
    if (wordingEdit == null) return super.restoreStreakCta(left);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'left': () => '$left',
                }
              : <String, String Function()>{
                  'left': () => '$left',
                },
        ) ??
        super.restoreStreakCta(left);
  }

  @override
  String get freshStreakInstead => plainWording(_edits['freshStreakInstead']) ?? super.freshStreakInstead;

  @override
  String get keepGrowing => plainWording(_edits['keepGrowing']) ?? super.keepGrowing;

  @override
  String get streakMilestoneLabel => plainWording(_edits['streakMilestoneLabel']) ?? super.streakMilestoneLabel;

  @override
  String get milestoneUnbroken => plainWording(_edits['milestoneUnbroken']) ?? super.milestoneUnbroken;

  @override
  String milestoneNextStop(int days) {
    final wordingEdit = _edits['milestoneNextStop'];
    if (wordingEdit == null) return super.milestoneNextStop(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(days)': () => '${daysCount(days)}',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.milestoneNextStop(days);
  }

  @override
  String get milestoneLastStop => plainWording(_edits['milestoneLastStop']) ?? super.milestoneLastStop;

  @override
  String milestoneBonusXp(int bonus) {
    final wordingEdit = _edits['milestoneBonusXp'];
    if (wordingEdit == null) return super.milestoneBonusXp(bonus);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'bonus': () => '$bonus',
                }
              : <String, String Function()>{
                  'bonus': () => '$bonus',
                },
        ) ??
        super.milestoneBonusXp(bonus);
  }

  @override
  String get achievementUnlocked => plainWording(_edits['achievementUnlocked']) ?? super.achievementUnlocked;

  @override
  String get bonusTag => plainWording(_edits['bonusTag']) ?? super.bonusTag;

  @override
  String get claimReward => plainWording(_edits['claimReward']) ?? super.claimReward;

  @override
  String get levelUpMsg => plainWording(_edits['levelUpMsg']) ?? super.levelUpMsg;

  @override
  String get profile => plainWording(_edits['profile']) ?? super.profile;

  @override
  String get achievements => plainWording(_edits['achievements']) ?? super.achievements;

  @override
  String achievementsViewAll(int n) {
    final wordingEdit = _edits['achievementsViewAll'];
    if (wordingEdit == null) return super.achievementsViewAll(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.achievementsViewAll(n);
  }

  @override
  String get achievementsShowLess => plainWording(_edits['achievementsShowLess']) ?? super.achievementsShowLess;

  @override
  String get achievementsMedalsEarned => plainWording(_edits['achievementsMedalsEarned']) ?? super.achievementsMedalsEarned;

  @override
  String get achievementsNextUp => plainWording(_edits['achievementsNextUp']) ?? super.achievementsNextUp;

  @override
  String achievementsRemaining(int n) {
    final wordingEdit = _edits['achievementsRemaining'];
    if (wordingEdit == null) return super.achievementsRemaining(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.achievementsRemaining(n);
  }

  @override
  String get achievementsAllDone => plainWording(_edits['achievementsAllDone']) ?? super.achievementsAllDone;

  @override
  String get achievementsMastered => plainWording(_edits['achievementsMastered']) ?? super.achievementsMastered;

  @override
  String get achievementsEarned => plainWording(_edits['achievementsEarned']) ?? super.achievementsEarned;

  @override
  String get achievementsTapTierHint => plainWording(_edits['achievementsTapTierHint']) ?? super.achievementsTapTierHint;

  @override
  String get profileSection => plainWording(_edits['profileSection']) ?? super.profileSection;

  @override
  String get achievementsRowTitle => plainWording(_edits['achievementsRowTitle']) ?? super.achievementsRowTitle;

  @override
  String get progressStreakTitle => plainWording(_edits['progressStreakTitle']) ?? super.progressStreakTitle;

  @override
  String get progressTitle => plainWording(_edits['progressTitle']) ?? super.progressTitle;

  @override
  String get dashboardViewFullInsights => plainWording(_edits['dashboardViewFullInsights']) ?? super.dashboardViewFullInsights;

  @override
  String get dashboardViewFullJournal => plainWording(_edits['dashboardViewFullJournal']) ?? super.dashboardViewFullJournal;

  @override
  String get profileDashboardSection => plainWording(_edits['profileDashboardSection']) ?? super.profileDashboardSection;

  @override
  String get settings => plainWording(_edits['settings']) ?? super.settings;

  @override
  String get settingsScreenTitle => plainWording(_edits['settingsScreenTitle']) ?? super.settingsScreenTitle;

  @override
  String get darkMode => plainWording(_edits['darkMode']) ?? super.darkMode;

  @override
  String get appearance => plainWording(_edits['appearance']) ?? super.appearance;

  @override
  String get appearanceSheetTitle => plainWording(_edits['appearanceSheetTitle']) ?? super.appearanceSheetTitle;

  @override
  String get appearancePremiumHint => plainWording(_edits['appearancePremiumHint']) ?? super.appearancePremiumHint;

  @override
  String get appFont => plainWording(_edits['appFont']) ?? super.appFont;

  @override
  String get appFontSheetTitle => plainWording(_edits['appFontSheetTitle']) ?? super.appFontSheetTitle;

  @override
  String get preview => plainWording(_edits['preview']) ?? super.preview;

  @override
  String get themePreviewApply => plainWording(_edits['themePreviewApply']) ?? super.themePreviewApply;

  @override
  String get themePreviewUnlock => plainWording(_edits['themePreviewUnlock']) ?? super.themePreviewUnlock;

  @override
  String get themeSectionFree => plainWording(_edits['themeSectionFree']) ?? super.themeSectionFree;

  @override
  String get themeSectionPremium => plainWording(_edits['themeSectionPremium']) ?? super.themeSectionPremium;

  @override
  String get themeCustomPitch => plainWording(_edits['themeCustomPitch']) ?? super.themeCustomPitch;

  @override
  String themeCustomReadyMade(String n) {
    final wordingEdit = _edits['themeCustomReadyMade'];
    if (wordingEdit == null) return super.themeCustomReadyMade(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.themeCustomReadyMade(n);
  }

  @override
  String get themeCustomName => plainWording(_edits['themeCustomName']) ?? super.themeCustomName;

  @override
  String get themeCustomTitle => plainWording(_edits['themeCustomTitle']) ?? super.themeCustomTitle;

  @override
  String get themeCustomHint => plainWording(_edits['themeCustomHint']) ?? super.themeCustomHint;

  @override
  String get themeCustomAccent => plainWording(_edits['themeCustomAccent']) ?? super.themeCustomAccent;

  @override
  String get themeCustomAccentHint => plainWording(_edits['themeCustomAccentHint']) ?? super.themeCustomAccentHint;

  @override
  String get themeCustomGrid => plainWording(_edits['themeCustomGrid']) ?? super.themeCustomGrid;

  @override
  String get themeCustomGridHint => plainWording(_edits['themeCustomGridHint']) ?? super.themeCustomGridHint;

  @override
  String get themeCustomDone => plainWording(_edits['themeCustomDone']) ?? super.themeCustomDone;

  @override
  String get themeCustomTabPalette => plainWording(_edits['themeCustomTabPalette']) ?? super.themeCustomTabPalette;

  @override
  String get themeCustomTabPicker => plainWording(_edits['themeCustomTabPicker']) ?? super.themeCustomTabPicker;

  @override
  String get themeCustomSaved => plainWording(_edits['themeCustomSaved']) ?? super.themeCustomSaved;

  @override
  String get themeCustomSavedEmpty => plainWording(_edits['themeCustomSavedEmpty']) ?? super.themeCustomSavedEmpty;

  @override
  String get themeCustomSavedTapHint => plainWording(_edits['themeCustomSavedTapHint']) ?? super.themeCustomSavedTapHint;

  @override
  String get themeCustomSaveTooltip => plainWording(_edits['themeCustomSaveTooltip']) ?? super.themeCustomSaveTooltip;

  @override
  String get themeCustomSavedFull => plainWording(_edits['themeCustomSavedFull']) ?? super.themeCustomSavedFull;

  @override
  String get themeCustomPreview => plainWording(_edits['themeCustomPreview']) ?? super.themeCustomPreview;

  @override
  String get themeCustomPreviewHabit => plainWording(_edits['themeCustomPreviewHabit']) ?? super.themeCustomPreviewHabit;

  @override
  String get themeCustomPreviewAction => plainWording(_edits['themeCustomPreviewAction']) ?? super.themeCustomPreviewAction;

  @override
  String previewingTheme(String name) {
    final wordingEdit = _edits['previewingTheme'];
    if (wordingEdit == null) return super.previewingTheme(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.previewingTheme(name);
  }

  @override
  String get language => plainWording(_edits['language']) ?? super.language;

  @override
  String get languageAr => plainWording(_edits['languageAr']) ?? super.languageAr;

  @override
  String get languageEn => plainWording(_edits['languageEn']) ?? super.languageEn;

  @override
  String get cumulativeXp => plainWording(_edits['cumulativeXp']) ?? super.cumulativeXp;

  @override
  String xpToLevel(int n) {
    final wordingEdit = _edits['xpToLevel'];
    if (wordingEdit == null) return super.xpToLevel(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                  'n + 1': () => '${n + 1}',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.xpToLevel(n);
  }

  @override
  String xpProgress(int current, int total, int nextLevel) {
    final wordingEdit = _edits['xpProgress'];
    if (wordingEdit == null) return super.xpProgress(current, total, nextLevel);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'progressFraction(current, total)': () => '${progressFraction(current, total)}',
                  'nextLevel': () => '$nextLevel',
                }
              : <String, String Function()>{
                  'progressFraction(current, total)': () => '${progressFraction(current, total)}',
                  'nextLevel': () => '$nextLevel',
                },
        ) ??
        super.xpProgress(current, total, nextLevel);
  }

  @override
  String get best => plainWording(_edits['best']) ?? super.best;

  @override
  String get total => plainWording(_edits['total']) ?? super.total;

  @override
  String get statInfoStreakTitle => plainWording(_edits['statInfoStreakTitle']) ?? super.statInfoStreakTitle;

  @override
  String get statInfoStreakDesc => plainWording(_edits['statInfoStreakDesc']) ?? super.statInfoStreakDesc;

  @override
  String get statInfoBestTitle => plainWording(_edits['statInfoBestTitle']) ?? super.statInfoBestTitle;

  @override
  String get statInfoBestDesc => plainWording(_edits['statInfoBestDesc']) ?? super.statInfoBestDesc;

  @override
  String get statInfoTotalTitle => plainWording(_edits['statInfoTotalTitle']) ?? super.statInfoTotalTitle;

  @override
  String get statInfoTotalDesc => plainWording(_edits['statInfoTotalDesc']) ?? super.statInfoTotalDesc;

  @override
  String get statInfoGoldTitle => plainWording(_edits['statInfoGoldTitle']) ?? super.statInfoGoldTitle;

  @override
  String get statInfoGoldDesc => plainWording(_edits['statInfoGoldDesc']) ?? super.statInfoGoldDesc;

  @override
  String get statInfoXpTitle => plainWording(_edits['statInfoXpTitle']) ?? super.statInfoXpTitle;

  @override
  String get statInfoXpDesc => plainWording(_edits['statInfoXpDesc']) ?? super.statInfoXpDesc;

  @override
  String get progressDayByDay => plainWording(_edits['progressDayByDay']) ?? super.progressDayByDay;

  @override
  String get holdingStrong => plainWording(_edits['holdingStrong']) ?? super.holdingStrong;

  @override
  String get startAgain => plainWording(_edits['startAgain']) ?? super.startAgain;

  @override
  String get noProgressYet => plainWording(_edits['noProgressYet']) ?? super.noProgressYet;

  @override
  String get loadingReport => plainWording(_edits['loadingReport']) ?? super.loadingReport;

  @override
  String get activeDays => plainWording(_edits['activeDays']) ?? super.activeDays;

  @override
  String get bestDay => plainWording(_edits['bestDay']) ?? super.bestDay;

  @override
  String get progressStatRate => plainWording(_edits['progressStatRate']) ?? super.progressStatRate;

  @override
  String get progressToday => plainWording(_edits['progressToday']) ?? super.progressToday;

  @override
  String get progressYesterday => plainWording(_edits['progressYesterday']) ?? super.progressYesterday;

  @override
  String get progressDayBreakdown => plainWording(_edits['progressDayBreakdown']) ?? super.progressDayBreakdown;

  @override
  String get progressChartLegend => plainWording(_edits['progressChartLegend']) ?? super.progressChartLegend;

  @override
  String progressDayScore(int done, int owed) {
    final wordingEdit = _edits['progressDayScore'];
    if (wordingEdit == null) return super.progressDayScore(done, owed);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'owed': () => '$owed',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'owed': () => '$owed',
                },
        ) ??
        super.progressDayScore(done, owed);
  }

  @override
  String progressScoreFraction(int done, int owed) {
    final wordingEdit = _edits['progressScoreFraction'];
    if (wordingEdit == null) return super.progressScoreFraction(done, owed);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'owed': () => '$owed',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'owed': () => '$owed',
                },
        ) ??
        super.progressScoreFraction(done, owed);
  }

  @override
  String get progressNothingDueShort => plainWording(_edits['progressNothingDueShort']) ?? super.progressNothingDueShort;

  @override
  String get progressRestedShort => plainWording(_edits['progressRestedShort']) ?? super.progressRestedShort;

  @override
  String get progressDayRested => plainWording(_edits['progressDayRested']) ?? super.progressDayRested;

  @override
  String get progressDayNothingDue => plainWording(_edits['progressDayNothingDue']) ?? super.progressDayNothingDue;

  @override
  String get streakFreeze => plainWording(_edits['streakFreeze']) ?? super.streakFreeze;

  @override
  String streakFreezeStatus(int current, int max) {
    final wordingEdit = _edits['streakFreezeStatus'];
    if (wordingEdit == null) return super.streakFreezeStatus(current, max);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'current': () => '$current',
                  'max': () => '$max',
                }
              : <String, String Function()>{
                  'current': () => '$current',
                  'max': () => '$max',
                },
        ) ??
        super.streakFreezeStatus(current, max);
  }

  @override
  String get freezeSlotTitle => plainWording(_edits['freezeSlotTitle']) ?? super.freezeSlotTitle;

  @override
  String freezeSlotBody(int capacity) {
    final wordingEdit = _edits['freezeSlotBody'];
    if (wordingEdit == null) return super.freezeSlotBody(capacity);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'capacity': () => '$capacity',
                }
              : <String, String Function()>{
                  'capacity': () => '$capacity',
                },
        ) ??
        super.freezeSlotBody(capacity);
  }

  @override
  String freezeSlotLocked(int level) {
    final wordingEdit = _edits['freezeSlotLocked'];
    if (wordingEdit == null) return super.freezeSlotLocked(level);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'level': () => '$level',
                }
              : <String, String Function()>{
                  'level': () => '$level',
                },
        ) ??
        super.freezeSlotLocked(level);
  }

  @override
  String get hubTitle => plainWording(_edits['hubTitle']) ?? super.hubTitle;

  @override
  String get hubTitleQuit => plainWording(_edits['hubTitleQuit']) ?? super.hubTitleQuit;

  @override
  String get plansTab => plainWording(_edits['plansTab']) ?? super.plansTab;

  @override
  String get choosePlan => plainWording(_edits['choosePlan']) ?? super.choosePlan;

  @override
  String get choosePlanSubtitle => plainWording(_edits['choosePlanSubtitle']) ?? super.choosePlanSubtitle;

  @override
  String get startPlan => plainWording(_edits['startPlan']) ?? super.startPlan;

  @override
  String get deactivatePlan => plainWording(_edits['deactivatePlan']) ?? super.deactivatePlan;

  @override
  String get planPickHabitsHint => plainWording(_edits['planPickHabitsHint']) ?? super.planPickHabitsHint;

  @override
  String addRemainingPlanHabits(int n) {
    final wordingEdit = _edits['addRemainingPlanHabits'];
    if (wordingEdit == null) return super.addRemainingPlanHabits(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.addRemainingPlanHabits(n);
  }

  @override
  String get browsePlans => plainWording(_edits['browsePlans']) ?? super.browsePlans;

  @override
  String get dailyReminder => plainWording(_edits['dailyReminder']) ?? super.dailyReminder;

  @override
  String get dailyReminderPromptTitle => plainWording(_edits['dailyReminderPromptTitle']) ?? super.dailyReminderPromptTitle;

  @override
  String get dailyReminderPromptBody => plainWording(_edits['dailyReminderPromptBody']) ?? super.dailyReminderPromptBody;

  @override
  String get dailyReminderPromptAfterIsha => plainWording(_edits['dailyReminderPromptAfterIsha']) ?? super.dailyReminderPromptAfterIsha;

  @override
  String get dailyReminderPromptOtherTime => plainWording(_edits['dailyReminderPromptOtherTime']) ?? super.dailyReminderPromptOtherTime;

  @override
  String get dailyReminderPromptLater => plainWording(_edits['dailyReminderPromptLater']) ?? super.dailyReminderPromptLater;

  @override
  String get dailyReminderPromptNever => plainWording(_edits['dailyReminderPromptNever']) ?? super.dailyReminderPromptNever;

  @override
  String get dailyReminderPromptSettingsHint => plainWording(_edits['dailyReminderPromptSettingsHint']) ?? super.dailyReminderPromptSettingsHint;

  @override
  String get dailyReminderPromptLastAsk => plainWording(_edits['dailyReminderPromptLastAsk']) ?? super.dailyReminderPromptLastAsk;

  @override
  String get dailyReminderPromptLastHint => plainWording(_edits['dailyReminderPromptLastHint']) ?? super.dailyReminderPromptLastHint;

  @override
  String dailyReminderSetToast(String time) {
    final wordingEdit = _edits['dailyReminderSetToast'];
    if (wordingEdit == null) return super.dailyReminderSetToast(time);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'time': () => '$time',
                }
              : <String, String Function()>{
                  'time': () => '$time',
                },
        ) ??
        super.dailyReminderSetToast(time);
  }

  @override
  String get tapToSetReminder => plainWording(_edits['tapToSetReminder']) ?? super.tapToSetReminder;

  @override
  String get reminderPermissionDenied => plainWording(_edits['reminderPermissionDenied']) ?? super.reminderPermissionDenied;

  @override
  String get noHabitsYet => plainWording(_edits['noHabitsYet']) ?? super.noHabitsYet;

  @override
  String get noHabitsDesc => plainWording(_edits['noHabitsDesc']) ?? super.noHabitsDesc;

  @override
  String get allDoneTitle => plainWording(_edits['allDoneTitle']) ?? super.allDoneTitle;

  @override
  String get allDoneSubtitle => plainWording(_edits['allDoneSubtitle']) ?? super.allDoneSubtitle;

  @override
  String get removeHabit => plainWording(_edits['removeHabit']) ?? super.removeHabit;

  @override
  String get editHabitAction => plainWording(_edits['editHabitAction']) ?? super.editHabitAction;

  @override
  String get newHabit => plainWording(_edits['newHabit']) ?? super.newHabit;

  @override
  String get editHabit => plainWording(_edits['editHabit']) ?? super.editHabit;

  @override
  String get saveChanges => plainWording(_edits['saveChanges']) ?? super.saveChanges;

  @override
  String get habitNameHint => plainWording(_edits['habitNameHint']) ?? super.habitNameHint;

  @override
  String get afterWhatRoutine => plainWording(_edits['afterWhatRoutine']) ?? super.afterWhatRoutine;

  @override
  String get routineHint => plainWording(_edits['routineHint']) ?? super.routineHint;

  @override
  String get cueAfterOption => plainWording(_edits['cueAfterOption']) ?? super.cueAfterOption;

  @override
  String get cueBeforeOption => plainWording(_edits['cueBeforeOption']) ?? super.cueBeforeOption;

  @override
  String get pickATime => plainWording(_edits['pickATime']) ?? super.pickATime;

  @override
  String get category => plainWording(_edits['category']) ?? super.category;

  @override
  String get frequency => plainWording(_edits['frequency']) ?? super.frequency;

  @override
  String get daily => plainWording(_edits['daily']) ?? super.daily;

  @override
  String get weekly => plainWording(_edits['weekly']) ?? super.weekly;

  @override
  String get times => plainWording(_edits['times']) ?? super.times;

  @override
  String get createHabit => plainWording(_edits['createHabit']) ?? super.createHabit;

  @override
  String get smartStarters => plainWording(_edits['smartStarters']) ?? super.smartStarters;

  @override
  String get addGoalTitle => plainWording(_edits['addGoalTitle']) ?? super.addGoalTitle;

  @override
  String get whatImprove => plainWording(_edits['whatImprove']) ?? super.whatImprove;

  @override
  String get whatHabitBuild => plainWording(_edits['whatHabitBuild']) ?? super.whatHabitBuild;

  @override
  String get whatReduce => plainWording(_edits['whatReduce']) ?? super.whatReduce;

  @override
  String get goalTitleHint => plainWording(_edits['goalTitleHint']) ?? super.goalTitleHint;

  @override
  String get smartSuggestions => plainWording(_edits['smartSuggestions']) ?? super.smartSuggestions;

  @override
  String get quickestStart => plainWording(_edits['quickestStart']) ?? super.quickestStart;

  @override
  String get goalTypeBuildOption => plainWording(_edits['goalTypeBuildOption']) ?? super.goalTypeBuildOption;

  @override
  String get goalTypeQuitOption => plainWording(_edits['goalTypeQuitOption']) ?? super.goalTypeQuitOption;

  @override
  String get categoryPickHint => plainWording(_edits['categoryPickHint']) ?? super.categoryPickHint;

  @override
  String get limitAmountRequired => plainWording(_edits['limitAmountRequired']) ?? super.limitAmountRequired;

  @override
  String quitLimitRule(int amount, String unit) {
    final wordingEdit = _edits['quitLimitRule'];
    if (wordingEdit == null) return super.quitLimitRule(amount, unit);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'amount': () => '$amount',
                  'unit': () => '$unit',
                }
              : <String, String Function()>{
                  'amount': () => '$amount',
                  'unit': () => '$unit',
                },
        ) ??
        super.quitLimitRule(amount, unit);
  }

  @override
  String get readyPlansLink => plainWording(_edits['readyPlansLink']) ?? super.readyPlansLink;

  @override
  String get timingBuildTitle => plainWording(_edits['timingBuildTitle']) ?? super.timingBuildTitle;

  @override
  String get timingQuitTitle => plainWording(_edits['timingQuitTitle']) ?? super.timingQuitTitle;

  @override
  String get whenQuestion => plainWording(_edits['whenQuestion']) ?? super.whenQuestion;

  @override
  String get customTime => plainWording(_edits['customTime']) ?? super.customTime;

  @override
  String get customText => plainWording(_edits['customText']) ?? super.customText;

  @override
  String get cuePrayerOption => plainWording(_edits['cuePrayerOption']) ?? super.cuePrayerOption;

  @override
  String get pickAPrayer => plainWording(_edits['pickAPrayer']) ?? super.pickAPrayer;

  @override
  String get remindMeSection => plainWording(_edits['remindMeSection']) ?? super.remindMeSection;

  @override
  String get reminderStyleSection => plainWording(_edits['reminderStyleSection']) ?? super.reminderStyleSection;

  @override
  String get reminderStyleNotification => plainWording(_edits['reminderStyleNotification']) ?? super.reminderStyleNotification;

  @override
  String get reminderStyleAlarm => plainWording(_edits['reminderStyleAlarm']) ?? super.reminderStyleAlarm;

  @override
  String get reminderStyleAlarmHint => plainWording(_edits['reminderStyleAlarmHint']) ?? super.reminderStyleAlarmHint;

  @override
  String get alarmPermissionDenied => plainWording(_edits['alarmPermissionDenied']) ?? super.alarmPermissionDenied;

  @override
  String get alarmNeedsNewerIos => plainWording(_edits['alarmNeedsNewerIos']) ?? super.alarmNeedsNewerIos;

  @override
  String get leadAtTime => plainWording(_edits['leadAtTime']) ?? super.leadAtTime;

  @override
  String get leadCustomOption => plainWording(_edits['leadCustomOption']) ?? super.leadCustomOption;

  @override
  String get leadCustomMinutesHint => plainWording(_edits['leadCustomMinutesHint']) ?? super.leadCustomMinutesHint;

  @override
  String offsetBeforeMinutes(int n) {
    final wordingEdit = _edits['offsetBeforeMinutes'];
    if (wordingEdit == null) return super.offsetBeforeMinutes(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.offsetBeforeMinutes(n);
  }

  @override
  String offsetAfterMinutes(int n) {
    final wordingEdit = _edits['offsetAfterMinutes'];
    if (wordingEdit == null) return super.offsetAfterMinutes(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.offsetAfterMinutes(n);
  }

  @override
  String get offsetBeforeLabel => plainWording(_edits['offsetBeforeLabel']) ?? super.offsetBeforeLabel;

  @override
  String get offsetAfterLabel => plainWording(_edits['offsetAfterLabel']) ?? super.offsetAfterLabel;

  @override
  String get quietHoursConflictWarning => plainWording(_edits['quietHoursConflictWarning']) ?? super.quietHoursConflictWarning;

  @override
  String get quietHoursOverrideOn => plainWording(_edits['quietHoursOverrideOn']) ?? super.quietHoursOverrideOn;

  @override
  String get quietHoursAllowAnywayAction => plainWording(_edits['quietHoursAllowAnywayAction']) ?? super.quietHoursAllowAnywayAction;

  @override
  String get quietHoursRespectAction => plainWording(_edits['quietHoursRespectAction']) ?? super.quietHoursRespectAction;

  @override
  String remindAtTimePreview(String time) {
    final wordingEdit = _edits['remindAtTimePreview'];
    if (wordingEdit == null) return super.remindAtTimePreview(time);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'time': () => '$time',
                }
              : <String, String Function()>{
                  'time': () => '$time',
                },
        ) ??
        super.remindAtTimePreview(time);
  }

  @override
  String get remindPreviewNeedsLocation => plainWording(_edits['remindPreviewNeedsLocation']) ?? super.remindPreviewNeedsLocation;

  @override
  String get timingToggle => plainWording(_edits['timingToggle']) ?? super.timingToggle;

  @override
  String get timingToggleQuit => plainWording(_edits['timingToggleQuit']) ?? super.timingToggleQuit;

  @override
  String get repeat => plainWording(_edits['repeat']) ?? super.repeat;

  @override
  String get repeatPickOne => plainWording(_edits['repeatPickOne']) ?? super.repeatPickOne;

  @override
  String get goalStyle => plainWording(_edits['goalStyle']) ?? super.goalStyle;

  @override
  String get customizeTiming => plainWording(_edits['customizeTiming']) ?? super.customizeTiming;

  @override
  String get avoidCompletely => plainWording(_edits['avoidCompletely']) ?? super.avoidCompletely;

  @override
  String get setLimit => plainWording(_edits['setLimit']) ?? super.setLimit;

  @override
  String get maxAmount => plainWording(_edits['maxAmount']) ?? super.maxAmount;

  @override
  String get customUnitPrompt => plainWording(_edits['customUnitPrompt']) ?? super.customUnitPrompt;

  @override
  String get customUnitHint => plainWording(_edits['customUnitHint']) ?? super.customUnitHint;

  @override
  String get customTriggerOptional => plainWording(_edits['customTriggerOptional']) ?? super.customTriggerOptional;

  @override
  String get threeTimesWeek => plainWording(_edits['threeTimesWeek']) ?? super.threeTimesWeek;

  @override
  String get specificDays => plainWording(_edits['specificDays']) ?? super.specificDays;

  @override
  String get timesPerWeek => plainWording(_edits['timesPerWeek']) ?? super.timesPerWeek;

  @override
  String get createGoal => plainWording(_edits['createGoal']) ?? super.createGoal;

  @override
  String get continueAction => plainWording(_edits['continueAction']) ?? super.continueAction;

  @override
  String get back => plainWording(_edits['back']) ?? super.back;

  @override
  String get tinyHintDefault => plainWording(_edits['tinyHintDefault']) ?? super.tinyHintDefault;

  @override
  String get tinyHintQuran => plainWording(_edits['tinyHintQuran']) ?? super.tinyHintQuran;

  @override
  String get tinyHintAthkar => plainWording(_edits['tinyHintAthkar']) ?? super.tinyHintAthkar;

  @override
  String get tinyHintFitness => plainWording(_edits['tinyHintFitness']) ?? super.tinyHintFitness;

  @override
  String get tinyHintSleep => plainWording(_edits['tinyHintSleep']) ?? super.tinyHintSleep;

  @override
  String get focus => plainWording(_edits['focus']) ?? super.focus;

  @override
  String get focusTitle => plainWording(_edits['focusTitle']) ?? super.focusTitle;

  @override
  String get focusDailyTitle => plainWording(_edits['focusDailyTitle']) ?? super.focusDailyTitle;

  @override
  String get focusTagline => plainWording(_edits['focusTagline']) ?? super.focusTagline;

  @override
  String focusRitualProgress(int done) {
    final wordingEdit = _edits['focusRitualProgress'];
    if (wordingEdit == null) return super.focusRitualProgress(done);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                },
        ) ??
        super.focusRitualProgress(done);
  }

  @override
  String get focusMostImportantTask => plainWording(_edits['focusMostImportantTask']) ?? super.focusMostImportantTask;

  @override
  String get focusMitSubtitle => plainWording(_edits['focusMitSubtitle']) ?? super.focusMitSubtitle;

  @override
  String get focusIfThenPlan => plainWording(_edits['focusIfThenPlan']) ?? super.focusIfThenPlan;

  @override
  String get focusTopTaskHint => plainWording(_edits['focusTopTaskHint']) ?? super.focusTopTaskHint;

  @override
  String get focusTopTaskLabel => plainWording(_edits['focusTopTaskLabel']) ?? super.focusTopTaskLabel;

  @override
  String get focusCuePrefix => plainWording(_edits['focusCuePrefix']) ?? super.focusCuePrefix;

  @override
  String get focusCueHint => plainWording(_edits['focusCueHint']) ?? super.focusCueHint;

  @override
  String get focusCueLabel => plainWording(_edits['focusCueLabel']) ?? super.focusCueLabel;

  @override
  String get focusActionPrefix => plainWording(_edits['focusActionPrefix']) ?? super.focusActionPrefix;

  @override
  String get focusActionHint => plainWording(_edits['focusActionHint']) ?? super.focusActionHint;

  @override
  String get focusActionLabel => plainWording(_edits['focusActionLabel']) ?? super.focusActionLabel;

  @override
  String get focusSavePlan => plainWording(_edits['focusSavePlan']) ?? super.focusSavePlan;

  @override
  String get focusPlanSaved => plainWording(_edits['focusPlanSaved']) ?? super.focusPlanSaved;

  @override
  String get focusTimerTitle => plainWording(_edits['focusTimerTitle']) ?? super.focusTimerTitle;

  @override
  String get focusTimerSubtitle => plainWording(_edits['focusTimerSubtitle']) ?? super.focusTimerSubtitle;

  @override
  String get focusPauseSprint => plainWording(_edits['focusPauseSprint']) ?? super.focusPauseSprint;

  @override
  String get focusStartSprint => plainWording(_edits['focusStartSprint']) ?? super.focusStartSprint;

  @override
  String get focusResetTimer => plainWording(_edits['focusResetTimer']) ?? super.focusResetTimer;

  @override
  String get focusReady => plainWording(_edits['focusReady']) ?? super.focusReady;

  @override
  String get focusFocusing => plainWording(_edits['focusFocusing']) ?? super.focusFocusing;

  @override
  String get focusComplete => plainWording(_edits['focusComplete']) ?? super.focusComplete;

  @override
  String focusMinutesLabel(int m) {
    final wordingEdit = _edits['focusMinutesLabel'];
    if (wordingEdit == null) return super.focusMinutesLabel(m);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'm': () => '$m',
                }
              : <String, String Function()>{
                  'm': () => '$m',
                },
        ) ??
        super.focusMinutesLabel(m);
  }

  @override
  String focusXpOnCompletion(int xp) {
    final wordingEdit = _edits['focusXpOnCompletion'];
    if (wordingEdit == null) return super.focusXpOnCompletion(xp);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'xp': () => '$xp',
                }
              : <String, String Function()>{
                  'xp': () => '$xp',
                },
        ) ??
        super.focusXpOnCompletion(xp);
  }

  @override
  String get focusSessionCompleteTitle => plainWording(_edits['focusSessionCompleteTitle']) ?? super.focusSessionCompleteTitle;

  @override
  String get focusDeepWorkDone => plainWording(_edits['focusDeepWorkDone']) ?? super.focusDeepWorkDone;

  @override
  String focusStayedFocused(String label) {
    final wordingEdit = _edits['focusStayedFocused'];
    if (wordingEdit == null) return super.focusStayedFocused(label);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'label': () => '$label',
                }
              : <String, String Function()>{
                  'label': () => '$label',
                },
        ) ??
        super.focusStayedFocused(label);
  }

  @override
  String get focusGreatWork => plainWording(_edits['focusGreatWork']) ?? super.focusGreatWork;

  @override
  String get focusRitualTitle => plainWording(_edits['focusRitualTitle']) ?? super.focusRitualTitle;

  @override
  String get focusRitualSubtitle => plainWording(_edits['focusRitualSubtitle']) ?? super.focusRitualSubtitle;

  @override
  String get focusRitualPlanWin => plainWording(_edits['focusRitualPlanWin']) ?? super.focusRitualPlanWin;

  @override
  String get focusRitualChooseTask => plainWording(_edits['focusRitualChooseTask']) ?? super.focusRitualChooseTask;

  @override
  String get focusRitualRunSprint => plainWording(_edits['focusRitualRunSprint']) ?? super.focusRitualRunSprint;

  @override
  String focusRitualSprintsLogged(int n) {
    final wordingEdit = _edits['focusRitualSprintsLogged'];
    if (wordingEdit == null) return super.focusRitualSprintsLogged(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                  'n == 1 ? \'\' : \'s\'': () => '${n == 1 ? '' : 's'}',
                },
        ) ??
        super.focusRitualSprintsLogged(n);
  }

  @override
  String get focusRitualReview => plainWording(_edits['focusRitualReview']) ?? super.focusRitualReview;

  @override
  String get focusRitualReviewSubtitle => plainWording(_edits['focusRitualReviewSubtitle']) ?? super.focusRitualReviewSubtitle;

  @override
  String get focusLogSprint => plainWording(_edits['focusLogSprint']) ?? super.focusLogSprint;

  @override
  String get focusResetToday => plainWording(_edits['focusResetToday']) ?? super.focusResetToday;

  @override
  String get focusWhyTitle => plainWording(_edits['focusWhyTitle']) ?? super.focusWhyTitle;

  @override
  String get focusWhySubtitle => plainWording(_edits['focusWhySubtitle']) ?? super.focusWhySubtitle;

  @override
  String get focusIfThenCueTitle => plainWording(_edits['focusIfThenCueTitle']) ?? super.focusIfThenCueTitle;

  @override
  String get focusIfThenCueBody => plainWording(_edits['focusIfThenCueBody']) ?? super.focusIfThenCueBody;

  @override
  String get focusOneTaskTitle => plainWording(_edits['focusOneTaskTitle']) ?? super.focusOneTaskTitle;

  @override
  String get focusOneTaskBody => plainWording(_edits['focusOneTaskBody']) ?? super.focusOneTaskBody;

  @override
  String get focusSprintTitle => plainWording(_edits['focusSprintTitle']) ?? super.focusSprintTitle;

  @override
  String get focusSprintBody => plainWording(_edits['focusSprintBody']) ?? super.focusSprintBody;

  @override
  String get habitDaily => plainWording(_edits['habitDaily']) ?? super.habitDaily;

  @override
  String habitWeeklyTimes(int n) {
    final wordingEdit = _edits['habitWeeklyTimes'];
    if (wordingEdit == null) return super.habitWeeklyTimes(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.habitWeeklyTimes(n);
  }

  @override
  String get goals => plainWording(_edits['goals']) ?? super.goals;

  @override
  String get goalsMatrix => plainWording(_edits['goalsMatrix']) ?? super.goalsMatrix;

  @override
  String get matrixSubtitle => plainWording(_edits['matrixSubtitle']) ?? super.matrixSubtitle;

  @override
  String get matrixUrgent => plainWording(_edits['matrixUrgent']) ?? super.matrixUrgent;

  @override
  String get matrixNotUrgent => plainWording(_edits['matrixNotUrgent']) ?? super.matrixNotUrgent;

  @override
  String get matrixImportant => plainWording(_edits['matrixImportant']) ?? super.matrixImportant;

  @override
  String get matrixNotImportant => plainWording(_edits['matrixNotImportant']) ?? super.matrixNotImportant;

  @override
  String get matrixToday => plainWording(_edits['matrixToday']) ?? super.matrixToday;

  @override
  String get matrixFav => plainWording(_edits['matrixFav']) ?? super.matrixFav;

  @override
  String matrixCarriedOverCount(int n) {
    final wordingEdit = _edits['matrixCarriedOverCount'];
    if (wordingEdit == null) return super.matrixCarriedOverCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.matrixCarriedOverCount(n);
  }

  @override
  String matrixUpcomingCount(int n) {
    final wordingEdit = _edits['matrixUpcomingCount'];
    if (wordingEdit == null) return super.matrixUpcomingCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.matrixUpcomingCount(n);
  }

  @override
  String get matrixAll => plainWording(_edits['matrixAll']) ?? super.matrixAll;

  @override
  String get matrixTapToAdd => plainWording(_edits['matrixTapToAdd']) ?? super.matrixTapToAdd;

  @override
  String get matrixAddAnother => plainWording(_edits['matrixAddAnother']) ?? super.matrixAddAnother;

  @override
  String get matrixAddTask => plainWording(_edits['matrixAddTask']) ?? super.matrixAddTask;

  @override
  String get matrixWhatToDo => plainWording(_edits['matrixWhatToDo']) ?? super.matrixWhatToDo;

  @override
  String get matrixMoveToQuadrant => plainWording(_edits['matrixMoveToQuadrant']) ?? super.matrixMoveToQuadrant;

  @override
  String get taskMoveAction => plainWording(_edits['taskMoveAction']) ?? super.taskMoveAction;

  @override
  String get taskFavAction => plainWording(_edits['taskFavAction']) ?? super.taskFavAction;

  @override
  String get taskUnfavAction => plainWording(_edits['taskUnfavAction']) ?? super.taskUnfavAction;

  @override
  String get taskDetailsAction => plainWording(_edits['taskDetailsAction']) ?? super.taskDetailsAction;

  @override
  String get matrixExpandQuadrant => plainWording(_edits['matrixExpandQuadrant']) ?? super.matrixExpandQuadrant;

  @override
  String get matrixCollapseQuadrant => plainWording(_edits['matrixCollapseQuadrant']) ?? super.matrixCollapseQuadrant;

  @override
  String get matrixDeleteTask => plainWording(_edits['matrixDeleteTask']) ?? super.matrixDeleteTask;

  @override
  String get matrixDeleteSelected => plainWording(_edits['matrixDeleteSelected']) ?? super.matrixDeleteSelected;

  @override
  String matrixSelectedCount(int count) {
    final wordingEdit = _edits['matrixSelectedCount'];
    if (wordingEdit == null) return super.matrixSelectedCount(count);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'count': () => '$count',
                }
              : <String, String Function()>{
                  'count': () => '$count',
                },
        ) ??
        super.matrixSelectedCount(count);
  }

  @override
  String get matrixCompletedTitle => plainWording(_edits['matrixCompletedTitle']) ?? super.matrixCompletedTitle;

  @override
  String get matrixNoCompletedTasks => plainWording(_edits['matrixNoCompletedTasks']) ?? super.matrixNoCompletedTasks;

  @override
  String get matrixNoCompletedTasksDesc => plainWording(_edits['matrixNoCompletedTasksDesc']) ?? super.matrixNoCompletedTasksDesc;

  @override
  String get matrixRestoreTask => plainWording(_edits['matrixRestoreTask']) ?? super.matrixRestoreTask;

  @override
  String get matrixAddMultipleHint => plainWording(_edits['matrixAddMultipleHint']) ?? super.matrixAddMultipleHint;

  @override
  String get matrixAddDetails => plainWording(_edits['matrixAddDetails']) ?? super.matrixAddDetails;

  @override
  String get matrixHideDetails => plainWording(_edits['matrixHideDetails']) ?? super.matrixHideDetails;

  @override
  String get matrixDescriptionHint => plainWording(_edits['matrixDescriptionHint']) ?? super.matrixDescriptionHint;

  @override
  String get matrixTaskDetails => plainWording(_edits['matrixTaskDetails']) ?? super.matrixTaskDetails;

  @override
  String get matrixNoDescription => plainWording(_edits['matrixNoDescription']) ?? super.matrixNoDescription;

  @override
  String get matrixReminderLabel => plainWording(_edits['matrixReminderLabel']) ?? super.matrixReminderLabel;

  @override
  String get matrixReminderPast => plainWording(_edits['matrixReminderPast']) ?? super.matrixReminderPast;

  @override
  String get matrixReminderTimeTitle => plainWording(_edits['matrixReminderTimeTitle']) ?? super.matrixReminderTimeTitle;

  @override
  String matrixReminderEarliest(String time) {
    final wordingEdit = _edits['matrixReminderEarliest'];
    if (wordingEdit == null) return super.matrixReminderEarliest(time);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'time': () => '$time',
                }
              : <String, String Function()>{
                  'time': () => '$time',
                },
        ) ??
        super.matrixReminderEarliest(time);
  }

  @override
  String get matrixReminderAddAnother => plainWording(_edits['matrixReminderAddAnother']) ?? super.matrixReminderAddAnother;

  @override
  String get matrixReminderRemove => plainWording(_edits['matrixReminderRemove']) ?? super.matrixReminderRemove;

  @override
  String get matrixReminderOffsetPast => plainWording(_edits['matrixReminderOffsetPast']) ?? super.matrixReminderOffsetPast;

  @override
  String get matrixExtraRemindersSection => plainWording(_edits['matrixExtraRemindersSection']) ?? super.matrixExtraRemindersSection;

  @override
  String get matrixExtraRemindersHint => plainWording(_edits['matrixExtraRemindersHint']) ?? super.matrixExtraRemindersHint;

  @override
  String get customReminderTitle => plainWording(_edits['customReminderTitle']) ?? super.customReminderTitle;

  @override
  String get customReminderValueHint => plainWording(_edits['customReminderValueHint']) ?? super.customReminderValueHint;

  @override
  String get habitDuplicateTime => plainWording(_edits['habitDuplicateTime']) ?? super.habitDuplicateTime;

  @override
  String habitOffsetFromTime(String time) {
    final wordingEdit = _edits['habitOffsetFromTime'];
    if (wordingEdit == null) return super.habitOffsetFromTime(time);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'time': () => '$time',
                }
              : <String, String Function()>{
                  'time': () => '$time',
                },
        ) ??
        super.habitOffsetFromTime(time);
  }

  @override
  String get habitOffsetTooLarge => plainWording(_edits['habitOffsetTooLarge']) ?? super.habitOffsetTooLarge;

  @override
  String get customReminderAdd => plainWording(_edits['customReminderAdd']) ?? super.customReminderAdd;

  @override
  String get habitOffsetSave => plainWording(_edits['habitOffsetSave']) ?? super.habitOffsetSave;

  @override
  String habitReminderAtPrayer(String prayer) {
    final wordingEdit = _edits['habitReminderAtPrayer'];
    if (wordingEdit == null) return super.habitReminderAtPrayer(prayer);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'prayer': () => '$prayer',
                }
              : <String, String Function()>{
                  'prayer': () => '$prayer',
                },
        ) ??
        super.habitReminderAtPrayer(prayer);
  }

  @override
  String habitReminderBeforePrayer(String prayer, String amount) {
    final wordingEdit = _edits['habitReminderBeforePrayer'];
    if (wordingEdit == null) return super.habitReminderBeforePrayer(prayer, amount);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'prayer': () => '$prayer',
                  '_byAmount(amount)': () => '${S._byAmount(amount)}',
                }
              : <String, String Function()>{
                  'amount': () => '$amount',
                  'prayer': () => '$prayer',
                },
        ) ??
        super.habitReminderBeforePrayer(prayer, amount);
  }

  @override
  String habitReminderAfterPrayer(String prayer, String amount) {
    final wordingEdit = _edits['habitReminderAfterPrayer'];
    if (wordingEdit == null) return super.habitReminderAfterPrayer(prayer, amount);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'prayer': () => '$prayer',
                  '_byAmount(amount)': () => '${S._byAmount(amount)}',
                }
              : <String, String Function()>{
                  'amount': () => '$amount',
                  'prayer': () => '$prayer',
                },
        ) ??
        super.habitReminderAfterPrayer(prayer, amount);
  }

  @override
  String habitReminderRowSemantics(String sentence, String time) {
    final wordingEdit = _edits['habitReminderRowSemantics'];
    if (wordingEdit == null) return super.habitReminderRowSemantics(sentence, time);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'sentence': () => '$sentence',
                  'time': () => '$time',
                }
              : <String, String Function()>{
                  'sentence': () => '$sentence',
                  'time': () => '$time',
                },
        ) ??
        super.habitReminderRowSemantics(sentence, time);
  }

  @override
  String get habitReminderRemove => plainWording(_edits['habitReminderRemove']) ?? super.habitReminderRemove;

  @override
  String get customReminderAlreadyAdded => plainWording(_edits['customReminderAlreadyAdded']) ?? super.customReminderAlreadyAdded;

  @override
  String get unitMinutes => plainWording(_edits['unitMinutes']) ?? super.unitMinutes;

  @override
  String get unitHours => plainWording(_edits['unitHours']) ?? super.unitHours;

  @override
  String get unitDays => plainWording(_edits['unitDays']) ?? super.unitDays;

  @override
  String get matrixReminderMaxReached => plainWording(_edits['matrixReminderMaxReached']) ?? super.matrixReminderMaxReached;

  @override
  String get reminderGateTitle => plainWording(_edits['reminderGateTitle']) ?? super.reminderGateTitle;

  @override
  String get reminderGateBody => plainWording(_edits['reminderGateBody']) ?? super.reminderGateBody;

  @override
  String get reminderGateHabitBody => plainWording(_edits['reminderGateHabitBody']) ?? super.reminderGateHabitBody;

  @override
  String get habitAddAnotherReminder => plainWording(_edits['habitAddAnotherReminder']) ?? super.habitAddAnotherReminder;

  @override
  String get habitAddReminderRow => plainWording(_edits['habitAddReminderRow']) ?? super.habitAddReminderRow;

  @override
  String get habitReminderMaxReached => plainWording(_edits['habitReminderMaxReached']) ?? super.habitReminderMaxReached;

  @override
  String get habitReminderKeepOne => plainWording(_edits['habitReminderKeepOne']) ?? super.habitReminderKeepOne;

  @override
  String get matrixDone => plainWording(_edits['matrixDone']) ?? super.matrixDone;

  @override
  String get matrixUndo => plainWording(_edits['matrixUndo']) ?? super.matrixUndo;

  @override
  String get undo => plainWording(_edits['undo']) ?? super.undo;

  @override
  String matrixTaskDeleted(String taskTitle) {
    final wordingEdit = _edits['matrixTaskDeleted'];
    if (wordingEdit == null) return super.matrixTaskDeleted(taskTitle);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'taskTitle': () => '$taskTitle',
                }
              : <String, String Function()>{
                  'taskTitle': () => '$taskTitle',
                },
        ) ??
        super.matrixTaskDeleted(taskTitle);
  }

  @override
  String get matrixPickADay => plainWording(_edits['matrixPickADay']) ?? super.matrixPickADay;

  @override
  String get matrixNoTasksThisDay => plainWording(_edits['matrixNoTasksThisDay']) ?? super.matrixNoTasksThisDay;

  @override
  String get matrixEditQuadrantTitle => plainWording(_edits['matrixEditQuadrantTitle']) ?? super.matrixEditQuadrantTitle;

  @override
  String get matrixEditQuadrantBody => plainWording(_edits['matrixEditQuadrantBody']) ?? super.matrixEditQuadrantBody;

  @override
  String get matrixEditQuadrantSave => plainWording(_edits['matrixEditQuadrantSave']) ?? super.matrixEditQuadrantSave;

  @override
  String get matrixEditQuadrantCancel => plainWording(_edits['matrixEditQuadrantCancel']) ?? super.matrixEditQuadrantCancel;

  @override
  String get matrixQuadrantColorTitle => plainWording(_edits['matrixQuadrantColorTitle']) ?? super.matrixQuadrantColorTitle;

  @override
  String get matrixQuadrantColorHint => plainWording(_edits['matrixQuadrantColorHint']) ?? super.matrixQuadrantColorHint;

  @override
  String get closetProfileRow => plainWording(_edits['closetProfileRow']) ?? super.closetProfileRow;

  @override
  String get closetCustomize => plainWording(_edits['closetCustomize']) ?? super.closetCustomize;

  @override
  String get closetTitle => plainWording(_edits['closetTitle']) ?? super.closetTitle;

  @override
  String get closetSubtitle => plainWording(_edits['closetSubtitle']) ?? super.closetSubtitle;

  @override
  String get closetCharacterSection => plainWording(_edits['closetCharacterSection']) ?? super.closetCharacterSection;

  @override
  String get closetOwned => plainWording(_edits['closetOwned']) ?? super.closetOwned;

  @override
  String get closetEquipped => plainWording(_edits['closetEquipped']) ?? super.closetEquipped;

  @override
  String get closetEquip => plainWording(_edits['closetEquip']) ?? super.closetEquip;

  @override
  String get closetUnequip => plainWording(_edits['closetUnequip']) ?? super.closetUnequip;

  @override
  String get closetBuy => plainWording(_edits['closetBuy']) ?? super.closetBuy;

  @override
  String get closetBuyConfirmTitle => plainWording(_edits['closetBuyConfirmTitle']) ?? super.closetBuyConfirmTitle;

  @override
  String closetBuyConfirmBody(int cost) {
    final wordingEdit = _edits['closetBuyConfirmBody'];
    if (wordingEdit == null) return super.closetBuyConfirmBody(cost);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'cost': () => '$cost',
                }
              : <String, String Function()>{
                  'cost': () => '$cost',
                },
        ) ??
        super.closetBuyConfirmBody(cost);
  }

  @override
  String get closetNotEnoughGold => plainWording(_edits['closetNotEnoughGold']) ?? super.closetNotEnoughGold;

  @override
  String get closetPurchaseFailed => plainWording(_edits['closetPurchaseFailed']) ?? super.closetPurchaseFailed;

  @override
  String get closetPurchased => plainWording(_edits['closetPurchased']) ?? super.closetPurchased;

  @override
  String get closetCancel => plainWording(_edits['closetCancel']) ?? super.closetCancel;

  @override
  String get closetBandOwned => plainWording(_edits['closetBandOwned']) ?? super.closetBandOwned;

  @override
  String get closetBandReach => plainWording(_edits['closetBandReach']) ?? super.closetBandReach;

  @override
  String get closetBandGoal => plainWording(_edits['closetBandGoal']) ?? super.closetBandGoal;

  @override
  String get closetCharacterEarned => plainWording(_edits['closetCharacterEarned']) ?? super.closetCharacterEarned;

  @override
  String closetCharacterLocked(String requirement) {
    final wordingEdit = _edits['closetCharacterLocked'];
    if (wordingEdit == null) return super.closetCharacterLocked(requirement);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'requirement': () => '$requirement',
                }
              : <String, String Function()>{
                  'requirement': () => '$requirement',
                },
        ) ??
        super.closetCharacterLocked(requirement);
  }

  @override
  String get closetMen => plainWording(_edits['closetMen']) ?? super.closetMen;

  @override
  String get closetWomen => plainWording(_edits['closetWomen']) ?? super.closetWomen;

  @override
  String get closetNoAccessory => plainWording(_edits['closetNoAccessory']) ?? super.closetNoAccessory;

  @override
  String get closetUnlockedByProgress => plainWording(_edits['closetUnlockedByProgress']) ?? super.closetUnlockedByProgress;

  @override
  String closetShortBy(int amount) {
    final wordingEdit = _edits['closetShortBy'];
    if (wordingEdit == null) return super.closetShortBy(amount);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'amount': () => '$amount',
                }
              : <String, String Function()>{
                  'amount': () => '$amount',
                },
        ) ??
        super.closetShortBy(amount);
  }

  @override
  String closetBalanceIs(int gold) {
    final wordingEdit = _edits['closetBalanceIs'];
    if (wordingEdit == null) return super.closetBalanceIs(gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'gold': () => '$gold',
                },
        ) ??
        super.closetBalanceIs(gold);
  }

  @override
  String closetBalanceAfter(int gold) {
    final wordingEdit = _edits['closetBalanceAfter'];
    if (wordingEdit == null) return super.closetBalanceAfter(gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'gold': () => '$gold',
                },
        ) ??
        super.closetBalanceAfter(gold);
  }

  @override
  String closetBalanceOf(int gold, int cost) {
    final wordingEdit = _edits['closetBalanceOf'];
    if (wordingEdit == null) return super.closetBalanceOf(gold, cost);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'gold': () => '$gold',
                  'cost': () => '$cost',
                }
              : <String, String Function()>{
                  'gold': () => '$gold',
                  'cost': () => '$cost',
                },
        ) ??
        super.closetBalanceOf(gold, cost);
  }

  @override
  String closetProgress(int have, int total) {
    final wordingEdit = _edits['closetProgress'];
    if (wordingEdit == null) return super.closetProgress(have, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'have': () => '$have',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'have': () => '$have',
                  'total': () => '$total',
                },
        ) ??
        super.closetProgress(have, total);
  }

  @override
  String closetPriceLater(int cost) {
    final wordingEdit = _edits['closetPriceLater'];
    if (wordingEdit == null) return super.closetPriceLater(cost);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'cost': () => '$cost',
                }
              : <String, String Function()>{
                  'cost': () => '$cost',
                },
        ) ??
        super.closetPriceLater(cost);
  }

  @override
  String get closetSeenByRooms => plainWording(_edits['closetSeenByRooms']) ?? super.closetSeenByRooms;

  @override
  String get rewardsTitle => plainWording(_edits['rewardsTitle']) ?? super.rewardsTitle;

  @override
  String get rewardsCardTitle => plainWording(_edits['rewardsCardTitle']) ?? super.rewardsCardTitle;

  @override
  String get rewardsCardEmpty => plainWording(_edits['rewardsCardEmpty']) ?? super.rewardsCardEmpty;

  @override
  String rewardsCardClosest(int n) {
    final wordingEdit = _edits['rewardsCardClosest'];
    if (wordingEdit == null) return super.rewardsCardClosest(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.rewardsCardClosest(n);
  }

  @override
  String get rewardsEmptyTitle => plainWording(_edits['rewardsEmptyTitle']) ?? super.rewardsEmptyTitle;

  @override
  String get rewardsEmptyBody => plainWording(_edits['rewardsEmptyBody']) ?? super.rewardsEmptyBody;

  @override
  String get rewardsStarterTitle => plainWording(_edits['rewardsStarterTitle']) ?? super.rewardsStarterTitle;

  @override
  String get rewardsWriteMyOwn => plainWording(_edits['rewardsWriteMyOwn']) ?? super.rewardsWriteMyOwn;

  @override
  String get rewardsAdd => plainWording(_edits['rewardsAdd']) ?? super.rewardsAdd;

  @override
  String get rewardsEditTitle => plainWording(_edits['rewardsEditTitle']) ?? super.rewardsEditTitle;

  @override
  String get rewardsSheetBody => plainWording(_edits['rewardsSheetBody']) ?? super.rewardsSheetBody;

  @override
  String get rewardsNameHint => plainWording(_edits['rewardsNameHint']) ?? super.rewardsNameHint;

  @override
  String get rewardsPriceLabel => plainWording(_edits['rewardsPriceLabel']) ?? super.rewardsPriceLabel;

  @override
  String rewardsPriceInvalid(int min, int max) {
    final wordingEdit = _edits['rewardsPriceInvalid'];
    if (wordingEdit == null) return super.rewardsPriceInvalid(min, max);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'min': () => '$min',
                  'max': () => '$max',
                }
              : <String, String Function()>{
                  'min': () => '$min',
                  'max': () => '$max',
                },
        ) ??
        super.rewardsPriceInvalid(min, max);
  }

  @override
  String get rewardsSave => plainWording(_edits['rewardsSave']) ?? super.rewardsSave;

  @override
  String get rewardsCancel => plainWording(_edits['rewardsCancel']) ?? super.rewardsCancel;

  @override
  String get rewardsDelete => plainWording(_edits['rewardsDelete']) ?? super.rewardsDelete;

  @override
  String get rewardsLimitReached => plainWording(_edits['rewardsLimitReached']) ?? super.rewardsLimitReached;

  @override
  String get rewardsListUnavailable => plainWording(_edits['rewardsListUnavailable']) ?? super.rewardsListUnavailable;

  @override
  String get rewardsBalanceUnavailable => plainWording(_edits['rewardsBalanceUnavailable']) ?? super.rewardsBalanceUnavailable;

  @override
  String get rewardsClaimTitle => plainWording(_edits['rewardsClaimTitle']) ?? super.rewardsClaimTitle;

  @override
  String rewardsClaimBody(String name, int cost) {
    final wordingEdit = _edits['rewardsClaimBody'];
    if (wordingEdit == null) return super.rewardsClaimBody(name, cost);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'cost': () => '$cost',
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'cost': () => '$cost',
                  'name': () => '$name',
                },
        ) ??
        super.rewardsClaimBody(name, cost);
  }

  @override
  String get rewardsClaimConfirm => plainWording(_edits['rewardsClaimConfirm']) ?? super.rewardsClaimConfirm;

  @override
  String get rewardsFailed => plainWording(_edits['rewardsFailed']) ?? super.rewardsFailed;

  @override
  String get rewardsClaimedEyebrow => plainWording(_edits['rewardsClaimedEyebrow']) ?? super.rewardsClaimedEyebrow;

  @override
  String rewardsPaid(int cost) {
    final wordingEdit = _edits['rewardsPaid'];
    if (wordingEdit == null) return super.rewardsPaid(cost);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'cost': () => '$cost',
                }
              : <String, String Function()>{
                  'cost': () => '$cost',
                },
        ) ??
        super.rewardsPaid(cost);
  }

  @override
  String rewardsBalanceNow(int gold) {
    final wordingEdit = _edits['rewardsBalanceNow'];
    if (wordingEdit == null) return super.rewardsBalanceNow(gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'gold': () => '$gold',
                },
        ) ??
        super.rewardsBalanceNow(gold);
  }

  @override
  String get rewardsEarnedIt => plainWording(_edits['rewardsEarnedIt']) ?? super.rewardsEarnedIt;

  @override
  String get rewardsGoEnjoy => plainWording(_edits['rewardsGoEnjoy']) ?? super.rewardsGoEnjoy;

  @override
  String rewardsSemantic(String name) {
    final wordingEdit = _edits['rewardsSemantic'];
    if (wordingEdit == null) return super.rewardsSemantic(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.rewardsSemantic(name);
  }

  @override
  String get rewardsDeleteTitle => plainWording(_edits['rewardsDeleteTitle']) ?? super.rewardsDeleteTitle;

  @override
  String rewardsDeleteBody(String name) {
    final wordingEdit = _edits['rewardsDeleteBody'];
    if (wordingEdit == null) return super.rewardsDeleteBody(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.rewardsDeleteBody(name);
  }

  @override
  String get rewardsDeleteConfirm => plainWording(_edits['rewardsDeleteConfirm']) ?? super.rewardsDeleteConfirm;

  @override
  String rewardsDeleted(String name) {
    final wordingEdit = _edits['rewardsDeleted'];
    if (wordingEdit == null) return super.rewardsDeleted(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.rewardsDeleted(name);
  }

  @override
  String get profileEditNameTitle => plainWording(_edits['profileEditNameTitle']) ?? super.profileEditNameTitle;

  @override
  String get profileEditNameBody => plainWording(_edits['profileEditNameBody']) ?? super.profileEditNameBody;

  @override
  String get profileEditNameHint => plainWording(_edits['profileEditNameHint']) ?? super.profileEditNameHint;

  @override
  String get profileEditNameSave => plainWording(_edits['profileEditNameSave']) ?? super.profileEditNameSave;

  @override
  String get profileEditNameCancel => plainWording(_edits['profileEditNameCancel']) ?? super.profileEditNameCancel;

  @override
  String get profileEditNameError => plainWording(_edits['profileEditNameError']) ?? super.profileEditNameError;

  @override
  String get navToday => plainWording(_edits['navToday']) ?? super.navToday;

  @override
  String get navGrid => plainWording(_edits['navGrid']) ?? super.navGrid;

  @override
  String get navMatrix => plainWording(_edits['navMatrix']) ?? super.navMatrix;

  @override
  String get navProfile => plainWording(_edits['navProfile']) ?? super.navProfile;

  @override
  String get navRooms => plainWording(_edits['navRooms']) ?? super.navRooms;

  @override
  String get navProgress => plainWording(_edits['navProgress']) ?? super.navProgress;

  @override
  String get navSettings => plainWording(_edits['navSettings']) ?? super.navSettings;

  @override
  String get navTasbih => plainWording(_edits['navTasbih']) ?? super.navTasbih;

  @override
  String get navRewards => plainWording(_edits['navRewards']) ?? super.navRewards;

  @override
  String get navCloset => plainWording(_edits['navCloset']) ?? super.navCloset;

  @override
  String get navNightReview => plainWording(_edits['navNightReview']) ?? super.navNightReview;

  @override
  String get navYearRecord => plainWording(_edits['navYearRecord']) ?? super.navYearRecord;

  @override
  String get navHeatmap => plainWording(_edits['navHeatmap']) ?? super.navHeatmap;

  @override
  String get navBarSettingsTitle => plainWording(_edits['navBarSettingsTitle']) ?? super.navBarSettingsTitle;

  @override
  String get navBarSettingsIntro => plainWording(_edits['navBarSettingsIntro']) ?? super.navBarSettingsIntro;

  @override
  String get navBarYourTabs => plainWording(_edits['navBarYourTabs']) ?? super.navBarYourTabs;

  @override
  String get navBarAddTabs => plainWording(_edits['navBarAddTabs']) ?? super.navBarAddTabs;

  @override
  String get navBarFull => plainWording(_edits['navBarFull']) ?? super.navBarFull;

  @override
  String get navBarPinned => plainWording(_edits['navBarPinned']) ?? super.navBarPinned;

  @override
  String get navBarRemove => plainWording(_edits['navBarRemove']) ?? super.navBarRemove;

  @override
  String get navBarAdd => plainWording(_edits['navBarAdd']) ?? super.navBarAdd;

  @override
  String get navBarReset => plainWording(_edits['navBarReset']) ?? super.navBarReset;

  @override
  String get navBarLockedTitle => plainWording(_edits['navBarLockedTitle']) ?? super.navBarLockedTitle;

  @override
  String get navBarLockedBody => plainWording(_edits['navBarLockedBody']) ?? super.navBarLockedBody;

  @override
  String get navBarLockedCta => plainWording(_edits['navBarLockedCta']) ?? super.navBarLockedCta;

  @override
  String get navBarHintTitle => plainWording(_edits['navBarHintTitle']) ?? super.navBarHintTitle;

  @override
  String get navBarHintBody => plainWording(_edits['navBarHintBody']) ?? super.navBarHintBody;

  @override
  String get navBadgesTitle => plainWording(_edits['navBadgesTitle']) ?? super.navBadgesTitle;

  @override
  String get navBadgesDesc => plainWording(_edits['navBadgesDesc']) ?? super.navBadgesDesc;

  @override
  String get navBadgeReviewPending => plainWording(_edits['navBadgeReviewPending']) ?? super.navBadgeReviewPending;

  @override
  String get appIconTitle => plainWording(_edits['appIconTitle']) ?? super.appIconTitle;

  @override
  String get appIconNow => plainWording(_edits['appIconNow']) ?? super.appIconNow;

  @override
  String get appIconPreviewing => plainWording(_edits['appIconPreviewing']) ?? super.appIconPreviewing;

  @override
  String get appIconShapeSection => plainWording(_edits['appIconShapeSection']) ?? super.appIconShapeSection;

  @override
  String get appIconColourSection => plainWording(_edits['appIconColourSection']) ?? super.appIconColourSection;

  @override
  String get appIconMoreColours => plainWording(_edits['appIconMoreColours']) ?? super.appIconMoreColours;

  @override
  String get appIconFollowTitle => plainWording(_edits['appIconFollowTitle']) ?? super.appIconFollowTitle;

  @override
  String get appIconFollowBody => plainWording(_edits['appIconFollowBody']) ?? super.appIconFollowBody;

  @override
  String get appIconUse => plainWording(_edits['appIconUse']) ?? super.appIconUse;

  @override
  String get appIconInUse => plainWording(_edits['appIconInUse']) ?? super.appIconInUse;

  @override
  String get appIconFailed => plainWording(_edits['appIconFailed']) ?? super.appIconFailed;

  @override
  String get appIconShapeSeedling => plainWording(_edits['appIconShapeSeedling']) ?? super.appIconShapeSeedling;

  @override
  String get appIconShapeSprout => plainWording(_edits['appIconShapeSprout']) ?? super.appIconShapeSprout;

  @override
  String get appIconShapeGrown => plainWording(_edits['appIconShapeGrown']) ?? super.appIconShapeGrown;

  @override
  String get appIconShapeBloom => plainWording(_edits['appIconShapeBloom']) ?? super.appIconShapeBloom;

  @override
  String get appIconShapeGrownInSentence => plainWording(_edits['appIconShapeGrownInSentence']) ?? super.appIconShapeGrownInSentence;

  @override
  String get appIconShapeBloomInSentence => plainWording(_edits['appIconShapeBloomInSentence']) ?? super.appIconShapeBloomInSentence;

  @override
  String get appIconColourOriginal => plainWording(_edits['appIconColourOriginal']) ?? super.appIconColourOriginal;

  @override
  String get appIconColourRed => plainWording(_edits['appIconColourRed']) ?? super.appIconColourRed;

  @override
  String get appIconColourYellow => plainWording(_edits['appIconColourYellow']) ?? super.appIconColourYellow;

  @override
  String get appIconColourGreen => plainWording(_edits['appIconColourGreen']) ?? super.appIconColourGreen;

  @override
  String get appIconColourBrown => plainWording(_edits['appIconColourBrown']) ?? super.appIconColourBrown;

  @override
  String get appIconColourGrey => plainWording(_edits['appIconColourGrey']) ?? super.appIconColourGrey;

  @override
  String appIconFullDaysLeft(int n) {
    final wordingEdit = _edits['appIconFullDaysLeft'];
    if (wordingEdit == null) return super.appIconFullDaysLeft(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'fullDaysInSentence(n)': () => '${fullDaysInSentence(n)}',
                }
              : <String, String Function()>{
                  'fullDaysInSentence(n)': () => '${fullDaysInSentence(n)}',
                },
        ) ??
        super.appIconFullDaysLeft(n);
  }

  @override
  String appIconNextShape(String shape, int n) {
    final wordingEdit = _edits['appIconNextShape'];
    if (wordingEdit == null) return super.appIconNextShape(shape, n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'shape': () => '$shape',
                  'fullDaysInSentence(n)': () => '${fullDaysInSentence(n)}',
                }
              : <String, String Function()>{
                  'shape': () => '$shape',
                  'n == 1 ? \'1 more full day\' : \'\$n more full days\'': () => '${n == 1 ? '1 more full day' : '$n more full days'}',
                },
        ) ??
        super.appIconNextShape(shape, n);
  }

  @override
  String get appIconAllShapes => plainWording(_edits['appIconAllShapes']) ?? super.appIconAllShapes;

  @override
  String get appIconFullDayRule => plainWording(_edits['appIconFullDayRule']) ?? super.appIconFullDayRule;

  @override
  String get appIconSeasonSection => plainWording(_edits['appIconSeasonSection']) ?? super.appIconSeasonSection;

  @override
  String get appIconRamadan => plainWording(_edits['appIconRamadan']) ?? super.appIconRamadan;

  @override
  String get appIconRamadanLocked => plainWording(_edits['appIconRamadanLocked']) ?? super.appIconRamadanLocked;

  @override
  String get appIconRamadanOpen => plainWording(_edits['appIconRamadanOpen']) ?? super.appIconRamadanOpen;

  @override
  String appIconRamadanSoon(int n) {
    final wordingEdit = _edits['appIconRamadanSoon'];
    if (wordingEdit == null) return super.appIconRamadanSoon(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysInSentence(n)': () => '${daysInSentence(n)}',
                }
              : <String, String Function()>{
                  'daysInSentence(n)': () => '${daysInSentence(n)}',
                },
        ) ??
        super.appIconRamadanSoon(n);
  }

  @override
  String get appIconRamadanNote => plainWording(_edits['appIconRamadanNote']) ?? super.appIconRamadanNote;

  @override
  String get appIconOfferTitle => plainWording(_edits['appIconOfferTitle']) ?? super.appIconOfferTitle;

  @override
  String appIconOfferBody(String colour) {
    final wordingEdit = _edits['appIconOfferBody'];
    if (wordingEdit == null) return super.appIconOfferBody(colour);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'colour': () => '$colour',
                }
              : <String, String Function()>{
                  'colour': () => '$colour',
                },
        ) ??
        super.appIconOfferBody(colour);
  }

  @override
  String get appIconOfferBodyOriginal => plainWording(_edits['appIconOfferBodyOriginal']) ?? super.appIconOfferBodyOriginal;

  @override
  String get appIconOfferBodyCustom => plainWording(_edits['appIconOfferBodyCustom']) ?? super.appIconOfferBodyCustom;

  @override
  String get appIconOfferAlways => plainWording(_edits['appIconOfferAlways']) ?? super.appIconOfferAlways;

  @override
  String get appIconOfferYes => plainWording(_edits['appIconOfferYes']) ?? super.appIconOfferYes;

  @override
  String get appIconOfferNo => plainWording(_edits['appIconOfferNo']) ?? super.appIconOfferNo;

  @override
  String get plantGrewTitle => plainWording(_edits['plantGrewTitle']) ?? super.plantGrewTitle;

  @override
  String get plantBloomedTitle => plainWording(_edits['plantBloomedTitle']) ?? super.plantBloomedTitle;

  @override
  String plantGrewBody(int n) {
    final wordingEdit = _edits['plantGrewBody'];
    if (wordingEdit == null) return super.plantGrewBody(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'fullDaysInSentence(n)': () => '${fullDaysInSentence(n)}',
                }
              : <String, String Function()>{
                  'fullDaysInSentence(n)': () => '${fullDaysInSentence(n)}',
                },
        ) ??
        super.plantGrewBody(n);
  }

  @override
  String get plantGrewUse => plainWording(_edits['plantGrewUse']) ?? super.plantGrewUse;

  @override
  String get plantGrewLater => plainWording(_edits['plantGrewLater']) ?? super.plantGrewLater;

  @override
  String get ramadanCardTitle => plainWording(_edits['ramadanCardTitle']) ?? super.ramadanCardTitle;

  @override
  String get ramadanCardBody => plainWording(_edits['ramadanCardBody']) ?? super.ramadanCardBody;

  @override
  String get getStartedTitle => plainWording(_edits['getStartedTitle']) ?? super.getStartedTitle;

  @override
  String guideStepCount(int step, int total) {
    final wordingEdit = _edits['guideStepCount'];
    if (wordingEdit == null) return super.guideStepCount(step, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'step': () => '$step',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'step': () => '$step',
                  'total': () => '$total',
                },
        ) ??
        super.guideStepCount(step, total);
  }

  @override
  String get getStartedAddHabit => plainWording(_edits['getStartedAddHabit']) ?? super.getStartedAddHabit;

  @override
  String get getStartedAddTask => plainWording(_edits['getStartedAddTask']) ?? super.getStartedAddTask;

  @override
  String get coachMarkSkip => plainWording(_edits['coachMarkSkip']) ?? super.coachMarkSkip;

  @override
  String get guideNeedsHabitFirst => plainWording(_edits['guideNeedsHabitFirst']) ?? super.guideNeedsHabitFirst;

  @override
  String get guideHiddenUndoHint => plainWording(_edits['guideHiddenUndoHint']) ?? super.guideHiddenUndoHint;

  @override
  String get squareNotReadyYet => plainWording(_edits['squareNotReadyYet']) ?? super.squareNotReadyYet;

  @override
  String get firstRunOfferTitle => plainWording(_edits['firstRunOfferTitle']) ?? super.firstRunOfferTitle;

  @override
  String get firstRunOfferBodyLead => plainWording(_edits['firstRunOfferBodyLead']) ?? super.firstRunOfferBodyLead;

  @override
  String get firstRunOfferBodyEmphasis => plainWording(_edits['firstRunOfferBodyEmphasis']) ?? super.firstRunOfferBodyEmphasis;

  @override
  String get firstRunOfferYes => plainWording(_edits['firstRunOfferYes']) ?? super.firstRunOfferYes;

  @override
  String get firstRunOfferLater => plainWording(_edits['firstRunOfferLater']) ?? super.firstRunOfferLater;

  @override
  String get rankUpEyebrow => plainWording(_edits['rankUpEyebrow']) ?? super.rankUpEyebrow;

  @override
  String rankUpLadderPosition(int rank, int total) {
    final wordingEdit = _edits['rankUpLadderPosition'];
    if (wordingEdit == null) return super.rankUpLadderPosition(rank, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'rank': () => '$rank',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'rank': () => '$rank',
                  'total': () => '$total',
                },
        ) ??
        super.rankUpLadderPosition(rank, total);
  }

  @override
  String get rankUpMarkGrew => plainWording(_edits['rankUpMarkGrew']) ?? super.rankUpMarkGrew;

  @override
  String rankUpNextAtLevel(int level) {
    final wordingEdit = _edits['rankUpNextAtLevel'];
    if (wordingEdit == null) return super.rankUpNextAtLevel(level);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'level': () => '$level',
                }
              : <String, String Function()>{
                  'level': () => '$level',
                },
        ) ??
        super.rankUpNextAtLevel(level);
  }

  @override
  String get rankUpSummitLine => plainWording(_edits['rankUpSummitLine']) ?? super.rankUpSummitLine;

  @override
  String rankUpSemantic(String title, int rank, int total) {
    final wordingEdit = _edits['rankUpSemantic'];
    if (wordingEdit == null) return super.rankUpSemantic(title, rank, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'title': () => '$title',
                  'rank': () => '$rank',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'title': () => '$title',
                  'rank': () => '$rank',
                  'total': () => '$total',
                },
        ) ??
        super.rankUpSemantic(title, rank, total);
  }

  @override
  String get gridTitle => plainWording(_edits['gridTitle']) ?? super.gridTitle;

  @override
  String get gridSlogan => plainWording(_edits['gridSlogan']) ?? super.gridSlogan;

  @override
  String get gridThisWeek => plainWording(_edits['gridThisWeek']) ?? super.gridThisWeek;

  @override
  String get gridGreenSquares => plainWording(_edits['gridGreenSquares']) ?? super.gridGreenSquares;

  @override
  String get gridPoints => plainWording(_edits['gridPoints']) ?? super.gridPoints;

  @override
  String get gridComplete => plainWording(_edits['gridComplete']) ?? super.gridComplete;

  @override
  String get gridWeekFilled => plainWording(_edits['gridWeekFilled']) ?? super.gridWeekFilled;

  @override
  String get gridPerfectDay => plainWording(_edits['gridPerfectDay']) ?? super.gridPerfectDay;

  @override
  String gridGreensToday(int n) {
    final wordingEdit = _edits['gridGreensToday'];
    if (wordingEdit == null) return super.gridGreensToday(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.gridGreensToday(n);
  }

  @override
  String gridOfHabitsToday(int total) {
    final wordingEdit = _edits['gridOfHabitsToday'];
    if (wordingEdit == null) return super.gridOfHabitsToday(total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'total': () => '$total',
                },
        ) ??
        super.gridOfHabitsToday(total);
  }

  @override
  String gridGreenSquaresThisWeek(int n) {
    final wordingEdit = _edits['gridGreenSquaresThisWeek'];
    if (wordingEdit == null) return super.gridGreenSquaresThisWeek(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                  'gridGreenSquaresCount(n)': () => '${gridGreenSquaresCount(n)}',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                  'gridGreenSquaresCount(n)': () => '${gridGreenSquaresCount(n)}',
                },
        ) ??
        super.gridGreenSquaresThisWeek(n);
  }

  @override
  String get gridTapHint => plainWording(_edits['gridTapHint']) ?? super.gridTapHint;

  @override
  String get tasbihTitle => plainWording(_edits['tasbihTitle']) ?? super.tasbihTitle;

  @override
  String get tasbihTapHint => plainWording(_edits['tasbihTapHint']) ?? super.tasbihTapHint;

  @override
  String get tasbihCustom => plainWording(_edits['tasbihCustom']) ?? super.tasbihCustom;

  @override
  String get tasbihCustomTitle => plainWording(_edits['tasbihCustomTitle']) ?? super.tasbihCustomTitle;

  @override
  String get tasbihCustomCancel => plainWording(_edits['tasbihCustomCancel']) ?? super.tasbihCustomCancel;

  @override
  String get tasbihCustomSet => plainWording(_edits['tasbihCustomSet']) ?? super.tasbihCustomSet;

  @override
  String get tasbihReset => plainWording(_edits['tasbihReset']) ?? super.tasbihReset;

  @override
  String get tasbihResetDone => plainWording(_edits['tasbihResetDone']) ?? super.tasbihResetDone;

  @override
  String tasbihMarkHabit(String name) {
    final wordingEdit = _edits['tasbihMarkHabit'];
    if (wordingEdit == null) return super.tasbihMarkHabit(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.tasbihMarkHabit(name);
  }

  @override
  String get tasbihMarked => plainWording(_edits['tasbihMarked']) ?? super.tasbihMarked;

  @override
  String get gridRewardHint => plainWording(_edits['gridRewardHint']) ?? super.gridRewardHint;

  @override
  String get gridPastDayHint => plainWording(_edits['gridPastDayHint']) ?? super.gridPastDayHint;

  @override
  String get gridRestorableDayHint => plainWording(_edits['gridRestorableDayHint']) ?? super.gridRestorableDayHint;

  @override
  String get gridMarkRestored => plainWording(_edits['gridMarkRestored']) ?? super.gridMarkRestored;

  @override
  String get gridClearMarkTitle => plainWording(_edits['gridClearMarkTitle']) ?? super.gridClearMarkTitle;

  @override
  String gridClearMarkBody(String habitName, int xp, int gold) {
    final wordingEdit = _edits['gridClearMarkBody'];
    if (wordingEdit == null) return super.gridClearMarkBody(habitName, xp, gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                },
        ) ??
        super.gridClearMarkBody(habitName, xp, gold);
  }

  @override
  String get gridClearPastMarkTitle => plainWording(_edits['gridClearPastMarkTitle']) ?? super.gridClearPastMarkTitle;

  @override
  String gridClearPastMarkBody(String habitName, String dayLabel) {
    final wordingEdit = _edits['gridClearPastMarkBody'];
    if (wordingEdit == null) return super.gridClearPastMarkBody(habitName, dayLabel);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                  'dayLabel': () => '$dayLabel',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                  'dayLabel': () => '$dayLabel',
                },
        ) ??
        super.gridClearPastMarkBody(habitName, dayLabel);
  }

  @override
  String gridClearMarkBodyNoReward(String habitName) {
    final wordingEdit = _edits['gridClearMarkBodyNoReward'];
    if (wordingEdit == null) return super.gridClearMarkBodyNoReward(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.gridClearMarkBodyNoReward(habitName);
  }

  @override
  String get gridClearMarkConfirm => plainWording(_edits['gridClearMarkConfirm']) ?? super.gridClearMarkConfirm;

  @override
  String get gridMarkCleared => plainWording(_edits['gridMarkCleared']) ?? super.gridMarkCleared;

  @override
  String get gridNotYetActiveHint {
    final wordingEdit = _edits['gridNotYetActiveHint'];
    if (wordingEdit == null) return super.gridNotYetActiveHint;
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  '_cutoffClockAr': () => '$_cutoffClockAr',
                }
              : <String, String Function()>{
                  '_cutoffClockEn': () => '$_cutoffClockEn',
                },
        ) ??
        super.gridNotYetActiveHint;
  }

  @override
  String get gridEmptyTitle => plainWording(_edits['gridEmptyTitle']) ?? super.gridEmptyTitle;

  @override
  String get gridEmptyDesc => plainWording(_edits['gridEmptyDesc']) ?? super.gridEmptyDesc;

  @override
  String get gridEditSquare => plainWording(_edits['gridEditSquare']) ?? super.gridEditSquare;

  @override
  String get gridNoteLabel => plainWording(_edits['gridNoteLabel']) ?? super.gridNoteLabel;

  @override
  String get gridNoteLocked => plainWording(_edits['gridNoteLocked']) ?? super.gridNoteLocked;

  @override
  String get gridNoteHint => plainWording(_edits['gridNoteHint']) ?? super.gridNoteHint;

  @override
  String get gridSave => plainWording(_edits['gridSave']) ?? super.gridSave;

  @override
  String get gridFutureDay => plainWording(_edits['gridFutureDay']) ?? super.gridFutureDay;

  @override
  String get gridSquareDoneFromToday => plainWording(_edits['gridSquareDoneFromToday']) ?? super.gridSquareDoneFromToday;

  @override
  String get gridSquareKeptToday => plainWording(_edits['gridSquareKeptToday']) ?? super.gridSquareKeptToday;

  @override
  String get gridSquarePartlyDoneFromToday => plainWording(_edits['gridSquarePartlyDoneFromToday']) ?? super.gridSquarePartlyDoneFromToday;

  @override
  String get gridJournalTitle => plainWording(_edits['gridJournalTitle']) ?? super.gridJournalTitle;

  @override
  String get gridJournalEmpty => plainWording(_edits['gridJournalEmpty']) ?? super.gridJournalEmpty;

  @override
  String get gridJournalSearchHint => plainWording(_edits['gridJournalSearchHint']) ?? super.gridJournalSearchHint;

  @override
  String get gridJournalNoResults => plainWording(_edits['gridJournalNoResults']) ?? super.gridJournalNoResults;

  @override
  String get gridJournalFilterAll => plainWording(_edits['gridJournalFilterAll']) ?? super.gridJournalFilterAll;

  @override
  String get gridJournalDeletedHabit => plainWording(_edits['gridJournalDeletedHabit']) ?? super.gridJournalDeletedHabit;

  @override
  String get heatmapTitle => plainWording(_edits['heatmapTitle']) ?? super.heatmapTitle;

  @override
  String get heatmapSubtitle => plainWording(_edits['heatmapSubtitle']) ?? super.heatmapSubtitle;

  @override
  String get heatmapTotalGreen => plainWording(_edits['heatmapTotalGreen']) ?? super.heatmapTotalGreen;

  @override
  String get heatmapActiveDays => plainWording(_edits['heatmapActiveDays']) ?? super.heatmapActiveDays;

  @override
  String get heatmapBestDay => plainWording(_edits['heatmapBestDay']) ?? super.heatmapBestDay;

  @override
  String get heatmapWeakestDay => plainWording(_edits['heatmapWeakestDay']) ?? super.heatmapWeakestDay;

  @override
  String get heatmapLess => plainWording(_edits['heatmapLess']) ?? super.heatmapLess;

  @override
  String get heatmapMore => plainWording(_edits['heatmapMore']) ?? super.heatmapMore;

  @override
  String get gridSectionBuild => plainWording(_edits['gridSectionBuild']) ?? super.gridSectionBuild;

  @override
  String get gridSectionQuit => plainWording(_edits['gridSectionQuit']) ?? super.gridSectionQuit;

  @override
  String gridFullRow(String name) {
    final wordingEdit = _edits['gridFullRow'];
    if (wordingEdit == null) return super.gridFullRow(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.gridFullRow(name);
  }

  @override
  String get perfectDayMsg => plainWording(_edits['perfectDayMsg']) ?? super.perfectDayMsg;

  @override
  String get weeklyRecapTitle => plainWording(_edits['weeklyRecapTitle']) ?? super.weeklyRecapTitle;

  @override
  String get weeklyNoteOfferAsk => plainWording(_edits['weeklyNoteOfferAsk']) ?? super.weeklyNoteOfferAsk;

  @override
  String get weeklyNoteOfferYes => plainWording(_edits['weeklyNoteOfferYes']) ?? super.weeklyNoteOfferYes;

  @override
  String get weeklyNoteOfferNo => plainWording(_edits['weeklyNoteOfferNo']) ?? super.weeklyNoteOfferNo;

  @override
  String get weeklyRecapThisWeek => plainWording(_edits['weeklyRecapThisWeek']) ?? super.weeklyRecapThisWeek;

  @override
  String get weeklyRecapLastWeek => plainWording(_edits['weeklyRecapLastWeek']) ?? super.weeklyRecapLastWeek;

  @override
  String weeklyRecapNeedsLove(String name) {
    final wordingEdit = _edits['weeklyRecapNeedsLove'];
    if (wordingEdit == null) return super.weeklyRecapNeedsLove(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.weeklyRecapNeedsLove(name);
  }

  @override
  String get weeklyRecapUp => plainWording(_edits['weeklyRecapUp']) ?? super.weeklyRecapUp;

  @override
  String get weeklyRecapSame => plainWording(_edits['weeklyRecapSame']) ?? super.weeklyRecapSame;

  @override
  String get weeklyRecapDown => plainWording(_edits['weeklyRecapDown']) ?? super.weeklyRecapDown;

  @override
  String get weeklyRecapFirst => plainWording(_edits['weeklyRecapFirst']) ?? super.weeklyRecapFirst;

  @override
  String get weeklyRecapPerHabit => plainWording(_edits['weeklyRecapPerHabit']) ?? super.weeklyRecapPerHabit;

  @override
  String get weeklyRecapTrend => plainWording(_edits['weeklyRecapTrend']) ?? super.weeklyRecapTrend;

  @override
  String get weeklyRecapPremiumTeaser => plainWording(_edits['weeklyRecapPremiumTeaser']) ?? super.weeklyRecapPremiumTeaser;

  @override
  String get insightsTitle => plainWording(_edits['insightsTitle']) ?? super.insightsTitle;

  @override
  String get insightsWindow => plainWording(_edits['insightsWindow']) ?? super.insightsWindow;

  @override
  String get insightsPerHabitTitle => plainWording(_edits['insightsPerHabitTitle']) ?? super.insightsPerHabitTitle;

  @override
  String insightWeekdayMiss(String habit, String weekday) {
    final wordingEdit = _edits['insightWeekdayMiss'];
    if (wordingEdit == null) return super.insightWeekdayMiss(habit, weekday);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habit': () => '$habit',
                  'weekday': () => '$weekday',
                }
              : <String, String Function()>{
                  'habit': () => '$habit',
                  'weekday': () => '$weekday',
                },
        ) ??
        super.insightWeekdayMiss(habit, weekday);
  }

  @override
  String insightStrongestDay(String weekday) {
    final wordingEdit = _edits['insightStrongestDay'];
    if (wordingEdit == null) return super.insightStrongestDay(weekday);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'weekday': () => '$weekday',
                }
              : <String, String Function()>{
                  'weekday': () => '$weekday',
                },
        ) ??
        super.insightStrongestDay(weekday);
  }

  @override
  String insightMostConsistent(String habit) {
    final wordingEdit = _edits['insightMostConsistent'];
    if (wordingEdit == null) return super.insightMostConsistent(habit);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habit': () => '$habit',
                }
              : <String, String Function()>{
                  'habit': () => '$habit',
                },
        ) ??
        super.insightMostConsistent(habit);
  }

  @override
  String insightNeedsPush(String habit) {
    final wordingEdit = _edits['insightNeedsPush'];
    if (wordingEdit == null) return super.insightNeedsPush(habit);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habit': () => '$habit',
                }
              : <String, String Function()>{
                  'habit': () => '$habit',
                },
        ) ??
        super.insightNeedsPush(habit);
  }

  @override
  String get insightsEmpty => plainWording(_edits['insightsEmpty']) ?? super.insightsEmpty;

  @override
  String get insightsPremiumTitle => plainWording(_edits['insightsPremiumTitle']) ?? super.insightsPremiumTitle;

  @override
  String get insightsPremiumBody => plainWording(_edits['insightsPremiumBody']) ?? super.insightsPremiumBody;

  @override
  String get insightsBreakdownTeaser => plainWording(_edits['insightsBreakdownTeaser']) ?? super.insightsBreakdownTeaser;

  @override
  String get insightDetailByDay => plainWording(_edits['insightDetailByDay']) ?? super.insightDetailByDay;

  @override
  String get insightDetailOwnDays => plainWording(_edits['insightDetailOwnDays']) ?? super.insightDetailOwnDays;

  @override
  String get insightDetailByWeek => plainWording(_edits['insightDetailByWeek']) ?? super.insightDetailByWeek;

  @override
  String insightCountOf(int done, int total) {
    final wordingEdit = _edits['insightCountOf'];
    if (wordingEdit == null) return super.insightCountOf(done, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                },
        ) ??
        super.insightCountOf(done, total);
  }

  @override
  String insightQuotaWeeks(String habit, int met, int weeks) {
    final wordingEdit = _edits['insightQuotaWeeks'];
    if (wordingEdit == null) return super.insightQuotaWeeks(habit, met, weeks);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habit': () => '$habit',
                  '_metOfWeeks(met, weeks)': () => '${_metOfWeeks(met, weeks)}',
                }
              : <String, String Function()>{
                  'habit': () => '$habit',
                  'met': () => '$met',
                  'weeks': () => '$weeks',
                  'weeks == 1 ? \'week\' : \'weeks\'': () => '${weeks == 1 ? 'week' : 'weeks'}',
                },
        ) ??
        super.insightQuotaWeeks(habit, met, weeks);
  }

  @override
  String insightQuotaAverage(int target) {
    final wordingEdit = _edits['insightQuotaAverage'];
    if (wordingEdit == null) return super.insightQuotaAverage(target);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'target': () => '$target',
                }
              : <String, String Function()>{
                  'target': () => '$target',
                },
        ) ??
        super.insightQuotaAverage(target);
  }

  @override
  String get insightTipQuotaWeeks => plainWording(_edits['insightTipQuotaWeeks']) ?? super.insightTipQuotaWeeks;

  @override
  String get insightDetailCompare => plainWording(_edits['insightDetailCompare']) ?? super.insightDetailCompare;

  @override
  String get insightTipMostConsistent => plainWording(_edits['insightTipMostConsistent']) ?? super.insightTipMostConsistent;

  @override
  String get insightTipNeedsPush => plainWording(_edits['insightTipNeedsPush']) ?? super.insightTipNeedsPush;

  @override
  String insightTipWeekdayMiss(String weekday) {
    final wordingEdit = _edits['insightTipWeekdayMiss'];
    if (wordingEdit == null) return super.insightTipWeekdayMiss(weekday);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'weekday': () => '$weekday',
                }
              : <String, String Function()>{
                  'weekday': () => '$weekday',
                },
        ) ??
        super.insightTipWeekdayMiss(weekday);
  }

  @override
  String get insightTipStrongestDay => plainWording(_edits['insightTipStrongestDay']) ?? super.insightTipStrongestDay;

  @override
  String insightWindowWithDates(String start, String end) {
    final wordingEdit = _edits['insightWindowWithDates'];
    if (wordingEdit == null) return super.insightWindowWithDates(start, end);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'start': () => '$start',
                  'end': () => '$end',
                }
              : <String, String Function()>{
                  'start': () => '$start',
                  'end': () => '$end',
                },
        ) ??
        super.insightWindowWithDates(start, end);
  }

  @override
  String insightPerfectRecord(int n) {
    final wordingEdit = _edits['insightPerfectRecord'];
    if (wordingEdit == null) return super.insightPerfectRecord(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.insightPerfectRecord(n);
  }

  @override
  String insightMostConsistentCompare(String habit, int mine, int theirs) {
    final wordingEdit = _edits['insightMostConsistentCompare'];
    if (wordingEdit == null) return super.insightMostConsistentCompare(habit, mine, theirs);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'mine': () => '$mine',
                  'theirs': () => '$theirs',
                  'habit': () => '$habit',
                }
              : <String, String Function()>{
                  'mine': () => '$mine',
                  'theirs': () => '$theirs',
                  'habit': () => '$habit',
                },
        ) ??
        super.insightMostConsistentCompare(habit, mine, theirs);
  }

  @override
  String insightNeedsPushCompare(String habit, int mine, int theirs) {
    final wordingEdit = _edits['insightNeedsPushCompare'];
    if (wordingEdit == null) return super.insightNeedsPushCompare(habit, mine, theirs);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'mine': () => '$mine',
                  'theirs': () => '$theirs',
                  'habit': () => '$habit',
                }
              : <String, String Function()>{
                  'mine': () => '$mine',
                  'theirs': () => '$theirs',
                  'habit': () => '$habit',
                },
        ) ??
        super.insightNeedsPushCompare(habit, mine, theirs);
  }

  @override
  String get insightOnlyHabitTracked => plainWording(_edits['insightOnlyHabitTracked']) ?? super.insightOnlyHabitTracked;

  @override
  String get historyLockedCta => plainWording(_edits['historyLockedCta']) ?? super.historyLockedCta;

  @override
  String get roomLobbyPill => plainWording(_edits['roomLobbyPill']) ?? super.roomLobbyPill;

  @override
  String get roomStartsTomorrowPill => plainWording(_edits['roomStartsTomorrowPill']) ?? super.roomStartsTomorrowPill;

  @override
  String roomLobbyBanner(int count) {
    final wordingEdit = _edits['roomLobbyBanner'];
    if (wordingEdit == null) return super.roomLobbyBanner(count);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'count': () => '$count',
                }
              : <String, String Function()>{
                  'count': () => '$count',
                },
        ) ??
        super.roomLobbyBanner(count);
  }

  @override
  String get roomLobbyLeaderHint => plainWording(_edits['roomLobbyLeaderHint']) ?? super.roomLobbyLeaderHint;

  @override
  String get roomPickStartTimeAction => plainWording(_edits['roomPickStartTimeAction']) ?? super.roomPickStartTimeAction;

  @override
  String get roomWaitingForLeaderSchedule => plainWording(_edits['roomWaitingForLeaderSchedule']) ?? super.roomWaitingForLeaderSchedule;

  @override
  String get roomScheduleTitle => plainWording(_edits['roomScheduleTitle']) ?? super.roomScheduleTitle;

  @override
  String get roomScheduleBody => plainWording(_edits['roomScheduleBody']) ?? super.roomScheduleBody;

  @override
  String get roomScheduleQuick1Hour => plainWording(_edits['roomScheduleQuick1Hour']) ?? super.roomScheduleQuick1Hour;

  @override
  String get roomScheduleTomorrowMorning => plainWording(_edits['roomScheduleTomorrowMorning']) ?? super.roomScheduleTomorrowMorning;

  @override
  String get roomScheduleTomorrowEvening => plainWording(_edits['roomScheduleTomorrowEvening']) ?? super.roomScheduleTomorrowEvening;

  @override
  String get roomScheduleCustomAction => plainWording(_edits['roomScheduleCustomAction']) ?? super.roomScheduleCustomAction;

  @override
  String get roomScheduleNotFuture => plainWording(_edits['roomScheduleNotFuture']) ?? super.roomScheduleNotFuture;

  @override
  String get roomCountdownTitle => plainWording(_edits['roomCountdownTitle']) ?? super.roomCountdownTitle;

  @override
  String roomCountdownAt(String when) {
    final wordingEdit = _edits['roomCountdownAt'];
    if (wordingEdit == null) return super.roomCountdownAt(when);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'when': () => '$when',
                }
              : <String, String Function()>{
                  'when': () => '$when',
                },
        ) ??
        super.roomCountdownAt(when);
  }

  @override
  String get roomCountdownDaysLabel => plainWording(_edits['roomCountdownDaysLabel']) ?? super.roomCountdownDaysLabel;

  @override
  String get roomCountdownHoursLabel => plainWording(_edits['roomCountdownHoursLabel']) ?? super.roomCountdownHoursLabel;

  @override
  String get roomCountdownMinLabel => plainWording(_edits['roomCountdownMinLabel']) ?? super.roomCountdownMinLabel;

  @override
  String get roomCountdownSecLabel => plainWording(_edits['roomCountdownSecLabel']) ?? super.roomCountdownSecLabel;

  @override
  String get roomChangeTimeAction => plainWording(_edits['roomChangeTimeAction']) ?? super.roomChangeTimeAction;

  @override
  String get roomStartNowAction => plainWording(_edits['roomStartNowAction']) ?? super.roomStartNowAction;

  @override
  String roomStartsInCompact(String compact) {
    final wordingEdit = _edits['roomStartsInCompact'];
    if (wordingEdit == null) return super.roomStartsInCompact(compact);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'compact': () => '$compact',
                }
              : <String, String Function()>{
                  'compact': () => '$compact',
                },
        ) ??
        super.roomStartsInCompact(compact);
  }

  @override
  String get roomStartAction => plainWording(_edits['roomStartAction']) ?? super.roomStartAction;

  @override
  String get roomStartConfirmTitle => plainWording(_edits['roomStartConfirmTitle']) ?? super.roomStartConfirmTitle;

  @override
  String get roomStartConfirmBody => plainWording(_edits['roomStartConfirmBody']) ?? super.roomStartConfirmBody;

  @override
  String get roomStartsTomorrowBanner => plainWording(_edits['roomStartsTomorrowBanner']) ?? super.roomStartsTomorrowBanner;

  @override
  String get roomEndedTitle => plainWording(_edits['roomEndedTitle']) ?? super.roomEndedTitle;

  @override
  String get roomEndedBody => plainWording(_edits['roomEndedBody']) ?? super.roomEndedBody;

  @override
  String get roomPlaceFirst => plainWording(_edits['roomPlaceFirst']) ?? super.roomPlaceFirst;

  @override
  String get roomPlaceFirstTied => plainWording(_edits['roomPlaceFirstTied']) ?? super.roomPlaceFirstTied;

  @override
  String roomPlaceTied(int rank) {
    final wordingEdit = _edits['roomPlaceTied'];
    if (wordingEdit == null) return super.roomPlaceTied(rank);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'rank': () => '$rank',
                }
              : <String, String Function()>{
                  'rank': () => '$rank',
                },
        ) ??
        super.roomPlaceTied(rank);
  }

  @override
  String get roomPlaceNone => plainWording(_edits['roomPlaceNone']) ?? super.roomPlaceNone;

  @override
  String get notifLocationResolving => plainWording(_edits['notifLocationResolving']) ?? super.notifLocationResolving;

  @override
  String get notifLocationSetGeneric => plainWording(_edits['notifLocationSetGeneric']) ?? super.notifLocationSetGeneric;

  @override
  String get roomBoostHint => plainWording(_edits['roomBoostHint']) ?? super.roomBoostHint;

  @override
  String get historyLockedBody => plainWording(_edits['historyLockedBody']) ?? super.historyLockedBody;

  @override
  String get demoGateExample => plainWording(_edits['demoGateExample']) ?? super.demoGateExample;

  @override
  String get demoGateMonthTitle => plainWording(_edits['demoGateMonthTitle']) ?? super.demoGateMonthTitle;

  @override
  String get demoGatePerfectStamp => plainWording(_edits['demoGatePerfectStamp']) ?? super.demoGatePerfectStamp;

  @override
  String get demoGateCta => plainWording(_edits['demoGateCta']) ?? super.demoGateCta;

  @override
  String get demoGateNotNow => plainWording(_edits['demoGateNotNow']) ?? super.demoGateNotNow;

  @override
  String get heatmapDayEmpty => plainWording(_edits['heatmapDayEmpty']) ?? super.heatmapDayEmpty;

  @override
  String get heatmapUpgradeTitle => plainWording(_edits['heatmapUpgradeTitle']) ?? super.heatmapUpgradeTitle;

  @override
  String heatmapUpgradeBody(int freeMonths) {
    final wordingEdit = _edits['heatmapUpgradeBody'];
    if (wordingEdit == null) return super.heatmapUpgradeBody(freeMonths);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'freeMonths': () => '$freeMonths',
                }
              : <String, String Function()>{
                  'freeMonths': () => '$freeMonths',
                },
        ) ??
        super.heatmapUpgradeBody(freeMonths);
  }

  @override
  String get nightReviewTitle => plainWording(_edits['nightReviewTitle']) ?? super.nightReviewTitle;

  @override
  String get nightReviewHistoryTitle => plainWording(_edits['nightReviewHistoryTitle']) ?? super.nightReviewHistoryTitle;

  @override
  String get nightReviewHistoryEmpty => plainWording(_edits['nightReviewHistoryEmpty']) ?? super.nightReviewHistoryEmpty;

  @override
  String get nightReviewPromptTitle => plainWording(_edits['nightReviewPromptTitle']) ?? super.nightReviewPromptTitle;

  @override
  String get nightReviewPromptDesc => plainWording(_edits['nightReviewPromptDesc']) ?? super.nightReviewPromptDesc;

  @override
  String get nightReviewMoodQuestion => plainWording(_edits['nightReviewMoodQuestion']) ?? super.nightReviewMoodQuestion;

  @override
  String get nightReviewReflectionLabel => plainWording(_edits['nightReviewReflectionLabel']) ?? super.nightReviewReflectionLabel;

  @override
  String get nightReviewReflectionHint => plainWording(_edits['nightReviewReflectionHint']) ?? super.nightReviewReflectionHint;

  @override
  String get nightReviewSummaryTitle => plainWording(_edits['nightReviewSummaryTitle']) ?? super.nightReviewSummaryTitle;

  @override
  String get nightReviewXpEarned => plainWording(_edits['nightReviewXpEarned']) ?? super.nightReviewXpEarned;

  @override
  String get nightReviewHabitsDoneLabel => plainWording(_edits['nightReviewHabitsDoneLabel']) ?? super.nightReviewHabitsDoneLabel;

  @override
  String get nightReviewTasksDoneLabel => plainWording(_edits['nightReviewTasksDoneLabel']) ?? super.nightReviewTasksDoneLabel;

  @override
  String get nightReviewGreenSquares => plainWording(_edits['nightReviewGreenSquares']) ?? super.nightReviewGreenSquares;

  @override
  String get nightReviewStreak => plainWording(_edits['nightReviewStreak']) ?? super.nightReviewStreak;

  @override
  String get nightReviewSave => plainWording(_edits['nightReviewSave']) ?? super.nightReviewSave;

  @override
  String get nightReviewSaved => plainWording(_edits['nightReviewSaved']) ?? super.nightReviewSaved;

  @override
  String get nightReviewDoneBadge => plainWording(_edits['nightReviewDoneBadge']) ?? super.nightReviewDoneBadge;

  @override
  String get nightReviewEditedHint => plainWording(_edits['nightReviewEditedHint']) ?? super.nightReviewEditedHint;

  @override
  String get premiumTitle => plainWording(_edits['premiumTitle']) ?? super.premiumTitle;

  @override
  String get premiumHeadline => plainWording(_edits['premiumHeadline']) ?? super.premiumHeadline;

  @override
  String get premiumSubhead => plainWording(_edits['premiumSubhead']) ?? super.premiumSubhead;

  @override
  String get premiumBenefitHabitsTitle => plainWording(_edits['premiumBenefitHabitsTitle']) ?? super.premiumBenefitHabitsTitle;

  @override
  String get premiumBenefitHabitsDesc => plainWording(_edits['premiumBenefitHabitsDesc']) ?? super.premiumBenefitHabitsDesc;

  @override
  String get premiumBenefitHistoryTitle => plainWording(_edits['premiumBenefitHistoryTitle']) ?? super.premiumBenefitHistoryTitle;

  @override
  String get premiumBenefitHistoryDesc => plainWording(_edits['premiumBenefitHistoryDesc']) ?? super.premiumBenefitHistoryDesc;

  @override
  String get premiumBenefitInsightsTitle => plainWording(_edits['premiumBenefitInsightsTitle']) ?? super.premiumBenefitInsightsTitle;

  @override
  String get premiumBenefitInsightsDesc => plainWording(_edits['premiumBenefitInsightsDesc']) ?? super.premiumBenefitInsightsDesc;

  @override
  String get premiumBenefitAppearanceTitle => plainWording(_edits['premiumBenefitAppearanceTitle']) ?? super.premiumBenefitAppearanceTitle;

  @override
  String get premiumBenefitAppearanceDesc => plainWording(_edits['premiumBenefitAppearanceDesc']) ?? super.premiumBenefitAppearanceDesc;

  @override
  String get premiumBenefitTaskRemindersTitle => plainWording(_edits['premiumBenefitTaskRemindersTitle']) ?? super.premiumBenefitTaskRemindersTitle;

  @override
  String get premiumBenefitTaskRemindersDesc => plainWording(_edits['premiumBenefitTaskRemindersDesc']) ?? super.premiumBenefitTaskRemindersDesc;

  @override
  String get premiumBenefitVoiceTitle => plainWording(_edits['premiumBenefitVoiceTitle']) ?? super.premiumBenefitVoiceTitle;

  @override
  String get premiumBenefitVoiceDesc => plainWording(_edits['premiumBenefitVoiceDesc']) ?? super.premiumBenefitVoiceDesc;

  @override
  String get premiumBenefitNavBarTitle => plainWording(_edits['premiumBenefitNavBarTitle']) ?? super.premiumBenefitNavBarTitle;

  @override
  String get premiumBenefitNavBarDesc => plainWording(_edits['premiumBenefitNavBarDesc']) ?? super.premiumBenefitNavBarDesc;

  @override
  String get premiumBenefitFutureTitle => plainWording(_edits['premiumBenefitFutureTitle']) ?? super.premiumBenefitFutureTitle;

  @override
  String get premiumBenefitFutureDesc => plainWording(_edits['premiumBenefitFutureDesc']) ?? super.premiumBenefitFutureDesc;

  @override
  String get premiumMonthly => plainWording(_edits['premiumMonthly']) ?? super.premiumMonthly;

  @override
  String get premiumYearly => plainWording(_edits['premiumYearly']) ?? super.premiumYearly;

  @override
  String get premiumLifetime => plainWording(_edits['premiumLifetime']) ?? super.premiumLifetime;

  @override
  String get premiumPerMonth => plainWording(_edits['premiumPerMonth']) ?? super.premiumPerMonth;

  @override
  String get premiumPerYear => plainWording(_edits['premiumPerYear']) ?? super.premiumPerYear;

  @override
  String get premiumOneTime => plainWording(_edits['premiumOneTime']) ?? super.premiumOneTime;

  @override
  String premiumSave(String pct) {
    final wordingEdit = _edits['premiumSave'];
    if (wordingEdit == null) return super.premiumSave(pct);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'pct': () => '$pct',
                }
              : <String, String Function()>{
                  'pct': () => '$pct',
                },
        ) ??
        super.premiumSave(pct);
  }

  @override
  String get premiumBestValueBadge => plainWording(_edits['premiumBestValueBadge']) ?? super.premiumBestValueBadge;

  @override
  String get premiumCta => plainWording(_edits['premiumCta']) ?? super.premiumCta;

  @override
  String get premiumWelcomeTitle => plainWording(_edits['premiumWelcomeTitle']) ?? super.premiumWelcomeTitle;

  @override
  String get premiumWelcomeEndsIn => plainWording(_edits['premiumWelcomeEndsIn']) ?? super.premiumWelcomeEndsIn;

  @override
  String get premiumSaleEndsIn => plainWording(_edits['premiumSaleEndsIn']) ?? super.premiumSaleEndsIn;

  @override
  String get premiumCountdownDays => plainWording(_edits['premiumCountdownDays']) ?? super.premiumCountdownDays;

  @override
  String get premiumCountdownHours => plainWording(_edits['premiumCountdownHours']) ?? super.premiumCountdownHours;

  @override
  String get premiumCountdownMinutes => plainWording(_edits['premiumCountdownMinutes']) ?? super.premiumCountdownMinutes;

  @override
  String get premiumCountdownSeconds => plainWording(_edits['premiumCountdownSeconds']) ?? super.premiumCountdownSeconds;

  @override
  String premiumCountdownSpoken(String left) {
    final wordingEdit = _edits['premiumCountdownSpoken'];
    if (wordingEdit == null) return super.premiumCountdownSpoken(left);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'left': () => '$left',
                }
              : <String, String Function()>{
                  'left': () => '$left',
                },
        ) ??
        super.premiumCountdownSpoken(left);
  }

  @override
  String premiumThenPrice(String price) {
    final wordingEdit = _edits['premiumThenPrice'];
    if (wordingEdit == null) return super.premiumThenPrice(price);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'price': () => '$price',
                }
              : <String, String Function()>{
                  'price': () => '$price',
                },
        ) ??
        super.premiumThenPrice(price);
  }

  @override
  String premiumRegularPriceSpoken(String price) {
    final wordingEdit = _edits['premiumRegularPriceSpoken'];
    if (wordingEdit == null) return super.premiumRegularPriceSpoken(price);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'price': () => '$price',
                }
              : <String, String Function()>{
                  'price': () => '$price',
                },
        ) ??
        super.premiumRegularPriceSpoken(price);
  }

  @override
  String premiumWelcomeFinePrint(String offer, String until, String regular) {
    final wordingEdit = _edits['premiumWelcomeFinePrint'];
    if (wordingEdit == null) return super.premiumWelcomeFinePrint(offer, until, regular);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'offer': () => '$offer',
                  'until': () => '$until',
                  'regular': () => '$regular',
                }
              : <String, String Function()>{
                  'offer': () => '$offer',
                  'until': () => '$until',
                  'regular': () => '$regular',
                },
        ) ??
        super.premiumWelcomeFinePrint(offer, until, regular);
  }

  @override
  String premiumSaleFinePrint(String offer, String until, String regular) {
    final wordingEdit = _edits['premiumSaleFinePrint'];
    if (wordingEdit == null) return super.premiumSaleFinePrint(offer, until, regular);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'offer': () => '$offer',
                  'until': () => '$until',
                  'regular': () => '$regular',
                }
              : <String, String Function()>{
                  'offer': () => '$offer',
                  'until': () => '$until',
                  'regular': () => '$regular',
                },
        ) ??
        super.premiumSaleFinePrint(offer, until, regular);
  }

  @override
  String get premiumHaveCode => plainWording(_edits['premiumHaveCode']) ?? super.premiumHaveCode;

  @override
  String get premiumLifetimeOwned => plainWording(_edits['premiumLifetimeOwned']) ?? super.premiumLifetimeOwned;

  @override
  String get premiumLifetimeStillRenewing => plainWording(_edits['premiumLifetimeStillRenewing']) ?? super.premiumLifetimeStillRenewing;

  @override
  String get premiumUpgradeTitle => plainWording(_edits['premiumUpgradeTitle']) ?? super.premiumUpgradeTitle;

  @override
  String get premiumUpgradeCancelNote => plainWording(_edits['premiumUpgradeCancelNote']) ?? super.premiumUpgradeCancelNote;

  @override
  String get premiumUpgradeCta => plainWording(_edits['premiumUpgradeCta']) ?? super.premiumUpgradeCta;

  @override
  String get premiumPurchasePending => plainWording(_edits['premiumPurchasePending']) ?? super.premiumPurchasePending;

  @override
  String get premiumRestore => plainWording(_edits['premiumRestore']) ?? super.premiumRestore;

  @override
  String get premiumRetry => plainWording(_edits['premiumRetry']) ?? super.premiumRetry;

  @override
  String get premiumComingSoon => plainWording(_edits['premiumComingSoon']) ?? super.premiumComingSoon;

  @override
  String get premiumBuyOnIphone => plainWording(_edits['premiumBuyOnIphone']) ?? super.premiumBuyOnIphone;

  @override
  String get premiumActive => plainWording(_edits['premiumActive']) ?? super.premiumActive;

  @override
  String get premiumManageSubscription => plainWording(_edits['premiumManageSubscription']) ?? super.premiumManageSubscription;

  @override
  String get premiumPurchaseError => plainWording(_edits['premiumPurchaseError']) ?? super.premiumPurchaseError;

  @override
  String get premiumRestoreSuccess => plainWording(_edits['premiumRestoreSuccess']) ?? super.premiumRestoreSuccess;

  @override
  String get premiumRestoreNothingFound => plainWording(_edits['premiumRestoreNothingFound']) ?? super.premiumRestoreNothingFound;

  @override
  String get premiumFinePrintMonthly => plainWording(_edits['premiumFinePrintMonthly']) ?? super.premiumFinePrintMonthly;

  @override
  String get premiumFinePrintMonthlyPlay => plainWording(_edits['premiumFinePrintMonthlyPlay']) ?? super.premiumFinePrintMonthlyPlay;

  @override
  String get premiumFinePrintLifetime => plainWording(_edits['premiumFinePrintLifetime']) ?? super.premiumFinePrintLifetime;

  @override
  String get premiumPurchaseNotEntitled => plainWording(_edits['premiumPurchaseNotEntitled']) ?? super.premiumPurchaseNotEntitled;

  @override
  String get notifRoomPushReady => plainWording(_edits['notifRoomPushReady']) ?? super.notifRoomPushReady;

  @override
  String get notifRoomPushNoPermission => plainWording(_edits['notifRoomPushNoPermission']) ?? super.notifRoomPushNoPermission;

  @override
  String get notifRoomPushNoToken => plainWording(_edits['notifRoomPushNoToken']) ?? super.notifRoomPushNoToken;

  @override
  String get notifRoomPushCategoryOff => plainWording(_edits['notifRoomPushCategoryOff']) ?? super.notifRoomPushCategoryOff;

  @override
  String get notifOpenSystemSettings => plainWording(_edits['notifOpenSystemSettings']) ?? super.notifOpenSystemSettings;

  @override
  String get premiumTermsOfUse => plainWording(_edits['premiumTermsOfUse']) ?? super.premiumTermsOfUse;

  @override
  String get premiumPrivacyPolicy => plainWording(_edits['premiumPrivacyPolicy']) ?? super.premiumPrivacyPolicy;

  @override
  String get premiumLinkOpenError => plainWording(_edits['premiumLinkOpenError']) ?? super.premiumLinkOpenError;

  @override
  String get helpSupportRowTitle => plainWording(_edits['helpSupportRowTitle']) ?? super.helpSupportRowTitle;

  @override
  String get helpFaqSectionTitle => plainWording(_edits['helpFaqSectionTitle']) ?? super.helpFaqSectionTitle;

  @override
  String get helpContactSectionTitle => plainWording(_edits['helpContactSectionTitle']) ?? super.helpContactSectionTitle;

  @override
  String get helpContactEmailLabel => plainWording(_edits['helpContactEmailLabel']) ?? super.helpContactEmailLabel;

  @override
  String get helpContactWhatsAppLabel => plainWording(_edits['helpContactWhatsAppLabel']) ?? super.helpContactWhatsAppLabel;

  @override
  String get helpContactInstagramLabel => plainWording(_edits['helpContactInstagramLabel']) ?? super.helpContactInstagramLabel;

  @override
  String get helpGuidesSectionTitle => plainWording(_edits['helpGuidesSectionTitle']) ?? super.helpGuidesSectionTitle;

  @override
  String get habitLimitTitle => plainWording(_edits['habitLimitTitle']) ?? super.habitLimitTitle;

  @override
  String habitLimitBody(int limit) {
    final wordingEdit = _edits['habitLimitBody'];
    if (wordingEdit == null) return super.habitLimitBody(limit);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'limit': () => '$limit',
                }
              : <String, String Function()>{
                  'limit': () => '$limit',
                },
        ) ??
        super.habitLimitBody(limit);
  }

  @override
  String get voiceNoteGateTitle => plainWording(_edits['voiceNoteGateTitle']) ?? super.voiceNoteGateTitle;

  @override
  String get voiceNoteGateBody => plainWording(_edits['voiceNoteGateBody']) ?? super.voiceNoteGateBody;

  @override
  String get voiceNoteRecording => plainWording(_edits['voiceNoteRecording']) ?? super.voiceNoteRecording;

  @override
  String get voiceNoteTapToRecord => plainWording(_edits['voiceNoteTapToRecord']) ?? super.voiceNoteTapToRecord;

  @override
  String get voiceNoteTapToStop => plainWording(_edits['voiceNoteTapToStop']) ?? super.voiceNoteTapToStop;

  @override
  String get voiceNoteMicPermissionDenied => plainWording(_edits['voiceNoteMicPermissionDenied']) ?? super.voiceNoteMicPermissionDenied;

  @override
  String get voiceNoteAttached => plainWording(_edits['voiceNoteAttached']) ?? super.voiceNoteAttached;

  @override
  String get voiceNotePlay => plainWording(_edits['voiceNotePlay']) ?? super.voiceNotePlay;

  @override
  String get voiceNotePause => plainWording(_edits['voiceNotePause']) ?? super.voiceNotePause;

  @override
  String get voiceNoteSkipBack => plainWording(_edits['voiceNoteSkipBack']) ?? super.voiceNoteSkipBack;

  @override
  String get voiceNoteSkipForward => plainWording(_edits['voiceNoteSkipForward']) ?? super.voiceNoteSkipForward;

  @override
  String voiceNoteSpeedLabel(String rate) {
    final wordingEdit = _edits['voiceNoteSpeedLabel'];
    if (wordingEdit == null) return super.voiceNoteSpeedLabel(rate);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'rate': () => '$rate',
                }
              : <String, String Function()>{
                  'rate': () => '$rate',
                },
        ) ??
        super.voiceNoteSpeedLabel(rate);
  }

  @override
  String get voiceNotesTitle => plainWording(_edits['voiceNotesTitle']) ?? super.voiceNotesTitle;

  @override
  String voiceNoteDefaultName(int n) {
    final wordingEdit = _edits['voiceNoteDefaultName'];
    if (wordingEdit == null) return super.voiceNoteDefaultName(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.voiceNoteDefaultName(n);
  }

  @override
  String get voiceNoteRenameTitle => plainWording(_edits['voiceNoteRenameTitle']) ?? super.voiceNoteRenameTitle;

  @override
  String get voiceNoteRenameHint => plainWording(_edits['voiceNoteRenameHint']) ?? super.voiceNoteRenameHint;

  @override
  String get voiceNoteRenameSave => plainWording(_edits['voiceNoteRenameSave']) ?? super.voiceNoteRenameSave;

  @override
  String get voiceNoteClosePlayer => plainWording(_edits['voiceNoteClosePlayer']) ?? super.voiceNoteClosePlayer;

  @override
  String streakAtRiskTitle(int days) {
    final wordingEdit = _edits['streakAtRiskTitle'];
    if (wordingEdit == null) return super.streakAtRiskTitle(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'days': () => '$days',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.streakAtRiskTitle(days);
  }

  @override
  String get streakAtRiskBody => plainWording(_edits['streakAtRiskBody']) ?? super.streakAtRiskBody;

  @override
  String get onboardingGridTitle => plainWording(_edits['onboardingGridTitle']) ?? super.onboardingGridTitle;

  @override
  String get onboardingGridBody => plainWording(_edits['onboardingGridBody']) ?? super.onboardingGridBody;

  @override
  String get onboardingHabitsTitle => plainWording(_edits['onboardingHabitsTitle']) ?? super.onboardingHabitsTitle;

  @override
  String get onboardingHabitsBody => plainWording(_edits['onboardingHabitsBody']) ?? super.onboardingHabitsBody;

  @override
  String get onboardingTasksTitle => plainWording(_edits['onboardingTasksTitle']) ?? super.onboardingTasksTitle;

  @override
  String get onboardingTasksBody => plainWording(_edits['onboardingTasksBody']) ?? super.onboardingTasksBody;

  @override
  String get onboardingRoomsTitle => plainWording(_edits['onboardingRoomsTitle']) ?? super.onboardingRoomsTitle;

  @override
  String get onboardingRoomsBody => plainWording(_edits['onboardingRoomsBody']) ?? super.onboardingRoomsBody;

  @override
  String get onboardingSkip => plainWording(_edits['onboardingSkip']) ?? super.onboardingSkip;

  @override
  String get onboardingNext => plainWording(_edits['onboardingNext']) ?? super.onboardingNext;

  @override
  String get onboardingGetStarted => plainWording(_edits['onboardingGetStarted']) ?? super.onboardingGetStarted;

  @override
  String get habitIconColor => plainWording(_edits['habitIconColor']) ?? super.habitIconColor;

  @override
  String get habitIconColorHint => plainWording(_edits['habitIconColorHint']) ?? super.habitIconColorHint;

  @override
  String get hexCode => plainWording(_edits['hexCode']) ?? super.hexCode;

  @override
  String get useDefaultColor => plainWording(_edits['useDefaultColor']) ?? super.useDefaultColor;

  @override
  String get colorPickerDone => plainWording(_edits['colorPickerDone']) ?? super.colorPickerDone;

  @override
  String get roomsTitle => plainWording(_edits['roomsTitle']) ?? super.roomsTitle;

  @override
  String get roomGenericError => plainWording(_edits['roomGenericError']) ?? super.roomGenericError;

  @override
  String get roomsEmptyTitle => plainWording(_edits['roomsEmptyTitle']) ?? super.roomsEmptyTitle;

  @override
  String get roomsEmptyBody => plainWording(_edits['roomsEmptyBody']) ?? super.roomsEmptyBody;

  @override
  String get roomCreateAction => plainWording(_edits['roomCreateAction']) ?? super.roomCreateAction;

  @override
  String get roomJoinAction => plainWording(_edits['roomJoinAction']) ?? super.roomJoinAction;

  @override
  String get roomGuestGateTitle => plainWording(_edits['roomGuestGateTitle']) ?? super.roomGuestGateTitle;

  @override
  String get roomGuestGateBody => plainWording(_edits['roomGuestGateBody']) ?? super.roomGuestGateBody;

  @override
  String get roomGuestGateAction => plainWording(_edits['roomGuestGateAction']) ?? super.roomGuestGateAction;

  @override
  String get roomStarTooltip => plainWording(_edits['roomStarTooltip']) ?? super.roomStarTooltip;

  @override
  String get roomUnstarTooltip => plainWording(_edits['roomUnstarTooltip']) ?? super.roomUnstarTooltip;

  @override
  String get roomCreateTitle => plainWording(_edits['roomCreateTitle']) ?? super.roomCreateTitle;

  @override
  String get roomNameLabel => plainWording(_edits['roomNameLabel']) ?? super.roomNameLabel;

  @override
  String get roomNameHint => plainWording(_edits['roomNameHint']) ?? super.roomNameHint;

  @override
  String get roomNameIdeas => plainWording(_edits['roomNameIdeas']) ?? super.roomNameIdeas;

  @override
  String get roomHabitModeLabel => plainWording(_edits['roomHabitModeLabel']) ?? super.roomHabitModeLabel;

  @override
  String get roomHabitModeShared => plainWording(_edits['roomHabitModeShared']) ?? super.roomHabitModeShared;

  @override
  String get roomHabitModeSharedHint => plainWording(_edits['roomHabitModeSharedHint']) ?? super.roomHabitModeSharedHint;

  @override
  String get roomHabitModeOwn => plainWording(_edits['roomHabitModeOwn']) ?? super.roomHabitModeOwn;

  @override
  String get roomHabitModeOwnHint => plainWording(_edits['roomHabitModeOwnHint']) ?? super.roomHabitModeOwnHint;

  @override
  String get roomYourHabitLabel => plainWording(_edits['roomYourHabitLabel']) ?? super.roomYourHabitLabel;

  @override
  String get roomCompeteModeLabel => plainWording(_edits['roomCompeteModeLabel']) ?? super.roomCompeteModeLabel;

  @override
  String get roomCompeteModeCompetitive => plainWording(_edits['roomCompeteModeCompetitive']) ?? super.roomCompeteModeCompetitive;

  @override
  String get roomCompeteModeCompetitiveHint => plainWording(_edits['roomCompeteModeCompetitiveHint']) ?? super.roomCompeteModeCompetitiveHint;

  @override
  String get roomCompeteModeTeam => plainWording(_edits['roomCompeteModeTeam']) ?? super.roomCompeteModeTeam;

  @override
  String get roomCompeteModeTeamHint => plainWording(_edits['roomCompeteModeTeamHint']) ?? super.roomCompeteModeTeamHint;

  @override
  String get roomOwnHabitsLabel => plainWording(_edits['roomOwnHabitsLabel']) ?? super.roomOwnHabitsLabel;

  @override
  String get roomOwnHabitsHint => plainWording(_edits['roomOwnHabitsHint']) ?? super.roomOwnHabitsHint;

  @override
  String get roomPlanHabitsLabel => plainWording(_edits['roomPlanHabitsLabel']) ?? super.roomPlanHabitsLabel;

  @override
  String get roomPlanHabitsHint => plainWording(_edits['roomPlanHabitsHint']) ?? super.roomPlanHabitsHint;

  @override
  String get roomDurationLabel => plainWording(_edits['roomDurationLabel']) ?? super.roomDurationLabel;

  @override
  String get roomDurationOpenEnded => plainWording(_edits['roomDurationOpenEnded']) ?? super.roomDurationOpenEnded;

  @override
  String get roomDurationCustomOption => plainWording(_edits['roomDurationCustomOption']) ?? super.roomDurationCustomOption;

  @override
  String get roomDurationCustomHint => plainWording(_edits['roomDurationCustomHint']) ?? super.roomDurationCustomHint;

  @override
  String get roomDurationCustomRange => plainWording(_edits['roomDurationCustomRange']) ?? super.roomDurationCustomRange;

  @override
  String get roomDurationCustomInvalid => plainWording(_edits['roomDurationCustomInvalid']) ?? super.roomDurationCustomInvalid;

  @override
  String get roomCreateSubmit => plainWording(_edits['roomCreateSubmit']) ?? super.roomCreateSubmit;

  @override
  String get roomDurationExtendHint => plainWording(_edits['roomDurationExtendHint']) ?? super.roomDurationExtendHint;

  @override
  String get roomCreateStepOne => plainWording(_edits['roomCreateStepOne']) ?? super.roomCreateStepOne;

  @override
  String get roomCreateStepTwo => plainWording(_edits['roomCreateStepTwo']) ?? super.roomCreateStepTwo;

  @override
  String get roomCreateStepHabitsTitle => plainWording(_edits['roomCreateStepHabitsTitle']) ?? super.roomCreateStepHabitsTitle;

  @override
  String get roomCreateNext => plainWording(_edits['roomCreateNext']) ?? super.roomCreateNext;

  @override
  String get roomCreateBack => plainWording(_edits['roomCreateBack']) ?? super.roomCreateBack;

  @override
  String get roomCreateNeedsName => plainWording(_edits['roomCreateNeedsName']) ?? super.roomCreateNeedsName;

  @override
  String get roomCreateNeedsHabit => plainWording(_edits['roomCreateNeedsHabit']) ?? super.roomCreateNeedsHabit;

  @override
  String get roomCreateNeedsDuration => plainWording(_edits['roomCreateNeedsDuration']) ?? super.roomCreateNeedsDuration;

  @override
  String get roomHabitModeOwnShort => plainWording(_edits['roomHabitModeOwnShort']) ?? super.roomHabitModeOwnShort;

  @override
  String get roomCreatedTitle => plainWording(_edits['roomCreatedTitle']) ?? super.roomCreatedTitle;

  @override
  String get roomShareCode => plainWording(_edits['roomShareCode']) ?? super.roomShareCode;

  @override
  String get roomCodeCopied => plainWording(_edits['roomCodeCopied']) ?? super.roomCodeCopied;

  @override
  String get roomCopyAction => plainWording(_edits['roomCopyAction']) ?? super.roomCopyAction;

  @override
  String get roomShareAction => plainWording(_edits['roomShareAction']) ?? super.roomShareAction;

  @override
  String get roomDoneAction => plainWording(_edits['roomDoneAction']) ?? super.roomDoneAction;

  @override
  String get roomCreatedPrivateNote => plainWording(_edits['roomCreatedPrivateNote']) ?? super.roomCreatedPrivateNote;

  @override
  String get roomCreatedNextTitle => plainWording(_edits['roomCreatedNextTitle']) ?? super.roomCreatedNextTitle;

  @override
  String get roomCreatedNextBody => plainWording(_edits['roomCreatedNextBody']) ?? super.roomCreatedNextBody;

  @override
  String get roomOpenAction => plainWording(_edits['roomOpenAction']) ?? super.roomOpenAction;

  @override
  String get roomJoinTitle => plainWording(_edits['roomJoinTitle']) ?? super.roomJoinTitle;

  @override
  String get roomCodeLabel => plainWording(_edits['roomCodeLabel']) ?? super.roomCodeLabel;

  @override
  String get roomCodeHint => plainWording(_edits['roomCodeHint']) ?? super.roomCodeHint;

  @override
  String get roomFindAction => plainWording(_edits['roomFindAction']) ?? super.roomFindAction;

  @override
  String get roomNotFound => plainWording(_edits['roomNotFound']) ?? super.roomNotFound;

  @override
  String get roomAlreadyEndedJoin => plainWording(_edits['roomAlreadyEndedJoin']) ?? super.roomAlreadyEndedJoin;

  @override
  String get roomAlreadyMemberJoin => plainWording(_edits['roomAlreadyMemberJoin']) ?? super.roomAlreadyMemberJoin;

  @override
  String get roomPreviewOwnMode => plainWording(_edits['roomPreviewOwnMode']) ?? super.roomPreviewOwnMode;

  @override
  String roomPreviewSharedHabit(String name) {
    final wordingEdit = _edits['roomPreviewSharedHabit'];
    if (wordingEdit == null) return super.roomPreviewSharedHabit(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomPreviewSharedHabit(name);
  }

  @override
  String get roomPreviewSharedHabitsLabel => plainWording(_edits['roomPreviewSharedHabitsLabel']) ?? super.roomPreviewSharedHabitsLabel;

  @override
  String get roomPickHabitLabel => plainWording(_edits['roomPickHabitLabel']) ?? super.roomPickHabitLabel;

  @override
  String get roomPickHabitHint => plainWording(_edits['roomPickHabitHint']) ?? super.roomPickHabitHint;

  @override
  String get roomPickHabitsLabel => plainWording(_edits['roomPickHabitsLabel']) ?? super.roomPickHabitsLabel;

  @override
  String get roomNoHabitsYet => plainWording(_edits['roomNoHabitsYet']) ?? super.roomNoHabitsYet;

  @override
  String get roomPlanReviewLabel => plainWording(_edits['roomPlanReviewLabel']) ?? super.roomPlanReviewLabel;

  @override
  String get roomPlanAddAsNew => plainWording(_edits['roomPlanAddAsNew']) ?? super.roomPlanAddAsNew;

  @override
  String roomPlanLinkExisting(String name) {
    final wordingEdit = _edits['roomPlanLinkExisting'];
    if (wordingEdit == null) return super.roomPlanLinkExisting(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomPlanLinkExisting(name);
  }

  @override
  String roomPlanTornHint(String names) {
    final wordingEdit = _edits['roomPlanTornHint'];
    if (wordingEdit == null) return super.roomPlanTornHint(names);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'names': () => '$names',
                }
              : <String, String Function()>{
                  'names': () => '$names',
                },
        ) ??
        super.roomPlanTornHint(names);
  }

  @override
  String get roomRelinkTitle => plainWording(_edits['roomRelinkTitle']) ?? super.roomRelinkTitle;

  @override
  String roomRelinkHint(String slotName, String currentName) {
    final wordingEdit = _edits['roomRelinkHint'];
    if (wordingEdit == null) return super.roomRelinkHint(slotName, currentName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'slotName': () => '$slotName',
                  'currentName': () => '$currentName',
                }
              : <String, String Function()>{
                  'slotName': () => '$slotName',
                  'currentName': () => '$currentName',
                },
        ) ??
        super.roomRelinkHint(slotName, currentName);
  }

  @override
  String roomRelinkConfirm(String newName, String oldName) {
    final wordingEdit = _edits['roomRelinkConfirm'];
    if (wordingEdit == null) return super.roomRelinkConfirm(newName, oldName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'newName': () => '$newName',
                  'oldName': () => '$oldName',
                }
              : <String, String Function()>{
                  'newName': () => '$newName',
                  'oldName': () => '$oldName',
                },
        ) ??
        super.roomRelinkConfirm(newName, oldName);
  }

  @override
  String get roomRelinkAction => plainWording(_edits['roomRelinkAction']) ?? super.roomRelinkAction;

  @override
  String get roomRelinkNone => plainWording(_edits['roomRelinkNone']) ?? super.roomRelinkNone;

  @override
  String roomRelinkDone(String name) {
    final wordingEdit = _edits['roomRelinkDone'];
    if (wordingEdit == null) return super.roomRelinkDone(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomRelinkDone(name);
  }

  @override
  String get roomRelinkFailed => plainWording(_edits['roomRelinkFailed']) ?? super.roomRelinkFailed;

  @override
  String get roomJoinSubmit => plainWording(_edits['roomJoinSubmit']) ?? super.roomJoinSubmit;

  @override
  String roomShowAllMembers(int n) {
    final wordingEdit = _edits['roomShowAllMembers'];
    if (wordingEdit == null) return super.roomShowAllMembers(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'roomMemberCount(n)': () => '${roomMemberCount(n)}',
                }
              : <String, String Function()>{
                  'roomMemberCount(n)': () => '${roomMemberCount(n)}',
                },
        ) ??
        super.roomShowAllMembers(n);
  }

  @override
  String get roomLargeRoomMutedNote => plainWording(_edits['roomLargeRoomMutedNote']) ?? super.roomLargeRoomMutedNote;

  @override
  String roomFinaleDialogBody(String roomName) {
    final wordingEdit = _edits['roomFinaleDialogBody'];
    if (wordingEdit == null) return super.roomFinaleDialogBody(roomName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'roomName': () => '$roomName',
                }
              : <String, String Function()>{
                  'roomName': () => '$roomName',
                },
        ) ??
        super.roomFinaleDialogBody(roomName);
  }

  @override
  String get roomFinaleShow => plainWording(_edits['roomFinaleShow']) ?? super.roomFinaleShow;

  @override
  String get roomFinaleDismiss => plainWording(_edits['roomFinaleDismiss']) ?? super.roomFinaleDismiss;

  @override
  String roomClaimPrize(int xp, int gold) {
    final wordingEdit = _edits['roomClaimPrize'];
    if (wordingEdit == null) return super.roomClaimPrize(xp, gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                },
        ) ??
        super.roomClaimPrize(xp, gold);
  }

  @override
  String get roomPrizeClaimed => plainWording(_edits['roomPrizeClaimed']) ?? super.roomPrizeClaimed;

  @override
  String get roomOngoing => plainWording(_edits['roomOngoing']) ?? super.roomOngoing;

  @override
  String get roomEnded => plainWording(_edits['roomEnded']) ?? super.roomEnded;

  @override
  String roomDaysLeft(int n) {
    final wordingEdit = _edits['roomDaysLeft'];
    if (wordingEdit == null) return super.roomDaysLeft(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(n)': () => '${daysCount(n)}',
                }
              : <String, String Function()>{
                  'daysCount(n)': () => '${daysCount(n)}',
                },
        ) ??
        super.roomDaysLeft(n);
  }

  @override
  String get roomMarkedToday => plainWording(_edits['roomMarkedToday']) ?? super.roomMarkedToday;

  @override
  String get roomNotDoneToday => plainWording(_edits['roomNotDoneToday']) ?? super.roomNotDoneToday;

  @override
  String roomPartialToday(int done, int total) {
    final wordingEdit = _edits['roomPartialToday'];
    if (wordingEdit == null) return super.roomPartialToday(done, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                },
        ) ??
        super.roomPartialToday(done, total);
  }

  @override
  String roomQuotaWeekProgress(String habit, int done, int target) {
    final wordingEdit = _edits['roomQuotaWeekProgress'];
    if (wordingEdit == null) return super.roomQuotaWeekProgress(habit, done, target);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habit': () => '$habit',
                  'done': () => '$done',
                  'target': () => '$target',
                }
              : <String, String Function()>{
                  'habit': () => '$habit',
                  'done': () => '$done',
                  'target': () => '$target',
                },
        ) ??
        super.roomQuotaWeekProgress(habit, done, target);
  }

  @override
  String get roomQuotaNeededToday => plainWording(_edits['roomQuotaNeededToday']) ?? super.roomQuotaNeededToday;

  @override
  String get roomStripStart => plainWording(_edits['roomStripStart']) ?? super.roomStripStart;

  @override
  String get roomStripDetails => plainWording(_edits['roomStripDetails']) ?? super.roomStripDetails;

  @override
  String get roomStripOpenCalendar => plainWording(_edits['roomStripOpenCalendar']) ?? super.roomStripOpenCalendar;

  @override
  String roomCalendarTitle(String name) {
    final wordingEdit = _edits['roomCalendarTitle'];
    if (wordingEdit == null) return super.roomCalendarTitle(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomCalendarTitle(name);
  }

  @override
  String get roomCalendarDone => plainWording(_edits['roomCalendarDone']) ?? super.roomCalendarDone;

  @override
  String get roomCalendarMissed => plainWording(_edits['roomCalendarMissed']) ?? super.roomCalendarMissed;

  @override
  String get roomCalendarPartial => plainWording(_edits['roomCalendarPartial']) ?? super.roomCalendarPartial;

  @override
  String get roomCalendarRestDay => plainWording(_edits['roomCalendarRestDay']) ?? super.roomCalendarRestDay;

  @override
  String get roomCalendarStoodDown => plainWording(_edits['roomCalendarStoodDown']) ?? super.roomCalendarStoodDown;

  @override
  String get roomCalendarPaused => plainWording(_edits['roomCalendarPaused']) ?? super.roomCalendarPaused;

  @override
  String get roomCalendarHabitPaused => plainWording(_edits['roomCalendarHabitPaused']) ?? super.roomCalendarHabitPaused;

  @override
  String get roomCalendarFirstDayNote => plainWording(_edits['roomCalendarFirstDayNote']) ?? super.roomCalendarFirstDayNote;

  @override
  String get roomCalendarFirstDayNoteOther => plainWording(_edits['roomCalendarFirstDayNoteOther']) ?? super.roomCalendarFirstDayNoteOther;

  @override
  String roomCalendarTotalOf(String done, int total) {
    final wordingEdit = _edits['roomCalendarTotalOf'];
    if (wordingEdit == null) return super.roomCalendarTotalOf(done, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                },
        ) ??
        super.roomCalendarTotalOf(done, total);
  }

  @override
  String get roomCalendarNothingAsked => plainWording(_edits['roomCalendarNothingAsked']) ?? super.roomCalendarNothingAsked;

  @override
  String get roomCalendarChipDone => plainWording(_edits['roomCalendarChipDone']) ?? super.roomCalendarChipDone;

  @override
  String get roomCalendarChipPartial => plainWording(_edits['roomCalendarChipPartial']) ?? super.roomCalendarChipPartial;

  @override
  String get roomCalendarChipMissed => plainWording(_edits['roomCalendarChipMissed']) ?? super.roomCalendarChipMissed;

  @override
  String get roomCalendarChipRest => plainWording(_edits['roomCalendarChipRest']) ?? super.roomCalendarChipRest;

  @override
  String roomCalendarGroupPool(List<String> names) {
    final wordingEdit = _edits['roomCalendarGroupPool'];
    if (wordingEdit == null) return super.roomCalendarGroupPool(names);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'names.join(\'، \')': () => '${names.join('، ')}',
                }
              : <String, String Function()>{
                  'names.join(\', \')': () => '${names.join(', ')}',
                },
        ) ??
        super.roomCalendarGroupPool(names);
  }

  @override
  String get roomCalendarSlotDeclined => plainWording(_edits['roomCalendarSlotDeclined']) ?? super.roomCalendarSlotDeclined;

  @override
  String get roomCalendarStillOpen => plainWording(_edits['roomCalendarStillOpen']) ?? super.roomCalendarStillOpen;

  @override
  String get roomCalendarTotal => plainWording(_edits['roomCalendarTotal']) ?? super.roomCalendarTotal;

  @override
  String get roomSheetClose => plainWording(_edits['roomSheetClose']) ?? super.roomSheetClose;

  @override
  String roomStartedOn(String date) {
    final wordingEdit = _edits['roomStartedOn'];
    if (wordingEdit == null) return super.roomStartedOn(date);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'date': () => '$date',
                }
              : <String, String Function()>{
                  'date': () => '$date',
                },
        ) ??
        super.roomStartedOn(date);
  }

  @override
  String roomStartsOn(String date) {
    final wordingEdit = _edits['roomStartsOn'];
    if (wordingEdit == null) return super.roomStartsOn(date);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'date': () => '$date',
                }
              : <String, String Function()>{
                  'date': () => '$date',
                },
        ) ??
        super.roomStartsOn(date);
  }

  @override
  String get notifSystemPermissionOff => plainWording(_edits['notifSystemPermissionOff']) ?? super.notifSystemPermissionOff;

  @override
  String get notifSystemPermissionOffAction => plainWording(_edits['notifSystemPermissionOffAction']) ?? super.notifSystemPermissionOffAction;

  @override
  String roomRuleChangedWarning(String habitNames) {
    final wordingEdit = _edits['roomRuleChangedWarning'];
    if (wordingEdit == null) return super.roomRuleChangedWarning(habitNames);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitNames': () => '$habitNames',
                }
              : <String, String Function()>{
                  'habitNames': () => '$habitNames',
                },
        ) ??
        super.roomRuleChangedWarning(habitNames);
  }

  @override
  String get roomRuleChangedAction => plainWording(_edits['roomRuleChangedAction']) ?? super.roomRuleChangedAction;

  @override
  String get roomRuleChangedApplied => plainWording(_edits['roomRuleChangedApplied']) ?? super.roomRuleChangedApplied;

  @override
  String get roomSkipSharedHabit => plainWording(_edits['roomSkipSharedHabit']) ?? super.roomSkipSharedHabit;

  @override
  String get roomSkippedLabel => plainWording(_edits['roomSkippedLabel']) ?? super.roomSkippedLabel;

  @override
  String get roomSkippedHint => plainWording(_edits['roomSkippedHint']) ?? super.roomSkippedHint;

  @override
  String get roomCancel => plainWording(_edits['roomCancel']) ?? super.roomCancel;

  @override
  String get roomRemoveHabitAction => plainWording(_edits['roomRemoveHabitAction']) ?? super.roomRemoveHabitAction;

  @override
  String get roomRemoveHabitPickerTitle => plainWording(_edits['roomRemoveHabitPickerTitle']) ?? super.roomRemoveHabitPickerTitle;

  @override
  String get roomRemoveHabitPickerHint => plainWording(_edits['roomRemoveHabitPickerHint']) ?? super.roomRemoveHabitPickerHint;

  @override
  String roomRemoveHabitConfirmTitle(String habitName) {
    final wordingEdit = _edits['roomRemoveHabitConfirmTitle'];
    if (wordingEdit == null) return super.roomRemoveHabitConfirmTitle(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomRemoveHabitConfirmTitle(habitName);
  }

  @override
  String get roomRemoveHabitConfirmBody => plainWording(_edits['roomRemoveHabitConfirmBody']) ?? super.roomRemoveHabitConfirmBody;

  @override
  String get roomRemoveHabitConfirmBodyNow => plainWording(_edits['roomRemoveHabitConfirmBodyNow']) ?? super.roomRemoveHabitConfirmBodyNow;

  @override
  String get roomRemoveHabitConfirmAction => plainWording(_edits['roomRemoveHabitConfirmAction']) ?? super.roomRemoveHabitConfirmAction;

  @override
  String roomHabitRemovedSnack(String habitName) {
    final wordingEdit = _edits['roomHabitRemovedSnack'];
    if (wordingEdit == null) return super.roomHabitRemovedSnack(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomHabitRemovedSnack(habitName);
  }

  @override
  String get roomRemoveLastHabitTitle => plainWording(_edits['roomRemoveLastHabitTitle']) ?? super.roomRemoveLastHabitTitle;

  @override
  String get roomRemoveLastHabitBody => plainWording(_edits['roomRemoveLastHabitBody']) ?? super.roomRemoveLastHabitBody;

  @override
  String get roomRemoveHabitAlreadyRemoved => plainWording(_edits['roomRemoveHabitAlreadyRemoved']) ?? super.roomRemoveHabitAlreadyRemoved;

  @override
  String get roomPlanLockedEnded => plainWording(_edits['roomPlanLockedEnded']) ?? super.roomPlanLockedEnded;

  @override
  String get roomLastDayLabel => plainWording(_edits['roomLastDayLabel']) ?? super.roomLastDayLabel;

  @override
  String roomHabitRestoredSnack(String habitName) {
    final wordingEdit = _edits['roomHabitRestoredSnack'];
    if (wordingEdit == null) return super.roomHabitRestoredSnack(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomHabitRestoredSnack(habitName);
  }

  @override
  String get roomPlanNoticeTitle => plainWording(_edits['roomPlanNoticeTitle']) ?? super.roomPlanNoticeTitle;

  @override
  String roomPlanNoticeRemovedToday(String habitName, String roomName) {
    final wordingEdit = _edits['roomPlanNoticeRemovedToday'];
    if (wordingEdit == null) return super.roomPlanNoticeRemovedToday(habitName, roomName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                  'roomName': () => '$roomName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                  'roomName': () => '$roomName',
                },
        ) ??
        super.roomPlanNoticeRemovedToday(habitName, roomName);
  }

  @override
  String roomPlanNoticeRemoved(String habitName, String roomName) {
    final wordingEdit = _edits['roomPlanNoticeRemoved'];
    if (wordingEdit == null) return super.roomPlanNoticeRemoved(habitName, roomName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                  'roomName': () => '$roomName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                  'roomName': () => '$roomName',
                },
        ) ??
        super.roomPlanNoticeRemoved(habitName, roomName);
  }

  @override
  String get roomPlanNoticeKeptHabit => plainWording(_edits['roomPlanNoticeKeptHabit']) ?? super.roomPlanNoticeKeptHabit;

  @override
  String get roomPlanNoticeDaysKept => plainWording(_edits['roomPlanNoticeDaysKept']) ?? super.roomPlanNoticeDaysKept;

  @override
  String roomPlanNoticeRestored(String habitName) {
    final wordingEdit = _edits['roomPlanNoticeRestored'];
    if (wordingEdit == null) return super.roomPlanNoticeRestored(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomPlanNoticeRestored(habitName);
  }

  @override
  String get roomPlanNoticeOk => plainWording(_edits['roomPlanNoticeOk']) ?? super.roomPlanNoticeOk;

  @override
  String get roomPlanNoticeOpenRoom => plainWording(_edits['roomPlanNoticeOpenRoom']) ?? super.roomPlanNoticeOpenRoom;

  @override
  String roomPlanPartialCreditHint(int n) {
    final wordingEdit = _edits['roomPlanPartialCreditHint'];
    if (wordingEdit == null) return super.roomPlanPartialCreditHint(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.roomPlanPartialCreditHint(n);
  }

  @override
  String get roomTeamProgressTitle => plainWording(_edits['roomTeamProgressTitle']) ?? super.roomTeamProgressTitle;

  @override
  String roomTeamProgressDays(int completed, int possible) {
    final wordingEdit = _edits['roomTeamProgressDays'];
    if (wordingEdit == null) return super.roomTeamProgressDays(completed, possible);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(completed)': () => '${daysCount(completed)}',
                  'daysCount(possible)': () => '${daysCount(possible)}',
                }
              : <String, String Function()>{
                  'completed': () => '$completed',
                  'possible': () => '$possible',
                },
        ) ??
        super.roomTeamProgressDays(completed, possible);
  }

  @override
  String get roomTeamAllDoneToday => plainWording(_edits['roomTeamAllDoneToday']) ?? super.roomTeamAllDoneToday;

  @override
  String roomTeamBonusHint(int xp, int gold) {
    final wordingEdit = _edits['roomTeamBonusHint'];
    if (wordingEdit == null) return super.roomTeamBonusHint(xp, gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                },
        ) ??
        super.roomTeamBonusHint(xp, gold);
  }

  @override
  String get roomTeamBonusClaimAction => plainWording(_edits['roomTeamBonusClaimAction']) ?? super.roomTeamBonusClaimAction;

  @override
  String get roomTeamBonusClaimedLabel => plainWording(_edits['roomTeamBonusClaimedLabel']) ?? super.roomTeamBonusClaimedLabel;

  @override
  String get roomTeamDayTitle => plainWording(_edits['roomTeamDayTitle']) ?? super.roomTeamDayTitle;

  @override
  String get roomTeamDayWon => plainWording(_edits['roomTeamDayWon']) ?? super.roomTeamDayWon;

  @override
  String roomTeamWaitingOn(String name) {
    final wordingEdit = _edits['roomTeamWaitingOn'];
    if (wordingEdit == null) return super.roomTeamWaitingOn(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomTeamWaitingOn(name);
  }

  @override
  String roomTeamWaitingCount(int n) {
    final wordingEdit = _edits['roomTeamWaitingCount'];
    if (wordingEdit == null) return super.roomTeamWaitingCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.roomTeamWaitingCount(n);
  }

  @override
  String get roomTeamNobodyYet => plainWording(_edits['roomTeamNobodyYet']) ?? super.roomTeamNobodyYet;

  @override
  String roomTeamNextMilestone(int days) {
    final wordingEdit = _edits['roomTeamNextMilestone'];
    if (wordingEdit == null) return super.roomTeamNextMilestone(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(days)': () => '${daysCount(days)}',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.roomTeamNextMilestone(days);
  }

  @override
  String roomTeamMilestoneReached(int days) {
    final wordingEdit = _edits['roomTeamMilestoneReached'];
    if (wordingEdit == null) return super.roomTeamMilestoneReached(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(days)': () => '${daysCount(days)}',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.roomTeamMilestoneReached(days);
  }

  @override
  String roomTeamMilestoneClaimed(int days) {
    final wordingEdit = _edits['roomTeamMilestoneClaimed'];
    if (wordingEdit == null) return super.roomTeamMilestoneClaimed(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(days)': () => '${daysCount(days)}',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                },
        ) ??
        super.roomTeamMilestoneClaimed(days);
  }

  @override
  String roomTeamMilestonePrize(int xp, int gold) {
    final wordingEdit = _edits['roomTeamMilestonePrize'];
    if (wordingEdit == null) return super.roomTeamMilestonePrize(xp, gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'xp': () => '$xp',
                  'gold': () => '$gold',
                },
        ) ??
        super.roomTeamMilestonePrize(xp, gold);
  }

  @override
  String roomTeamDaysToGo(int n) {
    final wordingEdit = _edits['roomTeamDaysToGo'];
    if (wordingEdit == null) return super.roomTeamDaysToGo(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(n)': () => '${daysCount(n)}',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                  'n == 1 ? \'day\' : \'days\'': () => '${n == 1 ? 'day' : 'days'}',
                },
        ) ??
        super.roomTeamDaysToGo(n);
  }

  @override
  String get roomTeamAllMilestonesDone => plainWording(_edits['roomTeamAllMilestonesDone']) ?? super.roomTeamAllMilestonesDone;

  @override
  String get roomTeamClaimAction => plainWording(_edits['roomTeamClaimAction']) ?? super.roomTeamClaimAction;

  @override
  String roomTodayFinished(int done, int total) {
    final wordingEdit = _edits['roomTodayFinished'];
    if (wordingEdit == null) return super.roomTodayFinished(done, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                },
        ) ??
        super.roomTodayFinished(done, total);
  }

  @override
  String get roomLastSevenDays => plainWording(_edits['roomLastSevenDays']) ?? super.roomLastSevenDays;

  @override
  String get roomRowsViewTitle => plainWording(_edits['roomRowsViewTitle']) ?? super.roomRowsViewTitle;

  @override
  String get roomRowsFull => plainWording(_edits['roomRowsFull']) ?? super.roomRowsFull;

  @override
  String get roomSoloTitle => plainWording(_edits['roomSoloTitle']) ?? super.roomSoloTitle;

  @override
  String get roomFaceDone => plainWording(_edits['roomFaceDone']) ?? super.roomFaceDone;

  @override
  String get roomFaceWaiting => plainWording(_edits['roomFaceWaiting']) ?? super.roomFaceWaiting;

  @override
  String get roomFaceExcused => plainWording(_edits['roomFaceExcused']) ?? super.roomFaceExcused;

  @override
  String roomFacesMore(int n) {
    final wordingEdit = _edits['roomFacesMore'];
    if (wordingEdit == null) return super.roomFacesMore(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.roomFacesMore(n);
  }

  @override
  String get roomFacesSheetHint => plainWording(_edits['roomFacesSheetHint']) ?? super.roomFacesSheetHint;

  @override
  String get roomFacesAll => plainWording(_edits['roomFacesAll']) ?? super.roomFacesAll;

  @override
  String get roomTeamRankingTitle => plainWording(_edits['roomTeamRankingTitle']) ?? super.roomTeamRankingTitle;

  @override
  String get roomTeamRankingShow => plainWording(_edits['roomTeamRankingShow']) ?? super.roomTeamRankingShow;

  @override
  String get roomTeamRankingHide => plainWording(_edits['roomTeamRankingHide']) ?? super.roomTeamRankingHide;

  @override
  String roomTeamFinaleScore(int won, int counted) {
    final wordingEdit = _edits['roomTeamFinaleScore'];
    if (wordingEdit == null) return super.roomTeamFinaleScore(won, counted);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'won': () => '$won',
                  'counted': () => '$counted',
                }
              : <String, String Function()>{
                  'won': () => '$won',
                  'counted': () => '$counted',
                },
        ) ??
        super.roomTeamFinaleScore(won, counted);
  }

  @override
  String get roomTeamFinaleCaption => plainWording(_edits['roomTeamFinaleCaption']) ?? super.roomTeamFinaleCaption;

  @override
  String roomTeamFinaleBestStreak(int days) {
    final wordingEdit = _edits['roomTeamFinaleBestStreak'];
    if (wordingEdit == null) return super.roomTeamFinaleBestStreak(days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'daysCount(days)': () => '${daysCount(days)}',
                }
              : <String, String Function()>{
                  'days': () => '$days',
                  'days == 1 ? \'day\' : \'days\'': () => '${days == 1 ? 'day' : 'days'}',
                },
        ) ??
        super.roomTeamFinaleBestStreak(days);
  }

  @override
  String get roomDetailsHidden => plainWording(_edits['roomDetailsHidden']) ?? super.roomDetailsHidden;

  @override
  String get roomDetailsVisible => plainWording(_edits['roomDetailsVisible']) ?? super.roomDetailsVisible;

  @override
  String get roomAddHabitAction => plainWording(_edits['roomAddHabitAction']) ?? super.roomAddHabitAction;

  @override
  String get roomAddHabitPickerTitle => plainWording(_edits['roomAddHabitPickerTitle']) ?? super.roomAddHabitPickerTitle;

  @override
  String get roomAddHabitPickerHint => plainWording(_edits['roomAddHabitPickerHint']) ?? super.roomAddHabitPickerHint;

  @override
  String roomHabitAddedConfirmation(String habitName) {
    final wordingEdit = _edits['roomHabitAddedConfirmation'];
    if (wordingEdit == null) return super.roomHabitAddedConfirmation(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomHabitAddedConfirmation(habitName);
  }

  @override
  String roomHabitAlreadyInPlan(String habitName) {
    final wordingEdit = _edits['roomHabitAlreadyInPlan'];
    if (wordingEdit == null) return super.roomHabitAlreadyInPlan(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomHabitAlreadyInPlan(habitName);
  }

  @override
  String get roomAddAnotherHabitAction => plainWording(_edits['roomAddAnotherHabitAction']) ?? super.roomAddAnotherHabitAction;

  @override
  String get roomAddAnotherHabitPickerTitle => plainWording(_edits['roomAddAnotherHabitPickerTitle']) ?? super.roomAddAnotherHabitPickerTitle;

  @override
  String get roomAddAnotherHabitPickerHint => plainWording(_edits['roomAddAnotherHabitPickerHint']) ?? super.roomAddAnotherHabitPickerHint;

  @override
  String get roomMuteAction => plainWording(_edits['roomMuteAction']) ?? super.roomMuteAction;

  @override
  String get roomUnmuteAction => plainWording(_edits['roomUnmuteAction']) ?? super.roomUnmuteAction;

  @override
  String get roomMutedConfirmation => plainWording(_edits['roomMutedConfirmation']) ?? super.roomMutedConfirmation;

  @override
  String get roomUnmutedConfirmation => plainWording(_edits['roomUnmutedConfirmation']) ?? super.roomUnmutedConfirmation;

  @override
  String get roomNoMoreHabitsToAdd => plainWording(_edits['roomNoMoreHabitsToAdd']) ?? super.roomNoMoreHabitsToAdd;

  @override
  String get roomCreateNewHabitAction => plainWording(_edits['roomCreateNewHabitAction']) ?? super.roomCreateNewHabitAction;

  @override
  String get roomCreateNewHabitSharedNote => plainWording(_edits['roomCreateNewHabitSharedNote']) ?? super.roomCreateNewHabitSharedNote;

  @override
  String roomPossibleDuplicateWarning(String existingName) {
    final wordingEdit = _edits['roomPossibleDuplicateWarning'];
    if (wordingEdit == null) return super.roomPossibleDuplicateWarning(existingName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'existingName': () => '$existingName',
                }
              : <String, String Function()>{
                  'existingName': () => '$existingName',
                },
        ) ??
        super.roomPossibleDuplicateWarning(existingName);
  }

  @override
  String roomNewHabitBannerTitle(String habitName) {
    final wordingEdit = _edits['roomNewHabitBannerTitle'];
    if (wordingEdit == null) return super.roomNewHabitBannerTitle(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomNewHabitBannerTitle(habitName);
  }

  @override
  String get roomNewHabitBannerBody => plainWording(_edits['roomNewHabitBannerBody']) ?? super.roomNewHabitBannerBody;

  @override
  String get roomNewHabitBannerAction => plainWording(_edits['roomNewHabitBannerAction']) ?? super.roomNewHabitBannerAction;

  @override
  String get roomResolveHabitsSheetTitle => plainWording(_edits['roomResolveHabitsSheetTitle']) ?? super.roomResolveHabitsSheetTitle;

  @override
  String get roomLinkedHabitDeletedHint => plainWording(_edits['roomLinkedHabitDeletedHint']) ?? super.roomLinkedHabitDeletedHint;

  @override
  String get habitLinkedRoomWarningTitle => plainWording(_edits['habitLinkedRoomWarningTitle']) ?? super.habitLinkedRoomWarningTitle;

  @override
  String get habitDeleteAnywayAction => plainWording(_edits['habitDeleteAnywayAction']) ?? super.habitDeleteAnywayAction;

  @override
  String get habitDeleteLinkedRoomCancel => plainWording(_edits['habitDeleteLinkedRoomCancel']) ?? super.habitDeleteLinkedRoomCancel;

  @override
  String roomSoleLinkedHabitPausedHint(String habitName) {
    final wordingEdit = _edits['roomSoleLinkedHabitPausedHint'];
    if (wordingEdit == null) return super.roomSoleLinkedHabitPausedHint(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.roomSoleLinkedHabitPausedHint(habitName);
  }

  @override
  String get habitPauseAnywayAction => plainWording(_edits['habitPauseAnywayAction']) ?? super.habitPauseAnywayAction;

  @override
  String get habitEdit => plainWording(_edits['habitEdit']) ?? super.habitEdit;

  @override
  String get habitActionsCancel => plainWording(_edits['habitActionsCancel']) ?? super.habitActionsCancel;

  @override
  String get restDayTitle => plainWording(_edits['restDayTitle']) ?? super.restDayTitle;

  @override
  String restDayOffPlan(String day, String habit) {
    final wordingEdit = _edits['restDayOffPlan'];
    if (wordingEdit == null) return super.restDayOffPlan(day, habit);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'day': () => '$day',
                  'habit': () => '$habit',
                }
              : <String, String Function()>{
                  'day': () => '$day',
                  'habit': () => '$habit',
                },
        ) ??
        super.restDayOffPlan(day, habit);
  }

  @override
  String restDayCoveredBySession(String day) {
    final wordingEdit = _edits['restDayCoveredBySession'];
    if (wordingEdit == null) return super.restDayCoveredBySession(day);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'day': () => '$day',
                }
              : <String, String Function()>{
                  'day': () => '$day',
                },
        ) ??
        super.restDayCoveredBySession(day);
  }

  @override
  String restDayQuotaMet(int done, int target) {
    final wordingEdit = _edits['restDayQuotaMet'];
    if (wordingEdit == null) return super.restDayQuotaMet(done, target);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'target': () => '$target',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'target': () => '$target',
                },
        ) ??
        super.restDayQuotaMet(done, target);
  }

  @override
  String get restDayNotNeeded => plainWording(_edits['restDayNotNeeded']) ?? super.restDayNotNeeded;

  @override
  String restDayCovers(String day) {
    final wordingEdit = _edits['restDayCovers'];
    if (wordingEdit == null) return super.restDayCovers(day);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'day': () => '$day',
                }
              : <String, String Function()>{
                  'day': () => '$day',
                },
        ) ??
        super.restDayCovers(day);
  }

  @override
  String get restDayExtra => plainWording(_edits['restDayExtra']) ?? super.restDayExtra;

  @override
  String restDayQuotaCounts(int after, int target) {
    final wordingEdit = _edits['restDayQuotaCounts'];
    if (wordingEdit == null) return super.restDayQuotaCounts(after, target);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'after': () => '$after',
                  'target': () => '$target',
                }
              : <String, String Function()>{
                  'after': () => '$after',
                  'target': () => '$target',
                },
        ) ??
        super.restDayQuotaCounts(after, target);
  }

  @override
  String get restDayNoPoints => plainWording(_edits['restDayNoPoints']) ?? super.restDayNoPoints;

  @override
  String get restDayWithPoints => plainWording(_edits['restDayWithPoints']) ?? super.restDayWithPoints;

  @override
  String get restDayConfirm => plainWording(_edits['restDayConfirm']) ?? super.restDayConfirm;

  @override
  String get habitPause => plainWording(_edits['habitPause']) ?? super.habitPause;

  @override
  String get habitPauseHint => plainWording(_edits['habitPauseHint']) ?? super.habitPauseHint;

  @override
  String get pauseUntilTitle => plainWording(_edits['pauseUntilTitle']) ?? super.pauseUntilTitle;

  @override
  String pauseUntilSubtitle(String habitName) {
    final wordingEdit = _edits['pauseUntilSubtitle'];
    if (wordingEdit == null) return super.pauseUntilSubtitle(habitName);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'habitName': () => '$habitName',
                }
              : <String, String Function()>{
                  'habitName': () => '$habitName',
                },
        ) ??
        super.pauseUntilSubtitle(habitName);
  }

  @override
  String get pauseUntilManual => plainWording(_edits['pauseUntilManual']) ?? super.pauseUntilManual;

  @override
  String get pauseUntilManualHint => plainWording(_edits['pauseUntilManualHint']) ?? super.pauseUntilManualHint;

  @override
  String get pauseUntilCustom => plainWording(_edits['pauseUntilCustom']) ?? super.pauseUntilCustom;

  @override
  String get pauseUntilCustomHint => plainWording(_edits['pauseUntilCustomHint']) ?? super.pauseUntilCustomHint;

  @override
  String pauseUntilOn(String when) {
    final wordingEdit = _edits['pauseUntilOn'];
    if (wordingEdit == null) return super.pauseUntilOn(when);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'when': () => '$when',
                }
              : <String, String Function()>{
                  'when': () => '$when',
                },
        ) ??
        super.pauseUntilOn(when);
  }

  @override
  String resumesOnBadge(String when) {
    final wordingEdit = _edits['resumesOnBadge'];
    if (wordingEdit == null) return super.resumesOnBadge(when);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'when': () => '$when',
                }
              : <String, String Function()>{
                  'when': () => '$when',
                },
        ) ??
        super.resumesOnBadge(when);
  }

  @override
  String autoResumedConfirmation(String name) {
    final wordingEdit = _edits['autoResumedConfirmation'];
    if (wordingEdit == null) return super.autoResumedConfirmation(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.autoResumedConfirmation(name);
  }

  @override
  String autoResumeBlockedByLimit(String name) {
    final wordingEdit = _edits['autoResumeBlockedByLimit'];
    if (wordingEdit == null) return super.autoResumeBlockedByLimit(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.autoResumeBlockedByLimit(name);
  }

  @override
  String get habitResume => plainWording(_edits['habitResume']) ?? super.habitResume;

  @override
  String get habitResumeHint => plainWording(_edits['habitResumeHint']) ?? super.habitResumeHint;

  @override
  String habitPausedConfirmation(String name) {
    final wordingEdit = _edits['habitPausedConfirmation'];
    if (wordingEdit == null) return super.habitPausedConfirmation(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.habitPausedConfirmation(name);
  }

  @override
  String habitResumedConfirmation(String name) {
    final wordingEdit = _edits['habitResumedConfirmation'];
    if (wordingEdit == null) return super.habitResumedConfirmation(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.habitResumedConfirmation(name);
  }

  @override
  String get habitPausedSection => plainWording(_edits['habitPausedSection']) ?? super.habitPausedSection;

  @override
  String get roomPausedTag => plainWording(_edits['roomPausedTag']) ?? super.roomPausedTag;

  @override
  String get roomStoodDownToday => plainWording(_edits['roomStoodDownToday']) ?? super.roomStoodDownToday;

  @override
  String habitPausedShowAll(int n) {
    final wordingEdit = _edits['habitPausedShowAll'];
    if (wordingEdit == null) return super.habitPausedShowAll(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.habitPausedShowAll(n);
  }

  @override
  String get habitPausedShowLess => plainWording(_edits['habitPausedShowLess']) ?? super.habitPausedShowLess;

  @override
  String get gridSelectPrompt => plainWording(_edits['gridSelectPrompt']) ?? super.gridSelectPrompt;

  @override
  String get habitDeleteForever => plainWording(_edits['habitDeleteForever']) ?? super.habitDeleteForever;

  @override
  String habitDeleteForeverBody(String name) {
    final wordingEdit = _edits['habitDeleteForeverBody'];
    if (wordingEdit == null) return super.habitDeleteForeverBody(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.habitDeleteForeverBody(name);
  }

  @override
  String get habitDeleteForeverConfirm => plainWording(_edits['habitDeleteForeverConfirm']) ?? super.habitDeleteForeverConfirm;

  @override
  String habitDeletedConfirmation(String name) {
    final wordingEdit = _edits['habitDeletedConfirmation'];
    if (wordingEdit == null) return super.habitDeletedConfirmation(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.habitDeletedConfirmation(name);
  }

  @override
  String get habitActionsTitle => plainWording(_edits['habitActionsTitle']) ?? super.habitActionsTitle;

  @override
  String get habitSelectMultiple => plainWording(_edits['habitSelectMultiple']) ?? super.habitSelectMultiple;

  @override
  String get habitArchivedConfirmation => plainWording(_edits['habitArchivedConfirmation']) ?? super.habitArchivedConfirmation;

  @override
  String get roomStatDays => plainWording(_edits['roomStatDays']) ?? super.roomStatDays;

  @override
  String roomOwnRate(int percent) {
    final wordingEdit = _edits['roomOwnRate'];
    if (wordingEdit == null) return super.roomOwnRate(percent);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'percent': () => '$percent',
                }
              : <String, String Function()>{
                  'percent': () => '$percent',
                },
        ) ??
        super.roomOwnRate(percent);
  }

  @override
  String get roomLeaveKeepsRecordBody => plainWording(_edits['roomLeaveKeepsRecordBody']) ?? super.roomLeaveKeepsRecordBody;

  @override
  String get roomYouLabel => plainWording(_edits['roomYouLabel']) ?? super.roomYouLabel;

  @override
  String get roomLeaderLabel => plainWording(_edits['roomLeaderLabel']) ?? super.roomLeaderLabel;

  @override
  String get roomLeaveAction => plainWording(_edits['roomLeaveAction']) ?? super.roomLeaveAction;

  @override
  String get roomLeaveConfirmTitle => plainWording(_edits['roomLeaveConfirmTitle']) ?? super.roomLeaveConfirmTitle;

  @override
  String get roomLeaveConfirmBody => plainWording(_edits['roomLeaveConfirmBody']) ?? super.roomLeaveConfirmBody;

  @override
  String get roomLeaveConfirmBodyLeader => plainWording(_edits['roomLeaveConfirmBodyLeader']) ?? super.roomLeaveConfirmBodyLeader;

  @override
  String get roomLeaveConfirmCancel => plainWording(_edits['roomLeaveConfirmCancel']) ?? super.roomLeaveConfirmCancel;

  @override
  String get roomDeleteAction => plainWording(_edits['roomDeleteAction']) ?? super.roomDeleteAction;

  @override
  String get roomDeleteConfirmTitle => plainWording(_edits['roomDeleteConfirmTitle']) ?? super.roomDeleteConfirmTitle;

  @override
  String get roomDeleteConfirmBody => plainWording(_edits['roomDeleteConfirmBody']) ?? super.roomDeleteConfirmBody;

  @override
  String get roomGoneMessage => plainWording(_edits['roomGoneMessage']) ?? super.roomGoneMessage;

  @override
  String get roomExtendAction => plainWording(_edits['roomExtendAction']) ?? super.roomExtendAction;

  @override
  String get roomExtendTitle => plainWording(_edits['roomExtendTitle']) ?? super.roomExtendTitle;

  @override
  String roomCadenceWeekly(int n) {
    final wordingEdit = _edits['roomCadenceWeekly'];
    if (wordingEdit == null) return super.roomCadenceWeekly(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.roomCadenceWeekly(n);
  }

  @override
  String get roomCadenceDaily => plainWording(_edits['roomCadenceDaily']) ?? super.roomCadenceDaily;

  @override
  String get roomExtendBody => plainWording(_edits['roomExtendBody']) ?? super.roomExtendBody;

  @override
  String get roomExtended => plainWording(_edits['roomExtended']) ?? super.roomExtended;

  @override
  String get roomFinaleExtendAction => plainWording(_edits['roomFinaleExtendAction']) ?? super.roomFinaleExtendAction;

  @override
  String get roomFinaleExtendHint => plainWording(_edits['roomFinaleExtendHint']) ?? super.roomFinaleExtendHint;

  @override
  String get roomFinaleMemberHint => plainWording(_edits['roomFinaleMemberHint']) ?? super.roomFinaleMemberHint;

  @override
  String get notificationsTitle => plainWording(_edits['notificationsTitle']) ?? super.notificationsTitle;

  @override
  String get notifMasterTitle => plainWording(_edits['notifMasterTitle']) ?? super.notifMasterTitle;

  @override
  String get notifMasterDesc => plainWording(_edits['notifMasterDesc']) ?? super.notifMasterDesc;

  @override
  String get notifWhatSection => plainWording(_edits['notifWhatSection']) ?? super.notifWhatSection;

  @override
  String get notifHabitReminders => plainWording(_edits['notifHabitReminders']) ?? super.notifHabitReminders;

  @override
  String get notifHabitRemindersDesc => plainWording(_edits['notifHabitRemindersDesc']) ?? super.notifHabitRemindersDesc;

  @override
  String get notifStreakRisk => plainWording(_edits['notifStreakRisk']) ?? super.notifStreakRisk;

  @override
  String get notifStreakRiskDesc => plainWording(_edits['notifStreakRiskDesc']) ?? super.notifStreakRiskDesc;

  @override
  String get notifMatrixNudge => plainWording(_edits['notifMatrixNudge']) ?? super.notifMatrixNudge;

  @override
  String get notifMatrixNudgeDesc => plainWording(_edits['notifMatrixNudgeDesc']) ?? super.notifMatrixNudgeDesc;

  @override
  String get notifBundle => plainWording(_edits['notifBundle']) ?? super.notifBundle;

  @override
  String get notifBundleDesc => plainWording(_edits['notifBundleDesc']) ?? super.notifBundleDesc;

  @override
  String get notifWeeklyDigest => plainWording(_edits['notifWeeklyDigest']) ?? super.notifWeeklyDigest;

  @override
  String get notifWeeklyDigestDesc => plainWording(_edits['notifWeeklyDigestDesc']) ?? super.notifWeeklyDigestDesc;

  @override
  String get notifRoomActivity => plainWording(_edits['notifRoomActivity']) ?? super.notifRoomActivity;

  @override
  String get notifRoomActivityDesc => plainWording(_edits['notifRoomActivityDesc']) ?? super.notifRoomActivityDesc;

  @override
  String get notifLocationNotSet => plainWording(_edits['notifLocationNotSet']) ?? super.notifLocationNotSet;

  @override
  String get notifDetectingLocation => plainWording(_edits['notifDetectingLocation']) ?? super.notifDetectingLocation;

  @override
  String get notifLocationDetectFailed => plainWording(_edits['notifLocationDetectFailed']) ?? super.notifLocationDetectFailed;

  @override
  String get notifCalcMethod => plainWording(_edits['notifCalcMethod']) ?? super.notifCalcMethod;

  @override
  String get notifQuietHoursSection => plainWording(_edits['notifQuietHoursSection']) ?? super.notifQuietHoursSection;

  @override
  String get notifQuietHours => plainWording(_edits['notifQuietHours']) ?? super.notifQuietHours;

  @override
  String get notifQuietHoursDesc => plainWording(_edits['notifQuietHoursDesc']) ?? super.notifQuietHoursDesc;

  @override
  String get notifQuietStart => plainWording(_edits['notifQuietStart']) ?? super.notifQuietStart;

  @override
  String get notifQuietEnd => plainWording(_edits['notifQuietEnd']) ?? super.notifQuietEnd;

  @override
  String get notifQuietAppliesToPrayer => plainWording(_edits['notifQuietAppliesToPrayer']) ?? super.notifQuietAppliesToPrayer;

  @override
  String get notifQuietAppliesToPrayerDesc => plainWording(_edits['notifQuietAppliesToPrayerDesc']) ?? super.notifQuietAppliesToPrayerDesc;

  @override
  String get notifTimingSection => plainWording(_edits['notifTimingSection']) ?? super.notifTimingSection;

  @override
  String get notifSendTest => plainWording(_edits['notifSendTest']) ?? super.notifSendTest;

  @override
  String get notifTestSent => plainWording(_edits['notifTestSent']) ?? super.notifTestSent;

  @override
  String get prayerPlaceTitle => plainWording(_edits['prayerPlaceTitle']) ?? super.prayerPlaceTitle;

  @override
  String get prayerPlaceNotSet => plainWording(_edits['prayerPlaceNotSet']) ?? super.prayerPlaceNotSet;

  @override
  String get prayerPlaceNeeded => plainWording(_edits['prayerPlaceNeeded']) ?? super.prayerPlaceNeeded;

  @override
  String get prayerPlaceFromPhone => plainWording(_edits['prayerPlaceFromPhone']) ?? super.prayerPlaceFromPhone;

  @override
  String get prayerPlacePicked => plainWording(_edits['prayerPlacePicked']) ?? super.prayerPlacePicked;

  @override
  String get prayerPlaceUses => plainWording(_edits['prayerPlaceUses']) ?? super.prayerPlaceUses;

  @override
  String get prayerPlaceAuto => plainWording(_edits['prayerPlaceAuto']) ?? super.prayerPlaceAuto;

  @override
  String get prayerPlaceAutoBody => plainWording(_edits['prayerPlaceAutoBody']) ?? super.prayerPlaceAutoBody;

  @override
  String get prayerPlaceCity => plainWording(_edits['prayerPlaceCity']) ?? super.prayerPlaceCity;

  @override
  String get prayerPlaceCityBody => plainWording(_edits['prayerPlaceCityBody']) ?? super.prayerPlaceCityBody;

  @override
  String get prayerPlaceBahrainTable => plainWording(_edits['prayerPlaceBahrainTable']) ?? super.prayerPlaceBahrainTable;

  @override
  String get prayerLocationTitle => plainWording(_edits['prayerLocationTitle']) ?? super.prayerLocationTitle;

  @override
  String get prayerLocationPrivacyNote => plainWording(_edits['prayerLocationPrivacyNote']) ?? super.prayerLocationPrivacyNote;

  @override
  String get citySearchHint => plainWording(_edits['citySearchHint']) ?? super.citySearchHint;

  @override
  String get citySearchNoResults => plainWording(_edits['citySearchNoResults']) ?? super.citySearchNoResults;

  @override
  String get citySearchPrompt => plainWording(_edits['citySearchPrompt']) ?? super.citySearchPrompt;

  @override
  String get citySearchEnterManually => plainWording(_edits['citySearchEnterManually']) ?? super.citySearchEnterManually;

  @override
  String get citySearchBackToSearch => plainWording(_edits['citySearchBackToSearch']) ?? super.citySearchBackToSearch;

  @override
  String get locationLabelHint => plainWording(_edits['locationLabelHint']) ?? super.locationLabelHint;

  @override
  String get latitude => plainWording(_edits['latitude']) ?? super.latitude;

  @override
  String get longitude => plainWording(_edits['longitude']) ?? super.longitude;

  @override
  String get useTheseCoordinates => plainWording(_edits['useTheseCoordinates']) ?? super.useTheseCoordinates;

  @override
  String get journeyTitle => plainWording(_edits['journeyTitle']) ?? super.journeyTitle;

  @override
  String get journeyEmptyTitle => plainWording(_edits['journeyEmptyTitle']) ?? super.journeyEmptyTitle;

  @override
  String get journeyEmptyBody => plainWording(_edits['journeyEmptyBody']) ?? super.journeyEmptyBody;

  @override
  String journeyMemberSince(String monthYear, int days) {
    final wordingEdit = _edits['journeyMemberSince'];
    if (wordingEdit == null) return super.journeyMemberSince(monthYear, days);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'monthYear': () => '$monthYear',
                  'days': () => '$days',
                }
              : <String, String Function()>{
                  'monthYear': () => '$monthYear',
                  'days': () => '$days',
                },
        ) ??
        super.journeyMemberSince(monthYear, days);
  }

  @override
  String get lifeTimelineTitle => plainWording(_edits['lifeTimelineTitle']) ?? super.lifeTimelineTitle;

  @override
  String get lifeTimelineSubtitle => plainWording(_edits['lifeTimelineSubtitle']) ?? super.lifeTimelineSubtitle;

  @override
  String lifeTimelineSince(String monthYear) {
    final wordingEdit = _edits['lifeTimelineSince'];
    if (wordingEdit == null) return super.lifeTimelineSince(monthYear);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'monthYear': () => '$monthYear',
                }
              : <String, String Function()>{
                  'monthYear': () => '$monthYear',
                },
        ) ??
        super.lifeTimelineSince(monthYear);
  }

  @override
  String lifeTimelineYearTotal(int total) {
    final wordingEdit = _edits['lifeTimelineYearTotal'];
    if (wordingEdit == null) return super.lifeTimelineYearTotal(total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'total': () => '$total',
                },
        ) ??
        super.lifeTimelineYearTotal(total);
  }

  @override
  String get lifeTimelineOpenHeatmap => plainWording(_edits['lifeTimelineOpenHeatmap']) ?? super.lifeTimelineOpenHeatmap;

  @override
  String lifeTimelineUpgradeBody(int freeMonths) {
    final wordingEdit = _edits['lifeTimelineUpgradeBody'];
    if (wordingEdit == null) return super.lifeTimelineUpgradeBody(freeMonths);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'freeMonths': () => '$freeMonths',
                }
              : <String, String Function()>{
                  'freeMonths': () => '$freeMonths',
                },
        ) ??
        super.lifeTimelineUpgradeBody(freeMonths);
  }

  @override
  String get roomMemberActions => plainWording(_edits['roomMemberActions']) ?? super.roomMemberActions;

  @override
  String get roomReportAction => plainWording(_edits['roomReportAction']) ?? super.roomReportAction;

  @override
  String get roomBlockAction => plainWording(_edits['roomBlockAction']) ?? super.roomBlockAction;

  @override
  String get roomReportMemberMenu => plainWording(_edits['roomReportMemberMenu']) ?? super.roomReportMemberMenu;

  @override
  String get roomReportPickMember => plainWording(_edits['roomReportPickMember']) ?? super.roomReportPickMember;

  @override
  String get roomReportNobodyYet => plainWording(_edits['roomReportNobodyYet']) ?? super.roomReportNobodyYet;

  @override
  String get roomUnblockAction => plainWording(_edits['roomUnblockAction']) ?? super.roomUnblockAction;

  @override
  String roomReportTitle(String name) {
    final wordingEdit = _edits['roomReportTitle'];
    if (wordingEdit == null) return super.roomReportTitle(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomReportTitle(name);
  }

  @override
  String get roomReportSubtitle => plainWording(_edits['roomReportSubtitle']) ?? super.roomReportSubtitle;

  @override
  String get roomReportReasonName => plainWording(_edits['roomReportReasonName']) ?? super.roomReportReasonName;

  @override
  String get roomReportReasonHarassment => plainWording(_edits['roomReportReasonHarassment']) ?? super.roomReportReasonHarassment;

  @override
  String get roomReportReasonSpam => plainWording(_edits['roomReportReasonSpam']) ?? super.roomReportReasonSpam;

  @override
  String get roomReportReasonOther => plainWording(_edits['roomReportReasonOther']) ?? super.roomReportReasonOther;

  @override
  String get roomReportNoteHint => plainWording(_edits['roomReportNoteHint']) ?? super.roomReportNoteHint;

  @override
  String get roomReportSubmit => plainWording(_edits['roomReportSubmit']) ?? super.roomReportSubmit;

  @override
  String get roomReportThanks => plainWording(_edits['roomReportThanks']) ?? super.roomReportThanks;

  @override
  String get roomReportAlsoBlock => plainWording(_edits['roomReportAlsoBlock']) ?? super.roomReportAlsoBlock;

  @override
  String roomBlockedConfirm(String name) {
    final wordingEdit = _edits['roomBlockedConfirm'];
    if (wordingEdit == null) return super.roomBlockedConfirm(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomBlockedConfirm(name);
  }

  @override
  String roomUnblockedConfirm(String name) {
    final wordingEdit = _edits['roomUnblockedConfirm'];
    if (wordingEdit == null) return super.roomUnblockedConfirm(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomUnblockedConfirm(name);
  }

  @override
  String get roomBlockExplain => plainWording(_edits['roomBlockExplain']) ?? super.roomBlockExplain;

  @override
  String get roomBlockedShow => plainWording(_edits['roomBlockedShow']) ?? super.roomBlockedShow;

  @override
  String get roomNameNotAllowed => plainWording(_edits['roomNameNotAllowed']) ?? super.roomNameNotAllowed;

  @override
  String roomReactionJoined(String name) {
    final wordingEdit = _edits['roomReactionJoined'];
    if (wordingEdit == null) return super.roomReactionJoined(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomReactionJoined(name);
  }

  @override
  String roomReactionFinished(String name) {
    final wordingEdit = _edits['roomReactionFinished'];
    if (wordingEdit == null) return super.roomReactionFinished(name);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'name': () => '$name',
                }
              : <String, String Function()>{
                  'name': () => '$name',
                },
        ) ??
        super.roomReactionFinished(name);
  }

  @override
  String matrixRewardFloatXp(int xp) {
    final wordingEdit = _edits['matrixRewardFloatXp'];
    if (wordingEdit == null) return super.matrixRewardFloatXp(xp);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'xp': () => '$xp',
                }
              : <String, String Function()>{
                  'xp': () => '$xp',
                },
        ) ??
        super.matrixRewardFloatXp(xp);
  }

  @override
  String matrixRewardFloatGold(int gold) {
    final wordingEdit = _edits['matrixRewardFloatGold'];
    if (wordingEdit == null) return super.matrixRewardFloatGold(gold);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'gold': () => '$gold',
                }
              : <String, String Function()>{
                  'gold': () => '$gold',
                },
        ) ??
        super.matrixRewardFloatGold(gold);
  }

  @override
  String get matrixAddedForLater => plainWording(_edits['matrixAddedForLater']) ?? super.matrixAddedForLater;

  @override
  String get monthlyStoryTitle => plainWording(_edits['monthlyStoryTitle']) ?? super.monthlyStoryTitle;

  @override
  String get monthlyStoryEmpty => plainWording(_edits['monthlyStoryEmpty']) ?? super.monthlyStoryEmpty;

  @override
  String monthlyStoryHeadline(String month) {
    final wordingEdit = _edits['monthlyStoryHeadline'];
    if (wordingEdit == null) return super.monthlyStoryHeadline(month);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'month': () => '$month',
                }
              : <String, String Function()>{
                  'month': () => '$month',
                },
        ) ??
        super.monthlyStoryHeadline(month);
  }

  @override
  String get monthlyStoryGreenSquares => plainWording(_edits['monthlyStoryGreenSquares']) ?? super.monthlyStoryGreenSquares;

  @override
  String get monthlyStoryShareAction => plainWording(_edits['monthlyStoryShareAction']) ?? super.monthlyStoryShareAction;

  @override
  String monthlyStoryShareText(String month, int greenSquares, int perfectDays, int levelUps, int achievements) {
    final wordingEdit = _edits['monthlyStoryShareText'];
    if (wordingEdit == null) return super.monthlyStoryShareText(month, greenSquares, perfectDays, levelUps, achievements);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'month': () => '$month',
                  'greenSquares': () => '$greenSquares',
                  'perfectDays': () => '$perfectDays',
                  'levelUps': () => '$levelUps',
                  'achievements': () => '$achievements',
                }
              : <String, String Function()>{
                  'month': () => '$month',
                  'greenSquares': () => '$greenSquares',
                  'perfectDays': () => '$perfectDays',
                  'levelUps': () => '$levelUps',
                  'achievements': () => '$achievements',
                },
        ) ??
        super.monthlyStoryShareText(month, greenSquares, perfectDays, levelUps, achievements);
  }

  @override
  String get yearRecordTitle => plainWording(_edits['yearRecordTitle']) ?? super.yearRecordTitle;

  @override
  String get yearRecordEmpty => plainWording(_edits['yearRecordEmpty']) ?? super.yearRecordEmpty;

  @override
  String yearRecordDaysCount(int n) {
    final wordingEdit = _edits['yearRecordDaysCount'];
    if (wordingEdit == null) return super.yearRecordDaysCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.yearRecordDaysCount(n);
  }

  @override
  String yearRecordCleanDaysCount(int n) {
    final wordingEdit = _edits['yearRecordCleanDaysCount'];
    if (wordingEdit == null) return super.yearRecordCleanDaysCount(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.yearRecordCleanDaysCount(n);
  }

  @override
  String get yearRecordArchivedSection => plainWording(_edits['yearRecordArchivedSection']) ?? super.yearRecordArchivedSection;

  @override
  String get monthPickerTitle => plainWording(_edits['monthPickerTitle']) ?? super.monthPickerTitle;

  @override
  String get weekPickerTitle => plainWording(_edits['weekPickerTitle']) ?? super.weekPickerTitle;

  @override
  String get yearPickerTitle => plainWording(_edits['yearPickerTitle']) ?? super.yearPickerTitle;

  @override
  String get monthPickerLocked => plainWording(_edits['monthPickerLocked']) ?? super.monthPickerLocked;

  @override
  String get monthlyStoryLoadFailed => plainWording(_edits['monthlyStoryLoadFailed']) ?? super.monthlyStoryLoadFailed;

  @override
  String get prestigeTitle => plainWording(_edits['prestigeTitle']) ?? super.prestigeTitle;

  @override
  String get prestigeSubtitle => plainWording(_edits['prestigeSubtitle']) ?? super.prestigeSubtitle;

  @override
  String get prestigeAutoOption => plainWording(_edits['prestigeAutoOption']) ?? super.prestigeAutoOption;

  @override
  String prestigeAutoOptionDesc(String currentTitle) {
    final wordingEdit = _edits['prestigeAutoOptionDesc'];
    if (wordingEdit == null) return super.prestigeAutoOptionDesc(currentTitle);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'currentTitle': () => '$currentTitle',
                }
              : <String, String Function()>{
                  'currentTitle': () => '$currentTitle',
                },
        ) ??
        super.prestigeAutoOptionDesc(currentTitle);
  }

  @override
  String prestigeUnlockedAt(int level) {
    final wordingEdit = _edits['prestigeUnlockedAt'];
    if (wordingEdit == null) return super.prestigeUnlockedAt(level);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'level': () => '$level',
                }
              : <String, String Function()>{
                  'level': () => '$level',
                },
        ) ??
        super.prestigeUnlockedAt(level);
  }

  @override
  String prestigeLockedUntil(int level) {
    final wordingEdit = _edits['prestigeLockedUntil'];
    if (wordingEdit == null) return super.prestigeLockedUntil(level);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'level': () => '$level',
                }
              : <String, String Function()>{
                  'level': () => '$level',
                },
        ) ??
        super.prestigeLockedUntil(level);
  }

  @override
  String get categoryBreakdownTitle => plainWording(_edits['categoryBreakdownTitle']) ?? super.categoryBreakdownTitle;

  @override
  String get reportsTitle => plainWording(_edits['reportsTitle']) ?? super.reportsTitle;

  @override
  String get reportsWeekly => plainWording(_edits['reportsWeekly']) ?? super.reportsWeekly;

  @override
  String get reportsMonthly => plainWording(_edits['reportsMonthly']) ?? super.reportsMonthly;

  @override
  String get reportsYearly => plainWording(_edits['reportsYearly']) ?? super.reportsYearly;

  @override
  String get recordTitle => plainWording(_edits['recordTitle']) ?? super.recordTitle;

  @override
  String get recordTabWeek => plainWording(_edits['recordTabWeek']) ?? super.recordTabWeek;

  @override
  String get recordTabMonth => plainWording(_edits['recordTabMonth']) ?? super.recordTabMonth;

  @override
  String get recordTabYear => plainWording(_edits['recordTabYear']) ?? super.recordTabYear;

  @override
  String get recordTabAll => plainWording(_edits['recordTabAll']) ?? super.recordTabAll;

  @override
  String get reportsRate => plainWording(_edits['reportsRate']) ?? super.reportsRate;

  @override
  String get reportsTotalDone => plainWording(_edits['reportsTotalDone']) ?? super.reportsTotalDone;

  @override
  String get reportsLongestRun => plainWording(_edits['reportsLongestRun']) ?? super.reportsLongestRun;

  @override
  String get shareMonthButton => plainWording(_edits['shareMonthButton']) ?? super.shareMonthButton;

  @override
  String get shareYearButton => plainWording(_edits['shareYearButton']) ?? super.shareYearButton;

  @override
  String get shareCardShare => plainWording(_edits['shareCardShare']) ?? super.shareCardShare;

  @override
  String get shareCardCaption => plainWording(_edits['shareCardCaption']) ?? super.shareCardCaption;

  @override
  String get shareCardFailed => plainWording(_edits['shareCardFailed']) ?? super.shareCardFailed;

  @override
  String get reportsPerfect => plainWording(_edits['reportsPerfect']) ?? super.reportsPerfect;

  @override
  String get reportsHabitsSection => plainWording(_edits['reportsHabitsSection']) ?? super.reportsHabitsSection;

  @override
  String get reportsRhythmTitle => plainWording(_edits['reportsRhythmTitle']) ?? super.reportsRhythmTitle;

  @override
  String reportsRhythmBest(String weekday) {
    final wordingEdit = _edits['reportsRhythmBest'];
    if (wordingEdit == null) return super.reportsRhythmBest(weekday);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'weekday': () => '$weekday',
                }
              : <String, String Function()>{
                  'weekday': () => '$weekday',
                },
        ) ??
        super.reportsRhythmBest(weekday);
  }

  @override
  String reportsRhythmWorst(String weekday) {
    final wordingEdit = _edits['reportsRhythmWorst'];
    if (wordingEdit == null) return super.reportsRhythmWorst(weekday);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'weekday': () => '$weekday',
                }
              : <String, String Function()>{
                  'weekday': () => '$weekday',
                },
        ) ??
        super.reportsRhythmWorst(weekday);
  }

  @override
  String get reportsEmptyWeek => plainWording(_edits['reportsEmptyWeek']) ?? super.reportsEmptyWeek;

  @override
  String get reportsEmptyMonth => plainWording(_edits['reportsEmptyMonth']) ?? super.reportsEmptyMonth;

  @override
  String get reportsEmptyYear => plainWording(_edits['reportsEmptyYear']) ?? super.reportsEmptyYear;

  @override
  String get habitStatsThisPeriod => plainWording(_edits['habitStatsThisPeriod']) ?? super.habitStatsThisPeriod;

  @override
  String get habitStatsCurrentStreak => plainWording(_edits['habitStatsCurrentStreak']) ?? super.habitStatsCurrentStreak;

  @override
  String get habitStatsBestStreak => plainWording(_edits['habitStatsBestStreak']) ?? super.habitStatsBestStreak;

  @override
  String get habitStatsDayHint => plainWording(_edits['habitStatsDayHint']) ?? super.habitStatsDayHint;

  @override
  String reportsDayDone(int n) {
    final wordingEdit = _edits['reportsDayDone'];
    if (wordingEdit == null) return super.reportsDayDone(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.reportsDayDone(n);
  }

  @override
  String get reportsDayNothing => plainWording(_edits['reportsDayNothing']) ?? super.reportsDayNothing;

  @override
  String get reportsDayScheduled => plainWording(_edits['reportsDayScheduled']) ?? super.reportsDayScheduled;

  @override
  String get reportsDayNotDue => plainWording(_edits['reportsDayNotDue']) ?? super.reportsDayNotDue;

  @override
  String timesPerDayNote(int n) {
    final wordingEdit = _edits['timesPerDayNote'];
    if (wordingEdit == null) return super.timesPerDayNote(n);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'n': () => '$n',
                }
              : <String, String Function()>{
                  'n': () => '$n',
                },
        ) ??
        super.timesPerDayNote(n);
  }

  @override
  String timesPerDayDecrease(int current) {
    final wordingEdit = _edits['timesPerDayDecrease'];
    if (wordingEdit == null) return super.timesPerDayDecrease(current);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'timesPerDayPhrase(current)': () => '${timesPerDayPhrase(current)}',
                }
              : <String, String Function()>{
                  'timesPerDayPhrase(current)': () => '${timesPerDayPhrase(current)}',
                },
        ) ??
        super.timesPerDayDecrease(current);
  }

  @override
  String timesPerDayIncrease(int current) {
    final wordingEdit = _edits['timesPerDayIncrease'];
    if (wordingEdit == null) return super.timesPerDayIncrease(current);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'timesPerDayPhrase(current)': () => '${timesPerDayPhrase(current)}',
                }
              : <String, String Function()>{
                  'timesPerDayPhrase(current)': () => '${timesPerDayPhrase(current)}',
                },
        ) ??
        super.timesPerDayIncrease(current);
  }

  @override
  String stepLinkRecap(int goal) {
    final wordingEdit = _edits['stepLinkRecap'];
    if (wordingEdit == null) return super.stepLinkRecap(goal);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'goal': () => '$goal',
                }
              : <String, String Function()>{
                  'goal': () => '$goal',
                },
        ) ??
        super.stepLinkRecap(goal);
  }

  @override
  String stepLinkGoal(int goal) {
    final wordingEdit = _edits['stepLinkGoal'];
    if (wordingEdit == null) return super.stepLinkGoal(goal);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'goal': () => '$goal',
                }
              : <String, String Function()>{
                  'goal': () => '$goal',
                },
        ) ??
        super.stepLinkGoal(goal);
  }

  @override
  String get stepGoalCustom => plainWording(_edits['stepGoalCustom']) ?? super.stepGoalCustom;

  @override
  String get stepGoalFieldLabel => plainWording(_edits['stepGoalFieldLabel']) ?? super.stepGoalFieldLabel;

  @override
  String stepGoalOutOfRange(int min, int max) {
    final wordingEdit = _edits['stepGoalOutOfRange'];
    if (wordingEdit == null) return super.stepGoalOutOfRange(min, max);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'min': () => '$min',
                  'max': () => '$max',
                }
              : <String, String Function()>{
                  'min': () => '$min',
                  'max': () => '$max',
                },
        ) ??
        super.stepGoalOutOfRange(min, max);
  }

  @override
  String get helpEmailSubject => plainWording(_edits['helpEmailSubject']) ?? super.helpEmailSubject;

  @override
  String get helpEmailBodyLead => plainWording(_edits['helpEmailBodyLead']) ?? super.helpEmailBodyLead;

  @override
  String get stepLinkSwitch => plainWording(_edits['stepLinkSwitch']) ?? super.stepLinkSwitch;

  @override
  String get stepLinkedBadge => plainWording(_edits['stepLinkedBadge']) ?? super.stepLinkedBadge;

  @override
  String get stepLinkDenied => plainWording(_edits['stepLinkDenied']) ?? super.stepLinkDenied;

  @override
  String get stepLinkUnsupported => plainWording(_edits['stepLinkUnsupported']) ?? super.stepLinkUnsupported;

  @override
  String get stepsUnit => plainWording(_edits['stepsUnit']) ?? super.stepsUnit;

  @override
  String stepsGoalShort(String goal) {
    final wordingEdit = _edits['stepsGoalShort'];
    if (wordingEdit == null) return super.stepsGoalShort(goal);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'goal': () => '$goal',
                }
              : <String, String Function()>{
                  'goal': () => '$goal',
                },
        ) ??
        super.stepsGoalShort(goal);
  }

  @override
  String get stepsLinkBlocked => plainWording(_edits['stepsLinkBlocked']) ?? super.stepsLinkBlocked;

  @override
  String get stepsLinkNoProvider => plainWording(_edits['stepsLinkNoProvider']) ?? super.stepsLinkNoProvider;

  @override
  String get gridMoreActions => plainWording(_edits['gridMoreActions']) ?? super.gridMoreActions;

  @override
  String get reorderHabitsTitle => plainWording(_edits['reorderHabitsTitle']) ?? super.reorderHabitsTitle;

  @override
  String get reorderHabitsHint => plainWording(_edits['reorderHabitsHint']) ?? super.reorderHabitsHint;

  @override
  String get reorderHabitsMenuHint => plainWording(_edits['reorderHabitsMenuHint']) ?? super.reorderHabitsMenuHint;

  @override
  String get gridSelectMultiple => plainWording(_edits['gridSelectMultiple']) ?? super.gridSelectMultiple;

  @override
  String get gridSelectMultipleHint => plainWording(_edits['gridSelectMultipleHint']) ?? super.gridSelectMultipleHint;

  @override
  String get notifLocationSearchAction => plainWording(_edits['notifLocationSearchAction']) ?? super.notifLocationSearchAction;

  @override
  String get gridNoteSaved => plainWording(_edits['gridNoteSaved']) ?? super.gridNoteSaved;

  @override
  String get gridNoteCleared => plainWording(_edits['gridNoteCleared']) ?? super.gridNoteCleared;

  @override
  String get gridNoteSaveFailed => plainWording(_edits['gridNoteSaveFailed']) ?? super.gridNoteSaveFailed;

  @override
  String get gridNoteSemantics => plainWording(_edits['gridNoteSemantics']) ?? super.gridNoteSemantics;

  @override
  String get gridNoteSeeAll => plainWording(_edits['gridNoteSeeAll']) ?? super.gridNoteSeeAll;

  @override
  String get gridNotesMenuHint => plainWording(_edits['gridNotesMenuHint']) ?? super.gridNotesMenuHint;

  @override
  String get gridJournalFilterHasNote => plainWording(_edits['gridJournalFilterHasNote']) ?? super.gridJournalFilterHasNote;

  @override
  String get heatDayNoteLabel => plainWording(_edits['heatDayNoteLabel']) ?? super.heatDayNoteLabel;

  @override
  String get gridJournalSearchThisMonth => plainWording(_edits['gridJournalSearchThisMonth']) ?? super.gridJournalSearchThisMonth;

  @override
  String gridJournalSearchProgress(int done, int total) {
    final wordingEdit = _edits['gridJournalSearchProgress'];
    if (wordingEdit == null) return super.gridJournalSearchProgress(done, total);
    return fillWording(
          wordingEdit,
          isAr
              ? <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                }
              : <String, String Function()>{
                  'done': () => '$done',
                  'total': () => '$total',
                },
        ) ??
        super.gridJournalSearchProgress(done, total);
  }

  @override
  String get gridJournalSearchBackToMonth => plainWording(_edits['gridJournalSearchBackToMonth']) ?? super.gridJournalSearchBackToMonth;
}

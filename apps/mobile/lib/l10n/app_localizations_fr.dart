// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonTryAgain => 'Réessayer';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonSignIn => 'Se connecter';

  @override
  String get commonMax => 'Max';

  @override
  String get commonBuy => 'Acheter';

  @override
  String get commonSell => 'Vendre';

  @override
  String get rankRookie => 'Recrue';

  @override
  String get rankAnalyst => 'Analyste';

  @override
  String get rankTrader => 'Trader';

  @override
  String get rankSeniorTrader => 'Trader senior';

  @override
  String get rankPartner => 'Associé';

  @override
  String get rankLegend => 'Légende';

  @override
  String formatCompactThousand(String value) {
    return '$value k';
  }

  @override
  String formatCompactMillion(String value) {
    return '$value M';
  }

  @override
  String formatCompactBillion(String value) {
    return '$value Md';
  }

  @override
  String formatCompactTrillion(String value) {
    return '$value Bn';
  }

  @override
  String get marketPriceUnavailable => 'Prix indisponible';

  @override
  String get commonAddMoney => 'Ajouter de l’argent';

  @override
  String get commonSaving => 'Enregistrement…';

  @override
  String get commonChecking => 'Vérification…';

  @override
  String get commonConnecting => 'Connexion…';

  @override
  String get commonSending => 'Envoi…';

  @override
  String get commonConfirming => 'Confirmation…';

  @override
  String get commonLoading => 'Chargement…';

  @override
  String get commonOpen => 'Ouvrir';

  @override
  String get commonRefresh => 'Actualiser';

  @override
  String get commonCopy => 'Copier';

  @override
  String get commonNotNow => 'Pas maintenant';

  @override
  String get commonSkip => 'Passer';

  @override
  String get commonHistory => 'Historique';

  @override
  String get commonSettings => 'Réglages';

  @override
  String commonInProgress(String label) {
    return '$label en cours';
  }

  @override
  String get modePaper => 'Entraînement';

  @override
  String get modeReal => 'Réel';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguagePhone => 'Langue du téléphone';

  @override
  String get settingsLanguagePhoneDetail =>
      'Utilise la langue de ton téléphone.';

  @override
  String get appGuestChoiceNotSaved =>
      'Impossible d’enregistrer ton choix. Réessaie.';

  @override
  String get appDeskAlreadySaved => 'Ton bureau est déjà enregistré.';

  @override
  String get appDeskReconnecting =>
      'Ton bureau se reconnecte. Réessaie dans un instant.';

  @override
  String get appSwitchedToPaper => 'Mode Entraînement activé.';

  @override
  String get appReasonBeingChecked =>
      'Nous vérifions la raison que tu as enregistrée. Actualise ta carrière.';

  @override
  String get appReasonNeedsPaperDesk =>
      'Ton bureau d’entraînement doit être en ligne avant que tu puisses écrire cette raison.';

  @override
  String get appReasonNeedsPaperBuy =>
      'Cet objectif nécessite un achat d’entraînement confirmé que tu détiens encore. Choisis une action quand tu veux.';

  @override
  String get appPromotionRefreshFirst =>
      'Actualise ta carrière avant de réclamer cette promotion.';

  @override
  String get appPromotionNotPrepared =>
      'Impossible de préparer ta promotion. Réessaie.';

  @override
  String get appPromotionCareerChanged =>
      'Ta carrière a changé. Actualise-la et réessaie.';

  @override
  String get appPaperDeskStillOpening =>
      'Ton bureau d’entraînement est encore en train de s’ouvrir. Réessaie.';

  @override
  String get appFirstTradeStepNotSaved =>
      'Ton opération est en sécurité, mais cette étape n’a pas été enregistrée.';

  @override
  String get appStockCouldNotOpen =>
      'Impossible d’ouvrir cette action. Réessaie.';

  @override
  String get appHistoryCouldNotConnect =>
      'Impossible de charger l’historique. Réessaie.';

  @override
  String get appReportNotSent => 'Le signalement n’a pas été envoyé. Réessaie.';

  @override
  String get appBlockFailed => 'Impossible de bloquer ce trader. Réessaie.';

  @override
  String get appWalletAddressCopied => 'Adresse du portefeuille copiée.';

  @override
  String get appWalletBackupFailed =>
      'Impossible d’ouvrir la sauvegarde du portefeuille. Réessaie.';

  @override
  String get appPaperDeskOpening => 'Ouverture de ton bureau d’entraînement.';

  @override
  String get appPaperDeskOffline =>
      'Ton bureau d’entraînement est hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get appPaperDeskTimeout =>
      'Ton bureau d’entraînement a mis trop de temps à s’ouvrir. Réessaie.';

  @override
  String get appPaperDeskSession =>
      'Ton bureau d’entraînement a besoin d’une nouvelle session. Réessaie.';

  @override
  String get appPaperDeskUnavailable =>
      'Ton bureau d’entraînement est indisponible. Réessaie.';

  @override
  String get appCareerStale =>
      'Affichage de ton dernier parcours confirmé. Actualise pour le mettre à jour.';

  @override
  String get appMissionsMismatch =>
      'Ta carrière a changé pendant le chargement des objectifs. Actualise pour les synchroniser.';

  @override
  String get appMissionsStale =>
      'Affichage de tes derniers objectifs confirmés. Actualise pour les mettre à jour.';

  @override
  String get appMissionsOffline =>
      'Tes objectifs sont hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get appMissionsTimeout =>
      'Tes objectifs ont mis trop de temps à s’ouvrir. Réessaie.';

  @override
  String get appMissionsSession =>
      'Tes objectifs ont besoin d’une nouvelle session. Réessaie.';

  @override
  String get appMissionsRateLimited =>
      'Tes objectifs s’actualisent trop vite. Réessaie dans un moment.';

  @override
  String get appMissionsProfileRequired =>
      'Termine de configurer ton profil Trimmy, puis réessaie.';

  @override
  String get appMissionsUnavailable =>
      'Tes objectifs sont indisponibles. Réessaie.';

  @override
  String get appProfileUnavailable =>
      'Ton profil Trimmy est indisponible. Réessaie.';

  @override
  String get appAccountEntryFailed =>
      'Ton compte est connecté. Essaie à nouveau d’ouvrir ton bureau.';

  @override
  String get appRealBalanceLabel => 'Solde total';

  @override
  String get appRealBalanceUpdating => 'Mise à jour du solde…';

  @override
  String get appRealBalanceUsdcAvailable => 'USDC disponibles';

  @override
  String appRealBalanceSplit(String cash, String stocks) {
    return '$cash de liquidités · $stocks en actions';
  }

  @override
  String get appDeskStaleBoth =>
      'Affichage de ton dernier bureau d’entraînement et de ton parcours confirmés. Les opérations sont en pause jusqu’à la reconnexion de Trimmy.';

  @override
  String get appDeskStalePaper =>
      'Affichage de ton dernier bureau d’entraînement confirmé. Les opérations sont en pause jusqu’à la reconnexion de Trimmy.';

  @override
  String get appTradingCouldNotConnect =>
      'Connexion impossible pour passer des ordres.';

  @override
  String get appTradingChecking => 'Vérification des opérations…';

  @override
  String get appTradingPaused => 'Les opérations sont temporairement en pause.';

  @override
  String get appTradingNotTradeable =>
      'Pas encore disponible avec de l’argent réel.';

  @override
  String get appVersionIssuerUnavailable => 'Émetteur indisponible';

  @override
  String get appVersionBackingUnavailable =>
      'Les détails de la garantie ne sont pas disponibles dans ces données de marché.';

  @override
  String get appVersionTradingHoursUnavailable =>
      'Se négocie sur la blockchain. Les horaires de l’émetteur sont indisponibles.';

  @override
  String get appRealMissionTitle => 'Un objectif d’entraînement';

  @override
  String get appRealMissionBody =>
      'Accomplis-le sur ton bureau d’entraînement.';

  @override
  String get appRealMissionButton => 'Ouvrir le bureau d’entraînement';

  @override
  String get appCloseAccountTitle => 'Fermer ton compte ?';

  @override
  String get appCloseAccountBodyNoWallet =>
      'Tu perdras l’accès au compte enregistré. Les données qui doivent être conservées restent protégées.';

  @override
  String get appCloseAccountBodyWallet =>
      'Garde l’accès à ton portefeuille avant de fermer ton compte. La fermeture ne déplacera pas ses fonds. Tu perdras l’accès à ton bureau enregistré.';

  @override
  String get appCloseAccountBackUpWallet => 'Sauvegarder le portefeuille';

  @override
  String get appCloseAccountConfirm => 'Fermer le compte';

  @override
  String get appFirstTradePrompt =>
      'Choisis une entreprise. Ta première opération est gratuite.';

  @override
  String get appOpeningTrimmy => 'Ouverture de Trimmy';

  @override
  String get appCouldNotOpenTrimmy => 'Impossible d’ouvrir Trimmy';

  @override
  String get appOpeningDesk => 'Ouverture de ton bureau';

  @override
  String get appCouldNotOpenDesk => 'Impossible d’ouvrir ton bureau';

  @override
  String get appOpeningTrade => 'Ouverture de ton opération';

  @override
  String get appCouldNotLoadTrade => 'Impossible de charger ton opération';

  @override
  String get appCouldNotLoadTradeBody =>
      'Réessaie pour voir ton ordre confirmé.';

  @override
  String get appSplashOpening => 'Trimmy s’ouvre';

  @override
  String get designCastSal => 'Sal, ton chef dans la salle des marchés';

  @override
  String get designCastWolf => 'Portrait du trader Wolf';

  @override
  String get designCastOracle => 'Portrait du trader Oracle';

  @override
  String get designCastShark => 'Portrait du trader Shark';

  @override
  String get designPaperMark => 'argent d’entraînement';

  @override
  String designPaperAmount(String amount) {
    return '$amount en argent d’entraînement';
  }

  @override
  String get designUseRealMoney => 'Utiliser de l’argent réel';

  @override
  String get designDismissMessage => 'Fermer le message';

  @override
  String get designCompleted => 'Terminé';

  @override
  String appPromotionTitle(String rankId, String rank) {
    String _temp0 = intl.Intl.selectLogic(rankId, {
      'analyst': 'Te voilà $rank !',
      'other': 'Te voilà $rank !',
    });
    return '$_temp0';
  }

  @override
  String get appPromotionMessage =>
      'Un nouveau chapitre dans la salle des marchés.';

  @override
  String get appPromotionFrom => 'Avant';

  @override
  String get appPromotionNewRank => 'Nouveau grade';

  @override
  String get appPromotionEarned => 'Gagné';

  @override
  String appPromotionTrims(String trims) {
    return '$trims Trims';
  }

  @override
  String get appPromotionBackToCareer => 'Retour à Carrière';

  @override
  String get appFirstPositionTitle => 'Ta première position.';

  @override
  String get appFirstPositionMessage => 'Tu as passé ton premier ordre !';

  @override
  String get appFirstPositionStock => 'Action';

  @override
  String get appFirstPositionShares => 'Quantité';

  @override
  String get appFirstPositionTime => 'Heure';

  @override
  String appFirstPositionTimeUtc(String time) {
    return '$time UTC';
  }

  @override
  String get appDayOneTitle => 'Jour 1, terminé.';

  @override
  String get appDayOneMessage => 'À demain dans la salle des marchés.';

  @override
  String get appSessionGuestRecovery => 'Ce bureau invité doit être récupéré.';

  @override
  String get appSessionAnswersNotSaved =>
      'Impossible d’enregistrer tes réponses. Réessaie une fois.';

  @override
  String get appSessionStepNotSaved =>
      'Impossible d’enregistrer cette étape. Réessaie.';

  @override
  String get appSessionSetupUnreadable =>
      'Impossible d’ouvrir ta configuration Trimmy. Recommence.';

  @override
  String get appSessionReadOffline =>
      'Ton profil est hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get appSessionReadTimeout =>
      'Ton profil a mis trop de temps à s’ouvrir. Réessaie.';

  @override
  String get appSessionReadSession =>
      'Ton profil a besoin d’une nouvelle session. Réessaie.';

  @override
  String get appSessionReadUnavailable =>
      'Ton profil est indisponible. Réessaie.';

  @override
  String get appSessionHandleTaken =>
      'Ce nom est déjà pris. Choisis-en un autre.';

  @override
  String get appSessionTradeRequired =>
      'Ton opération confirmée doit arriver sur ton bureau avant de poursuivre cette étape.';

  @override
  String get appSessionNotReady =>
      'Trimmy confirme encore ce moment. Réessaie.';

  @override
  String get appSessionPrincipalChanged =>
      'L’identité de ton bureau a changé. Rouvre-le et réessaie.';

  @override
  String get appSessionConflict =>
      'Ton profil a changé sur un autre appareil. Réessaie.';

  @override
  String get appSessionWriteOffline =>
      'Tu es hors ligne. Reconnecte-toi et réessaie.';

  @override
  String get appSessionWriteTimeout => 'C’était trop long. Réessaie.';

  @override
  String get appSessionWriteSession =>
      'Ta session a changé. Rouvre ton profil.';

  @override
  String get appSessionWriteFailed =>
      'Cette étape n’a pas été enregistrée. Réessaie.';

  @override
  String get appMarketLoadMoreFailed =>
      'Impossible de charger plus d’actions. Réessaie.';

  @override
  String get appMarketCatalogFailed =>
      'Impossible de charger les actions. Tire vers le bas pour réessayer.';

  @override
  String get appMarketNoStarterPicks =>
      'Les suggestions de départ sont indisponibles. Cherche par entreprise ou par symbole.';

  @override
  String get appMarketNotConfigured =>
      'Les données de marché ne sont pas configurées dans cette version.';

  @override
  String get appMarketBusy =>
      'Les données de marché sont saturées. Réessaie dans un instant.';

  @override
  String get appMarketTimeout =>
      'Les données de marché ont mis trop de temps. Réessaie.';

  @override
  String get appMarketOffline =>
      'Tu es hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get appMarketUnavailable =>
      'Impossible de charger les actions. Réessaie.';

  @override
  String get tabDesk => 'Bureau';

  @override
  String get tabMarket => 'Marché';

  @override
  String get tabCareer => 'Carrière';

  @override
  String get tabProfile => 'Profil';

  @override
  String get firstTradeSkip => 'Passer la première opération';

  @override
  String get firstTradeTitle => 'Ton premier coup.';

  @override
  String get firstTradeOpeningDesk => 'Ouverture de ton bureau d’entraînement…';

  @override
  String get firstTradeDeskUnavailable =>
      'Ton bureau d’entraînement est indisponible. Réessaie.';

  @override
  String get firstTradeContinueError => 'Impossible de continuer. Réessaie.';

  @override
  String get firstTradePickCompany => 'Choisis une entreprise.';

  @override
  String get firstTradeHint => 'Indice';

  @override
  String get firstTradeCompanyGuide =>
      'Une action est une petite part d’une entreprise. Choisis-en une.';

  @override
  String get firstTradeAmountTitle => 'Choisis le montant';

  @override
  String get firstTradeAmountGuide =>
      'Choisis un montant pour essayer. C’est gratuit.';

  @override
  String get firstTradeReviewBuy => 'Vérifier l’achat';

  @override
  String get firstTradeOrderPlaced => 'Tu as passé ton premier ordre !';

  @override
  String get firstTradeCreateProfile =>
      'Maintenant, créons ton profil de trader.';

  @override
  String get firstTradeBuyConfirmed => 'Achat confirmé';

  @override
  String get firstTradeInvested => 'Investi';

  @override
  String firstTradeSharesLine(String shares) {
    return 'Actions  $shares';
  }

  @override
  String firstTradeTrimsEarned(String trims) {
    return '+$trims Trims';
  }

  @override
  String get firstTradeKeepFreeMoney => 'Continuer avec l’argent offert';

  @override
  String get firstTradeKeepFreeMoneyDetail =>
      'Prends confiance sur ton bureau.';

  @override
  String firstTradeSharesCount(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions',
      one: '$shares action',
    );
    return '$_temp0';
  }

  @override
  String firstTradeFreeMoneyAmount(String amount) {
    return '$amount d’argent offert';
  }

  @override
  String get firstTradeNextMove => 'Ton prochain coup.';

  @override
  String get firstTradeNextMoveBody =>
      'Continue à prendre tes marques, ou alimente ton portefeuille.';

  @override
  String get firstTradeAddMoneyDetail => 'Découvre tes options de dépôt.';

  @override
  String get firstTradeAddMoneyLater =>
      'Tu peux ajouter de l’argent depuis ton bureau quand tu veux.';

  @override
  String get firstTradeContinueSafe =>
      'Ton opération est enregistrée. Essaie de continuer à nouveau.';

  @override
  String get amountPickerErrorEmpty => 'Saisis un montant.';

  @override
  String get amountPickerErrorDecimals => 'Utilise 2 décimales au maximum.';

  @override
  String amountPickerErrorMin(String amount) {
    return 'Choisis au moins $amount.';
  }

  @override
  String amountPickerErrorMax(String amount) {
    return 'Choisis au plus $amount.';
  }

  @override
  String get amountPickerFieldLabel => 'Montant en dollars';

  @override
  String amountPickerEditSemantics(num value, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'Montant, $amount dollars. Modifier le montant',
      one: 'Montant, $amount dollar. Modifier le montant',
    );
    return '$_temp0';
  }

  @override
  String amountPickerDecreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Baisser le montant de $amount dollars',
      one: 'Baisser le montant de $amount dollar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerIncreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Augmenter le montant de $amount dollars',
      one: 'Augmenter le montant de $amount dollar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerPresetSemantics(num amount, String amountText) {
    String _temp0 = intl.Intl.pluralLogic(
      amount,
      locale: localeName,
      other: 'Fixer le montant à $amountText dollars',
      one: 'Fixer le montant à $amountText dollar',
    );
    return '$_temp0';
  }

  @override
  String get onboardingGoalLearn => 'Apprendre';

  @override
  String get onboardingGoalLearnDetail => 'Commence par les bases.';

  @override
  String get onboardingGoalPractice => 'M’entraîner';

  @override
  String get onboardingGoalPracticeDetail =>
      'Prends des décisions avec de l’argent d’entraînement.';

  @override
  String get onboardingGoalTrade => 'Trader avec de l’argent d’entraînement';

  @override
  String get onboardingGoalTradeDetail =>
      'Prends confiance avec les prix en temps réel.';

  @override
  String get onboardingGoalFriends => 'Amis';

  @override
  String get onboardingGoalFriendsDetail =>
      'Les ligues ne sont pas encore disponibles.';

  @override
  String get onboardingKnowledgeNothing => 'Rien pour l’instant';

  @override
  String get onboardingKnowledgeBasics => 'Je connais les bases';

  @override
  String get onboardingKnowledgePractised => 'J’ai pratiqué en simulation';

  @override
  String get onboardingKnowledgeTraded => 'J’ai déjà fait du trading';

  @override
  String get onboardingKnowledgeDaily => 'Je fais du trading tous les jours';

  @override
  String get onboardingDailyShowUp => 'Être là';

  @override
  String get onboardingDailyShowUpDetail =>
      'Ouvre Trimmy et jette un œil à ton bureau.';

  @override
  String get onboardingDailyOneMove => 'Un coup';

  @override
  String get onboardingDailyOneMoveDetail =>
      'Fais une opération d’entraînement réfléchie.';

  @override
  String get onboardingDailyThreeMoves => 'Trois coups';

  @override
  String get onboardingDailyThreeMovesDetail =>
      'Fais trois opérations d’entraînement réfléchies.';

  @override
  String get onboardingSalHello =>
      'Cinq petites questions, puis ta première opération d’entraînement.';

  @override
  String get onboardingQuestionGoal => 'Pourquoi es-tu là ?';

  @override
  String get onboardingQuestionKnowledge => 'Où en es-tu avec la bourse ?';

  @override
  String get onboardingQuestionPersona => 'Choisis ton trader.';

  @override
  String get onboardingQuestionDailyGoal => 'Choisis ton objectif quotidien.';

  @override
  String get onboardingQuestionHandle =>
      'Comment doit-on t’appeler dans la salle des marchés ?';

  @override
  String get onboardingHandleLabel => 'Pseudo';

  @override
  String get onboardingHandleHelper => 'De 3 à 18 caractères';

  @override
  String get onboardingHandleTooShort => 'Utilise au moins 3 caractères.';

  @override
  String get onboardingHandleTooLong => 'Utilise 18 caractères maximum.';

  @override
  String get onboardingHandleStartWithLetter => 'Commence par une lettre.';

  @override
  String get onboardingHandleCharacters =>
      'Utilise des lettres, des chiffres ou des tirets bas.';

  @override
  String get onboardingProgressLabel => 'Progression de la configuration';

  @override
  String onboardingProgressValue(int percent) {
    return '$percent pour cent';
  }

  @override
  String onboardingProgressStep(int step, int total) {
    return '$step sur $total';
  }

  @override
  String onboardingSalSays(String text) {
    return 'Sal dit : $text';
  }

  @override
  String get onboardingNotificationsAsk =>
      'Je te préviens à l’ouverture et à la fermeture de Wall Street. Ici, tu peux investir à toute heure.';

  @override
  String get onboardingNotificationsSoon => 'Les alertes sont presque prêtes.';

  @override
  String get onboardingNotificationsPhoneAsks =>
      'Ton téléphone va te demander.';

  @override
  String get onboardingNotificationsKeepSettingUp =>
      'Continue à configurer ton bureau.';

  @override
  String get onboardingNotificationsChangeLater =>
      'Tu peux modifier les alertes à tout moment dans Réglages.';

  @override
  String get onboardingNotificationsLater =>
      'Les alertes apparaîtront ici quand l’envoi sera activé.';

  @override
  String get onboardingNotificationsSaving => 'Enregistrement en cours';

  @override
  String get onboardingNotificationsTurnOn => 'Activer les alertes';

  @override
  String get onboardingReviewAnswers => 'Revoir mes réponses';

  @override
  String get onboardingOpeningMarket => 'Ouverture du marché';

  @override
  String get onboardingSetupNotSaved =>
      'Ta configuration n’a pas été enregistrée. Réessaie.';

  @override
  String get onboardingPermissionRequestFailed =>
      'Le téléphone n’a pas ouvert la demande. Réessaie.';

  @override
  String get onboardingSalPortrait => 'Sal, ton chef de salle';

  @override
  String get onboardingPermissionPreview =>
      'Aperçu de la demande d’autorisation des notifications';

  @override
  String get onboardingIntroSaveError =>
      'Impossible d’enregistrer cette étape. Réessaie.';

  @override
  String get onboardingIntroSaving => 'Enregistrement de ta progression';

  @override
  String get onboardingCouldNotSave => 'Impossible d’enregistrer. Réessaie.';

  @override
  String get onboardingReminderSkip => 'Passer les rappels';

  @override
  String get onboardingReminderTitle => 'Un petit rappel ?';

  @override
  String get onboardingReminderQuestion =>
      'À quelle fréquence veux-tu un rappel ?';

  @override
  String get onboardingReminderPermissionOff =>
      'Les notifications sont désactivées. Tu peux changer ça dans les réglages de ton téléphone.';

  @override
  String get onboardingReminderUnavailable =>
      'Ta préférence est enregistrée. Les notifications ne sont pas encore disponibles dans cette version.';

  @override
  String get onboardingReminderNotSet =>
      'Impossible de programmer le rappel. Réessaie.';

  @override
  String get onboardingReminderChanged =>
      'Ta préférence a changé sur un autre appareil. Choisis à nouveau.';

  @override
  String get onboardingReminderSavedNotSet =>
      'Enregistré sur ce téléphone. Impossible de programmer le rappel. Réessaie.';

  @override
  String get onboardingReminderSavedOffline =>
      'Enregistré sur ce téléphone. La synchronisation réessaiera quand tu seras en ligne.';

  @override
  String get personaWolfName => 'Wolf';

  @override
  String get personaOracleName => 'Oracle';

  @override
  String get personaSharkName => 'Shark';

  @override
  String get personaWolfDetail => 'Intrépide. Rapide. Adore les gros coups.';

  @override
  String get personaOracleDetail => 'Patience d’abord. S’informe avant d’agir.';

  @override
  String get personaSharkDetail => 'Garde son calme quand la foule s’agite.';

  @override
  String personaPortrait(String name) {
    return 'Portrait du trader $name';
  }

  @override
  String get personaPickerTitle => 'Choisis ton trader';

  @override
  String get personaPickerSubtitle => 'Qui veux-tu incarner ?';

  @override
  String get personaPickerChoose => 'Choisir';

  @override
  String get personaPickerSaveError =>
      'Impossible d’enregistrer ton choix. Réessaie.';

  @override
  String welcomeHeadline(String wallStreet) {
    return 'Lance ta carrière à $wallStreet.';
  }

  @override
  String get welcomeHeroSemantics =>
      'Lance ta carrière à Wall Street. Des actions tokenisées gravitent autour de l’invitation.';

  @override
  String get welcomeStartFirstDay => 'Commencer ma première journée';

  @override
  String get welcomeSignInOrCreate => 'Connexion ou inscription';

  @override
  String get welcomeNoteSkip => 'Passer l’introduction';

  @override
  String get welcomeNoteTitle => 'Bienvenue dans\nla salle des marchés.';

  @override
  String get welcomeNoteBody =>
      'Ta première journée commence par un entraînement.\n\nChoisis une entreprise. C’est gratuit.';

  @override
  String get chartPeriodDay => '1J';

  @override
  String get chartPeriodWeek => '1S';

  @override
  String get chartPeriodMonth => '1M';

  @override
  String get chartPeriodYear => '1A';

  @override
  String chartPriceLabel(String from, String to) {
    return 'Graphique des prix. De $from à $to. Maintiens appuyé pour explorer.';
  }

  @override
  String chartTradeBoughtSummary(String shares, String price, String date) {
    return 'Achat : $shares · $price · $date';
  }

  @override
  String chartTradeSoldSummary(String shares, String price, String date) {
    return 'Vente : $shares · $price · $date';
  }

  @override
  String chartTradeBoughtLabel(
    num count,
    String shares,
    String price,
    String date,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tu as acheté $shares actions à $price, $date',
      one: 'Tu as acheté $shares action à $price, $date',
    );
    return '$_temp0';
  }

  @override
  String chartTradeSoldLabel(
    num count,
    String shares,
    String price,
    String date,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tu as vendu $shares actions à $price, $date',
      one: 'Tu as vendu $shares action à $price, $date',
    );
    return '$_temp0';
  }

  @override
  String get chartTradeMarkerBuy => 'A';

  @override
  String get chartTradeMarkerSell => 'V';

  @override
  String get chartNoYear =>
      'Une année d’historique n’est pas encore disponible.';

  @override
  String get chartHistoryUnavailable =>
      'L’historique des prix est indisponible. Réessaie.';

  @override
  String get chartStaleReading =>
      'C’est un ancien relevé. Actualise pour un graphique plus récent.';

  @override
  String get chartNotEnoughReadings =>
      'Il n’y a pas assez de relevés pour cette période.';

  @override
  String get chartSevenDayLabel =>
      'Évolution du prix de l’entreprise sur sept jours';

  @override
  String get chartSevenDayCaption => 'Évolution de l’action cotée sur 7 jours';

  @override
  String get chartNoHistoryForVersion =>
      'L’historique des prix n’est pas encore disponible pour cette version.';

  @override
  String get chartReadingsNotComparable =>
      'Ces relevés ne peuvent pas être comparés de façon fiable.';

  @override
  String chartReadingAt(String time) {
    return '$time UTC · Depuis le premier relevé';
  }

  @override
  String chartRelativeHistoryLabel(String symbol) {
    return 'Historique relatif de $symbol';
  }

  @override
  String chartChangeAtTime(String change, String time) {
    return '$change le $time UTC';
  }

  @override
  String get chartGapsHint =>
      'Les trous signifient que le fournisseur n’a renvoyé aucun relevé. Fais glisser pour explorer.';

  @override
  String get chartDragHint => 'Fais glisser sur le graphique pour explorer.';

  @override
  String get holdersLoadFailedTitle => 'Impossible de charger les détenteurs';

  @override
  String get holdersLoadFailedBody => 'Réessaie dans un instant.';

  @override
  String get holdersEmpty => 'Aucun détenteur à afficher';

  @override
  String get holdersColumnHolder => 'Détenteur';

  @override
  String get holdersColumnTokens => 'Tokens';

  @override
  String holdersSampleNote(String count) {
    return 'Soldes des $count plus grands comptes du token. Ce n’est pas la liste complète des détenteurs.';
  }

  @override
  String get marketTitle => 'Marché';

  @override
  String get marketSubtitle => 'Actions tokenisées';

  @override
  String marketSortTooltip(String sort) {
    return 'Tri : $sort';
  }

  @override
  String get marketSortButtonLabel => 'Trier les actions';

  @override
  String get marketSearchButtonLabel => 'Rechercher des entreprises';

  @override
  String get marketSortTitle => 'Trier les actions chargées';

  @override
  String get marketSortFeatured => 'À la une';

  @override
  String get marketSortName => 'Nom';

  @override
  String get marketSortBiggestGains => 'Plus fortes hausses';

  @override
  String get marketSortBiggestDrops => 'Plus fortes baisses';

  @override
  String get marketSortHighestPrice => 'Prix le plus élevé';

  @override
  String get marketSortMostHeld => 'Les plus détenues';

  @override
  String get marketListAll => 'Toutes';

  @override
  String get marketListStarterPicks => 'Pour débuter';

  @override
  String get marketListTrending => 'Tendances';

  @override
  String get marketListMovers => 'En mouvement';

  @override
  String get marketListMostHeld => 'Les plus détenues';

  @override
  String get marketListFollowing => 'Suivies';

  @override
  String get marketListNewOnChain => 'Nouvelles on-chain';

  @override
  String get marketListTech => 'Technologie';

  @override
  String get marketListFinance => 'Finance';

  @override
  String get marketListEnergy => 'Énergie';

  @override
  String get marketListHealth => 'Santé';

  @override
  String get marketListConsumer => 'Consommation';

  @override
  String get marketListFunds => 'Fonds';

  @override
  String get marketListPreIpo => 'Pré-IPO';

  @override
  String get marketLoadingAll => 'Vérification de toutes les actions…';

  @override
  String get marketEmptyFollowingTitle => 'Ta liste de suivi commence ici.';

  @override
  String get marketEmptyFollowingBody =>
      'Touche Suivre sur une entreprise pour la garder ici.';

  @override
  String get marketEmptyFunds => 'Aucun fonds à afficher pour l’instant.';

  @override
  String get marketEmptyPreIpo =>
      'Aucune entreprise pré-IPO à afficher pour l’instant.';

  @override
  String get marketEmptyStocks => 'Aucune action à afficher pour l’instant.';

  @override
  String get marketEmptyBody => 'Essaie de rechercher une entreprise.';

  @override
  String get marketFindCompany => 'Trouver une entreprise';

  @override
  String get marketFollowingLoadFailed =>
      'Certaines actions n’ont pas chargé. Réessayer';

  @override
  String get marketLoadingMore => 'Chargement d’autres actions';

  @override
  String get marketOffline => 'Tu es hors ligne. Vérifie ta connexion.';

  @override
  String get marketListUnavailable => 'La liste du marché est indisponible.';

  @override
  String marketFollowAdded(String name) {
    return 'Tu suis maintenant $name.';
  }

  @override
  String marketFollowRemoved(String name) {
    return 'Tu ne suis plus $name.';
  }

  @override
  String get marketFollowSignInNeeded =>
      'Connecte-toi pour enregistrer ta liste de suivi.';

  @override
  String get marketFollowListFull =>
      'Ta liste de suivi est pleine. Retire d’abord une entreprise.';

  @override
  String get marketFollowUnchanged => 'Le suivi n’a pas changé. Réessaie.';

  @override
  String get marketFollowButton => '+ Suivre';

  @override
  String get marketFollowingButton => 'Suivie';

  @override
  String get marketTradeable => 'Négociable';

  @override
  String get marketChangeUnavailable => 'Variation indisponible';

  @override
  String marketCardChange24h(String change) {
    return '$change  24 h';
  }

  @override
  String marketCardLabel(
    String tradeable,
    String name,
    String symbol,
    String price,
    String change,
  ) {
    String _temp0 = intl.Intl.selectLogic(tradeable, {
      'yes': '$name, $symbol, $price, $change, négociable',
      'other': '$name, $symbol, $price, $change',
    });
    return '$_temp0';
  }

  @override
  String get marketChangeUnavailableSpoken => 'variation indisponible';

  @override
  String marketChangeSpoken(String direction, String change) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'down': 'En baisse de $change',
      'up': 'En hausse de $change',
      'other': 'Stable à $change',
    });
    return '$_temp0';
  }

  @override
  String marketCompanyLogoLabel(String name) {
    return 'Logo de $name';
  }

  @override
  String get marketPaperMarkLabel => 'argent d’entraînement';

  @override
  String marketPaperAmountLabel(String amount) {
    return '$amount en argent d’entraînement';
  }

  @override
  String get marketSearchHint => 'Nom ou symbole';

  @override
  String get marketSearchClear => 'Effacer la recherche';

  @override
  String get marketRecentTitle => 'Consultées récemment';

  @override
  String get marketRecentClear => 'Effacer';

  @override
  String get marketRecentEmptyTitle => 'Trouve ta prochaine entreprise';

  @override
  String get marketRecentEmptyBody =>
      'Tes recherches récentes s’afficheront ici.';

  @override
  String marketSearchNoResults(String query) {
    return 'Rien ne s’appelle « $query ». Essaie le symbole.';
  }

  @override
  String get marketSearchLoadingResult => 'Chargement de l’entreprise';

  @override
  String get marketSearchDidNotFinish =>
      'La recherche n’a pas abouti. Réessaie.';

  @override
  String get marketSearchStale =>
      'Ces résultats sont anciens. Relance la recherche pour une liste plus récente.';

  @override
  String get marketSearchOffline =>
      'Tu es hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get marketSearchPaused => 'La recherche s’est interrompue. Réessaie.';

  @override
  String get marketSearchRateLimited =>
      'Trop de recherches. Attends un instant et réessaie.';

  @override
  String get marketSearchTimeout =>
      'La recherche a pris trop de temps. Réessaie.';

  @override
  String get marketSearchDisabled =>
      'La recherche d’entreprises n’est pas disponible dans cette version.';

  @override
  String get marketSearchUnavailable =>
      'La recherche d’entreprises est indisponible. Réessaie.';

  @override
  String stockFollowTooltip(String name) {
    return 'Suivre $name';
  }

  @override
  String stockUnfollowTooltip(String name) {
    return 'Ne plus suivre $name';
  }

  @override
  String stockShareTooltip(String name) {
    return 'Partager $name';
  }

  @override
  String get stockPositionTitle => 'Ta position';

  @override
  String get stockPast24h => 'sur 24 h';

  @override
  String get stockChartFailedTitle => 'Le graphique n’a pas chargé';

  @override
  String get stockChartEmptyTitle => 'Pas encore de graphique';

  @override
  String get stockChartEmptyBody =>
      'Ce token a besoin de plus d’historique de prix.';

  @override
  String get stockPriceAlertTooltip => 'Créer une alerte de prix';

  @override
  String stockChartUpdatedAt(String time) {
    return 'Graphique jusqu’à $time';
  }

  @override
  String stockPositionShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions',
      one: '$shares action',
    );
    return '$_temp0';
  }

  @override
  String get stockPositionValue => 'Valeur';

  @override
  String get stockPositionValueAtTrade => 'Valeur lors de l’ordre';

  @override
  String get stockPositionNotPriced => 'Sans prix';

  @override
  String get stockPositionAverageCost => 'Coût moyen';

  @override
  String get stockPositionReturn => 'Rendement';

  @override
  String get stockPositionReturnAtTrade => 'Rendement lors de l’ordre';

  @override
  String get stockSectionsLabel => 'Détails de l’entreprise';

  @override
  String get stockSectionAbout => 'À propos';

  @override
  String get stockSectionHolders => 'Détenteurs';

  @override
  String get stockSectionComments => 'Commentaires';

  @override
  String get stockAboutReadMore => 'Voir plus';

  @override
  String get stockAboutReadLess => 'Voir moins';

  @override
  String get stockMetricVolume24h => 'Volume 24 h';

  @override
  String get stockMetricLiquidity => 'Liquidité';

  @override
  String get stockMetricTokenMarketCap => 'Capitalisation du token';

  @override
  String get stockMetricTokenHolders => 'Détenteurs du token';

  @override
  String get stockMetricCompanyMarketCap => 'Capitalisation de l’entreprise';

  @override
  String get stockMetricSector => 'Secteur';

  @override
  String get stockTokensTitle => 'Tokens disponibles';

  @override
  String stockCopyAddressTooltip(String symbol) {
    return 'Copier l’adresse de $symbol';
  }

  @override
  String get stockAddressCopied => 'Adresse copiée';

  @override
  String get stockAboutEmpty => 'Les détails arrivent';

  @override
  String get stockPracticeInPaper => 'Essayer en Entraînement';

  @override
  String get stockVersionsLabel => 'Versions du token';

  @override
  String stockVersionSelectedLabel(String version) {
    return 'Version du token $version. Changer';
  }

  @override
  String stockVersionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versions',
      one: '$count version',
    );
    return '$_temp0';
  }

  @override
  String get stockVersionsTitle => 'Versions';

  @override
  String get stockVersionNotTradeable => 'Non négociable.';

  @override
  String get reasonWriteTitle => 'Écris ta raison';

  @override
  String get reasonWriteSavedTitle => 'Raison enregistrée';

  @override
  String get reasonWritePrompt => 'Qu’est-ce qui t’a fait acheter ?';

  @override
  String get reasonWriteHint => 'Ton avis sur cette action…';

  @override
  String get reasonWriteSave => 'Enregistrer la raison';

  @override
  String get reasonWriteRetry => 'Réessayer';

  @override
  String get reasonWriteCloseRefresh => 'Fermer et actualiser';

  @override
  String reasonWriteRewardTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get reasonWriteMissionRecorded => 'Objectif enregistré';

  @override
  String reasonWriteHeldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions',
      one: '$shares action',
    );
    return '$_temp0';
  }

  @override
  String get reasonWriteErrorInvalidInput =>
      'Utilise une seule ligne et 180 caractères maximum.';

  @override
  String get reasonWriteErrorOffline =>
      'Tu es hors ligne. Ta raison n’a pas été enregistrée. Réessaie.';

  @override
  String get reasonWriteErrorTimeout =>
      'L’enregistrement a pris trop de temps. Réessaie.';

  @override
  String get reasonWriteErrorAccount =>
      'Actualise ta session avant d’enregistrer cette raison.';

  @override
  String get reasonWriteErrorProfile =>
      'Termine de configurer ton profil avant d’enregistrer cette raison.';

  @override
  String get reasonWriteErrorOrderNotFound =>
      'Cet achat d’entraînement est introuvable. Actualise ton bureau.';

  @override
  String get reasonWriteErrorBuyRequired =>
      'Une raison ne peut être ajoutée qu’à un achat d’entraînement confirmé.';

  @override
  String get reasonWriteErrorPositionRequired =>
      'Tu dois encore détenir cette action pour enregistrer une raison.';

  @override
  String get reasonWriteErrorExists =>
      'Cet achat d’entraînement a déjà une raison. Actualise ta Carrière.';

  @override
  String get reasonWriteErrorRetryMismatch =>
      'Cette nouvelle tentative n’a pas pu être associée. Actualise ta Carrière.';

  @override
  String get reasonWriteErrorRateLimited =>
      'Les raisons sont saturées pour le moment. Réessaie dans un instant.';

  @override
  String get reasonWriteErrorGeneric =>
      'Ta raison n’a pas été enregistrée. Réessaie.';

  @override
  String get reasonPrivacyTitle => 'Qui peut voir mes commentaires';

  @override
  String get reasonPrivacyNobody => 'Personne';

  @override
  String get reasonPrivacyEveryone => 'Tout le monde';

  @override
  String get reasonPrivacyFriends => 'Amis';

  @override
  String reasonPrivacySavingChoice(String choice) {
    return 'Enregistrement de « $choice ».';
  }

  @override
  String get reasonPrivacyLoading => 'Chargement de ton choix.';

  @override
  String get reasonPrivacyNotAvailable =>
      'Ton choix n’est pas encore disponible.';

  @override
  String reasonPrivacySavedStatus(String status) {
    return 'Enregistré. $status';
  }

  @override
  String reasonPrivacyChangedElsewhere(String status) {
    return 'Modifié sur un autre appareil. Actualisé. $status';
  }

  @override
  String get reasonPrivacyNobodyLine =>
      'Tes commentaires ne sont visibles que par toi.';

  @override
  String get reasonPrivacyEveryoneLine =>
      'Tout le monde sur Trimmy peut les voir sur la page de chaque action.';

  @override
  String get reasonPrivacyFriendsLine =>
      'Pas encore disponible. Rien n’est partagé tant qu’il n’y a pas d’amis.';

  @override
  String get reasonPrivacyFriendsAvailableLine =>
      'Seuls tes amis Trimmy peuvent les voir sur la page de chaque action.';

  @override
  String get reasonPrivacyConsentLine =>
      'Tes commentaires et ton pseudo apparaîtront sur la page de cette action pour tout le monde sur Trimmy. Les montants ne s’affichent jamais.';

  @override
  String get reasonPrivacyNobodyOption =>
      'Toi uniquement. C’est le choix par défaut.';

  @override
  String get reasonPrivacyEveryoneOption =>
      'Tout le monde sur Trimmy, sur la page de chaque action.';

  @override
  String reasonPrivacySheetNow(String choice) {
    return 'Actuellement : $choice.';
  }

  @override
  String get reasonPrivacyGuestRecovery =>
      'Ce bureau invité doit être récupéré.';

  @override
  String get reasonPrivacySessionRefresh =>
      'Ta session doit être actualisée. Réessaie.';

  @override
  String get reasonPrivacyLoadOffline =>
      'Tu es hors ligne. Impossible de charger ton choix.';

  @override
  String get reasonPrivacyLoadTimeout =>
      'Ton choix a mis trop de temps à charger.';

  @override
  String get reasonPrivacyLoadSession =>
      'Ta session doit être actualisée pour charger ceci.';

  @override
  String get reasonPrivacyAccountClosed => 'Ce compte est fermé.';

  @override
  String get reasonPrivacyLoadFailed => 'Impossible de charger ton choix.';

  @override
  String get reasonPrivacySaveOffline =>
      'Tu es hors ligne. Ton choix n’est pas encore enregistré.';

  @override
  String reasonPrivacySaveOfflineChoice(String choice) {
    return 'Tu es hors ligne. Le choix « $choice » n’est pas encore enregistré.';
  }

  @override
  String get reasonPrivacySaveTimeout =>
      'L’enregistrement a pris trop de temps. Ton choix n’est pas encore enregistré.';

  @override
  String reasonPrivacySaveTimeoutChoice(String choice) {
    return 'L’enregistrement a pris trop de temps. Le choix « $choice » n’est pas encore enregistré.';
  }

  @override
  String get reasonPrivacySaveSession =>
      'Ta session doit être actualisée. Ton choix n’est pas encore enregistré.';

  @override
  String reasonPrivacySaveSessionChoice(String choice) {
    return 'Ta session doit être actualisée. Le choix « $choice » n’est pas encore enregistré.';
  }

  @override
  String get reasonPrivacySaveAccountClosed =>
      'Ce compte est fermé. Rien n’a été enregistré.';

  @override
  String get reasonPrivacySaveMismatch =>
      'Cet enregistrement n’a pas pu être associé. Choisis à nouveau.';

  @override
  String get reasonPrivacySaveFailed =>
      'Échec de l’enregistrement. Ton choix n’est pas encore enregistré.';

  @override
  String reasonPrivacySaveFailedChoice(String choice) {
    return 'Échec de l’enregistrement. Le choix « $choice » n’est pas encore enregistré.';
  }

  @override
  String get reasonPrivacyRateLimitedLoad =>
      'Trop de changements. Réessaie de charger dans un instant.';

  @override
  String reasonPrivacyRateLimitedLoadSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Trop de changements. Réessaie de charger dans $seconds secondes.',
      one: 'Trop de changements. Réessaie de charger dans $seconds seconde.',
    );
    return '$_temp0';
  }

  @override
  String get reasonPrivacyRateLimitedSave =>
      'Trop de changements. Réessaie d’enregistrer dans un instant.';

  @override
  String reasonPrivacyRateLimitedSaveSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other:
          'Trop de changements. Réessaie d’enregistrer dans $seconds secondes.',
      one: 'Trop de changements. Réessaie d’enregistrer dans $seconds seconde.',
    );
    return '$_temp0';
  }

  @override
  String get reasonReportSheetTitle => 'Pourquoi signales-tu ce commentaire ?';

  @override
  String get reasonReportSheetBody =>
      'Choisis le motif le plus adapté. La personne qui l’a écrit ne verra pas qui l’a signalé.';

  @override
  String get reasonReportConfirmTitle => 'Signaler cette raison ?';

  @override
  String reasonReportConfirmBody(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'spam':
          'Trimmy examinera le signalement pour spam. La raison quittera cette page une fois le signalement reçu.',
      'harassment':
          'Trimmy examinera le signalement pour harcèlement. La raison quittera cette page une fois le signalement reçu.',
      'impersonation':
          'Trimmy examinera le signalement pour usurpation d’identité. La raison quittera cette page une fois le signalement reçu.',
      'unsafe':
          'Trimmy examinera le signalement pour contenu dangereux. La raison quittera cette page une fois le signalement reçu.',
      'other':
          'Trimmy examinera le signalement. La raison quittera cette page une fois le signalement reçu.',
    });
    return '$_temp0';
  }

  @override
  String get reasonReportAction => 'Signaler';

  @override
  String get reasonBlockAction => 'Bloquer';

  @override
  String get reasonReportReceived => 'Signalement reçu.';

  @override
  String reasonBlockConfirmTitle(String handle) {
    return 'Bloquer @$handle ?';
  }

  @override
  String get reasonBlockConfirmBody =>
      'Ses raisons quitteront cette page. Toute amitié et les invitations en attente entre vous seront aussi supprimées. Les raisons publiques restent visibles depuis d’autres comptes.';

  @override
  String reasonBlockDone(String handle) {
    return 'Tu as bloqué @$handle.';
  }

  @override
  String get reasonSafetyErrorConflict =>
      'Ceci a changé sur un autre appareil. Choisis à nouveau.';

  @override
  String get reasonSafetyErrorRateLimited =>
      'Trop de changements à la fois. Attends un moment et réessaie.';

  @override
  String get reasonSafetyErrorUnavailable =>
      'Cette action n’est pas disponible pour ton compte pour le moment.';

  @override
  String get reasonSafetyErrorUnconfirmed =>
      'Impossible de confirmer le résultat. Une nouvelle tentative sera faite sans risque.';

  @override
  String get reasonSafetyErrorGeneric =>
      'Cette action n’a pas pu aboutir. Réessaie.';

  @override
  String get reasonEmpty => 'Aucun commentaire pour l’instant';

  @override
  String get reasonEmptyFriends => 'Aucun commentaire d’amis pour l’instant';

  @override
  String get reasonOwnHistoryIncomplete =>
      'Impossible de charger ici tout ton historique de raisons.';

  @override
  String get reasonOwnStatusFailed =>
      'Impossible de vérifier si ta raison est privée.';

  @override
  String get reasonShowMore => 'Voir plus';

  @override
  String get reasonLoadSessionRefresh =>
      'Ta session doit être actualisée pour charger les commentaires.';

  @override
  String get reasonLoadOffline =>
      'Tu es hors ligne. Impossible de charger les commentaires.';

  @override
  String get reasonLoadTimeout =>
      'Les commentaires ont mis trop de temps à charger.';

  @override
  String get reasonLoadRateLimited =>
      'Les commentaires s’actualisent trop vite. Réessaie dans un instant.';

  @override
  String get reasonLoadFailed => 'Impossible de charger les commentaires.';

  @override
  String get reasonAudienceSemantics => 'Choisis de qui voir les commentaires';

  @override
  String get reasonAudienceEveryone => 'Tout le monde';

  @override
  String get reasonAudienceFriends => 'Amis';

  @override
  String get reasonYouBadge => 'Toi';

  @override
  String reasonSavedAt(String date, String time) {
    return 'Enregistré le $date à $time';
  }

  @override
  String get reasonPrivateLine => 'Ton commentaire est privé.';

  @override
  String get reasonLoadingComments => 'Chargement des commentaires';

  @override
  String get fastBuyTitle => 'Achat rapide';

  @override
  String get fastBuyClose => 'Fermer l’achat rapide';

  @override
  String get fastBuySearchHint => 'Cherche un nom ou un symbole';

  @override
  String get fastBuyOpenFailed => 'Impossible d’ouvrir cette action. Réessaie.';

  @override
  String get fastBuyConnectFailed =>
      'Impossible de se connecter pour passer des ordres.';

  @override
  String get fastBuyNoneAvailable =>
      'Aucune action disponible à l’achat pour le moment.';

  @override
  String get fastBuyNoTradeableMatch =>
      'Aucune action disponible ne correspond à ta recherche.';

  @override
  String get fastBuyNoMatches => 'Aucun résultat pour l’instant.';

  @override
  String paperAmount(String amount) {
    return '$amount en argent d’entraînement';
  }

  @override
  String paperOrderEquivalentPaper(String amount) {
    return '≈ $amount en argent d’entraînement';
  }

  @override
  String paperOrderEquivalentShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $shares actions',
      one: '≈ $shares action',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderConversionAtReview =>
      'La conversion s’affiche à la vérification';

  @override
  String paperOrderBuyTitle(String symbol) {
    return 'Acheter $symbol';
  }

  @override
  String paperOrderSellTitle(String symbol) {
    return 'Vendre $symbol';
  }

  @override
  String get paperOrderReviewBuyTitle => 'Vérifie ton achat';

  @override
  String get paperOrderReviewSellTitle => 'Vérifie ta vente';

  @override
  String get paperOrderConfirmedTitle => 'Opération confirmée';

  @override
  String get paperOrderFirstTradeSwipeHint =>
      'Balaie vers le bas pour modifier ton achat';

  @override
  String get paperOrderFirstTradeSkip => 'Passer la première opération';

  @override
  String get paperOrderFirstTradeReviewTitle => 'Vérifie ton achat.';

  @override
  String get paperOrderSharesLabel => 'Actions';

  @override
  String get paperOrderPricePerShare => 'Prix par action';

  @override
  String get paperOrderFee => 'Frais';

  @override
  String get paperOrderTotal => 'Total';

  @override
  String get paperOrderConfirmingBuy => 'Confirmation de l’achat…';

  @override
  String get paperOrderCheckingPrice => 'Vérification du prix…';

  @override
  String get paperOrderConfirmBuy => 'Confirmer l’achat';

  @override
  String get paperOrderConfirmSell => 'Confirmer la vente';

  @override
  String paperOrderSharesValue(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions',
      one: '$shares action',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSharesAvailable(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions disponibles',
      one: '$shares action disponible',
    );
    return '$_temp0';
  }

  @override
  String paperOrderPaperAvailable(String amount) {
    return 'Disponible : $amount en argent d’entraînement';
  }

  @override
  String paperOrderBuyingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Achat de $shares actions',
      one: 'Achat de $shares action',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSellingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vente de $shares actions',
      one: 'Vente de $shares action',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYouPay => 'Tu paies';

  @override
  String get paperOrderYouReceive => 'Tu reçois';

  @override
  String get paperOrderBuyConfirmed => 'Achat confirmé';

  @override
  String get paperOrderSaleConfirmed => 'Vente confirmée';

  @override
  String paperOrderOnYourDesk(String symbol) {
    return '$symbol est sur ton bureau.';
  }

  @override
  String paperOrderLeftYourDesk(String symbol) {
    return '$symbol a quitté ton bureau.';
  }

  @override
  String paperOrderPositionChanged(String symbol) {
    return 'Ta position sur $symbol a changé.';
  }

  @override
  String paperOrderBoughtShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions achetées',
      one: '$shares action achetée',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSoldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares actions vendues',
      one: '$shares action vendue',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYourPosition => 'Ta position';

  @override
  String get paperOrderPositionValue => 'Valeur de la position';

  @override
  String get paperOrderTrimsEarned => 'Trims gagnés';

  @override
  String get paperOrderReasonLabel => 'Pourquoi as-tu acheté ?';

  @override
  String get paperOrderReasonHint => 'Une ligne claire';

  @override
  String get paperOrderSaveReason => 'Enregistrer la raison';

  @override
  String get paperOrderRetryReason => 'Enregistrer à nouveau';

  @override
  String paperOrderReasonTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get paperOrderReasonSaved => 'Raison enregistrée';

  @override
  String paperOrderReasonQuote(String note) {
    return '« $note »';
  }

  @override
  String get paperOrderReasonUnavailable =>
      'Ton opération est confirmée. Impossible d’enregistrer une raison pour le moment.';

  @override
  String get paperOrderUnitLabel => 'Unité du montant de l’ordre';

  @override
  String get paperOrderUnitPaper => 'Argent';

  @override
  String get paperOrderUnitShares => 'Actions';

  @override
  String get paperOrderKeyDelete => 'Effacer';

  @override
  String get paperOrderKeyDecimal => 'Virgule';

  @override
  String get paperOrderNoVersion =>
      'Cette entreprise n’a pas de version disponible.';

  @override
  String get paperOrderReasonNotSaved =>
      'Opération confirmée. Ta raison n’a pas été enregistrée. Réessaie.';

  @override
  String get paperOrderReasonNotSavedDone =>
      'L’opération est faite, mais la raison n’a pas été enregistrée. Réessaie.';

  @override
  String get paperOrderReasonTooLong =>
      'Utilise une seule ligne et 180 caractères maximum.';

  @override
  String get paperOrderReasonOffline =>
      'Opération confirmée. Tu es hors ligne, ta raison n’a donc pas été enregistrée. Réessaie.';

  @override
  String get paperOrderReasonTimeout =>
      'Opération confirmée. L’enregistrement de la raison a pris trop de temps. Réessaie.';

  @override
  String get paperOrderReasonSessionExpired =>
      'Opération confirmée. Ta session doit être actualisée avant d’enregistrer la raison.';

  @override
  String get paperOrderReasonProfileRequired =>
      'Opération confirmée. Termine de configurer ton profil avant d’enregistrer la raison.';

  @override
  String get paperOrderReasonOrderNotFound =>
      'Opération confirmée. Cet ordre est introuvable. Actualise ton bureau.';

  @override
  String get paperOrderReasonBuyRequired =>
      'Tu ne peux enregistrer une raison qu’après un achat d’entraînement confirmé.';

  @override
  String get paperOrderReasonPositionRequired =>
      'Opération confirmée. Tu dois détenir cette action pour enregistrer une raison.';

  @override
  String get paperOrderReasonExists =>
      'Cette opération a déjà une raison enregistrée. Actualise ta carrière.';

  @override
  String get paperOrderReasonRetryMismatch =>
      'Opération confirmée. Cette nouvelle tentative n’a pas pu être associée. Actualise ta carrière.';

  @override
  String get paperOrderReasonBusy =>
      'Opération confirmée. Trop de raisons sont enregistrées en ce moment. Réessaie dans un instant.';

  @override
  String get paperOrderErrorInvalidAmount =>
      'Saisis un montant supérieur à zéro.';

  @override
  String get paperOrderErrorInsufficientPaper =>
      'Tu n’as pas assez d’argent d’entraînement pour cet ordre.';

  @override
  String get paperOrderErrorInsufficientShares =>
      'Tu n’as pas assez d’actions à vendre.';

  @override
  String get paperOrderErrorQuoteExpired =>
      'Ce prix a expiré. Consulte une nouvelle cotation.';

  @override
  String get paperOrderErrorPriceChanged =>
      'Le prix a bougé. Consulte la nouvelle cotation.';

  @override
  String get paperOrderErrorOffline =>
      'Tu es hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get paperOrderErrorTimeout => 'C’était trop long. Réessaie.';

  @override
  String get paperOrderErrorAccountRequired =>
      'Enregistre ton bureau avant de passer cet ordre.';

  @override
  String get paperOrderErrorDuplicate =>
      'Cet ordre a déjà été reçu. Actualise ton bureau.';

  @override
  String get paperOrderErrorRejected => 'L’ordre n’a pas été accepté.';

  @override
  String get paperOrderErrorUnavailable => 'L’ordre n’est pas passé. Réessaie.';

  @override
  String get liveOrderErrorAddUsdc =>
      'Ajoute d’abord des USDC à ton portefeuille Solana.';

  @override
  String get liveOrderErrorAddSol =>
      'Ajoute des SOL pour couvrir les frais de réseau et de compte.';

  @override
  String get liveOrderErrorInsufficientHoldings =>
      'Tu n’as pas assez de ce token pour vendre.';

  @override
  String get liveOrderErrorTradeLimit =>
      'Cet ordre dépasse la limite actuelle par opération.';

  @override
  String get liveOrderErrorAppUpdate =>
      'Mets à jour Trimmy pour lire les conditions de l’émetteur avant d’investir.';

  @override
  String get liveOrderErrorTermsRequired =>
      'Confirme les conditions de l’émetteur pour continuer.';

  @override
  String get liveOrderErrorWalletRequired =>
      'Crée ton portefeuille pour continuer.';

  @override
  String get liveOrderErrorOrderPending =>
      'Ton opération précédente est encore en cours de confirmation.';

  @override
  String get liveOrderErrorQuoteExpired =>
      'Ce prix a expiré. Demande une nouvelle cotation.';

  @override
  String get liveOrderErrorBusy =>
      'Les cotations sont surchargées. Réessaie dans un instant.';

  @override
  String get liveOrderErrorNoRoute =>
      'Aucune route pour cet ordre en ce moment. Essaie un autre montant.';

  @override
  String get liveOrderErrorMarketClosed =>
      'Cette action se négocie quand les marchés américains sont ouverts. Réessaie à ce moment-là.';

  @override
  String get liveOrderErrorBelowMinimum =>
      'Cet ordre est sous le minimum du teneur de marché. Essaie un montant plus élevé.';

  @override
  String get liveOrderErrorPriceOffMarket =>
      'Ce prix est trop éloigné du marché en ce moment. Réessaie bientôt ou avec un montant plus petit.';

  @override
  String get liveOrderErrorFeeTooHigh =>
      'Les frais sont trop élevés pour cet ordre. Réessaie plus tard.';

  @override
  String get liveOrderErrorAccountRequired =>
      'Reconnecte-toi pour utiliser ton portefeuille.';

  @override
  String get liveOrderErrorFreshQuote =>
      'Cet ordre a besoin d’une nouvelle cotation.';

  @override
  String get liveOrderErrorUnavailable =>
      'Impossible de se connecter pour passer des ordres. Réessaie.';

  @override
  String get liveOrderErrorGeneric =>
      'Impossible de terminer cette étape. Réessaie.';

  @override
  String get liveOrderConfirmTermsFirst =>
      'Confirme d’abord les conditions de l’émetteur.';

  @override
  String get liveOrderInvalidShares => 'Saisis un nombre d’actions valide.';

  @override
  String get liveOrderInvalidUsdc => 'Saisis un montant valide en USDC.';

  @override
  String liveOrderUpToPerOrder(String amount) {
    return 'Jusqu’à $amount par ordre.';
  }

  @override
  String liveOrderMinimum(String amount) {
    return 'Les ordres sur ce token commencent à $amount.';
  }

  @override
  String liveOrderMarketNotice(String status) {
    return '$status.';
  }

  @override
  String get liveOrderQuoteFailed =>
      'Impossible d’obtenir une cotation vérifiée. Réessaie.';

  @override
  String get liveOrderCheckingResult =>
      'Vérification du résultat. Ton ordre ne sera pas envoyé deux fois.';

  @override
  String get liveOrderSigningFailed =>
      'La signature n’a pas abouti. Aucun ordre n’a été envoyé.';

  @override
  String get liveOrderReconnecting => 'Reconnexion pour vérifier ton ordre…';

  @override
  String get liveOrderTermsOpenFailed =>
      'Impossible d’ouvrir les conditions de l’émetteur. Réessaie.';

  @override
  String get liveOrderTransactionOpenFailed =>
      'Impossible d’ouvrir la transaction. Réessaie.';

  @override
  String get liveOrderTitleFallback => 'Opération';

  @override
  String get liveOrderAccountChangedTitle => 'Ton compte a changé';

  @override
  String get liveOrderAccountChangedBody =>
      'Connecte-toi, puis rouvre cette opération.';

  @override
  String get liveOrderCheckLastOrderTitle => 'Vérifions ton dernier ordre';

  @override
  String get liveOrderConnectFailedTitle =>
      'Impossible de se connecter pour passer des ordres';

  @override
  String get liveOrderConnectedRetryBody =>
      'Réessaie une fois la connexion rétablie.';

  @override
  String get liveOrderPausedTitle =>
      'Les opérations sont en pause pour le moment';

  @override
  String get liveOrderPausedBody =>
      'Ton portefeuille et tes placements sont toujours là.';

  @override
  String get liveOrderNotTradableTitle =>
      'Ce token n’est pas encore négociable ici';

  @override
  String get liveOrderChooseAnother => 'Choisis une autre action.';

  @override
  String get liveOrderBackToStocks => 'Retour aux actions';

  @override
  String get liveOrderCheckingBalance => 'Vérification du solde…';

  @override
  String liveOrderAvailable(String amount) {
    return 'Disponible : $amount';
  }

  @override
  String liveOrderBuyTitle(String symbol) {
    return 'Acheter $symbol';
  }

  @override
  String liveOrderSellTitle(String symbol) {
    return 'Vendre $symbol';
  }

  @override
  String get liveOrderBuyInstead => 'Passer à l’achat';

  @override
  String get liveOrderSellInstead => 'Passer à la vente';

  @override
  String get liveOrderYouSell => 'Tu vends';

  @override
  String get liveOrderYouPay => 'Tu paies';

  @override
  String liveOrderLimit(String amount) {
    return 'Limite par ordre : $amount';
  }

  @override
  String liveOrderLimitCappedMax(String amount) {
    return 'Le maximum est ramené à $amount, la limite par ordre.';
  }

  @override
  String liveOrderLimitCappedPercent(String percent, String amount) {
    return '$percent ramené à $amount, la limite par ordre.';
  }

  @override
  String get liveOrderCheckingPrice => 'Vérification du prix et des frais…';

  @override
  String get liveOrderReviewBuy => 'Vérifier l’achat';

  @override
  String get liveOrderReviewSell => 'Vérifier la vente';

  @override
  String get liveOrderReviewBuyTitle => 'Vérifie ton achat';

  @override
  String get liveOrderReviewSellTitle => 'Vérifie ta vente';

  @override
  String get liveOrderYouReceive => 'Tu reçois ≈';

  @override
  String get liveOrderMinimumReceived => 'Minimum reçu';

  @override
  String get liveOrderNetworkFees => 'Frais de réseau et de compte';

  @override
  String get liveOrderSwapFee => 'Frais de swap';

  @override
  String get liveOrderPrice => 'Prix';

  @override
  String get liveOrderFixedQuote => 'Cotation fixe d’un teneur de marché';

  @override
  String get liveOrderIssuer => 'Émetteur';

  @override
  String get liveOrderIssuerFee => 'Frais de l’émetteur';

  @override
  String get liveOrderConfirmBuy => 'Confirmer l’achat';

  @override
  String get liveOrderConfirmSell => 'Confirmer la vente';

  @override
  String get liveOrderEditAmount => 'Modifier le montant';

  @override
  String get liveOrderTradeConfirmed => 'Opération confirmée';

  @override
  String get liveOrderConfirmingTrade => 'Confirmation de ton opération';

  @override
  String get liveOrderQuoteExpired => 'Cotation expirée';

  @override
  String get liveOrderTradeIncomplete => 'L’opération n’a pas abouti';

  @override
  String get liveOrderConfirmedBody => 'Ton ordre est confirmé sur Solana.';

  @override
  String get liveOrderPendingBody =>
      'Tu peux fermer cet écran. Rouvre l’opération pour voir son état.';

  @override
  String get liveOrderExpiredBody => 'Demande un nouveau prix pour continuer.';

  @override
  String get liveOrderFailedBody => 'Ton ordre n’a pas été exécuté.';

  @override
  String get liveOrderViewWalletActivity => 'Voir l’activité du portefeuille ↗';

  @override
  String get liveOrderViewTransaction => 'Voir la transaction ↗';

  @override
  String get liveOrderGetFreshPrice => 'Obtenir un nouveau prix';

  @override
  String liveOrderIssuerExcluded(String regions) {
    return 'Non proposé aux résidents de : $regions';
  }

  @override
  String liveOrderIssuerFeeNote(String percent) {
    return 'Frais de l’émetteur : $percent sur chaque achat et chaque vente';
  }

  @override
  String get liveOrderLegacyAttestation =>
      'Je suis éligible selon les conditions de l’émetteur.';

  @override
  String get liveOrderIssuerTerms => 'Conditions de l’émetteur ↗';

  @override
  String get liveHistoryStatusConfirming => 'Confirmation en cours';

  @override
  String get liveHistoryStatusConfirmed => 'Confirmée';

  @override
  String get liveHistoryStatusFailed => 'Non aboutie';

  @override
  String get liveHistoryStatusExpired => 'Expirée';

  @override
  String get liveHistoryErrorSignIn =>
      'Reconnecte-toi pour voir tes opérations.';

  @override
  String get liveHistoryErrorLoad =>
      'Impossible de charger tes opérations. Réessaie.';

  @override
  String get liveHistoryErrorLoadMore =>
      'Impossible de charger plus d’opérations. Réessaie.';

  @override
  String get liveHistoryErrorOpenStock =>
      'Impossible d’ouvrir cette action. Réessaie.';

  @override
  String get liveHistoryTitle => 'Tes opérations';

  @override
  String get liveHistoryEmptyTitle => 'Ta première opération commence ici';

  @override
  String get liveHistoryEmptyBody => 'Tes ordres apparaîtront ici.';

  @override
  String get liveHistoryMore => 'Plus d’opérations';

  @override
  String liveHistoryRowBuy(String symbol) {
    return 'Achat de $symbol';
  }

  @override
  String liveHistoryRowSell(String symbol) {
    return 'Vente de $symbol';
  }

  @override
  String get liveHistoryYouPaid => 'Tu as payé';

  @override
  String get liveHistoryYouSold => 'Tu as vendu';

  @override
  String get liveHistoryYouReceived => 'Tu as reçu';

  @override
  String get liveHistoryFinalAmounts =>
      'Montants finaux de la transaction confirmée.';

  @override
  String get liveHistoryQuotedOutput => 'Montant de la cotation';

  @override
  String get liveHistoryMinimumOutput => 'Montant minimum';

  @override
  String get liveHistoryEstimates =>
      'Estimations de l’ordre. Consulte la transaction pour les montants finaux.';

  @override
  String get liveHistoryViewTransaction => 'Voir la transaction';

  @override
  String get liveHistoryOpenStock => 'Ouvrir l’action';

  @override
  String get liveTradingOpenAlways => 'Ouvert 24 h/24, 7 j/7';

  @override
  String get liveTradingOpenWeekends => 'Ouvert maintenant, week-ends compris';

  @override
  String get liveTradingOpenNow => 'Ouvert maintenant';

  @override
  String get liveTradingPausedByIssuer => 'Suspendu par l’émetteur';

  @override
  String get liveTradingPausedByMarket => 'Suspendu par le marché';

  @override
  String liveTradingPausedResumes(String time) {
    return 'Suspendu · reprend $time';
  }

  @override
  String get liveTradingShortPause => 'Courte pause';

  @override
  String liveTradingShortPauseResumes(String time) {
    return 'Courte pause · reprend $time';
  }

  @override
  String get liveTradingClosed => 'Fermé';

  @override
  String liveTradingClosedOpens(String time) {
    return 'Fermé · ouvre $time';
  }

  @override
  String get liveTradingHoursAroundClock =>
      'Se négocie en continu, avec de courtes pauses entre les séances américaines.';

  @override
  String get liveTradingHoursWeekdays =>
      'Se négocie 24 h/24, du dimanche soir au vendredi soir (heure de l’Est américain).';

  @override
  String get liveTradingHoursRegular =>
      'Se négocie uniquement aux heures du marché américain, de 9 h 30 à 16 h (heure de l’Est), en semaine.';

  @override
  String get liveTradingHoursSessions =>
      'Se négocie uniquement pendant les séances du marché américain.';

  @override
  String liveTradingTimeToday(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeTomorrow(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'demain à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeWeekday(int hour, String weekday, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: '$weekday à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeDate(int hour, String date, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'le $date à $clock',
    );
    return '$_temp0';
  }

  @override
  String get liveTradingReasonIssuerNotOffered =>
      'Trimmy ne propose pas cet émetteur.';

  @override
  String get liveTradingReasonNotYet => 'Pas encore négociable dans Trimmy.';

  @override
  String get liveTradingReasonIdentity =>
      'Trimmy n’a pas pu confirmer qui a émis ce token.';

  @override
  String get liveTradingReasonRestricted =>
      'L’émetteur impose sur ce token des restrictions que Trimmy ne peut pas accepter.';

  @override
  String get liveTradingReasonLowLiquidity =>
      'Trop peu d’échanges pour l’acheter et le vendre en toute sécurité.';

  @override
  String get liveTradingReasonNoRoute =>
      'Aucune route d’ordre n’a passé les contrôles de sécurité de Trimmy.';

  @override
  String get liveTradingReasonPriceOff =>
      'Son prix est trop éloigné du vrai prix de l’action.';

  @override
  String get liveTradingReasonHeldBack =>
      'En pause pendant que Trimmy vérifie ce token.';

  @override
  String get liveTradingReasonNotChecked => 'Pas encore vérifié.';

  @override
  String liveTradingReasonClosedOpens(String time) {
    return 'Son marché est fermé. Il ouvre $time, puis Trimmy le vérifie.';
  }

  @override
  String get liveTradingReasonUsHours =>
      'Se négocie uniquement quand les marchés américains sont ouverts.';

  @override
  String get liveTradingReasonAwaitingReview =>
      'Son marché est ouvert. Trimmy le vérifie avant de te le proposer.';

  @override
  String get liveTradingReasonNoMarketMaker =>
      'Aucun teneur de marché ne le cote en ce moment.';

  @override
  String get liveTradingReasonUnavailable => 'Non négociable dans Trimmy.';

  @override
  String get liveTradingOtherIssuer => 'Autre émetteur';

  @override
  String get holdingsCheckingWallet => 'Vérification de ton portefeuille…';

  @override
  String get holdingsWalletStarts => 'Ton portefeuille commence ici';

  @override
  String get holdingsEmptyTitle => 'Pas encore d’actions';

  @override
  String get holdingsEmptyBody => 'Ta première action commence ici.';

  @override
  String get holdingsExplore => 'Explorer les actions';

  @override
  String get walletFastBuy => 'Achat rapide';

  @override
  String get walletSend => 'Envoyer';

  @override
  String get walletCashBalance => 'Liquidités';

  @override
  String get walletAccountBalance => 'Solde du compte';

  @override
  String get walletKnownValue => 'Valeur connue';

  @override
  String get walletSwitchToPaper => 'Passer en mode Entraînement';

  @override
  String get walletSwitchToReal => 'Passer en mode argent réel';

  @override
  String get walletUsdcAvailable => 'USDC disponibles';

  @override
  String walletPositions(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText positions',
      one: '$countText position',
    );
    return '$_temp0';
  }

  @override
  String get walletSomePricesUnavailable => 'Certains prix indisponibles';

  @override
  String get walletPositionPricesUnavailable =>
      'Prix des positions indisponibles';

  @override
  String get walletCheckingSol => 'Vérification des SOL…';

  @override
  String walletSolForFees(String amount) {
    return '$amount SOL pour les frais';
  }

  @override
  String get walletCashMarks => 'USDC et SOL';

  @override
  String get fundCreateWalletFailed =>
      'Impossible de créer ton portefeuille. Réessaie.';

  @override
  String get fundWalletUnconfirmed =>
      'Impossible de confirmer ton portefeuille.';

  @override
  String get fundWalletOffline =>
      'Tu es hors ligne. Reconnecte-toi pour charger ton portefeuille.';

  @override
  String get fundWalletLoadFailed => 'Impossible de charger ton portefeuille.';

  @override
  String get fundTabCash => 'Carte';

  @override
  String get fundTabCrypto => 'Crypto';

  @override
  String get fundWalletMissingTitle => 'Un portefeuille pour ton argent';

  @override
  String get fundCreatingWallet => 'Création…';

  @override
  String get fundCreateWallet => 'Créer le portefeuille';

  @override
  String fundDepositQrLabel(String address) {
    return 'Adresse de dépôt Solana $address';
  }

  @override
  String get fundSendOnlyWarning =>
      'N’envoie que des USDC ou des SOL à ce compte, sur le réseau Solana.';

  @override
  String get fundAddressCopied => 'Copié';

  @override
  String get fundCopyAddress => 'Copier l’adresse';

  @override
  String get guestDeskStartAgainFailedExpired =>
      'Impossible de recommencer. Ton bureau expiré est toujours conservé.';

  @override
  String get guestDeskStartAgainFailed =>
      'Impossible de recommencer. Ton ancien bureau est toujours conservé.';

  @override
  String get guestDeskStartFreshTitle => 'Repartir de zéro ?';

  @override
  String get guestDeskExpiredTitle => 'La session invité a expiré';

  @override
  String get guestDeskEndedTitle => 'La session invité est terminée';

  @override
  String get guestDeskStartFreshMessage =>
      'Ce téléphone perdra l’accès à ton ancien bureau. C’est irréversible.';

  @override
  String get guestDeskExpiredMessage =>
      'Tes données invité sont conservées. Ce bureau ne peut plus passer d’ordres ni être sauvegardé dans un compte.';

  @override
  String get guestDeskEndedMessage =>
      'Tes données invité sont conservées, mais ce téléphone ne peut plus ouvrir le bureau.';

  @override
  String get guestDeskStartFreshDetail =>
      'Ton solde, tes positions et ton historique ne passeront pas au nouveau bureau.';

  @override
  String get guestDeskSignInDetail =>
      'Connecte-toi pour ouvrir ton compte sauvegardé. Ton bureau invité reste intact.';

  @override
  String get guestDeskOpening => 'Ouverture…';

  @override
  String get guestDeskStartNewConfirm => 'Créer un nouveau bureau';

  @override
  String get guestDeskKeep => 'Garder ce bureau';

  @override
  String get guestDeskStartNewGuest => 'Créer un nouveau bureau invité';

  @override
  String get guestDeskPreservedTitle => 'Bon retour';

  @override
  String get guestDeskPreservedMessage =>
      'Tes opérations sauvegardées et ta progression sont prêtes.';

  @override
  String get guestDeskPreservedExpiredDetail =>
      'Ton bureau invité expiré est conservé à part. Il ne peut plus passer d’ordres ni être fusionné.';

  @override
  String get guestDeskPreservedDetail =>
      'Tes opérations invité restent à part. Déconnecte-toi pour retrouver ce bureau.';

  @override
  String get guestDeskGoToDesk => 'Aller à mon bureau';

  @override
  String get onrampErrorNotEnabled =>
      'Les dépôts par carte ne sont pas encore disponibles. Tu peux quand même transférer depuis un autre portefeuille.';

  @override
  String get onrampErrorSignIn => 'Reconnecte-toi pour continuer.';

  @override
  String get onrampErrorExpired =>
      'Ce paiement doit être vérifié avec le support. Le solde de ton portefeuille se mettra quand même à jour.';

  @override
  String get onrampErrorBusy => 'Patiente un instant, puis réessaie.';

  @override
  String onrampErrorAmount(String min, String max) {
    return 'Saisis un montant entre $min et $max.';
  }

  @override
  String get onrampErrorWalletChanged =>
      'Actualise ton portefeuille avant de continuer.';

  @override
  String get onrampErrorUnavailable =>
      'Impossible d’ouvrir le paiement. Réessaie dans un instant.';

  @override
  String get onrampErrorStep => 'Cette étape n’a pas abouti. Réessaie.';

  @override
  String get onrampErrorEmail => 'Saisis un e-mail pour ton reçu.';

  @override
  String get onrampErrorRefresh =>
      'Impossible d’actualiser ce dépôt. Vérifie à nouveau avant de payer une deuxième fois.';

  @override
  String get onrampTestDoneTitle => 'Dépôt test terminé';

  @override
  String get onrampDoneTitle => 'Argent ajouté';

  @override
  String get onrampFailedTitle => 'Dépôt à vérifier';

  @override
  String get onrampPendingTitle => 'Termine ton dépôt';

  @override
  String get onrampTestDoneBody =>
      'Les USDC de test sont arrivés sur Solana devnet.';

  @override
  String get onrampDoneBody => 'Tes USDC sont dans ton portefeuille.';

  @override
  String get onrampFailedBody =>
      'Contacte Crossmint avec ce numéro de commande. Ne paie pas une deuxième fois.';

  @override
  String get onrampPendingBody =>
      'Termine le paiement dans ton navigateur, puis reviens ici.';

  @override
  String get onrampOpenPayment => 'Ouvrir le paiement';

  @override
  String onrampOrderId(String orderId) {
    return 'Commande $orderId';
  }

  @override
  String get onrampCheckingOptions => 'Vérification des moyens de paiement…';

  @override
  String get onrampCardUnavailable =>
      'Les dépôts par carte ne sont pas encore disponibles.';

  @override
  String get onrampTransferFromWallet => 'Transférer depuis un portefeuille';

  @override
  String get onrampTestCheckout => 'Paiement test';

  @override
  String get onrampMethods => 'Carte, Apple Pay ou Google Pay';

  @override
  String get onrampMethodsNote =>
      'Les options disponibles s’affichent au paiement.';

  @override
  String get onrampAmountLabel => 'Montant';

  @override
  String get onrampReceiptEmail => 'E-mail pour le reçu';

  @override
  String get onrampUsdcNote =>
      'USDC sur Solana. Les frais s’affichent au paiement.';

  @override
  String get onrampConfirmWallet =>
      'Confirme que ce portefeuille est à toi. Tu signes un message, pas un paiement.';

  @override
  String get onrampVerificationMessage => 'Message de vérification';

  @override
  String get onrampOneMoment => 'Un instant…';

  @override
  String get onrampVerifyContinue => 'Vérifier et continuer';

  @override
  String get onrampPoweredByCrossmint => 'Fourni par Crossmint';

  @override
  String get signInTitleDeskAwaits => 'Ton bureau t’attend.';

  @override
  String get signInTitleTrimmy => 'Connecte-toi à Trimmy.';

  @override
  String get signInCaption => 'Connecte-toi ou crée ton compte.';

  @override
  String get signInCaptionExpired =>
      'Ouvre le bureau de ton compte. Le bureau invité expiré reste à part.';

  @override
  String get signInNoticeExpired =>
      'Si tu quittes la connexion, le bureau invité expiré reste conservé.';

  @override
  String get signInErrorConnection =>
      'Impossible de connecter ton compte. Ton bureau est toujours là.';

  @override
  String get signInErrorConnectionExpired =>
      'Impossible de connecter ton compte. Ton ancien bureau est conservé.';

  @override
  String get signInErrorUnfinished => 'Ça n’a pas abouti. Réessaie.';

  @override
  String get signInClosed =>
      'La connexion a été fermée. Ton bureau est toujours là.';

  @override
  String get signInClosedExpired =>
      'La connexion a été fermée. Ton ancien bureau est conservé.';

  @override
  String get signInErrorCode => 'Ce code n’a pas marché. Réessaie.';

  @override
  String get signInUnavailable =>
      'La connexion n’est pas disponible pour le moment.';

  @override
  String get signInErrorEmailInvalid => 'Saisis une adresse e-mail complète.';

  @override
  String get signInErrorSendCode => 'Impossible d’envoyer le code. Réessaie.';

  @override
  String get signInErrorCodeMissing => 'Saisis le code reçu par e-mail.';

  @override
  String get signInCloseTooltip => 'Fermer la connexion';

  @override
  String get signInUseDifferentEmail => 'Utiliser un autre e-mail';

  @override
  String get signInTitleSaveDesk => 'Sauvegarde ton bureau.';

  @override
  String get signInTitleCheckEmail => 'Consulte tes e-mails.';

  @override
  String get signInTitleYourEmail => 'Ton e-mail.';

  @override
  String get signInExpiredDeskSeparate =>
      'Le bureau invité expiré reste à part.';

  @override
  String get signInDeskStaysOnPhone => 'Ton bureau reste sur ce téléphone.';

  @override
  String signInCodeSentTo(String email) {
    return 'Nous avons envoyé un code à $email.';
  }

  @override
  String get signInWeWillSendCode => 'Nous t’enverrons un code de connexion.';

  @override
  String get signInNotSetUp =>
      'La connexion à un compte n’est pas configurée dans cette version. Ton bureau reste sur ce téléphone.';

  @override
  String get signInNotSetUpExpired =>
      'La connexion à un compte n’est pas configurée dans cette version. Le bureau invité expiré reste conservé.';

  @override
  String get signInContinueAsGuest => 'Continuer en mode invité';

  @override
  String get signInLater => 'Plus tard';

  @override
  String get signInCodeLabel => 'Code';

  @override
  String get signInEmailLabel => 'Adresse e-mail';

  @override
  String get signInSendCode => 'Envoyer le code';

  @override
  String get signInWelcomeBackTitle => 'Bon retour.';

  @override
  String get signInWelcomeBackCaption => 'Ton prochain coup t’attend.';

  @override
  String get signInOr => 'OU';

  @override
  String get signInContinueWithEmail => 'Continuer par e-mail';

  @override
  String get signInBusyValue => 'En cours';

  @override
  String signInContinueWithProvider(String provider) {
    return 'Continuer avec $provider';
  }

  @override
  String get careerWorldNextNeighbourhood => 'Le prochain quartier';

  @override
  String get careerWorldMoreOnTheWay => 'D’autres missions arrivent.';

  @override
  String careerWorldLockedHint(int day) {
    return 'Termine le jour $day pour ouvrir cette journée.';
  }

  @override
  String get careerWorldLoading => 'Ouverture de ta semaine…';

  @override
  String get careerWorldLoadFailed => 'Impossible de charger tes missions.';

  @override
  String get careerWorldBeyondFirstMonth => 'Au-delà du premier mois';

  @override
  String get careerWorldCityGrowing => 'La ville continue de grandir';

  @override
  String get careerWorldStartHere => 'COMMENCE ICI';

  @override
  String get careerWorldContinue => 'CONTINUER';

  @override
  String get careerWorldComingLater => 'Bientôt';

  @override
  String get careerWorldFiled => 'Envoyé';

  @override
  String careerWorldDayFiled(int day) {
    return 'Jour $day, envoyé';
  }

  @override
  String careerWorldDayCurrent(int day) {
    return 'Jour $day, mission en cours';
  }

  @override
  String careerWorldDayLocked(int day) {
    return 'Jour $day, verrouillé';
  }

  @override
  String careerWorldDayComingLater(int day) {
    return 'Jour $day, bientôt';
  }

  @override
  String get workdayEntryReload => 'Recharger ta mission';

  @override
  String workdayEntryEyebrow(int day, String speaker) {
    return 'JOUR $day · $speaker';
  }

  @override
  String get workdayEntryNext => 'Ta prochaine mission';

  @override
  String get workdayEntryContinue => 'Continue ta mission';

  @override
  String get deskActivityTitle => 'Ton activité';

  @override
  String get deskActivityEmpty => 'Ta première opération lance l’histoire.';

  @override
  String deskActivityBought(String symbol) {
    return 'Tu as acheté $symbol';
  }

  @override
  String deskActivitySold(String symbol) {
    return 'Tu as vendu $symbol';
  }

  @override
  String get deskCommunityTitle => 'Communauté';

  @override
  String get deskCommunityPrompt => 'Découvre ce que disent les traders';

  @override
  String get deskCommunityLoadFailed => 'Impossible de charger la communauté';

  @override
  String get deskCommunityOpening => 'Ouverture de la communauté…';

  @override
  String get deskCommunityStart => 'Lance une conversation';

  @override
  String get deskCommunitySubtitle => 'Commentaires publics d’autres traders.';

  @override
  String deskCommunityPostByHandle(String handle, String cashtag) {
    return '@$handle sur $cashtag';
  }

  @override
  String deskCommunityPostByTrader(String cashtag) {
    return 'Un trader sur $cashtag';
  }

  @override
  String get deskTitle => 'Ton bureau';

  @override
  String get deskUpdatesTooltip => 'Nouveautés';

  @override
  String get deskOpenProfile => 'Ouvrir le profil';

  @override
  String deskPersonaPicture(String name) {
    return 'Photo de profil de $name';
  }

  @override
  String deskStreakLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'jours de série',
      one: 'jour de série',
    );
    return '$_temp0';
  }

  @override
  String get deskHoldingsTitle => 'Tes placements';

  @override
  String get deskExplore => 'Explorer';

  @override
  String deskShareCount(num count, String quantity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$quantity actions',
      one: '$quantity action',
    );
    return '$_temp0';
  }

  @override
  String get deskPickTraderTitle => 'Choisis ton trader';

  @override
  String get deskPickTraderSubtitle => 'Personnalise ton bureau.';

  @override
  String get deskSaveTitle => 'Sauvegarde ton bureau';

  @override
  String get deskSaveSubtitle => 'Retrouve-le sur tes autres appareils.';

  @override
  String get deskCareerFallback => 'Ta carrière';

  @override
  String get deskNextStepFallback => 'Découvre ta prochaine étape';

  @override
  String get deskEmptyTitle => 'Pas encore d’actions';

  @override
  String get deskEmptyBody => 'Choisis une entreprise pour commencer.';

  @override
  String get deskEmptyExplore => 'Explorer les actions';

  @override
  String get deskHoldingValueUnavailable => 'Valeur indisponible';

  @override
  String clockWallStreetClosesIn(String duration) {
    return 'Ici, les actions s’échangent 24 h/24, 7 j/7. Wall Street ferme dans $duration.';
  }

  @override
  String clockWallStreetOpensIn(String duration) {
    return 'Ici, les actions s’échangent 24 h/24, 7 j/7. Wall Street ouvre dans $duration.';
  }

  @override
  String clockDurationMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min',
    );
    return '$_temp0';
  }

  @override
  String clockDurationHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours h',
    );
    return '$_temp0';
  }

  @override
  String clockDurationHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours h $minutes min',
    );
    return '$_temp0';
  }

  @override
  String clockDurationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days j',
    );
    return '$_temp0';
  }

  @override
  String clockDurationDaysHours(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days j $hours h',
    );
    return '$_temp0';
  }

  @override
  String get workdayDraftSaved => 'Enregistré';

  @override
  String get workdayDraftNotSaved => 'Pas encore enregistré';

  @override
  String get workdayLeaveTitle => 'Quitter cette note ?';

  @override
  String get workdayLeaveBody =>
      'Tes dernières modifications ne sont pas encore enregistrées.';

  @override
  String get workdayLeaveKeepWriting => 'Continuer à écrire';

  @override
  String get workdayLeaveWithoutSaving => 'Quitter sans enregistrer';

  @override
  String get workdaySaveRetry =>
      'Enregistrement impossible pour l’instant. Réessaie.';

  @override
  String workdayDayTitle(int day) {
    return 'Jour $day';
  }

  @override
  String get workdaySaveAndClose => 'Enregistrer et fermer';

  @override
  String get workdayFiledTitle => 'Envoyé.';

  @override
  String workdayTrimsEarned(int trims) {
    return '+$trims Trims';
  }

  @override
  String workdayNextDay(int day, String title) {
    return 'Jour $day : $title';
  }

  @override
  String get workdayHintShow => 'Un indice ?';

  @override
  String get workdayHintHide => 'Masquer l’indice';

  @override
  String get workdayFileHeading => 'Envoie une mise à jour à l’équipe';

  @override
  String get workdayFileBody => 'Garde les deux faits que la source confirme.';

  @override
  String get workdayNoteHint => 'Ajoute une note (facultatif)';

  @override
  String get workdayButtonBack => 'Retour dans la rue';

  @override
  String get workdayButtonCheckEvidence => 'Vérifier les preuves';

  @override
  String get workdayButtonSendDecision => 'Envoyer ta décision';

  @override
  String get workdayButtonFile => 'Envoyer la mise à jour';

  @override
  String get workdayPinDetail => 'Épingler le détail';

  @override
  String get workdayUnpinDetail => 'Désépingler le détail';

  @override
  String get workdayOpensSoon => 'Ouvre bientôt';

  @override
  String get workdayOpensTomorrow => 'Ouvre demain';

  @override
  String workdayOpensOnWeekday(String weekday) {
    return 'Ouvre $weekday';
  }

  @override
  String workdayOpensOnDate(String date) {
    return 'Ouvre le $date';
  }

  @override
  String get workdayErrorCheckEvidence =>
      'Revérifie la source. Ces détails ne confirment pas cette mise à jour.';

  @override
  String get workdayErrorCheckDecision => 'Regarde les chiffres de plus près.';

  @override
  String get workdayErrorTomorrow =>
      'La mission du jour est terminée. Ta prochaine journée commence bientôt.';

  @override
  String get workdayErrorClosed =>
      'Le bureau est fermé aujourd’hui. Reviens à la prochaine journée.';

  @override
  String get workdayErrorChanged =>
      'Ton travail a changé sur un autre écran. On l’a actualisé.';

  @override
  String get workdayErrorLocked => 'Termine d’abord la mission précédente.';

  @override
  String get workdayErrorSession => 'Ton compte a changé. Rouvre ton bureau.';

  @override
  String get workdayErrorSaveFailed =>
      'Enregistrement impossible pour l’instant. Ton travail est toujours là. Réessaie.';

  @override
  String get careerMissionFirstPaperBuyTitle => 'Achète ta première action';

  @override
  String get careerMissionWriteAReasonTitle => 'Écris ta raison';

  @override
  String get careerMissionHoldThroughRedDayTitle =>
      'Tiens bon un jour dans le rouge';

  @override
  String get careerErrorOffline =>
      'Ta carrière est hors ligne. Vérifie ta connexion et réessaie.';

  @override
  String get careerErrorTimeout =>
      'Ta carrière a mis trop de temps à s’ouvrir. Réessaie.';

  @override
  String get careerErrorSession =>
      'Ta carrière a besoin d’une nouvelle session. Réessaie.';

  @override
  String get careerErrorRateLimited =>
      'Ta carrière s’actualise trop vite. Réessaie dans un instant.';

  @override
  String get careerErrorProfileRequired =>
      'Termine de configurer ton profil Trimmy, puis réessaie.';

  @override
  String get careerErrorUnavailable =>
      'Ta carrière est indisponible. Réessaie.';

  @override
  String careerStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Série de $countText jours',
      one: 'Série de $countText jour',
    );
    return '$_temp0';
  }

  @override
  String get careerStreakRetryActivity => 'Recharger l’activité';

  @override
  String careerStreakDaySemantics(String date, String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'active': 'actif',
      'upcoming': 'à venir',
      'none': 'sans activité',
      'unavailable': 'activité indisponible',
      'other': 'activité indisponible',
    });
    return '$date, $_temp0';
  }

  @override
  String get careerYourProgress => 'Ta progression';

  @override
  String get careerPointsLabel => 'Points de carrière';

  @override
  String careerTrimsCount(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText Trims',
      one: '$countText Trim',
    );
    return '$_temp0';
  }

  @override
  String careerTrimsAwarded(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$countText Trims',
      one: '+$countText Trim',
    );
    return '$_temp0';
  }

  @override
  String get communityTitle => 'Communauté';

  @override
  String get communityUpdatesTitle => 'Nouveautés';

  @override
  String get communityScopeEveryone => 'Tout le monde';

  @override
  String get communityScopeFollowing => 'Abonnements';

  @override
  String get communityLoadFailed =>
      'Impossible de charger l’activité. Réessaie.';

  @override
  String get communitySaveFailed =>
      'Ce changement n’a pas été enregistré. Réessaie.';

  @override
  String get communityEmptyUpdatesTitle => 'Tu es à jour';

  @override
  String get communityEmptyUpdatesBody =>
      'Les nouveaux commentaires des personnes que tu suis apparaissent ici.';

  @override
  String get communityEmptyFollowingTitle => 'Les gens que tu suis, ici';

  @override
  String get communityEmptyFollowingBody =>
      'Suis un trader depuis l’onglet Tout le monde.';

  @override
  String get communityEmptyEveryoneTitle =>
      'Aucun commentaire partagé pour l’instant';

  @override
  String get communityEmptyEveryoneBody =>
      'Les commentaires publics apparaîtront ici.';

  @override
  String get communityAnonymousTrader => 'Trader';

  @override
  String get communityFollowingButton => 'Suivi';

  @override
  String get communityFollowButton => '+ Suivre';

  @override
  String get communityCommentOptions => 'Options du commentaire';

  @override
  String get communityMuteUpdates => 'Couper les nouveautés';

  @override
  String get communityTurnOnUpdates => 'Activer les nouveautés';

  @override
  String get communityReport => 'Signaler';

  @override
  String get communityBlockTrader => 'Bloquer ce trader';

  @override
  String communityPostTime(String date, String time) {
    return '$date · $time';
  }

  @override
  String get communityLoadMore => 'Charger plus';

  @override
  String get floorTitle => 'Carrière';

  @override
  String get floorCloseProgress => 'Fermer la progression';

  @override
  String get floorProgressButton => 'Progression';

  @override
  String get floorCareerLoadFailed => 'Impossible de charger ta carrière';

  @override
  String get floorBrowseStocks => 'Voir les actions';

  @override
  String get floorTrimsTooltip =>
      'Les Trims sont des points de carrière. Gagne-les grâce aux activités pour monter en grade.';

  @override
  String get floorMilestonesTitle => 'Objectifs de carrière';

  @override
  String get floorMilestonesActivities => 'Tes activités';

  @override
  String floorMilestonesComplete(String complete, String total) {
    return '$complete sur $total atteints';
  }

  @override
  String get floorMilestonesUpdating => 'Mise à jour de ta progression…';

  @override
  String get floorActivitiesLoadFailed => 'Impossible de charger les activités';

  @override
  String get floorMissionCommentTitle => 'Commente ton opération';

  @override
  String get floorMissionStatusComplete => 'Atteint';

  @override
  String get floorMissionStatusReady => 'Disponible';

  @override
  String get floorMissionStatusLocked => 'Verrouillé';

  @override
  String get floorMissionHoldHint =>
      'Garde une action pendant un jour de baisse.';

  @override
  String get floorMissionWriteComment => 'Écris un commentaire';

  @override
  String get floorMissionFindStock => 'Trouve une action';

  @override
  String floorMissionBecomeRank(String rank) {
    return 'Devenir $rank';
  }

  @override
  String floorPromotionUnlocked(String rank) {
    return 'Grade débloqué : $rank';
  }

  @override
  String get floorRankHighestReached => 'Grade le plus élevé atteint';

  @override
  String floorRankPromotionReady(String rank) {
    return 'Promotion prête : $rank';
  }

  @override
  String get floorRankThresholdReached =>
      'Tu as assez de Trims. Termine l’objectif de promotion';

  @override
  String floorRankTrimsToNext(int count, String countText, String rank) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Encore $countText Trims pour devenir $rank',
      one: 'Encore $countText Trim pour devenir $rank',
    );
    return '$_temp0';
  }

  @override
  String floorRankProgressSemantics(String percent, String status) {
    return 'Progression de grade : $percent pour cent. $status';
  }

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileYourProfile => 'Ton profil';

  @override
  String get profileGuestTitle => 'Fais-le à ton image';

  @override
  String get profileGuestBody =>
      'Connecte-toi pour garder tes opérations et ta carrière au même endroit.';

  @override
  String get profileProgressRefreshFailed =>
      'Impossible d’actualiser la progression.';

  @override
  String get profileLoadProgress => 'Charger la progression';

  @override
  String get profileChooseTrader => 'Choisis ton trader';

  @override
  String get profileYourTrader => 'Ton trader';

  @override
  String get profileChangeTrader => 'Changer de trader';

  @override
  String profileStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText jours',
      one: '$countText jour',
    );
    return '$_temp0';
  }

  @override
  String get profileStreakLabel => 'Série';

  @override
  String get socialReportCategorySpam => 'Spam';

  @override
  String get socialReportCategoryHarassment => 'Harcèlement';

  @override
  String get socialReportCategoryImpersonation => 'Usurpation d’identité';

  @override
  String get socialReportCategoryUnsafe => 'Contenu dangereux';

  @override
  String get socialReportCategoryOther => 'Autre chose';

  @override
  String get infoHelpTitle => 'Aide';

  @override
  String get infoTermsTitle => 'Conditions';

  @override
  String get infoPrivacyTitle => 'Confidentialité';

  @override
  String get infoContactTitle => 'Parle-nous';

  @override
  String get infoContactBody =>
      'Retrouve @trimmyhq sur X pour demander de l’aide ou donner ton avis.';

  @override
  String get infoLinkCopied => 'Lien copié';

  @override
  String get infoCopyContactLink => 'Copier le lien de contact';

  @override
  String get infoCopyWebsiteLink => 'Copier le lien du site';

  @override
  String infoLastUpdated(String date) {
    return 'Dernière mise à jour : $date';
  }

  @override
  String infoProviderPolicyLink(String provider, String url) {
    return '$provider : $url';
  }

  @override
  String get infoPracticeAndCareerTitle => 'Entraînement et Carrière';

  @override
  String get infoPrivacyHeading => 'La confidentialité, en termes simples.';

  @override
  String get infoPrivacyIntro =>
      'Cet avis décrit les informations traitées par l’app Trimmy et par les services qui la font fonctionner.';

  @override
  String get infoPrivacyAccountTitle => 'Ton compte ou ta session invité';

  @override
  String get infoPrivacyAccountBody =>
      'La connexion passe par Privy et par le fournisseur d’e-mail ou de réseau social que tu choisis. Trimmy reçoit des identifiants de compte, des informations d’authentification de session et les données disponibles des comptes liés, comme ton e-mail, ton pseudo ou ta photo de profil, pour t’authentifier et récupérer ta progression. Continuer en tant qu’invité crée une session distincte ; l’activité en mode invité peut aussi être enregistrée sur notre serveur. Te connecter peut associer cette progression à ton compte.';

  @override
  String get infoPrivacyPracticeBody =>
      'Tes ordres d’entraînement, tes soldes, tes réponses aux activités, tes journées terminées, tes séries, tes Trims, ta liste de suivi et ton profil de trader servent au jeu et à ta progression. Les préférences et les brouillons d’activités non terminées peuvent être enregistrés sur ton appareil ; les données de ton compte et de ta progression sont aussi conservées sur notre serveur.';

  @override
  String get infoPrivacyCommentsTitle => 'Commentaires et abonnements';

  @override
  String get infoPrivacyCommentsBody =>
      'Ton choix de partage des commentaires détermine quels autres utilisateurs peuvent voir tes commentaires avec ton pseudo, ton personnage de trader et l’actif concerné. Le fil de la communauté ne publie pas les montants de tes ordres ni le solde de ton portefeuille. Nous conservons tes abonnements, tes préférences de partage, les blocages et les signalements pour fournir ces fonctions et traiter les abus. L’activité publique sur la blockchain reste visible indépendamment de ces réglages.';

  @override
  String get infoPrivacyWalletsTitle => 'Portefeuilles et opérations réelles';

  @override
  String get infoPrivacyWalletsBody =>
      'Privy fournit le portefeuille intégré et l’interface de signature. Trimmy utilise ton adresse Solana publique pour lire les soldes, demander des cotations et préparer les transactions que tu vérifies. Notre serveur reçoit les transactions signées pour les soumettre et conserve les conditions de l’ordre, les références de transaction et leur statut. Les adresses de portefeuille, les montants de tokens et les signatures de transaction sont publics sur la blockchain. Fermer Trimmy ne peut pas effacer ces données.';

  @override
  String get infoPrivacyFundingTitle => 'Ajout d’argent';

  @override
  String get infoPrivacyFundingBody =>
      'Quand tu utilises le paiement Crossmint, Trimmy transmet l’e-mail, le portefeuille de destination, le montant demandé et la preuve de propriété du portefeuille nécessaires pour préparer l’ordre. Crossmint traite les informations de paiement et de vérification d’identité dans son propre parcours de paiement. Trimmy reçoit le statut de l’ordre et de la livraison ; notre serveur d’ajout d’argent ne collecte ni numéros de carte ni documents de vérification.';

  @override
  String get infoPrivacyRemindersBody =>
      'Les rappels de Carrière sont programmés sur ton appareil avec ton autorisation. Tu peux changer ta préférence de rappels dans Trimmy ou désactiver les notifications dans les réglages de l’appareil. Le suivi des opérations est facultatif sur les appareils compatibles. Si tu l’actives, nous enregistrons un jeton de notification de l’appareil et utilisons Firebase Cloud Messaging pour envoyer une courte mise à jour quand un ordre réel se termine. Les montants et les soldes n’y figurent pas. Tu peux désactiver le suivi des opérations dans Réglages. Les alertes sociales et de prix ne sont pas encore disponibles.';

  @override
  String get infoPrivacyServicesTitle => 'Services et données techniques';

  @override
  String get infoPrivacyServicesBody =>
      'Des hébergeurs et des fournisseurs de bases de données font fonctionner l’app. Les services de données de marché reçoivent des requêtes sur les actifs ; Jupiter et les fournisseurs blockchain reçoivent les requêtes de portefeuille ou de transaction nécessaires au trading réel. Privy, ton fournisseur de connexion et Crossmint gèrent les informations selon leurs propres politiques et peuvent les traiter dans d’autres pays. Les informations réseau, les heures des requêtes, les identifiants et les erreurs nous aident à fournir le service, à limiter les abus et à analyser les pannes.';

  @override
  String get infoPrivacyChoicesTitle => 'Tes choix et tes données';

  @override
  String get infoPrivacyChoicesBody =>
      'Tu peux modifier tes préférences de partage et de rappels dans Réglages. Te déconnecter ne supprime pas les données du serveur. Fermer un compte désactive l’accès, mais n’efface pas son historique, ne supprime pas ton compte chez le fournisseur, ne déplace pas d’actifs et ne retire pas de données de la blockchain. Effacer les données de l’app peut supprimer ta progression locale et tes informations d’accès ; avant de le faire, assure-toi de pouvoir récupérer un portefeuille approvisionné.';

  @override
  String get infoPrivacyRequestsBody =>
      'Contacte @trimmyhq sur X pour toute question sur l’accès, la rectification ou la suppression des informations détenues par Trimmy. Demande une conversation privée et ne publie pas d’identifiants ni de documents personnels en public. Nous pourrons avoir besoin de vérifier la demande. Les données des fournisseurs suivent leurs propres politiques ; Trimmy ne peut pas supprimer les données de la blockchain.';

  @override
  String get infoPrivacyProvidersTitle =>
      'Politiques de confidentialité des fournisseurs';

  @override
  String get infoTermsHeading => 'Utiliser Trimmy.';

  @override
  String get infoTermsIntro =>
      'Trimmy associe une simulation de trading à un mode en argent réel distinct. Ces conditions décrivent l’app telle qu’elle fonctionne aujourd’hui. Les fonctionnalités sont encore en développement.';

  @override
  String get infoTermsPracticeBody =>
      'Les soldes et les ordres d’entraînement sont simulés. Les Trims, les séries et les rangs de Carrière enregistrent ta progression dans le jeu ; ils ne peuvent pas être retirés en argent. L’entraînement peut utiliser des données d’exemple ou des données de référence du marché. Terminer une activité ne prouve pas que l’investissement est adapté à ta situation, et les commentaires des autres utilisateurs n’engagent qu’eux. Le contenu éducatif ne constitue pas un conseil personnalisé en investissement, juridique ou fiscal.';

  @override
  String get infoTermsRealMoneyTitle => 'Argent réel';

  @override
  String get infoTermsRealMoneyBody =>
      'Le mode Réel utilise un portefeuille sur le réseau principal (mainnet) de Solana et les actions tokenisées prises en charge. Un ordre peut déplacer des actifs réels quand tu le vérifies et le confirmes. Vérifie l’actif, le montant, les frais et la destination avant d’approuver. Une cotation est une estimation qui peut expirer ; un ordre envoyé ou en attente n’est pas une opération confirmée. Pour l’instant, l’historique affiche les montants des cotations vérifiées, et non un relevé complet des exécutions finales, des frais ou des transferts externes.';

  @override
  String get infoTermsTokenizedBody =>
      'Les actions tokenisées sont soumises aux conditions de leur émetteur et ne donnent pas forcément les mêmes droits que la détention directe d’actions de l’entreprise. Les prix peuvent baisser, la liquidité peut disparaître, et des défaillances de l’émetteur, du réseau ou des fournisseurs peuvent entraîner des pertes. Trimmy ne promet ni rendement ni exécution à un prix affiché.';

  @override
  String get infoTermsFundingTitle => 'Ajouter de l’argent à ton portefeuille';

  @override
  String get infoTermsFundingBody =>
      'Envoie uniquement des USDC ou des SOL pris en charge à l’adresse affichée, sur le réseau Solana. Vérifie l’adresse et le réseau avant d’envoyer ; Trimmy ne peut pas simplement annuler un transfert terminé sur la blockchain. Il te faut aussi des SOL pour les frais de réseau. Pour l’instant, le paiement par carte Crossmint est un environnement de test : ses fonds de test ne financent pas d’opérations sur le mainnet. Sa disponibilité hors test, ses moyens de paiement, la vérification et les frais dépendent du fournisseur.';

  @override
  String get infoTermsAccessTitle => 'Accès au compte';

  @override
  String get infoTermsAccessBody =>
      'Protège ta méthode de connexion et lis attentivement les demandes du portefeuille. Ne partage jamais une clé privée, une phrase de récupération ou un code de connexion à usage unique avec l’assistance. Cette version ne permet pas encore les retraits ni l’export du portefeuille dans l’app. Fermer ton compte ne retire pas tes actifs. Règle l’accès à ton portefeuille avant de fermer un compte ou de supprimer l’app d’un appareil approvisionné.';

  @override
  String get infoTermsEligibilityTitle => 'Éligibilité et autres services';

  @override
  String get infoTermsEligibilityBody =>
      'Tu dois respecter les exigences applicables des émetteurs d’actifs et des prestataires de services, y compris les restrictions de lieu et d’éligibilité. Voir un actif ou obtenir une cotation ne signifie pas que tu es éligible. Privy, Crossmint, les prestataires de trading et les émetteurs d’actifs ont leurs propres conditions. Trimmy ne promet pas d’être disponible dans tous les pays.';

  @override
  String get infoTermsCommunityTitle => 'Participer à la communauté';

  @override
  String get infoTermsCommunityBody =>
      'Partage des commentaires que tu as le droit de publier. N’usurpe pas l’identité d’autrui, ne divulgue pas d’informations privées, ne manipule pas le marché, ne harcèle pas les utilisateurs et n’interfère pas avec les comptes et les services. Des réglages de partage et des outils de blocage et de signalement sont disponibles pour les commentaires et les échanges de la communauté.';

  @override
  String get infoTermsAvailabilityTitle => 'Disponibilité et questions';

  @override
  String get infoTermsAvailabilityBody =>
      'Les données de marché, les cotations, les notifications et la confirmation du réseau peuvent être retardées ou indisponibles. Les fonctionnalités et ces avis peuvent changer au fil du développement. Rien ici ne supprime les droits qui ne peuvent pas être exclus en vertu de la loi applicable. Contacte @trimmyhq sur X pour obtenir de l’aide ou poser des questions sur ces conditions.';

  @override
  String get settingsReminders => 'Rappels';

  @override
  String get settingsAccountSection => 'Compte';

  @override
  String get settingsSignInDetail => 'Connecte-toi pour garder ta progression.';

  @override
  String get settingsHandle => 'Pseudo';

  @override
  String get settingsYourTrader => 'Ton trader';

  @override
  String get settingsChooseCharacter => 'Choisis un personnage';

  @override
  String get settingsEmail => 'E-mail';

  @override
  String get settingsSignInMethods => 'Méthodes de connexion';

  @override
  String get settingsSignInMethodsUnavailable =>
      'Méthode de connexion indisponible.';

  @override
  String get settingsSignInMethodEmail => 'E-mail';

  @override
  String get settingsSignOut => 'Se déconnecter';

  @override
  String get settingsNotificationsSection => 'Notifications';

  @override
  String get settingsNotificationGroupMarket => 'Marché';

  @override
  String get settingsNotificationGroupCareer => 'Carrière';

  @override
  String get settingsNotificationGroupSocial => 'Social';

  @override
  String get settingsNotificationGroupAccount => 'Compte';

  @override
  String get settingsNotificationOpen => 'Ouverture de Wall Street';

  @override
  String get settingsNotificationOpenDetail => 'Quand Wall Street ouvre.';

  @override
  String get settingsNotificationClose => 'Fermeture de Wall Street';

  @override
  String get settingsNotificationCloseDetail => 'Quand Wall Street ferme.';

  @override
  String get settingsNotificationEvents => 'Événements sur mes actions';

  @override
  String get settingsNotificationEventsDetail =>
      'Des nouvelles qui concernent les actions que tu détiens.';

  @override
  String get settingsNotificationPrices => 'Alertes de prix';

  @override
  String settingsNotificationPricesDetail(String small, String large) {
    return 'Variations de $small ou $large sur les actions que tu suis.';
  }

  @override
  String get settingsNotificationStreak => 'Rappel de série';

  @override
  String get settingsNotificationStreakDetail =>
      'Quand ta série est en danger.';

  @override
  String get settingsNotificationMissions => 'Objectifs';

  @override
  String get settingsNotificationMissionsDetail =>
      'Nouveaux objectifs et ta progression.';

  @override
  String get settingsNotificationPromotions => 'Promotions';

  @override
  String get settingsNotificationPromotionsDetail =>
      'Quand tu atteins un nouveau rang.';

  @override
  String get settingsNotificationLeague => 'Ligue';

  @override
  String get settingsNotificationLeagueDetail =>
      'Résultats de la ligue et changements de classement.';

  @override
  String get settingsNotificationFriends => 'Amis';

  @override
  String get settingsNotificationFriendsDetail =>
      'Les opérations de tes amis et leurs raisons.';

  @override
  String get settingsNotificationTrades => 'Suivi des opérations';

  @override
  String get settingsNotificationTradesDetail =>
      'Quand un ordre en argent réel se termine.';

  @override
  String get settingsNotificationNews => 'Nouveautés de Trimmy';

  @override
  String get settingsNotificationNewsDetail =>
      'Actualités et nouveautés de l’app.';

  @override
  String get settingsNotAvailableYet => 'Pas encore disponible.';

  @override
  String get settingsQuietHours => 'Heures de silence';

  @override
  String settingsQuietHoursRange(String start, String end) {
    return 'De $start à $end';
  }

  @override
  String get settingsEditQuietHours => 'Modifier les heures de silence';

  @override
  String get settingsPreferencesSection => 'Préférences';

  @override
  String get settingsSound => 'Son';

  @override
  String get settingsSoundDetail => 'Des sons pour les moments clés.';

  @override
  String get settingsHaptics => 'Vibrations';

  @override
  String get settingsHapticsDetail =>
      'De petites vibrations quand tu touches l’écran.';

  @override
  String get settingsAnimations => 'Animations';

  @override
  String get settingsAnimationsLimited =>
      'Limitées par un réglage de ton téléphone.';

  @override
  String get settingsAnimationsDetail => 'Mouvements et célébrations.';

  @override
  String get settingsReduceMotion => 'Réduire les animations';

  @override
  String get settingsReduceMotionOn =>
      'Activé. Suit le réglage de ton téléphone.';

  @override
  String get settingsReduceMotionOff =>
      'Désactivé. Suit le réglage de ton téléphone.';

  @override
  String get settingsPaperLimit => 'Limite d’argent d’entraînement';

  @override
  String get settingsResetPaper => 'Réinitialiser l’entraînement';

  @override
  String get settingsResetPaperBusy =>
      'Réinitialisation de ton bureau d’entraînement.';

  @override
  String get settingsResetPaperPending =>
      'La réinitialisation que tu as confirmée n’est pas encore terminée.';

  @override
  String get settingsResetPaperDetail =>
      'Efface tes opérations d’entraînement et recommence.';

  @override
  String get settingsResetPaperTitle =>
      'Réinitialiser ton bureau d’entraînement ?';

  @override
  String get settingsResetPaperBody =>
      'Tu repars d’un bureau d’entraînement tout neuf. Tes anciens reçus restent dans ton historique. Ta Carrière, tes Trims, ton rang, ta série et ton argent ne changent pas.';

  @override
  String get settingsResetPaperPhrase => 'réinitialiser mon bureau';

  @override
  String settingsResetPaperInstruction(String phrase) {
    return 'Écris « $phrase » pour continuer.';
  }

  @override
  String settingsResetPaperFieldLabel(String phrase) {
    return 'Phrase de confirmation. Écris $phrase.';
  }

  @override
  String get settingsResetPaperFieldTitle => 'Phrase de confirmation';

  @override
  String get settingsResetPaperConfirm => 'Réinitialiser';

  @override
  String get settingsResetPaperDoneTitle =>
      'Bureau d’entraînement réinitialisé';

  @override
  String settingsResetPaperDone(String amount) {
    return 'Ton bureau est prêt avec $amount en argent d’entraînement.';
  }

  @override
  String settingsResetPaperDoneNewer(String amount) {
    return 'Les opérations plus récentes ont été conservées. Ton solde est de $amount en argent d’entraînement.';
  }

  @override
  String get settingsResetPaperFailed =>
      'Ton bureau d’entraînement n’a pas été réinitialisé. Réessaie.';

  @override
  String get settingsResetPaperStale =>
      'Ton bureau d’entraînement a changé et a été actualisé. Vérifie-le, puis confirme à nouveau la réinitialisation.';

  @override
  String get settingsResetPaperNotNeeded =>
      'Ton bureau d’entraînement est déjà tout neuf. Rien n’a été effacé.';

  @override
  String get settingsResetPaperOffline =>
      'Tu es hors ligne. Ta demande de réinitialisation est enregistrée telle quelle pour réessayer sans risque.';

  @override
  String get settingsResetPaperTimeout =>
      'La réinitialisation a mis trop de temps à être confirmée. Ta demande est enregistrée telle quelle pour réessayer sans risque.';

  @override
  String get settingsResetPaperAccountRequired =>
      'Ton bureau d’entraînement a besoin d’une nouvelle session pour terminer la réinitialisation.';

  @override
  String get settingsResetPaperRateLimited =>
      'Les réinitialisations de l’entraînement sont limitées. Réessaie cette demande enregistrée plus tard.';

  @override
  String get settingsResetPaperUnavailable =>
      'La réinitialisation n’a pas pu être confirmée. Ta demande est enregistrée telle quelle pour réessayer sans risque.';

  @override
  String get settingsResetPaperRejected =>
      'Ton bureau d’entraînement n’a pas été réinitialisé. Actualise ton bureau et réessaie.';

  @override
  String get settingsMoneySection => 'Argent';

  @override
  String get settingsMoneyCardOrCrypto => 'Carte ou crypto';

  @override
  String get settingsMoneyComingSoon =>
      'Le trading en argent réel arrivera plus tard.';

  @override
  String get settingsMoneyUnavailable =>
      'Les fonctions liées à l’argent ne sont pas disponibles pour ce compte.';

  @override
  String get settingsCurrency => 'Devise';

  @override
  String get settingsDepositPartner => 'Partenaire de dépôt';

  @override
  String get settingsFees => 'Frais';

  @override
  String get settingsCountryCheck => 'Vérification du pays';

  @override
  String get settingsBankAccounts => 'Comptes bancaires';

  @override
  String get settingsCards => 'Cartes';

  @override
  String get settingsWallet => 'Portefeuille';

  @override
  String get settingsWalletNoDetails =>
      'Aucun détail du portefeuille pour l’instant.';

  @override
  String get settingsWalletComingSoon =>
      'Les outils du portefeuille arriveront plus tard.';

  @override
  String get settingsWalletUnavailable =>
      'Les outils du portefeuille ne sont pas disponibles pour ce compte.';

  @override
  String get settingsCheckWallet => 'Voir le portefeuille';

  @override
  String get settingsBackUpWallet => 'Sauvegarder le portefeuille';

  @override
  String get settingsBackUpWalletDetail => 'Garde l’accès en dehors de Trimmy.';

  @override
  String get settingsPrivacySection => 'Confidentialité';

  @override
  String get settingsHoldingsVisibility => 'Qui voit mes placements';

  @override
  String get settingsVisibilityFriends => 'Amis';

  @override
  String get settingsVisibilityEveryone => 'Tout le monde';

  @override
  String get settingsVisibilityNobody => 'Personne';

  @override
  String get settingsDownloadData => 'Télécharger mes données';

  @override
  String get settingsSupportSection => 'Assistance';

  @override
  String get settingsSendFeedback => 'Donner ton avis';

  @override
  String get settingsReportBug => 'Signaler un bug';

  @override
  String get settingsReportBugDetail => 'La version de ton app sera jointe.';

  @override
  String get settingsLegalSection => 'Informations légales';

  @override
  String get settingsRiskNotice => 'Avertissement sur les risques';

  @override
  String get settingsAboutTokenizedStocks => 'À propos des actions tokenisées';

  @override
  String get settingsAboutTokenizedStocksDetail =>
      'Ce qu’elles sont et ce qu’elles ne sont pas.';

  @override
  String get settingsAccountClosureSection => 'Fermeture du compte';

  @override
  String get settingsCloseAccount => 'Fermer le compte';

  @override
  String get settingsCloseAccountDetail =>
      'Vois ce qui arrive à ton historique et à ton portefeuille.';

  @override
  String get sendErrorCheckInput => 'Vérifie l’adresse et le montant.';

  @override
  String get sendErrorSelf =>
      'C’est ton propre portefeuille. Saisis une autre adresse.';

  @override
  String get sendErrorNotWallet =>
      'Cette adresse n’est pas un portefeuille. C’est peut-être un compte de token ou un programme. Demande plutôt l’adresse du portefeuille.';

  @override
  String get sendErrorDestinationFrozen =>
      'Ce portefeuille ne peut pas recevoir ce token pour le moment.';

  @override
  String get sendErrorAssetUnsupported =>
      'Ce token ne peut pas être envoyé depuis Trimmy.';

  @override
  String get sendErrorNotTransferable =>
      'Ce token a des règles de transfert qui empêchent Trimmy de l’envoyer.';

  @override
  String get sendErrorAssetPaused =>
      'Son émetteur a suspendu les transferts pour le moment.';

  @override
  String get sendErrorAssetFrozen =>
      'Ce token est gelé dans ton portefeuille. Contacte son émetteur.';

  @override
  String get sendErrorInsufficient => 'Tu n’en as pas autant à envoyer.';

  @override
  String get sendErrorAddSol =>
      'Ajoute un peu de SOL pour couvrir les frais de réseau.';

  @override
  String sendErrorLeaveSol(String amount) {
    return 'Garde au moins $amount SOL, ou envoie tout.';
  }

  @override
  String sendErrorTooSmall(String amount) {
    return 'Un nouveau portefeuille a besoin d’au moins $amount SOL pour être ouvert.';
  }

  @override
  String get sendErrorCheckFailed =>
      'Cet envoi n’a pas passé la vérification. Rien n’a été envoyé.';

  @override
  String get sendErrorReviewExpired =>
      'Cette vérification a expiré. Vérifie à nouveau.';

  @override
  String get sendErrorPrevious =>
      'Vérifie ton envoi précédent avant d’en commencer un autre.';

  @override
  String get sendErrorMismatch =>
      'Cette transaction ne correspond pas à ce que tu as vérifié. Rien n’a été envoyé.';

  @override
  String get sendErrorStorage =>
      'Autorise le stockage de l’appareil pour pouvoir retrouver ton envoi.';

  @override
  String get sendErrorBusy => 'Un instant, puis réessaie.';

  @override
  String get sendErrorCancelled =>
      'La signature a été annulée. Rien n’a été envoyé.';

  @override
  String get sendErrorPaused =>
      'Les envois sont en pause pour le moment. Réessaie plus tard.';

  @override
  String get sendErrorGeneric =>
      'Impossible de se connecter pour l’envoi. Réessaie.';

  @override
  String get sendRecoveryFailed =>
      'Impossible de vérifier ton envoi précédent. Réessaie de le vérifier.';

  @override
  String get sendEnterAddress => 'Saisis une adresse de portefeuille Solana.';

  @override
  String get sendEnterAmount => 'Saisis un montant.';

  @override
  String sendHaveReady(String amount) {
    return 'Tu as $amount à envoyer.';
  }

  @override
  String get sendTitle => 'Envoyer';

  @override
  String get sendCheckPrevious => 'Vérifier l’envoi précédent';

  @override
  String get sendNothingTitle => 'Rien à envoyer pour l’instant';

  @override
  String get sendNothingBody =>
      'Ajoute d’abord de l’argent ou achète une action. Tout ce qui est dans ton portefeuille peut être envoyé d’ici.';

  @override
  String get sendHeading => 'Envoyer vers un portefeuille Solana';

  @override
  String get sendWarning =>
      'Envoie uniquement vers une adresse Solana. Un envoi est irréversible.';

  @override
  String get sendWhatLabel => 'Ce que tu envoies';

  @override
  String get sendAssetUsdc => 'Dollars américains (USDC)';

  @override
  String get sendRecipientLabel => 'Adresse du portefeuille destinataire';

  @override
  String get sendPaste => 'Coller';

  @override
  String get sendSharesLabel => 'Actions';

  @override
  String sendAmountLabel(String symbol) {
    return 'Montant ($symbol)';
  }

  @override
  String sendReadyToSend(String amount) {
    return 'Disponible à l’envoi : $amount';
  }

  @override
  String sendMaxKeepsSol(String amount) {
    return 'Max garde $amount SOL pour que tu puisses encore payer les frais de réseau.';
  }

  @override
  String get sendReview => 'Vérifier l’envoi';

  @override
  String get sendReviewTitle => 'Vérifie ton envoi';

  @override
  String get sendYouSend => 'Tu envoies';

  @override
  String get sendTheyReceive =>
      'Le destinataire reçoit, après les frais de l’émetteur';

  @override
  String get sendNetworkFee => 'Frais de réseau';

  @override
  String sendOpensAccount(String symbol) {
    return 'Ouvre son compte $symbol (une seule fois)';
  }

  @override
  String get sendToWallet => 'Vers ce portefeuille Solana';

  @override
  String get sendCheckEvery =>
      'Vérifie chaque caractère. Un envoi est irréversible, et Trimmy ne peut pas récupérer l’argent envoyé à une mauvaise adresse.';

  @override
  String get sendNow => 'Envoyer maintenant';

  @override
  String get sendEdit => 'Modifier';

  @override
  String get sendResultSent => 'Envoyé';

  @override
  String get sendResultSending => 'Envoi en cours';

  @override
  String get sendResultFailed => 'L’envoi n’a pas abouti';

  @override
  String get sendResultExpired => 'Envoi expiré';

  @override
  String get sendResultChecking => 'Confirmation en cours';

  @override
  String get sendBodySent => 'C’est confirmé sur Solana.';

  @override
  String get sendBodySending => 'Ça prend généralement quelques secondes.';

  @override
  String get sendBodyFailed =>
      'Solana l’a refusé. Seuls les frais de réseau ont été dépensés.';

  @override
  String get sendBodyExpired =>
      'Cette transaction a expiré sans confirmation. Tu peux vérifier un nouvel envoi.';

  @override
  String get sendBodyChecking =>
      'On vérifie encore cet envoi. Ne le renvoie pas.';

  @override
  String get sendViewSolscan => 'Voir sur Solscan';

  @override
  String get sendCloseFailed =>
      'Cet envoi est enregistré. Réessaie de le fermer.';

  @override
  String get reminderDailyLabel => 'En semaine';

  @override
  String get reminderDailyCaption => 'Vers 19 h, quand du travail t’attend.';

  @override
  String get reminderOccasionalLabel => 'Quelques fois par semaine';

  @override
  String get reminderOccasionalCaption =>
      'Lundi, mercredi et vendredi, vers 19 h.';

  @override
  String get reminderOffLabel => 'Pas de rappels';

  @override
  String get reminderOffCaption => 'Je reviendrai de moi-même.';

  @override
  String get reminderNotificationTitle => 'Ton bureau t’attend';

  @override
  String get reminderNotificationBody =>
      'Ta prochaine mission t’attend à ton bureau.';

  @override
  String reminderNotificationDay(int day, String title) {
    return 'Jour $day : $title';
  }

  @override
  String get pushErrorNotificationsOff =>
      'Les notifications sont désactivées dans les réglages de l’appareil.';

  @override
  String get pushErrorUpdate =>
      'Impossible de mettre à jour les notifications. Réessaie.';

  @override
  String get pushErrorTurnOff =>
      'Impossible de désactiver les alertes. Réessaie une fois en ligne.';

  @override
  String get pushErrorConnect =>
      'Impossible de connecter les notifications. Réessaie.';

  @override
  String get signInResendCode => 'Envoyer un nouveau code';

  @override
  String signInResendIn(int seconds) {
    return 'Renvoyer dans $seconds s';
  }

  @override
  String get appCloseAccountClosing => 'Fermeture de ton compte…';

  @override
  String get appCloseAccountFailed => 'Ton compte n’a pas été fermé. Réessaie.';
}

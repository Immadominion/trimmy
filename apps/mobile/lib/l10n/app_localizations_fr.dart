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
  String get rankRookie => 'Débutant';

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
}

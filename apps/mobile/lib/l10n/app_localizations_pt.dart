// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonDone => 'Concluir';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonBack => 'Voltar';

  @override
  String get commonTryAgain => 'Tentar de novo';

  @override
  String get commonRetry => 'Tentar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonSignIn => 'Entrar';

  @override
  String get commonMax => 'Máx.';

  @override
  String get commonBuy => 'Comprar';

  @override
  String get commonSell => 'Vender';

  @override
  String get rankRookie => 'Novato';

  @override
  String get rankAnalyst => 'Analista';

  @override
  String get rankTrader => 'Trader';

  @override
  String get rankSeniorTrader => 'Trader sênior';

  @override
  String get rankPartner => 'Sócio';

  @override
  String get rankLegend => 'Lenda';

  @override
  String formatCompactThousand(String value) {
    return '$value mil';
  }

  @override
  String formatCompactMillion(String value) {
    return '$value mi';
  }

  @override
  String formatCompactBillion(String value) {
    return '$value bi';
  }

  @override
  String formatCompactTrillion(String value) {
    return '$value tri';
  }

  @override
  String get marketPriceUnavailable => 'Preço indisponível';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguagePhone => 'Idioma do celular';

  @override
  String get settingsLanguagePhoneDetail =>
      'Usa o idioma configurado no seu celular.';
}

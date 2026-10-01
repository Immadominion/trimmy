// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonTryAgain => 'Intentar de nuevo';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonSignIn => 'Iniciar sesión';

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
  String get rankSeniorTrader => 'Trader sénior';

  @override
  String get rankPartner => 'Socio';

  @override
  String get rankLegend => 'Leyenda';

  @override
  String formatCompactThousand(String value) {
    return '$value mil';
  }

  @override
  String formatCompactMillion(String value) {
    return '$value M';
  }

  @override
  String formatCompactBillion(String value) {
    return '$value mil M';
  }

  @override
  String formatCompactTrillion(String value) {
    return '$value B';
  }

  @override
  String get marketPriceUnavailable => 'Precio no disponible';

  @override
  String get commonAddMoney => 'Agregar dinero';

  @override
  String get commonSaving => 'Guardando…';

  @override
  String get commonChecking => 'Verificando…';

  @override
  String get commonConnecting => 'Conectando…';

  @override
  String get commonSending => 'Enviando…';

  @override
  String get commonConfirming => 'Confirmando…';

  @override
  String get commonLoading => 'Cargando…';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonRefresh => 'Actualizar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonNotNow => 'Ahora no';

  @override
  String get commonSkip => 'Omitir';

  @override
  String get commonHistory => 'Historial';

  @override
  String get commonSettings => 'Configuración';

  @override
  String commonInProgress(String label) {
    return '$label en curso';
  }

  @override
  String get modePaper => 'Práctica';

  @override
  String get modeReal => 'Real';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguagePhone => 'Idioma del teléfono';

  @override
  String get settingsLanguagePhoneDetail =>
      'Usa el idioma que tiene tu teléfono.';
}

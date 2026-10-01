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

  @override
  String get appGuestChoiceNotSaved =>
      'No pudimos guardar tu elección. Inténtalo de nuevo.';

  @override
  String get appDeskAlreadySaved => 'Tu escritorio ya está guardado.';

  @override
  String get appDeskReconnecting =>
      'Tu escritorio se está reconectando. Inténtalo en un momento.';

  @override
  String get appSwitchedToPaper => 'Cambiaste al modo Práctica.';

  @override
  String get appReasonBeingChecked =>
      'Estamos revisando el motivo que guardaste. Actualiza tu carrera.';

  @override
  String get appReasonNeedsPaperDesk =>
      'Tu escritorio de práctica debe estar en línea antes de que puedas escribir este motivo.';

  @override
  String get appReasonNeedsPaperBuy =>
      'Esta misión necesita una compra de práctica confirmada que aún tengas. Elige una acción cuando quieras.';

  @override
  String get appPromotionRefreshFirst =>
      'Actualiza tu carrera antes de reclamar este ascenso.';

  @override
  String get appPromotionNotPrepared =>
      'No pudimos preparar tu ascenso. Inténtalo de nuevo.';

  @override
  String get appPromotionCareerChanged =>
      'Tu carrera cambió. Actualízala y vuelve a intentarlo.';

  @override
  String get appPaperDeskStillOpening =>
      'Tu escritorio de práctica todavía se está abriendo. Inténtalo de nuevo.';

  @override
  String get appFirstTradeStepNotSaved =>
      'Tu operación está a salvo, pero este paso no se guardó.';

  @override
  String get appStockCouldNotOpen =>
      'No se pudo abrir esta acción. Inténtalo de nuevo.';

  @override
  String get appHistoryCouldNotConnect =>
      'No se pudo cargar el historial. Inténtalo de nuevo.';

  @override
  String get appReportNotSent =>
      'No se pudo enviar el reporte. Inténtalo de nuevo.';

  @override
  String get appBlockFailed =>
      'No se pudo bloquear a este trader. Inténtalo de nuevo.';

  @override
  String get appWalletAddressCopied => 'Dirección de la billetera copiada.';

  @override
  String get appWalletBackupFailed =>
      'No se pudo abrir la copia de seguridad de la billetera. Inténtalo de nuevo.';

  @override
  String get appPaperDeskOpening => 'Abriendo tu escritorio de práctica.';

  @override
  String get appPaperDeskOffline =>
      'Tu escritorio de práctica está sin conexión. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get appPaperDeskTimeout =>
      'Tu escritorio de práctica tardó demasiado en abrir. Inténtalo de nuevo.';

  @override
  String get appPaperDeskSession =>
      'Tu escritorio de práctica necesita una nueva sesión. Inténtalo de nuevo.';

  @override
  String get appPaperDeskUnavailable =>
      'Tu escritorio de práctica no está disponible. Inténtalo de nuevo.';

  @override
  String get appCareerStale =>
      'Mostramos tu último historial de carrera confirmado. Actualiza para verlo al día.';

  @override
  String get appMissionsMismatch =>
      'Tu carrera cambió mientras cargaban las misiones. Actualiza para sincronizarlas.';

  @override
  String get appMissionsStale =>
      'Mostramos tus últimas misiones confirmadas. Actualiza para verlas al día.';

  @override
  String get appMissionsOffline =>
      'Tus misiones están sin conexión. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get appMissionsTimeout =>
      'Tus misiones tardaron demasiado en abrir. Inténtalo de nuevo.';

  @override
  String get appMissionsSession =>
      'Tus misiones necesitan una nueva sesión. Inténtalo de nuevo.';

  @override
  String get appMissionsRateLimited =>
      'Tus misiones se están actualizando demasiado rápido. Inténtalo en un rato.';

  @override
  String get appMissionsProfileRequired =>
      'Termina de configurar tu perfil de Trimmy y vuelve a intentarlo.';

  @override
  String get appMissionsUnavailable =>
      'Tus misiones no están disponibles. Inténtalo de nuevo.';

  @override
  String get appProfileUnavailable =>
      'Tu perfil de Trimmy no está disponible. Inténtalo de nuevo.';

  @override
  String get appAccountEntryFailed =>
      'Tu cuenta está conectada. Intenta abrir tu escritorio otra vez.';

  @override
  String get appRealBalanceLabel => 'Saldo total';

  @override
  String get appRealBalanceUpdating => 'Actualizando saldo…';

  @override
  String get appRealBalanceUsdcAvailable => 'USDC disponible';

  @override
  String appRealBalanceSplit(String cash, String stocks) {
    return '$cash disponible · $stocks en acciones';
  }

  @override
  String get appDeskStaleBoth =>
      'Mostramos tu último escritorio de práctica y tu historial de carrera confirmados. Las operaciones están en pausa hasta que Trimmy se reconecte.';

  @override
  String get appDeskStalePaper =>
      'Mostramos tu último escritorio de práctica confirmado. Las operaciones están en pausa hasta que Trimmy se reconecte.';

  @override
  String get appTradingCouldNotConnect => 'No pudimos conectar para operar.';

  @override
  String get appTradingChecking => 'Verificando operaciones…';

  @override
  String get appTradingPaused => 'Las operaciones están en pausa por ahora.';

  @override
  String get appTradingNotTradeable =>
      'Todavía no se puede operar con dinero real.';

  @override
  String get appVersionIssuerUnavailable => 'Emisor no disponible';

  @override
  String get appVersionBackingUnavailable =>
      'Los detalles del respaldo no están disponibles en estos datos del mercado.';

  @override
  String get appVersionTradingHoursUnavailable =>
      'Se opera en la blockchain. El horario del emisor no está disponible.';

  @override
  String get appRealMissionTitle => 'Una misión de práctica';

  @override
  String get appRealMissionBody => 'Complétala en tu escritorio de práctica.';

  @override
  String get appRealMissionButton => 'Abrir escritorio de práctica';

  @override
  String get appCloseAccountTitle => '¿Cerrar tu cuenta?';

  @override
  String get appCloseAccountBodyNoWallet =>
      'Perderás el acceso a la cuenta guardada. Los registros que debemos conservar seguirán protegidos.';

  @override
  String get appCloseAccountBodyWallet =>
      'Asegura el acceso a tu billetera antes de cerrar tu cuenta. Cerrarla no moverá sus fondos. Perderás el acceso a tu escritorio guardado.';

  @override
  String get appCloseAccountBackUpWallet => 'Respaldar billetera';

  @override
  String get appCloseAccountConfirm => 'Cerrar cuenta';

  @override
  String get appFirstTradePrompt =>
      'Elige una empresa. Tu primera operación es gratis.';

  @override
  String get appOpeningTrimmy => 'Abriendo Trimmy';

  @override
  String get appCouldNotOpenTrimmy => 'No se pudo abrir Trimmy';

  @override
  String get appOpeningDesk => 'Abriendo tu escritorio';

  @override
  String get appCouldNotOpenDesk => 'No se pudo abrir tu escritorio';

  @override
  String get appOpeningTrade => 'Abriendo tu operación';

  @override
  String get appCouldNotLoadTrade => 'No se pudo cargar tu operación';

  @override
  String get appCouldNotLoadTradeBody =>
      'Inténtalo de nuevo para ver tu orden confirmada.';

  @override
  String get appSplashOpening => 'Trimmy se está abriendo';

  @override
  String get designCastSal => 'Sal, tu jefe en el piso de operaciones';

  @override
  String get designCastWolf => 'Retrato del trader Wolf';

  @override
  String get designCastOracle => 'Retrato del trader Oracle';

  @override
  String get designCastShark => 'Retrato del trader Shark';

  @override
  String get designPaperMark => 'dinero de práctica';

  @override
  String designPaperAmount(String amount) {
    return '$amount en dinero de práctica';
  }

  @override
  String get designUseRealMoney => 'Usar dinero real';

  @override
  String get designDismissMessage => 'Cerrar mensaje';

  @override
  String get designCompleted => 'Completado';

  @override
  String appPromotionTitle(String rankId, String rank) {
    String _temp0 = intl.Intl.selectLogic(rankId, {
      'analyst': '¡Ahora eres $rank!',
      'other': '¡Ahora eres $rank!',
    });
    return '$_temp0';
  }

  @override
  String get appPromotionMessage =>
      'Un nuevo capítulo en el piso de operaciones.';

  @override
  String get appPromotionFrom => 'Antes';

  @override
  String get appPromotionNewRank => 'Nuevo rango';

  @override
  String get appPromotionEarned => 'Ganaste';

  @override
  String appPromotionTrims(String trims) {
    return '$trims Trims';
  }

  @override
  String get appPromotionBackToCareer => 'Volver a Carrera';

  @override
  String get appFirstPositionTitle => 'Tu primera posición.';

  @override
  String get appFirstPositionMessage => '¡Hiciste tu primera orden!';

  @override
  String get appFirstPositionStock => 'Acción';

  @override
  String get appFirstPositionShares => 'Cantidad';

  @override
  String get appFirstPositionTime => 'Hora';

  @override
  String appFirstPositionTimeUtc(String time) {
    return '$time UTC';
  }

  @override
  String get appDayOneTitle => 'Día 1, completado.';

  @override
  String get appDayOneMessage => 'Nos vemos mañana en el piso de operaciones.';

  @override
  String get appSessionGuestRecovery =>
      'Este escritorio de invitado necesita recuperarse.';

  @override
  String get appSessionAnswersNotSaved =>
      'No pudimos guardar tus respuestas. Inténtalo una vez más.';

  @override
  String get appSessionStepNotSaved =>
      'No pudimos guardar ese paso. Inténtalo de nuevo.';

  @override
  String get appSessionSetupUnreadable =>
      'No pudimos abrir tu configuración de Trimmy. Empieza de nuevo.';

  @override
  String get appSessionReadOffline =>
      'Tu perfil está sin conexión. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get appSessionReadTimeout =>
      'Tu perfil tardó demasiado en abrir. Inténtalo de nuevo.';

  @override
  String get appSessionReadSession =>
      'Tu perfil necesita una nueva sesión. Inténtalo de nuevo.';

  @override
  String get appSessionReadUnavailable =>
      'Tu perfil no está disponible. Inténtalo de nuevo.';

  @override
  String get appSessionHandleTaken => 'Ese nombre ya está en uso. Elige otro.';

  @override
  String get appSessionTradeRequired =>
      'Tu operación confirmada debe llegar a tu escritorio antes de seguir con este paso.';

  @override
  String get appSessionNotReady =>
      'Trimmy todavía está confirmando ese momento. Inténtalo de nuevo.';

  @override
  String get appSessionPrincipalChanged =>
      'La identidad de tu escritorio cambió. Ábrelo de nuevo y vuelve a intentarlo.';

  @override
  String get appSessionConflict =>
      'Tu perfil cambió en otro dispositivo. Inténtalo de nuevo.';

  @override
  String get appSessionWriteOffline =>
      'Estás sin conexión. Vuelve a conectarte e inténtalo de nuevo.';

  @override
  String get appSessionWriteTimeout =>
      'Eso tardó demasiado. Inténtalo de nuevo.';

  @override
  String get appSessionWriteSession =>
      'Tu sesión cambió. Vuelve a abrir tu perfil.';

  @override
  String get appSessionWriteFailed =>
      'Ese paso no se guardó. Inténtalo de nuevo.';

  @override
  String get appMarketLoadMoreFailed =>
      'No pudimos cargar más acciones. Inténtalo de nuevo.';

  @override
  String get appMarketCatalogFailed =>
      'No se pudieron cargar las acciones. Desliza hacia abajo para intentarlo de nuevo.';

  @override
  String get appMarketNoStarterPicks =>
      'Las sugerencias para empezar no están disponibles. Busca por empresa o símbolo.';

  @override
  String get appMarketNotConfigured =>
      'Los datos del mercado no están configurados en esta versión.';

  @override
  String get appMarketBusy =>
      'Los datos del mercado están saturados. Inténtalo en un momento.';

  @override
  String get appMarketTimeout =>
      'Los datos del mercado tardaron demasiado. Inténtalo de nuevo.';

  @override
  String get appMarketOffline =>
      'Estás sin conexión. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get appMarketUnavailable =>
      'No se pudieron cargar las acciones. Inténtalo de nuevo.';

  @override
  String get tabDesk => 'Escritorio';

  @override
  String get tabMarket => 'Mercado';

  @override
  String get tabCareer => 'Carrera';

  @override
  String get tabProfile => 'Perfil';

  @override
  String get firstTradeSkip => 'Saltar la primera operación';

  @override
  String get firstTradeTitle => 'Tu primera jugada.';

  @override
  String get firstTradeOpeningDesk => 'Abriendo tu escritorio de práctica…';

  @override
  String get firstTradeDeskUnavailable =>
      'Tu escritorio de práctica no está disponible. Inténtalo de nuevo.';

  @override
  String get firstTradeContinueError =>
      'No se pudo continuar. Inténtalo de nuevo.';

  @override
  String get firstTradePickCompany => 'Elige una empresa.';

  @override
  String get firstTradeHint => 'Pista';

  @override
  String get firstTradeCompanyGuide =>
      'Una acción es una pequeña parte de una empresa. Elige una.';

  @override
  String get firstTradeAmountTitle => 'Elige el monto';

  @override
  String get firstTradeAmountGuide => 'Elige un monto para probar. Es gratis.';

  @override
  String get firstTradeReviewBuy => 'Revisar compra';

  @override
  String get firstTradeOrderPlaced => '¡Hiciste tu primera orden!';

  @override
  String get firstTradeCreateProfile =>
      'Ahora vamos a crear tu perfil de trader.';

  @override
  String get firstTradeBuyConfirmed => 'Compra confirmada';

  @override
  String get firstTradeInvested => 'Invertido';

  @override
  String firstTradeSharesLine(String shares) {
    return 'Acciones  $shares';
  }

  @override
  String firstTradeTrimsEarned(String trims) {
    return '+$trims Trims';
  }

  @override
  String get firstTradeKeepFreeMoney => 'Seguir con dinero gratis';

  @override
  String get firstTradeKeepFreeMoneyDetail =>
      'Gana confianza en tu escritorio.';

  @override
  String firstTradeSharesCount(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares acciones',
      one: '$shares acción',
    );
    return '$_temp0';
  }

  @override
  String firstTradeFreeMoneyAmount(String amount) {
    return '$amount en dinero gratis';
  }

  @override
  String get firstTradeNextMove => 'Tu siguiente jugada.';

  @override
  String get firstTradeNextMoveBody =>
      'Sigue tomando confianza o agrega dinero a tu billetera.';

  @override
  String get firstTradeAddMoneyDetail => 'Mira tus opciones para depositar.';

  @override
  String get firstTradeAddMoneyLater =>
      'Puedes agregar dinero desde tu escritorio cuando quieras.';

  @override
  String get firstTradeContinueSafe =>
      'Tu operación está a salvo. Intenta continuar de nuevo.';

  @override
  String get amountPickerErrorEmpty => 'Escribe un monto.';

  @override
  String get amountPickerErrorDecimals => 'Usa como máximo 2 decimales.';

  @override
  String amountPickerErrorMin(String amount) {
    return 'Elige al menos $amount.';
  }

  @override
  String amountPickerErrorMax(String amount) {
    return 'Elige como máximo $amount.';
  }

  @override
  String get amountPickerFieldLabel => 'Monto en dólares';

  @override
  String amountPickerEditSemantics(num value, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'Monto, $amount dólares. Editar monto',
      one: 'Monto, $amount dólar. Editar monto',
    );
    return '$_temp0';
  }

  @override
  String amountPickerDecreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Bajar el monto $amount dólares',
      one: 'Bajar el monto $amount dólar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerIncreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Subir el monto $amount dólares',
      one: 'Subir el monto $amount dólar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerPresetSemantics(num amount, String amountText) {
    String _temp0 = intl.Intl.pluralLogic(
      amount,
      locale: localeName,
      other: 'Fijar el monto en $amountText dólares',
      one: 'Fijar el monto en $amountText dólar',
    );
    return '$_temp0';
  }

  @override
  String get onboardingGoalLearn => 'Aprender';

  @override
  String get onboardingGoalLearnDetail => 'Empieza por lo básico.';

  @override
  String get onboardingGoalPractice => 'Practicar';

  @override
  String get onboardingGoalPracticeDetail =>
      'Toma decisiones con dinero de práctica.';

  @override
  String get onboardingGoalTrade => 'Operar con dinero de práctica';

  @override
  String get onboardingGoalTradeDetail =>
      'Gana confianza con precios en tiempo real.';

  @override
  String get onboardingGoalFriends => 'Amigos';

  @override
  String get onboardingGoalFriendsDetail =>
      'Las ligas aún no están disponibles.';

  @override
  String get onboardingKnowledgeNothing => 'Nada todavía';

  @override
  String get onboardingKnowledgeBasics => 'Sé lo básico';

  @override
  String get onboardingKnowledgePractised => 'Ya practiqué';

  @override
  String get onboardingKnowledgeTraded => 'Ya operé antes';

  @override
  String get onboardingKnowledgeDaily => 'Opero todos los días';

  @override
  String get onboardingDailyShowUp => 'Estar presente';

  @override
  String get onboardingDailyShowUpDetail =>
      'Abre Trimmy y revisa tu escritorio.';

  @override
  String get onboardingDailyOneMove => 'Una jugada';

  @override
  String get onboardingDailyOneMoveDetail =>
      'Haz una operación de práctica bien pensada.';

  @override
  String get onboardingDailyThreeMoves => 'Tres jugadas';

  @override
  String get onboardingDailyThreeMovesDetail =>
      'Haz tres operaciones de práctica bien pensadas.';

  @override
  String get onboardingSalHello =>
      'Cinco preguntas rápidas y luego tu primera operación de práctica.';

  @override
  String get onboardingQuestionGoal => '¿Por qué estás aquí?';

  @override
  String get onboardingQuestionKnowledge => '¿Cuánto sabes de la bolsa?';

  @override
  String get onboardingQuestionPersona => 'Elige tu trader.';

  @override
  String get onboardingQuestionDailyGoal => 'Elige tu meta diaria.';

  @override
  String get onboardingQuestionHandle => '¿Cómo te van a llamar en el piso?';

  @override
  String get onboardingHandleLabel => 'Nombre de usuario';

  @override
  String get onboardingHandleHelper => 'De 3 a 18 caracteres';

  @override
  String get onboardingHandleTooShort => 'Usa al menos 3 caracteres.';

  @override
  String get onboardingHandleTooLong => 'Usa 18 caracteres como máximo.';

  @override
  String get onboardingHandleStartWithLetter => 'Empieza con una letra.';

  @override
  String get onboardingHandleCharacters =>
      'Usa letras, números o guiones bajos.';

  @override
  String get onboardingProgressLabel => 'Progreso de la configuración inicial';

  @override
  String onboardingProgressValue(int percent) {
    return '$percent por ciento';
  }

  @override
  String onboardingProgressStep(int step, int total) {
    return '$step de $total';
  }

  @override
  String onboardingSalSays(String text) {
    return 'Sal dice: $text';
  }

  @override
  String get onboardingNotificationsAsk =>
      'Te aviso cuando Wall Street abra y cierre. Aquí puedes operar a cualquier hora.';

  @override
  String get onboardingNotificationsSoon => 'Las alertas están casi listas.';

  @override
  String get onboardingNotificationsPhoneAsks =>
      'Ahora tu teléfono te preguntará.';

  @override
  String get onboardingNotificationsKeepSettingUp =>
      'Sigue configurando tu escritorio.';

  @override
  String get onboardingNotificationsChangeLater =>
      'Puedes cambiar las alertas cuando quieras en Configuración.';

  @override
  String get onboardingNotificationsLater =>
      'Las alertas aparecerán aquí cuando se active el envío.';

  @override
  String get onboardingNotificationsSaving => 'Guardando tu configuración';

  @override
  String get onboardingNotificationsTurnOn => 'Activar alertas';

  @override
  String get onboardingReviewAnswers => 'Revisar mis respuestas';

  @override
  String get onboardingOpeningMarket => 'Abriendo el mercado';

  @override
  String get onboardingSetupNotSaved =>
      'No se guardó tu configuración. Inténtalo de nuevo.';

  @override
  String get onboardingPermissionRequestFailed =>
      'El teléfono no abrió la solicitud. Inténtalo de nuevo.';

  @override
  String get onboardingSalPortrait => 'Sal, tu jefe de piso';

  @override
  String get onboardingPermissionPreview =>
      'Vista previa del permiso de notificaciones del teléfono';

  @override
  String get onboardingIntroSaveError =>
      'No se pudo guardar este paso. Inténtalo de nuevo.';

  @override
  String get onboardingIntroSaving => 'Guardando tu progreso';

  @override
  String get onboardingCouldNotSave =>
      'No se pudo guardar. Inténtalo de nuevo.';

  @override
  String get onboardingReminderSkip => 'Omitir recordatorios';

  @override
  String get onboardingReminderTitle => '¿Un recordatorio?';

  @override
  String get onboardingReminderQuestion =>
      '¿Cada cuánto quieres un recordatorio?';

  @override
  String get onboardingReminderPermissionOff =>
      'Las notificaciones están desactivadas. Puedes cambiarlo en la configuración de tu teléfono.';

  @override
  String get onboardingReminderUnavailable =>
      'Tu preferencia se guardó. Las notificaciones aún no están disponibles en esta versión.';

  @override
  String get onboardingReminderNotSet =>
      'No se pudo programar el recordatorio. Inténtalo de nuevo.';

  @override
  String get onboardingReminderChanged =>
      'Tu preferencia cambió en otro dispositivo. Vuelve a elegir.';

  @override
  String get onboardingReminderSavedNotSet =>
      'Se guardó en este teléfono. No se pudo programar el recordatorio. Inténtalo de nuevo.';

  @override
  String get onboardingReminderSavedOffline =>
      'Se guardó en este teléfono. Se volverá a sincronizar cuando tengas conexión.';

  @override
  String get personaWolfName => 'Wolf';

  @override
  String get personaOracleName => 'Oracle';

  @override
  String get personaSharkName => 'Shark';

  @override
  String get personaWolfDetail =>
      'Audaz. Veloz. Le encantan las grandes jugadas.';

  @override
  String get personaOracleDetail => 'Paciente. Lee antes de actuar.';

  @override
  String get personaSharkDetail =>
      'Mantiene la calma cuando la multitud se agita.';

  @override
  String personaPortrait(String name) {
    return 'Retrato del trader $name';
  }

  @override
  String get personaPickerTitle => 'Elige tu trader';

  @override
  String get personaPickerSubtitle => '¿Quién quieres ser?';

  @override
  String get personaPickerChoose => 'Elegir';

  @override
  String get personaPickerSaveError =>
      'No se pudo guardar tu elección. Inténtalo de nuevo.';

  @override
  String welcomeHeadline(String wallStreet) {
    return 'Empieza tu carrera en $wallStreet.';
  }

  @override
  String get welcomeHeroSemantics =>
      'Empieza tu carrera en Wall Street. Acciones tokenizadas giran alrededor de la invitación.';

  @override
  String get welcomeStartFirstDay => 'Empezar mi primer día';

  @override
  String get welcomeSignInOrCreate => 'Inicia sesión o regístrate';

  @override
  String get welcomeNoteSkip => 'Saltar introducción';

  @override
  String get welcomeNoteTitle => 'Te damos la bienvenida\nal piso.';

  @override
  String get welcomeNoteBody =>
      'Tu primer día empieza con práctica.\n\nElige una empresa. Es gratis.';

  @override
  String get chartPeriodDay => '1D';

  @override
  String get chartPeriodWeek => '1S';

  @override
  String get chartPeriodMonth => '1M';

  @override
  String get chartPeriodYear => '1A';

  @override
  String chartPriceLabel(String from, String to) {
    return 'Gráfico de precios. De $from a $to. Mantén presionado para explorar.';
  }

  @override
  String chartTradeBoughtSummary(String shares, String price, String date) {
    return 'Compra: $shares · $price · $date';
  }

  @override
  String chartTradeSoldSummary(String shares, String price, String date) {
    return 'Venta: $shares · $price · $date';
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
      other: 'Compraste $shares acciones a $price, $date',
      one: 'Compraste $shares acción a $price, $date',
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
      other: 'Vendiste $shares acciones a $price, $date',
      one: 'Vendiste $shares acción a $price, $date',
    );
    return '$_temp0';
  }

  @override
  String get chartTradeMarkerBuy => 'C';

  @override
  String get chartTradeMarkerSell => 'V';

  @override
  String get chartNoYear => 'Aún no hay un año de historial.';

  @override
  String get chartHistoryUnavailable =>
      'El historial de precios no está disponible. Inténtalo de nuevo.';

  @override
  String get chartStaleReading =>
      'Esta es una lectura anterior. Actualiza para ver un gráfico más reciente.';

  @override
  String get chartNotEnoughReadings =>
      'No hay suficientes lecturas para este período.';

  @override
  String get chartSevenDayLabel =>
      'Movimiento del precio de la empresa en siete días';

  @override
  String get chartSevenDayCaption =>
      'Movimiento de 7 días de la acción en bolsa';

  @override
  String get chartNoHistoryForVersion =>
      'El historial de precios aún no está disponible para esta versión.';

  @override
  String get chartReadingsNotComparable =>
      'Estas lecturas no se pueden comparar con confianza.';

  @override
  String chartReadingAt(String time) {
    return '$time UTC · Desde la primera lectura';
  }

  @override
  String chartRelativeHistoryLabel(String symbol) {
    return 'Historial relativo de $symbol';
  }

  @override
  String chartChangeAtTime(String change, String time) {
    return '$change el $time UTC';
  }

  @override
  String get chartGapsHint =>
      'Los huecos indican que el proveedor no dio lectura. Arrastra para explorar.';

  @override
  String get chartDragHint => 'Arrastra por el gráfico para explorar.';

  @override
  String get holdersLoadFailedTitle => 'No se pudieron cargar los titulares';

  @override
  String get holdersLoadFailedBody => 'Inténtalo de nuevo en un momento.';

  @override
  String get holdersEmpty => 'No hay titulares para mostrar';

  @override
  String get holdersColumnHolder => 'Titular';

  @override
  String get holdersColumnTokens => 'Tokens';

  @override
  String holdersSampleNote(String count) {
    return 'Saldos de las $count cuentas del token más grandes. No es la lista completa de titulares.';
  }

  @override
  String get marketTitle => 'Mercado';

  @override
  String get marketSubtitle => 'Acciones tokenizadas';

  @override
  String marketSortTooltip(String sort) {
    return 'Orden: $sort';
  }

  @override
  String get marketSortButtonLabel => 'Ordenar acciones';

  @override
  String get marketSearchButtonLabel => 'Buscar empresas';

  @override
  String get marketSortTitle => 'Ordenar acciones cargadas';

  @override
  String get marketSortFeatured => 'Destacadas';

  @override
  String get marketSortName => 'Nombre';

  @override
  String get marketSortBiggestGains => 'Mayores subidas';

  @override
  String get marketSortBiggestDrops => 'Mayores caídas';

  @override
  String get marketSortHighestPrice => 'Precio más alto';

  @override
  String get marketSortMostHeld => 'Con más titulares';

  @override
  String get marketListAll => 'Todas';

  @override
  String get marketListStarterPicks => 'Para empezar';

  @override
  String get marketListTrending => 'Tendencia';

  @override
  String get marketListMovers => 'En movimiento';

  @override
  String get marketListMostHeld => 'Con más titulares';

  @override
  String get marketListFollowing => 'Siguiendo';

  @override
  String get marketListNewOnChain => 'Nuevas on-chain';

  @override
  String get marketListTech => 'Tecnología';

  @override
  String get marketListFinance => 'Finanzas';

  @override
  String get marketListEnergy => 'Energía';

  @override
  String get marketListHealth => 'Salud';

  @override
  String get marketListConsumer => 'Consumo';

  @override
  String get marketListFunds => 'Fondos';

  @override
  String get marketListPreIpo => 'Pre-IPO';

  @override
  String get marketLoadingAll => 'Revisando todas las acciones…';

  @override
  String get marketEmptyFollowingTitle =>
      'Tu lista de seguimiento empieza aquí.';

  @override
  String get marketEmptyFollowingBody =>
      'Toca Seguir en una empresa para tenerla aquí.';

  @override
  String get marketEmptyFunds => 'Aún no hay fondos para mostrar.';

  @override
  String get marketEmptyPreIpo => 'Aún no hay empresas pre-IPO para mostrar.';

  @override
  String get marketEmptyStocks => 'Aún no hay acciones para mostrar.';

  @override
  String get marketEmptyBody => 'Prueba buscar una empresa.';

  @override
  String get marketFindCompany => 'Buscar una empresa';

  @override
  String get marketFollowingLoadFailed =>
      'Algunas acciones no cargaron. Reintentar';

  @override
  String get marketLoadingMore => 'Cargando más acciones';

  @override
  String get marketOffline => 'Estás sin conexión. Revisa tu internet.';

  @override
  String get marketListUnavailable =>
      'La lista del mercado no está disponible.';

  @override
  String marketFollowAdded(String name) {
    return 'Ahora sigues a $name.';
  }

  @override
  String marketFollowRemoved(String name) {
    return 'Dejaste de seguir a $name.';
  }

  @override
  String get marketFollowSignInNeeded =>
      'Inicia sesión para guardar tu lista de seguimiento.';

  @override
  String get marketFollowListFull =>
      'Tu lista de seguimiento está llena. Quita una empresa primero.';

  @override
  String get marketFollowUnchanged =>
      'No se pudo cambiar el seguimiento. Inténtalo de nuevo.';

  @override
  String get marketFollowButton => '+ Seguir';

  @override
  String get marketFollowingButton => 'Siguiendo';

  @override
  String get marketTradeable => 'Negociable';

  @override
  String get marketChangeUnavailable => 'Variación no disponible';

  @override
  String marketCardChange24h(String change) {
    return '$change  24 h';
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
      'yes': '$name, $symbol, $price, $change, negociable',
      'other': '$name, $symbol, $price, $change',
    });
    return '$_temp0';
  }

  @override
  String get marketChangeUnavailableSpoken => 'variación no disponible';

  @override
  String marketChangeSpoken(String direction, String change) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'down': 'Baja $change',
      'up': 'Sube $change',
      'other': 'Sin cambios $change',
    });
    return '$_temp0';
  }

  @override
  String marketCompanyLogoLabel(String name) {
    return 'Logo de $name';
  }

  @override
  String get marketPaperMarkLabel => 'dinero de práctica';

  @override
  String marketPaperAmountLabel(String amount) {
    return '$amount en dinero de práctica';
  }

  @override
  String get marketSearchHint => 'Nombre o símbolo';

  @override
  String get marketSearchClear => 'Borrar búsqueda';

  @override
  String get marketRecentTitle => 'Vistas recientemente';

  @override
  String get marketRecentClear => 'Borrar';

  @override
  String get marketRecentEmptyTitle => 'Encuentra tu próxima empresa';

  @override
  String get marketRecentEmptyBody =>
      'Tus búsquedas recientes aparecerán aquí.';

  @override
  String marketSearchNoResults(String query) {
    return 'No hay nada llamado “$query”. Prueba con el símbolo.';
  }

  @override
  String get marketSearchLoadingResult => 'Cargando empresa';

  @override
  String get marketSearchDidNotFinish =>
      'La búsqueda no terminó. Inténtalo de nuevo.';

  @override
  String get marketSearchStale =>
      'Estos resultados son antiguos. Busca de nuevo para ver una lista más reciente.';

  @override
  String get marketSearchOffline =>
      'Estás sin conexión. Revisa tu internet e inténtalo de nuevo.';

  @override
  String get marketSearchPaused => 'La búsqueda se pausó. Inténtalo de nuevo.';

  @override
  String get marketSearchRateLimited =>
      'Demasiadas búsquedas. Espera un momento e inténtalo de nuevo.';

  @override
  String get marketSearchTimeout =>
      'La búsqueda tardó demasiado. Inténtalo de nuevo.';

  @override
  String get marketSearchDisabled =>
      'La búsqueda de empresas no está disponible en esta versión.';

  @override
  String get marketSearchUnavailable =>
      'La búsqueda de empresas no está disponible. Inténtalo de nuevo.';

  @override
  String stockFollowTooltip(String name) {
    return 'Seguir a $name';
  }

  @override
  String stockUnfollowTooltip(String name) {
    return 'Dejar de seguir a $name';
  }

  @override
  String stockShareTooltip(String name) {
    return 'Compartir $name';
  }

  @override
  String get stockPositionTitle => 'Tu posición';

  @override
  String get stockPast24h => 'últimas 24 h';

  @override
  String get stockChartFailedTitle => 'El gráfico no cargó';

  @override
  String get stockChartEmptyTitle => 'Aún no hay gráfico';

  @override
  String get stockChartEmptyBody =>
      'Este token necesita más historial de precios.';

  @override
  String get stockPriceAlertTooltip => 'Crear una alerta de precio';

  @override
  String stockChartUpdatedAt(String time) {
    return 'Gráfico hasta $time';
  }

  @override
  String stockPositionShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares acciones',
      one: '$shares acción',
    );
    return '$_temp0';
  }

  @override
  String get stockPositionValue => 'Valor';

  @override
  String get stockPositionValueAtTrade => 'Valor al operar';

  @override
  String get stockPositionNotPriced => 'Sin precio';

  @override
  String get stockPositionAverageCost => 'Costo promedio';

  @override
  String get stockPositionReturn => 'Rendimiento';

  @override
  String get stockPositionReturnAtTrade => 'Rendimiento al operar';

  @override
  String get stockSectionsLabel => 'Detalles de la empresa';

  @override
  String get stockSectionAbout => 'Acerca de';

  @override
  String get stockSectionHolders => 'Titulares';

  @override
  String get stockSectionComments => 'Comentarios';

  @override
  String get stockAboutReadMore => 'Leer más';

  @override
  String get stockAboutReadLess => 'Leer menos';

  @override
  String get stockMetricVolume24h => 'Volumen 24 h';

  @override
  String get stockMetricLiquidity => 'Liquidez';

  @override
  String get stockMetricTokenMarketCap => 'Capitalización del token';

  @override
  String get stockMetricTokenHolders => 'Titulares del token';

  @override
  String get stockMetricCompanyMarketCap => 'Capitalización de la empresa';

  @override
  String get stockMetricSector => 'Sector';

  @override
  String get stockTokensTitle => 'Tokens disponibles';

  @override
  String stockCopyAddressTooltip(String symbol) {
    return 'Copiar la dirección de $symbol';
  }

  @override
  String get stockAddressCopied => 'Dirección copiada';

  @override
  String get stockAboutEmpty => 'Los detalles están en camino';

  @override
  String get stockPracticeInPaper => 'Probar en modo Práctica';

  @override
  String get stockVersionsLabel => 'Versiones del token';

  @override
  String stockVersionSelectedLabel(String version) {
    return 'Versión del token $version. Cambiar';
  }

  @override
  String stockVersionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versiones',
      one: '1 versión',
    );
    return '$_temp0';
  }

  @override
  String get stockVersionsTitle => 'Versiones';

  @override
  String get stockVersionNotTradeable => 'No disponible para operar.';

  @override
  String get reasonWriteTitle => 'Escribe tu motivo';

  @override
  String get reasonWriteSavedTitle => 'Motivo guardado';

  @override
  String get reasonWritePrompt => '¿Qué te hizo comprar?';

  @override
  String get reasonWriteHint => 'Tu opinión sobre esta acción…';

  @override
  String get reasonWriteSave => 'Guardar motivo';

  @override
  String get reasonWriteRetry => 'Reintentar';

  @override
  String get reasonWriteCloseRefresh => 'Cerrar y actualizar';

  @override
  String reasonWriteRewardTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get reasonWriteMissionRecorded => 'Misión registrada';

  @override
  String reasonWriteHeldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares acciones',
      one: '$shares acción',
    );
    return '$_temp0';
  }

  @override
  String get reasonWriteErrorInvalidInput =>
      'Usa una sola línea y 180 caracteres como máximo.';

  @override
  String get reasonWriteErrorOffline =>
      'Estás sin conexión. Tu motivo no se guardó. Inténtalo de nuevo.';

  @override
  String get reasonWriteErrorTimeout =>
      'Guardar tardó demasiado. Inténtalo de nuevo.';

  @override
  String get reasonWriteErrorAccount =>
      'Actualiza tu sesión antes de guardar este motivo.';

  @override
  String get reasonWriteErrorProfile =>
      'Termina de configurar tu perfil antes de guardar este motivo.';

  @override
  String get reasonWriteErrorOrderNotFound =>
      'No se encontró esta compra de práctica. Actualiza tu escritorio.';

  @override
  String get reasonWriteErrorBuyRequired =>
      'Solo puedes agregar un motivo a una compra de práctica confirmada.';

  @override
  String get reasonWriteErrorPositionRequired =>
      'Necesitas seguir teniendo esta acción para guardar un motivo.';

  @override
  String get reasonWriteErrorExists =>
      'Esta compra de práctica ya tiene un motivo. Actualiza tu Carrera.';

  @override
  String get reasonWriteErrorRetryMismatch =>
      'No se pudo vincular este reintento. Actualiza tu Carrera.';

  @override
  String get reasonWriteErrorRateLimited =>
      'Hay mucha actividad en los motivos ahora. Inténtalo de nuevo en un momento.';

  @override
  String get reasonWriteErrorGeneric =>
      'Tu motivo no se guardó. Inténtalo de nuevo.';

  @override
  String get reasonPrivacyTitle => 'Quién puede ver mis comentarios';

  @override
  String get reasonPrivacyNobody => 'Nadie';

  @override
  String get reasonPrivacyEveryone => 'Todos';

  @override
  String get reasonPrivacyFriends => 'Amigos';

  @override
  String reasonPrivacySavingChoice(String choice) {
    return 'Guardando “$choice”.';
  }

  @override
  String get reasonPrivacyLoading => 'Cargando tu elección.';

  @override
  String get reasonPrivacyNotAvailable => 'Tu elección aún no está disponible.';

  @override
  String reasonPrivacySavedStatus(String status) {
    return 'Guardado. $status';
  }

  @override
  String reasonPrivacyChangedElsewhere(String status) {
    return 'Cambió en otro dispositivo. Actualizado. $status';
  }

  @override
  String get reasonPrivacyNobodyLine => 'Solo tú puedes ver tus comentarios.';

  @override
  String get reasonPrivacyEveryoneLine =>
      'Cualquier persona en Trimmy puede verlos en la página de cada acción.';

  @override
  String get reasonPrivacyFriendsLine =>
      'Aún no disponible. No se comparte nada hasta que haya amigos.';

  @override
  String get reasonPrivacyFriendsAvailableLine =>
      'Solo tus amigos de Trimmy pueden verlos en la página de cada acción.';

  @override
  String get reasonPrivacyConsentLine =>
      'Tus comentarios y tu nombre de usuario aparecerán en la página de esa acción para cualquier persona en Trimmy. Los montos nunca se muestran.';

  @override
  String get reasonPrivacyNobodyOption =>
      'Solo tú. Es la opción predeterminada.';

  @override
  String get reasonPrivacyEveryoneOption =>
      'Cualquier persona en Trimmy, en la página de cada acción.';

  @override
  String reasonPrivacySheetNow(String choice) {
    return 'Ahora: $choice.';
  }

  @override
  String get reasonPrivacyGuestRecovery =>
      'Este escritorio de invitado necesita recuperarse.';

  @override
  String get reasonPrivacySessionRefresh =>
      'Tu sesión necesita actualizarse. Inténtalo de nuevo.';

  @override
  String get reasonPrivacyLoadOffline =>
      'Estás sin conexión. No se pudo cargar tu elección.';

  @override
  String get reasonPrivacyLoadTimeout =>
      'Tu elección tardó demasiado en cargar.';

  @override
  String get reasonPrivacyLoadSession =>
      'Tu sesión necesita actualizarse para poder cargar esto.';

  @override
  String get reasonPrivacyAccountClosed => 'Esta cuenta está cerrada.';

  @override
  String get reasonPrivacyLoadFailed => 'No se pudo cargar tu elección.';

  @override
  String get reasonPrivacySaveOffline =>
      'Estás sin conexión. Tu elección aún no se guardó.';

  @override
  String reasonPrivacySaveOfflineChoice(String choice) {
    return 'Estás sin conexión. La opción “$choice” aún no se guardó.';
  }

  @override
  String get reasonPrivacySaveTimeout =>
      'Guardar tardó demasiado. Tu elección aún no se guardó.';

  @override
  String reasonPrivacySaveTimeoutChoice(String choice) {
    return 'Guardar tardó demasiado. La opción “$choice” aún no se guardó.';
  }

  @override
  String get reasonPrivacySaveSession =>
      'Tu sesión necesita actualizarse. Tu elección aún no se guardó.';

  @override
  String reasonPrivacySaveSessionChoice(String choice) {
    return 'Tu sesión necesita actualizarse. La opción “$choice” aún no se guardó.';
  }

  @override
  String get reasonPrivacySaveAccountClosed =>
      'Esta cuenta está cerrada. No se guardó nada.';

  @override
  String get reasonPrivacySaveMismatch =>
      'No se pudo vincular ese guardado. Vuelve a elegir.';

  @override
  String get reasonPrivacySaveFailed =>
      'No se pudo guardar. Tu elección aún no se guardó.';

  @override
  String reasonPrivacySaveFailedChoice(String choice) {
    return 'No se pudo guardar. La opción “$choice” aún no se guardó.';
  }

  @override
  String get reasonPrivacyRateLimitedLoad =>
      'Demasiados cambios. Intenta cargar de nuevo en un momento.';

  @override
  String reasonPrivacyRateLimitedLoadSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other:
          'Demasiados cambios. Intenta cargar de nuevo en $seconds segundos.',
      one: 'Demasiados cambios. Intenta cargar de nuevo en $seconds segundo.',
    );
    return '$_temp0';
  }

  @override
  String get reasonPrivacyRateLimitedSave =>
      'Demasiados cambios. Intenta guardar de nuevo en un momento.';

  @override
  String reasonPrivacyRateLimitedSaveSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other:
          'Demasiados cambios. Intenta guardar de nuevo en $seconds segundos.',
      one: 'Demasiados cambios. Intenta guardar de nuevo en $seconds segundo.',
    );
    return '$_temp0';
  }

  @override
  String get reasonReportSheetTitle => '¿Por qué reportas este comentario?';

  @override
  String get reasonReportSheetBody =>
      'Elige el motivo que más se acerque. Quien lo escribió no verá quién lo reportó.';

  @override
  String get reasonReportConfirmTitle => '¿Reportar este motivo?';

  @override
  String reasonReportConfirmBody(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'spam':
          'Trimmy revisará el reporte de spam. El motivo saldrá de esta página cuando se reciba el reporte.',
      'harassment':
          'Trimmy revisará el reporte de acoso. El motivo saldrá de esta página cuando se reciba el reporte.',
      'impersonation':
          'Trimmy revisará el reporte de suplantación de identidad. El motivo saldrá de esta página cuando se reciba el reporte.',
      'unsafe':
          'Trimmy revisará el reporte de contenido peligroso. El motivo saldrá de esta página cuando se reciba el reporte.',
      'other':
          'Trimmy revisará el reporte. El motivo saldrá de esta página cuando se reciba el reporte.',
    });
    return '$_temp0';
  }

  @override
  String get reasonReportAction => 'Reportar';

  @override
  String get reasonBlockAction => 'Bloquear';

  @override
  String get reasonReportReceived => 'Reporte recibido.';

  @override
  String reasonBlockConfirmTitle(String handle) {
    return '¿Bloquear a @$handle?';
  }

  @override
  String get reasonBlockConfirmBody =>
      'Sus motivos saldrán de esta página. También se eliminarán la amistad y las invitaciones pendientes entre ustedes. Los motivos públicos se pueden seguir viendo desde otras cuentas.';

  @override
  String reasonBlockDone(String handle) {
    return 'Bloqueaste a @$handle.';
  }

  @override
  String get reasonSafetyErrorConflict =>
      'Esto cambió en otro dispositivo. Vuelve a elegir.';

  @override
  String get reasonSafetyErrorRateLimited =>
      'Demasiados cambios a la vez. Espera un momento e inténtalo de nuevo.';

  @override
  String get reasonSafetyErrorUnavailable =>
      'Esta acción no está disponible para tu cuenta en este momento.';

  @override
  String get reasonSafetyErrorUnconfirmed =>
      'No pudimos confirmar el resultado. Se volverá a intentar de forma segura.';

  @override
  String get reasonSafetyErrorGeneric =>
      'No se pudo completar esa acción. Inténtalo de nuevo.';

  @override
  String get reasonEmpty => 'Aún no hay comentarios';

  @override
  String get reasonEmptyFriends => 'Aún no hay comentarios de amigos';

  @override
  String get reasonOwnHistoryIncomplete =>
      'No se pudo cargar aquí tu historial completo de motivos.';

  @override
  String get reasonOwnStatusFailed =>
      'No se pudo verificar si tu motivo es privado.';

  @override
  String get reasonShowMore => 'Ver más';

  @override
  String get reasonLoadSessionRefresh =>
      'Tu sesión necesita actualizarse para cargar los comentarios.';

  @override
  String get reasonLoadOffline =>
      'Estás sin conexión. No se pudieron cargar los comentarios.';

  @override
  String get reasonLoadTimeout =>
      'Los comentarios tardaron demasiado en cargar.';

  @override
  String get reasonLoadRateLimited =>
      'Los comentarios se están actualizando demasiado rápido. Inténtalo de nuevo en un momento.';

  @override
  String get reasonLoadFailed => 'No se pudieron cargar los comentarios.';

  @override
  String get reasonAudienceSemantics => 'Elige de quién ver los comentarios';

  @override
  String get reasonAudienceEveryone => 'Todos';

  @override
  String get reasonAudienceFriends => 'Amigos';

  @override
  String get reasonYouBadge => 'Tú';

  @override
  String reasonSavedAt(String date, String time) {
    return 'Guardado el $date a las $time';
  }

  @override
  String get reasonPrivateLine => 'Tu comentario es privado.';

  @override
  String get reasonLoadingComments => 'Cargando comentarios';

  @override
  String get fastBuyTitle => 'Compra rápida';

  @override
  String get fastBuyClose => 'Cerrar compra rápida';

  @override
  String get fastBuySearchHint => 'Busca un nombre o símbolo';

  @override
  String get fastBuyOpenFailed =>
      'No se pudo abrir esta acción. Inténtalo de nuevo.';

  @override
  String get fastBuyConnectFailed => 'No se pudo conectar para operar.';

  @override
  String get fastBuyNoneAvailable =>
      'No hay acciones disponibles para comprar ahora.';

  @override
  String get fastBuyNoTradeableMatch =>
      'Ninguna acción que puedas comprar coincide.';

  @override
  String get fastBuyNoMatches => 'Aún no hay resultados.';

  @override
  String paperAmount(String amount) {
    return '$amount en dinero de práctica';
  }

  @override
  String paperOrderEquivalentPaper(String amount) {
    return '≈ $amount en dinero de práctica';
  }

  @override
  String paperOrderEquivalentShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $shares acciones',
      one: '≈ $shares acción',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderConversionAtReview => 'Verás la conversión al revisar';

  @override
  String paperOrderBuyTitle(String symbol) {
    return 'Comprar $symbol';
  }

  @override
  String paperOrderSellTitle(String symbol) {
    return 'Vender $symbol';
  }

  @override
  String get paperOrderReviewBuyTitle => 'Revisa tu compra';

  @override
  String get paperOrderReviewSellTitle => 'Revisa tu venta';

  @override
  String get paperOrderConfirmedTitle => 'Operación confirmada';

  @override
  String get paperOrderFirstTradeSwipeHint =>
      'Desliza hacia abajo para editar tu compra';

  @override
  String get paperOrderFirstTradeSkip => 'Omitir la primera operación';

  @override
  String get paperOrderFirstTradeReviewTitle => 'Revisa tu compra.';

  @override
  String get paperOrderSharesLabel => 'Acciones';

  @override
  String get paperOrderPricePerShare => 'Precio por acción';

  @override
  String get paperOrderFee => 'Comisión';

  @override
  String get paperOrderTotal => 'Total';

  @override
  String get paperOrderConfirmingBuy => 'Confirmando compra…';

  @override
  String get paperOrderCheckingPrice => 'Verificando precio…';

  @override
  String get paperOrderConfirmBuy => 'Confirmar compra';

  @override
  String get paperOrderConfirmSell => 'Confirmar venta';

  @override
  String paperOrderSharesValue(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares acciones',
      one: '$shares acción',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSharesAvailable(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares acciones disponibles',
      one: '$shares acción disponible',
    );
    return '$_temp0';
  }

  @override
  String paperOrderPaperAvailable(String amount) {
    return 'Disponible: $amount en dinero de práctica';
  }

  @override
  String paperOrderBuyingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vas a comprar $shares acciones',
      one: 'Vas a comprar $shares acción',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSellingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vas a vender $shares acciones',
      one: 'Vas a vender $shares acción',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYouPay => 'Pagas';

  @override
  String get paperOrderYouReceive => 'Recibes';

  @override
  String get paperOrderBuyConfirmed => 'Compra confirmada';

  @override
  String get paperOrderSaleConfirmed => 'Venta confirmada';

  @override
  String paperOrderOnYourDesk(String symbol) {
    return '$symbol ya está en tu escritorio.';
  }

  @override
  String paperOrderLeftYourDesk(String symbol) {
    return '$symbol salió de tu escritorio.';
  }

  @override
  String paperOrderPositionChanged(String symbol) {
    return 'Tu posición en $symbol cambió.';
  }

  @override
  String paperOrderBoughtShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Compraste $shares acciones',
      one: 'Compraste $shares acción',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSoldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vendiste $shares acciones',
      one: 'Vendiste $shares acción',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYourPosition => 'Tu posición';

  @override
  String get paperOrderPositionValue => 'Valor de la posición';

  @override
  String get paperOrderTrimsEarned => 'Trims ganados';

  @override
  String get paperOrderReasonLabel => '¿Por qué compraste?';

  @override
  String get paperOrderReasonHint => 'Una línea clara';

  @override
  String get paperOrderSaveReason => 'Guardar motivo';

  @override
  String get paperOrderRetryReason => 'Guardar otra vez';

  @override
  String paperOrderReasonTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get paperOrderReasonSaved => 'Motivo guardado';

  @override
  String paperOrderReasonQuote(String note) {
    return '“$note”';
  }

  @override
  String get paperOrderReasonUnavailable =>
      'Tu operación está confirmada. Ahora no se puede guardar un motivo.';

  @override
  String get paperOrderUnitLabel => 'Unidad del monto de la orden';

  @override
  String get paperOrderUnitPaper => 'Dinero';

  @override
  String get paperOrderUnitShares => 'Acciones';

  @override
  String get paperOrderKeyDelete => 'Borrar';

  @override
  String get paperOrderKeyDecimal => 'Separador decimal';

  @override
  String get paperOrderNoVersion =>
      'Esta empresa no tiene una versión disponible.';

  @override
  String get paperOrderReasonNotSaved =>
      'Operación confirmada. Tu motivo no se guardó. Inténtalo de nuevo.';

  @override
  String get paperOrderReasonNotSavedDone =>
      'La operación se hizo, pero el motivo no se guardó. Inténtalo de nuevo.';

  @override
  String get paperOrderReasonTooLong =>
      'Usa una sola línea y 180 caracteres como máximo.';

  @override
  String get paperOrderReasonOffline =>
      'Operación confirmada. Estás sin conexión, así que tu motivo no se guardó. Inténtalo de nuevo.';

  @override
  String get paperOrderReasonTimeout =>
      'Operación confirmada. Guardar el motivo tardó demasiado. Inténtalo de nuevo.';

  @override
  String get paperOrderReasonSessionExpired =>
      'Operación confirmada. Debes actualizar tu sesión antes de guardar el motivo.';

  @override
  String get paperOrderReasonProfileRequired =>
      'Operación confirmada. Termina de configurar tu perfil antes de guardar el motivo.';

  @override
  String get paperOrderReasonOrderNotFound =>
      'Operación confirmada. No encontramos esta orden. Actualiza tu escritorio.';

  @override
  String get paperOrderReasonBuyRequired =>
      'Solo puedes guardar un motivo después de una compra de práctica confirmada.';

  @override
  String get paperOrderReasonPositionRequired =>
      'Operación confirmada. Debes tener esta acción para guardar un motivo.';

  @override
  String get paperOrderReasonExists =>
      'Esta operación ya tiene un motivo guardado. Actualiza tu carrera.';

  @override
  String get paperOrderReasonRetryMismatch =>
      'Operación confirmada. No pudimos asociar este reintento. Actualiza tu carrera.';

  @override
  String get paperOrderReasonBusy =>
      'Operación confirmada. Hay muchos motivos guardándose ahora. Inténtalo en un momento.';

  @override
  String get paperOrderErrorInvalidAmount => 'Ingresa un monto mayor que cero.';

  @override
  String get paperOrderErrorInsufficientPaper =>
      'No tienes suficiente dinero de práctica para esta orden.';

  @override
  String get paperOrderErrorInsufficientShares =>
      'No tienes suficientes acciones para vender.';

  @override
  String get paperOrderErrorQuoteExpired =>
      'Ese precio venció. Consulta una nueva cotización.';

  @override
  String get paperOrderErrorPriceChanged =>
      'El precio cambió. Consulta la nueva cotización.';

  @override
  String get paperOrderErrorOffline =>
      'Estás sin conexión. Revisa tu internet e inténtalo de nuevo.';

  @override
  String get paperOrderErrorTimeout =>
      'Eso tardó demasiado. Inténtalo de nuevo.';

  @override
  String get paperOrderErrorAccountRequired =>
      'Guarda tu escritorio antes de hacer esta orden.';

  @override
  String get paperOrderErrorDuplicate =>
      'Esta orden ya se recibió. Actualiza tu escritorio.';

  @override
  String get paperOrderErrorRejected => 'La orden no fue aceptada.';

  @override
  String get paperOrderErrorUnavailable =>
      'La orden no se completó. Inténtalo de nuevo.';

  @override
  String get liveOrderErrorAddUsdc =>
      'Primero agrega USDC a tu billetera de Solana.';

  @override
  String get liveOrderErrorAddSol =>
      'Agrega SOL para cubrir las comisiones de red y de cuenta.';

  @override
  String get liveOrderErrorInsufficientHoldings =>
      'No tienes suficiente de este token para vender.';

  @override
  String get liveOrderErrorTradeLimit =>
      'Esta orden supera el límite actual por operación.';

  @override
  String get liveOrderErrorAppUpdate =>
      'Actualiza Trimmy para revisar los términos del emisor antes de operar.';

  @override
  String get liveOrderErrorTermsRequired =>
      'Confirma los términos del emisor para continuar.';

  @override
  String get liveOrderErrorWalletRequired =>
      'Crea tu billetera para continuar.';

  @override
  String get liveOrderErrorOrderPending =>
      'Tu operación anterior todavía se está confirmando.';

  @override
  String get liveOrderErrorQuoteExpired =>
      'Ese precio venció. Pide una nueva cotización.';

  @override
  String get liveOrderErrorBusy =>
      'Hay mucha demanda de cotizaciones. Intenta de nuevo en un momento.';

  @override
  String get liveOrderErrorNoRoute =>
      'No hay ruta para esta orden ahora. Prueba con otro monto.';

  @override
  String get liveOrderErrorMarketClosed =>
      'Esta acción se negocia mientras los mercados de EE. UU. están abiertos. Intenta de nuevo en ese horario.';

  @override
  String get liveOrderErrorBelowMinimum =>
      'Esta orden está por debajo del mínimo del creador de mercado. Prueba con un monto mayor.';

  @override
  String get liveOrderErrorPriceOffMarket =>
      'Ese precio está muy lejos del mercado ahora. Intenta de nuevo en un rato o con un monto menor.';

  @override
  String get liveOrderErrorFeeTooHigh =>
      'Las comisiones son demasiado altas para esta orden. Intenta más tarde.';

  @override
  String get liveOrderErrorAccountRequired =>
      'Inicia sesión de nuevo para usar tu billetera.';

  @override
  String get liveOrderErrorFreshQuote =>
      'Esta orden necesita una nueva cotización.';

  @override
  String get liveOrderErrorUnavailable =>
      'No se pudo conectar para operar. Intenta de nuevo.';

  @override
  String get liveOrderErrorGeneric =>
      'No se pudo completar este paso. Intenta de nuevo.';

  @override
  String get liveOrderConfirmTermsFirst =>
      'Primero confirma los términos del emisor.';

  @override
  String get liveOrderInvalidShares =>
      'Ingresa una cantidad de acciones válida.';

  @override
  String get liveOrderInvalidUsdc => 'Ingresa un monto válido en USDC.';

  @override
  String liveOrderUpToPerOrder(String amount) {
    return 'Hasta $amount por orden.';
  }

  @override
  String liveOrderMinimum(String amount) {
    return 'Las órdenes de este token empiezan en $amount.';
  }

  @override
  String liveOrderMarketNotice(String status) {
    return '$status.';
  }

  @override
  String get liveOrderQuoteFailed =>
      'No se pudo obtener una cotización verificada. Intenta de nuevo.';

  @override
  String get liveOrderCheckingResult =>
      'Revisando el resultado. Tu orden no se enviará dos veces.';

  @override
  String get liveOrderSigningFailed =>
      'La firma no terminó. No se envió ninguna orden.';

  @override
  String get liveOrderReconnecting => 'Reconectando para revisar tu orden…';

  @override
  String get liveOrderTermsOpenFailed =>
      'No se pudieron abrir los términos del emisor. Intenta de nuevo.';

  @override
  String get liveOrderTransactionOpenFailed =>
      'No se pudo abrir la transacción. Intenta de nuevo.';

  @override
  String get liveOrderTitleFallback => 'Operar';

  @override
  String get liveOrderAccountChangedTitle => 'Tu cuenta cambió';

  @override
  String get liveOrderAccountChangedBody =>
      'Inicia sesión y vuelve a abrir esta operación.';

  @override
  String get liveOrderCheckLastOrderTitle => 'Revisemos tu última orden';

  @override
  String get liveOrderConnectFailedTitle => 'No se pudo conectar para operar';

  @override
  String get liveOrderConnectedRetryBody =>
      'Intenta de nuevo cuando tengas conexión.';

  @override
  String get liveOrderPausedTitle => 'Las operaciones están en pausa por ahora';

  @override
  String get liveOrderPausedBody =>
      'Tu billetera y tus inversiones siguen aquí.';

  @override
  String get liveOrderNotTradableTitle =>
      'Este token aún no se puede operar aquí';

  @override
  String get liveOrderChooseAnother => 'Elige otra acción para operar.';

  @override
  String get liveOrderBackToStocks => 'Volver a acciones';

  @override
  String get liveOrderCheckingBalance => 'Revisando saldo…';

  @override
  String liveOrderAvailable(String amount) {
    return 'Disponible: $amount';
  }

  @override
  String liveOrderBuyTitle(String symbol) {
    return 'Comprar $symbol';
  }

  @override
  String liveOrderSellTitle(String symbol) {
    return 'Vender $symbol';
  }

  @override
  String get liveOrderBuyInstead => 'Cambiar a compra';

  @override
  String get liveOrderSellInstead => 'Cambiar a venta';

  @override
  String get liveOrderYouSell => 'Vendes';

  @override
  String get liveOrderYouPay => 'Pagas';

  @override
  String liveOrderLimit(String amount) {
    return 'Límite por orden: $amount';
  }

  @override
  String liveOrderLimitCappedMax(String amount) {
    return 'El máximo se ajustó al límite por orden de $amount.';
  }

  @override
  String liveOrderLimitCappedPercent(String percent, String amount) {
    return 'El $percent se ajustó al límite por orden de $amount.';
  }

  @override
  String get liveOrderCheckingPrice => 'Revisando precio y comisiones…';

  @override
  String get liveOrderReviewBuy => 'Revisar compra';

  @override
  String get liveOrderReviewSell => 'Revisar venta';

  @override
  String get liveOrderReviewBuyTitle => 'Revisa tu compra';

  @override
  String get liveOrderReviewSellTitle => 'Revisa tu venta';

  @override
  String get liveOrderYouReceive => 'Recibes ≈';

  @override
  String get liveOrderMinimumReceived => 'Mínimo a recibir';

  @override
  String get liveOrderNetworkFees => 'Comisiones de red y cuenta';

  @override
  String get liveOrderSwapFee => 'Comisión de intercambio';

  @override
  String get liveOrderPrice => 'Precio';

  @override
  String get liveOrderFixedQuote => 'Cotización fija de un creador de mercado';

  @override
  String get liveOrderIssuer => 'Emisor';

  @override
  String get liveOrderIssuerFee => 'Comisión del emisor';

  @override
  String get liveOrderConfirmBuy => 'Confirmar compra';

  @override
  String get liveOrderConfirmSell => 'Confirmar venta';

  @override
  String get liveOrderEditAmount => 'Editar monto';

  @override
  String get liveOrderTradeConfirmed => 'Operación confirmada';

  @override
  String get liveOrderConfirmingTrade => 'Confirmando tu operación';

  @override
  String get liveOrderQuoteExpired => 'Cotización vencida';

  @override
  String get liveOrderTradeIncomplete => 'La operación no se completó';

  @override
  String get liveOrderConfirmedBody => 'Tu orden está confirmada en Solana.';

  @override
  String get liveOrderPendingBody =>
      'Puedes cerrar esta pantalla. Vuelve a abrir la operación para ver su estado.';

  @override
  String get liveOrderExpiredBody => 'Pide un precio nuevo para continuar.';

  @override
  String get liveOrderFailedBody => 'Tu orden no se ejecutó.';

  @override
  String get liveOrderViewWalletActivity => 'Ver actividad de la billetera ↗';

  @override
  String get liveOrderViewTransaction => 'Ver transacción ↗';

  @override
  String get liveOrderGetFreshPrice => 'Pedir precio nuevo';

  @override
  String liveOrderIssuerExcluded(String regions) {
    return 'No disponible para residentes de: $regions';
  }

  @override
  String liveOrderIssuerFeeNote(String percent) {
    return 'Comisión del emisor: $percent en cada compra y venta';
  }

  @override
  String get liveOrderLegacyAttestation =>
      'Cumplo los requisitos según los términos del emisor.';

  @override
  String get liveOrderIssuerTerms => 'Términos del emisor ↗';

  @override
  String get liveHistoryStatusConfirming => 'Confirmando';

  @override
  String get liveHistoryStatusConfirmed => 'Confirmada';

  @override
  String get liveHistoryStatusFailed => 'No completada';

  @override
  String get liveHistoryStatusExpired => 'Vencida';

  @override
  String get liveHistoryErrorSignIn =>
      'Inicia sesión de nuevo para ver tus operaciones.';

  @override
  String get liveHistoryErrorLoad =>
      'No se pudieron cargar tus operaciones. Intenta de nuevo.';

  @override
  String get liveHistoryErrorLoadMore =>
      'No se pudieron cargar más operaciones. Intenta de nuevo.';

  @override
  String get liveHistoryErrorOpenStock =>
      'No se pudo abrir esta acción. Intenta de nuevo.';

  @override
  String get liveHistoryTitle => 'Tus operaciones';

  @override
  String get liveHistoryEmptyTitle => 'Tu primera operación empieza aquí';

  @override
  String get liveHistoryEmptyBody => 'Tus órdenes aparecerán aquí.';

  @override
  String get liveHistoryMore => 'Más operaciones';

  @override
  String liveHistoryRowBuy(String symbol) {
    return 'Compra de $symbol';
  }

  @override
  String liveHistoryRowSell(String symbol) {
    return 'Venta de $symbol';
  }

  @override
  String get liveHistoryYouPaid => 'Pagaste';

  @override
  String get liveHistoryYouSold => 'Vendiste';

  @override
  String get liveHistoryYouReceived => 'Recibiste';

  @override
  String get liveHistoryFinalAmounts =>
      'Montos finales de la transacción confirmada.';

  @override
  String get liveHistoryQuotedOutput => 'Monto cotizado';

  @override
  String get liveHistoryMinimumOutput => 'Monto mínimo';

  @override
  String get liveHistoryEstimates =>
      'Estimaciones de la orden. Mira la transacción para ver los montos finales.';

  @override
  String get liveHistoryViewTransaction => 'Ver transacción';

  @override
  String get liveHistoryOpenStock => 'Abrir acción';

  @override
  String get liveTradingOpenAlways => 'Abierto 24/7';

  @override
  String get liveTradingOpenWeekends =>
      'Abierto ahora, incluso los fines de semana';

  @override
  String get liveTradingOpenNow => 'Abierto ahora';

  @override
  String get liveTradingPausedByIssuer => 'Pausado por el emisor';

  @override
  String get liveTradingPausedByMarket => 'Pausado por el mercado';

  @override
  String liveTradingPausedResumes(String time) {
    return 'Pausado · se reanuda $time';
  }

  @override
  String get liveTradingShortPause => 'Pausa breve';

  @override
  String liveTradingShortPauseResumes(String time) {
    return 'Pausa breve · se reanuda $time';
  }

  @override
  String get liveTradingClosed => 'Cerrado';

  @override
  String liveTradingClosedOpens(String time) {
    return 'Cerrado · abre $time';
  }

  @override
  String get liveTradingHoursAroundClock =>
      'Se negocia a toda hora, con pausas breves entre las sesiones de EE. UU.';

  @override
  String get liveTradingHoursWeekdays =>
      'Se negocia las 24 horas, del domingo por la noche al viernes por la noche (hora del este de EE. UU.).';

  @override
  String get liveTradingHoursRegular =>
      'Se negocia solo en el horario del mercado de EE. UU., de 9:30 a. m. a 4 p. m. (hora del este), de lunes a viernes.';

  @override
  String get liveTradingHoursSessions =>
      'Se negocia solo durante las sesiones del mercado de EE. UU.';

  @override
  String liveTradingTimeToday(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'a las $clock',
      one: 'a la $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeTomorrow(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'mañana a las $clock',
      one: 'mañana a la $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeWeekday(int hour, String weekday, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'el $weekday a las $clock',
      one: 'el $weekday a la $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeDate(int hour, String date, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'el $date a las $clock',
      one: 'el $date a la $clock',
    );
    return '$_temp0';
  }

  @override
  String get liveTradingReasonIssuerNotOffered =>
      'Trimmy no ofrece este emisor.';

  @override
  String get liveTradingReasonNotYet =>
      'Aún no está disponible para operar en Trimmy.';

  @override
  String get liveTradingReasonIdentity =>
      'Trimmy no pudo confirmar quién emitió este token.';

  @override
  String get liveTradingReasonRestricted =>
      'El emisor tiene restricciones sobre este token que Trimmy no puede aceptar.';

  @override
  String get liveTradingReasonLowLiquidity =>
      'Se negocia muy poco para comprarlo y venderlo con seguridad.';

  @override
  String get liveTradingReasonNoRoute =>
      'Ninguna ruta de orden pasó los controles de seguridad de Trimmy.';

  @override
  String get liveTradingReasonPriceOff =>
      'Su precio está muy lejos del precio real de la acción.';

  @override
  String get liveTradingReasonHeldBack =>
      'En pausa mientras Trimmy revisa este token.';

  @override
  String get liveTradingReasonNotChecked => 'Aún no se revisó.';

  @override
  String liveTradingReasonClosedOpens(String time) {
    return 'Su mercado está cerrado. Abre $time y luego Trimmy lo revisa.';
  }

  @override
  String get liveTradingReasonUsHours =>
      'Solo se negocia mientras los mercados de EE. UU. están abiertos.';

  @override
  String get liveTradingReasonAwaitingReview =>
      'Su mercado está abierto. Trimmy lo está revisando antes de que puedas operar.';

  @override
  String get liveTradingReasonNoMarketMaker =>
      'Ningún creador de mercado lo está cotizando ahora.';

  @override
  String get liveTradingReasonUnavailable =>
      'No está disponible para operar en Trimmy.';

  @override
  String get liveTradingOtherIssuer => 'Otro emisor';

  @override
  String get holdingsCheckingWallet => 'Revisando tu billetera…';

  @override
  String get holdingsWalletStarts => 'Tu billetera empieza aquí';

  @override
  String get holdingsEmptyTitle => 'Aún no tienes acciones';

  @override
  String get holdingsEmptyBody => 'Tu primera acción empieza aquí.';

  @override
  String get holdingsExplore => 'Explorar acciones';

  @override
  String get walletFastBuy => 'Compra rápida';

  @override
  String get walletSend => 'Enviar';

  @override
  String get walletCashBalance => 'Saldo disponible';

  @override
  String get walletAccountBalance => 'Saldo de la cuenta';

  @override
  String get walletKnownValue => 'Valor conocido';

  @override
  String get walletSwitchToPaper => 'Cambiar al modo Práctica';

  @override
  String get walletSwitchToReal => 'Cambiar al modo de dinero real';

  @override
  String get walletUsdcAvailable => 'USDC disponible';

  @override
  String walletPositions(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText posiciones',
      one: '$countText posición',
    );
    return '$_temp0';
  }

  @override
  String get walletSomePricesUnavailable => 'Algunos precios no disponibles';

  @override
  String get walletPositionPricesUnavailable =>
      'Precios de posiciones no disponibles';

  @override
  String get walletCheckingSol => 'Revisando SOL…';

  @override
  String walletSolForFees(String amount) {
    return '$amount SOL para comisiones';
  }

  @override
  String get walletCashMarks => 'USDC y SOL';

  @override
  String get fundCreateWalletFailed =>
      'No se pudo crear tu billetera. Inténtalo de nuevo.';

  @override
  String get fundWalletUnconfirmed => 'No pudimos confirmar tu billetera.';

  @override
  String get fundWalletOffline =>
      'No tienes conexión. Vuelve a conectarte para cargar tu billetera.';

  @override
  String get fundWalletLoadFailed => 'No se pudo cargar tu billetera.';

  @override
  String get fundTabCash => 'Tarjeta';

  @override
  String get fundTabCrypto => 'Cripto';

  @override
  String get fundWalletMissingTitle => 'Una billetera para tu dinero';

  @override
  String get fundCreatingWallet => 'Creando…';

  @override
  String get fundCreateWallet => 'Crear billetera';

  @override
  String fundDepositQrLabel(String address) {
    return 'Dirección de depósito en Solana $address';
  }

  @override
  String get fundSendOnlyWarning =>
      'Envía solo USDC o SOL a esta cuenta en la red Solana.';

  @override
  String get fundAddressCopied => 'Copiado';

  @override
  String get fundCopyAddress => 'Copiar dirección';

  @override
  String get guestDeskStartAgainFailedExpired =>
      'No se pudo empezar de nuevo. Tu escritorio vencido sigue guardado.';

  @override
  String get guestDeskStartAgainFailed =>
      'No se pudo empezar de nuevo. Tu escritorio anterior sigue guardado.';

  @override
  String get guestDeskStartFreshTitle => '¿Empezar de cero?';

  @override
  String get guestDeskExpiredTitle => 'La sesión de invitado venció';

  @override
  String get guestDeskEndedTitle => 'La sesión de invitado terminó';

  @override
  String get guestDeskStartFreshMessage =>
      'Este teléfono perderá el acceso a tu escritorio anterior. No se puede deshacer.';

  @override
  String get guestDeskExpiredMessage =>
      'Tus registros de invitado se conservan. Este escritorio ya no puede operar ni guardarse en una cuenta.';

  @override
  String get guestDeskEndedMessage =>
      'Tus registros de invitado se conservan, pero este teléfono ya no puede abrir el escritorio.';

  @override
  String get guestDeskStartFreshDetail =>
      'Tu saldo, tus posiciones y tu historial no pasarán al escritorio nuevo.';

  @override
  String get guestDeskSignInDetail =>
      'Inicia sesión para abrir tu cuenta guardada. Tu escritorio de invitado queda intacto.';

  @override
  String get guestDeskOpening => 'Abriendo…';

  @override
  String get guestDeskStartNewConfirm => 'Empezar un escritorio nuevo';

  @override
  String get guestDeskKeep => 'Conservar este escritorio';

  @override
  String get guestDeskStartNewGuest => 'Empezar otro escritorio de invitado';

  @override
  String get guestDeskPreservedTitle => 'Hola de nuevo';

  @override
  String get guestDeskPreservedMessage =>
      'Tus operaciones guardadas y tu progreso están listos.';

  @override
  String get guestDeskPreservedExpiredDetail =>
      'Tu escritorio de invitado vencido se conserva aparte. Ya no puede operar ni combinarse.';

  @override
  String get guestDeskPreservedDetail =>
      'Tus operaciones de invitado quedan aparte. Cierra sesión para volver a ese escritorio.';

  @override
  String get guestDeskGoToDesk => 'Ir a mi escritorio';

  @override
  String get onrampErrorNotEnabled =>
      'Los depósitos con tarjeta aún no están disponibles. Puedes transferir desde otra billetera.';

  @override
  String get onrampErrorSignIn => 'Vuelve a iniciar sesión para continuar.';

  @override
  String get onrampErrorExpired =>
      'Este pago debe revisarse con soporte. El saldo de tu billetera se actualizará igual.';

  @override
  String get onrampErrorBusy => 'Espera un momento y vuelve a intentarlo.';

  @override
  String onrampErrorAmount(String min, String max) {
    return 'Escribe un monto de $min a $max.';
  }

  @override
  String get onrampErrorWalletChanged =>
      'Actualiza tu billetera antes de continuar.';

  @override
  String get onrampErrorUnavailable =>
      'No se pudo abrir el pago. Inténtalo de nuevo en un momento.';

  @override
  String get onrampErrorStep => 'Este paso no se completó. Inténtalo de nuevo.';

  @override
  String get onrampErrorEmail => 'Escribe un correo para tu comprobante.';

  @override
  String get onrampErrorRefresh =>
      'No se pudo actualizar este depósito. Revísalo otra vez antes de volver a pagar.';

  @override
  String get onrampTestDoneTitle => 'Depósito de prueba completado';

  @override
  String get onrampDoneTitle => 'Dinero agregado';

  @override
  String get onrampFailedTitle => 'El depósito necesita atención';

  @override
  String get onrampPendingTitle => 'Termina tu depósito';

  @override
  String get onrampTestDoneBody =>
      'Los USDC de prueba llegaron a Solana devnet.';

  @override
  String get onrampDoneBody => 'Tus USDC están en tu billetera.';

  @override
  String get onrampFailedBody =>
      'Contacta a Crossmint con este número de pedido. No vuelvas a pagar.';

  @override
  String get onrampPendingBody =>
      'Termina el pago en tu navegador y luego vuelve aquí.';

  @override
  String get onrampOpenPayment => 'Abrir pago';

  @override
  String onrampOrderId(String orderId) {
    return 'Pedido $orderId';
  }

  @override
  String get onrampCheckingOptions => 'Revisando opciones de pago…';

  @override
  String get onrampCardUnavailable =>
      'Los depósitos con tarjeta aún no están disponibles.';

  @override
  String get onrampTransferFromWallet => 'Transferir desde una billetera';

  @override
  String get onrampTestCheckout => 'Pago de prueba';

  @override
  String get onrampMethods => 'Tarjeta, Apple Pay o Google Pay';

  @override
  String get onrampMethodsNote => 'Las opciones disponibles aparecen al pagar.';

  @override
  String get onrampAmountLabel => 'Monto';

  @override
  String get onrampReceiptEmail => 'Correo para el comprobante';

  @override
  String get onrampUsdcNote =>
      'USDC en Solana. Las comisiones se muestran al pagar.';

  @override
  String get onrampConfirmWallet =>
      'Confirma que esta billetera es tuya. Solo firmas un mensaje, no un pago.';

  @override
  String get onrampVerificationMessage => 'Mensaje de verificación';

  @override
  String get onrampOneMoment => 'Un momento…';

  @override
  String get onrampVerifyContinue => 'Verificar y continuar';

  @override
  String get onrampPoweredByCrossmint => 'Con tecnología de Crossmint';

  @override
  String get signInTitleDeskAwaits => 'Tu escritorio te espera.';

  @override
  String get signInTitleTrimmy => 'Inicia sesión en Trimmy.';

  @override
  String get signInCaption => 'Inicia sesión o crea tu cuenta.';

  @override
  String get signInCaptionExpired =>
      'Abre el escritorio de tu cuenta. El escritorio de invitado vencido queda aparte.';

  @override
  String get signInNoticeExpired =>
      'Si cierras el inicio de sesión, el escritorio de invitado vencido se conserva.';

  @override
  String get signInErrorConnection =>
      'No pudimos conectar tu cuenta. Tu escritorio sigue aquí.';

  @override
  String get signInErrorConnectionExpired =>
      'No pudimos conectar tu cuenta. Tu escritorio anterior se conserva.';

  @override
  String get signInErrorUnfinished => 'No se completó. Inténtalo de nuevo.';

  @override
  String get signInClosed =>
      'Se cerró el inicio de sesión. Tu escritorio sigue aquí.';

  @override
  String get signInClosedExpired =>
      'Se cerró el inicio de sesión. Tu escritorio anterior se conserva.';

  @override
  String get signInErrorCode => 'Ese código no funcionó. Inténtalo de nuevo.';

  @override
  String get signInUnavailable =>
      'El inicio de sesión no está disponible en este momento.';

  @override
  String get signInErrorEmailInvalid =>
      'Escribe un correo electrónico completo.';

  @override
  String get signInErrorSendCode =>
      'No pudimos enviar el código. Inténtalo de nuevo.';

  @override
  String get signInErrorCodeMissing =>
      'Escribe el código que te enviamos por correo.';

  @override
  String get signInCloseTooltip => 'Cerrar inicio de sesión';

  @override
  String get signInUseDifferentEmail => 'Usar otro correo';

  @override
  String get signInTitleSaveDesk => 'Guarda tu escritorio.';

  @override
  String get signInTitleCheckEmail => 'Revisa tu correo.';

  @override
  String get signInTitleYourEmail => 'Tu correo.';

  @override
  String get signInExpiredDeskSeparate =>
      'El escritorio de invitado vencido queda aparte.';

  @override
  String get signInDeskStaysOnPhone =>
      'Tu escritorio se queda en este teléfono.';

  @override
  String signInCodeSentTo(String email) {
    return 'Enviamos un código a $email.';
  }

  @override
  String get signInWeWillSendCode =>
      'Te enviaremos un código para iniciar sesión.';

  @override
  String get signInNotSetUp =>
      'El inicio de sesión con cuenta no está configurado en esta versión. Tu escritorio se queda en este teléfono.';

  @override
  String get signInNotSetUpExpired =>
      'El inicio de sesión con cuenta no está configurado en esta versión. El escritorio de invitado vencido se conserva.';

  @override
  String get signInContinueAsGuest => 'Continuar en modo invitado';

  @override
  String get signInLater => 'Más tarde';

  @override
  String get signInCodeLabel => 'Código';

  @override
  String get signInEmailLabel => 'Correo electrónico';

  @override
  String get signInSendCode => 'Enviar código';

  @override
  String get signInWelcomeBackTitle => 'Hola de nuevo.';

  @override
  String get signInWelcomeBackCaption => 'Tu próxima jugada te espera.';

  @override
  String get signInOr => 'O';

  @override
  String get signInContinueWithEmail => 'Continuar con correo';

  @override
  String get signInBusyValue => 'En curso';

  @override
  String signInContinueWithProvider(String provider) {
    return 'Continuar con $provider';
  }

  @override
  String get careerWorldNextNeighbourhood => 'El próximo barrio';

  @override
  String get careerWorldMoreOnTheWay => 'Vienen más tareas.';

  @override
  String careerWorldLockedHint(int day) {
    return 'Completa el día $day para abrir esta jornada.';
  }

  @override
  String get careerWorldLoading => 'Abriendo tu semana…';

  @override
  String get careerWorldLoadFailed => 'No se pudieron cargar tus tareas.';

  @override
  String get careerWorldBeyondFirstMonth => 'Más allá del primer mes';

  @override
  String get careerWorldCityGrowing => 'La ciudad sigue creciendo';

  @override
  String get careerWorldStartHere => 'EMPIEZA AQUÍ';

  @override
  String get careerWorldContinue => 'CONTINUAR';

  @override
  String get careerWorldComingLater => 'Próximamente';

  @override
  String get careerWorldFiled => 'Entregado';

  @override
  String careerWorldDayFiled(int day) {
    return 'Día $day, entregado';
  }

  @override
  String careerWorldDayCurrent(int day) {
    return 'Día $day, tarea actual';
  }

  @override
  String careerWorldDayLocked(int day) {
    return 'Día $day, bloqueado';
  }

  @override
  String careerWorldDayComingLater(int day) {
    return 'Día $day, próximamente';
  }

  @override
  String get workdayEntryReload => 'Volver a cargar tu tarea';

  @override
  String workdayEntryEyebrow(int day, String speaker) {
    return 'DÍA $day · $speaker';
  }

  @override
  String get workdayEntryNext => 'Tu próxima tarea';

  @override
  String get workdayEntryContinue => 'Continúa tu tarea';

  @override
  String get deskActivityTitle => 'Tu actividad';

  @override
  String get deskActivityEmpty => 'Tu primera operación empieza la historia.';

  @override
  String deskActivityBought(String symbol) {
    return 'Compraste $symbol';
  }

  @override
  String deskActivitySold(String symbol) {
    return 'Vendiste $symbol';
  }

  @override
  String get deskCommunityTitle => 'Comunidad';

  @override
  String get deskCommunityPrompt => 'Mira lo que dicen los traders';

  @override
  String get deskCommunityLoadFailed => 'No se pudo cargar la comunidad';

  @override
  String get deskCommunityOpening => 'Abriendo la comunidad…';

  @override
  String get deskCommunityStart => 'Inicia una conversación';

  @override
  String get deskCommunitySubtitle => 'Comentarios públicos de otros traders.';

  @override
  String deskCommunityPostByHandle(String handle, String cashtag) {
    return '@$handle sobre $cashtag';
  }

  @override
  String deskCommunityPostByTrader(String cashtag) {
    return 'Un trader sobre $cashtag';
  }

  @override
  String get deskTitle => 'Tu escritorio';

  @override
  String get deskUpdatesTooltip => 'Novedades';

  @override
  String get deskOpenProfile => 'Abrir perfil';

  @override
  String deskPersonaPicture(String name) {
    return 'Foto de perfil de $name';
  }

  @override
  String deskStreakLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días de racha',
      one: 'día de racha',
    );
    return '$_temp0';
  }

  @override
  String get deskHoldingsTitle => 'Tus inversiones';

  @override
  String get deskExplore => 'Explorar';

  @override
  String deskShareCount(num count, String quantity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$quantity acciones',
      one: '$quantity acción',
    );
    return '$_temp0';
  }

  @override
  String get deskPickTraderTitle => 'Elige tu trader';

  @override
  String get deskPickTraderSubtitle => 'Haz tuyo este escritorio.';

  @override
  String get deskSaveTitle => 'Guarda tu escritorio';

  @override
  String get deskSaveSubtitle => 'Llévalo a tus otros dispositivos.';

  @override
  String get deskCareerFallback => 'Tu carrera';

  @override
  String get deskNextStepFallback => 'Mira tu próximo paso';

  @override
  String get deskEmptyTitle => 'Aún no tienes acciones';

  @override
  String get deskEmptyBody => 'Elige una empresa para empezar.';

  @override
  String get deskEmptyExplore => 'Explorar acciones';

  @override
  String get deskHoldingValueUnavailable => 'Valor no disponible';

  @override
  String clockWallStreetClosesIn(String duration) {
    return 'Aquí las acciones se negocian 24/7. Wall Street cierra en $duration.';
  }

  @override
  String clockWallStreetOpensIn(String duration) {
    return 'Aquí las acciones se negocian 24/7. Wall Street abre en $duration.';
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
      other: '$days d',
    );
    return '$_temp0';
  }

  @override
  String clockDurationDaysHours(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days d $hours h',
    );
    return '$_temp0';
  }

  @override
  String get workdayDraftSaved => 'Guardado';

  @override
  String get workdayDraftNotSaved => 'Aún no se guardó';

  @override
  String get workdayLeaveTitle => '¿Salir de esta nota?';

  @override
  String get workdayLeaveBody => 'Tus últimos cambios aún no se guardaron.';

  @override
  String get workdayLeaveKeepWriting => 'Seguir escribiendo';

  @override
  String get workdayLeaveWithoutSaving => 'Salir sin guardar';

  @override
  String get workdaySaveRetry => 'Aún no se pudo guardar. Inténtalo de nuevo.';

  @override
  String workdayDayTitle(int day) {
    return 'Día $day';
  }

  @override
  String get workdaySaveAndClose => 'Guardar y cerrar';

  @override
  String get workdayFiledTitle => 'Entregado.';

  @override
  String workdayTrimsEarned(int trims) {
    return '+$trims Trims';
  }

  @override
  String workdayNextDay(int day, String title) {
    return 'Día $day: $title';
  }

  @override
  String get workdayHintShow => '¿Una pista?';

  @override
  String get workdayHintHide => 'Ocultar pista';

  @override
  String get workdayFileHeading => 'Envía una actualización al equipo';

  @override
  String get workdayFileBody =>
      'Quédate con los dos datos que respalda la fuente.';

  @override
  String get workdayNoteHint => 'Agrega una nota (opcional)';

  @override
  String get workdayButtonBack => 'Volver a la calle';

  @override
  String get workdayButtonCheckEvidence => 'Revisar la evidencia';

  @override
  String get workdayButtonSendDecision => 'Enviar tu decisión';

  @override
  String get workdayButtonFile => 'Entregar actualización';

  @override
  String get workdayPinDetail => 'Fijar dato';

  @override
  String get workdayUnpinDetail => 'Desfijar dato';

  @override
  String get workdayOpensSoon => 'Abre pronto';

  @override
  String get workdayOpensTomorrow => 'Abre mañana';

  @override
  String workdayOpensOnWeekday(String weekday) {
    return 'Abre el $weekday';
  }

  @override
  String workdayOpensOnDate(String date) {
    return 'Abre el $date';
  }

  @override
  String get workdayErrorCheckEvidence =>
      'Revisa la fuente otra vez. Esos datos no respaldan esta actualización.';

  @override
  String get workdayErrorCheckDecision => 'Vuelve a mirar las cifras.';

  @override
  String get workdayErrorTomorrow =>
      'La tarea de hoy está lista. Tu próxima jornada empieza pronto.';

  @override
  String get workdayErrorClosed =>
      'Hoy la oficina está cerrada. Vuelve en la próxima jornada.';

  @override
  String get workdayErrorChanged =>
      'Tu trabajo cambió en otra pantalla. Ya lo actualizamos.';

  @override
  String get workdayErrorLocked => 'Primero entrega la tarea anterior.';

  @override
  String get workdayErrorSession =>
      'Tu cuenta cambió. Abre tu escritorio de nuevo.';

  @override
  String get workdayErrorSaveFailed =>
      'Aún no se pudo guardar. Tu trabajo sigue aquí. Inténtalo de nuevo.';

  @override
  String get careerMissionFirstPaperBuyTitle => 'Compra tu primera acción';

  @override
  String get careerMissionWriteAReasonTitle => 'Escribe tu motivo';

  @override
  String get careerMissionHoldThroughRedDayTitle => 'Aguanta un día en rojo';

  @override
  String get careerErrorOffline =>
      'Tu carrera está sin conexión. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get careerErrorTimeout =>
      'Tu carrera tardó demasiado en abrir. Inténtalo de nuevo.';

  @override
  String get careerErrorSession =>
      'Tu carrera necesita una nueva sesión. Inténtalo de nuevo.';

  @override
  String get careerErrorRateLimited =>
      'Tu carrera se está actualizando demasiado rápido. Inténtalo de nuevo en un momento.';

  @override
  String get careerErrorProfileRequired =>
      'Termina de configurar tu perfil de Trimmy y vuelve a intentarlo.';

  @override
  String get careerErrorUnavailable =>
      'Tu carrera no está disponible. Inténtalo de nuevo.';

  @override
  String careerStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Racha de $countText días',
      one: 'Racha de $countText día',
    );
    return '$_temp0';
  }

  @override
  String get careerStreakRetryActivity => 'Volver a cargar la actividad';

  @override
  String careerStreakDaySemantics(String date, String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'active': 'con actividad',
      'upcoming': 'por venir',
      'none': 'sin actividad',
      'unavailable': 'actividad no disponible',
      'other': 'actividad no disponible',
    });
    return '$date, $_temp0';
  }

  @override
  String get careerYourProgress => 'Tu progreso';

  @override
  String get careerPointsLabel => 'Puntos de carrera';

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
  String get communityTitle => 'Comunidad';

  @override
  String get communityUpdatesTitle => 'Novedades';

  @override
  String get communityScopeEveryone => 'Todos';

  @override
  String get communityScopeFollowing => 'Siguiendo';

  @override
  String get communityLoadFailed =>
      'No se pudo cargar la actividad. Inténtalo de nuevo.';

  @override
  String get communitySaveFailed =>
      'No se guardó ese cambio. Inténtalo de nuevo.';

  @override
  String get communityEmptyUpdatesTitle => 'Estás al día';

  @override
  String get communityEmptyUpdatesBody =>
      'Aquí aparecen los comentarios nuevos de las personas que sigues.';

  @override
  String get communityEmptyFollowingTitle => 'Tu gente, aquí';

  @override
  String get communityEmptyFollowingBody =>
      'Sigue a un trader desde la pestaña Todos.';

  @override
  String get communityEmptyEveryoneTitle =>
      'Aún no hay comentarios compartidos';

  @override
  String get communityEmptyEveryoneBody =>
      'Los comentarios públicos aparecerán aquí.';

  @override
  String get communityAnonymousTrader => 'Trader';

  @override
  String get communityFollowingButton => 'Siguiendo';

  @override
  String get communityFollowButton => '+ Seguir';

  @override
  String get communityCommentOptions => 'Opciones del comentario';

  @override
  String get communityMuteUpdates => 'Silenciar novedades';

  @override
  String get communityTurnOnUpdates => 'Activar novedades';

  @override
  String get communityReport => 'Denunciar';

  @override
  String get communityBlockTrader => 'Bloquear trader';

  @override
  String communityPostTime(String date, String time) {
    return '$date · $time';
  }

  @override
  String get communityLoadMore => 'Cargar más';

  @override
  String get floorTitle => 'Carrera';

  @override
  String get floorCloseProgress => 'Cerrar progreso';

  @override
  String get floorProgressButton => 'Progreso';

  @override
  String get floorCareerLoadFailed => 'No se pudo cargar tu carrera';

  @override
  String get floorBrowseStocks => 'Ver acciones';

  @override
  String get floorTrimsTooltip =>
      'Los Trims son puntos de carrera. Gánalos con actividades para subir de rango.';

  @override
  String get floorMilestonesTitle => 'Misiones de carrera';

  @override
  String get floorMilestonesActivities => 'Tus actividades';

  @override
  String floorMilestonesComplete(String complete, String total) {
    return '$complete de $total completadas';
  }

  @override
  String get floorMilestonesUpdating => 'Actualizando tu progreso…';

  @override
  String get floorActivitiesLoadFailed =>
      'No se pudieron cargar las actividades';

  @override
  String get floorMissionCommentTitle => 'Comenta tu operación';

  @override
  String get floorMissionStatusComplete => 'Completada';

  @override
  String get floorMissionStatusReady => 'Disponible';

  @override
  String get floorMissionStatusLocked => 'Bloqueada';

  @override
  String get floorMissionHoldHint =>
      'Conserva una acción durante un día a la baja.';

  @override
  String get floorMissionWriteComment => 'Escribe un comentario';

  @override
  String get floorMissionFindStock => 'Busca una acción';

  @override
  String floorMissionBecomeRank(String rank) {
    return 'Asciende a $rank';
  }

  @override
  String floorPromotionUnlocked(String rank) {
    return 'Rango desbloqueado: $rank';
  }

  @override
  String get floorRankHighestReached => 'Alcanzaste el rango más alto';

  @override
  String floorRankPromotionReady(String rank) {
    return 'Tu ascenso a $rank está listo';
  }

  @override
  String get floorRankThresholdReached =>
      'Ya tienes los Trims necesarios. Completa la misión de ascenso';

  @override
  String floorRankTrimsToNext(int count, String countText, String rank) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Faltan $countText Trims para $rank',
      one: 'Falta $countText Trim para $rank',
    );
    return '$_temp0';
  }

  @override
  String floorRankProgressSemantics(String percent, String status) {
    return 'Progreso de rango: $percent por ciento. $status';
  }

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileYourProfile => 'Tu perfil';

  @override
  String get profileGuestTitle => 'Hazlo tuyo';

  @override
  String get profileGuestBody =>
      'Inicia sesión para tener tus operaciones y tu carrera en un solo lugar.';

  @override
  String get profileProgressRefreshFailed =>
      'No se pudo actualizar el progreso.';

  @override
  String get profileLoadProgress => 'Cargar progreso';

  @override
  String get profileChooseTrader => 'Elige tu trader';

  @override
  String get profileYourTrader => 'Tu trader';

  @override
  String get profileChangeTrader => 'Cambiar tu trader';

  @override
  String profileStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText días',
      one: '$countText día',
    );
    return '$_temp0';
  }

  @override
  String get profileStreakLabel => 'Racha';

  @override
  String get socialReportCategorySpam => 'Spam';

  @override
  String get socialReportCategoryHarassment => 'Acoso';

  @override
  String get socialReportCategoryImpersonation => 'Suplantación de identidad';

  @override
  String get socialReportCategoryUnsafe => 'Contenido peligroso';

  @override
  String get socialReportCategoryOther => 'Otro motivo';

  @override
  String get infoHelpTitle => 'Ayuda';

  @override
  String get infoTermsTitle => 'Términos';

  @override
  String get infoPrivacyTitle => 'Privacidad';

  @override
  String get infoContactTitle => 'Habla con nosotros';

  @override
  String get infoContactBody =>
      'Busca @trimmyhq en X para pedir ayuda o darnos tu opinión.';

  @override
  String get infoLinkCopied => 'Enlace copiado';

  @override
  String get infoCopyContactLink => 'Copiar enlace de contacto';

  @override
  String get infoCopyWebsiteLink => 'Copiar enlace del sitio web';

  @override
  String infoLastUpdated(String date) {
    return 'Última actualización: $date';
  }

  @override
  String infoProviderPolicyLink(String provider, String url) {
    return '$provider: $url';
  }

  @override
  String get infoPracticeAndCareerTitle => 'Práctica y Carrera';

  @override
  String get infoPrivacyHeading => 'Privacidad, en palabras simples.';

  @override
  String get infoPrivacyIntro =>
      'Este aviso describe la información que manejan la app Trimmy y los servicios que la respaldan.';

  @override
  String get infoPrivacyAccountTitle => 'Tu cuenta o sesión de invitado';

  @override
  String get infoPrivacyAccountBody =>
      'El inicio de sesión usa Privy y el proveedor de correo o red social que elijas. Trimmy recibe identificadores de cuenta, credenciales de sesión y los datos disponibles de las cuentas vinculadas, como tu correo, tu nombre de usuario o tu foto de perfil, para autenticarte y recuperar tu progreso. Continuar como invitado crea una sesión aparte; la actividad como invitado también puede guardarse en nuestro servidor. Al iniciar sesión, ese progreso puede vincularse a tu cuenta.';

  @override
  String get infoPrivacyPracticeBody =>
      'Tus órdenes de práctica, saldos, respuestas a actividades, jornadas completadas, rachas, Trims, lista de seguimiento y perfil de trader se usan para el juego y para tu progreso. Las preferencias y los borradores de actividades sin terminar pueden guardarse en tu dispositivo; los registros de tu cuenta y de tu progreso también se guardan en nuestro servidor.';

  @override
  String get infoPrivacyCommentsTitle => 'Comentarios y seguimientos';

  @override
  String get infoPrivacyCommentsBody =>
      'Tu elección sobre compartir comentarios controla qué otros usuarios pueden ver tus comentarios junto con tu nombre de usuario, tu personaje de trader y el activo del que hablas. El feed de la comunidad no publica los montos de tus órdenes ni el saldo de tu billetera. Guardamos a quién sigues, tus preferencias para compartir, los bloqueos y las denuncias para ofrecer estas funciones y atender abusos. La actividad pública en la blockchain sigue siendo visible sin importar estos ajustes.';

  @override
  String get infoPrivacyWalletsTitle => 'Billeteras y operaciones reales';

  @override
  String get infoPrivacyWalletsBody =>
      'Privy proporciona la billetera integrada y la interfaz de firma. Trimmy usa tu dirección pública de Solana para consultar saldos, pedir cotizaciones y preparar las transacciones que revisas. Nuestro servidor recibe las transacciones firmadas para enviarlas y guarda las condiciones de la orden, las referencias de la transacción y su estado. Las direcciones de billetera, los montos de tokens y las firmas de las transacciones son públicos en la blockchain. Cerrar Trimmy no puede borrar esos registros.';

  @override
  String get infoPrivacyFundingTitle => 'Agregar dinero';

  @override
  String get infoPrivacyFundingBody =>
      'Cuando usas el pago de Crossmint, Trimmy comparte el correo, la billetera de destino, el monto solicitado y la prueba de titularidad de la billetera necesarios para preparar la orden. Crossmint maneja la información de pago y de verificación de identidad en su propio proceso de pago. Trimmy recibe el estado de la orden y de la entrega; nuestro servidor para agregar dinero no recopila números de tarjeta ni documentos de verificación.';

  @override
  String get infoPrivacyRemindersBody =>
      'Los recordatorios de Carrera se programan en tu dispositivo con tu permiso. Puedes cambiar tu preferencia de recordatorios en Trimmy o desactivar las notificaciones en la configuración del dispositivo. Los avisos de operaciones son opcionales en los dispositivos compatibles. Si los activas, guardamos un token de notificaciones del dispositivo y usamos Firebase Cloud Messaging para enviar un aviso breve cuando termina una orden real. No se incluyen montos ni saldos. Puedes desactivar los avisos de operaciones en Configuración. Las alertas sociales y de precio todavía no están disponibles.';

  @override
  String get infoPrivacyServicesTitle => 'Servicios y registros técnicos';

  @override
  String get infoPrivacyServicesBody =>
      'Proveedores de alojamiento y de bases de datos dan soporte a la app. Los servicios de datos de mercado reciben consultas sobre activos; Jupiter y los proveedores de blockchain reciben las consultas de billetera o de transacciones necesarias para operar con dinero real. Privy, tu proveedor de inicio de sesión y Crossmint manejan la información según sus propias políticas y pueden procesarla en otros países. La información de red, la hora de las solicitudes, los identificadores y los errores nos ayudan a prestar el servicio, limitar abusos e investigar fallas.';

  @override
  String get infoPrivacyChoicesTitle => 'Tus opciones y registros';

  @override
  String get infoPrivacyChoicesBody =>
      'Puedes cambiar tus preferencias para compartir y de recordatorios en Configuración. Cerrar sesión no elimina los registros del servidor. Cerrar una cuenta desactiva el acceso, pero no borra su historial, no elimina tu cuenta con el proveedor, no mueve activos ni quita datos de la blockchain. Borrar los datos de la app puede eliminar el progreso local y la información de acceso; antes de hacerlo, asegúrate de poder recuperar una billetera con fondos.';

  @override
  String get infoPrivacyRequestsBody =>
      'Escribe a @trimmyhq en X para consultar sobre el acceso, la corrección o la eliminación de la información que guarda Trimmy. Pide una conversación privada y no publiques credenciales ni documentos personales a la vista de todos. Es posible que necesitemos verificar la solicitud. Los registros de los proveedores siguen sus propias políticas; Trimmy no puede eliminar los registros de la blockchain.';

  @override
  String get infoPrivacyProvidersTitle =>
      'Políticas de privacidad de los proveedores';

  @override
  String get infoTermsHeading => 'Uso de Trimmy.';

  @override
  String get infoTermsIntro =>
      'Trimmy combina una simulación de trading con un modo de dinero real separado. Estos términos describen la app tal como funciona hoy. Las funciones siguen en desarrollo.';

  @override
  String get infoTermsPracticeBody =>
      'Los saldos y las órdenes de práctica son simulados. Los Trims, las rachas y los rangos de Carrera registran tu progreso en el juego; no se pueden retirar como dinero. La práctica puede usar datos de ejemplo o datos de referencia del mercado. Completar una actividad no demuestra que invertir sea adecuado para ti, y los comentarios de otros usuarios son sus propias opiniones. El contenido educativo no es asesoramiento personalizado de inversión, legal ni fiscal.';

  @override
  String get infoTermsRealMoneyTitle => 'Dinero real';

  @override
  String get infoTermsRealMoneyBody =>
      'El modo Real usa una billetera en la red principal (mainnet) de Solana y las acciones tokenizadas compatibles. Una orden puede mover activos reales cuando la revisas y la confirmas. Revisa el activo, el monto, las comisiones y el destino antes de aprobar. Una cotización es una estimación que puede vencer; una orden enviada o pendiente no es una operación confirmada. Por ahora, el historial muestra los montos de las cotizaciones revisadas, no un estado de cuenta completo de las ejecuciones finales, las comisiones ni las transferencias externas.';

  @override
  String get infoTermsTokenizedBody =>
      'Las acciones tokenizadas están sujetas a los términos de su emisor y no necesariamente dan los mismos derechos que tener directamente acciones de la empresa. Los precios pueden caer, la liquidez puede desaparecer y las fallas del emisor, de la red o de los proveedores pueden causar pérdidas. Trimmy no promete rendimientos ni la ejecución a un precio mostrado.';

  @override
  String get infoTermsFundingTitle => 'Agregar dinero a tu billetera';

  @override
  String get infoTermsFundingBody =>
      'Envía solo USDC o SOL compatibles a la dirección que se muestra, en la red Solana. Verifica la dirección y la red antes de enviar; Trimmy no puede simplemente deshacer una transferencia completada en la blockchain. También necesitas SOL para las comisiones de red. Por ahora, el pago con tarjeta de Crossmint es un entorno de prueba: sus fondos de prueba no sirven para operar en mainnet. Su disponibilidad fuera del entorno de prueba, los métodos de pago, la verificación y las comisiones dependen del proveedor.';

  @override
  String get infoTermsAccessTitle => 'Acceso a la cuenta';

  @override
  String get infoTermsAccessBody =>
      'Protege tu método de inicio de sesión y revisa con cuidado las solicitudes de la billetera. Nunca compartas una clave privada, una frase de recuperación ni un código de inicio de sesión de un solo uso con el equipo de soporte. Esta versión todavía no permite retiros ni exportar la billetera desde la app. Cerrar tu cuenta no retira tus activos. Resuelve el acceso a tu billetera antes de cerrar una cuenta o de eliminar la app de un dispositivo con fondos.';

  @override
  String get infoTermsEligibilityTitle => 'Elegibilidad y otros servicios';

  @override
  String get infoTermsEligibilityBody =>
      'Debes cumplir los requisitos aplicables de los emisores de activos y de los proveedores de servicios, incluidas las restricciones de ubicación y de elegibilidad. Ver un activo u obtener una cotización no significa que seas elegible. Privy, Crossmint, los proveedores de trading y los emisores de activos tienen sus propios términos. Trimmy no promete estar disponible en todos los países.';

  @override
  String get infoTermsCommunityTitle => 'Uso de la comunidad';

  @override
  String get infoTermsCommunityBody =>
      'Comparte comentarios que tengas derecho a publicar. No te hagas pasar por otras personas, no expongas información privada, no manipules el mercado, no acoses a otros usuarios ni interfieras con cuentas o servicios. Hay ajustes para compartir y herramientas para bloquear y denunciar en los comentarios y las interacciones de la comunidad.';

  @override
  String get infoTermsAvailabilityTitle => 'Disponibilidad y preguntas';

  @override
  String get infoTermsAvailabilityBody =>
      'Los datos de mercado, las cotizaciones, las notificaciones y la confirmación de la red pueden retrasarse o no estar disponibles. Las funciones y estos avisos pueden cambiar a medida que avanza el desarrollo. Nada de lo aquí indicado elimina derechos que no puedan excluirse según la ley aplicable. Escribe a @trimmyhq en X si necesitas ayuda o tienes preguntas sobre estos términos.';

  @override
  String get settingsReminders => 'Recordatorios';

  @override
  String get settingsAccountSection => 'Cuenta';

  @override
  String get settingsSignInDetail =>
      'Inicia sesión para conservar tu progreso.';

  @override
  String get settingsHandle => 'Nombre de usuario';

  @override
  String get settingsYourTrader => 'Tu trader';

  @override
  String get settingsChooseCharacter => 'Elige un personaje';

  @override
  String get settingsEmail => 'Correo electrónico';

  @override
  String get settingsSignInMethods => 'Métodos de inicio de sesión';

  @override
  String get settingsSignInMethodsUnavailable =>
      'Método de inicio de sesión no disponible.';

  @override
  String get settingsSignInMethodEmail => 'Correo';

  @override
  String get settingsSignOut => 'Cerrar sesión';

  @override
  String get settingsNotificationsSection => 'Notificaciones';

  @override
  String get settingsNotificationGroupMarket => 'Mercado';

  @override
  String get settingsNotificationGroupCareer => 'Carrera';

  @override
  String get settingsNotificationGroupSocial => 'Social';

  @override
  String get settingsNotificationGroupAccount => 'Cuenta';

  @override
  String get settingsNotificationOpen => 'Apertura de Wall Street';

  @override
  String get settingsNotificationOpenDetail => 'Cuando abre Wall Street.';

  @override
  String get settingsNotificationClose => 'Cierre de Wall Street';

  @override
  String get settingsNotificationCloseDetail => 'Cuando cierra Wall Street.';

  @override
  String get settingsNotificationEvents => 'Eventos de mis acciones';

  @override
  String get settingsNotificationEventsDetail =>
      'Novedades que afectan a las acciones que tienes.';

  @override
  String get settingsNotificationPrices => 'Alertas de precio';

  @override
  String settingsNotificationPricesDetail(String small, String large) {
    return 'Movimientos de $small o $large en las acciones que sigues.';
  }

  @override
  String get settingsNotificationStreak => 'Recordatorio de racha';

  @override
  String get settingsNotificationStreakDetail =>
      'Cuando tu racha está en riesgo.';

  @override
  String get settingsNotificationMissions => 'Misiones';

  @override
  String get settingsNotificationMissionsDetail =>
      'Nuevas misiones y tu avance.';

  @override
  String get settingsNotificationPromotions => 'Ascensos';

  @override
  String get settingsNotificationPromotionsDetail =>
      'Cuando alcanzas un nuevo rango.';

  @override
  String get settingsNotificationLeague => 'Liga';

  @override
  String get settingsNotificationLeagueDetail =>
      'Resultados de la liga y cambios de posición.';

  @override
  String get settingsNotificationFriends => 'Amigos';

  @override
  String get settingsNotificationFriendsDetail =>
      'Operaciones y motivos de tus amigos.';

  @override
  String get settingsNotificationTrades => 'Avisos de operaciones';

  @override
  String get settingsNotificationTradesDetail =>
      'Cuando termina una orden con dinero real.';

  @override
  String get settingsNotificationNews => 'Novedades de Trimmy';

  @override
  String get settingsNotificationNewsDetail => 'Noticias y mejoras de la app.';

  @override
  String get settingsNotAvailableYet => 'Todavía no está disponible.';

  @override
  String get settingsQuietHours => 'Horas de silencio';

  @override
  String settingsQuietHoursRange(String start, String end) {
    return 'De $start a $end';
  }

  @override
  String get settingsEditQuietHours => 'Editar horas de silencio';

  @override
  String get settingsPreferencesSection => 'Preferencias';

  @override
  String get settingsSound => 'Sonido';

  @override
  String get settingsSoundDetail => 'Sonidos para los momentos clave.';

  @override
  String get settingsHaptics => 'Vibración';

  @override
  String get settingsHapticsDetail => 'Pequeñas vibraciones al tocar.';

  @override
  String get settingsAnimations => 'Animaciones';

  @override
  String get settingsAnimationsLimited =>
      'Limitadas por la configuración de tu teléfono.';

  @override
  String get settingsAnimationsDetail => 'Movimiento y celebraciones.';

  @override
  String get settingsReduceMotion => 'Reducir movimiento';

  @override
  String get settingsReduceMotionOn =>
      'Activado. Sigue la configuración de tu teléfono.';

  @override
  String get settingsReduceMotionOff =>
      'Desactivado. Sigue la configuración de tu teléfono.';

  @override
  String get settingsPaperLimit => 'Límite de dinero de práctica';

  @override
  String get settingsResetPaper => 'Reiniciar práctica';

  @override
  String get settingsResetPaperBusy => 'Reiniciando tu escritorio de práctica.';

  @override
  String get settingsResetPaperPending =>
      'El reinicio que confirmaste todavía no termina.';

  @override
  String get settingsResetPaperDetail =>
      'Borra tus operaciones de práctica y empieza de nuevo.';

  @override
  String get settingsResetPaperTitle => '¿Reiniciar tu escritorio de práctica?';

  @override
  String get settingsResetPaperBody =>
      'Esto empieza un escritorio de práctica nuevo. Tus comprobantes anteriores se quedan en tu historial. Tu Carrera, tus Trims, tu rango, tu racha y tu dinero no cambian.';

  @override
  String get settingsResetPaperPhrase => 'reiniciar mi escritorio';

  @override
  String settingsResetPaperInstruction(String phrase) {
    return 'Escribe “$phrase” para continuar.';
  }

  @override
  String settingsResetPaperFieldLabel(String phrase) {
    return 'Frase de confirmación. Escribe $phrase.';
  }

  @override
  String get settingsResetPaperFieldTitle => 'Frase de confirmación';

  @override
  String get settingsResetPaperConfirm => 'Reiniciar escritorio';

  @override
  String get settingsResetPaperDoneTitle => 'Escritorio de práctica reiniciado';

  @override
  String settingsResetPaperDone(String amount) {
    return 'Tu escritorio está listo con $amount en dinero de práctica.';
  }

  @override
  String settingsResetPaperDoneNewer(String amount) {
    return 'Se conservaron las operaciones más recientes. Tu saldo es de $amount en dinero de práctica.';
  }

  @override
  String get settingsResetPaperFailed =>
      'Tu escritorio de práctica no se reinició. Inténtalo de nuevo.';

  @override
  String get settingsResetPaperStale =>
      'Tu escritorio de práctica cambió y se actualizó. Revísalo y vuelve a confirmar el reinicio.';

  @override
  String get settingsResetPaperNotNeeded =>
      'Tu escritorio de práctica ya está como nuevo. No se borró nada.';

  @override
  String get settingsResetPaperOffline =>
      'No tienes conexión. Tu solicitud de reinicio quedó guardada tal cual para reintentarla sin riesgo.';

  @override
  String get settingsResetPaperTimeout =>
      'El reinicio tardó demasiado en confirmarse. Tu solicitud quedó guardada tal cual para reintentarla sin riesgo.';

  @override
  String get settingsResetPaperAccountRequired =>
      'Tu escritorio de práctica necesita una sesión nueva para terminar el reinicio.';

  @override
  String get settingsResetPaperRateLimited =>
      'Los reinicios de práctica son limitados. Vuelve a intentar esta solicitud guardada más tarde.';

  @override
  String get settingsResetPaperUnavailable =>
      'No se pudo confirmar el reinicio. Tu solicitud quedó guardada tal cual para reintentarla sin riesgo.';

  @override
  String get settingsResetPaperRejected =>
      'Tu escritorio de práctica no se reinició. Actualiza tu escritorio e inténtalo de nuevo.';

  @override
  String get settingsMoneySection => 'Dinero';

  @override
  String get settingsMoneyCardOrCrypto => 'Tarjeta o cripto';

  @override
  String get settingsMoneyComingSoon =>
      'Operar con dinero real llegará más adelante.';

  @override
  String get settingsMoneyUnavailable =>
      'Las funciones de dinero no están disponibles para esta cuenta.';

  @override
  String get settingsCurrency => 'Moneda';

  @override
  String get settingsDepositPartner => 'Proveedor de depósitos';

  @override
  String get settingsFees => 'Comisiones';

  @override
  String get settingsCountryCheck => 'Verificación de país';

  @override
  String get settingsBankAccounts => 'Cuentas bancarias';

  @override
  String get settingsCards => 'Tarjetas';

  @override
  String get settingsWallet => 'Billetera';

  @override
  String get settingsWalletNoDetails =>
      'Todavía no hay detalles de la billetera.';

  @override
  String get settingsWalletComingSoon =>
      'Las herramientas de billetera llegarán más adelante.';

  @override
  String get settingsWalletUnavailable =>
      'Las herramientas de billetera no están disponibles para esta cuenta.';

  @override
  String get settingsCheckWallet => 'Ver billetera';

  @override
  String get settingsBackUpWallet => 'Respaldar billetera';

  @override
  String get settingsBackUpWalletDetail =>
      'Conserva el acceso fuera de Trimmy.';

  @override
  String get settingsPrivacySection => 'Privacidad';

  @override
  String get settingsHoldingsVisibility => 'Quién ve mis inversiones';

  @override
  String get settingsVisibilityFriends => 'Amigos';

  @override
  String get settingsVisibilityEveryone => 'Todos';

  @override
  String get settingsVisibilityNobody => 'Nadie';

  @override
  String get settingsDownloadData => 'Descargar mis datos';

  @override
  String get settingsSupportSection => 'Soporte';

  @override
  String get settingsSendFeedback => 'Enviar opinión';

  @override
  String get settingsReportBug => 'Reportar un error';

  @override
  String get settingsReportBugDetail => 'Se adjuntará la versión de tu app.';

  @override
  String get settingsLegalSection => 'Información legal';

  @override
  String get settingsRiskNotice => 'Aviso de riesgos';

  @override
  String get settingsAboutTokenizedStocks => 'Sobre las acciones tokenizadas';

  @override
  String get settingsAboutTokenizedStocksDetail => 'Qué son y qué no son.';

  @override
  String get settingsAccountClosureSection => 'Cierre de cuenta';

  @override
  String get settingsCloseAccount => 'Cerrar cuenta';

  @override
  String get settingsCloseAccountDetail =>
      'Revisa qué pasa con tus registros y tu billetera.';
}

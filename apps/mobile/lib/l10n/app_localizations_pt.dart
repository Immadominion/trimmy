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
  String get commonAddMoney => 'Adicionar dinheiro';

  @override
  String get commonSaving => 'Salvando…';

  @override
  String get commonChecking => 'Verificando…';

  @override
  String get commonConnecting => 'Conectando…';

  @override
  String get commonSending => 'Enviando…';

  @override
  String get commonConfirming => 'Confirmando…';

  @override
  String get commonLoading => 'Carregando…';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonRefresh => 'Atualizar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonNotNow => 'Agora não';

  @override
  String get commonSkip => 'Pular';

  @override
  String get commonHistory => 'Histórico';

  @override
  String get commonSettings => 'Configurações';

  @override
  String commonInProgress(String label) {
    return '$label em andamento';
  }

  @override
  String get modePaper => 'Treino';

  @override
  String get modeReal => 'Real';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguagePhone => 'Idioma do celular';

  @override
  String get settingsLanguagePhoneDetail =>
      'Usa o idioma configurado no seu celular.';

  @override
  String get appGuestChoiceNotSaved =>
      'Não foi possível salvar sua escolha. Tente de novo.';

  @override
  String get appDeskAlreadySaved => 'Sua mesa já está salva.';

  @override
  String get appDeskReconnecting =>
      'Sua mesa está reconectando. Tente de novo em instantes.';

  @override
  String get appSwitchedToPaper => 'Você mudou para o modo Treino.';

  @override
  String get appReasonBeingChecked =>
      'Estamos verificando o motivo que você salvou. Atualize sua carreira.';

  @override
  String get appReasonNeedsPaperDesk =>
      'Sua mesa de treino precisa estar on-line antes de você escrever este motivo.';

  @override
  String get appReasonNeedsPaperBuy =>
      'Esta missão precisa de uma compra de treino confirmada que você ainda tenha. Escolha uma ação quando quiser.';

  @override
  String get appPromotionRefreshFirst =>
      'Atualize sua carreira antes de resgatar esta promoção.';

  @override
  String get appPromotionNotPrepared =>
      'Não foi possível preparar sua promoção. Tente de novo.';

  @override
  String get appPromotionCareerChanged =>
      'Sua carreira mudou. Atualize e tente de novo.';

  @override
  String get appPaperDeskStillOpening =>
      'Sua mesa de treino ainda está abrindo. Tente de novo.';

  @override
  String get appFirstTradeStepNotSaved =>
      'Sua operação está segura, mas esta etapa não foi salva.';

  @override
  String get appStockCouldNotOpen =>
      'Não foi possível abrir esta ação. Tente de novo.';

  @override
  String get appHistoryCouldNotConnect =>
      'Não foi possível carregar o histórico. Tente de novo.';

  @override
  String get appReportNotSent =>
      'Não foi possível enviar a denúncia. Tente de novo.';

  @override
  String get appBlockFailed =>
      'Não foi possível bloquear este trader. Tente de novo.';

  @override
  String get appWalletAddressCopied => 'Endereço da carteira copiado.';

  @override
  String get appWalletBackupFailed =>
      'Não foi possível abrir o backup da carteira. Tente de novo.';

  @override
  String get appPaperDeskOpening => 'Abrindo sua mesa de treino.';

  @override
  String get appPaperDeskOffline =>
      'Sua mesa de treino está off-line. Verifique sua conexão e tente de novo.';

  @override
  String get appPaperDeskTimeout =>
      'Sua mesa de treino demorou demais para abrir. Tente de novo.';

  @override
  String get appPaperDeskSession =>
      'Sua mesa de treino precisa de uma nova sessão. Tente de novo.';

  @override
  String get appPaperDeskUnavailable =>
      'Sua mesa de treino não está disponível. Tente de novo.';

  @override
  String get appCareerStale =>
      'Mostrando seu último histórico de carreira confirmado. Atualize para ver o mais recente.';

  @override
  String get appMissionsMismatch =>
      'Sua carreira mudou enquanto as missões carregavam. Atualize para sincronizá-las.';

  @override
  String get appMissionsStale =>
      'Mostrando suas últimas missões confirmadas. Atualize para ver as mais recentes.';

  @override
  String get appMissionsOffline =>
      'Suas missões estão off-line. Verifique sua conexão e tente de novo.';

  @override
  String get appMissionsTimeout =>
      'Suas missões demoraram demais para abrir. Tente de novo.';

  @override
  String get appMissionsSession =>
      'Suas missões precisam de uma nova sessão. Tente de novo.';

  @override
  String get appMissionsRateLimited =>
      'Suas missões estão atualizando rápido demais. Tente de novo daqui a pouco.';

  @override
  String get appMissionsProfileRequired =>
      'Termine de configurar seu perfil do Trimmy e tente de novo.';

  @override
  String get appMissionsUnavailable =>
      'Suas missões não estão disponíveis. Tente de novo.';

  @override
  String get appProfileUnavailable =>
      'Seu perfil do Trimmy não está disponível. Tente de novo.';

  @override
  String get appAccountEntryFailed =>
      'Sua conta está conectada. Tente abrir sua mesa de novo.';

  @override
  String get appRealBalanceLabel => 'Saldo total';

  @override
  String get appRealBalanceUpdating => 'Atualizando saldo…';

  @override
  String get appRealBalanceUsdcAvailable => 'USDC disponível';

  @override
  String appRealBalanceSplit(String cash, String stocks) {
    return '$cash disponível · $stocks em ações';
  }

  @override
  String get appDeskStaleBoth =>
      'Mostrando sua última mesa de treino e seu histórico de carreira confirmados. As operações ficam pausadas até o Trimmy se reconectar.';

  @override
  String get appDeskStalePaper =>
      'Mostrando sua última mesa de treino confirmada. As operações ficam pausadas até o Trimmy se reconectar.';

  @override
  String get appTradingCouldNotConnect =>
      'Não foi possível conectar para operar.';

  @override
  String get appTradingChecking => 'Verificando operações…';

  @override
  String get appTradingPaused => 'As operações estão pausadas no momento.';

  @override
  String get appTradingNotTradeable =>
      'Ainda não é possível operar com dinheiro real.';

  @override
  String get appVersionIssuerUnavailable => 'Emissor indisponível';

  @override
  String get appVersionBackingUnavailable =>
      'Os detalhes do lastro não estão disponíveis nestes dados de mercado.';

  @override
  String get appVersionTradingHoursUnavailable =>
      'Negociado na blockchain. O horário do emissor não está disponível.';

  @override
  String get appRealMissionTitle => 'Uma missão de treino';

  @override
  String get appRealMissionBody => 'Faça isso na sua mesa de treino.';

  @override
  String get appRealMissionButton => 'Abrir mesa de treino';

  @override
  String get appCloseAccountTitle => 'Encerrar sua conta?';

  @override
  String get appCloseAccountBodyNoWallet =>
      'Você perderá o acesso à conta salva. Os registros que precisam ser mantidos continuam protegidos.';

  @override
  String get appCloseAccountBodyWallet =>
      'Garanta o acesso à sua carteira antes de encerrar sua conta. Encerrar a conta não move os fundos da carteira. Você perderá o acesso à sua mesa salva.';

  @override
  String get appCloseAccountBackUpWallet => 'Fazer backup da carteira';

  @override
  String get appCloseAccountConfirm => 'Encerrar conta';

  @override
  String get appFirstTradePrompt =>
      'Escolha uma empresa. Sua primeira operação é grátis.';

  @override
  String get appOpeningTrimmy => 'Abrindo o Trimmy';

  @override
  String get appCouldNotOpenTrimmy => 'Não foi possível abrir o Trimmy';

  @override
  String get appOpeningDesk => 'Abrindo sua mesa';

  @override
  String get appCouldNotOpenDesk => 'Não foi possível abrir sua mesa';

  @override
  String get appOpeningTrade => 'Abrindo sua operação';

  @override
  String get appCouldNotLoadTrade => 'Não foi possível carregar sua operação';

  @override
  String get appCouldNotLoadTradeBody =>
      'Tente de novo para ver sua ordem confirmada.';

  @override
  String get appSplashOpening => 'O Trimmy está abrindo';

  @override
  String get designCastSal => 'Sal, seu chefe no pregão';

  @override
  String get designCastWolf => 'Retrato do trader Wolf';

  @override
  String get designCastOracle => 'Retrato do trader Oracle';

  @override
  String get designCastShark => 'Retrato do trader Shark';

  @override
  String get designPaperMark => 'dinheiro de treino';

  @override
  String designPaperAmount(String amount) {
    return '$amount em dinheiro de treino';
  }

  @override
  String get designUseRealMoney => 'Usar dinheiro real';

  @override
  String get designDismissMessage => 'Fechar mensagem';

  @override
  String get designCompleted => 'Concluído';

  @override
  String appPromotionTitle(String rankId, String rank) {
    String _temp0 = intl.Intl.selectLogic(rankId, {
      'analyst': 'Agora você é $rank!',
      'other': 'Agora você é $rank!',
    });
    return '$_temp0';
  }

  @override
  String get appPromotionMessage => 'Um novo capítulo no pregão.';

  @override
  String get appPromotionFrom => 'Antes';

  @override
  String get appPromotionNewRank => 'Novo nível';

  @override
  String get appPromotionEarned => 'Ganhou';

  @override
  String appPromotionTrims(String trims) {
    return '$trims Trims';
  }

  @override
  String get appPromotionBackToCareer => 'Voltar para Carreira';

  @override
  String get appFirstPositionTitle => 'Sua primeira posição.';

  @override
  String get appFirstPositionMessage => 'Você fez sua primeira ordem!';

  @override
  String get appFirstPositionStock => 'Ação';

  @override
  String get appFirstPositionShares => 'Quantidade';

  @override
  String get appFirstPositionTime => 'Horário';

  @override
  String appFirstPositionTimeUtc(String time) {
    return '$time UTC';
  }

  @override
  String get appDayOneTitle => 'Dia 1, concluído.';

  @override
  String get appDayOneMessage => 'Até amanhã no pregão.';

  @override
  String get appSessionGuestRecovery =>
      'Esta mesa de convidado precisa ser recuperada.';

  @override
  String get appSessionAnswersNotSaved =>
      'Não foi possível salvar suas respostas. Tente mais uma vez.';

  @override
  String get appSessionStepNotSaved =>
      'Não foi possível salvar essa etapa. Tente de novo.';

  @override
  String get appSessionSetupUnreadable =>
      'Não foi possível abrir sua configuração do Trimmy. Comece de novo.';

  @override
  String get appSessionReadOffline =>
      'Seu perfil está off-line. Verifique sua conexão e tente de novo.';

  @override
  String get appSessionReadTimeout =>
      'Seu perfil demorou demais para abrir. Tente de novo.';

  @override
  String get appSessionReadSession =>
      'Seu perfil precisa de uma nova sessão. Tente de novo.';

  @override
  String get appSessionReadUnavailable =>
      'Seu perfil não está disponível. Tente de novo.';

  @override
  String get appSessionHandleTaken =>
      'Esse nome já está em uso. Escolha outro.';

  @override
  String get appSessionTradeRequired =>
      'Sua operação confirmada precisa chegar à sua mesa antes de seguir com esta etapa.';

  @override
  String get appSessionNotReady =>
      'O Trimmy ainda está confirmando esse momento. Tente de novo.';

  @override
  String get appSessionPrincipalChanged =>
      'A identidade da sua mesa mudou. Abra-a de novo e tente outra vez.';

  @override
  String get appSessionConflict =>
      'Seu perfil mudou em outro dispositivo. Tente de novo.';

  @override
  String get appSessionWriteOffline =>
      'Você está off-line. Reconecte e tente de novo.';

  @override
  String get appSessionWriteTimeout => 'Isso demorou demais. Tente de novo.';

  @override
  String get appSessionWriteSession =>
      'Sua sessão mudou. Abra seu perfil de novo.';

  @override
  String get appSessionWriteFailed =>
      'Essa etapa não foi salva. Tente de novo.';

  @override
  String get appMarketLoadMoreFailed =>
      'Não foi possível carregar mais ações. Tente de novo.';

  @override
  String get appMarketCatalogFailed =>
      'Não foi possível carregar as ações. Puxe para baixo para tentar de novo.';

  @override
  String get appMarketNoStarterPicks =>
      'As sugestões iniciais não estão disponíveis. Busque por empresa ou código.';

  @override
  String get appMarketNotConfigured =>
      'Os dados de mercado não estão configurados nesta versão.';

  @override
  String get appMarketBusy =>
      'Os dados de mercado estão sobrecarregados. Tente de novo em instantes.';

  @override
  String get appMarketTimeout =>
      'Os dados de mercado demoraram demais. Tente de novo.';

  @override
  String get appMarketOffline =>
      'Você está off-line. Verifique sua conexão e tente de novo.';

  @override
  String get appMarketUnavailable =>
      'Não foi possível carregar as ações. Tente de novo.';

  @override
  String get tabDesk => 'Mesa';

  @override
  String get tabMarket => 'Mercado';

  @override
  String get tabCareer => 'Carreira';

  @override
  String get tabProfile => 'Perfil';

  @override
  String get firstTradeSkip => 'Pular a primeira operação';

  @override
  String get firstTradeTitle => 'Sua primeira jogada.';

  @override
  String get firstTradeOpeningDesk => 'Abrindo sua mesa de treino…';

  @override
  String get firstTradeDeskUnavailable =>
      'Sua mesa de treino não está disponível. Tente de novo.';

  @override
  String get firstTradeContinueError =>
      'Não deu para continuar. Tente de novo.';

  @override
  String get firstTradePickCompany => 'Escolha uma empresa.';

  @override
  String get firstTradeHint => 'Dica';

  @override
  String get firstTradeCompanyGuide =>
      'Uma ação é um pedacinho de uma empresa. Escolha uma.';

  @override
  String get firstTradeAmountTitle => 'Escolha o valor';

  @override
  String get firstTradeAmountGuide => 'Escolha um valor para testar. É grátis.';

  @override
  String get firstTradeReviewBuy => 'Revisar compra';

  @override
  String get firstTradeOrderPlaced => 'Você fez sua primeira ordem!';

  @override
  String get firstTradeCreateProfile =>
      'Agora vamos criar seu perfil de trader.';

  @override
  String get firstTradeBuyConfirmed => 'Compra confirmada';

  @override
  String get firstTradeInvested => 'Investido';

  @override
  String firstTradeSharesLine(String shares) {
    return 'Ações  $shares';
  }

  @override
  String firstTradeTrimsEarned(String trims) {
    return '+$trims Trims';
  }

  @override
  String get firstTradeKeepFreeMoney => 'Continuar com dinheiro grátis';

  @override
  String get firstTradeKeepFreeMoneyDetail => 'Ganhe confiança na sua mesa.';

  @override
  String firstTradeSharesCount(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares ações',
      one: '$shares ação',
    );
    return '$_temp0';
  }

  @override
  String firstTradeFreeMoneyAmount(String amount) {
    return '$amount em dinheiro grátis';
  }

  @override
  String get firstTradeNextMove => 'Sua próxima jogada.';

  @override
  String get firstTradeNextMoveBody =>
      'Continue pegando o jeito ou adicione dinheiro à sua carteira.';

  @override
  String get firstTradeAddMoneyDetail => 'Veja suas opções de depósito.';

  @override
  String get firstTradeAddMoneyLater =>
      'Você pode adicionar dinheiro pela sua mesa quando quiser.';

  @override
  String get firstTradeContinueSafe =>
      'Sua operação está salva. Tente continuar de novo.';

  @override
  String get amountPickerErrorEmpty => 'Digite um valor.';

  @override
  String get amountPickerErrorDecimals => 'Use no máximo 2 casas decimais.';

  @override
  String amountPickerErrorMin(String amount) {
    return 'Escolha pelo menos $amount.';
  }

  @override
  String amountPickerErrorMax(String amount) {
    return 'Escolha no máximo $amount.';
  }

  @override
  String get amountPickerFieldLabel => 'Valor em dólares';

  @override
  String amountPickerEditSemantics(num value, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'Valor, $amount dólares. Editar valor',
      one: 'Valor, $amount dólar. Editar valor',
    );
    return '$_temp0';
  }

  @override
  String amountPickerDecreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Diminuir o valor em $amount dólares',
      one: 'Diminuir o valor em $amount dólar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerIncreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Aumentar o valor em $amount dólares',
      one: 'Aumentar o valor em $amount dólar',
    );
    return '$_temp0';
  }

  @override
  String amountPickerPresetSemantics(num amount, String amountText) {
    String _temp0 = intl.Intl.pluralLogic(
      amount,
      locale: localeName,
      other: 'Definir o valor em $amountText dólares',
      one: 'Definir o valor em $amountText dólar',
    );
    return '$_temp0';
  }

  @override
  String get onboardingGoalLearn => 'Aprender';

  @override
  String get onboardingGoalLearnDetail => 'Comece pelo básico.';

  @override
  String get onboardingGoalPractice => 'Praticar';

  @override
  String get onboardingGoalPracticeDetail =>
      'Tome decisões com dinheiro de treino.';

  @override
  String get onboardingGoalTrade => 'Operar com dinheiro de treino';

  @override
  String get onboardingGoalTradeDetail =>
      'Ganhe confiança com preços em tempo real.';

  @override
  String get onboardingGoalFriends => 'Amigos';

  @override
  String get onboardingGoalFriendsDetail =>
      'As ligas ainda não estão disponíveis.';

  @override
  String get onboardingKnowledgeNothing => 'Nada ainda';

  @override
  String get onboardingKnowledgeBasics => 'Sei o básico';

  @override
  String get onboardingKnowledgePractised => 'Já pratiquei';

  @override
  String get onboardingKnowledgeTraded => 'Já operei antes';

  @override
  String get onboardingKnowledgeDaily => 'Opero todo dia';

  @override
  String get onboardingDailyShowUp => 'Marcar presença';

  @override
  String get onboardingDailyShowUpDetail => 'Abra o Trimmy e confira sua mesa.';

  @override
  String get onboardingDailyOneMove => 'Uma jogada';

  @override
  String get onboardingDailyOneMoveDetail =>
      'Faça uma operação de treino bem pensada.';

  @override
  String get onboardingDailyThreeMoves => 'Três jogadas';

  @override
  String get onboardingDailyThreeMovesDetail =>
      'Faça três operações de treino bem pensadas.';

  @override
  String get onboardingSalHello =>
      'Cinco perguntas rápidas e depois sua primeira operação de treino.';

  @override
  String get onboardingQuestionGoal => 'Por que você está aqui?';

  @override
  String get onboardingQuestionKnowledge => 'Quanto você entende de bolsa?';

  @override
  String get onboardingQuestionPersona => 'Escolha seu trader.';

  @override
  String get onboardingQuestionDailyGoal => 'Escolha sua meta diária.';

  @override
  String get onboardingQuestionHandle => 'Como vão te chamar no pregão?';

  @override
  String get onboardingHandleLabel => 'Nome de usuário';

  @override
  String get onboardingHandleHelper => 'De 3 a 18 caracteres';

  @override
  String get onboardingHandleTooShort => 'Use pelo menos 3 caracteres.';

  @override
  String get onboardingHandleTooLong => 'Use no máximo 18 caracteres.';

  @override
  String get onboardingHandleStartWithLetter => 'Comece com uma letra.';

  @override
  String get onboardingHandleCharacters =>
      'Use letras, números ou sublinhados.';

  @override
  String get onboardingProgressLabel => 'Progresso da configuração inicial';

  @override
  String onboardingProgressValue(int percent) {
    return '$percent por cento';
  }

  @override
  String onboardingProgressStep(int step, int total) {
    return '$step de $total';
  }

  @override
  String onboardingSalSays(String text) {
    return 'Sal diz: $text';
  }

  @override
  String get onboardingNotificationsAsk =>
      'Eu te aviso quando Wall Street abrir e fechar. Aqui você pode operar a qualquer hora.';

  @override
  String get onboardingNotificationsSoon => 'Os alertas estão quase prontos.';

  @override
  String get onboardingNotificationsPhoneAsks =>
      'Agora o celular vai perguntar.';

  @override
  String get onboardingNotificationsKeepSettingUp =>
      'Continue configurando sua mesa.';

  @override
  String get onboardingNotificationsChangeLater =>
      'Você pode mudar os alertas quando quiser em Configurações.';

  @override
  String get onboardingNotificationsLater =>
      'Os alertas vão aparecer aqui quando o envio for ativado.';

  @override
  String get onboardingNotificationsSaving => 'Salvando sua configuração';

  @override
  String get onboardingNotificationsTurnOn => 'Ativar alertas';

  @override
  String get onboardingReviewAnswers => 'Revisar minhas respostas';

  @override
  String get onboardingOpeningMarket => 'Abrindo o mercado';

  @override
  String get onboardingSetupNotSaved =>
      'Sua configuração não foi salva. Tente de novo.';

  @override
  String get onboardingPermissionRequestFailed =>
      'O celular não abriu o pedido. Tente de novo.';

  @override
  String get onboardingSalPortrait => 'Sal, seu chefe no pregão';

  @override
  String get onboardingPermissionPreview =>
      'Prévia da permissão de notificações do celular';

  @override
  String get onboardingIntroSaveError =>
      'Não foi possível salvar esta etapa. Tente de novo.';

  @override
  String get onboardingIntroSaving => 'Salvando seu progresso';

  @override
  String get onboardingCouldNotSave =>
      'Não foi possível salvar. Tente de novo.';

  @override
  String get onboardingReminderSkip => 'Pular lembretes';

  @override
  String get onboardingReminderTitle => 'Que tal um lembrete?';

  @override
  String get onboardingReminderQuestion =>
      'Com que frequência você quer um lembrete?';

  @override
  String get onboardingReminderPermissionOff =>
      'As notificações estão desativadas. Você pode mudar isso nos ajustes do celular.';

  @override
  String get onboardingReminderUnavailable =>
      'Sua preferência foi salva. As notificações ainda não estão disponíveis nesta versão.';

  @override
  String get onboardingReminderNotSet =>
      'Não foi possível programar o lembrete. Tente de novo.';

  @override
  String get onboardingReminderChanged =>
      'Sua preferência mudou em outro dispositivo. Escolha de novo.';

  @override
  String get onboardingReminderSavedNotSet =>
      'Salvo neste celular. Não foi possível programar o lembrete. Tente de novo.';

  @override
  String get onboardingReminderSavedOffline =>
      'Salvo neste celular. A sincronização vai tentar de novo quando você estiver on-line.';

  @override
  String get personaWolfName => 'Wolf';

  @override
  String get personaOracleName => 'Oracle';

  @override
  String get personaSharkName => 'Shark';

  @override
  String get personaWolfDetail => 'Audaz. Veloz. Adora uma grande jogada.';

  @override
  String get personaOracleDetail => 'Paciente. Lê antes de agir.';

  @override
  String get personaSharkDetail => 'Mantém a calma quando a multidão se agita.';

  @override
  String personaPortrait(String name) {
    return 'Retrato do trader $name';
  }

  @override
  String get personaPickerTitle => 'Escolha seu trader';

  @override
  String get personaPickerSubtitle => 'Quem você quer ser?';

  @override
  String get personaPickerChoose => 'Escolher';

  @override
  String get personaPickerSaveError =>
      'Não foi possível salvar sua escolha. Tente de novo.';

  @override
  String welcomeHeadline(String wallStreet) {
    return 'Comece sua carreira em $wallStreet.';
  }

  @override
  String get welcomeHeroSemantics =>
      'Comece sua carreira em Wall Street. Ações tokenizadas giram em volta do convite.';

  @override
  String get welcomeStartFirstDay => 'Começar meu primeiro dia';

  @override
  String get welcomeSignInOrCreate => 'Entrar ou criar conta';

  @override
  String get welcomeNoteSkip => 'Pular introdução';

  @override
  String get welcomeNoteTitle => 'Boas-vindas\nao pregão.';

  @override
  String get welcomeNoteBody =>
      'Seu primeiro dia começa com um treino.\n\nEscolha uma empresa. É grátis.';

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
    return 'Gráfico de preços. De $from a $to. Toque e segure para explorar.';
  }

  @override
  String chartTradeBoughtSummary(String shares, String price, String date) {
    return 'Compra: $shares · $price · $date';
  }

  @override
  String chartTradeSoldSummary(String shares, String price, String date) {
    return 'Venda: $shares · $price · $date';
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
      other: 'Você comprou $shares ações por $price, $date',
      one: 'Você comprou $shares ação por $price, $date',
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
      other: 'Você vendeu $shares ações por $price, $date',
      one: 'Você vendeu $shares ação por $price, $date',
    );
    return '$_temp0';
  }

  @override
  String get chartTradeMarkerBuy => 'C';

  @override
  String get chartTradeMarkerSell => 'V';

  @override
  String get chartNoYear => 'Ainda não há um ano de histórico.';

  @override
  String get chartHistoryUnavailable =>
      'O histórico de preços está indisponível. Tente de novo.';

  @override
  String get chartStaleReading =>
      'Esta é uma leitura antiga. Atualize para ver um gráfico mais recente.';

  @override
  String get chartNotEnoughReadings =>
      'Não há leituras suficientes para este período.';

  @override
  String get chartSevenDayLabel => 'Movimento do preço da empresa em sete dias';

  @override
  String get chartSevenDayCaption => 'Movimento da ação na bolsa em 7 dias';

  @override
  String get chartNoHistoryForVersion =>
      'O histórico de preços ainda não está disponível para esta versão.';

  @override
  String get chartReadingsNotComparable =>
      'Essas leituras não podem ser comparadas com segurança.';

  @override
  String chartReadingAt(String time) {
    return '$time UTC · Desde a primeira leitura';
  }

  @override
  String chartRelativeHistoryLabel(String symbol) {
    return 'Histórico relativo de $symbol';
  }

  @override
  String chartChangeAtTime(String change, String time) {
    return '$change em $time UTC';
  }

  @override
  String get chartGapsHint =>
      'Lacunas indicam que o provedor não retornou leitura. Arraste para explorar.';

  @override
  String get chartDragHint => 'Arraste pelo gráfico para explorar.';

  @override
  String get holdersLoadFailedTitle =>
      'Não foi possível carregar os detentores';

  @override
  String get holdersLoadFailedBody => 'Tente de novo em instantes.';

  @override
  String get holdersEmpty => 'Nenhum detentor para mostrar';

  @override
  String get holdersColumnHolder => 'Detentor';

  @override
  String get holdersColumnTokens => 'Tokens';

  @override
  String holdersSampleNote(String count) {
    return 'Saldos das $count maiores contas do token. Não é a lista completa de detentores.';
  }

  @override
  String get marketTitle => 'Mercado';

  @override
  String get marketSubtitle => 'Ações tokenizadas';

  @override
  String marketSortTooltip(String sort) {
    return 'Ordem: $sort';
  }

  @override
  String get marketSortButtonLabel => 'Ordenar ações';

  @override
  String get marketSearchButtonLabel => 'Buscar empresas';

  @override
  String get marketSortTitle => 'Ordenar ações carregadas';

  @override
  String get marketSortFeatured => 'Destaques';

  @override
  String get marketSortName => 'Nome';

  @override
  String get marketSortBiggestGains => 'Maiores altas';

  @override
  String get marketSortBiggestDrops => 'Maiores quedas';

  @override
  String get marketSortHighestPrice => 'Maior preço';

  @override
  String get marketSortMostHeld => 'Com mais detentores';

  @override
  String get marketListAll => 'Todas';

  @override
  String get marketListStarterPicks => 'Para começar';

  @override
  String get marketListTrending => 'Em alta';

  @override
  String get marketListMovers => 'Em movimento';

  @override
  String get marketListMostHeld => 'Mais detidas';

  @override
  String get marketListFollowing => 'Seguindo';

  @override
  String get marketListNewOnChain => 'Novas on-chain';

  @override
  String get marketListTech => 'Tecnologia';

  @override
  String get marketListFinance => 'Finanças';

  @override
  String get marketListEnergy => 'Energia';

  @override
  String get marketListHealth => 'Saúde';

  @override
  String get marketListConsumer => 'Consumo';

  @override
  String get marketListFunds => 'Fundos';

  @override
  String get marketListPreIpo => 'Pré-IPO';

  @override
  String get marketLoadingAll => 'Verificando todas as ações…';

  @override
  String get marketEmptyFollowingTitle =>
      'Sua lista de acompanhamento começa aqui.';

  @override
  String get marketEmptyFollowingBody =>
      'Toque em Seguir em uma empresa para mantê-la aqui.';

  @override
  String get marketEmptyFunds => 'Ainda não há fundos para mostrar.';

  @override
  String get marketEmptyPreIpo => 'Ainda não há empresas pré-IPO para mostrar.';

  @override
  String get marketEmptyStocks => 'Ainda não há ações para mostrar.';

  @override
  String get marketEmptyBody => 'Tente buscar uma empresa.';

  @override
  String get marketFindCompany => 'Buscar uma empresa';

  @override
  String get marketFollowingLoadFailed =>
      'Algumas ações não carregaram. Tentar de novo';

  @override
  String get marketLoadingMore => 'Carregando mais ações';

  @override
  String get marketOffline => 'Você está offline. Verifique sua conexão.';

  @override
  String get marketListUnavailable => 'A lista do mercado não está disponível.';

  @override
  String marketFollowAdded(String name) {
    return 'Agora você segue $name.';
  }

  @override
  String marketFollowRemoved(String name) {
    return 'Você deixou de seguir $name.';
  }

  @override
  String get marketFollowSignInNeeded =>
      'Entre para salvar sua lista de acompanhamento.';

  @override
  String get marketFollowListFull =>
      'Sua lista de acompanhamento está cheia. Remova uma empresa primeiro.';

  @override
  String get marketFollowUnchanged =>
      'Não foi possível mudar o acompanhamento. Tente de novo.';

  @override
  String get marketFollowButton => '+ Seguir';

  @override
  String get marketFollowingButton => 'Seguindo';

  @override
  String get marketTradeable => 'Negociável';

  @override
  String get marketChangeUnavailable => 'Variação indisponível';

  @override
  String marketCardChange24h(String change) {
    return '$change  24h';
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
      'yes': '$name, $symbol, $price, $change, negociável',
      'other': '$name, $symbol, $price, $change',
    });
    return '$_temp0';
  }

  @override
  String get marketChangeUnavailableSpoken => 'variação indisponível';

  @override
  String marketChangeSpoken(String direction, String change) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'down': 'Queda de $change',
      'up': 'Alta de $change',
      'other': 'Estável $change',
    });
    return '$_temp0';
  }

  @override
  String marketCompanyLogoLabel(String name) {
    return 'Logotipo de $name';
  }

  @override
  String get marketPaperMarkLabel => 'dinheiro de treino';

  @override
  String marketPaperAmountLabel(String amount) {
    return '$amount em dinheiro de treino';
  }

  @override
  String get marketSearchHint => 'Nome ou símbolo';

  @override
  String get marketSearchClear => 'Limpar busca';

  @override
  String get marketRecentTitle => 'Vistas recentemente';

  @override
  String get marketRecentClear => 'Limpar';

  @override
  String get marketRecentEmptyTitle => 'Encontre sua próxima empresa';

  @override
  String get marketRecentEmptyBody => 'Suas buscas recentes vão aparecer aqui.';

  @override
  String marketSearchNoResults(String query) {
    return 'Nada chamado “$query”. Tente o símbolo.';
  }

  @override
  String get marketSearchLoadingResult => 'Carregando empresa';

  @override
  String get marketSearchDidNotFinish => 'A busca não terminou. Tente de novo.';

  @override
  String get marketSearchStale =>
      'Estes resultados são antigos. Busque de novo para ver uma lista mais recente.';

  @override
  String get marketSearchOffline =>
      'Você está offline. Verifique sua conexão e tente de novo.';

  @override
  String get marketSearchPaused => 'A busca foi pausada. Tente de novo.';

  @override
  String get marketSearchRateLimited =>
      'Muitas buscas. Espere um pouco e tente de novo.';

  @override
  String get marketSearchTimeout => 'A busca demorou demais. Tente de novo.';

  @override
  String get marketSearchDisabled =>
      'A busca de empresas não está disponível nesta versão.';

  @override
  String get marketSearchUnavailable =>
      'A busca de empresas está indisponível. Tente de novo.';

  @override
  String stockFollowTooltip(String name) {
    return 'Seguir $name';
  }

  @override
  String stockUnfollowTooltip(String name) {
    return 'Deixar de seguir $name';
  }

  @override
  String stockShareTooltip(String name) {
    return 'Compartilhar $name';
  }

  @override
  String get stockPositionTitle => 'Sua posição';

  @override
  String get stockPast24h => 'últimas 24h';

  @override
  String get stockChartFailedTitle => 'O gráfico não carregou';

  @override
  String get stockChartEmptyTitle => 'Ainda não há gráfico';

  @override
  String get stockChartEmptyBody =>
      'Este token precisa de mais histórico de preços.';

  @override
  String get stockPriceAlertTooltip => 'Criar um alerta de preço';

  @override
  String stockChartUpdatedAt(String time) {
    return 'Gráfico até $time';
  }

  @override
  String stockPositionShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares ações',
      one: '$shares ação',
    );
    return '$_temp0';
  }

  @override
  String get stockPositionValue => 'Valor';

  @override
  String get stockPositionValueAtTrade => 'Valor na operação';

  @override
  String get stockPositionNotPriced => 'Sem preço';

  @override
  String get stockPositionAverageCost => 'Custo médio';

  @override
  String get stockPositionReturn => 'Retorno';

  @override
  String get stockPositionReturnAtTrade => 'Retorno na operação';

  @override
  String get stockSectionsLabel => 'Detalhes da empresa';

  @override
  String get stockSectionAbout => 'Sobre';

  @override
  String get stockSectionHolders => 'Detentores';

  @override
  String get stockSectionComments => 'Comentários';

  @override
  String get stockAboutReadMore => 'Ler mais';

  @override
  String get stockAboutReadLess => 'Ler menos';

  @override
  String get stockMetricVolume24h => 'Volume 24h';

  @override
  String get stockMetricLiquidity => 'Liquidez';

  @override
  String get stockMetricTokenMarketCap => 'Valor de mercado do token';

  @override
  String get stockMetricTokenHolders => 'Detentores do token';

  @override
  String get stockMetricCompanyMarketCap => 'Valor de mercado da empresa';

  @override
  String get stockMetricSector => 'Setor';

  @override
  String get stockTokensTitle => 'Tokens disponíveis';

  @override
  String stockCopyAddressTooltip(String symbol) {
    return 'Copiar o endereço de $symbol';
  }

  @override
  String get stockAddressCopied => 'Endereço copiado';

  @override
  String get stockAboutEmpty => 'Os detalhes estão a caminho';

  @override
  String get stockPracticeInPaper => 'Testar no modo Treino';

  @override
  String get stockVersionsLabel => 'Versões do token';

  @override
  String stockVersionSelectedLabel(String version) {
    return 'Versão do token $version. Alterar';
  }

  @override
  String stockVersionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versões',
      one: '1 versão',
    );
    return '$_temp0';
  }

  @override
  String get stockVersionsTitle => 'Versões';

  @override
  String get stockVersionNotTradeable => 'Indisponível para operar.';

  @override
  String get reasonWriteTitle => 'Escreva seu motivo';

  @override
  String get reasonWriteSavedTitle => 'Motivo salvo';

  @override
  String get reasonWritePrompt => 'O que fez você comprar?';

  @override
  String get reasonWriteHint => 'Sua opinião sobre esta ação…';

  @override
  String get reasonWriteSave => 'Salvar motivo';

  @override
  String get reasonWriteRetry => 'Tentar de novo';

  @override
  String get reasonWriteCloseRefresh => 'Fechar e atualizar';

  @override
  String reasonWriteRewardTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get reasonWriteMissionRecorded => 'Missão registrada';

  @override
  String reasonWriteHeldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares ações',
      one: '$shares ação',
    );
    return '$_temp0';
  }

  @override
  String get reasonWriteErrorInvalidInput =>
      'Use uma só linha e no máximo 180 caracteres.';

  @override
  String get reasonWriteErrorOffline =>
      'Você está sem conexão. Seu motivo não foi salvo. Tente de novo.';

  @override
  String get reasonWriteErrorTimeout => 'Salvar demorou demais. Tente de novo.';

  @override
  String get reasonWriteErrorAccount =>
      'Atualize sua sessão antes de salvar este motivo.';

  @override
  String get reasonWriteErrorProfile =>
      'Termine de configurar seu perfil antes de salvar este motivo.';

  @override
  String get reasonWriteErrorOrderNotFound =>
      'Esta compra de treino não foi encontrada. Atualize sua mesa.';

  @override
  String get reasonWriteErrorBuyRequired =>
      'Só é possível adicionar um motivo a uma compra de treino confirmada.';

  @override
  String get reasonWriteErrorPositionRequired =>
      'Você precisa ainda ter esta ação para salvar um motivo.';

  @override
  String get reasonWriteErrorExists =>
      'Esta compra de treino já tem um motivo. Atualize sua Carreira.';

  @override
  String get reasonWriteErrorRetryMismatch =>
      'Não foi possível associar esta nova tentativa. Atualize sua Carreira.';

  @override
  String get reasonWriteErrorRateLimited =>
      'Os motivos estão sobrecarregados agora. Tente de novo daqui a pouco.';

  @override
  String get reasonWriteErrorGeneric =>
      'Seu motivo não foi salvo. Tente de novo.';

  @override
  String get reasonPrivacyTitle => 'Quem pode ver meus comentários';

  @override
  String get reasonPrivacyNobody => 'Ninguém';

  @override
  String get reasonPrivacyEveryone => 'Todos';

  @override
  String get reasonPrivacyFriends => 'Amigos';

  @override
  String reasonPrivacySavingChoice(String choice) {
    return 'Salvando “$choice”.';
  }

  @override
  String get reasonPrivacyLoading => 'Carregando sua escolha.';

  @override
  String get reasonPrivacyNotAvailable =>
      'Sua escolha ainda não está disponível.';

  @override
  String reasonPrivacySavedStatus(String status) {
    return 'Salvo. $status';
  }

  @override
  String reasonPrivacyChangedElsewhere(String status) {
    return 'Alterado em outro dispositivo. Atualizado. $status';
  }

  @override
  String get reasonPrivacyNobodyLine => 'Só você pode ver seus comentários.';

  @override
  String get reasonPrivacyEveryoneLine =>
      'Qualquer pessoa no Trimmy pode vê-los na página de cada ação.';

  @override
  String get reasonPrivacyFriendsLine =>
      'Ainda não disponível. Nada é compartilhado até existirem amigos.';

  @override
  String get reasonPrivacyFriendsAvailableLine =>
      'Só seus amigos do Trimmy podem vê-los na página de cada ação.';

  @override
  String get reasonPrivacyConsentLine =>
      'Seus comentários e seu nome de usuário vão aparecer na página dessa ação para qualquer pessoa no Trimmy. Valores em dinheiro nunca aparecem.';

  @override
  String get reasonPrivacyNobodyOption => 'Só você. Esta é a opção padrão.';

  @override
  String get reasonPrivacyEveryoneOption =>
      'Qualquer pessoa no Trimmy, na página de cada ação.';

  @override
  String reasonPrivacySheetNow(String choice) {
    return 'Agora: $choice.';
  }

  @override
  String get reasonPrivacyGuestRecovery =>
      'Esta mesa de convidado precisa ser recuperada.';

  @override
  String get reasonPrivacySessionRefresh =>
      'Sua sessão precisa ser atualizada. Tente de novo.';

  @override
  String get reasonPrivacyLoadOffline =>
      'Você está sem conexão. Não foi possível carregar sua escolha.';

  @override
  String get reasonPrivacyLoadTimeout =>
      'Sua escolha demorou demais para carregar.';

  @override
  String get reasonPrivacyLoadSession =>
      'Sua sessão precisa ser atualizada para carregar isto.';

  @override
  String get reasonPrivacyAccountClosed => 'Esta conta foi encerrada.';

  @override
  String get reasonPrivacyLoadFailed =>
      'Não foi possível carregar sua escolha.';

  @override
  String get reasonPrivacySaveOffline =>
      'Você está sem conexão. Sua escolha ainda não foi salva.';

  @override
  String reasonPrivacySaveOfflineChoice(String choice) {
    return 'Você está sem conexão. A opção “$choice” ainda não foi salva.';
  }

  @override
  String get reasonPrivacySaveTimeout =>
      'Salvar demorou demais. Sua escolha ainda não foi salva.';

  @override
  String reasonPrivacySaveTimeoutChoice(String choice) {
    return 'Salvar demorou demais. A opção “$choice” ainda não foi salva.';
  }

  @override
  String get reasonPrivacySaveSession =>
      'Sua sessão precisa ser atualizada. Sua escolha ainda não foi salva.';

  @override
  String reasonPrivacySaveSessionChoice(String choice) {
    return 'Sua sessão precisa ser atualizada. A opção “$choice” ainda não foi salva.';
  }

  @override
  String get reasonPrivacySaveAccountClosed =>
      'Esta conta foi encerrada. Nada foi salvo.';

  @override
  String get reasonPrivacySaveMismatch =>
      'Não foi possível associar esse salvamento. Escolha de novo.';

  @override
  String get reasonPrivacySaveFailed =>
      'Não foi possível salvar. Sua escolha ainda não foi salva.';

  @override
  String reasonPrivacySaveFailedChoice(String choice) {
    return 'Não foi possível salvar. A opção “$choice” ainda não foi salva.';
  }

  @override
  String get reasonPrivacyRateLimitedLoad =>
      'Muitas alterações. Tente carregar de novo daqui a pouco.';

  @override
  String reasonPrivacyRateLimitedLoadSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Muitas alterações. Tente carregar de novo em $seconds segundos.',
      one: 'Muitas alterações. Tente carregar de novo em $seconds segundo.',
    );
    return '$_temp0';
  }

  @override
  String get reasonPrivacyRateLimitedSave =>
      'Muitas alterações. Tente salvar de novo daqui a pouco.';

  @override
  String reasonPrivacyRateLimitedSaveSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Muitas alterações. Tente salvar de novo em $seconds segundos.',
      one: 'Muitas alterações. Tente salvar de novo em $seconds segundo.',
    );
    return '$_temp0';
  }

  @override
  String get reasonReportSheetTitle =>
      'Por que você está denunciando este comentário?';

  @override
  String get reasonReportSheetBody =>
      'Escolha o motivo que mais se aproxima. Quem escreveu não vai ver quem denunciou.';

  @override
  String get reasonReportConfirmTitle => 'Denunciar este motivo?';

  @override
  String reasonReportConfirmBody(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'spam':
          'O Trimmy vai analisar a denúncia de spam. O motivo sai desta página assim que a denúncia for recebida.',
      'harassment':
          'O Trimmy vai analisar a denúncia de assédio. O motivo sai desta página assim que a denúncia for recebida.',
      'impersonation':
          'O Trimmy vai analisar a denúncia por fingir ser outra pessoa. O motivo sai desta página assim que a denúncia for recebida.',
      'unsafe':
          'O Trimmy vai analisar a denúncia de conteúdo perigoso. O motivo sai desta página assim que a denúncia for recebida.',
      'other':
          'O Trimmy vai analisar a denúncia. O motivo sai desta página assim que a denúncia for recebida.',
    });
    return '$_temp0';
  }

  @override
  String get reasonReportAction => 'Denunciar';

  @override
  String get reasonBlockAction => 'Bloquear';

  @override
  String get reasonReportReceived => 'Denúncia recebida.';

  @override
  String reasonBlockConfirmTitle(String handle) {
    return 'Bloquear @$handle?';
  }

  @override
  String get reasonBlockConfirmBody =>
      'Os motivos dessa pessoa saem desta página. Qualquer amizade e convites pendentes entre vocês também serão removidos. Motivos públicos ainda podem ser vistos por outras contas.';

  @override
  String reasonBlockDone(String handle) {
    return 'Você bloqueou @$handle.';
  }

  @override
  String get reasonSafetyErrorConflict =>
      'Isso mudou em outro dispositivo. Escolha de novo.';

  @override
  String get reasonSafetyErrorRateLimited =>
      'Muitas alterações de uma vez. Aguarde um pouco e tente de novo.';

  @override
  String get reasonSafetyErrorUnavailable =>
      'Esta ação não está disponível para sua conta agora.';

  @override
  String get reasonSafetyErrorUnconfirmed =>
      'Não conseguimos confirmar o resultado. Vamos tentar de novo com segurança.';

  @override
  String get reasonSafetyErrorGeneric =>
      'Não foi possível concluir essa ação. Tente de novo.';

  @override
  String get reasonEmpty => 'Ainda não há comentários';

  @override
  String get reasonEmptyFriends => 'Ainda não há comentários de amigos';

  @override
  String get reasonOwnHistoryIncomplete =>
      'Não foi possível carregar aqui seu histórico completo de motivos.';

  @override
  String get reasonOwnStatusFailed =>
      'Não foi possível verificar se seu motivo é privado.';

  @override
  String get reasonShowMore => 'Ver mais';

  @override
  String get reasonLoadSessionRefresh =>
      'Sua sessão precisa ser atualizada para carregar os comentários.';

  @override
  String get reasonLoadOffline =>
      'Você está sem conexão. Não foi possível carregar os comentários.';

  @override
  String get reasonLoadTimeout =>
      'Os comentários demoraram demais para carregar.';

  @override
  String get reasonLoadRateLimited =>
      'Os comentários estão atualizando rápido demais. Tente de novo daqui a pouco.';

  @override
  String get reasonLoadFailed => 'Não foi possível carregar os comentários.';

  @override
  String get reasonAudienceSemantics => 'Escolha de quem ver os comentários';

  @override
  String get reasonAudienceEveryone => 'Todos';

  @override
  String get reasonAudienceFriends => 'Amigos';

  @override
  String get reasonYouBadge => 'Você';

  @override
  String reasonSavedAt(String date, String time) {
    return 'Salvo em $date às $time';
  }

  @override
  String get reasonPrivateLine => 'Seu comentário é privado.';

  @override
  String get reasonLoadingComments => 'Carregando comentários';

  @override
  String get fastBuyTitle => 'Compra rápida';

  @override
  String get fastBuyClose => 'Fechar compra rápida';

  @override
  String get fastBuySearchHint => 'Busque um nome ou código';

  @override
  String get fastBuyOpenFailed =>
      'Não foi possível abrir esta ação. Tente de novo.';

  @override
  String get fastBuyConnectFailed => 'Não foi possível conectar para operar.';

  @override
  String get fastBuyNoneAvailable =>
      'Nenhuma ação disponível para comprar agora.';

  @override
  String get fastBuyNoTradeableMatch =>
      'Nenhuma ação disponível corresponde à busca.';

  @override
  String get fastBuyNoMatches => 'Ainda não há resultados.';

  @override
  String paperAmount(String amount) {
    return '$amount em dinheiro de treino';
  }

  @override
  String paperOrderEquivalentPaper(String amount) {
    return '≈ $amount em dinheiro de treino';
  }

  @override
  String paperOrderEquivalentShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $shares ações',
      one: '≈ $shares ação',
      zero: '≈ $shares ações',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderConversionAtReview => 'Você verá a conversão na revisão';

  @override
  String paperOrderBuyTitle(String symbol) {
    return 'Comprar $symbol';
  }

  @override
  String paperOrderSellTitle(String symbol) {
    return 'Vender $symbol';
  }

  @override
  String get paperOrderReviewBuyTitle => 'Revise sua compra';

  @override
  String get paperOrderReviewSellTitle => 'Revise sua venda';

  @override
  String get paperOrderConfirmedTitle => 'Operação confirmada';

  @override
  String get paperOrderFirstTradeSwipeHint =>
      'Deslize para baixo para editar sua compra';

  @override
  String get paperOrderFirstTradeSkip => 'Pular a primeira operação';

  @override
  String get paperOrderFirstTradeReviewTitle => 'Revise sua compra.';

  @override
  String get paperOrderSharesLabel => 'Ações';

  @override
  String get paperOrderPricePerShare => 'Preço por ação';

  @override
  String get paperOrderFee => 'Taxa';

  @override
  String get paperOrderTotal => 'Total';

  @override
  String get paperOrderConfirmingBuy => 'Confirmando compra…';

  @override
  String get paperOrderCheckingPrice => 'Verificando preço…';

  @override
  String get paperOrderConfirmBuy => 'Confirmar compra';

  @override
  String get paperOrderConfirmSell => 'Confirmar venda';

  @override
  String paperOrderSharesValue(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares ações',
      one: '$shares ação',
      zero: '$shares ações',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSharesAvailable(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares ações disponíveis',
      one: '$shares ação disponível',
      zero: '$shares ações disponíveis',
    );
    return '$_temp0';
  }

  @override
  String paperOrderPaperAvailable(String amount) {
    return 'Disponível: $amount em dinheiro de treino';
  }

  @override
  String paperOrderBuyingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comprando $shares ações',
      one: 'Comprando $shares ação',
      zero: 'Comprando $shares ações',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSellingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vendendo $shares ações',
      one: 'Vendendo $shares ação',
      zero: 'Vendendo $shares ações',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYouPay => 'Você paga';

  @override
  String get paperOrderYouReceive => 'Você recebe';

  @override
  String get paperOrderBuyConfirmed => 'Compra confirmada';

  @override
  String get paperOrderSaleConfirmed => 'Venda confirmada';

  @override
  String paperOrderOnYourDesk(String symbol) {
    return '$symbol já está na sua mesa.';
  }

  @override
  String paperOrderLeftYourDesk(String symbol) {
    return '$symbol saiu da sua mesa.';
  }

  @override
  String paperOrderPositionChanged(String symbol) {
    return 'Sua posição em $symbol mudou.';
  }

  @override
  String paperOrderBoughtShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Você comprou $shares ações',
      one: 'Você comprou $shares ação',
      zero: 'Você comprou $shares ações',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSoldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Você vendeu $shares ações',
      one: 'Você vendeu $shares ação',
      zero: 'Você vendeu $shares ações',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYourPosition => 'Sua posição';

  @override
  String get paperOrderPositionValue => 'Valor da posição';

  @override
  String get paperOrderTrimsEarned => 'Trims ganhos';

  @override
  String get paperOrderReasonLabel => 'Por que você comprou?';

  @override
  String get paperOrderReasonHint => 'Uma linha clara';

  @override
  String get paperOrderSaveReason => 'Salvar motivo';

  @override
  String get paperOrderRetryReason => 'Salvar de novo';

  @override
  String paperOrderReasonTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get paperOrderReasonSaved => 'Motivo salvo';

  @override
  String paperOrderReasonQuote(String note) {
    return '“$note”';
  }

  @override
  String get paperOrderReasonUnavailable =>
      'Sua operação foi confirmada. No momento, não dá para salvar um motivo.';

  @override
  String get paperOrderUnitLabel => 'Unidade do valor da ordem';

  @override
  String get paperOrderUnitPaper => 'Dinheiro';

  @override
  String get paperOrderUnitShares => 'Ações';

  @override
  String get paperOrderKeyDelete => 'Apagar';

  @override
  String get paperOrderKeyDecimal => 'Vírgula';

  @override
  String get paperOrderNoVersion =>
      'Esta empresa não tem uma versão disponível.';

  @override
  String get paperOrderReasonNotSaved =>
      'Operação confirmada. Seu motivo não foi salvo. Tente de novo.';

  @override
  String get paperOrderReasonNotSavedDone =>
      'A operação foi feita, mas o motivo não foi salvo. Tente de novo.';

  @override
  String get paperOrderReasonTooLong =>
      'Use uma linha só e no máximo 180 caracteres.';

  @override
  String get paperOrderReasonOffline =>
      'Operação confirmada. Você está sem conexão, então seu motivo não foi salvo. Tente de novo.';

  @override
  String get paperOrderReasonTimeout =>
      'Operação confirmada. Salvar o motivo demorou demais. Tente de novo.';

  @override
  String get paperOrderReasonSessionExpired =>
      'Operação confirmada. Sua sessão precisa ser atualizada antes de salvar o motivo.';

  @override
  String get paperOrderReasonProfileRequired =>
      'Operação confirmada. Termine de configurar seu perfil antes de salvar o motivo.';

  @override
  String get paperOrderReasonOrderNotFound =>
      'Operação confirmada. Não encontramos esta ordem. Atualize sua mesa.';

  @override
  String get paperOrderReasonBuyRequired =>
      'Só dá para salvar um motivo depois de uma compra de treino confirmada.';

  @override
  String get paperOrderReasonPositionRequired =>
      'Operação confirmada. Você precisa ter esta ação para salvar um motivo.';

  @override
  String get paperOrderReasonExists =>
      'Esta operação já tem um motivo salvo. Atualize sua carreira.';

  @override
  String get paperOrderReasonRetryMismatch =>
      'Operação confirmada. Não foi possível associar esta nova tentativa. Atualize sua carreira.';

  @override
  String get paperOrderReasonBusy =>
      'Operação confirmada. Muitos motivos sendo salvos agora. Tente daqui a pouco.';

  @override
  String get paperOrderErrorInvalidAmount => 'Digite um valor maior que zero.';

  @override
  String get paperOrderErrorInsufficientPaper =>
      'Você não tem dinheiro de treino suficiente para esta ordem.';

  @override
  String get paperOrderErrorInsufficientShares =>
      'Você não tem ações suficientes para vender.';

  @override
  String get paperOrderErrorQuoteExpired =>
      'Esse preço expirou. Confira uma nova cotação.';

  @override
  String get paperOrderErrorPriceChanged =>
      'O preço mudou. Confira a nova cotação.';

  @override
  String get paperOrderErrorOffline =>
      'Você está sem conexão. Verifique sua internet e tente de novo.';

  @override
  String get paperOrderErrorTimeout => 'Isso demorou demais. Tente de novo.';

  @override
  String get paperOrderErrorAccountRequired =>
      'Salve sua mesa antes de fazer esta ordem.';

  @override
  String get paperOrderErrorDuplicate =>
      'Esta ordem já foi recebida. Atualize sua mesa.';

  @override
  String get paperOrderErrorRejected => 'A ordem não foi aceita.';

  @override
  String get paperOrderErrorUnavailable =>
      'A ordem não foi concluída. Tente de novo.';

  @override
  String get liveOrderErrorAddUsdc =>
      'Primeiro adicione USDC à sua carteira Solana.';

  @override
  String get liveOrderErrorAddSol =>
      'Adicione SOL para cobrir as taxas de rede e de conta.';

  @override
  String get liveOrderErrorInsufficientHoldings =>
      'Você não tem o suficiente deste token para vender.';

  @override
  String get liveOrderErrorTradeLimit =>
      'Esta ordem passa do limite atual por operação.';

  @override
  String get liveOrderErrorAppUpdate =>
      'Atualize o Trimmy para ver os termos do emissor antes de operar.';

  @override
  String get liveOrderErrorTermsRequired =>
      'Confirme os termos do emissor para continuar.';

  @override
  String get liveOrderErrorWalletRequired =>
      'Crie sua carteira para continuar.';

  @override
  String get liveOrderErrorOrderPending =>
      'Sua operação anterior ainda está sendo confirmada.';

  @override
  String get liveOrderErrorQuoteExpired =>
      'Esse preço expirou. Peça uma nova cotação.';

  @override
  String get liveOrderErrorBusy =>
      'As cotações estão sobrecarregadas. Tente de novo em instantes.';

  @override
  String get liveOrderErrorNoRoute =>
      'Não há rota para esta ordem agora. Tente outro valor.';

  @override
  String get liveOrderErrorMarketClosed =>
      'Esta ação é negociada enquanto os mercados dos EUA estão abertos. Tente de novo nesse horário.';

  @override
  String get liveOrderErrorBelowMinimum =>
      'Esta ordem está abaixo do mínimo do formador de mercado. Tente um valor maior.';

  @override
  String get liveOrderErrorPriceOffMarket =>
      'Esse preço está muito longe do mercado agora. Tente de novo daqui a pouco ou com um valor menor.';

  @override
  String get liveOrderErrorFeeTooHigh =>
      'As taxas estão altas demais para esta ordem. Tente mais tarde.';

  @override
  String get liveOrderErrorAccountRequired =>
      'Entre de novo para usar sua carteira.';

  @override
  String get liveOrderErrorFreshQuote =>
      'Esta ordem precisa de uma nova cotação.';

  @override
  String get liveOrderErrorUnavailable =>
      'Não foi possível conectar para operar. Tente de novo.';

  @override
  String get liveOrderErrorGeneric =>
      'Não foi possível concluir esta etapa. Tente de novo.';

  @override
  String get liveOrderConfirmTermsFirst =>
      'Primeiro confirme os termos do emissor.';

  @override
  String get liveOrderInvalidShares => 'Digite uma quantidade de ações válida.';

  @override
  String get liveOrderInvalidUsdc => 'Digite um valor válido em USDC.';

  @override
  String liveOrderUpToPerOrder(String amount) {
    return 'Até $amount por ordem.';
  }

  @override
  String liveOrderMinimum(String amount) {
    return 'As ordens deste token começam em $amount.';
  }

  @override
  String liveOrderMarketNotice(String status) {
    return '$status.';
  }

  @override
  String get liveOrderQuoteFailed =>
      'Não foi possível obter uma cotação verificada. Tente de novo.';

  @override
  String get liveOrderCheckingResult =>
      'Verificando o resultado. Sua ordem não será enviada duas vezes.';

  @override
  String get liveOrderSigningFailed =>
      'A assinatura não foi concluída. Nenhuma ordem foi enviada.';

  @override
  String get liveOrderReconnecting => 'Reconectando para verificar sua ordem…';

  @override
  String get liveOrderTermsOpenFailed =>
      'Não foi possível abrir os termos do emissor. Tente de novo.';

  @override
  String get liveOrderTransactionOpenFailed =>
      'Não foi possível abrir a transação. Tente de novo.';

  @override
  String get liveOrderTitleFallback => 'Operação';

  @override
  String get liveOrderAccountChangedTitle => 'Sua conta mudou';

  @override
  String get liveOrderAccountChangedBody =>
      'Entre na conta e abra esta operação de novo.';

  @override
  String get liveOrderCheckLastOrderTitle => 'Vamos verificar sua última ordem';

  @override
  String get liveOrderConnectFailedTitle =>
      'Não foi possível conectar para operar';

  @override
  String get liveOrderConnectedRetryBody =>
      'Tente de novo quando tiver conexão.';

  @override
  String get liveOrderPausedTitle => 'As operações estão pausadas por enquanto';

  @override
  String get liveOrderPausedBody =>
      'Sua carteira e seus investimentos continuam aqui.';

  @override
  String get liveOrderNotTradableTitle =>
      'Este token ainda não pode ser negociado aqui';

  @override
  String get liveOrderChooseAnother => 'Escolha outra ação para operar.';

  @override
  String get liveOrderBackToStocks => 'Voltar às ações';

  @override
  String get liveOrderCheckingBalance => 'Verificando saldo…';

  @override
  String liveOrderAvailable(String amount) {
    return 'Disponível: $amount';
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
  String get liveOrderBuyInstead => 'Mudar para compra';

  @override
  String get liveOrderSellInstead => 'Mudar para venda';

  @override
  String get liveOrderYouSell => 'Você vende';

  @override
  String get liveOrderYouPay => 'Você paga';

  @override
  String liveOrderLimit(String amount) {
    return 'Limite por ordem: $amount';
  }

  @override
  String liveOrderLimitCappedMax(String amount) {
    return 'O máximo foi limitado a $amount, o limite por ordem.';
  }

  @override
  String liveOrderLimitCappedPercent(String percent, String amount) {
    return '$percent foi limitado a $amount, o limite por ordem.';
  }

  @override
  String get liveOrderCheckingPrice => 'Verificando preço e taxas…';

  @override
  String get liveOrderReviewBuy => 'Revisar compra';

  @override
  String get liveOrderReviewSell => 'Revisar venda';

  @override
  String get liveOrderReviewBuyTitle => 'Revise sua compra';

  @override
  String get liveOrderReviewSellTitle => 'Revise sua venda';

  @override
  String get liveOrderYouReceive => 'Você recebe ≈';

  @override
  String get liveOrderMinimumReceived => 'Mínimo a receber';

  @override
  String get liveOrderNetworkFees => 'Taxas de rede e de conta';

  @override
  String get liveOrderSwapFee => 'Taxa de swap';

  @override
  String get liveOrderPrice => 'Preço';

  @override
  String get liveOrderFixedQuote => 'Cotação fixa de um formador de mercado';

  @override
  String get liveOrderIssuer => 'Emissor';

  @override
  String get liveOrderIssuerFee => 'Taxa do emissor';

  @override
  String get liveOrderConfirmBuy => 'Confirmar compra';

  @override
  String get liveOrderConfirmSell => 'Confirmar venda';

  @override
  String get liveOrderEditAmount => 'Editar valor';

  @override
  String get liveOrderTradeConfirmed => 'Operação confirmada';

  @override
  String get liveOrderConfirmingTrade => 'Confirmando sua operação';

  @override
  String get liveOrderQuoteExpired => 'Cotação expirada';

  @override
  String get liveOrderTradeIncomplete => 'A operação não foi concluída';

  @override
  String get liveOrderConfirmedBody => 'Sua ordem foi confirmada na Solana.';

  @override
  String get liveOrderPendingBody =>
      'Você pode fechar esta tela. Abra a operação de novo para ver o status.';

  @override
  String get liveOrderExpiredBody => 'Peça um novo preço para continuar.';

  @override
  String get liveOrderFailedBody => 'Sua ordem não foi executada.';

  @override
  String get liveOrderViewWalletActivity => 'Ver atividade da carteira ↗';

  @override
  String get liveOrderViewTransaction => 'Ver transação ↗';

  @override
  String get liveOrderGetFreshPrice => 'Pedir novo preço';

  @override
  String liveOrderIssuerExcluded(String regions) {
    return 'Indisponível para residentes de: $regions';
  }

  @override
  String liveOrderIssuerFeeNote(String percent) {
    return 'Taxa do emissor: $percent em cada compra e venda';
  }

  @override
  String get liveOrderLegacyAttestation =>
      'Sou elegível segundo os termos do emissor.';

  @override
  String get liveOrderIssuerTerms => 'Termos do emissor ↗';

  @override
  String get liveHistoryStatusConfirming => 'Confirmando';

  @override
  String get liveHistoryStatusConfirmed => 'Confirmada';

  @override
  String get liveHistoryStatusFailed => 'Não concluída';

  @override
  String get liveHistoryStatusExpired => 'Expirada';

  @override
  String get liveHistoryErrorSignIn => 'Entre de novo para ver suas operações.';

  @override
  String get liveHistoryErrorLoad =>
      'Não foi possível carregar suas operações. Tente de novo.';

  @override
  String get liveHistoryErrorLoadMore =>
      'Não foi possível carregar mais operações. Tente de novo.';

  @override
  String get liveHistoryErrorOpenStock =>
      'Não foi possível abrir esta ação. Tente de novo.';

  @override
  String get liveHistoryTitle => 'Suas operações';

  @override
  String get liveHistoryEmptyTitle => 'Sua primeira operação começa aqui';

  @override
  String get liveHistoryEmptyBody => 'Suas ordens vão aparecer aqui.';

  @override
  String get liveHistoryMore => 'Mais operações';

  @override
  String liveHistoryRowBuy(String symbol) {
    return 'Compra de $symbol';
  }

  @override
  String liveHistoryRowSell(String symbol) {
    return 'Venda de $symbol';
  }

  @override
  String get liveHistoryYouPaid => 'Você pagou';

  @override
  String get liveHistoryYouSold => 'Você vendeu';

  @override
  String get liveHistoryYouReceived => 'Você recebeu';

  @override
  String get liveHistoryFinalAmounts =>
      'Valores finais da transação confirmada.';

  @override
  String get liveHistoryQuotedOutput => 'Valor cotado';

  @override
  String get liveHistoryMinimumOutput => 'Valor mínimo';

  @override
  String get liveHistoryEstimates =>
      'Estimativas da ordem. Veja a transação para os valores finais.';

  @override
  String get liveHistoryViewTransaction => 'Ver transação';

  @override
  String get liveHistoryOpenStock => 'Abrir ação';

  @override
  String get liveTradingOpenAlways => 'Aberto 24/7';

  @override
  String get liveTradingOpenWeekends =>
      'Aberto agora, inclusive nos fins de semana';

  @override
  String get liveTradingOpenNow => 'Aberto agora';

  @override
  String get liveTradingPausedByIssuer => 'Pausado pelo emissor';

  @override
  String get liveTradingPausedByMarket => 'Pausado pelo mercado';

  @override
  String liveTradingPausedResumes(String time) {
    return 'Pausado · volta $time';
  }

  @override
  String get liveTradingShortPause => 'Pausa curta';

  @override
  String liveTradingShortPauseResumes(String time) {
    return 'Pausa curta · volta $time';
  }

  @override
  String get liveTradingClosed => 'Fechado';

  @override
  String liveTradingClosedOpens(String time) {
    return 'Fechado · abre $time';
  }

  @override
  String get liveTradingHoursAroundClock =>
      'É negociado a qualquer hora, com pausas curtas entre as sessões dos EUA.';

  @override
  String get liveTradingHoursWeekdays =>
      'É negociado 24 horas por dia, de domingo à noite até sexta à noite (horário do leste dos EUA).';

  @override
  String get liveTradingHoursRegular =>
      'É negociado só no horário do mercado dos EUA, das 9h30 às 16h (horário do leste), em dias úteis.';

  @override
  String get liveTradingHoursSessions =>
      'É negociado só durante as sessões do mercado dos EUA.';

  @override
  String liveTradingTimeToday(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'às $clock',
      one: 'à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeTomorrow(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'amanhã às $clock',
      one: 'amanhã à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeWeekday(int hour, String weekday, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: '$weekday às $clock',
      one: '$weekday à $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeDate(int hour, String date, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'em $date às $clock',
      one: 'em $date à $clock',
    );
    return '$_temp0';
  }

  @override
  String get liveTradingReasonIssuerNotOffered =>
      'O Trimmy não oferece este emissor.';

  @override
  String get liveTradingReasonNotYet =>
      'Ainda não está disponível para operar no Trimmy.';

  @override
  String get liveTradingReasonIdentity =>
      'O Trimmy não conseguiu confirmar quem emitiu este token.';

  @override
  String get liveTradingReasonRestricted =>
      'O emissor tem restrições neste token que o Trimmy não pode aceitar.';

  @override
  String get liveTradingReasonLowLiquidity =>
      'É pouco negociado para comprar e vender com segurança.';

  @override
  String get liveTradingReasonNoRoute =>
      'Nenhuma rota de ordem passou nas verificações de segurança do Trimmy.';

  @override
  String get liveTradingReasonPriceOff =>
      'O preço está muito longe do preço real da ação.';

  @override
  String get liveTradingReasonHeldBack =>
      'Pausado enquanto o Trimmy verifica este token.';

  @override
  String get liveTradingReasonNotChecked => 'Ainda não verificado.';

  @override
  String liveTradingReasonClosedOpens(String time) {
    return 'O mercado está fechado. Ele abre $time e depois o Trimmy faz a verificação.';
  }

  @override
  String get liveTradingReasonUsHours =>
      'Só é negociado enquanto os mercados dos EUA estão abertos.';

  @override
  String get liveTradingReasonAwaitingReview =>
      'O mercado está aberto. O Trimmy está verificando antes de você poder operar.';

  @override
  String get liveTradingReasonNoMarketMaker =>
      'Nenhum formador de mercado está cotando agora.';

  @override
  String get liveTradingReasonUnavailable =>
      'Não está disponível para operar no Trimmy.';

  @override
  String get liveTradingOtherIssuer => 'Outro emissor';

  @override
  String get holdingsCheckingWallet => 'Verificando sua carteira…';

  @override
  String get holdingsWalletStarts => 'Sua carteira começa aqui';

  @override
  String get holdingsEmptyTitle => 'Nenhuma ação ainda';

  @override
  String get holdingsEmptyBody => 'Sua primeira ação começa aqui.';

  @override
  String get holdingsExplore => 'Explorar ações';

  @override
  String get walletFastBuy => 'Compra rápida';

  @override
  String get walletSend => 'Enviar';

  @override
  String get walletCashBalance => 'Saldo disponível';

  @override
  String get walletAccountBalance => 'Saldo da conta';

  @override
  String get walletKnownValue => 'Valor conhecido';

  @override
  String get walletSwitchToPaper => 'Mudar para o modo Treino';

  @override
  String get walletSwitchToReal => 'Mudar para o modo dinheiro real';

  @override
  String get walletUsdcAvailable => 'USDC disponível';

  @override
  String walletPositions(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText posições',
      one: '$countText posição',
      zero: '$countText posições',
    );
    return '$_temp0';
  }

  @override
  String get walletSomePricesUnavailable => 'Alguns preços indisponíveis';

  @override
  String get walletPositionPricesUnavailable =>
      'Preços das posições indisponíveis';

  @override
  String get walletCheckingSol => 'Verificando SOL…';

  @override
  String walletSolForFees(String amount) {
    return '$amount SOL para taxas';
  }

  @override
  String get walletCashMarks => 'USDC e SOL';

  @override
  String get fundCreateWalletFailed =>
      'Não foi possível criar sua carteira. Tente de novo.';

  @override
  String get fundWalletUnconfirmed => 'Não conseguimos confirmar sua carteira.';

  @override
  String get fundWalletOffline =>
      'Você está sem conexão. Conecte-se de novo para carregar sua carteira.';

  @override
  String get fundWalletLoadFailed => 'Não foi possível carregar sua carteira.';

  @override
  String get fundTabCash => 'Cartão';

  @override
  String get fundTabCrypto => 'Cripto';

  @override
  String get fundWalletMissingTitle => 'Uma carteira para o seu dinheiro';

  @override
  String get fundCreatingWallet => 'Criando…';

  @override
  String get fundCreateWallet => 'Criar carteira';

  @override
  String fundDepositQrLabel(String address) {
    return 'Endereço de depósito na Solana $address';
  }

  @override
  String get fundSendOnlyWarning =>
      'Envie apenas USDC ou SOL para esta conta na rede Solana.';

  @override
  String get fundAddressCopied => 'Copiado';

  @override
  String get fundCopyAddress => 'Copiar endereço';

  @override
  String get guestDeskStartAgainFailedExpired =>
      'Não foi possível começar de novo. Sua mesa expirada continua guardada.';

  @override
  String get guestDeskStartAgainFailed =>
      'Não foi possível começar de novo. Sua mesa antiga continua guardada.';

  @override
  String get guestDeskStartFreshTitle => 'Começar do zero?';

  @override
  String get guestDeskExpiredTitle => 'A sessão de convidado expirou';

  @override
  String get guestDeskEndedTitle => 'A sessão de convidado terminou';

  @override
  String get guestDeskStartFreshMessage =>
      'Este celular vai perder o acesso à sua mesa antiga. Não dá para desfazer.';

  @override
  String get guestDeskExpiredMessage =>
      'Seus registros de convidado estão guardados. Esta mesa não pode mais operar nem ser salva em uma conta.';

  @override
  String get guestDeskEndedMessage =>
      'Seus registros de convidado estão guardados, mas este celular não consegue mais abrir a mesa.';

  @override
  String get guestDeskStartFreshDetail =>
      'Seu saldo, suas posições e seu histórico não vão para a nova mesa.';

  @override
  String get guestDeskSignInDetail =>
      'Entre para abrir sua conta salva. Sua mesa de convidado fica intacta.';

  @override
  String get guestDeskOpening => 'Abrindo…';

  @override
  String get guestDeskStartNewConfirm => 'Começar uma nova mesa';

  @override
  String get guestDeskKeep => 'Manter esta mesa';

  @override
  String get guestDeskStartNewGuest => 'Começar outra mesa de convidado';

  @override
  String get guestDeskPreservedTitle => 'Olá de novo';

  @override
  String get guestDeskPreservedMessage =>
      'Suas operações salvas e seu progresso estão prontos.';

  @override
  String get guestDeskPreservedExpiredDetail =>
      'Sua mesa de convidado expirada fica guardada à parte. Ela não pode mais operar nem ser mesclada.';

  @override
  String get guestDeskPreservedDetail =>
      'Suas operações de convidado ficam separadas. Saia da conta para voltar àquela mesa.';

  @override
  String get guestDeskGoToDesk => 'Ir para minha mesa';

  @override
  String get onrampErrorNotEnabled =>
      'Depósitos com cartão ainda não estão disponíveis. Você ainda pode transferir de outra carteira.';

  @override
  String get onrampErrorSignIn => 'Entre de novo para continuar.';

  @override
  String get onrampErrorExpired =>
      'Este pagamento precisa ser verificado com o suporte. O saldo da sua carteira ainda vai ser atualizado.';

  @override
  String get onrampErrorBusy => 'Espere um pouco e tente de novo.';

  @override
  String onrampErrorAmount(String min, String max) {
    return 'Digite um valor de $min a $max.';
  }

  @override
  String get onrampErrorWalletChanged =>
      'Atualize sua carteira antes de continuar.';

  @override
  String get onrampErrorUnavailable =>
      'Não foi possível abrir o pagamento. Tente de novo daqui a pouco.';

  @override
  String get onrampErrorStep => 'Esta etapa não foi concluída. Tente de novo.';

  @override
  String get onrampErrorEmail => 'Digite um e-mail para o comprovante.';

  @override
  String get onrampErrorRefresh =>
      'Não foi possível atualizar este depósito. Confira de novo antes de pagar outra vez.';

  @override
  String get onrampTestDoneTitle => 'Depósito de teste concluído';

  @override
  String get onrampDoneTitle => 'Dinheiro adicionado';

  @override
  String get onrampFailedTitle => 'O depósito precisa de atenção';

  @override
  String get onrampPendingTitle => 'Conclua seu depósito';

  @override
  String get onrampTestDoneBody =>
      'Os USDC de teste chegaram na Solana devnet.';

  @override
  String get onrampDoneBody => 'Seus USDC estão na sua carteira.';

  @override
  String get onrampFailedBody =>
      'Fale com a Crossmint e informe este número do pedido. Não pague de novo.';

  @override
  String get onrampPendingBody =>
      'Conclua o pagamento no navegador e depois volte aqui.';

  @override
  String get onrampOpenPayment => 'Abrir pagamento';

  @override
  String onrampOrderId(String orderId) {
    return 'Pedido $orderId';
  }

  @override
  String get onrampCheckingOptions => 'Verificando opções de pagamento…';

  @override
  String get onrampCardUnavailable =>
      'Depósitos com cartão ainda não estão disponíveis.';

  @override
  String get onrampTransferFromWallet => 'Transferir de uma carteira';

  @override
  String get onrampTestCheckout => 'Pagamento de teste';

  @override
  String get onrampMethods => 'Cartão, Apple Pay ou Google Pay';

  @override
  String get onrampMethodsNote =>
      'As opções disponíveis aparecem no pagamento.';

  @override
  String get onrampAmountLabel => 'Valor';

  @override
  String get onrampReceiptEmail => 'E-mail para o comprovante';

  @override
  String get onrampUsdcNote =>
      'USDC na Solana. As taxas aparecem no pagamento.';

  @override
  String get onrampConfirmWallet =>
      'Confirme que esta carteira é sua. Você assina uma mensagem, não um pagamento.';

  @override
  String get onrampVerificationMessage => 'Mensagem de verificação';

  @override
  String get onrampOneMoment => 'Um momento…';

  @override
  String get onrampVerifyContinue => 'Verificar e continuar';

  @override
  String get onrampPoweredByCrossmint => 'Com tecnologia da Crossmint';

  @override
  String get signInTitleDeskAwaits => 'Sua mesa te espera.';

  @override
  String get signInTitleTrimmy => 'Entre no Trimmy.';

  @override
  String get signInCaption => 'Entre ou crie sua conta.';

  @override
  String get signInCaptionExpired =>
      'Abra a mesa da sua conta. A mesa de convidado expirada fica separada.';

  @override
  String get signInNoticeExpired =>
      'Se você fechar o login, a mesa de convidado expirada continua guardada.';

  @override
  String get signInErrorConnection =>
      'Não conseguimos conectar sua conta. Sua mesa continua aqui.';

  @override
  String get signInErrorConnectionExpired =>
      'Não conseguimos conectar sua conta. Sua mesa anterior está guardada.';

  @override
  String get signInErrorUnfinished => 'Não deu para concluir. Tente de novo.';

  @override
  String get signInClosed => 'O login foi fechado. Sua mesa continua aqui.';

  @override
  String get signInClosedExpired =>
      'O login foi fechado. Sua mesa anterior está guardada.';

  @override
  String get signInErrorCode => 'Esse código não funcionou. Tente de novo.';

  @override
  String get signInUnavailable => 'O login não está disponível agora.';

  @override
  String get signInErrorEmailInvalid => 'Digite um e-mail completo.';

  @override
  String get signInErrorSendCode =>
      'Não conseguimos enviar o código. Tente de novo.';

  @override
  String get signInErrorCodeMissing =>
      'Digite o código que enviamos por e-mail.';

  @override
  String get signInCloseTooltip => 'Fechar login';

  @override
  String get signInUseDifferentEmail => 'Usar outro e-mail';

  @override
  String get signInTitleSaveDesk => 'Salve sua mesa.';

  @override
  String get signInTitleCheckEmail => 'Confira seu e-mail.';

  @override
  String get signInTitleYourEmail => 'Seu e-mail.';

  @override
  String get signInExpiredDeskSeparate =>
      'A mesa de convidado expirada fica separada.';

  @override
  String get signInDeskStaysOnPhone => 'Sua mesa fica neste celular.';

  @override
  String signInCodeSentTo(String email) {
    return 'Enviamos um código para $email.';
  }

  @override
  String get signInWeWillSendCode =>
      'Vamos enviar um código de login para você.';

  @override
  String get signInNotSetUp =>
      'O login com conta não está configurado nesta versão. Sua mesa fica neste celular.';

  @override
  String get signInNotSetUpExpired =>
      'O login com conta não está configurado nesta versão. A mesa de convidado expirada continua guardada.';

  @override
  String get signInContinueAsGuest => 'Continuar no modo convidado';

  @override
  String get signInLater => 'Mais tarde';

  @override
  String get signInCodeLabel => 'Código';

  @override
  String get signInEmailLabel => 'E-mail';

  @override
  String get signInSendCode => 'Enviar código';

  @override
  String get signInWelcomeBackTitle => 'Olá de novo.';

  @override
  String get signInWelcomeBackCaption => 'Sua próxima jogada está esperando.';

  @override
  String get signInOr => 'OU';

  @override
  String get signInContinueWithEmail => 'Continuar com e-mail';

  @override
  String get signInBusyValue => 'Em andamento';

  @override
  String signInContinueWithProvider(String provider) {
    return 'Continuar com $provider';
  }

  @override
  String get careerWorldNextNeighbourhood => 'O próximo bairro';

  @override
  String get careerWorldMoreOnTheWay => 'Mais tarefas estão a caminho.';

  @override
  String careerWorldLockedHint(int day) {
    return 'Conclua o dia $day para abrir este expediente.';
  }

  @override
  String get careerWorldLoading => 'Abrindo sua semana…';

  @override
  String get careerWorldLoadFailed => 'Não foi possível carregar suas tarefas.';

  @override
  String get careerWorldBeyondFirstMonth => 'Além do primeiro mês';

  @override
  String get careerWorldCityGrowing => 'A cidade continua crescendo';

  @override
  String get careerWorldStartHere => 'COMECE AQUI';

  @override
  String get careerWorldContinue => 'CONTINUAR';

  @override
  String get careerWorldComingLater => 'Em breve';

  @override
  String get careerWorldFiled => 'Entregue';

  @override
  String careerWorldDayFiled(int day) {
    return 'Dia $day, entregue';
  }

  @override
  String careerWorldDayCurrent(int day) {
    return 'Dia $day, tarefa atual';
  }

  @override
  String careerWorldDayLocked(int day) {
    return 'Dia $day, bloqueado';
  }

  @override
  String careerWorldDayComingLater(int day) {
    return 'Dia $day, em breve';
  }

  @override
  String get workdayEntryReload => 'Recarregar sua tarefa';

  @override
  String workdayEntryEyebrow(int day, String speaker) {
    return 'DIA $day · $speaker';
  }

  @override
  String get workdayEntryNext => 'Sua próxima tarefa';

  @override
  String get workdayEntryContinue => 'Continue sua tarefa';

  @override
  String get deskActivityTitle => 'Sua atividade';

  @override
  String get deskActivityEmpty => 'Sua primeira operação começa a história.';

  @override
  String deskActivityBought(String symbol) {
    return 'Você comprou $symbol';
  }

  @override
  String deskActivitySold(String symbol) {
    return 'Você vendeu $symbol';
  }

  @override
  String get deskCommunityTitle => 'Comunidade';

  @override
  String get deskCommunityPrompt => 'Veja o que os traders estão dizendo';

  @override
  String get deskCommunityLoadFailed =>
      'Não foi possível carregar a comunidade';

  @override
  String get deskCommunityOpening => 'Abrindo a comunidade…';

  @override
  String get deskCommunityStart => 'Comece uma conversa';

  @override
  String get deskCommunitySubtitle => 'Comentários públicos de outros traders.';

  @override
  String deskCommunityPostByHandle(String handle, String cashtag) {
    return '@$handle sobre $cashtag';
  }

  @override
  String deskCommunityPostByTrader(String cashtag) {
    return 'Um trader sobre $cashtag';
  }

  @override
  String get deskTitle => 'Sua mesa';

  @override
  String get deskUpdatesTooltip => 'Novidades';

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
      other: 'dias de sequência',
      one: 'dia de sequência',
    );
    return '$_temp0';
  }

  @override
  String get deskHoldingsTitle => 'Seus investimentos';

  @override
  String get deskExplore => 'Explorar';

  @override
  String deskShareCount(num count, String quantity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$quantity ações',
      one: '$quantity ação',
    );
    return '$_temp0';
  }

  @override
  String get deskPickTraderTitle => 'Escolha seu trader';

  @override
  String get deskPickTraderSubtitle => 'Deixe esta mesa com a sua cara.';

  @override
  String get deskSaveTitle => 'Salve sua mesa';

  @override
  String get deskSaveSubtitle => 'Leve para seus outros dispositivos.';

  @override
  String get deskCareerFallback => 'Sua carreira';

  @override
  String get deskNextStepFallback => 'Veja seu próximo passo';

  @override
  String get deskEmptyTitle => 'Nenhuma ação ainda';

  @override
  String get deskEmptyBody => 'Escolha uma empresa para começar.';

  @override
  String get deskEmptyExplore => 'Explorar ações';

  @override
  String get deskHoldingValueUnavailable => 'Valor indisponível';

  @override
  String clockWallStreetClosesIn(String duration) {
    return 'Aqui as ações são negociadas 24/7. Wall Street fecha em $duration.';
  }

  @override
  String clockWallStreetOpensIn(String duration) {
    return 'Aqui as ações são negociadas 24/7. Wall Street abre em $duration.';
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
  String get workdayDraftSaved => 'Salvo';

  @override
  String get workdayDraftNotSaved => 'Ainda não salvo';

  @override
  String get workdayLeaveTitle => 'Sair desta nota?';

  @override
  String get workdayLeaveBody =>
      'Suas últimas alterações ainda não foram salvas.';

  @override
  String get workdayLeaveKeepWriting => 'Continuar escrevendo';

  @override
  String get workdayLeaveWithoutSaving => 'Sair sem salvar';

  @override
  String get workdaySaveRetry =>
      'Ainda não foi possível salvar. Tente de novo.';

  @override
  String workdayDayTitle(int day) {
    return 'Dia $day';
  }

  @override
  String get workdaySaveAndClose => 'Salvar e fechar';

  @override
  String get workdayFiledTitle => 'Entregue.';

  @override
  String workdayTrimsEarned(int trims) {
    return '+$trims Trims';
  }

  @override
  String workdayNextDay(int day, String title) {
    return 'Dia $day: $title';
  }

  @override
  String get workdayHintShow => 'Uma dica?';

  @override
  String get workdayHintHide => 'Ocultar dica';

  @override
  String get workdayFileHeading => 'Envie uma atualização para a equipe';

  @override
  String get workdayFileBody => 'Fique com os dois fatos que a fonte comprova.';

  @override
  String get workdayNoteHint => 'Adicione uma nota (opcional)';

  @override
  String get workdayButtonBack => 'Voltar para a rua';

  @override
  String get workdayButtonCheckEvidence => 'Conferir as evidências';

  @override
  String get workdayButtonSendDecision => 'Enviar sua decisão';

  @override
  String get workdayButtonFile => 'Entregar atualização';

  @override
  String get workdayPinDetail => 'Fixar dado';

  @override
  String get workdayUnpinDetail => 'Desafixar dado';

  @override
  String get workdayOpensSoon => 'Abre em breve';

  @override
  String get workdayOpensTomorrow => 'Abre amanhã';

  @override
  String workdayOpensOnWeekday(String weekday) {
    return 'Abre $weekday';
  }

  @override
  String workdayOpensOnDate(String date) {
    return 'Abre em $date';
  }

  @override
  String get workdayErrorCheckEvidence =>
      'Confira a fonte de novo. Esses dados não sustentam esta atualização.';

  @override
  String get workdayErrorCheckDecision => 'Dê outra olhada nos números.';

  @override
  String get workdayErrorTomorrow =>
      'A tarefa de hoje está concluída. Seu próximo expediente começa em breve.';

  @override
  String get workdayErrorClosed =>
      'O escritório está fechado hoje. Volte no próximo expediente.';

  @override
  String get workdayErrorChanged =>
      'Seu trabalho mudou em outra tela. Já atualizamos.';

  @override
  String get workdayErrorLocked => 'Entregue primeiro a tarefa anterior.';

  @override
  String get workdayErrorSession => 'Sua conta mudou. Abra sua mesa de novo.';

  @override
  String get workdayErrorSaveFailed =>
      'Ainda não foi possível salvar. Seu trabalho continua aqui. Tente de novo.';

  @override
  String get careerMissionFirstPaperBuyTitle => 'Compre sua primeira ação';

  @override
  String get careerMissionWriteAReasonTitle => 'Escreva seu motivo';

  @override
  String get careerMissionHoldThroughRedDayTitle =>
      'Aguente um dia no vermelho';

  @override
  String get careerErrorOffline =>
      'Sua carreira está offline. Verifique sua conexão e tente de novo.';

  @override
  String get careerErrorTimeout =>
      'Sua carreira demorou demais para abrir. Tente de novo.';

  @override
  String get careerErrorSession =>
      'Sua carreira precisa de uma nova sessão. Tente de novo.';

  @override
  String get careerErrorRateLimited =>
      'Sua carreira está atualizando rápido demais. Tente de novo daqui a pouco.';

  @override
  String get careerErrorProfileRequired =>
      'Termine de configurar seu perfil do Trimmy e tente de novo.';

  @override
  String get careerErrorUnavailable =>
      'Sua carreira está indisponível. Tente de novo.';

  @override
  String careerStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sequência de $countText dias',
      one: 'Sequência de $countText dia',
    );
    return '$_temp0';
  }

  @override
  String get careerStreakRetryActivity => 'Recarregar atividade';

  @override
  String careerStreakDaySemantics(String date, String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'active': 'com atividade',
      'upcoming': 'ainda por vir',
      'none': 'sem atividade',
      'unavailable': 'atividade indisponível',
      'other': 'atividade indisponível',
    });
    return '$date, $_temp0';
  }

  @override
  String get careerYourProgress => 'Seu progresso';

  @override
  String get careerPointsLabel => 'Pontos de carreira';

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
  String get communityTitle => 'Comunidade';

  @override
  String get communityUpdatesTitle => 'Novidades';

  @override
  String get communityScopeEveryone => 'Todos';

  @override
  String get communityScopeFollowing => 'Seguindo';

  @override
  String get communityLoadFailed =>
      'Não foi possível carregar a atividade. Tente de novo.';

  @override
  String get communitySaveFailed =>
      'Essa alteração não foi salva. Tente de novo.';

  @override
  String get communityEmptyUpdatesTitle => 'Você está em dia';

  @override
  String get communityEmptyUpdatesBody =>
      'Os comentários novos de quem você segue aparecem aqui.';

  @override
  String get communityEmptyFollowingTitle => 'Sua galera, aqui';

  @override
  String get communityEmptyFollowingBody => 'Siga um trader na aba Todos.';

  @override
  String get communityEmptyEveryoneTitle =>
      'Ainda não há comentários compartilhados';

  @override
  String get communityEmptyEveryoneBody =>
      'Os comentários públicos vão aparecer aqui.';

  @override
  String get communityAnonymousTrader => 'Trader';

  @override
  String get communityFollowingButton => 'Seguindo';

  @override
  String get communityFollowButton => '+ Seguir';

  @override
  String get communityCommentOptions => 'Opções do comentário';

  @override
  String get communityMuteUpdates => 'Silenciar novidades';

  @override
  String get communityTurnOnUpdates => 'Ativar novidades';

  @override
  String get communityReport => 'Denunciar';

  @override
  String get communityBlockTrader => 'Bloquear trader';

  @override
  String communityPostTime(String date, String time) {
    return '$date · $time';
  }

  @override
  String get communityLoadMore => 'Carregar mais';

  @override
  String get floorTitle => 'Carreira';

  @override
  String get floorCloseProgress => 'Fechar progresso';

  @override
  String get floorProgressButton => 'Progresso';

  @override
  String get floorCareerLoadFailed => 'Não foi possível carregar sua carreira';

  @override
  String get floorBrowseStocks => 'Ver ações';

  @override
  String get floorTrimsTooltip =>
      'Trims são pontos de carreira. Ganhe Trims com atividades para subir de cargo.';

  @override
  String get floorMilestonesTitle => 'Missões de carreira';

  @override
  String get floorMilestonesActivities => 'Suas atividades';

  @override
  String floorMilestonesComplete(String complete, String total) {
    return '$complete de $total concluídas';
  }

  @override
  String get floorMilestonesUpdating => 'Atualizando seu progresso…';

  @override
  String get floorActivitiesLoadFailed =>
      'Não foi possível carregar as atividades';

  @override
  String get floorMissionCommentTitle => 'Comente sua operação';

  @override
  String get floorMissionStatusComplete => 'Concluída';

  @override
  String get floorMissionStatusReady => 'Disponível';

  @override
  String get floorMissionStatusLocked => 'Bloqueada';

  @override
  String get floorMissionHoldHint =>
      'Mantenha uma ação durante um dia de queda.';

  @override
  String get floorMissionWriteComment => 'Escreva um comentário';

  @override
  String get floorMissionFindStock => 'Encontre uma ação';

  @override
  String floorMissionBecomeRank(String rank) {
    return 'Torne-se $rank';
  }

  @override
  String floorPromotionUnlocked(String rank) {
    return 'Cargo desbloqueado: $rank';
  }

  @override
  String get floorRankHighestReached => 'Você chegou ao cargo mais alto';

  @override
  String floorRankPromotionReady(String rank) {
    return 'Sua promoção a $rank está pronta';
  }

  @override
  String get floorRankThresholdReached =>
      'Você já tem os Trims necessários. Conclua a missão de promoção';

  @override
  String floorRankTrimsToNext(int count, String countText, String rank) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Faltam $countText Trims para $rank',
      one: 'Falta $countText Trim para $rank',
    );
    return '$_temp0';
  }

  @override
  String floorRankProgressSemantics(String percent, String status) {
    return 'Progresso do cargo: $percent por cento. $status';
  }

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileYourProfile => 'Seu perfil';

  @override
  String get profileGuestTitle => 'Deixe do seu jeito';

  @override
  String get profileGuestBody =>
      'Entre para manter suas operações e sua carreira em um só lugar.';

  @override
  String get profileProgressRefreshFailed =>
      'Não foi possível atualizar o progresso.';

  @override
  String get profileLoadProgress => 'Carregar progresso';

  @override
  String get profileChooseTrader => 'Escolha seu trader';

  @override
  String get profileYourTrader => 'Seu trader';

  @override
  String get profileChangeTrader => 'Trocar seu trader';

  @override
  String profileStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText dias',
      one: '$countText dia',
    );
    return '$_temp0';
  }

  @override
  String get profileStreakLabel => 'Sequência';

  @override
  String get socialReportCategorySpam => 'Spam';

  @override
  String get socialReportCategoryHarassment => 'Assédio';

  @override
  String get socialReportCategoryImpersonation => 'Fingir ser outra pessoa';

  @override
  String get socialReportCategoryUnsafe => 'Conteúdo perigoso';

  @override
  String get socialReportCategoryOther => 'Outro motivo';

  @override
  String get infoHelpTitle => 'Ajuda';

  @override
  String get infoTermsTitle => 'Termos';

  @override
  String get infoPrivacyTitle => 'Privacidade';

  @override
  String get infoContactTitle => 'Fale com a gente';

  @override
  String get infoContactBody =>
      'Procure @trimmyhq no X para pedir ajuda ou mandar sua opinião.';

  @override
  String get infoLinkCopied => 'Link copiado';

  @override
  String get infoCopyContactLink => 'Copiar link de contato';

  @override
  String get infoCopyWebsiteLink => 'Copiar link do site';

  @override
  String infoLastUpdated(String date) {
    return 'Última atualização: $date';
  }

  @override
  String infoProviderPolicyLink(String provider, String url) {
    return '$provider: $url';
  }

  @override
  String get infoPracticeAndCareerTitle => 'Treino e Carreira';

  @override
  String get infoPrivacyHeading => 'Privacidade, em palavras simples.';

  @override
  String get infoPrivacyIntro =>
      'Este aviso descreve as informações tratadas pelo app Trimmy e pelos serviços que dão suporte a ele.';

  @override
  String get infoPrivacyAccountTitle => 'Sua conta ou sessão de convidado';

  @override
  String get infoPrivacyAccountBody =>
      'O login usa a Privy e o provedor de e-mail ou rede social que você escolher. O Trimmy recebe identificadores de conta, credenciais de sessão e os dados disponíveis das contas vinculadas, como seu e-mail, nome de usuário ou foto de perfil, para autenticar você e recuperar seu progresso. Continuar como convidado cria uma sessão separada; a atividade como convidado também pode ser armazenada no nosso servidor. Ao entrar, esse progresso pode ser vinculado à sua conta.';

  @override
  String get infoPrivacyPracticeBody =>
      'Suas ordens de treino, saldos, respostas de atividades, expedientes concluídos, sequências, Trims, lista de acompanhamento e perfil de trader servem para o jogo e para o seu progresso. Preferências e rascunhos de atividades não concluídas podem ser salvos no seu dispositivo; os registros da conta e do progresso também são armazenados no nosso servidor.';

  @override
  String get infoPrivacyCommentsTitle => 'Comentários e quem você segue';

  @override
  String get infoPrivacyCommentsBody =>
      'Sua escolha de compartilhamento de comentários define quais outros usuários podem ver seus comentários com seu nome de usuário, seu personagem de trader e o ativo comentado. O feed da comunidade não publica os valores das suas ordens nem o saldo da sua carteira. Armazenamos quem você segue, preferências de compartilhamento, bloqueios e denúncias para oferecer esses recursos e lidar com abusos. A atividade pública na blockchain continua visível independentemente dessas configurações.';

  @override
  String get infoPrivacyWalletsTitle => 'Carteiras e operações reais';

  @override
  String get infoPrivacyWalletsBody =>
      'A Privy fornece a carteira integrada e a interface de assinatura. O Trimmy usa seu endereço público na Solana para ler saldos, pedir cotações e preparar as transações que você revisa. Nosso servidor recebe as transações assinadas para envio e armazena os termos da ordem, as referências da transação e o status. Endereços de carteira, quantidades de tokens e assinaturas de transações são públicos na blockchain. Encerrar o Trimmy não pode apagar esses registros.';

  @override
  String get infoPrivacyFundingTitle => 'Adicionar dinheiro';

  @override
  String get infoPrivacyFundingBody =>
      'Quando você usa o checkout da Crossmint, o Trimmy compartilha o e-mail, a carteira de destino, o valor solicitado e a prova de titularidade da carteira necessários para preparar a ordem. A Crossmint trata as informações de pagamento e de verificação de identidade no próprio checkout. O Trimmy recebe o status da ordem e da entrega; nosso servidor para adicionar dinheiro não coleta números de cartão nem documentos de verificação.';

  @override
  String get infoPrivacyRemindersBody =>
      'Os lembretes da Carreira são agendados no seu dispositivo com a sua permissão. Você pode mudar a preferência de lembretes no Trimmy ou desativar as notificações nas configurações do dispositivo. As atualizações de operações são opcionais em dispositivos compatíveis. Se você ativá-las, armazenamos um token de notificação do dispositivo e usamos o Firebase Cloud Messaging para enviar uma atualização curta quando uma ordem real é concluída. Valores e saldos não são incluídos. Você pode desativar as atualizações de operações em Configurações. Alertas sociais e de preço ainda não estão disponíveis.';

  @override
  String get infoPrivacyServicesTitle => 'Serviços e registros técnicos';

  @override
  String get infoPrivacyServicesBody =>
      'Provedores de hospedagem e de banco de dados dão suporte ao app. Serviços de dados de mercado recebem consultas sobre ativos; a Jupiter e os provedores de blockchain recebem as consultas de carteira ou de transações necessárias para operar com dinheiro real. A Privy, seu provedor de login e a Crossmint tratam as informações conforme as próprias políticas e podem processá-las em outros países. Informações de rede, horários das solicitações, identificadores e erros ajudam a prestar o serviço, limitar abusos e investigar falhas.';

  @override
  String get infoPrivacyChoicesTitle => 'Suas escolhas e registros';

  @override
  String get infoPrivacyChoicesBody =>
      'Você pode mudar as preferências de compartilhamento e de lembretes em Configurações. Sair não apaga os registros do servidor. Encerrar uma conta desativa o acesso, mas não apaga o histórico dela, não exclui sua conta no provedor, não move ativos nem remove dados da blockchain. Limpar os dados do app pode remover o progresso local e as informações de acesso; antes disso, confirme que você consegue recuperar uma carteira com saldo.';

  @override
  String get infoPrivacyRequestsBody =>
      'Fale com @trimmyhq no X para perguntar sobre acesso, correção ou exclusão de informações mantidas pelo Trimmy. Peça uma conversa privada e não publique credenciais nem documentos pessoais abertamente. Talvez precisemos verificar a solicitação. Os registros dos provedores seguem as próprias políticas; o Trimmy não pode excluir registros da blockchain.';

  @override
  String get infoPrivacyProvidersTitle =>
      'Políticas de privacidade dos provedores';

  @override
  String get infoTermsHeading => 'Uso do Trimmy.';

  @override
  String get infoTermsIntro =>
      'O Trimmy combina uma simulação de trading com um modo separado de dinheiro real. Estes termos descrevem o app como ele funciona hoje. Os recursos continuam em desenvolvimento.';

  @override
  String get infoTermsPracticeBody =>
      'Saldos e ordens de treino são simulados. Trims, sequências e cargos da Carreira registram o progresso no jogo; não podem ser sacados como dinheiro. O treino pode usar dados de exemplo ou dados de referência do mercado. Concluir uma atividade não comprova que investir é adequado para você, e os comentários de outros usuários são opiniões deles. O conteúdo educativo não é consultoria personalizada de investimentos, jurídica ou tributária.';

  @override
  String get infoTermsRealMoneyTitle => 'Dinheiro real';

  @override
  String get infoTermsRealMoneyBody =>
      'O modo Real usa uma carteira na rede principal (mainnet) da Solana e as ações tokenizadas compatíveis. Uma ordem pode movimentar ativos reais quando você a revisa e confirma. Confira o ativo, o valor, as taxas e o destino antes de aprovar. Uma cotação é uma estimativa que pode expirar; uma ordem enviada ou pendente não é uma operação confirmada. Por enquanto, o histórico mostra os valores das cotações revisadas, não um extrato completo das execuções finais, das taxas ou das transferências externas.';

  @override
  String get infoTermsTokenizedBody =>
      'As ações tokenizadas estão sujeitas aos termos do emissor e não dão necessariamente os mesmos direitos que ter ações da empresa diretamente. Os preços podem cair, a liquidez pode desaparecer e falhas do emissor, da rede ou dos provedores podem causar perdas. O Trimmy não promete retornos nem execução a um preço exibido.';

  @override
  String get infoTermsFundingTitle => 'Adicionar dinheiro à sua carteira';

  @override
  String get infoTermsFundingBody =>
      'Envie apenas USDC ou SOL compatíveis para o endereço exibido, na rede Solana. Confira o endereço e a rede antes de enviar; uma transferência concluída na blockchain não pode simplesmente ser desfeita pelo Trimmy. Você também precisa de SOL para as taxas de rede. Por enquanto, o checkout com cartão da Crossmint é um ambiente de teste: os fundos de teste não servem para operações na mainnet. A disponibilidade fora do ambiente de teste, as formas de pagamento, a verificação e as taxas dependem do provedor.';

  @override
  String get infoTermsAccessTitle => 'Acesso à conta';

  @override
  String get infoTermsAccessBody =>
      'Proteja sua forma de entrar e revise com atenção as solicitações da carteira. Nunca compartilhe uma chave privada, frase de recuperação ou código de acesso de uso único com o suporte. Esta versão ainda não oferece saques nem exportação da carteira no app. Encerrar sua conta não saca seus ativos. Resolva o acesso à carteira antes de encerrar uma conta ou remover o app de um dispositivo com saldo.';

  @override
  String get infoTermsEligibilityTitle => 'Elegibilidade e outros serviços';

  @override
  String get infoTermsEligibilityBody =>
      'Você precisa cumprir os requisitos aplicáveis dos emissores de ativos e dos provedores de serviço, incluindo restrições de localização e de elegibilidade. Ver um ativo ou obter uma cotação não significa que você é elegível. Privy, Crossmint, provedores de trading e emissores de ativos têm termos próprios. O Trimmy não promete disponibilidade em todos os países.';

  @override
  String get infoTermsCommunityTitle => 'Uso da comunidade';

  @override
  String get infoTermsCommunityBody =>
      'Compartilhe comentários que você tem o direito de publicar. Não se passe por outras pessoas, não exponha informações privadas, não manipule o mercado, não assedie usuários nem interfira em contas e serviços. Há configurações de compartilhamento e ferramentas de bloqueio e denúncia para comentários e interações da comunidade.';

  @override
  String get infoTermsAvailabilityTitle => 'Disponibilidade e dúvidas';

  @override
  String get infoTermsAvailabilityBody =>
      'Dados de mercado, cotações, notificações e a confirmação da rede podem atrasar ou ficar indisponíveis. Os recursos e estes avisos podem mudar conforme o desenvolvimento continua. Nada aqui remove direitos que não possam ser excluídos pela legislação aplicável. Fale com @trimmyhq no X para pedir ajuda ou tirar dúvidas sobre estes termos.';

  @override
  String get settingsReminders => 'Lembretes';

  @override
  String get settingsAccountSection => 'Conta';

  @override
  String get settingsSignInDetail => 'Entre para manter seu progresso.';

  @override
  String get settingsHandle => 'Nome de usuário';

  @override
  String get settingsYourTrader => 'Seu trader';

  @override
  String get settingsChooseCharacter => 'Escolha um personagem';

  @override
  String get settingsEmail => 'E-mail';

  @override
  String get settingsSignInMethods => 'Formas de entrar';

  @override
  String get settingsSignInMethodsUnavailable =>
      'Forma de entrar indisponível.';

  @override
  String get settingsSignInMethodEmail => 'E-mail';

  @override
  String get settingsSignOut => 'Sair';

  @override
  String get settingsNotificationsSection => 'Notificações';

  @override
  String get settingsNotificationGroupMarket => 'Mercado';

  @override
  String get settingsNotificationGroupCareer => 'Carreira';

  @override
  String get settingsNotificationGroupSocial => 'Social';

  @override
  String get settingsNotificationGroupAccount => 'Conta';

  @override
  String get settingsNotificationOpen => 'Abertura de Wall Street';

  @override
  String get settingsNotificationOpenDetail => 'Quando Wall Street abre.';

  @override
  String get settingsNotificationClose => 'Fechamento de Wall Street';

  @override
  String get settingsNotificationCloseDetail => 'Quando Wall Street fecha.';

  @override
  String get settingsNotificationEvents => 'Eventos das minhas ações';

  @override
  String get settingsNotificationEventsDetail =>
      'Novidades que afetam as ações que você tem.';

  @override
  String get settingsNotificationPrices => 'Alertas de preço';

  @override
  String settingsNotificationPricesDetail(String small, String large) {
    return 'Variações de $small ou $large nas ações que você segue.';
  }

  @override
  String get settingsNotificationStreak => 'Lembrete de sequência';

  @override
  String get settingsNotificationStreakDetail =>
      'Quando sua sequência estiver em risco.';

  @override
  String get settingsNotificationMissions => 'Missões';

  @override
  String get settingsNotificationMissionsDetail =>
      'Novas missões e seu progresso.';

  @override
  String get settingsNotificationPromotions => 'Promoções';

  @override
  String get settingsNotificationPromotionsDetail =>
      'Quando você conquista um novo cargo.';

  @override
  String get settingsNotificationLeague => 'Liga';

  @override
  String get settingsNotificationLeagueDetail =>
      'Resultados da liga e mudanças de posição.';

  @override
  String get settingsNotificationFriends => 'Amigos';

  @override
  String get settingsNotificationFriendsDetail =>
      'Operações e motivos dos seus amigos.';

  @override
  String get settingsNotificationTrades => 'Atualizações de operações';

  @override
  String get settingsNotificationTradesDetail =>
      'Quando uma ordem com dinheiro real é concluída.';

  @override
  String get settingsNotificationNews => 'Novidades do Trimmy';

  @override
  String get settingsNotificationNewsDetail => 'Notícias e melhorias do app.';

  @override
  String get settingsNotAvailableYet => 'Ainda não disponível.';

  @override
  String get settingsQuietHours => 'Horário de silêncio';

  @override
  String settingsQuietHoursRange(String start, String end) {
    return 'Das $start às $end';
  }

  @override
  String get settingsEditQuietHours => 'Editar horário de silêncio';

  @override
  String get settingsPreferencesSection => 'Preferências';

  @override
  String get settingsSound => 'Som';

  @override
  String get settingsSoundDetail => 'Sons nos momentos importantes.';

  @override
  String get settingsHaptics => 'Vibração';

  @override
  String get settingsHapticsDetail => 'Pequenas vibrações ao tocar.';

  @override
  String get settingsAnimations => 'Animações';

  @override
  String get settingsAnimationsLimited =>
      'Limitadas pela configuração do seu celular.';

  @override
  String get settingsAnimationsDetail => 'Movimento e comemorações.';

  @override
  String get settingsReduceMotion => 'Reduzir movimento';

  @override
  String get settingsReduceMotionOn =>
      'Ativado. Segue a configuração do seu celular.';

  @override
  String get settingsReduceMotionOff =>
      'Desativado. Segue a configuração do seu celular.';

  @override
  String get settingsPaperLimit => 'Limite de dinheiro de treino';

  @override
  String get settingsResetPaper => 'Reiniciar treino';

  @override
  String get settingsResetPaperBusy => 'Reiniciando sua mesa de treino.';

  @override
  String get settingsResetPaperPending =>
      'O reinício que você confirmou ainda não terminou.';

  @override
  String get settingsResetPaperDetail =>
      'Apague suas operações de treino e comece de novo.';

  @override
  String get settingsResetPaperTitle => 'Reiniciar sua mesa de treino?';

  @override
  String get settingsResetPaperBody =>
      'Isso começa uma mesa de treino nova. Os comprovantes anteriores continuam no seu histórico. Sua Carreira, seus Trims, seu cargo, sua sequência e seu dinheiro não mudam.';

  @override
  String get settingsResetPaperPhrase => 'reiniciar minha mesa';

  @override
  String settingsResetPaperInstruction(String phrase) {
    return 'Digite “$phrase” para continuar.';
  }

  @override
  String settingsResetPaperFieldLabel(String phrase) {
    return 'Frase de confirmação. Digite $phrase.';
  }

  @override
  String get settingsResetPaperFieldTitle => 'Frase de confirmação';

  @override
  String get settingsResetPaperConfirm => 'Reiniciar mesa';

  @override
  String get settingsResetPaperDoneTitle => 'Mesa de treino reiniciada';

  @override
  String settingsResetPaperDone(String amount) {
    return 'Sua mesa está pronta com $amount em dinheiro de treino.';
  }

  @override
  String settingsResetPaperDoneNewer(String amount) {
    return 'As operações mais recentes foram mantidas. Seu saldo é de $amount em dinheiro de treino.';
  }

  @override
  String get settingsResetPaperFailed =>
      'Sua mesa de treino não foi reiniciada. Tente de novo.';

  @override
  String get settingsResetPaperStale =>
      'Sua mesa de treino mudou e foi atualizada. Confira e confirme o reinício de novo.';

  @override
  String get settingsResetPaperNotNeeded =>
      'Sua mesa de treino já está zerada. Nada foi apagado.';

  @override
  String get settingsResetPaperOffline =>
      'Você está sem conexão. Seu pedido de reinício foi salvo exatamente como está para tentar de novo com segurança.';

  @override
  String get settingsResetPaperTimeout =>
      'O reinício demorou demais para ser confirmado. Seu pedido foi salvo exatamente como está para tentar de novo com segurança.';

  @override
  String get settingsResetPaperAccountRequired =>
      'Sua mesa de treino precisa de uma nova sessão para concluir o reinício.';

  @override
  String get settingsResetPaperRateLimited =>
      'Os reinícios do treino são limitados. Tente este pedido salvo de novo mais tarde.';

  @override
  String get settingsResetPaperUnavailable =>
      'Não foi possível confirmar o reinício. Seu pedido foi salvo exatamente como está para tentar de novo com segurança.';

  @override
  String get settingsResetPaperRejected =>
      'Sua mesa de treino não foi reiniciada. Atualize sua mesa e tente de novo.';

  @override
  String get settingsMoneySection => 'Dinheiro';

  @override
  String get settingsMoneyCardOrCrypto => 'Cartão ou cripto';

  @override
  String get settingsMoneyComingSoon =>
      'Operar com dinheiro real chega mais tarde.';

  @override
  String get settingsMoneyUnavailable =>
      'Os recursos de dinheiro não estão disponíveis para esta conta.';

  @override
  String get settingsCurrency => 'Moeda';

  @override
  String get settingsDepositPartner => 'Parceiro de depósito';

  @override
  String get settingsFees => 'Taxas';

  @override
  String get settingsCountryCheck => 'Verificação de país';

  @override
  String get settingsBankAccounts => 'Contas bancárias';

  @override
  String get settingsCards => 'Cartões';

  @override
  String get settingsWallet => 'Carteira';

  @override
  String get settingsWalletNoDetails => 'Ainda não há detalhes da carteira.';

  @override
  String get settingsWalletComingSoon =>
      'As ferramentas da carteira chegam mais tarde.';

  @override
  String get settingsWalletUnavailable =>
      'As ferramentas da carteira não estão disponíveis para esta conta.';

  @override
  String get settingsCheckWallet => 'Ver carteira';

  @override
  String get settingsBackUpWallet => 'Fazer backup da carteira';

  @override
  String get settingsBackUpWalletDetail => 'Mantenha o acesso fora do Trimmy.';

  @override
  String get settingsPrivacySection => 'Privacidade';

  @override
  String get settingsHoldingsVisibility => 'Quem vê meus investimentos';

  @override
  String get settingsVisibilityFriends => 'Amigos';

  @override
  String get settingsVisibilityEveryone => 'Todos';

  @override
  String get settingsVisibilityNobody => 'Ninguém';

  @override
  String get settingsDownloadData => 'Baixar meus dados';

  @override
  String get settingsSupportSection => 'Suporte';

  @override
  String get settingsSendFeedback => 'Enviar opinião';

  @override
  String get settingsReportBug => 'Relatar um erro';

  @override
  String get settingsReportBugDetail => 'A versão do seu app será anexada.';

  @override
  String get settingsLegalSection => 'Informações legais';

  @override
  String get settingsRiskNotice => 'Aviso de riscos';

  @override
  String get settingsAboutTokenizedStocks => 'Sobre as ações tokenizadas';

  @override
  String get settingsAboutTokenizedStocksDetail => 'O que são e o que não são.';

  @override
  String get settingsAccountClosureSection => 'Encerramento da conta';

  @override
  String get settingsCloseAccount => 'Encerrar conta';

  @override
  String get settingsCloseAccountDetail =>
      'Veja o que acontece com seus registros e sua carteira.';

  @override
  String get sendErrorCheckInput => 'Confira o endereço e o valor.';

  @override
  String get sendErrorSelf =>
      'Essa é a sua própria carteira. Digite outro endereço.';

  @override
  String get sendErrorNotWallet =>
      'Esse endereço não é uma carteira. Pode ser uma conta de token ou um programa. Peça o endereço da carteira.';

  @override
  String get sendErrorDestinationFrozen =>
      'Essa carteira não pode receber este token agora.';

  @override
  String get sendErrorAssetUnsupported =>
      'Este token não pode ser enviado pelo Trimmy.';

  @override
  String get sendErrorNotTransferable =>
      'Este token tem regras de transferência que impedem o envio pelo Trimmy.';

  @override
  String get sendErrorAssetPaused =>
      'O emissor pausou as transferências por enquanto.';

  @override
  String get sendErrorAssetFrozen =>
      'Este token está congelado na sua carteira. Fale com o emissor.';

  @override
  String get sendErrorInsufficient => 'Você não tem tudo isso para enviar.';

  @override
  String get sendErrorAddSol =>
      'Adicione um pouco de SOL para cobrir a taxa de rede.';

  @override
  String sendErrorLeaveSol(String amount) {
    return 'Deixe pelo menos $amount SOL ou envie tudo.';
  }

  @override
  String sendErrorTooSmall(String amount) {
    return 'Uma carteira nova precisa de pelo menos $amount SOL para ser aberta.';
  }

  @override
  String get sendErrorCheckFailed =>
      'Este envio não passou na verificação. Nada foi enviado.';

  @override
  String get sendErrorReviewExpired => 'Esta revisão expirou. Revise de novo.';

  @override
  String get sendErrorPrevious =>
      'Confira seu envio anterior antes de começar outro.';

  @override
  String get sendErrorMismatch =>
      'Esta transação não corresponde ao que você revisou. Nada foi enviado.';

  @override
  String get sendErrorStorage =>
      'Permita o armazenamento do dispositivo para poder recuperar seu envio.';

  @override
  String get sendErrorBusy => 'Aguarde um momento e tente de novo.';

  @override
  String get sendErrorCancelled =>
      'A assinatura foi cancelada. Nada foi enviado.';

  @override
  String get sendErrorPaused =>
      'Os envios estão pausados agora. Tente mais tarde.';

  @override
  String get sendErrorGeneric =>
      'Não foi possível conectar para enviar. Tente de novo.';

  @override
  String get sendRecoveryFailed =>
      'Não foi possível verificar seu envio anterior. Tente verificar de novo.';

  @override
  String get sendEnterAddress => 'Digite um endereço de carteira Solana.';

  @override
  String get sendEnterAmount => 'Digite um valor.';

  @override
  String sendHaveReady(String amount) {
    return 'Você tem $amount para enviar.';
  }

  @override
  String get sendTitle => 'Enviar';

  @override
  String get sendCheckPrevious => 'Verificar envio anterior';

  @override
  String get sendNothingTitle => 'Ainda não há nada para enviar';

  @override
  String get sendNothingBody =>
      'Primeiro adicione dinheiro ou compre uma ação. Daqui você pode enviar tudo o que estiver na sua carteira.';

  @override
  String get sendHeading => 'Enviar para uma carteira Solana';

  @override
  String get sendWarning =>
      'Envie só para um endereço Solana. Os envios não podem ser desfeitos.';

  @override
  String get sendWhatLabel => 'O que enviar';

  @override
  String get sendAssetUsdc => 'Dólares americanos (USDC)';

  @override
  String get sendRecipientLabel => 'Endereço da carteira de destino';

  @override
  String get sendPaste => 'Colar';

  @override
  String get sendSharesLabel => 'Ações';

  @override
  String sendAmountLabel(String symbol) {
    return 'Valor ($symbol)';
  }

  @override
  String sendReadyToSend(String amount) {
    return 'Disponível para enviar: $amount';
  }

  @override
  String sendMaxKeepsSol(String amount) {
    return 'O máximo deixa $amount SOL para você continuar pagando as taxas de rede.';
  }

  @override
  String get sendReview => 'Revisar envio';

  @override
  String get sendReviewTitle => 'Revise seu envio';

  @override
  String get sendYouSend => 'Você envia';

  @override
  String get sendTheyReceive => 'O destinatário recebe, após a taxa do emissor';

  @override
  String get sendNetworkFee => 'Taxa de rede';

  @override
  String sendOpensAccount(String symbol) {
    return 'Abre a conta de $symbol do destinatário (uma vez)';
  }

  @override
  String get sendToWallet => 'Para esta carteira Solana';

  @override
  String get sendCheckEvery =>
      'Confira cada caractere. Os envios não podem ser desfeitos, e o Trimmy não consegue recuperar dinheiro enviado para um endereço errado.';

  @override
  String get sendNow => 'Enviar agora';

  @override
  String get sendEdit => 'Editar';

  @override
  String get sendResultSent => 'Enviado';

  @override
  String get sendResultSending => 'Enviando';

  @override
  String get sendResultFailed => 'Não foi concluído';

  @override
  String get sendResultExpired => 'O envio expirou';

  @override
  String get sendResultChecking => 'Ainda confirmando';

  @override
  String get sendBodySent => 'Foi confirmado na Solana.';

  @override
  String get sendBodySending => 'Isso costuma levar alguns segundos.';

  @override
  String get sendBodyFailed =>
      'A Solana recusou. Só a taxa de rede foi cobrada.';

  @override
  String get sendBodyExpired =>
      'Esta transação expirou sem confirmação. Você pode revisar um novo envio.';

  @override
  String get sendBodyChecking =>
      'Ainda estamos verificando este envio. Não envie de novo.';

  @override
  String get sendViewSolscan => 'Ver no Solscan';

  @override
  String get sendCloseFailed => 'Este envio está salvo. Tente fechar de novo.';

  @override
  String get reminderDailyLabel => 'Em dias úteis';

  @override
  String get reminderDailyCaption =>
      'Por volta das 19h, quando houver trabalho esperando.';

  @override
  String get reminderOccasionalLabel => 'Algumas vezes por semana';

  @override
  String get reminderOccasionalCaption =>
      'Segunda, quarta e sexta, por volta das 19h.';

  @override
  String get reminderOffLabel => 'Sem lembretes';

  @override
  String get reminderOffCaption => 'Eu volto por conta própria.';

  @override
  String get reminderNotificationTitle => 'Sua mesa está te esperando';

  @override
  String get reminderNotificationBody =>
      'Sua próxima tarefa está te esperando na sua mesa.';

  @override
  String reminderNotificationDay(int day, String title) {
    return 'Dia $day: $title';
  }

  @override
  String get pushErrorNotificationsOff =>
      'As notificações estão desativadas nos ajustes do dispositivo.';

  @override
  String get pushErrorUpdate =>
      'Não foi possível atualizar as notificações. Tente de novo.';

  @override
  String get pushErrorTurnOff =>
      'Não foi possível desativar os alertas. Tente de novo quando estiver on-line.';

  @override
  String get pushErrorConnect =>
      'Não foi possível conectar as notificações. Tente de novo.';

  @override
  String get signInResendCode => 'Enviar um novo código';

  @override
  String signInResendIn(int seconds) {
    return 'Reenviar em $seconds s';
  }

  @override
  String get appCloseAccountClosing => 'Encerrando sua conta…';

  @override
  String get appCloseAccountFailed =>
      'Sua conta não foi encerrada. Tente de novo.';
}

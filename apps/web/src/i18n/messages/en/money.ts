import type {AreaMessages} from '../types';

/**
 * Own money ("Real mode"): the Real balance card and holdings on the Desk,
 * Add money (crypto deposit), Fast buy, Send, the real-money order panel
 * (entry, issuer terms, review, result), trade history, and the trading
 * reasons and market hours other screens show for tokens.
 *
 * Token symbols (USDC, SOL, AAPLx), Solana, Solscan, wallet addresses and
 * issuer names stay as they are. Issuer warnings, summaries, holder rights,
 * excluded regions and eligibility statements come from the API.
 * Amounts arrive already formatted for the reader's region.
 */
export default {
  // Shared across the Real screens.
  'money.realMoney': 'Real money',
  /** Mode names on the Paper/Real switch and badges ("Paper" is Practice mode). */
  'money.mode.real': 'Real',
  'money.mode.paper': 'Paper',
  'money.mode.switchToPaper': 'Switch to paper mode',
  'money.mode.switchToReal': 'Switch to real money mode',
  'money.addMoney': 'Add money',
  /** Accessible name of a sheet's × button. */
  'money.close': 'Close',
  /** Fills an amount field with everything available. */
  'money.max': 'Max',
  'money.checkingWallet': 'Checking your wallet…',
  'money.checkingTrading': 'Checking trading…',
  'money.checkingLastOrder': 'Checking your last order…',
  /** A Real token's market state as a sentence: {status} is a short line such as "Closed · opens Mon 1:05 AM". */
  'money.market.sentence': '{status}.',
  'money.error.signInAgain': 'Sign in again to use your wallet.',

  // Desk: the Real balance card.
  'money.desk.label': 'Real money balance',
  'money.desk.totalBalance': 'Total balance',
  'money.desk.cashBalance': 'Cash balance',
  /** Under the total: {cash} is USDC cash in dollars, {stocks} the value of stock tokens. */
  'money.desk.split': '{cash} cash · {stocks} in stocks',
  'money.desk.createWallet': 'Create your wallet to add money.',
  'money.desk.usdcAvailable': 'USDC available',
  'money.desk.updating': 'Updating balance…',
  /** {amount} is a SOL amount; SOL pays Solana network fees. */
  'money.desk.solForFees': '{amount} SOL for fees',
  'money.desk.checkingSol': 'Checking SOL…',
  /** Accessible name of the USDC and SOL coin pictures. */
  'money.desk.cashMarks': 'USDC and SOL',
  /** {amount} is a USDC amount, such as "25 USDC". */
  'money.desk.readyToTrade': '{amount} is ready to trade. The rest is in another token account.',
  'money.desk.fastBuy': 'Fast buy',
  'money.desk.send': 'Send',

  // Desk: Real holdings.
  'money.holdings.title': 'Holdings',
  /** Opens the list of real-money trades. */
  'money.holdings.history': 'History',
  'money.holdings.walletStartsHere': 'Your wallet starts here',
  'money.holdings.emptyTitle': 'No stocks yet',
  'money.holdings.emptyBody': 'Your first stock starts here.',
  'money.holdings.explore': 'Explore stocks',
  /** After the shares held: the part that can be sold now. {amount} is a number of shares. */
  'money.holdings.readyToSell': '{amount} ready to sell',
  'money.holdings.marketValue': 'Market value',
  'money.holdings.valueUnavailable': 'Value unavailable',

  // Add money sheet (crypto deposit; card payments are not open yet).
  'money.fund.title': 'Add money',
  'money.fund.methods': 'How to add money',
  'money.fund.crypto': 'Crypto',
  'money.fund.recommended': 'Recommended',
  'money.fund.card': 'Card',
  'money.fund.comingSoon': 'Coming soon',
  'money.fund.cardSoonTitle': 'Card payments are coming soon.',
  'money.fund.cardSoonBody': 'For now, add money with crypto: send USDC to your wallet on Solana.',
  'money.fund.useCrypto': 'Use crypto',
  'money.fund.walletTitle': 'A wallet for your money',
  'money.fund.signInBody': 'Sign in to create your own Solana wallet and add money.',
  'money.fund.creating': 'Creating…',
  'money.fund.createWallet': 'Create wallet',
  'money.fund.setupUnavailable': 'Wallet setup isn’t available in this browser right now.',
  'money.fund.walletUnconfirmed': 'We couldn’t confirm your wallet.',
  'money.fund.offline': 'You’re offline. Reconnect to load your wallet.',
  'money.fund.walletFailed': 'Couldn’t load your wallet.',
  'money.fund.createFailed': 'Couldn’t create your wallet. Try again.',
  'money.fund.copyFailed': 'Couldn’t copy the address. Select it and copy it instead.',
  /** Accessible name of the QR code. {address} is the wallet address. */
  'money.fund.qrLabel': 'Solana deposit address {address}',
  'money.fund.sendOnly': 'Send only USDC or SOL to this account on the Solana network.',
  'money.fund.cashNote': 'USDC is your cash for trades. A little SOL pays network fees.',
  'money.fund.copied': 'Copied',
  'money.fund.copy': 'Copy address',
  'money.fund.showAddress': 'Show full address',

  // Fast buy sheet.
  'money.fastBuy.title': 'Fast buy',
  'money.fastBuy.close': 'Close fast buy',
  'money.fastBuy.search': 'Search a name or ticker',
  'money.fastBuy.tradingFailed': 'Trading couldn’t connect.',
  'money.fastBuy.retry': 'Retry',
  'money.fastBuy.noMatch': 'No tradeable stock matches that.',
  'money.fastBuy.noneAvailable': 'No stocks available to buy right now.',
  'money.fastBuy.marketSlow': 'The Market is taking a moment.',
  'money.fastBuy.finding': 'Finding companies…',
  'money.fastBuy.noMatches': 'No matches yet.',

  // Issuers (the companies that issue tokenized stocks).
  /** Stands in for an issuer whose name is unknown, before " · AAPLx". */
  'money.issuer.fallbackName': 'Issuer',
  'money.issuer.otherName': 'Other issuer',
  /** Accessible name of the issuer card. {issuer} is the issuer's name. */
  'money.issuer.label': '{issuer} issuer terms',
  /** {regions} is the API's list of places, separated by commas. */
  'money.issuer.excluded': 'Not for residents of {regions}',
  /** {fee} is a percentage, such as "0.5%". */
  'money.issuer.fee': 'Issuer fee: {fee} on every buy and sell',
  'money.issuer.terms': 'Issuer terms ↗',
  /** The eligibility tick for servers too old to send the issuer's own statement. */
  'money.issuer.legacyAttestation': 'I’m eligible under the issuer’s terms.',

  // Order panel: entry.
  'money.order.signedOutTitle': 'Trade with your own money.',
  'money.order.signedOutBody': 'Sign in to use your wallet.',
  'money.order.label': 'Real-money order',
  /** Leaves Real mode for this company and opens the Paper (practice) order. */
  'money.order.practice': 'Practice in Paper',
  'money.order.accountChangedTitle': 'Your account changed',
  'money.order.accountChangedBody': 'Reopen trading after signing in.',
  'money.order.recoveryTitle': 'Let’s check your last order',
  'money.order.whenConnected': 'Try again when you’re connected.',
  'money.order.connectFailedTitle': 'Trading couldn’t connect',
  'money.order.pausedTitle': 'Trading is temporarily paused',
  'money.order.pausedBody': 'Your wallet and holdings are still here.',
  'money.order.notTradableTitle': 'This token isn’t tradable here yet',
  'money.order.chooseAnother': 'Choose another stock to trade.',
  'money.order.checkingBalance': 'Checking balance…',
  /** {amount} is USDC or shares with their symbol, such as "25 USDC". */
  'money.order.available': '{amount} available',
  /** Heading of the order panel. {symbol} is the token, such as AAPLx. */
  'money.order.heading': '{side, select, sell {Sell {symbol}} other {Buy {symbol}}}',
  'money.order.buyInstead': 'Buy instead',
  'money.order.sellInstead': 'Sell instead',
  'money.order.youSell': 'You sell',
  'money.order.youPay': 'You pay',
  /** Shown before a dollar amount being typed (USDC). */
  'money.order.dollarSign': '$',
  'money.order.partlyElsewhere': 'Some of your {symbol} is in another token account. Only {amount} {symbol} can be sold here.',
  'money.order.limit': 'Order limit: {amount}',
  'money.order.maxCapped': 'Max capped at the order limit of {amount}.',
  /** {percent} is the quick amount chosen, such as "50%". */
  'money.order.percentCapped': '{percent} capped at the order limit of {amount}.',
  'money.order.minimum': 'Orders start at {amount}.',
  'money.order.createWallet': 'Create your wallet to continue.',
  'money.order.checkingPrice': 'Checking price and fees…',
  'money.order.review': '{side, select, sell {Review sell} other {Review buy}}',
  'money.order.confirmTermsFirst': 'Confirm the issuer terms first.',
  'money.order.invalidAmount': '{side, select, sell {Enter a valid share amount.} other {Enter a valid USDC amount.}}',
  'money.order.overLimit': 'Up to {amount} per order.',
  'money.order.underMinimum': 'Orders for this token start at {amount}.',

  // Order panel: review before signing.
  'money.review.title': '{side, select, sell {Review your sell} other {Review your buy}}',
  'money.review.youPay': 'You pay',
  'money.review.youReceive': 'You receive ≈',
  'money.review.minimumReceived': 'Minimum received',
  'money.review.networkFees': 'Network + account fees',
  /** At most {amount} (of SOL). */
  'money.review.atMost': '≤ {amount}',
  /** The platform's fee on the swap from USDC to the token or back. */
  'money.review.swapFee': 'Swap fee',
  'money.review.price': 'Price',
  'money.review.fixedQuote': 'Fixed quote from a market maker',
  'money.review.returned': 'Returned to your wallet',
  'money.review.returnedValue': 'Up to {amount} from your wrapped SOL account',
  'money.review.solBack': 'SOL back ≈',
  'money.review.issuer': 'Issuer',
  'money.review.issuerFee': 'Issuer fee',
  'money.review.delivery': 'Delivery',
  'money.review.deliveryValue': 'By the market maker at fill',
  'money.review.closesWrappedSol': 'This order closes your existing wrapped SOL account and returns it to your wallet as SOL.',
  'money.review.temporaryAccount': 'The route uses a temporary token account that closes within the same transaction.',
  'money.review.makerFills': 'A market maker fills this order at the fixed price above and pays the network fee.',
  'money.review.makerDelivers': 'The market maker creates your tokens just in time, after you sign, and delivers them when the order fills. The fill is all or nothing: you get the full amount or the order doesn’t go through.',
  /** A countdown, once a second. */
  'money.review.expiresIn': 'Quote expires in {seconds}s',
  'money.review.expired': 'Quote expired. Get a new review.',
  'money.review.waitingWallet': 'Waiting for your wallet…',
  'money.review.confirming': 'Confirming…',
  'money.review.confirm': '{side, select, sell {Confirm sell} other {Confirm buy}}',
  'money.review.edit': 'Edit amount',
  /** "Confirm" is the button above. */
  'money.review.disclosure': 'Confirm signs this exact order with your Trimmy wallet. Amounts are the reviewed quote; the transaction shows the final amounts.',

  // Order panel: result.
  'money.result.confirmedTitle': 'Trade confirmed',
  'money.result.pendingTitle': 'Confirming your trade',
  'money.result.expiredTitle': 'Quote expired',
  'money.result.failedTitle': 'Trade didn’t complete',
  'money.result.confirmedBody': 'Your order is confirmed on Solana.',
  'money.result.pendingBody': 'You can close this. Reopen the trade to check its status.',
  'money.result.expiredBody': 'Get a fresh price to continue.',
  'money.result.failedBody': 'Your order wasn’t filled.',
  'money.result.freshPrice': 'Get fresh price',
  /** A trade as a record (a buy or a sell of {symbol}), on the result and in history. */
  'money.trade.label': '{side, select, sell {Sell {symbol}} other {Buy {symbol}}}',
  /** Links to Solscan, the Solana explorer. */
  'money.explorer.walletActivity': 'View wallet activity ↗',
  'money.explorer.transaction': 'View transaction ↗',

  // Order notices: why an order step stopped. Every one is shown in the order panel.
  'money.notice.verifiedQuote': 'Couldn’t get a verified quote. Try again.',
  'money.notice.checkingResult': 'Checking the result. Your order won’t be sent twice.',
  'money.notice.storage': 'Allow browser storage so Trimmy can keep track of this order. No order was sent.',
  'money.notice.priceExpired': 'That price expired. Get a fresh quote. No order was sent.',
  'money.notice.accountChanged': 'Your account changed. No order was sent.',
  'money.notice.walletConnecting': 'Your wallet is still connecting. Try again in a moment. No order was sent.',
  'money.notice.walletChanged': 'Your wallet changed. Get a fresh quote. No order was sent.',
  'money.notice.signingTimeout': 'Your wallet didn’t answer in time. No order was sent.',
  'money.notice.signingFailed': 'Signing didn’t finish. No order was sent.',
  'money.notice.reconnecting': 'Reconnecting to check your order…',

  // Order refusals from the trading API, by code.
  /** The API says how many seconds to wait. The English always said "seconds" except for 1. */
  'money.orderError.busySeconds': '{seconds, plural, one {Quotes are busy. Try again in # second.} other {Quotes are busy. Try again in # seconds.}}',
  'money.orderError.busy': 'Quotes are busy. Try again in a moment.',
  'money.orderError.addUsdc': 'Add USDC to your Solana wallet first.',
  'money.orderError.addSol': 'Add SOL to cover network and account fees.',
  'money.orderError.insufficientHoldings': 'You don’t have enough of this token to sell.',
  'money.orderError.tradeLimit': 'This order is above the current trade limit.',
  'money.orderError.updateApp': 'Reload Trimmy to review the issuer terms before trading.',
  'money.orderError.termsRequired': 'Confirm the issuer terms to continue.',
  'money.orderError.walletRequired': 'Create your wallet to continue.',
  'money.orderError.orderPending': 'Your previous trade is still confirming.',
  'money.orderError.quoteExpired': 'That price expired. Get a fresh quote.',
  'money.orderError.noRoute': 'No route for this order right now. Try another amount.',
  'money.orderError.marketClosed': 'This stock trades while US markets are open. Try again then.',
  'money.orderError.belowMinimum': 'This order is under the market maker’s minimum. Try a larger amount.',
  'money.orderError.priceOffMarket': 'That price is too far from the market right now. Try again shortly or a smaller amount.',
  'money.orderError.feeTooHigh': 'The fees are too high for this order. Try later.',
  'money.orderError.freshQuote': 'This order needs a fresh quote.',
  /** "Version" is one of a company's tokens, from another issuer. */
  'money.orderError.marketInputInvalid': 'Trimmy can’t trade this token right now. Choose another version or company.',
  'money.orderError.liveUnavailable': 'Trading couldn’t connect. Try again.',
  'money.orderError.generic': 'Couldn’t complete this step. Try again.',

  // When a token trades. {when} is a phrase from the money.market.when keys.
  'money.market.open247': 'Open 24/7',
  'money.market.openWeekends': 'Open now, including weekends',
  'money.market.openNow': 'Open now',
  'money.market.issuerPaused': 'Paused by the issuer',
  'money.market.marketPaused': 'Paused by the market',
  'money.market.pausedResumes': 'Paused · resumes {when}',
  'money.market.shortPause': 'Short pause',
  'money.market.shortPauseResumes': 'Short pause · resumes {when}',
  'money.market.closed': 'Closed',
  'money.market.closedOpens': 'Closed · opens {when}',
  'money.market.notTrading': 'Not trading right now',
  /**
   * A local time, as it follows "opens" or "resumes". {time} is a clock time
   * already formatted ("1:05 AM", "01:05"); it also works as a plural on the
   * hour shown, for "a la 1:05" against "a las 9:30". {day} is a short
   * weekday ("Mon"), {date} a short date ("Oct 5").
   */
  'money.market.when.today': '{time}',
  'money.market.when.tomorrow': 'tomorrow {time}',
  'money.market.when.weekday': '{day} {time}',
  'money.market.when.date': '{date}, {time}',
  'money.market.hours.aroundClock': 'Trades around the clock, with short pauses between US sessions.',
  'money.market.hours.weekdays': 'Trades 24 hours a day, Sunday evening to Friday evening (US Eastern).',
  'money.market.hours.regular': 'Trades during US market hours only, 9:30 AM to 4 PM Eastern on weekdays.',
  'money.market.hours.sessions': 'Trades during US market sessions only.',

  // Why a token cannot be traded right now (Market, company page, order panel).
  'money.reason.tradingPaused': 'Trading is temporarily paused.',
  'money.reason.notOffered': 'This issuer is not offered in Trimmy.',
  'money.reason.notYet': 'Not available to trade in Trimmy yet.',
  'money.reason.unavailable': 'Not available to trade in Trimmy.',
  'money.reason.opensThenChecks': 'Its market is closed. It opens {when}, then Trimmy checks it.',
  'money.reason.identityUnverified': 'Trimmy could not confirm who issued this token.',
  'money.reason.tokenRestricted': 'The issuer has restrictions on this token that Trimmy cannot accept.',
  'money.reason.lowLiquidity': 'Too little trading to buy and sell it safely.',
  'money.reason.noReviewedRoute': 'No order route passed Trimmy’s safety checks.',
  'money.reason.priceOffMarket': 'Its price is too far from the real share price.',
  'money.reason.heldBack': 'Paused while Trimmy checks this token.',
  'money.reason.notReviewed': 'Not checked yet.',
  'money.reason.marketClosed': 'Trades only while US markets are open.',
  'money.reason.awaitingReview': 'Its market is open. Trimmy is checking it before you can trade.',
  'money.reason.noMarketMakerQuote': 'No market maker is quoting it right now.',

  // Trade history (real-money orders).
  'money.history.title': 'Your trades',
  'money.history.back': '← Back to your desk',
  'money.history.loading': 'Loading your trades…',
  'money.history.emptyTitle': 'Your first trade starts here',
  'money.history.emptyBody': 'Your orders will appear here.',
  'money.history.status.pending': 'Confirming',
  'money.history.status.confirmed': 'Confirmed',
  'money.history.status.failed': 'Not completed',
  'money.history.status.expired': 'Expired',
  /** When the order was placed: {date} and {time} are already formatted. */
  'money.history.when': '{date} · {time}',
  'money.history.youPaid': 'You paid',
  'money.history.youSold': 'You sold',
  'money.history.youReceived': 'You received',
  'money.history.finalNote': 'Final amounts from the confirmed transaction.',
  'money.history.quotedOutput': 'Quoted output',
  'money.history.minimumOutput': 'Minimum output',
  'money.history.estimateNote': 'Order estimates. See the transaction for the final amounts.',
  'money.history.openStock': 'Open stock',
  'money.history.signInAgain': 'Sign in again to see your trades.',
  'money.history.loadFailed': 'Couldn’t load your trades. Try again.',
  'money.history.moreFailed': 'Couldn’t load more trades. Try again.',
  'money.history.loadingMore': 'Loading…',
  'money.history.more': 'More trades',

  // Send sheet: USDC, SOL or a stock token to another Solana wallet.
  'money.send.title': 'Send',
  'money.send.usdcName': 'US dollars (USDC)',
  'money.send.solName': 'Solana (SOL)',
  'money.send.emptyTitle': 'Nothing to send yet',
  'money.send.emptyBody': 'Add money or buy a stock first. Anything in your wallet can be sent from here.',
  'money.send.warning': 'Only send to a Solana address. Sends can’t be undone.',
  'money.send.what': 'What to send',
  'money.send.recipient': 'Recipient’s wallet address',
  'money.send.shares': 'Shares',
  /** {symbol} is USDC or SOL. */
  'money.send.amount': 'Amount ({symbol})',
  /** {amount} is a number, {symbol} the token. */
  'money.send.ready': '{amount} {symbol} ready to send',
  'money.send.solReserve': 'Max keeps {amount} SOL so you can still pay network fees.',
  'money.send.review': 'Review send',
  'money.send.youSend': 'You send',
  'money.send.theyReceive': 'They receive, after the issuer fee',
  'money.send.networkFee': 'Network fee',
  /** The one-time cost of opening the recipient's account for this token. */
  'money.send.opensAccount': 'Opens their {symbol} account (once)',
  'money.send.toWallet': 'To this Solana wallet',
  'money.send.checkAddress': 'Check every character. Sends can’t be undone, and Trimmy can’t get money back from a wrong address.',
  'money.send.sending': 'Sending…',
  'money.send.sendNow': 'Send now',
  'money.send.edit': 'Edit',
  'money.send.status.sending': 'Sending',
  'money.send.status.sent': 'Sent',
  'money.send.status.failed': 'It didn’t go through',
  'money.send.status.expired': 'Send expired',
  'money.send.status.pending': 'Still confirming',
  'money.send.body.sending': 'This usually takes a few seconds.',
  'money.send.body.sent': 'It’s confirmed on Solana.',
  'money.send.body.failed': 'Solana refused it. Only the network fee was spent.',
  'money.send.body.expired': 'This transaction expired without confirmation. You can review a new send.',
  'money.send.body.pending': 'We’re still checking this send. Don’t send it again.',
  'money.send.solscan': 'View on Solscan',
  'money.send.saved': 'This send is saved. Try closing it again.',
  'money.send.checkPrevious': 'Check previous send',
  'money.send.recoveryFailed': 'Your previous send couldn’t be checked. Try checking again.',
  'money.send.needAddress': 'Enter a Solana wallet address.',
  'money.send.needAmount': 'Enter an amount.',
  'money.send.tooMuch': 'You have {amount} {symbol} ready to send.',

  // Send refusals, by code.
  'money.sendError.checkInput': 'Check the address and the amount.',
  'money.sendError.destinationSelf': 'That’s your own wallet. Enter another address.',
  'money.sendError.notWallet': 'That address isn’t a wallet. It may be a token account or a program. Ask for the wallet address instead.',
  'money.sendError.destinationFrozen': 'That wallet can’t receive this token right now.',
  'money.sendError.assetUnsupported': 'This token can’t be sent from Trimmy.',
  'money.sendError.notTransferable': 'This token has transfer rules Trimmy can’t send with.',
  'money.sendError.assetPaused': 'Its issuer has paused transfers for now.',
  'money.sendError.assetFrozen': 'This token is frozen in your wallet. Contact its issuer.',
  'money.sendError.insufficient': 'You don’t have that much ready to send.',
  'money.sendError.addSol': 'Add a little SOL to cover the network fee.',
  /** {amount} is a SOL amount. */
  'money.sendError.leaveSol': 'Leave at least {amount} SOL, or send all of it.',
  'money.sendError.tooSmall': 'A new wallet needs at least {amount} SOL to open.',
  'money.sendError.simulation': 'This send didn’t pass its check. Nothing was sent.',
  'money.sendError.reviewExpired': 'This review expired. Review it again.',
  'money.sendError.previousSend': 'Check your previous send before starting another.',
  'money.sendError.invalidTransaction': 'This transaction doesn’t match your review. Nothing was signed.',
  'money.sendError.signatureMismatch': 'Your wallet returned a different transaction. Nothing was sent.',
  'money.sendError.storage': 'Allow device storage to keep your send recoverable.',
  'money.sendError.busy': 'One moment, then try again.',
  'money.sendError.cancelled': 'Signing was cancelled. Nothing was sent.',
  'money.sendError.signingTimeout': 'Your wallet didn’t answer in time. Nothing was sent.',
  'money.sendError.walletBusy': 'Your wallet is busy. Try again in a moment.',
  'money.sendError.paused': 'Sending is paused right now. Try again later.',
  'money.sendError.connection': 'Sending couldn’t connect. Try again.',
} as const satisfies AreaMessages<'money'>;

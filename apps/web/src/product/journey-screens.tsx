import type {ProductMarketClient} from './market-client';
import type {CareerSummary, PaperPortfolio} from './practice-client';
import {useCompanyIdentities} from './company-identity';
import type {FirstDayJourney} from './use-first-day-journey';
import {FirstOrderCelebration, GuestDeskPreserved, MoneyChoicePage, ReminderPreferencePage} from './first-day-followup';
import {SignInScreen} from './sign-in-screen';

export interface JourneyScreensProps {
  readonly journey: FirstDayJourney; readonly market: ProductMarketClient;
  readonly career: CareerSummary | null; readonly portfolio: PaperPortfolio | null;
  readonly careerLoading: boolean; readonly motion: boolean; readonly preservedExpired: boolean;
  readonly onGuest: () => Promise<void>; readonly onAccount: () => void;
  readonly onRetryEvidence: () => void; readonly onFinish: (addMoney: boolean) => Promise<void>;
}
/** One screen at a time, in mobile's order. Only the gate's named action grants guest access. */
export function JourneyScreens(props: JourneyScreensProps) {
  const {journey} = props, view = journey.view;
  const evidence = view.kind === 'celebration' ? view.evidence : null;
  const identities = useCompanyIdentities(props.market, evidence ? [evidence.assetId] : [], props.portfolio);
  if (journey.preservedNotice) return <GuestDeskPreserved expired={props.preservedExpired} onContinue={journey.acknowledgePreserved}/>;
  if (view.kind === 'gate') return <SignInScreen motion={props.motion} hasDesk entryGate onGuest={props.onGuest} onBack={() => {}} onAccount={props.onAccount}/>;
  if (view.kind === 'celebration') {
    const identity = evidence ? identities.get(evidence.assetId) : undefined;
    return <FirstOrderCelebration key={evidence?.orderId ?? 'pending'} evidence={evidence} name={identity?.name ?? null} logoUrl={identity?.imageUrl ?? null}
      career={props.career} loading={props.careerLoading} onRetry={props.onRetryEvidence}
      onContinue={() => evidence ? journey.continueAfterCelebration(evidence.orderId) : Promise.resolve()}/>;
  }
  if (view.kind === 'reminders') return <ReminderPreferencePage saved={journey.reminder} onSave={journey.saveReminder} onDone={journey.reminderDone}/>;
  if (view.kind === 'money') return <MoneyChoicePage onFinish={props.onFinish}/>;
  return null;
}

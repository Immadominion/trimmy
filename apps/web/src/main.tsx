import ReactDOM from 'react-dom/client';
import {LOAD_FAILURE, applyDocumentLanguage, startupLanguage} from './i18n/locales';

const element = document.getElementById('root');
if (!element) throw new Error('Application root is missing.');
const root = ReactDOM.createRoot(element);
// The language is known before any chunk loads; its catalog loads beside the page's own code.
const language = startupLanguage();
applyDocumentLanguage(language.locale);
const i18n = Promise.all([import('./i18n/runtime'), import('./i18n/react')])
  .then(async ([runtime, react]) => {await runtime.initI18n(language); return react.I18nRoot;});
// Recovery is independent of onboarding, guest storage and the practice API.
if (/^\/wallet-recovery\/?$/.test(window.location.pathname)) {
  void Promise.all([import('./recovery/wallet-recovery'), import('./recovery/wallet-recovery.css'), i18n])
    .then(([{WalletRecoveryPage}, , I18nRoot]) => root.render(<I18nRoot>{() => <WalletRecoveryPage />}</I18nRoot>)).catch(unavailable);
} else {
  void Promise.all([import('./product-entry'), i18n])
    .then(([{ProductApp}, I18nRoot]) => root.render(<I18nRoot title="common.appTitle">{() => <ProductApp />}</I18nRoot>)).catch(unavailable);
}

function unavailable() {root.render(<main style={{padding: 24, fontFamily: 'system-ui'}}>{LOAD_FAILURE[language.locale]}</main>);}

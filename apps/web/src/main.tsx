import ReactDOM from 'react-dom/client';

const element = document.getElementById('root');
if (!element) throw new Error('Application root is missing.');
const root = ReactDOM.createRoot(element);
// Recovery is independent of onboarding, guest storage and the practice API.
if (/^\/wallet-recovery\/?$/.test(window.location.pathname)) {
  void Promise.all([import('./recovery/wallet-recovery'), import('./recovery/wallet-recovery.css')])
    .then(([{WalletRecoveryPage}]) => root.render(<WalletRecoveryPage />)).catch(unavailable);
} else {
  void import('./product-entry').then(({ProductApp}) => root.render(<ProductApp />)).catch(unavailable);
}

function unavailable() {root.render(<main style={{padding: 24, fontFamily: 'system-ui'}}>Trimmy couldn’t load. Please reopen this page.</main>);}

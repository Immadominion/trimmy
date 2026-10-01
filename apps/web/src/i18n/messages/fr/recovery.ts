import type en from '../en/recovery';
import type {Translation} from '../types';

const messages: Translation<typeof en> = {
  'recovery.documentTitle': 'Trimmy | Récupération du portefeuille',
  'recovery.eyebrow': 'Ton portefeuille, avec toi',
  'recovery.title': 'Garde l’accès<br/>à ton portefeuille.',
  'recovery.footer': 'Besoin d’aide ? {link}<br/>N’envoie jamais de clé ni de code de connexion au support.',

  'recovery.invalidLink': 'Ce lien de récupération n’est pas valide. Ouvre la récupération du portefeuille depuis Trimmy dans ton navigateur.',
  'recovery.unavailable': 'La récupération du portefeuille n’est pas disponible ici. Réessaie plus tard.',
  'recovery.opening': 'Ouverture de la récupération du portefeuille…',
  'recovery.loadFailed': 'La récupération du portefeuille n’a pas pu se charger. Rouvre cette page depuis Trimmy.',

  'recovery.account.opening': 'Ouverture de ton compte…',
  'recovery.account.failed': 'Ton compte n’a pas pu se charger. Rouvre cette page pour réessayer.',
  'recovery.signIn.intro': 'Connecte-toi comme tu le fais dans Trimmy. Choisis ensuite ton portefeuille pour ouvrir sa clé de récupération dans Privy.',
  'recovery.signIn.button': 'Se connecter à Trimmy',
  'recovery.signIn.failed': 'La connexion n’a pas pu s’ouvrir. Réessaie.',
  'recovery.privy.landingHeader': 'Connecte-toi à Trimmy',
  'recovery.privy.loginMessage': 'Utilise le même compte que dans ton app Trimmy.',

  'recovery.wallet.intro': 'Utilise ta clé de récupération pour importer ce même portefeuille dans un autre portefeuille compatible avec Solana.',
  'recovery.wallet.mismatchTitle': 'Ce n’est pas le bon compte.',
  'recovery.wallet.mismatchBody': 'Connecte-toi avec le compte que tu utilises pour ce portefeuille dans Trimmy.',
  'recovery.wallet.none': 'Aucun portefeuille Solana Trimmy n’est associé à ce compte.',
  'recovery.wallet.chooseLabel': 'Choisis un portefeuille Solana',
  'recovery.wallet.solana': 'Portefeuille Solana',
  'recovery.wallet.selected': 'Sélectionné',
  'recovery.wallet.keyNote': 'Ta clé contrôle tes fonds. Garde-la secrète. Privy l’affiche dans une fenêtre sécurisée à part ; Trimmy ne la reçoit pas.',
  'recovery.wallet.wait': 'Un instant…',
  'recovery.wallet.openKey': 'Ouvrir la clé de récupération',
  'recovery.wallet.windowClosed': 'La fenêtre de récupération est fermée. Tu peux la rouvrir si besoin.',
  'recovery.wallet.windowFailed': 'La fenêtre de récupération n’a pas pu s’ouvrir. Réessaie.',
  'recovery.wallet.switchAccount': 'Changer de compte',
  'recovery.wallet.signingOut': 'Déconnexion…',
  'recovery.wallet.signOutFailed': 'Impossible de te déconnecter. Réessaie.',
};
export default messages;

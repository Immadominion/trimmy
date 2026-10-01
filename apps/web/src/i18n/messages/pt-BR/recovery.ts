import type en from '../en/recovery';
import type {Translation} from '../types';

const messages: Translation<typeof en> = {
  'recovery.documentTitle': 'Trimmy | Recuperação da carteira',
  'recovery.eyebrow': 'Sua carteira, com você',
  'recovery.title': 'Mantenha o acesso<br/>à sua carteira.',
  'recovery.footer': 'Precisa de ajuda? {link}<br/>Nunca envie ao suporte uma chave ou um código de acesso.',

  'recovery.invalidLink': 'Este link de recuperação não é válido. Abra a recuperação da carteira pelo Trimmy no seu navegador.',
  'recovery.unavailable': 'A recuperação da carteira não está disponível aqui. Tente de novo mais tarde.',
  'recovery.opening': 'Abrindo a recuperação da carteira…',
  'recovery.loadFailed': 'Não foi possível carregar a recuperação da carteira. Abra esta página de novo pelo Trimmy.',

  'recovery.account.opening': 'Abrindo sua conta…',
  'recovery.account.failed': 'Não foi possível carregar sua conta. Abra esta página de novo para tentar outra vez.',
  'recovery.signIn.intro': 'Entre do mesmo jeito que você entra no Trimmy. Depois, escolha sua carteira para abrir a chave de recuperação no Privy.',
  'recovery.signIn.button': 'Entrar no Trimmy',
  'recovery.signIn.failed': 'Não foi possível abrir o login. Tente de novo.',
  'recovery.privy.landingHeader': 'Entre no Trimmy',
  'recovery.privy.loginMessage': 'Use a mesma conta do seu app Trimmy.',

  'recovery.wallet.intro': 'Use sua chave de recuperação para importar esta mesma carteira em outra carteira compatível com Solana.',
  'recovery.wallet.mismatchTitle': 'Esta não é a conta certa.',
  'recovery.wallet.mismatchBody': 'Entre com a conta que você usa para esta carteira no Trimmy.',
  'recovery.wallet.none': 'Nenhuma carteira Solana do Trimmy está vinculada a esta conta.',
  'recovery.wallet.chooseLabel': 'Escolha uma carteira Solana',
  'recovery.wallet.solana': 'Carteira Solana',
  'recovery.wallet.selected': 'Selecionada',
  'recovery.wallet.keyNote': 'Sua chave controla seus fundos. Mantenha-a em sigilo. O Privy mostra a chave em uma janela segura separada; o Trimmy não a recebe.',
  'recovery.wallet.wait': 'Aguarde…',
  'recovery.wallet.openKey': 'Abrir chave de recuperação',
  'recovery.wallet.windowClosed': 'A janela de recuperação foi fechada. Você pode abrir de novo se precisar.',
  'recovery.wallet.windowFailed': 'Não foi possível abrir a janela de recuperação. Tente de novo.',
  'recovery.wallet.switchAccount': 'Trocar de conta',
  'recovery.wallet.signingOut': 'Saindo…',
  'recovery.wallet.signOutFailed': 'Não foi possível sair. Tente de novo.',
};
export default messages;

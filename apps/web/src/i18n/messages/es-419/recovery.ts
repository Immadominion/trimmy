import type en from '../en/recovery';
import type {Translation} from '../types';

const messages: Translation<typeof en> = {
  'recovery.documentTitle': 'Trimmy | Recuperación de billetera',
  'recovery.eyebrow': 'Tu billetera, contigo',
  'recovery.title': 'Conserva el acceso<br/>a tu billetera.',
  'recovery.footer': '¿Necesitas ayuda? {link}<br/>Nunca le envíes a soporte una clave ni un código de inicio de sesión.',

  'recovery.invalidLink': 'Este enlace de recuperación no es válido. Abre la recuperación de billetera desde Trimmy en tu navegador.',
  'recovery.unavailable': 'La recuperación de billetera no está disponible aquí. Vuelve a intentarlo más tarde.',
  'recovery.opening': 'Abriendo la recuperación de billetera…',
  'recovery.loadFailed': 'No se pudo cargar la recuperación de billetera. Vuelve a abrir esta página desde Trimmy.',

  'recovery.account.opening': 'Abriendo tu cuenta…',
  'recovery.account.failed': 'No se pudo cargar tu cuenta. Vuelve a abrir esta página para intentarlo de nuevo.',
  'recovery.signIn.intro': 'Inicia sesión de la misma forma que en Trimmy. Luego elige tu billetera para abrir su clave de recuperación en Privy.',
  'recovery.signIn.button': 'Iniciar sesión en Trimmy',
  'recovery.signIn.failed': 'No se pudo abrir el inicio de sesión. Inténtalo de nuevo.',
  'recovery.privy.landingHeader': 'Inicia sesión en Trimmy',
  'recovery.privy.loginMessage': 'Usa la misma cuenta que en tu app de Trimmy.',

  'recovery.wallet.intro': 'Usa tu clave de recuperación para importar esta misma billetera en otra billetera compatible con Solana.',
  'recovery.wallet.mismatchTitle': 'Esta no es la cuenta correcta.',
  'recovery.wallet.mismatchBody': 'Inicia sesión con la cuenta que usas para esta billetera en Trimmy.',
  'recovery.wallet.none': 'No hay ninguna billetera Solana de Trimmy vinculada a esta cuenta.',
  'recovery.wallet.chooseLabel': 'Elige una billetera Solana',
  'recovery.wallet.solana': 'Billetera Solana',
  'recovery.wallet.selected': 'Seleccionada',
  'recovery.wallet.keyNote': 'Tu clave controla tus fondos. Mantenla en privado. Privy la muestra en una ventana segura aparte; Trimmy no la recibe.',
  'recovery.wallet.wait': 'Espera un momento…',
  'recovery.wallet.openKey': 'Abrir clave de recuperación',
  'recovery.wallet.windowClosed': 'Se cerró la ventana de recuperación. Puedes volver a abrirla si la necesitas.',
  'recovery.wallet.windowFailed': 'No se pudo abrir la ventana de recuperación. Inténtalo de nuevo.',
  'recovery.wallet.switchAccount': 'Cambiar de cuenta',
  'recovery.wallet.signingOut': 'Cerrando sesión…',
  'recovery.wallet.signOutFailed': 'No se pudo cerrar sesión. Inténtalo de nuevo.',
};
export default messages;

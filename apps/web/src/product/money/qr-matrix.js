// The qrcode package has no bundled types; this edge stays in JS behind
// qr-matrix.d.ts. It only encodes a public Solana address into modules.
import QRCode from 'qrcode';

export function qrMatrix(text) {
  if (typeof text !== 'string' || text.length === 0 || text.length > 256) throw new Error('QR_INPUT_INVALID');
  const code = QRCode.create(text, {errorCorrectionLevel: 'M'});
  const size = code.modules.size;
  const modules = [];
  for (let row = 0; row < size; row++) for (let col = 0; col < size; col++) modules.push(Boolean(code.modules.get(row, col)));
  return {size, modules};
}

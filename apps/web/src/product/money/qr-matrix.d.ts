/** A QR code's module grid for a short text, error correction level M. */
export interface QrMatrix {readonly size: number; readonly modules: readonly boolean[]}
export function qrMatrix(text: string): QrMatrix;

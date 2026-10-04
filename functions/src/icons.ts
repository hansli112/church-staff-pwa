import sharp from 'sharp';

/**
 * Home-screen icons made from a church logo, so neither Android nor iOS
 * crops it or fills its transparent parts with black.
 *
 * - icon-192, icon-512: the logo as is, for `purpose: any`.
 * - maskable-512: the logo inside the maskable safe zone (a centred circle
 *   80% across, so a square logo is at most 56% wide) on white.
 * - apple-touch-180: opaque, on white; iOS fills transparency with black.
 */
export const ICON_FILES = ['icon-192.png', 'icon-512.png', 'maskable-512.png', 'apple-touch-180.png'] as const;
export type IconFile = (typeof ICON_FILES)[number];

const WHITE = { r: 255, g: 255, b: 255, alpha: 1 };
const CLEAR = { r: 0, g: 0, b: 0, alpha: 0 };

async function fit(logo: Buffer, size: number) {
  return sharp(logo).resize(size, size, { fit: 'contain', background: CLEAR }).png().toBuffer();
}

/** [logo] centred at [scale] of a [size] square on white, with no alpha. */
async function onWhite(logo: Buffer, size: number, scale: number) {
  const inner = Math.round(size * scale);
  const pad = Math.floor((size - inner) / 2);
  return sharp(await fit(logo, inner))
    .extend({ top: pad, bottom: size - inner - pad, left: pad, right: size - inner - pad, background: WHITE })
    .flatten({ background: WHITE })
    .removeAlpha()
    .png()
    .toBuffer();
}

export async function makeIcons(logo: Buffer): Promise<Record<IconFile, Buffer>> {
  const [icon192, icon512, maskable, apple] = await Promise.all([
    fit(logo, 192),
    fit(logo, 512),
    onWhite(logo, 512, 0.56),
    onWhite(logo, 180, 0.9),
  ]);
  return { 'icon-192.png': icon192, 'icon-512.png': icon512, 'maskable-512.png': maskable, 'apple-touch-180.png': apple };
}

/** Where a derived icon is stored: next to the logo, named after its version. */
export const iconStoragePath = (cid: string, version: string, file: IconFile) => `churches/${cid}/logo-${version}-${file}`;

// Photos' uploads, as the old screen's eqUpload, eqLogoUpload, eqRemove and eqLogoRemove: the picture resized for the web
// in the browser first (a photo to at most 1,600 px wide as a JPEG at 82%, a logo to 1,200 px as a PNG), put in the
// site-photos bucket under a new name, then named on the website through its function (site_set_airport_photo(),
// site_set_airline_logo()), and the file it replaces taken out of the bucket. Removing one is the website's function
// (site_remove_airport_photo(), site_remove_airline_logo()) and the file taken out. A preview never gets here (Photos.tsx
// checks first, and data/preview.ts refuses any write to the storage from a preview address).
import { supabase } from "../../data/supabase";
import { LOGO_WIDTH, PHOTO_WIDTH, fitWidth, logoPath, photoPath } from "./model";

const BUCKET = "site-photos";

async function resized(file: Blob, max: number, type: "image/jpeg" | "image/png", quality?: number): Promise<Blob> {
  const bmp = await createImageBitmap(file);
  const { width, height } = fitWidth(bmp.width, bmp.height, max);
  const cv = document.createElement("canvas");
  cv.width = width;
  cv.height = height;
  const ctx = cv.getContext("2d");
  if (!ctx) throw new Error("the browser can't draw the picture");
  ctx.drawImage(bmp, 0, 0, width, height);
  bmp.close();
  const blob = await new Promise<Blob | null>((r) => cv.toBlob(r, type, quality));
  if (!blob) throw new Error("the picture couldn't be made smaller");
  return blob;
}

async function put(path: string, blob: Blob, contentType: string): Promise<string> {
  const up = await supabase.storage.from(BUCKET).upload(path, blob, { contentType, cacheControl: "31536000", upsert: false });
  if (up.error) throw new Error(up.error.message);
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}

async function drop(path: string | null | undefined) {
  if (path) await supabase.storage.from(BUCKET).remove([path]);
}

/** A destination photo: resized, uploaded, named on the website with its credit; the uploaded file it replaces removed. */
export async function uploadPhoto(code: string, file: Blob, credit: string, old: { uploaded?: boolean; path?: string | null } | undefined) {
  const blob = await resized(file, PHOTO_WIDTH, "image/jpeg", 0.82);
  const path = photoPath(code, Date.now());
  const url = await put(path, blob, "image/jpeg");
  const r = await supabase.rpc("site_set_airport_photo", { p_code: code, p_url: url, p_credit: credit || undefined, p_path: path });
  if (r.error) throw new Error(r.error.message);
  if (old?.uploaded) await drop(old.path);
  return { url, path };
}

/** An airline's logo: resized, uploaded, named on the website; the file it replaces removed. */
export async function uploadLogo(airline: string, file: Blob, old: { path?: string | null } | undefined) {
  const blob = await resized(file, LOGO_WIDTH, "image/png");
  const path = logoPath(airline, Date.now());
  const url = await put(path, blob, "image/png");
  const r = await supabase.rpc("site_set_airline_logo", { p_airline: airline, p_url: url, p_path: path });
  if (r.error) throw new Error(r.error.message);
  await drop(old?.path);
  return { url, path };
}

/** A destination photo taken off the website (the city photo or the plain card shows again), and its file removed. */
export async function removePhoto(code: string, old: { uploaded?: boolean; path?: string | null } | undefined) {
  const r = await supabase.rpc("site_remove_airport_photo", { p_code: code });
  if (r.error) throw new Error(r.error.message);
  if (old?.uploaded) await drop(old.path);
}

/** Back to the in-game logo for an airline, and the uploaded file removed. */
export async function removeLogo(airline: string, old: { path?: string | null } | undefined) {
  const r = await supabase.rpc("site_remove_airline_logo", { p_airline: airline });
  if (r.error) throw new Error(r.error.message);
  await drop(old?.path);
}

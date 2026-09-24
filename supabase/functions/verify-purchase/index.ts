// verify-purchase — التحقق من شراء اشتراك العيلة وكتابته في `family_subscriptions`.
//
// بتتلصق في محرر Edge Functions في لوحة Supabase. **من غير أي import**:
// كله `fetch` و Web Crypto — نفس عُرف `escalate`.
//
// ---------------------------------------------------------------- الطلب
//
//   POST /functions/v1/verify-purchase
//   Authorization: Bearer <جلسة المستخدم>      ← مش مفتاح الخدمة: المشتري بيتكلم
//   { "patient_uuid": "...",
//     "store": "apple" | "google",
//     "product_id": "fakkarni_family_monthly" | "fakkarni_family_yearly",
//     "receipt": "<Apple: transactionId — Google: purchaseToken>" }
//
// ---------------------------------------------------------------- الردود
//
//   200 { status: "active", expires_at }      المتجر أكّد، والصف اتكتب
//   200 { status: "not_configured" }          أسرار المتجر مش متظبطة (HANDOVER B7)
//                                             — التطبيق بيفضل في التجربة/المهلة
//   200 { status: "invalid" }                 المتجر رفض الإيصال
//   401 / 403                                 مفيش جلسة، أو المشتري مش في دائرة المريض
//
// ---------------------------------------------------------------- الأسرار
//
// **كلها من أسرار الدالة وبس** (Supabase → Edge Functions → Secrets):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY            (موجودين تلقائياً)
//   APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY   (App Store Connect → Keys → In-App Purchase)
//   APPLE_BUNDLE_ID                                    (com.…)
//   GOOGLE_SERVICE_ACCOUNT_JSON                        (حساب خدمة له صلاحية androidpublisher)
//   ANDROID_PACKAGE                                    (اسم الحزمة)
// لو أسرار متجر ناقصة الدالة بترد `not_configured` **من غير ما ترمي** —
// المشتري ما يتقفلش عليه بسبب إعداد ناقص عندنا.
//
// **مفيش Deno على جهاز التطوير: الملف ده اتكتب واتراجع، وما اتشغّلش.**
// أول تشغيل حقيقي هو أول شراء sandbox على TestFlight / Internal testing.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const PRODUCTS = new Set(['fakkarni_family_monthly', 'fakkarni_family_yearly']);

type Store = 'apple' | 'google';

interface VerifyResult {
  ok: boolean;
  expiresAt?: string;
  reason?: string;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ------------------------------------------------------------------ Supabase

async function restGet(path: string, jwt: string): Promise<unknown> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new Error(`rest ${path}: HTTP ${res.status}: ${await res.text()}`);
  return await res.json();
}

/// المستخدم بتاع الجلسة — من GoTrue، مش من فك الـJWT بنفسنا.
async function userIdOf(jwt: string): Promise<string | null> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) return null;
  const body = (await res.json()) as { id?: string };
  return body.id ?? null;
}

/// المشتري لازم يكون في الدائرة: المالك أو علاقة مقبولة.
async function inCircle(userId: string, patientUuid: string): Promise<boolean> {
  const owner = (await restGet(
    `patients?select=uuid&uuid=eq.${patientUuid}&owner_id=eq.${userId}`,
    SERVICE_KEY,
  )) as unknown[];
  if (owner.length > 0) return true;
  const linked = (await restGet(
    `care_relationships?select=caregiver_id&patient_uuid=eq.${patientUuid}&caregiver_id=eq.${userId}&status=eq.accepted`,
    SERVICE_KEY,
  )) as unknown[];
  return linked.length > 0;
}

async function writeSubscription(
  patientUuid: string,
  store: Store,
  productId: string,
  purchaserId: string,
  expiresAt: string,
): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/family_subscriptions?on_conflict=patient_uuid`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      patient_uuid: patientUuid,
      status: 'active',
      // التجربة بتفضل بتاريخها القديم لو فيه صف؛ للصف الجديد: النهارده
      trial_ends_at: new Date().toISOString(),
      expires_at: expiresAt,
      store,
      product_id: productId,
      purchaser_id: purchaserId,
      last_verified_at: new Date().toISOString(),
    }),
  });
  if (!res.ok) throw new Error(`write: HTTP ${res.status}: ${await res.text()}`);
}

// ------------------------------------------------------------------ Apple

function b64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = '';
  for (const b of arr) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

/// JWT بتوقيع ES256 لـApp Store Server API (صالح ٢٠ دقيقة).
async function appleJwt(issuer: string, keyId: string, pem: string, bundleId: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    iss: issuer,
    iat: now,
    exp: now + 20 * 60,
    aud: 'appstoreconnect-v1',
    bid: bundleId,
  })));
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(pem), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(sig)}`;
}

function decodeJwsPayload(jws: string): Record<string, unknown> {
  const part = jws.split('.')[1] ?? '';
  const padded = part.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (part.length % 4)) % 4);
  return JSON.parse(atob(padded)) as Record<string, unknown>;
}

async function verifyApple(transactionId: string, productId: string): Promise<VerifyResult | 'not_configured'> {
  const issuer = Deno.env.get('APPLE_ISSUER_ID');
  const keyId = Deno.env.get('APPLE_KEY_ID');
  const pem = Deno.env.get('APPLE_PRIVATE_KEY');
  const bundleId = Deno.env.get('APPLE_BUNDLE_ID');
  if (!issuer || !keyId || !pem || !bundleId) return 'not_configured';

  const token = await appleJwt(issuer, keyId, pem, bundleId);
  // الإنتاج الأول، وبعدين sandbox — نفس ما Apple بتوصي
  for (const host of ['https://api.storekit.itunes.apple.com', 'https://api.storekit-sandbox.itunes.apple.com']) {
    const res = await fetch(`${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue;
    if (!res.ok) return { ok: false, reason: `apple: HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
    const body = (await res.json()) as { signedTransactionInfo?: string };
    if (!body.signedTransactionInfo) return { ok: false, reason: 'apple: no transaction info' };
    // **مش بنتحقق من توقيع JWS هنا** — الرد جاي من Apple على HTTPS بمفتاحنا.
    const info = decodeJwsPayload(body.signedTransactionInfo);
    if (info.productId !== productId) return { ok: false, reason: 'apple: product mismatch' };
    const expires = info.expiresDate;
    if (typeof expires !== 'number') return { ok: false, reason: 'apple: no expiry' };
    return { ok: true, expiresAt: new Date(expires).toISOString() };
  }
  return { ok: false, reason: 'apple: transaction not found' };
}

// ------------------------------------------------------------------ Google

async function googleAccessToken(serviceAccount: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(serviceAccount.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${payload}`));
  const assertion = `${header}.${payload}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${assertion}`,
  });
  if (!res.ok) throw new Error(`google token: HTTP ${res.status}: ${await res.text()}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

async function verifyGoogle(purchaseToken: string, productId: string): Promise<VerifyResult | 'not_configured'> {
  const raw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  const pkg = Deno.env.get('ANDROID_PACKAGE');
  if (!raw || !pkg) return 'not_configured';
  const account = JSON.parse(raw) as { client_email: string; private_key: string };
  const token = await googleAccessToken(account);
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!res.ok) return { ok: false, reason: `google: HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
  const body = (await res.json()) as {
    subscriptionState?: string;
    lineItems?: { productId?: string; expiryTime?: string }[];
  };
  const line = body.lineItems?.find((l) => l.productId === productId);
  if (!line?.expiryTime) return { ok: false, reason: 'google: product not in purchase' };
  const active = body.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE' || body.subscriptionState === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD';
  if (!active) return { ok: false, reason: `google: ${body.subscriptionState}` };
  return { ok: true, expiresAt: new Date(line.expiryTime).toISOString() };
}

// ------------------------------------------------------------------ المدخل

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json(405, { error: 'method' });
  const auth = req.headers.get('Authorization') ?? '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!jwt) return json(401, { error: 'no session' });

  let body: { patient_uuid?: string; store?: Store; product_id?: string; receipt?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'bad json' });
  }
  const { patient_uuid: patientUuid, store, product_id: productId, receipt } = body;
  if (!patientUuid || !store || !productId || !receipt) return json(400, { error: 'missing fields' });
  if (!PRODUCTS.has(productId)) return json(400, { error: 'unknown product' });
  if (store !== 'apple' && store !== 'google') return json(400, { error: 'unknown store' });

  const userId = await userIdOf(jwt);
  if (!userId) return json(401, { error: 'no session' });
  if (!(await inCircle(userId, patientUuid))) return json(403, { error: 'not in circle' });

  try {
    const result = store === 'apple' ? await verifyApple(receipt, productId) : await verifyGoogle(receipt, productId);
    if (result === 'not_configured') return json(200, { status: 'not_configured' });
    if (!result.ok) {
      console.log(`verify-purchase: ${result.reason}`);
      return json(200, { status: 'invalid' });
    }
    await writeSubscription(patientUuid, store, productId, userId, result.expiresAt!);
    return json(200, { status: 'active', expires_at: result.expiresAt });
  } catch (error) {
    console.log(`verify-purchase: ${String(error)}`);
    return json(500, { error: 'verify failed' });
  }
});

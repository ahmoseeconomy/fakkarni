// confirm-signal — إشارة «اتأكّدت» للناحية التانية (0035).
//
// بتتنادى من تريجر في القاعدة (`private.send_confirm_signal`) لما جرعة
// تتعلّم `taken` على موبايل المريض، أو لما ممرض يأكّد نيابةً. بتبعت رسالة
// دفع **صامتة** (data فقط — مفيش إشعار ظاهر) لكل أجهزة أصحاب المريض
// وممرضينه، والتطبيق هو اللي بيقرّر: المريض بيسحب التأكيد (وده اللي
// بيلغي سلّمه)، والممرض بيلغي تذكيره. **اللي ما وصلوش** بيتظبط في
// المقارنة الجاية على موبايله — الإشارة بتسرّع، ما بتقرّرش.
//
// نفس شكل `escalate`: مفتاح الخدمة حصراً، مفيش import، fetch + Web Crypto.
// «مين يستلم» تعريف واحد في SQL: `public.confirm_signal_targets_for_service`.
//
//   curl -X POST "$URL/functions/v1/confirm-signal" \
//     -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
//     -d '{"dose_event_uuid":"...","source":"patient"}'

const SUPABASE_URL = requiredEnv('SUPABASE_URL');
const SERVICE_KEY = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

async function dbJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await db(path, init);
  const text = await res.text();
  if (!res.ok) throw new Error(`db_error ${res.status} on ${path}: ${text}`);
  return JSON.parse(text) as T;
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN [^-]+-----/, '').replace(/-----END [^-]+-----/, '').replace(/\s+/g, '');
  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return der;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function serviceAccount(): ServiceAccount {
  const parsed = JSON.parse(requiredEnv('FIREBASE_SERVICE_ACCOUNT')) as ServiceAccount;
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT ناقص client_email/private_key/project_id');
  }
  return parsed;
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const encoder = new TextEncoder();
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = { iss: sa.client_email, scope: FCM_SCOPE, aud: 'https://oauth2.googleapis.com/token', iat: issuedAt, exp: issuedAt + 3600 };
  const unsigned = `${base64Url(encoder.encode(JSON.stringify(header)))}.${base64Url(encoder.encode(JSON.stringify(claims)))}`;
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(sa.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned)));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${base64Url(signature)}` }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`oauth_failed ${res.status}: ${text}`);
  return (JSON.parse(text) as { access_token: string }).access_token;
}

interface Target {
  user_id: string;
  patient_uuid: string;
  is_owner: boolean;
}

/// رسالة data فقط: مفيش `notification`، فمفيش حاجة بتظهر للمستخدم — التطبيق
/// هو اللي بيقرا `type=confirm`. أندرويد `HIGH` عشان توصل والتطبيق نايم.
async function sendSilent(sa: ServiceAccount, bearer: string, token: string, data: Record<string, string>) {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token,
        data,
        android: { priority: 'HIGH' },
        apns: { headers: { 'apns-priority': '5', 'apns-push-type': 'background' }, payload: { aps: { 'content-available': 1 } } },
      },
    }),
  });
  const text = await res.text();
  console.log(`FCM: HTTP ${res.status}: ${text}`);
  if (res.status === 404 || text.includes('UNREGISTERED')) {
    await db(`device_tokens?token=eq.${encodeURIComponent(token)}`, { method: 'DELETE' });
  }
  return res.status;
}

function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body, null, 2), { status, headers: { 'Content-Type': 'application/json' } });

  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!secretEquals(bearer, SERVICE_KEY)) return json({ error: 'service_role_key_required' }, 401);

  let body: { dose_event_uuid?: string; source?: string } = {};
  try {
    const text = await req.text();
    if (text.trim()) body = JSON.parse(text);
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  if (!body.dose_event_uuid) return json({ error: 'dose_event_uuid_required' }, 400);
  const source = body.source === 'proxy' ? 'proxy' : 'patient';

  try {
    const targets = await dbJson<Target[]>('rpc/confirm_signal_targets_for_service', {
      method: 'POST',
      body: JSON.stringify({ p_event: body.dose_event_uuid }),
    });
    // مصدر التأكيد ما بيتبعتلوش: المريض اللي أكّد عارف، والممرض اللي أكّد
    // موبايله لغى تذكيره بنفسه.
    const recipients = targets.filter((t) => (source === 'patient' ? !t.is_owner : true));
    if (recipients.length === 0) return json({ sent: 0 });

    const sa = serviceAccount();
    const token = await accessToken(sa);
    let sent = 0;
    for (const t of recipients) {
      const tokens = await dbJson<{ token: string }[]>(`device_tokens?user_id=eq.${t.user_id}&select=token`);
      for (const row of tokens) {
        const status = await sendSilent(sa, token, row.token, {
          type: 'confirm',
          dose_event_uuid: body.dose_event_uuid,
          patient_uuid: t.patient_uuid,
          source,
        });
        if (status >= 200 && status < 300) sent++;
      }
    }
    return json({ sent, recipients: recipients.length });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`confirm-signal: وقعت — ${message}`);
    return json({ error: message }, 500);
  }
});

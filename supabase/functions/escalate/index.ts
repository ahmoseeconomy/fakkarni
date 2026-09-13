// escalate — آخر درجة في السلّم: إشعار لابن المريض.
//
// بتتلصق في محرر Edge Functions في لوحة Supabase. مفيش CLI ولا Deno على
// جهاز التطوير، فالملف ده **من غير أي import**: كله `fetch` و Web Crypto.
// مفيش نسخة مكتبة تتكسر، ومفيش رابط CDN يقع وسط عرض.
//
// ---------------------------------------------------------------- التشغيل
//
// لازم تتنادى بـ**مفتاح الخدمة** (service role). الدالة بتتأكد من كده
// بنفسها فوق `verify_jwt` الافتراضي: من غير الفحص ده أي مستخدم مسجّل —
// وده يشمل أي مستخدم مجهول — يقدر يبعت تنبيهات لعيلة مش عيلته.
//
//   # فحص بالإيد على حدث معيّن، من غير ما تكتب أي حاجة:
//   curl -X POST "$URL/functions/v1/escalate" \
//     -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
//     -H "Content-Type: application/json" \
//     -d '{"dose_event_uuid":"...","dry_run":true}'
//
//   # نفس الحدث، بجد: بيحجز صف في escalations وبيحاول يبعت
//   curl ... -d '{"dose_event_uuid":"..."}'
//
//   # المسح الدوري (ده اللي الكرون بينادیه)
//   curl ... -d '{}'
//
// ------------------------------------------------------------ وضعان، وفرقهما
//
// **المسح** بيسأل `public.due_escalations_for_service` — التعريف الوحيد
// لـ«مين يستاهل تنبيه». مفيش نسخة من الاستعلام هنا، ولا شرط واحد منه
// متكرر في TypeScript.
//
// **النداء بالإيد** مش اختيار — هو «ابعت للحدث ده، أنا اخترته بنفسي».
// فهو **بيتخطى شرط الوقت عن قصد** (مستحيل تستنى ٦١ دقيقة وسط عرض)، لكنه
// ما بيتخطاش حاجة تانية: لو مفيش ابن مربوط مفيش حد يتنبّه، ولو الصف
// محجوز قبل كده الـunique بيرفض. الاستعلامات اللي تحته **بحث** مش
// **اختيار** — مفيش فيها ولا شرط بيقرر استحقاق.
//
// -------------------------------------------------------------- بعد الإرسال
//
// الصف بيتحجز في `escalations` **قبل** الإرسال. ده اللي بيمنع التكرار:
// الـunique هو الحارس، مش ذاكرة في الكود.
//
// فشل FCM بيتقسم:
//   * عطل عابر (5xx / 429 / الشبكة) → الحجز بيتشال، فالدقة الجاية بتعيد
//     المحاولة. الصمت هنا أسوأ من تنبيه متأخر: ده آخر درجة في السلّم،
//     والمكالمات الصوتية اتلغت من المنتج. النافذة المحدودة (يومين) هي
//     اللي بتوقّف إعادة المحاولة لوحدها — مفيش عدّاد محتاج صيانة.
//   * عطل دائم (توكن ميت) → الصف بيفضل 'failed' للتدقيق، والتوكن
//     بيتمسح. FCM بيقول UNREGISTERED لما التطبيق يتشال؛ الاحتفاظ بيه
//     معناه فشل كل خمس دقايق للأبد.
//
// الرد من FCM بيتسجّل كما هو: `FCM: HTTP <status>: <body>` — نفس عُرف
// سطر Gemini، وللسبب نفسه: وقت العطل الرد هو مصدر الحقيقة، مش ذاكرتنا
// عن شكل الطلب.

const SUPABASE_URL = requiredEnv('SUPABASE_URL');
const SERVICE_KEY = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');

/// نطاق FCM والدرجة اللي الجولة دي بتبعتها.
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/// قناة أندرويد على موبايل **الابن**. لازم الجزء الخامس (Dart) ينشئها
/// بنفس الاسم بالحرف، وإلا أندرويد بيرجّع الإشعار للقناة الافتراضية
/// وبيفقد أولويته — من غير أي خطأ يبان.
const CAREGIVER_CHANNEL = 'fakkarni_caregiver';

/// حد المسح الواحد. الكرون بيدق كل خمس دقايق، فده سقف مش هدف.
const SCAN_LIMIT = 200;

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

// ------------------------------------------------------------- PostgREST

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

async function dbJson<T>(path: string): Promise<T> {
  const res = await db(path);
  const text = await res.text();
  if (!res.ok) throw new Error(`db_error ${res.status} on ${path}: ${text}`);
  return JSON.parse(text) as T;
}

// ------------------------------------------------- توكن الوصول إلى FCM

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
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
  const raw = requiredEnv('FIREBASE_SERVICE_ACCOUNT');
  let parsed: ServiceAccount;
  try {
    parsed = JSON.parse(raw) as ServiceAccount;
  } catch {
    // السبب الأشهر: اتلصق ناقص، أو اتلف فيه علامات تنصيص زيادة.
    throw new Error('FIREBASE_SERVICE_ACCOUNT مش JSON صالح');
  }
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT ناقص client_email/private_key/project_id');
  }
  return parsed;
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const encoder = new TextEncoder();
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: issuedAt,
    exp: issuedAt + 3600,
  };

  const unsigned = `${base64Url(encoder.encode(JSON.stringify(header)))}.` +
    `${base64Url(encoder.encode(JSON.stringify(claims)))}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned)),
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    // بيتسجّل كامل: خطأ الساعة (`invalid_grant`) وخطأ المفتاح شكلهم واحد
    // من بره، والرد هو اللي بيفرّق.
    console.error(`OAuth: HTTP ${res.status}: ${text}`);
    throw new Error(`oauth_failed ${res.status}`);
  }
  return (JSON.parse(text) as { access_token: string }).access_token;
}

// ----------------------------------------------------------- نص الإشعار

/// معاد الجرعة بتوقيت القاهرة. مصر بتغيّر التوقيت الصيفي، و`Intl` بيعرف
/// ده — حساب بالإيد على الـUTC بيغلط ساعة نص السنة.
function cairoTime(iso: string): string {
  return new Intl.DateTimeFormat('ar-EG', {
    timeZone: 'Africa/Cairo',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(iso));
}

/// نفس نبرة شاشة المتابعة: بتبلّغ، ما بتحكمش. «ما اتأكدتش» مش «فاتته».
function notificationText(target: Target): { title: string; body: string } {
  return {
    title: `${target.patient_name} — جرعة ما اتأكدتش`,
    body: `${target.medication_name}، معاد ${cairoTime(target.scheduled_at)}. اطمن عليه.`,
  };
}

// ------------------------------------------------------------- الإرسال

interface Target {
  dose_event_uuid: string;
  patient_uuid: string;
  patient_name: string;
  medication_name: string;
  scheduled_at: string;
  caregiver_id: string;
}

interface SendOutcome {
  token: string;
  status: number;
  body: string;
  permanentFailure: boolean;
}

async function sendToToken(
  sa: ServiceAccount,
  token: string,
  bearer: string,
  target: Target,
): Promise<SendOutcome> {
  const { title, body } = notificationText(target);
  const message = {
    token,
    notification: { title, body },
    data: {
      type: 'escalation',
      dose_event_uuid: target.dose_event_uuid,
      patient_uuid: target.patient_uuid,
    },
    android: {
      priority: 'HIGH',
      notification: { channel_id: CAREGIVER_CHANNEL },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive' } },
    },
  };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message }),
    },
  );
  const text = await res.text();

  // مصدر الحقيقة وقت العطل. بيتسجّل سواء نجح أو فشل.
  console.log(`FCM: HTTP ${res.status}: ${text}`);

  return {
    token,
    status: res.status,
    body: text,
    // توكن ميت: التطبيق اتشال أو البيانات اتمسحت. الاحتفاظ بيه = فشل
    // كل خمس دقايق للأبد.
    permanentFailure: res.status === 404 || text.includes('UNREGISTERED'),
  };
}

// --------------------------------------------------------------- الأهداف

/// أهداف المسح — سؤال واحد للقاعدة، والقاعدة هي اللي بتقرر.
async function scanTargets(): Promise<Target[]> {
  const res = await db('rpc/due_escalations_for_service', {
    method: 'POST',
    body: JSON.stringify({ p_limit: SCAN_LIMIT }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`due_escalations failed ${res.status}: ${text}`);
  return JSON.parse(text) as Target[];
}

/// **بحث**، مش اختيار: الحدث ده، ومين مربوط بصاحبه. مفيش شرط استحقاق
/// هنا بالمرة — الوقت والحالة بيتخطوا عن قصد عشان الفحص اليدوي يشتغل
/// على جرعة لسه معادها دلوقتي.
async function manualTargets(doseEventUuid: string): Promise<Target[]> {
  const events = await dbJson<{ dose_schedule_uuid: string; scheduled_at: string }[]>(
    `dose_events?uuid=eq.${doseEventUuid}&select=dose_schedule_uuid,scheduled_at`,
  );
  if (events.length === 0) throw new Error(`مفيش dose_event بالـuuid ده: ${doseEventUuid}`);

  const schedules = await dbJson<{ medication_uuid: string }[]>(
    `dose_schedules?uuid=eq.${events[0].dose_schedule_uuid}&select=medication_uuid`,
  );
  const medications = await dbJson<{ name: string; patient_uuid: string }[]>(
    `medications?uuid=eq.${schedules[0].medication_uuid}&select=name,patient_uuid`,
  );
  const patients = await dbJson<{ uuid: string; name: string }[]>(
    `patients?uuid=eq.${medications[0].patient_uuid}&select=uuid,name`,
  );
  const caregivers = await dbJson<{ caregiver_id: string }[]>(
    `care_relationships?patient_uuid=eq.${medications[0].patient_uuid}` +
      `&status=eq.accepted&select=caregiver_id`,
  );

  return caregivers.map((c) => ({
    dose_event_uuid: doseEventUuid,
    patient_uuid: patients[0].uuid,
    patient_name: patients[0].name,
    medication_name: medications[0].name,
    scheduled_at: events[0].scheduled_at,
    caregiver_id: c.caregiver_id,
  }));
}

// -------------------------------------------------------- معالجة هدف واحد

async function handle(sa: ServiceAccount, bearer: string, target: Target) {
  const label = `${target.patient_name}/${target.caregiver_id}`;

  // ١) الحجز قبل الإرسال. الـunique هو اللي بيمنع التكرار.
  const claim = await db('escalations', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({
      dose_event_uuid: target.dose_event_uuid,
      caregiver_id: target.caregiver_id,
    }),
  });

  if (claim.status === 409) {
    console.log(`escalate: ${label} اتنبّه قبل كده — مفيش إرسال`);
    return { ...target, result: 'already_escalated' };
  }
  const claimText = await claim.text();
  if (!claim.ok) throw new Error(`claim_failed ${claim.status}: ${claimText}`);
  const row = (JSON.parse(claimText) as { uuid: string }[])[0];

  const release = async () => {
    await db(`escalations?uuid=eq.${row.uuid}`, { method: 'DELETE' });
  };
  const mark = async (fields: Record<string, unknown>) => {
    await db(`escalations?uuid=eq.${row.uuid}`, {
      method: 'PATCH',
      body: JSON.stringify(fields),
    });
  };

  // ٢) توكنات الابن.
  const tokens = await dbJson<{ token: string }[]>(
    `device_tokens?user_id=eq.${target.caregiver_id}&select=token`,
  );

  if (tokens.length === 0) {
    // مش فشل إرسال — مفيش حاجة تتبعت لها أصلاً. الصف بيفضل عشان يبان
    // إن القرار اتاخد، وده بالظبط اللي بيتشاف في الفحص اليدوي الأول.
    console.log(`escalate: ${label} مفيش توكن مسجّل — الصف اتكتب no_token`);
    // `sent_at` بيفضل فاضي عن قصد: مفيش حاجة اتبعتت. العمود يقول الحقيقة
    // أو ما يتملاش.
    await mark({ delivery_status: 'no_token' });
    return { ...target, escalation_uuid: row.uuid, result: 'no_token' };
  }

  // ٣) الإرسال لكل أجهزته.
  let outcomes: SendOutcome[];
  try {
    outcomes = await Promise.all(
      tokens.map((t) => sendToToken(sa, t.token, bearer, target)),
    );
  } catch (error) {
    // الشبكة وقعت قبل ما نعرف أي حاجة. عابر بالتعريف.
    console.error(`escalate: ${label} الشبكة وقعت — بنشيل الحجز عشان يتعاد`, error);
    await release();
    return { ...target, result: 'transient_error_released' };
  }

  for (const dead of outcomes.filter((o) => o.permanentFailure)) {
    console.log(`escalate: توكن ميت بيتمسح (${label})`);
    await db(`device_tokens?token=eq.${encodeURIComponent(dead.token)}`, {
      method: 'DELETE',
    });
  }

  const delivered = outcomes.filter((o) => o.status >= 200 && o.status < 300);
  const transient = outcomes.filter(
    (o) => o.status === 429 || o.status >= 500,
  );

  if (delivered.length === 0 && transient.length > 0) {
    // ولا جهاز استلم، والسبب عابر → سيب الدقة الجاية تحاول تاني.
    console.error(`escalate: ${label} عطل عابر من FCM — بنشيل الحجز`);
    await release();
    return { ...target, result: 'transient_error_released' };
  }

  const status = delivered.length > 0 ? 'sent' : 'failed';
  await mark({
    delivery_status: status,
    sent_at: new Date().toISOString(),
    fcm_status: outcomes[0].status,
    fcm_response: JSON.stringify(
      outcomes.map((o) => ({ status: o.status, body: o.body.slice(0, 500) })),
    ),
  });

  console.log(`escalate: ${label} → ${status} (${delivered.length}/${outcomes.length})`);
  return {
    ...target,
    escalation_uuid: row.uuid,
    result: status,
    devices: outcomes.length,
    delivered: delivered.length,
  };
}

// ------------------------------------------------------------ نقطة الدخول

/// مقارنة بطول ثابت — مقارنة عادية بتسرّب طول البادئة المتطابقة.
function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body, null, 2), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });

  // مفتاح الخدمة حصراً. `verify_jwt` لوحده بيسمح لأي مستخدم مسجّل —
  // وده يشمل كل مستخدم مجهول في التطبيق — إنه يشغّل تصعيد لعيلة غريبة.
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!secretEquals(bearer, SERVICE_KEY)) {
    return json({ error: 'service_role_key_required' }, 401);
  }

  let body: { dose_event_uuid?: string; dry_run?: boolean } = {};
  try {
    const text = await req.text();
    if (text.trim()) body = JSON.parse(text);
  } catch {
    return json({ error: 'bad_json' }, 400);
  }

  try {
    const targets = body.dose_event_uuid
      ? await manualTargets(body.dose_event_uuid)
      : await scanTargets();

    const mode = body.dose_event_uuid ? 'manual' : 'scan';
    console.log(`escalate: ${mode} — ${targets.length} هدف`);

    if (body.dry_run) {
      return json({ mode, dry_run: true, targets });
    }
    if (targets.length === 0) {
      // في الوضع اليدوي ده جواب حقيقي: الأب مالوش ابن مربوط.
      return json({ mode, handled: 0, results: [] });
    }

    // إعدادات FCM بتتفحص **قبل** أي حجز: حجز من غير إمكانية إرسال بيقفل
    // الجرعة عن محاولة جاية من غير ما حد يتنبّه.
    const sa = serviceAccount();
    const bearerToken = await accessToken(sa);

    const results = [];
    for (const target of targets) {
      results.push(await handle(sa, bearerToken, target));
    }
    return json({ mode, handled: results.length, results });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`escalate: وقعت — ${message}`);
    return json({ error: message }, 500);
  }
});

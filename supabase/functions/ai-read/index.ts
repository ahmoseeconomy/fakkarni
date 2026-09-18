// ai-read — قراية روشتة أو تقرير تحليل بـGemini، **بمفتاحنا إحنا مش بمفتاح في التطبيق**.
//
// بتتلصق في محرر Edge Functions في لوحة Supabase. مفيش CLI ولا Deno على
// جهاز التطوير، فالملف ده **من غير أي import** زي `escalate`: كله `fetch`.
//
// ------------------------------------------------------------ ليه موجودة
//
// قبل C2 المفتاح كان `String.fromEnvironment` — يعني شايل جوّه كل APK وIPA،
// واستخراجه شغل عشر دقايق. دلوقتي التطبيق **ما عندوش مفتاح خالص**: بينادي
// الدالة دي بجلسة المستخدم، والمفتاح سر هنا.
//
// وبيجيب معاه تلات حاجات:
//   ١. كل قراية **منسوبة لحساب** (جدول `ai_reads`، ٠٠١٣).
//   ٢. **حد يومي لكل حساب** + **سقف للتطبيق كله** — باگ أو مستخدم شاذ ما
//      بيفضّيش الحصة. السقف الكلي موجود لأن الدخول لسه مجهول (الدين ٢):
//      أي حد معاه المفتاح المنشور يقدر يصنع مستخدمين مجهولين جداد، وكل واحد
//      فيهم بحدّه. السقف هو اللي بيحط نهاية للفاتورة.
//   ٣. **البرومبت والـschema هنا، مش في الطلب.** العميل بيبعت `kind` وصورة
//      وبس — فجلسة مسروقة ما تقدرش تحوّل مفتاحنا لبروكسي Gemini عام.
//
// ---------------------------------------------------------------- الأسرار
//
// لوحة Supabase → Edge Functions → Secrets (مش Vault — ده ناحية القاعدة):
//   GEMINI_API_KEY          إجباري. عمره ما بيتكتب في الريبو ولا في رد ولا
//                           في سطر لوج. بيتبعت لجوجل في header وبس.
//   GEMINI_MODEL            اختياري — بيغلب PINNED_MODEL من غير لصق جديد.
//   GEMINI_FALLBACK_MODEL   اختياري — بيغلب FALLBACK_MODEL.
// `SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` المنصة بتحطهم لوحدها.
//
// ---------------------------------------------------------------- التشغيل
//
// `verify_jwt` **يفضل مفعّل**: البوابة هي اللي بتتحقق من توقيع التوكن، وإحنا
// بنقرا منه الـsub والـrole بس. لو اتقفل، أي حد يقدر يزوّر هوية — ما يتقفلش.
//
//   # من غير جلسة (المفتاح المنشور بس) → 401
//   curl -i -X POST "$URL/functions/v1/ai-read" \
//     -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
//     -H "Content-Type: application/json" -d '{}'
//
//   # بجلسة مستخدم، وطلب ناقص → 400 bad_kind (وما بيتحسبش ولا بيكلّم جوجل)
//   curl -i -X POST "$URL/functions/v1/ai-read" \
//     -H "apikey: $ANON" -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
//     -H "Content-Type: application/json" -d '{"kind":"x"}'
//
//   # قراية حقيقية
//   ... -d "{\"kind\":\"prescription\",\"mime\":\"image/jpeg\",\"image\":\"$(base64 -i rx.jpg)\"}"
//
// ------------------------------------------------------------------ الردود
//
//   200  رد Gemini **زي ما هو** — التطبيق هو اللي بيفكّه وبيحكم على الثقة،
//        زي قبل C2 بالظبط. لو القراية جت من الموديل البديل:
//        `x-model-warning: <المثبّت>;<البديل>;<retired|overloaded>` (ASCII
//        بس — الـheader ما بيشيلش عربي؛ التطبيق هو اللي بيبني الجملة).
//   400  bad_json / bad_kind / bad_mime / bad_image / image_too_large
//   401  session_required — مفيش جلسة مستخدم
//   405  method_not_allowed
//   429  daily_cap / global_cap — و`message` جملة عربي التطبيق بيعرضها زي ما هي
//   500  missing_env:<الاسم>
//   502  gemini_failed — و`detail` فيه حالة جوجل وأول الرد (المفتاح مش فيه)
//   503  cap_check_failed — **الحد بيقفل لما مايقدرش يعدّ**: حد بيفتح لما
//        القاعدة تقع مش حد. الإدخال بالإيد في التطبيق مش محتاج الدالة دي.
//
// المثبّت لما يتقاعد (٤٠٤ + NOT_FOUND) **أو يبقى تحت ضغط (٥٠٣ / ٤٢٩)** → مرة
// واحدة على البديل، وبصوت عالي في اللوج. ٤٠٠ **ما بيعملش** ده — إخفاء رفض
// الـschema هو بالظبط تغيّر السلوك الصامت اللي التثبيت موجود عشان يمنعه.
// القاعدة كلها في `fallbackReason` تحت.

/// حد القرايات الناجحة لكل مستخدم في يوم القاهرة الواحد.
const DAILY_CAP_PER_USER = 20;

/// سقف التطبيق كله في اليوم — الحماية من مصنع المستخدمين المجهولين.
const DAILY_CAP_GLOBAL = 500;

/// الموديل: **جوجل هي اللي بتقرّر يعيش قد إيه، مش إحنا.** رسالة الـ٤٠٤ هي
/// مصدر الحقيقة. قارئ أدوية ما ينفعش سلوكه يتغيّر في صمت، فالمثبّت هو الأصل.
const PINNED_MODEL = 'gemini-3.6-flash';
const FALLBACK_MODEL = 'gemini-flash-latest';

/// الصورة بتوصل متصغّرة من التطبيق (C1: ضلع ١٦٠٠، حوالي نص ميجا). ٨ ميجا
/// base64 سقف للأمان مش هدف.
const MAX_IMAGE_BASE64_CHARS = 8 * 1024 * 1024;

const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];

/// مهلة نداء جوجل الواحد. **مفيش نداء من غير مهلة**: من غيرها الدالة بتفضل
/// مستنية لحد ما المنصة تقتلها، والتطبيق قاعد على «بيقرا الروشتة…» بالدقايق
/// من غير ما يقول أي حاجة. المحاولتين (المثبّت والبديل) لازم يخلّصوا تحت
/// مهلة العميل (٧٥ ثانية).
const GEMINI_TIMEOUT_MS = Number(Deno.env.get('GEMINI_TIMEOUT_MS') ?? '') || 25_000;

/// مهلة نداء القاعدة (عدّاد الحد) — لو اتعلّقت، بنقفل مش بنستنى.
const DB_TIMEOUT_MS = 10_000;

/// **التفكير مقفول افتراضياً.** الموديلات الحديثة بتفكّر قبل ما ترد، والتفكير
/// وقت — ونقل أرقام وأسامي من ورقة مش محتاج تفكير. ده أكبر سبب في إن القراية
/// كانت بتاخد ١٥–٢٠ ثانية عند جوجل. لو القراية بوظت، رجّعه من السر
/// `GEMINI_THINKING_BUDGET` (فاضي = ما نبعتش الحقل أصلاً).
const THINKING_BUDGET_RAW = (Deno.env.get('GEMINI_THINKING_BUDGET') ?? '0').trim();

const BUSY_MESSAGE = 'الخدمة زحمة دلوقتي — استنى شوية وجرّب تاني.';

const CAP_MESSAGE = 'وصلت لحد القراءات النهارده — جرّب بكرة';
const GLOBAL_CAP_MESSAGE = 'القراية بالصورة واقفة النهارده — جرّب بكرة، أو اكتبها بإيدك';

// ------------------------------------------------- البرومبت والـschema لكل نوع
//
// منقولين من Dart **بالحرف** (C2). القاعدة ٦ مكتوبة للموديل نفسه: ما تخمّنش،
// وما تنصحش. `test/ai/ai_read_function_test.dart` بيقرا الملف ده وبيقع لو
// الجمل دي اتشالت أو لو الـschema بتاع التحليل بقى فيه نطاق أو علامة أو تفسير.

const STRING_FIELD = {
  type: 'OBJECT',
  properties: {
    value: { type: 'STRING', nullable: true },
    confidence: { type: 'NUMBER' },
    note: { type: 'STRING', nullable: true },
  },
  required: ['confidence'],
};

// <prescription-prompt>
const PRESCRIPTION_PROMPT = `You are reading a photo of a paper medical prescription from Egypt (Arabic and/or English, often handwritten).
Extract ONLY what is literally written. Never guess, infer, or complete anything.

For each medication line return: name (as written, keep Latin drug names in Latin), amount (e.g. "قرص واحد", "1 tablet", "5 ml"), timing, durationDays.

Timing rules:
- Prefer meal-relative timing: anchor ∈ {wake, breakfast, lunch, dinner, sleep}, relation ∈ {before, after, at}, offsetMinutes only if a number of minutes is written.
- "1×3" / "3 times daily" style with no meal named: set timesPerDay and leave anchor null.
- Set clockTime "HH:MM" (24h) ONLY if an explicit clock time is written on the paper.
- If timing is unclear, illegible, or "when needed": leave anchor, clockTime and timesPerDay null, set a low confidence, and set note to "مش متأكد — اسأل الصيدلي".

durationDays: ONLY if a duration is written. If not written, value must be null with confidence 1 — a missing duration is not an error.

confidence is 0..1 for each field based on legibility. Below 0.8 means a human must check it.
Do not add, remove, rename or substitute any medication. Do not give medical advice.
`;
// </prescription-prompt>

const PRESCRIPTION_SCHEMA = {
  type: 'OBJECT',
  properties: {
    doctor: STRING_FIELD,
    medications: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: STRING_FIELD,
          amount: STRING_FIELD,
          timing: {
            type: 'OBJECT',
            properties: {
              anchor: {
                type: 'STRING',
                nullable: true,
                enum: ['wake', 'breakfast', 'lunch', 'dinner', 'sleep'],
              },
              relation: {
                type: 'STRING',
                nullable: true,
                enum: ['before', 'after', 'at'],
              },
              offsetMinutes: { type: 'INTEGER', nullable: true },
              clockTime: { type: 'STRING', nullable: true },
              timesPerDay: { type: 'INTEGER', nullable: true },
              confidence: { type: 'NUMBER' },
              note: { type: 'STRING', nullable: true },
            },
            required: ['confidence'],
          },
          durationDays: {
            type: 'OBJECT',
            properties: {
              value: { type: 'INTEGER', nullable: true },
              confidence: { type: 'NUMBER' },
              note: { type: 'STRING', nullable: true },
            },
            required: ['confidence'],
          },
        },
        required: ['name', 'amount', 'timing', 'durationDays'],
      },
    },
  },
  required: ['medications'],
};

// <lab-system-instruction>
const LAB_SYSTEM_INSTRUCTION = `You transcribe numbers from a photo of a medical lab report. You are not a doctor and you never act like one.
Return ONLY: the lab name, the report date, and for each test its name exactly as printed, its numeric result, and its unit.
Do NOT return reference ranges. Do NOT return H/L or high/low flags or asterisks.
Do NOT interpret, diagnose, recommend, or advise. Never say a value is high, low, normal, abnormal, dangerous or concerning.
Never suggest seeing a doctor, repeating a test, or any action.
If a value is not a number or is illegible, return null for it with confidence 0. Never guess a digit.
`;
// </lab-system-instruction>

const LAB_PROMPT = `Read the attached lab report. For each result row return test (name as printed, keep Latin names in Latin), value (the number only), unit (as printed).
lab: the laboratory name if printed. reportDate: YYYY-MM-DD only if a date is printed.
confidence is 0..1 per field based on legibility. Below 0.8 means a human must check it.
Do not add, merge, rename or skip rows.
`;

// <lab-schema>
// حقل التحليل **من غير `note`** — مفيش أي قناة نص حر من الموديل للشاشة.
const LAB_STRING_FIELD = {
  type: 'OBJECT',
  properties: {
    value: { type: 'STRING', nullable: true },
    confidence: { type: 'NUMBER' },
  },
  required: ['confidence'],
};

const LAB_SCHEMA = {
  type: 'OBJECT',
  properties: {
    lab: LAB_STRING_FIELD,
    reportDate: LAB_STRING_FIELD,
    results: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          test: LAB_STRING_FIELD,
          value: {
            type: 'OBJECT',
            properties: {
              value: { type: 'NUMBER', nullable: true },
              confidence: { type: 'NUMBER' },
            },
            required: ['confidence'],
          },
          unit: LAB_STRING_FIELD,
        },
        required: ['test', 'value', 'unit'],
      },
    },
  },
  required: ['results'],
};
// </lab-schema>

type Kind = 'prescription' | 'lab';

const KINDS: Record<Kind, { prompt: string; schema: unknown; systemInstruction?: string }> = {
  prescription: { prompt: PRESCRIPTION_PROMPT, schema: PRESCRIPTION_SCHEMA },
  lab: { prompt: LAB_PROMPT, schema: LAB_SCHEMA, systemInstruction: LAB_SYSTEM_INSTRUCTION },
};

// ---------------------------------------------------------------- أدوات

function excerpt(text: string, max = 800): string {
  return text.length <= max ? text : `${text.substring(0, max)}…`;
}

/// الـpayload بتاع التوكن. **من غير تحقق من التوقيع** — البوابة (`verify_jwt`)
/// عملته قبل ما نوصل هنا. عشان كده `verify_jwt` ما يتقفلش.
function jwtClaims(token: string): { sub?: string; role?: string } | null {
  try {
    const part = token.split('.')[1];
    if (!part) return null;
    const padded = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
    const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// الموديل ده رفض `thinkingConfig`؟ بيتفتكر لنسخة الدالة دي — فالثمن محاولة
/// واحدة زيادة عند أول طلب، مش عند كل طلب.
let thinkingRejected = false;

async function db(url: string, serviceKey: string, path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    signal: AbortSignal.timeout(DB_TIMEOUT_MS),
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

/// محاولة واحدة عند جوجل: الحالة، نص الرد، وهل المهلة خلصت.
/// `status = 0` معناها ما وصلناش لرد أصلاً (شبكة أو مهلة).
type Attempt = { status: number; raw: string; timedOut: boolean };

async function callGemini(model: string, key: string, body: string): Promise<Attempt> {
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        // المفتاح في header — مش في الرابط — فما بيظهرش في أي لوج للروابط.
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
        body,
        signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      },
    );
    return { status: res.status, raw: await res.text(), timedOut: false };
  } catch (error) {
    const name = (error as { name?: string })?.name ?? '';
    const timedOut = name === 'TimeoutError' || name === 'AbortError';
    return { status: 0, raw: `transport: ${error}`, timedOut };
  }
}

// <fallback-rule>
/// إمتى المثبّت يسيب مكانه للبديل — **مرة واحدة**، وبصوت عالي. بترجّع السبب
/// (ASCII، بيروح في `x-model-warning`) أو null = مفيش بديل.
///
///   retired     ٤٠٤ + NOT_FOUND — جوجل قفلت الموديل. لازم تثبيت جديد بالإيد.
///   overloaded  ٥٠٣ أو ٤٢٩ — المثبّت تحت ضغط أو حصته خلصت **دلوقتي**. زحمة
///               على موديل واحد وسط عرض ما ينفعش تتقري «مقدرتش أقرا». مفيش
///               حاجة تتثبّت من جديد؛ لو اتكرر كتير دي مسألة حصة.
///   timeout     المهلة خلصت من غير رد. نفس المعنى عند المستخدم (الخدمة
///               بطيئة دلوقتي)، بس بيتسجّل باسمه عشان يتفرّق في اللوج.
///
/// ٤٠٠ **مش هنا، وما تتضافش**: رفض الـschema لازم يبان، وإخفاؤه ببديل هو
/// بالظبط تغيّر السلوك الصامت اللي التثبيت موجود عشان يمنعه. و٤٠٤ من غير
/// NOT_FOUND مش تقاعد. البديل نفسه ما بيتبدّلش: لو وقع → ٥٠٢ gemini_failed.
function fallbackReason(status: number, raw: string, timedOut = false): 'retired' | 'overloaded' | 'timeout' | null {
  if (timedOut) return 'timeout';
  if (status === 404 && raw.includes('NOT_FOUND')) return 'retired';
  if (status === 503 || status === 429) return 'overloaded';
  return null;
}
// </fallback-rule>

Deno.serve(async (req: Request): Promise<Response> => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
    });

  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  // ---- ١. مين بينادي. المفتاح المنشور لوحده (role = anon) مش جلسة.
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const claims = jwtClaims(bearer);
  if (!claims || claims.role !== 'authenticated' || !claims.sub || !UUID.test(claims.sub)) {
    return json({ error: 'session_required' }, 401);
  }
  const userId = claims.sub;

  // ---- ٢. الطلب: نوع + صورة + نوع ملف. **مفيش برومبت من العميل.**
  let input: { kind?: unknown; image?: unknown; mime?: unknown };
  try {
    input = JSON.parse(await req.text());
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  if (input === null || typeof input !== 'object') return json({ error: 'bad_json' }, 400);
  if (input.kind !== 'prescription' && input.kind !== 'lab') return json({ error: 'bad_kind' }, 400);
  if (typeof input.mime !== 'string' || !ALLOWED_MIME.includes(input.mime)) {
    return json({ error: 'bad_mime' }, 400);
  }
  if (typeof input.image !== 'string' || input.image.length === 0 || !/^[A-Za-z0-9+/]+=*$/.test(input.image)) {
    return json({ error: 'bad_image' }, 400);
  }
  if (input.image.length > MAX_IMAGE_BASE64_CHARS) return json({ error: 'image_too_large' }, 400);
  const kind = input.kind as Kind;
  const image = input.image as string;
  const mime = input.mime as string;
  const bytes = Math.floor((image.length * 3) / 4);

  // ---- الأسرار. اسم السر الناقص مش سر، فبيتقال بوضوح.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  for (const [name, value] of [
    ['SUPABASE_URL', supabaseUrl],
    ['SUPABASE_SERVICE_ROLE_KEY', serviceKey],
    ['GEMINI_API_KEY', geminiKey],
  ]) {
    if (!value) {
      console.error(`ai-read: missing_env:${name}`);
      return json({ error: `missing_env:${name}` }, 500);
    }
  }
  const pinned = (Deno.env.get('GEMINI_MODEL') ?? '').trim() || PINNED_MODEL;
  const fallback = (Deno.env.get('GEMINI_FALLBACK_MODEL') ?? '').trim() || FALLBACK_MODEL;

  // ---- ٣. الحد — قبل ما جوجل تتكلّم. التعريف الوحيد لـ«النهارده» في ٠٠١٣.
  let userReads: number;
  let allReads: number;
  try {
    const res = await db(supabaseUrl!, serviceKey!, 'rpc/ai_reads_today_for_service', {
      method: 'POST',
      body: JSON.stringify({ p_user: userId }),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${excerpt(text, 300)}`);
    const row = (JSON.parse(text) as { user_reads: number; all_reads: number }[])[0];
    userReads = row.user_reads;
    allReads = row.all_reads;
  } catch (error) {
    console.error(`ai-read: cap check failed — closing: ${error}`);
    return json({ error: 'cap_check_failed' }, 503);
  }
  if (userReads >= DAILY_CAP_PER_USER) {
    console.log(`ai-read: daily_cap user=${userId} reads=${userReads}`);
    return json({ error: 'daily_cap', message: CAP_MESSAGE }, 429);
  }
  if (allReads >= DAILY_CAP_GLOBAL) {
    console.error(`ai-read: GLOBAL CAP reached (${allReads}) — every read is refused until Cairo midnight`);
    return json({ error: 'global_cap', message: GLOBAL_CAP_MESSAGE }, 429);
  }

  // ---- ٤. جوجل. نفس الطلب اللي التطبيق كان بيبنيه قبل C2، + قفل التفكير.
  const spec = KINDS[kind];
  const bodyWith = (thinking: boolean) =>
    JSON.stringify({
      ...(spec.systemInstruction
        ? { systemInstruction: { parts: [{ text: spec.systemInstruction }] } }
        : {}),
      contents: [
        { parts: [{ text: spec.prompt }, { inline_data: { mime_type: mime, data: image } }] },
      ],
      generationConfig: {
        temperature: 0,
        responseMimeType: 'application/json',
        responseSchema: spec.schema,
        ...(thinking ? { thinkingConfig: { thinkingBudget: Number(THINKING_BUDGET_RAW) } } : {}),
      },
    });

  const started = Date.now();
  let model = pinned;
  let warning: string | null = null;

  // التفكير مقفول، **إلا لو الموديل ده رفض الحقل**. الرفض بيرجع ٤٠٠ فوري
  // (من غير أي شغل موديل)، فبنعيد مرة من غيره وبنفتكر — نفس النسخة من
  // الدالة مش هتحاول تاني. ده **مش** إخفاء ٤٠٠: مربوط باسم الحقل بالحرف،
  // وبيتسجّل بصوت عالي، ورفض الـschema بيفضل بيطلع زي ما هو.
  const sendThinking = THINKING_BUDGET_RAW !== '' && !thinkingRejected;
  let res = await callGemini(pinned, geminiKey!, bodyWith(sendThinking));
  if (sendThinking && res.status === 400 && /thinking/i.test(res.raw)) {
    thinkingRejected = true;
    console.error(`Gemini: WARNING ${pinned} رفض thinkingConfig — إعادة من غيره: ${excerpt(res.raw, 200)}`);
    res = await callGemini(pinned, geminiKey!, bodyWith(false));
  }
  const body = bodyWith(sendThinking && !thinkingRejected);

  const reason = fallbackReason(res.status, res.raw, res.timedOut);
  if (reason) {
    console.error(
      `Gemini: WARNING pinned model ${pinned} ${reason} (HTTP ${res.status}): ${excerpt(res.raw, 200)} — retrying once with ${fallback}`,
    );
    warning = `${pinned};${fallback};${reason}`;
    model = fallback;
    res = await callGemini(fallback, geminiKey!, body);
  }
  const { status, raw, timedOut } = res;
  const ok = status === 200;
  const durationMs = Date.now() - started;

  // ---- ٥. السجل. الفاشلة بتتسجّل وما بتتحسبش. وفشل الكتابة ما بياخدش
  // القراية من المريض — بس بيتقال بصوت عالي، لأن قراية ما اتسجّلتش ما اتعدّتش.
  try {
    const res = await db(supabaseUrl!, serviceKey!, 'ai_reads', {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ user_id: userId, kind, bytes, model, ok, duration_ms: durationMs }),
    });
    if (!res.ok) console.error(`ai-read: ⚠ ai_reads insert HTTP ${res.status}: ${excerpt(await res.text(), 300)}`);
  } catch (error) {
    console.error(`ai-read: ⚠ ai_reads insert failed: ${error}`);
  }

  if (!ok) {
    // الرد هو مصدر الحقيقة وقت العطل. المفتاح راح في header فمش جوّاه.
    const detail = `HTTP ${status}: ${excerpt(raw)}${warning ? ` (after fallback ${fallback})` : ''}`;
    console.error(`Gemini: ${detail} (${durationMs}ms)`);
    // زحمة أو مهلة مش «صوّر تاني»: الصورة سليمة والمشكلة عندهم. الرسالة
    // بتقول الحقيقة عشان المريض ما يفضلش يصوّر ورقته من أول وجديد.
    const busy = timedOut || fallbackReason(status, raw) === 'overloaded';
    return busy
      ? json({ error: 'gemini_busy', message: BUSY_MESSAGE, detail }, 503)
      : json({ error: 'gemini_failed', detail }, 502);
  }

  console.log(`ai-read: ok kind=${kind} model=${model} bytes=${bytes} ms=${durationMs} user=${userId}`);
  return new Response(raw, {
    status: 200,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...(warning ? { 'x-model-warning': warning } : {}),
    },
  });
});

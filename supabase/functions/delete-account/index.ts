// delete-account — «امسح حسابي» (Apple 5.1.1(v)).
//
// بتتلصق في محرر Edge Functions في لوحة Supabase. **من غير أي import**:
// كله `fetch` — نفس عُرف `escalate` و`verify-purchase`.
//
// ---------------------------------------------------------------- الطلب
//
//   POST /functions/v1/delete-account
//   Authorization: Bearer <جلسة المستخدم نفسه>   ← مش مفتاح الخدمة
//   { "confirm": "delete-my-account" }
//
// ---------------------------------------------------------------- الردود
//
//   200 { status: "deleted", kind }        كل حاجة اتمسحت، والمستخدم كمان
//   400 { status: "bad_request" }          من غير تأكيد صريح في الجسم
//   401 { status: "unauthorized" }         مفيش جلسة صالحة
//   500 { status: "not_configured" }       أسرار الدالة ناقصة
//   500 { status: "failed", step }         وقعت في خطوة — **المستخدم لسه
//                                          موجود**، والإعادة آمنة
//
// ---------------------------------------------------------------- الترتيب
//
// ١) الصور من الباكت (Storage API — المسح المباشر من الجدول ممنوع).
// ٢) الصفوف كلها في معاملة واحدة: `delete_account_for_service` (0033).
// ٣) المستخدم من Auth — **آخر حاجة**.
//
// كل خطوة بتتعاد من غير ضرر: وقعت في ١ ← مفيش صف اتمسح؛ وقعت في ٣ ← الصفوف
// اتمسحت والمستخدم لسه موجود، والإعادة بتلاقي الصفوف فاضية وتكمّل. مفيش
// حالة «نص حساب» يقدر يدخل بيها: طول ما المستخدم موجود، التطبيق بيقول
// «جرّب تاني» وما بيمسحش حاجة من على الموبايل.
//
// ---------------------------------------------------------------- الأسرار
//
// SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY — موجودين تلقائياً في أسرار
// الدالة. **مفتاح الخدمة عمره ما بيطلع من هنا**، ولا بيتكتب في لوج.
//
// **مفيش Deno على جهاز التطوير: الملف ده اتكتب واتراجع، وما اتشغّلش.**

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const CONFIRM = 'delete-my-account';
const STORAGE_BATCH = 500;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const service = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

/// المستخدم بتاع الجلسة — من GoTrue نفسه، مش من فك الـJWT بنفسنا.
async function userIdOf(jwt: string): Promise<string | null> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) return null;
  const body = (await res.json()) as { id?: string };
  return body.id ?? null;
}

async function rpc<T>(name: string, userId: string): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: service,
    body: JSON.stringify({ p_user: userId }),
  });
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}: ${await res.text()}`);
  return (await res.json()) as T;
}

/// ١) الصور — دفعات، والباكت بيرجّع 200 حتى لو اسم مش موجود (الإعادة آمنة).
async function deleteObjects(userId: string): Promise<number> {
  const rows = await rpc<{ bucket_id: string; name: string }[]>(
    'account_deletion_objects_for_service',
    userId,
  );
  const byBucket = new Map<string, string[]>();
  for (const r of rows) {
    const list = byBucket.get(r.bucket_id) ?? [];
    list.push(r.name);
    byBucket.set(r.bucket_id, list);
  }
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += STORAGE_BATCH) {
      const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
        method: 'DELETE',
        headers: service,
        body: JSON.stringify({ prefixes: names.slice(i, i + STORAGE_BATCH) }),
      });
      if (!res.ok) throw new Error(`storage ${bucket}: HTTP ${res.status}: ${await res.text()}`);
    }
  }
  return rows.length;
}

/// ٣) المستخدم — 404 معناها إنه اتمسح في محاولة قبل كده.
async function deleteAuthUser(userId: string): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE',
    headers: service,
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`auth: HTTP ${res.status}: ${await res.text()}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { status: 'bad_request' });
  if (!SUPABASE_URL || !SERVICE_KEY) return json(500, { status: 'not_configured' });

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  // مفتاح الخدمة نفسه مش جلسة مستخدم — الدالة دي للمستخدم يمسح نفسه وبس
  if (!jwt || jwt === SERVICE_KEY) return json(401, { status: 'unauthorized' });

  let body: { confirm?: string } = {};
  try {
    body = await req.json();
  } catch {
    // جسم مش JSON = من غير تأكيد
  }
  if (body.confirm !== CONFIRM) return json(400, { status: 'bad_request' });

  const userId = await userIdOf(jwt);
  if (!userId) return json(401, { status: 'unauthorized' });

  let step = 'storage';
  try {
    const objects = await deleteObjects(userId);
    step = 'rows';
    const result = await rpc<{ kind: string; removed_patients: number; removed_links: number }[]>(
      'delete_account_for_service',
      userId,
    );
    step = 'auth';
    await deleteAuthUser(userId);
    const kind = result[0]?.kind ?? 'empty';
    // لوج من غير أي بيان شخصي: النوع والأعداد بس
    console.log(`delete-account: ${kind} — objects=${objects} patients=${result[0]?.removed_patients ?? 0} links=${result[0]?.removed_links ?? 0}`);
    return json(200, { status: 'deleted', kind });
  } catch (error) {
    console.error(`delete-account: وقعت في ${step}: ${error}`);
    return json(500, { status: 'failed', step });
  }
});

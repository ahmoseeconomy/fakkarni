#!/usr/bin/env bash
# leak_check.sh <build-dir> <secrets-json>
#
# **حزمة الويب عامة.** أي حد بيفتح اللوحة بيقدر يقرا كل بايت فيها — فمفتاح
# جيميني أو أي سر تاني بيدخلها بالغلط بيبقى على الإنترنت في نفس اللحظة.
# السكربت ده بيتشغّل **بعد البناء وقبل الرفع**، وبيوقف الرفع لو لقى حاجة.
#
# **بيطبع اسم المفتاح وبس، عمره ما يطبع قيمته** — تقرير بيسرّب السر وهو
# بيبلّغ عنه أسوأ من مفيش تقرير.
#
# المسموح: `SUPABASE_URL` و`SUPABASE_ANON_KEY` وبس — دول بيشحنوا في كل
# نسخة من التطبيق أصلاً، والحاجز عليهم هو RLS مش إخفاؤهم.

set -uo pipefail

BUILD_DIR="${1:-}"
SECRETS="${2:-}"

if [[ -z "$BUILD_DIR" || -z "$SECRETS" ]]; then
  echo "usage: leak_check.sh <build-dir> <secrets-json>" >&2
  exit 2
fi
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "leak-check: مجلد البناء مش موجود: $BUILD_DIR" >&2
  exit 2
fi
if [[ ! -f "$SECRETS" ]]; then
  echo "leak-check: ملف الأسرار مش موجود: $SECRETS" >&2
  exit 2
fi

# **قايمة السماح** — مفتاحين وبس. أي اسم تاني في `secrets.json` قيمته
# واسمه الاتنين ممنوعين في الحزمة.
ALLOWED=("SUPABASE_URL" "SUPABASE_ANON_KEY")

allowed() {
  local needle="$1" k
  for k in "${ALLOWED[@]}"; do
    [[ "$k" == "$needle" ]] && return 0
  done
  return 1
}

# `-a` بيعامل الملفات الثنائية كنص: سر جوّه `.wasm` أو `.map` سر برضه.
contains() {
  grep -rqaF -- "$1" "$BUILD_DIR" 2>/dev/null
}

leaks=()

while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  if allowed "$key"; then
    continue
  fi

  # اسم المفتاح نفسه: وجوده معناه إن حد مرّر التعريف للبناء.
  if contains "$key"; then
    leaks+=("$key (الاسم)")
  fi

  value="$(jq -er --arg k "$key" '.[$k] | select(type == "string")' "$SECRETS" 2>/dev/null)"
  if [[ -z "${value:-}" ]]; then
    # قيمة فاضية أو مش نص — `grep` على فراغ بيطابق كل حاجة، فبنعدّي
    # **وبنقول**، عشان السكوت ما يتقراش «عدّى».
    echo "leak-check: تخطّينا فحص قيمة $key (فاضية أو مش نص)" >&2
    continue
  fi
  if contains "$value"; then
    leaks+=("$key (القيمة)")
  fi
done < <(jq -r 'keys[]' "$SECRETS")

# رموز ممنوعة مهما كان مصدرها — مش شرط تكون في `secrets.json`.
#
# **الاسم مقسوم عن قصد**: حارس `no_privileged_key_test` بيوقع لو الكلمة
# اتكتبت كاملة في أي ملف في الحزمة، **حتى في تعليق** — والسكربت ده جوّه
# الحزمة. القسمة بتخلّي الحارس يفضل مطلق من غير استثناء لملف.
for token in "service""_role" "AIza"; do
  if contains "$token"; then
    leaks+=("$token")
  fi
done

if (( ${#leaks[@]} > 0 )); then
  echo "" >&2
  echo "!! leak-check وقّف الرفع — الحزمة فيها حاجة مش مفروض تتنشر:" >&2
  for l in "${leaks[@]}"; do
    echo "   - $l" >&2
  done
  echo "" >&2
  echo "(الأسماء وبس — القيم عمرها ما تتطبع.)" >&2
  exit 1
fi

echo "leak-check: الحزمة نضيفة — المسموح بس (${ALLOWED[*]})."
exit 0

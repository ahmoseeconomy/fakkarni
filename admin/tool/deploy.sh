#!/usr/bin/env bash
# deploy.sh — بناء لوحة الأدمن ورفعها على Firebase Hosting.
#
#   bash admin/tool/deploy.sh            # بناء + فحص تسريب + رفع
#   bash admin/tool/deploy.sh --no-deploy  # بناء + فحص وبس
#
# **تعريفين وبس بيدخلوا البناء**: `SUPABASE_URL` و`SUPABASE_ANON_KEY`.
# عمرنا ما نبني الويب بـ`--dart-define-from-file=../secrets.json`: الملف ده
# فيه مفتاح جيميني كمان، وحزمة الويب **عامة** — أي حد بيفتح اللوحة بيقدر
# يقراها بايت بايت. عشان كده السكربت بيقرا المفتاحين بالاسم، وبيشغّل
# `leak_check.sh` بعد البناء، والرفع بيقف لو لقى أي حاجة.
#
# **ورابط مشروع سوپابيز ما بيتكوميتش**: `firebase.json` فيه علامة
# `__SUPABASE_ORIGIN__`، والسكربت بيكتب `firebase.deploy.json` مؤقت
# (متجاهَل في git) وبيرفع بيه عن طريق `--config`.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ADMIN="$ROOT/admin"
SECRETS="$ROOT/secrets.json"
SITE_TARGET="admin"
GENERATED="$ROOT/firebase.deploy.json"

DEPLOY=1
[[ "${1:-}" == "--no-deploy" ]] && DEPLOY=0

command -v jq >/dev/null || { echo "محتاج jq: brew install jq" >&2; exit 2; }
[[ -f "$SECRETS" ]] || { echo "مفيش $SECRETS" >&2; exit 2; }

# القيم بتتقرا في متغيّرات وعمرها ما تتطبع.
SUPABASE_URL="$(jq -er '.SUPABASE_URL' "$SECRETS")" || { echo "SUPABASE_URL مش في secrets.json" >&2; exit 2; }
SUPABASE_ANON_KEY="$(jq -er '.SUPABASE_ANON_KEY' "$SECRETS")" || { echo "SUPABASE_ANON_KEY مش في secrets.json" >&2; exit 2; }

echo "==> بناء الويب (release)"
cd "$ADMIN" || exit 2
# `--csp` بيطلّع جافاسكريبت من غير eval، و`--no-web-resources-cdn` بينزّل
# CanvasKit جوّه الحزمة — الاتنين اللي بيخلّوا الـCSP تحت تقدر تبقى ضيّقة.
flutter build web --release --csp --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" || exit 1

echo
echo "==> فحص التسريب"
bash "$HERE/leak_check.sh" "$ADMIN/build/web" "$SECRETS" || {
  echo "الرفع اتوقف." >&2
  exit 1
}

if (( DEPLOY == 0 )); then
  echo
  echo "==> --no-deploy: وقفنا قبل الرفع."
  exit 0
fi

command -v firebase >/dev/null || {
  echo "مفيش firebase CLI: npm i -g firebase-tools ثم firebase login" >&2
  exit 2
}

# أصل سوپابيز للـCSP — https وwss لنفس المضيف.
ORIGIN="${SUPABASE_URL%/}"
HOST="${ORIGIN#https://}"
CSP_ORIGINS="$ORIGIN wss://$HOST"

cleanup() { rm -f "$GENERATED"; }
trap cleanup EXIT

python3 - "$ROOT/firebase.json" "$GENERATED" "$CSP_ORIGINS" <<'PY'
import sys
src, dst, origins = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding='utf-8').read()
if '__SUPABASE_ORIGIN__' not in text:
    sys.exit('firebase.json مفيهوش __SUPABASE_ORIGIN__ — اتغيّر؟')
open(dst, 'w', encoding='utf-8').write(text.replace('__SUPABASE_ORIGIN__', origins))
PY
[[ -f "$GENERATED" ]] || exit 1

echo
echo "==> الرفع على hosting:$SITE_TARGET"
cd "$ROOT" || exit 2
firebase deploy --only "hosting:$SITE_TARGET" --config "$GENERATED"
STATUS=$?

if (( STATUS == 0 )); then
  echo
  echo "تم. لو ده أول رفع، اعمل الموقع الأول:"
  echo "  firebase hosting:sites:create fakkarni-admin"
fi
exit $STATUS

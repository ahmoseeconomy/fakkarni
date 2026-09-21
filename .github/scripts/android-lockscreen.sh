#!/usr/bin/env bash
#
# سكّة أندرويد على المحاكي — كل خطوات التشغيلة في ملف واحد.
#
# **ليه ملف أصلاً، ومش `script:` في الـworkflow؟**
# `reactivecircus/android-emulator-runner` بينفّذ كل **سطر** من `script:`
# في صدفة لوحده. ده مقروء من لوج الشغلانة نفسها، مش من التوثيق:
#
#   [command]/usr/bin/sh -c adb shell settings put global window_animation_scale 0
#   [command]/usr/bin/sh -c adb install -r -g … || true
#   [command]/usr/bin/sh -c cd android && ./gradlew :app:connectedDebugAndroidTest --info
#
# ولكل سطر `/usr/bin/sh -c` بتاعه. النتيجة أربع حاجات كانت بتكسر
# التشغيلة في صمت:
#   - `set +e` و`set -e` ما بيعدّوش للسطر اللي بعده.
#   - `STATUS=$?` بيضيع، فـ`exit $STATUS` ما بينقلش نتيجة الاختبار خالص.
#   - `cd android` ما بيفضلش.
#   - وسطر متقسّم بـ`\` بيتنفّذ **نصّين**: النص التاني — اللي فيه
#     `|| true` — بيروح في داهية، فالسطر الأول بيقع لوحده.
# وأي سطر بيقع بينهي الخطوة فوراً، فاللي بعده عمره ما بيجري.
#
# ده اللي خلّى تشغيلتين خضرا (الاختبار نجح) يبقوا حمرا: `adb pull` على
# مجلد لقطات **مش موجود في تشغيلة ناجحة** كان بيرجّع ١.
#
# القاعدة دلوقتي: الـ`script:` سطر واحد بينده الملف ده، والملف ده هو
# اللي فيه المنطق — بصدفة واحدة، ومتغيّرات بتعيش، وخروج بحالة جرادل.

set -uo pipefail   # **مش** -e: جمع الأدلة لازم يجري حتى لو الاختبار وقع

PKG=com.fakkarni.fakkarni
ART=artifacts

mkdir -p "$ART/screen"

# ---- تجهيز الجهاز -----------------------------------------------------
adb shell settings put global window_animation_scale 0 || true
adb shell settings put global transition_animation_scale 0 || true
adb shell settings put global animator_duration_scale 0 || true
# إذن الإشعارات على ١٣+ — من غيره مفيش إشعار أصلاً
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk || true
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
# المنبّه الدقيق على ١٢+
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true

# ---- اللوج هو أثر أندرويد --------------------------------------------
# `diag()` بتكتب في ملف على iOS بس؛ هنا السطر بيخرج من `debugPrint`
# للوج. من غير اللوج مفيش أي وسيلة نعرف بيها إذا الـisolate اشتغل.
adb logcat -c || true
adb logcat -v time > "$ART/logcat-full.txt" 2>&1 &
LOGCAT_PID=$!

# ---- الاختبار ---------------------------------------------------------
( cd android && ./gradlew :app:connectedDebugAndroidTest --info )
STATUS=$?

kill "$LOGCAT_PID" 2>/dev/null || true
wait "$LOGCAT_PID" 2>/dev/null || true
sleep 2

# ---- الأدلة — ولا سطر هنا يقدر يحمّر الشغلانة ------------------------
# تشغيلة ناجحة من غير لقطات هي **الحالة العادية**، مش خطأ.
collect() {
  # اللقطات: `screencap` بيكتب في /data/local/tmp (يوزر الشل، وadb
  # بيوصله دايماً)، والمكتبة بتكتب في الكاش الخارجي بتاع التطبيق —
  # وده تحت التخزين المحدود فالسحب منه مش مضمون.
  adb pull /data/local/tmp/. "$ART/screen" >/dev/null 2>&1 || true
  adb root >/dev/null 2>&1 || true
  adb wait-for-device >/dev/null 2>&1 || true
  adb pull "/sdcard/Android/data/$PKG/cache/fkshots" "$ART/screen" >/dev/null 2>&1 || true
  # حاجتنا بس — /data/local/tmp فيه حاجات تانية
  find "$ART/screen" -type f \
    ! -name 'fk-*' ! -name 'hierarchy-*' ! -name 'screen-*' \
    -delete 2>/dev/null || true

  # نسخة مفلترة جنب الكاملة — الكاملة فيها كل حاجة على الجهاز
  grep -i -E 'flutter|fakkarni|FKDIAG|FKTEST|Isolate|Handle|TestHook' \
    "$ART/logcat-full.txt" > "$ART/logcat-ours.txt" 2>/dev/null || true

  {
    echo "==== حالة جرادل: $STATUS ===="
    echo "==== حكم TestRunner (ده اللي بيتقري الأول) ===="
    # **شغلانة حمرا مش معناها اختبار أحمر.** السطر ده هو اللي بيقول.
    grep -a "TestRunner: run finished" "$ART/logcat-full.txt" || \
      echo "(مفيش سطر «run finished» — الاختبار ما وصلش لآخره)"
    echo "==== سكّة الصحوة ===="
    grep -a -E "Isolate: (دخلنا|خلص) المعالج" "$ART/logcat-full.txt" || \
      echo "(مفيش أي سطر Isolate: — الدوسة ما وصلتش دارت)"
  } | tee "$ART/verdict.txt" || true

  echo "---- اللقطات ----"
  ls -la "$ART/screen" || true
  echo "---- تقرير جرادل ----"
  # **مجلد البناء منقول**: `android/build.gradle.kts` بيحط
  # `rootProject.layout.buildDirectory` على `../../build`، يعني تقارير
  # وحدة app في `<الريبو>/build/app/` — مش في `android/app/build/`.
  # الـworkflow كان بيرفع المسار التاني، وهو مش موجود ولا مرة.
  ls -la build/app/reports/androidTests/connected 2>/dev/null || \
    echo "(مفيش تقرير HTML)"
  ls -la build/app/outputs/androidTest-results/connected 2>/dev/null || \
    echo "(مفيش نتايج XML)"
  echo "---- آخر ٨٠ سطر تخصّنا ----"
  tail -80 "$ART/logcat-ours.txt" || true
}
collect || true

# حالة الاختبار هي حالة الشغلانة — وبس.
exit "$STATUS"

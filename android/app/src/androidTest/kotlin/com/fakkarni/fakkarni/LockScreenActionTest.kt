package com.fakkarni.fakkarni

import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.regex.Pattern

/**
 * **سكّة أندرويد: زرار على الإشعار.**
 *
 * دي السكّة الوحيدة في الوعد اللي عمرها ما اشتغلت على أي جهاز. على iOS
 * اتثبت يوم ٢٠ سبتمبر إن الطريق ده **مش** بيتنفّذ خالص (النظام بيفتح
 * التطبيق ويسيب الرد في getNotificationAppLaunchDetails)، فاللي فاضل هو
 * أندرويد — ومفيش جهاز أندرويد هنا والمحاكي بيقع على مستوى QEMU على
 * الماك ده. فالاختبار بيتشغّل على محاكي في CI.
 *
 * **تشغيلة ٢٢ سبتمبر ٢٠٢٦ أثبتت المستقبِل الناقص**: أول مرة في التاريخ
 * دوسة على زرار أندرويد توصل دارت (`Isolate: دخلنا المعالج`). وبعدين
 * وقعت عند **فتح** القاعدة، قبل أي كتابة:
 * `SqliteException(5): database is locked … pragma journal_mode = WAL`.
 *
 * **والقفل اتحسم في التشغيلة الرابعة: الاختبار هو اللي كان ماسكه.**
 * النسخة القديمة كانت بتفتح `fakkarni.sqlite` بـ`SQLiteDatabase` بتاع
 * إطار أندرويد، `OPEN_READWRITE`، من ٣٠ ملّي بعد الدوسة وكل نص ثانية —
 * وكان مكتوب فوقها إنها «بتفتح الملف زي ما التطبيق بيفتحه»، وده كان
 * غلط: ده اتصال **تاني خالص** بإعداد journal بتاعه وأقفاله بتاعته، مش
 * sqlite3 بتاع drift بالـpragmas بتاعتنا. **والدليل إنه كان بيقلب الملف
 * برّه WAL**: قبل التغيير ما كانش فيه `-wal` ولا `-shm` في أي لقطة؛
 * بعده الاتنين موجودين قبل الدوسة (`-wal` ٤٢٨ كيلو)، والقفل راح، والصف
 * اتكتب (`journal_mode = wal، taken = 1`). أداة القياس كانت بتكسّر اللي
 * بتقيسه.
 *
 * **والسكّة نفسها اتثبتت يوم ٢٢ سبتمبر ٢٠٢٦**: دوسة ← معالج ← صف جرعة
 * على أندرويد، من غير أي شك. ٩.٦ ثانية من الدوسة لسطر النهاية — آمنة
 * هنا لأن العملية حية ومثبّتة على `adj 0`؛ مش آمنة بالضرورة في السكّة
 * المقتولة، شوف آخر الشرح.
 *
 * فالنسخة دي **ما بتفتحش الملف الحي خالص**:
 *  أ. بتستنّى على **اللوج**: سطر النهاية بتاع المعالج، نجاح أو فشل.
 *  ب. وبعد السطر ده بس، بتاخد **نسخة** من الملفات التلاتة وتقرا النسخة
 *     `OPEN_READONLY` — بما فيها `pragma journal_mode`.
 *  ج. ولقطة الملفات (موجود/حجم/تاريخ) بتتاخد **قبل** أي قراية بتاعتنا،
 *     على الجهتين: قبل الدوسة وبعد سطر النهاية.
 *
 * **لسه مفتوح، ومتسجّل مش متصلّح:** `am kill` مش بيقتل العملية هنا.
 * الاختبار المُجهَّز بيجري **جوّه** عملية التطبيق، والـinstrumentation
 * بيثبّتها على `adj 0`، و`am kill` بيقتل عمليات الخلفية بس. يعني سيناريو
 * «التطبيق مقتول» لسه ما اتجرّبش. اللي الملف ده بيثبته هو إن دوسة على
 * زرار في الستارة بتوصل دارت وبتكتب الصف — مش أكتر.
 *
 * **والتسعة ونص ثانية دي متعلّقة بالسكّة دي بالظبط.** العملية هنا حية
 * ومثبّتة، فالشغل بياخد وقته. في السكّة المقتولة الـ`BroadcastReceiver`
 * بيرجع والعملية بتنزل لأولوية «مخزّنة» — ٩.٦ ثانية شغل هناك ممكن
 * تتقطع في نصها. الرقم ده اتسجّل هنا عشان يتقرا مع اختبار السكّة
 * المقتولة لما يتكتب، مش عشان يتقرا كإنه «تمام».
 */
@RunWith(AndroidJUnit4::class)
class LockScreenActionTest {

    private val device: UiDevice
        get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val pkg = "com.fakkarni.fakkarni"

    /** الملف اللي التطبيق بيفتحه بالظبط — `connection.dart`. */
    private val dbFile: File
        get() = File(File(context.filesDir.parentFile, "app_flutter"), "fakkarni.sqlite")

    private val dbNames =
        listOf("fakkarni.sqlite", "fakkarni.sqlite-wal", "fakkarni.sqlite-shm")

    private val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    /**
     * سطر النهاية بتاع المعالج في `bootstrap.dart`.
     *
     * `handled=ok` علامة **لاتينية** عن قصد: مقارنة عربية على مخرج
     * `logcat` ماشية على ترميز ماشي على أكتر من طبقة، والسطر ده هو اللي
     * الاختبار كله بيستنّاه.
     */
    private val handledOk = "handled=ok"

    /** سطر الفشل — موجود من قبل، وبيتقري كما هو. */
    private val handleFailed = "مقدرش يتعالج"

    @Test
    fun lockScreenConfirmWritesTheDoseAndKillsTheLadder() {
        // ١ — زرع جرعة في أقرب دقيقة جاية، من برّه التطبيق
        launchWithSeed(60)
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 20_000)
        // الجدولة بتحصل في main بعد الزرع
        Thread.sleep(5_000)

        // ٢ — Home، وبعدين `am kill`. المنبّه بيفضل عند النظام.
        //
        // **مش بيقتل العملية فعلاً** (شوف الشرح فوق) — التأكيد اللي تحت
        // بيقيس علم الحزمة، مش موت العملية، والفرق ده متسجّل في CLAUDE.md
        // عشان يتصلّح لوحده.
        device.pressHome()
        Thread.sleep(2_000)
        device.executeShellCommand("am kill $pkg")
        Thread.sleep(2_000)
        assertTrue(
            "am kill المفروض يسيب الحزمة شغّالة مش موقوفة — " +
                "force-stop كان هيلغي المنبّه ويخلّي الاختبار يقع لسبب غلط",
            !isPackageStopped(),
        )

        // ٣ — الإشعار، الستارة، والزرار
        val appeared = device.wait(Until.hasObject(By.textContains("TestDose")), 90_000)
        if (!appeared) {
            device.openNotification()
            device.wait(Until.hasObject(By.textContains("TestDose")), 30_000)
        }
        device.openNotification()
        device.wait(Until.hasObject(By.textContains("TestDose")), 15_000)

        // الأزرار ممكن تكون مطويّة — الفرد بيختلف بين النسخ، فبنجرب
        // الاتنين: ضغطة مطوّلة على الإشعار، وبعدين السهم لو موجود.
        device.findObject(By.textContains("TestDose"))?.let { notification ->
            notification.longClick()
            Thread.sleep(1_000)
        }
        device.findObject(By.desc("Expand"))?.click()
        Thread.sleep(1_000)

        val taken = device.wait(Until.findObject(By.text("أخدته")), 10_000)
        assertTrue("زرار «أخدته» ما ظهرش في الستارة", taken != null)

        // **اللقطة الأولى: قبل الدوسة وقبل أي قراية بتاعتنا.** الفرق بينها
        // وبين اللقطة اللي بعد سطر النهاية هو اللي بيقول هل الـWAL اتعمل
        // أصلاً، ومين غيّر إيه.
        printSnapshot("قبل الدوسة")

        val baseline = handlerLines().size
        taken!!.click()
        val tappedAt = System.currentTimeMillis()

        // ٤ — الانتظار على **اللوج**، مش على القاعدة. الملف الحي ما
        // بيتفتحش هنا خالص: الاختبار كان أول متّهم في زحمة القفل.
        val outcome = awaitHandlerOutcome(timeoutMs = 60_000, baseline = baseline)
        val elapsed = System.currentTimeMillis() - tappedAt

        if (outcome == null) {
            printSnapshot("بعد المهلة")
            dumpLog()
            fail("مفيش سطر نهاية من المعالج خلال ٦٠ ثانية بعد الدوسة")
        }
        println("FKTEST: سطر نهاية المعالج بعد ${elapsed}ms — $outcome")

        // **اللقطة التانية: بعد سطر النهاية، ولسه قبل أي قراية بتاعتنا.**
        printSnapshot("بعد سطر النهاية")

        if (!outcome!!.contains(handledOk)) {
            dumpLog()
            fail("المعالج وقع: $outcome")
        }

        // ٥ — وبعد كده بس، القاعدة — و**نسخة منها**، مش الملف الحي
        val (mode, count) = readCopy()
        println("FKTEST: journal_mode في النسخة = $mode، taken = $count")
        if (count != 1) {
            dumpLog()
            fail("الجرعة المفروض اتسجّلت taken — العدّ في النسخة = $count")
        }

        // ٦ — و«يومك» بيعرضها **مؤكَّدة**
        //
        // النسخة القديمة كانت بتدوّر على «TestDose» في أي مكان — والاسم ده
        // موجود في الحالتين (السطر الهادي والكارت الذهبي)، فالتأكيد كان
        // بيعدّي على شاشة بتقول «لسه ما اتأكدتش». حارس ما يقدرش يقع
        // للسبب اللي في اسمه = مش حارس.
        launchWithSeed(0)
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 20_000)
        Thread.sleep(6_000)

        when (val shown = doseOnScreen()) {
            DoseOnScreen.TAKEN -> Unit
            DoseOnScreen.UNCONFIRMED -> {
                captureScreen("stale")
                dumpLog()
                fail(
                    "«يومك» بايتة (stale): الصف مكتوب taken في القاعدة، " +
                        "والشاشة لسه بتقول «$unconfirmedText». الـisolate كتب " +
                        "من نسخة قاعدة تانية، والاستعلامات المتدفّقة بتاعة " +
                        "الـmain isolate ما سمعتش بالكتابة.",
                )
            }
            DoseOnScreen.NOT_FOUND -> {
                captureScreen("not-found")
                dumpLog()
                fail(
                    "«يومك» مش بتعرض الجرعة لا مؤكَّدة ولا مش مؤكَّدة بعد " +
                        "${maxSwipes} تمريرة — مش بايتة، مستخبية أو الشاشة " +
                        "أصلاً مش «يومك». شوف اللقطة وشجرة النوافذ ($shown).",
                )
            }
        }
    }

    /** الحالة اللي «يومك» بتعرضها للجرعة المزروعة. */
    private enum class DoseOnScreen { TAKEN, UNCONFIRMED, NOT_FOUND }

    /**
     * **إزاي «يومك» بتعرض جرعة اتأكّدت — مقروء من `day_rail.dart`.**
     *
     *  - **مأخوذة** → `_quietLine`: علامة ✓ (أيقونة، مفيش نص)، اسم الدوا،
     *    و`say.takenAt(time)` = «أخدته ٧:٣٠ ص» (المريض المزروع `Sex.m`).
     *    **السطر ده ما بيتشالش من السكة أبداً** — بقرار مكتوب في الملف:
     *    المريض لازم يشوف إنه خدها.
     *  - **لسه** → `_card` بحافة ذهبية + «لسه ما اتأكدتش»، و«الآن»
     *    (`now_card.dart`) بيقول «لسه ما اتأكدتش — كان معادها …» لنفس
     *    الحالة. يعني الجملة دي هي علامة «مش مؤكّدة» في الاتنين.
     *
     * فالتفرقة اللي الخطوة دي محتاجاها:
     *  - «لسه ما اتأكدتش» ظاهرة → الشاشة شايفاها **مش** مؤكّدة = **بايتة**.
     *  - «أخدته <حاجة>» ظاهرة → **مؤكّدة**.
     *  - ولا الاتنين بعد ما نلف الصفحة كلها → **مستخبية** أو مش «يومك».
     *
     * **ليه نمط مش نص:** زرار الستارة نصه «أخدته» بالظبط ومن غير أي حاجة
     * بعده؛ السطر الهادي «أخدته» + وقت. النمط بيطلب الكلمة التانية، فمفيش
     * خلط بين الزرار والسطر.
     *
     * **وليه تمرير:** «جدول النهاردة» تحت الترويسة و«خلال ٤٨ ساعة» وكارت
     * المية — يعني السطر الهادي غالباً تحت حد الشاشة، وUiAutomator بيشوف
     * اللي معروض بس.
     */
    private val unconfirmedText = "لسه ما اتأكدتش"
    private val takenLine: Pattern =
        Pattern.compile("^\\s*أخدت(ه|يه)\\s+\\S+.*$", Pattern.DOTALL)
    private val maxSwipes = 8

    private fun doseOnScreen(): DoseOnScreen {
        for (i in 0..maxSwipes) {
            // «مش مؤكّدة» بتتشاف الأول: لو الشاشة بايتة، ده أول اللي بيبان
            // وفوق خالص، ومحتاجينه يقع باسمه مش بـ«مش موجودة».
            if (device.hasObject(By.textContains(unconfirmedText))) {
                return DoseOnScreen.UNCONFIRMED
            }
            if (device.hasObject(By.text(takenLine))) return DoseOnScreen.TAKEN
            if (i == maxSwipes) break
            swipeUpOnce()
        }
        return DoseOnScreen.NOT_FOUND
    }

    private fun swipeUpOnce() {
        val w = device.displayWidth
        val h = device.displayHeight
        device.swipe(w / 2, (h * 0.75).toInt(), w / 2, (h * 0.30).toInt(), 12)
        Thread.sleep(600)
    }

    /**
     * **اللقطة وشجرة النوافذ — الشاشة نفسها، مش وصف ليها من الكود.**
     *
     * التشغيلة اللي فاتت وقعت عند «مش موجودة» ومحدش عرف الشاشة كانت
     * بتقول إيه. الشجرة نص فبتتطبع كمان على stdout، فحتى لو السحب من
     * الجهاز فشل، الدليل بيبقى في تقرير الاختبار.
     */
    private fun captureScreen(label: String) {
        val dir = File(context.externalCacheDir ?: context.cacheDir, "fkshots")
        dir.mkdirs()
        val xml = File(dir, "hierarchy-$label.xml")
        val png = File(dir, "screen-$label.png")
        try {
            device.dumpWindowHierarchy(xml)
            println("FKTEST: شجرة النوافذ → ${xml.absolutePath} (${xml.length()} بايت)")
            println("FKTEST: ---- شجرة النوافذ ($label) ----")
            xml.readLines().forEach { println("FKXML| $it") }
            println("FKTEST: ---- آخر الشجرة ----")
        } catch (e: Exception) {
            println("FKTEST: شجرة النوافذ فشلت: $e")
        }
        try {
            val ok = device.takeScreenshot(png)
            println("FKTEST: اللقطة → ${png.absolutePath} ok=$ok (${png.length()} بايت)")
        } catch (e: Exception) {
            println("FKTEST: اللقطة فشلت: $e")
        }
    }

    private fun launchWithSeed(seconds: Int) {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg)!!
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (seconds > 0) intent.putExtra("fk_seed_seconds", seconds)
        context.startActivity(intent)
    }

    /**
     * الحزمة في حالة «موقوفة»؟ ده اللي force-stop بيعمله و`am kill` لأ.
     *
     * **مفيش أنابيب هنا عن قصد.** `UiDevice.executeShellCommand` بيعدّي
     * على `Runtime.exec(String)`، اللي بيقطّع النص على المسافات من غير
     * صدفة — يعني `| grep` بيتبعت كوسيطة لـdumpsys ومش بيفلتر حاجة.
     * النسخة الأولى كانت كده، فالتأكيد كان بيعدّي **وهو فاضي**.
     *
     * **وهو لسه بيقيس علم الحزمة، مش موت العملية** — حارس تاني شكله
     * بيقيس حاجة وبيقيس غيرها. متسجّل في CLAUDE.md للّفة الجاية.
     */
    private fun isPackageStopped(): Boolean {
        val out = device.executeShellCommand("dumpsys package $pkg")
        val flags = out.lineSequence()
            .filter { it.contains("stopped=", ignoreCase = true) }
            .toList()
        assertTrue(
            "ما لقيناش علم stopped في dumpsys — التأكيد ده كان هيعدّي فاضي",
            flags.isNotEmpty(),
        )
        println("FKTEST: حالة الحزمة — ${flags.joinToString(" / ") { it.trim() }}")
        return flags.any { it.contains("stopped=true", ignoreCase = true) }
    }

    /** سطور النهاية اللي في مخزن اللوج دلوقتي — نجاح أو فشل. */
    private fun handlerLines(): List<String> =
        device.executeShellCommand("logcat -d -v time")
            .lineSequence()
            .filter { it.contains(handledOk) || it.contains(handleFailed) }
            .toList()

    /**
     * بيستنّى سطر نهاية **جديد** (بعد [baseline])، ويرجّعه — أو null لو
     * المهلة عدّت.
     *
     * الأساس عدد مش وقت: `logcat -v time` بيدّي طابع من غير سنة، ومقارنة
     * التواريخ كانت هتبقى تخمين تاني. ومخزن اللوج ممكن يلفّ، عشان كده
     * `coerceAtLeast`.
     */
    private fun awaitHandlerOutcome(timeoutMs: Long, baseline: Int): String? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val lines = handlerLines()
            if (lines.size > baseline) {
                return lines[baseline.coerceAtMost(lines.size - 1)].trim()
            }
            Thread.sleep(500)
        }
        return null
    }

    /**
     * موجود/حجم/تاريخ للملفات التلاتة — **stat بس، مفيش فتح للقاعدة**.
     *
     * ده اللي خلّى التشغيلة اللي فاتت تكدب علينا: تاريخ `.sqlite` كان
     * فتح الاستطلاع بتاع الاختبار نفسه، مش كتابة من التطبيق.
     */
    private fun printSnapshot(label: String) {
        println("FKTEST: ---- لقطة الملفات ($label) ${stamp.format(Date())} ----")
        for (name in dbNames) {
            val f = File(dbFile.parentFile, name)
            println(
                if (f.exists()) {
                    "FKTEST: $name — ${f.length()} بايت، آخر تعديل ${stamp.format(Date(f.lastModified()))}"
                } else {
                    "FKTEST: $name — مش موجود"
                },
            )
        }
    }

    /**
     * بينسخ التلاتة لمجلد مؤقت وبيقرا **النسخة** `OPEN_READONLY`.
     *
     * النسخ بيحصل بعد سطر النهاية بس، يعني المعالج خلص معاملته. وأي حاجة
     * الإطار يعملها في الملف بتاعه هنا بتحصل على **نسخة** — الملف الحي
     * عمره ما بيتفتح من الاختبار.
     */
    private fun readCopy(): Pair<String, Int> {
        val dir = File(context.cacheDir, "fkdbsnap-${System.currentTimeMillis()}")
        dir.mkdirs()
        for (name in dbNames) {
            val src = File(dbFile.parentFile, name)
            if (src.exists()) src.copyTo(File(dir, name), overwrite = true)
        }
        val copy = File(dir, "fakkarni.sqlite")
        if (!copy.exists()) return "مفيش-ملف" to -1
        return try {
            SQLiteDatabase
                .openDatabase(copy.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                .use { db ->
                    val mode = db.rawQuery("pragma journal_mode", null)
                        .use { c -> if (c.moveToFirst()) c.getString(0) else "?" }
                    val count = db
                        .rawQuery("select count(*) from dose_events where state = 'taken'", null)
                        .use { c -> if (c.moveToFirst()) c.getInt(0) else -1 }
                    mode to count
                }
        } catch (e: Exception) {
            println("FKTEST: قراية النسخة وقعت: $e")
            "قراية-وقعت" to -1
        }
    }

    /**
     * آخر ٢٠٠ سطر تخصّنا. **مفيش أنابيب** — بنجيب اللوج كامل وبنفلتر في
     * كوتلن. و`diag()` على أندرويد بتخرج من `debugPrint` للوج، يعني
     * **اللوج هو أثر أندرويد** (ملف iOS مش موجود هنا).
     */
    private fun dumpLog() {
        println("FKTEST: ---- آخر ٢٠٠ سطر تخصّنا من اللوج ----")
        val interesting = Regex("flutter|fakkarni|FKDIAG|Isolate|Handle", RegexOption.IGNORE_CASE)
        val lines = device.executeShellCommand("logcat -d -v time")
            .lineSequence()
            .filter { interesting.containsMatchIn(it) }
            .toList()
        lines.takeLast(200).forEach { println("FKTEST| $it") }
        if (lines.none { it.contains("Isolate:") }) {
            println("FKTEST: >>> مفيش ولا سطر Isolate: — الدوسة عمرها ما وصلت دارت")
        }
        println("FKTEST: ---- آخر اللوج ----")
    }
}

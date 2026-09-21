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
 * **ومين ماسك الاتصال التاني كان مجهول — والمتّهم الأول هو الاختبار ده
 * نفسه.** النسخة القديمة كانت بتفتح `fakkarni.sqlite` بـ`SQLiteDatabase`
 * بتاع إطار أندرويد، `OPEN_READWRITE`، من ٣٠ ملّي بعد الدوسة وكل نص
 * ثانية. وكان مكتوب فوقها إنها «بتفتح الملف زي ما التطبيق بيفتحه» —
 * **وده كان غلط**: التطبيق بيفتح عن طريق sqlite3 بتاع drift بالـpragmas
 * بتاعته (WAL + busy_timeout)، والإطار بيفتح باتصال تاني خالص بإعداد
 * journal بتاعه وأقفاله بتاعته. يعني أداة القياس كانت قاعدة على الملف
 * وهو بيتكتب.
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

        // ٦ — والتطبيق بيعرضها مؤكَّدة بعد ما يتفتح تاني
        launchWithSeed(0)
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 20_000)
        Thread.sleep(6_000)
        assertTrue(
            "«يومك» المفروض تعرض الجرعة مؤكَّدة",
            device.wait(Until.hasObject(By.textContains("TestDose")), 15_000),
        )
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

package com.fakkarni.fakkarni

import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * **سكّة أندرويد: زرار على الإشعار والتطبيق متقفول.**
 *
 * دي السكّة الوحيدة في الوعد اللي عمرها ما اشتغلت على أي جهاز. على iOS
 * اتثبت يوم ٢٠ سبتمبر إن الطريق ده **مش** بيتنفّذ خالص (النظام بيفتح
 * التطبيق ويسيب الرد في getNotificationAppLaunchDetails)، فاللي فاضل هو
 * أندرويد — ومفيش جهاز أندرويد هنا والمحاكي بيقع على مستوى QEMU على
 * الماك ده. فالاختبار بيتشغّل على محاكي في CI.
 *
 * بيعيد بالحرف اللي اتعمل بالإيد على الآيفون:
 *  ١. يزرع جرعة معادها في أقرب دقيقة جاية (باب خلفي debug بس)
 *  ٢. يقتل **العملية** — `am kill` مش `am force-stop`
 *  ٣. يستنى الإشعار، يفتح الستارة، يفرد، ويدوس «أخدته»
 *  ٤. يستنّى لحد ما صف الجرعة يظهر، **ويقول خد قد إيه**
 *  ٥. يفتح التطبيق تاني ويتأكد إن الحالة باينة مؤكَّدة
 *
 * **ليه `am kill` مش `am force-stop`:** الاتنين بيقتلوا العملية، بس
 * force-stop بيحط الحزمة في حالة «موقوفة» وبيلغي كل منبّهاتها في
 * AlarmManager. يعني الإشعار عمره ما هيرن، والاختبار كان هيقع لسبب غلط
 * خالص. و`am kill` بيقتل العمليات **اللي في الخلفية بس**، عشان كده
 * بنضغط Home الأول.
 *
 * **تشغيلة ٢١ سبتمبر ٢٠٢٦ وصلت لآخر تأكيد ووقعت عنده**: الباب اتفتح
 * (المنبّه عاش، الإشعار رن والعملية ميتة، الزرار كان موجود، والدوسة
 * وصلت) والعدّ رجع صفر. تلات تفسيرات مفيش في التشغيلة دي حاجة تفرّق
 * بينهم — WAL مش متشيك‑بوينت، أو الوقت قصير، أو الـisolate فعلاً بايظ —
 * وعشان كده الملف ده بقى بيقيس بدل ما يفترض، وبيطبع كل اللي بيلزم
 * للتفرقة قبل ما يقع.
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

    @Test
    fun lockScreenConfirmWritesTheDoseAndKillsTheLadder() {
        // ١ — زرع جرعة في أقرب دقيقة جاية، من برّه التطبيق
        launchWithSeed(60)
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 20_000)
        // الجدولة بتحصل في main بعد الزرع
        Thread.sleep(5_000)

        // ٢ — Home، وبعدين قتل العملية. المنبّه بيفضل عند النظام.
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
        taken!!.click()
        val tappedAt = System.currentTimeMillis()

        // ٤ — بنستنّى الصف بدل ما نفترض وقت. **الرقم ده اللي عايزينه**:
        // قد إيه الـisolate بياخد فعلاً على محاكي — مش ثابت بنخمّنه.
        val elapsed = awaitTakenDose(timeoutMs = 60_000, since = tappedAt)
        if (elapsed == null) {
            dumpEvidence(tappedAt)
            assertEquals("الجرعة المفروض اتسجّلت taken", 1, takenDoseCount())
        }
        println("FKTEST: صف الجرعة ظهر بعد ${elapsed}ms من الدوسة")

        // ٥ — والتطبيق بيعرضها مؤكَّدة بعد ما يتفتح تاني
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
     * النسخة الأولى كانت كده، فالتأكيد كان بيعدّي **وهو فاضي**: النص
     * الراجع مكانش فيه `stopped=true` لأنه مكانش فيه حاجة أصلاً.
     * دلوقتي بنجيب المخرج كامل وبنفلتره في كوتلن، وبنرمي لو ما لقيناش
     * العلم أصلاً بدل ما نعدّي على الفاضي.
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

    /** بيرجّع الوقت بالملي لما الصف يظهر، أو null لو المهلة عدّت. */
    private fun awaitTakenDose(timeoutMs: Long, since: Long): Long? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (takenDoseCount() >= 1) return System.currentTimeMillis() - since
            Thread.sleep(500)
        }
        return null
    }

    /**
     * عدد صفوف dose_events اللي حالتها taken.
     *
     * **بنفتح الملف زي ما التطبيق بيفتحه: قراية وكتابة، مش OPEN_READONLY.**
     * القاعدة شغّالة على `journal_mode = WAL`، والكتابة بتقعد في
     * `fakkarni.sqlite-wal` لحد ما يحصل checkpoint. اتصال **للقراية بس**
     * ما بيقدرش يعمل استرجاع للـWAL، فبيرجّع اللقطة اللي قبله — **صفر، من
     * غير أي خطأ**. يعني الصف ممكن يكون موجود والاختبار أعمى عنه.
     *
     * **وده مش تضعيف للتأكيد**: استرجاع الـWAL بيظهر المعاملات
     * **المكتملة** بس؛ أي كتابة ناقصة بترجع لورا وبتفضل غير مرئية زي ما
     * هي. يعني إحنا بنشيل سلبية كاذبة، مش بنخفّض السقف.
     */
    private fun takenDoseCount(readOnly: Boolean = false): Int {
        val file = dbFile
        if (!file.exists()) return 0
        return try {
            val flags = if (readOnly) {
                SQLiteDatabase.OPEN_READONLY
            } else {
                SQLiteDatabase.OPEN_READWRITE
            }
            SQLiteDatabase.openDatabase(file.absolutePath, null, flags).use { db ->
                db.rawQuery("select count(*) from dose_events where state = 'taken'", null)
                    .use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
            }
        } catch (e: Exception) {
            println("FKTEST: قراية القاعدة وقعت (readOnly=$readOnly): $e")
            0
        }
    }

    /**
     * كل اللي بيلزم للتفرقة بين التلات تفسيرات — **قبل ما نقع، مش بعدها**.
     *
     * لو التشغيلة الجاية وقعت، التقرير نفسه المفروض يقول أنهي واحد فيهم:
     *  أ — WAL: العدّ بالكتابة > العدّ بالقراية، أو `-wal` فيه بايتات
     *  ب — الوقت: مفيش صف لكن اللوج بيقول إن الـisolate اشتغل ولسه ماشي
     *  ج — الـisolate: مفيش سطر `Isolate:` في اللوج خالص
     */
    private fun dumpEvidence(tappedAt: Long) {
        val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
        println("FKTEST: ======== الدليل ========")
        println("FKTEST: الدوسة كانت ${stamp.format(Date(tappedAt))}")

        for (name in listOf("fakkarni.sqlite", "fakkarni.sqlite-wal", "fakkarni.sqlite-shm")) {
            val f = File(dbFile.parentFile, name)
            println(
                if (f.exists()) {
                    "FKTEST: $name — ${f.length()} بايت، آخر تعديل ${stamp.format(Date(f.lastModified()))}"
                } else {
                    "FKTEST: $name — مش موجود"
                },
            )
        }

        val readWrite = takenDoseCount(readOnly = false)
        val readOnly = takenDoseCount(readOnly = true)
        println("FKTEST: taken بالقراية-والكتابة = $readWrite، بالقراية-بس = $readOnly")
        if (readWrite > readOnly) {
            println("FKTEST: >>> التفسير (أ): الصف في الـWAL والقراية-بس كانت عماها")
        }

        // زي فوق: مفيش أنابيب ولا `$(...)` — بنجيب اللوج كامل وبنفلتره
        // في كوتلن. و`diag()` على أندرويد بتخرج من `debugPrint` للوج، يعني
        // **اللوج هو أثر أندرويد** (الملف بتاع iOS مش موجود هنا).
        println("FKTEST: ---- آخر ٢٠٠ سطر تخصّنا من اللوج ----")
        val interesting = Regex("flutter|fakkarni|FKDIAG|Isolate|Handle", RegexOption.IGNORE_CASE)
        val lines = device.executeShellCommand("logcat -d -v time")
            .lineSequence()
            .filter { interesting.containsMatchIn(it) }
            .toList()
        lines.takeLast(200).forEach { println("FKTEST| $it") }
        if (lines.none { it.contains("Isolate:") }) {
            println("FKTEST: >>> التفسير (ج): مفيش ولا سطر Isolate: — الـisolate ما اشتغلش")
        }
        println("FKTEST: ======== آخر الدليل ========")
    }
}

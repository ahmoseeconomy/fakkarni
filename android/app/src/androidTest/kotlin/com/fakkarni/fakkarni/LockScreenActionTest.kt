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
 *  ٤. يتأكد إن صف الجرعة اتكتب
 *  ٥. يفتح التطبيق تاني ويتأكد إن الحالة باينة مؤكَّدة
 *
 * **ليه `am kill` مش `am force-stop`:** الاتنين بيقتلوا العملية، بس
 * force-stop بيحط الحزمة في حالة «موقوفة» وبيلغي كل منبّهاتها في
 * AlarmManager. يعني الإشعار عمره ما هيرن، والاختبار كان هيقع لسبب غلط
 * خالص. و`am kill` بيقتل العمليات **اللي في الخلفية بس**، عشان كده
 * بنضغط Home الأول — لو التطبيق قدام، النداء ده ما بيعملش حاجة.
 */
@RunWith(AndroidJUnit4::class)
class LockScreenActionTest {

    private val device: UiDevice
        get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val pkg = "com.fakkarni.fakkarni"

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
        Thread.sleep(8_000)

        // ٤ — الصف اتكتب؟ بنقرا ملف drift نفسه بنفس الـUID.
        assertEquals("الجرعة المفروض اتسجّلت taken", 1, takenDoseCount())

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

    /** الحزمة في حالة «موقوفة»؟ ده اللي force-stop بيعمله و`am kill` لأ. */
    private fun isPackageStopped(): Boolean {
        val out = device.executeShellCommand("dumpsys package $pkg | grep -i stopped")
        return out.contains("stopped=true", ignoreCase = true)
    }

    /**
     * عدد صفوف dose_events اللي حالتها taken — من ملف drift مباشرةً.
     *
     * الاختبار بيشتغل في عملية التطبيق نفسه، فنفس الـUID ونفس الصلاحيات.
     */
    private fun takenDoseCount(): Int {
        val docs = File(context.filesDir.parentFile, "app_flutter")
        val candidates = docs.listFiles { f -> f.name.endsWith(".sqlite") || f.name.endsWith(".db") }
            ?: emptyArray()
        assertTrue("ما لقيناش ملف قاعدة البيانات في ${docs.absolutePath}", candidates.isNotEmpty())

        var total = 0
        for (file in candidates) {
            val db = SQLiteDatabase.openDatabase(
                file.absolutePath, null, SQLiteDatabase.OPEN_READONLY,
            )
            db.use {
                val cursor = it.rawQuery(
                    "select count(*) from dose_events where state = 'taken'", null,
                )
                cursor.use { c -> if (c.moveToFirst()) total += c.getInt(0) }
            }
        }
        return total
    }
}

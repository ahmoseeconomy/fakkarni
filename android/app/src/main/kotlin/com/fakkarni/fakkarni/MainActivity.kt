package com.fakkarni.fakkarni

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BatteryChannel.register(this, flutterEngine)
        TestHookChannel.register(this, flutterEngine)
    }
}

/**
 * الباب الخلفي بتاع اختبار الجهاز — **debug بس**.
 *
 * سكّة أندرويد (زرار الإشعار والتطبيق متقفول) عمرها ما اشتغلت على أي
 * جهاز. الاختبار الآلي بيشغّل النشاط ومعاه `fk_seed_seconds`، ودارت
 * بتاخد الرقم مرة واحدة وتزرع جرعة معادها في أقرب دقيقة جاية.
 *
 * **البوابة هنا هي علم `debuggable` بتاع الـAPK نفسه**، و`kReleaseMode`
 * بوابة تانية في
 * `test_hook.dart`.** في نسخة الإصدار القناة دي مش بتتسجّل أصلاً، فالنداء
 * بيرمي MissingPluginException ودارت بتبلعه وترجّع null.
 */
object TestHookChannel {
    private const val NAME = "fakkarni/testhook"
    private const val EXTRA = "fk_seed_seconds"

    fun register(activity: MainActivity, engine: FlutterEngine) {
        // مش BuildConfig.DEBUG: ده ثابت وقت الترجمة في ملف ممكن يتعدّل،
        // والعلم ده بيتقرا من الـmanifest بتاع الـAPK اللي شغّال فعلاً.
        // نسخة الإصدار عمرها ما بتبقى debuggable.
        val debuggable =
            (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) return
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeSeedSeconds" -> {
                    val seconds = activity.intent?.getIntExtra(EXTRA, -1) ?: -1
                    // مرة واحدة بس: من غير المسح، كل رجوع للنشاط بيزرع تاني
                    activity.intent?.removeExtra(EXTRA)
                    result.success(if (seconds > 0) seconds else null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

/**
 * قاتل البطارية بتاع الشركة المصنّعة هو **أشهر سبب** إن تذكير دوا ما يرنش
 * على أندرويد — وأندرويد هو بالظبط المنصة اللي مش بنقدر نجربها هنا. يعني
 * ده الفحص اللي الميزة كلها موجودة عشانه.
 *
 * القناة دي بتعمل حاجتين وبس:
 *  - **القراية**: `isIgnoringBatteryOptimizations` — ما بتحتاجش أي إذن،
 *    فالفحص آمن على أي جهاز وفي أي نسخة.
 *  - **الفتح**: بتوديه على قايمة «تحسين البطارية» في الإعدادات.
 *
 * **عن قصد مش بنستعمل `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`**
 * (الحوار المباشر «اسمح؟»): هو بيطلب إذن `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`،
 * وده إذن **مقيّد** على Google Play وبيتراجع مع قايمة استخدامات مقبولة.
 * `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` بيوصل لنفس النتيجة بدوسة
 * زيادة، **من غير أي إذن ومن غير أي تعرّض لسياسة المتجر**. شوف الملاحظة
 * في CLAUDE.md.
 */
object BatteryChannel {
    private const val NAME = "fakkarni/battery"

    fun register(context: Context, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoring(context))
                "openBatterySettings" -> result.success(openSettings(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoring(context: Context): Boolean {
        // قبل Marshmallow مفيش تحسين بطارية أصلاً — يعني مفيش حاجة مكسورة
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return try {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            power.isIgnoringBatteryOptimizations(context.packageName)
        } catch (e: Exception) {
            // فحص فاشل بيقول «مش عارفين»، وبيتحسب سليم: إنذار كذب على
            // شاشة مريض أسوأ من فحص ساكت
            true
        }
    }

    private fun openSettings(context: Context): Boolean = try {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }
}

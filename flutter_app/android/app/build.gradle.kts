plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "eg.security.security_management"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "eg.security.security_management"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // بناء arm64 فقط لتقليل حجم الـ APK (أغلب الأجهزة الحديثة)
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // مكتبة فحص Vulkan للتشخيص فقط — غير مطلوبة للتشغيل وتضيف 14 ميجا
            excludes += listOf("**/libVkLayer_khronos_validation.so")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ===== تقليل الحجم: بعد بناء الـ debug، نبني نسخة Release خفيفة في مجلد منفصل
// (خارج قفل المشروع) ثم نستبدل ملف app-debug.apk بها — فيرفع الـ CI نسخة الخفيفة.
val buildReleaseAndSwap = tasks.register("buildReleaseAndSwap") {
    doLast {
        val projectRoot = rootProject.projectDir.parentFile
        val debugApk = File(rootProject.projectDir, "build/app/outputs/flutter-apk/app-debug.apk")
        if (!debugApk.exists()) {
            println("SLIM: app-debug.apk غير موجود — تخطّي الاستبدال")
            return@doLast
        }
        val tmp = File(projectRoot.parentFile, "slim_release_build").canonicalFile
        tmp.deleteRecursively()
        val dest = File(tmp, "flutter_app")
        dest.mkdirs()
        projectRoot.walkTopDown()
            .onEnter { dir -> dir.name != "build" && dir.name != ".gradle" }
            .forEach { src ->
                val dst = File(dest, src.toRelativeString(projectRoot))
                if (src.isDirectory) dst.mkdirs() else src.copyTo(dst, overwrite = true)
            }
        println("SLIM: تم نسخ المشروع إلى " + dest)
        fun runCmd(dir: File, vararg cmd: String): Int {
            val proc = ProcessBuilder(*cmd).directory(dir).redirectErrorStream(true).start()
            proc.inputStream.bufferedReader().forEachLine { println("SLIM: " + it) }
            return proc.waitFor()
        }
        runCmd(dest, "flutter", "pub", "get")
        val code = runCmd(dest, "flutter", "build", "apk", "--release")
        val relApk = File(dest, "build/app/outputs/flutter-apk/app-release.apk")
        if (code == 0 && relApk.exists()) {
            relApk.copyTo(debugApk, overwrite = true)
            println("SLIM: تم استبدال الـ APK بنسخة Release خفيفة حجمها " + (relApk.length() / 1048576) + " ميجا")
        } else {
            println("SLIM: فشل بناء Release (exit=" + code + ") — سيُرفع الـ APK الـ debug كما هو")
        }
    }
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy(buildReleaseAndSwap)
}

package eg.security.security_management

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.MediaStore
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File

/**
 * تطبيق "إدارة الأمن" للأندرويد = نفس صفحة الويب بكل تفاصيلها داخل WebView.
 * - نفس السيرفر ونفس الواجهة فلا يوجد أي فرق ولا مزامنة مطلوبة.
 * - رفع الصور (معرض/كاميرا)، تصدير الملفات إلى التنزيلات، الطباعة/حفظ PDF، زر الرجوع.
 */
class MainActivity : Activity() {
    companion object {
        const val DEFAULT_URL =
            "https://script.google.com/macros/s/AKfycbz5ISJT-vROTmczOi8HdFBvwSXiUZ3mMGzHJBfv732cumsONfMsu-yK_5-NuOzByHQu/exec"
        const val REQ_FILE = 4711
        const val PURPLE = 0xFF7C5CFC.toInt()
    }

    private lateinit var web: WebView
    private lateinit var bar: ProgressBar
    private lateinit var errBox: LinearLayout
    private lateinit var errText: TextView
    private var loadFailed = false
    private var fileCb: ValueCallback<Array<Uri>>? = null
    private var captureFile: File? = null
    private var captureUri: Uri? = null

    private fun prefs() = getSharedPreferences("app", Context.MODE_PRIVATE)
    private fun savedUrl(): String {
        val u = prefs().getString("url", "") ?: ""
        return if (u.startsWith("http")) u else DEFAULT_URL
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = PURPLE
        window.navigationBarColor = PURPLE

        val root = FrameLayout(this)
        root.setBackgroundColor(PURPLE)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val b = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom)
            WindowInsetsCompat.CONSUMED
        }

        web = WebView(this)
        web.setBackgroundColor(Color.parseColor("#F6F5FB"))
        root.addView(web, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        bar.max = 100
        root.addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 8))

        errBox = LinearLayout(this)
        errBox.orientation = LinearLayout.VERTICAL
        errBox.gravity = Gravity.CENTER
        errBox.setBackgroundColor(Color.WHITE)
        errBox.setPadding(48, 48, 48, 48)
        errBox.visibility = View.GONE
        val title = TextView(this)
        title.text = "تعذّر فتح التطبيق"
        title.textSize = 20f
        title.gravity = Gravity.CENTER
        title.setTextColor(Color.parseColor("#B91C1C"))
        errText = TextView(this)
        errText.textSize = 13f
        errText.gravity = Gravity.CENTER
        errText.setPadding(0, 16, 0, 24)
        val retry = Button(this)
        retry.text = "إعادة المحاولة"
        retry.setOnClickListener { load() }
        val change = Button(this)
        change.text = "تغيير رابط السيرفر"
        change.setOnClickListener { askUrl() }
        errBox.addView(title)
        errBox.addView(errText)
        errBox.addView(retry)
        errBox.addView(change)
        root.addView(errBox, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        setContentView(root)
        setupWeb()
        if (savedInstanceState != null) web.restoreState(savedInstanceState) else load()
    }

    private fun load() {
        errBox.visibility = View.GONE
        loadFailed = false
        web.loadUrl(savedUrl())
    }

    private fun askUrl() {
        val et = EditText(this)
        et.setText(savedUrl())
        et.textDirection = View.TEXT_DIRECTION_LTR
        AlertDialog.Builder(this)
            .setTitle("رابط السيرفر (ينتهي بـ /exec)")
            .setView(et)
            .setPositiveButton("حفظ") { _, _ ->
                prefs().edit().putString("url", et.text.toString().trim()).apply()
                load()
            }
            .setNeutralButton("الافتراضي") { _, _ ->
                prefs().edit().remove("url").apply()
                load()
            }
            .setNegativeButton("إلغاء", null)
            .show()
    }

    private fun setupWeb() {
        val s = web.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        s.databaseEnabled = true
        s.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        s.javaScriptCanOpenWindowsAutomatically = true
        s.setSupportMultipleWindows(false)
        s.setSupportZoom(false)
        s.builtInZoomControls = false
        s.textZoom = 100
        s.mediaPlaybackRequiresUserGesture = false
        s.userAgentString = s.userAgentString + " SecurityAndroidApp/2.1"
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

        web.addJavascriptInterface(Bridge(), "AndroidApp")

        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                loadFailed = false
                bar.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                bar.visibility = View.GONE
                if (!loadFailed) errBox.visibility = View.GONE
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) {
                    loadFailed = true
                    errText.text = "تأكد من الإنترنت ورابط السيرفر.\n(" + (error?.description ?: "") + ")"
                    errBox.visibility = View.VISIBLE
                }
            }

            override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) {
                if (request?.isForMainFrame == true && (errorResponse?.statusCode ?: 0) >= 400) {
                    loadFailed = true
                    errText.text = "رد السيرفر: " + errorResponse?.statusCode + "\nتأكد من رابط النشر (Deploy ← Web app ← أي شخص)."
                    errBox.visibility = View.VISIBLE
                }
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val u = request?.url ?: return false
                val sch = u.scheme ?: return false
                if (sch == "http" || sch == "https") {
                    val h = u.host ?: ""
                    if (h.endsWith("google.com") || h.endsWith("googleusercontent.com")) return false
                    return openExternal(u)
                }
                return openExternal(u) // tel: mailto: whatsapp: intent: ...
            }
        }

        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                bar.progress = newProgress
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                fileCb?.onReceiveValue(null)
                fileCb = filePathCallback
                return try {
                    startActivityForResult(buildChooser(fileChooserParams), REQ_FILE)
                    true
                } catch (e: Exception) {
                    fileCb?.onReceiveValue(null)
                    fileCb = null
                    false
                }
            }
        }

        web.setDownloadListener { url, _, contentDisposition, mime, _ ->
            // روابط تنزيل عادية (http) — تُفتح خارجيًا؛ روابط blob/data يعالجها الجسر من الصفحة
            if (url.startsWith("http")) {
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: Exception) {}
            }
        }
    }

    private fun openExternal(u: Uri): Boolean {
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, u))
            true
        } catch (e: ActivityNotFoundException) {
            true
        } catch (e: Exception) {
            true
        }
    }

    private fun buildChooser(p: WebChromeClient.FileChooserParams?): Intent {
        val accept = (p?.acceptTypes ?: arrayOf()).filter { it.isNotBlank() }
        val content = Intent(Intent.ACTION_GET_CONTENT)
        content.addCategory(Intent.CATEGORY_OPENABLE)
        content.type = "*/*"
        if (accept.isNotEmpty()) content.putExtra(Intent.EXTRA_MIME_TYPES, accept.toTypedArray())
        if (p?.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE) {
            content.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        val chooser = Intent.createChooser(content, "اختر ملفًا")
        val wantsImage = accept.isEmpty() || accept.any { it.startsWith("image") || it == "*/*" }
        captureFile = null
        captureUri = null
        if (wantsImage) {
            try {
                val f = File(cacheDir, "capture-" + System.currentTimeMillis() + ".jpg")
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
                val cam = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                cam.putExtra(MediaStore.EXTRA_OUTPUT, uri)
                cam.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(cam))
                captureFile = f
                captureUri = uri
            } catch (_: Exception) {
            }
        }
        return chooser
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_FILE) {
            val cb = fileCb
            fileCb = null
            var res: Array<Uri>? = null
            if (resultCode == RESULT_OK) {
                val hasData = data != null && (data.data != null || data.clipData != null)
                res = if (hasData) {
                    WebChromeClient.FileChooserParams.parseResult(resultCode, data)
                } else {
                    val f = captureFile
                    val cu = captureUri
                    if (f != null && cu != null && f.exists() && f.length() > 0) arrayOf(cu) else null
                }
            }
            cb?.onReceiveValue(res)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // الصفحة تدير الرجوع بنفسها (النوافذ المنبثقة والتبويبات عبر history)
        if (errBox.visibility == View.VISIBLE) {
            moveTaskToBack(true)
        } else if (web.canGoBack()) {
            web.goBack()
        } else {
            moveTaskToBack(true)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }

    override fun onResume() {
        super.onResume()
        web.onResume()
    }

    override fun onPause() {
        web.onPause()
        super.onPause()
    }

    /** الجسر بين الصفحة والتطبيق (متاح في الصفحة باسم AndroidApp) */
    inner class Bridge {
        @JavascriptInterface
        fun isApp(): Boolean = true

        @JavascriptInterface
        fun print() {
            runOnUiThread {
                try {
                    val pm = getSystemService(Context.PRINT_SERVICE) as PrintManager
                    val name = "إدارة الأمن"
                    pm.print(name, web.createPrintDocumentAdapter(name), PrintAttributes.Builder().build())
                } catch (e: Exception) {
                    Toast.makeText(this@MainActivity, "تعذرت الطباعة", Toast.LENGTH_LONG).show()
                }
            }
        }

        @JavascriptInterface
        fun saveFile(name: String, mime: String, b64: String) {
            try {
                val bytes = Base64.decode(b64, Base64.DEFAULT)
                val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "file" }
                var opened: Uri? = null
                var where: String
                if (Build.VERSION.SDK_INT >= 29) {
                    val cv = ContentValues()
                    cv.put(MediaStore.Downloads.DISPLAY_NAME, safe)
                    cv.put(MediaStore.Downloads.MIME_TYPE, mime)
                    cv.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv)
                        ?: throw Exception("تعذر إنشاء الملف")
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    opened = uri
                    where = "التنزيلات"
                } else {
                    val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
                    dir.mkdirs()
                    File(dir, safe).writeBytes(bytes)
                    where = dir.absolutePath
                }
                runOnUiThread {
                    Toast.makeText(this@MainActivity, "تم حفظ $safe في $where", Toast.LENGTH_LONG).show()
                    if (opened != null) {
                        try {
                            val i = Intent(Intent.ACTION_VIEW)
                            i.setDataAndType(opened, mime)
                            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(i)
                        } catch (_: Exception) {
                        }
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    Toast.makeText(this@MainActivity, "تعذر حفظ الملف: " + e.message, Toast.LENGTH_LONG).show()
                }
            }
        }

        @JavascriptInterface
        fun changeServer() {
            runOnUiThread { askUrl() }
        }
    }
}

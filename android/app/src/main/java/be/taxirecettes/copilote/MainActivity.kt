package be.taxirecettes.copilote

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.GeolocationPermissions
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView

    // Import d'une sauvegarde : sans ce sélecteur de fichiers, le bouton « Importer »
    // (un <input type=file> dans la page) ne faisait rien du tout.
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private val fileChooser =
        registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            filePathCallback?.onReceiveValue(if (uri != null) arrayOf(uri) else arrayOf())
            filePathCallback = null
        }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this)
        web = WebView(this)
        root.addView(
            web,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        setContentView(root)

        val s = web.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        @Suppress("DEPRECATION")
        s.databaseEnabled = true
        // Inutile pour file:///android_asset, et ouvrirait la lecture du systeme de fichiers.
        s.allowFileAccess = false
        s.mediaPlaybackRequiresUserGesture = true

        // Le pont natif n'est exposé QUE dans l'app chauffeur, qui charge une page
        // embarquée. Patron/Admin chargent une page DISTANTE : lui donner accès au
        // code natif serait une porte d'entrée (script tiers compromis, XSS...).
        if (BuildConfig.IS_DRIVER) {
            web.addJavascriptInterface(TaxiBridge(this), "TaxiNative")
        }

        // Hors réseau, une page distante affiche sinon une erreur système en anglais.
        web.webViewClient = object : WebViewClient() {
            override fun onReceivedError(
                view: WebView,
                request: android.webkit.WebResourceRequest,
                error: android.webkit.WebResourceError
            ) {
                if (!request.isForMainFrame) return
                val html = """<meta name="viewport" content="width=device-width,initial-scale=1">
                    <body style="background:#0F172A;color:#E5E7EB;font:16px system-ui;text-align:center;padding:56px 24px">
                    <h2 style="margin:0 0 8px">Pas de connexion</h2>
                    <p style="color:#94A3B8">Cette application a besoin d'internet pour afficher ton tableau de bord.</p>
                    <p style="margin-top:24px"><a href="" style="color:#FFB020;font-weight:600">Réessayer</a></p>
                    </body>"""
                view.loadDataWithBaseURL(
                    BuildConfig.LAUNCH_URL, html, "text/html", "UTF-8", BuildConfig.LAUNCH_URL
                )
            }
        }

        web.webChromeClient = object : WebChromeClient() {
            // GPS du taximetre : accordé uniquement dans l'app chauffeur.
            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?
            ) {
                callback?.invoke(origin, BuildConfig.IS_DRIVER, false)
            }

            // Ouvre le sélecteur de fichiers quand la page a un <input type=file>
            // (bouton « Importer une sauvegarde »).
            override fun onShowFileChooser(
                webView: WebView?,
                callback: ValueCallback<Array<Uri>>?,
                params: FileChooserParams?
            ): Boolean {
                filePathCallback?.onReceiveValue(null)
                filePathCallback = callback
                return try {
                    fileChooser.launch("*/*")   // le contenu JSON est validé par la page
                    true
                } catch (_: Exception) {
                    filePathCallback = null
                    false
                }
            }
        }
        web.loadUrl(BuildConfig.LAUNCH_URL)

        // Les permissions (notifications + GPS) ne concernent que l'app chauffeur
        // (taximètre). Patron / Admin sont de simples tableaux de bord web.
        if (BuildConfig.IS_DRIVER) {
            val need = ArrayList<String>()
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                need.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED
            ) {
                need.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (need.isNotEmpty()) requestPermissions(need.toTypedArray(), 101)
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }
}

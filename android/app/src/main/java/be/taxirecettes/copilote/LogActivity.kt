package be.taxirecettes.copilote

import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider

class LogActivity : AppCompatActivity() {

    private lateinit var text: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dp = resources.displayMetrics.density
        fun d(v: Int) = (v * dp).toInt()

        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setPadding(d(12), d(12), d(12), d(12))

        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        val share = Button(this); share.text = "Partager"; share.isAllCaps = false
        val clear = Button(this); clear.text = "Effacer"; clear.isAllCaps = false
        row.addView(share, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(clear, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        col.addView(row)

        val scroll = ScrollView(this)
        text = TextView(this)
        text.textSize = 11f
        text.typeface = Typeface.MONOSPACE
        text.setTextIsSelectable(true)
        text.setPadding(0, d(8), 0, 0)
        scroll.addView(text)
        col.addView(
            scroll,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        setContentView(col)

        share.setOnClickListener { shareLog() }
        clear.setOnClickListener {
            LogStore.clear(this)
            load()
            Toast.makeText(this, "Journal effacé", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onResume() {
        super.onResume()
        load()
    }

    private fun load() {
        val t = LogStore.read(this)
        text.text = if (t.isBlank())
            "Journal vide pour le moment.\n\nOuvre Uber / Bolt / Taxis Verts pendant une journée, puis reviens ici."
        else t
    }

    private fun shareLog() {
        try {
            val f = LogStore.fileFor(this)
            if (!f.exists() || f.length() == 0L) {
                Toast.makeText(this, "Journal vide", Toast.LENGTH_SHORT).show()
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
            val send = Intent(Intent.ACTION_SEND)
            send.type = "text/plain"
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(send, "Partager le journal"))
        } catch (_: Exception) {
            Toast.makeText(this, "Partage impossible", Toast.LENGTH_SHORT).show()
        }
    }
}

package com.openless.app

import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep

/** Rust calls back into this object to refresh overlay UI state. */
@Keep
object OpenLessOverlayBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile var listener: OverlayStateListener? = null
    @Volatile var imeListener: OverlayStateListener? = null
    @Volatile var imeSessionListener: ((String) -> Unit)? = null

    interface OverlayStateListener {
        fun onCapsuleStateChanged(state: String, message: String?, level: Float)
    }

    @Keep
    @JvmStatic
    fun onCapsuleStateChanged(state: String, message: String?, level: Float) {
        mainHandler.post {
            listener?.onCapsuleStateChanged(state, message, level)
            imeListener?.onCapsuleStateChanged(state, message, level)
        }
    }

    @Keep
    @JvmStatic
    fun onImeSessionEvent(json: String) {
        mainHandler.post { imeSessionListener?.invoke(json) }
    }

    @Keep
    @JvmStatic
    fun showToast(message: String) {
        mainHandler.post {
            val service = OpenLessOverlayService.instance ?: return@post
            val app = service.applicationContext
            val raw = app.getSharedPreferences("openless_ime_ui", android.content.Context.MODE_PRIVATE)
                .getString("locale", null)
                ?.takeUnless { it.equals("system", ignoreCase = true) || it.isBlank() }
                ?: app.resources.configuration.locales[0].toLanguageTag()
            val isPt = raw.startsWith("pt", ignoreCase = true)
            val isEn = !raw.startsWith("zh", ignoreCase = true)
            val localized = when {
                isPt -> when (message) {
                    "已复制到剪贴板" -> "Copiado para a área de transferência"
                    "无法启动语音编辑，请确认已启用该功能并聚焦外部输入框" -> "Não foi possível iniciar a edição por voz. Verifique se o recurso está ativado e se há um campo externo focado."
                    else -> message
                }
                isEn -> when (message) {
                    "已复制到剪贴板" -> "Copied to clipboard"
                    "无法启动语音编辑，请确认已启用该功能并聚焦外部输入框" -> "Cannot start voice editing. Make sure the feature is enabled and an external input field is focused."
                    else -> message
                }
                else -> message
            }
            android.widget.Toast.makeText(
                    app,
                    localized,
                    android.widget.Toast.LENGTH_SHORT,
                )
                .show()
        }
    }
}

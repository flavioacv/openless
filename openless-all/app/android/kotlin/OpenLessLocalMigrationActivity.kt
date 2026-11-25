package com.openless.app

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Full-screen native flow for exporting and importing the versioned local
 * migration bundle. SAF, password handling, preview, conflict resolution,
 * and restore remain native because they depend on Activity lifecycle state.
 */
class OpenLessLocalMigrationActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("openless_ime_ui", Context.MODE_PRIVATE) }

    private var pendingExportMode: String? = null
    private var pendingExportIncludeCredentials = false
    private var pendingExportPassword: String? = null
    private val requestCodeExportSave = 4201
    private val requestCodeImportOpen = 4202
    private val requestCodeLegacyImportOpen = 4203
    private val maxMigrationBundleBytes = OpenLessMigrationBundlePolicy.MAX_BUNDLE_BYTES
    private data class PendingExportState(
        val mode: String,
        val includeCredentials: Boolean,
        val password: String?,
    )
    private val rawLocale by lazy {
        prefs.getString("locale", null)
            ?.takeUnless { it.equals("system", ignoreCase = true) || it.isBlank() }
            ?: resources.configuration.locales[0].toLanguageTag()
    }
    private val portugueseUi by lazy { rawLocale.startsWith("pt", ignoreCase = true) }
    private val englishUi by lazy { !rawLocale.startsWith("zh", ignoreCase = true) }

    private fun ui(zh: String, en: String, pt: String = en) = when {
        portugueseUi -> pt
        englishUi -> en
        else -> zh
    }
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private val isDarkTheme: Boolean
        get() = when (prefs.getString("theme_mode", null)) {
            "light" -> false
            "dark" -> true
            else -> (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) != Configuration.UI_MODE_NIGHT_NO
        }

    private fun tone(dark: Int, light: Int): Int = if (isDarkTheme) dark else light

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val retained = lastNonConfigurationInstance as? PendingExportState
        if (retained != null) {
            pendingExportMode = retained.mode
            pendingExportIncludeCredentials = retained.includeCredentials
            pendingExportPassword = retained.password
        } else if (savedInstanceState != null) {
            pendingExportMode = savedInstanceState.getString("migrationExportMode")
            pendingExportIncludeCredentials = savedInstanceState.getBoolean("migrationExportIncludeCredentials", false)
            pendingExportPassword = null
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContentView(buildContent())
        WindowCompat.getInsetsController(window, window.decorView)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("migrationExportMode", pendingExportMode)
        outState.putBoolean("migrationExportIncludeCredentials", pendingExportIncludeCredentials)
    }

    @Suppress("DEPRECATION")
    override fun onRetainNonConfigurationInstance(): Any? =
        pendingExportMode?.let { PendingExportState(it, pendingExportIncludeCredentials, pendingExportPassword) }

    private fun buildContent(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(tone(Color.rgb(30, 30, 30), Color.rgb(245, 245, 247)))
        }
        val header = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), dp(16), dp(8))
        }
        header.addView(
            TextView(this).apply {
                text = "←"
                textSize = 22f
                setTextColor(tone(Color.WHITE, Color.rgb(30, 30, 34)))
                gravity = Gravity.CENTER
                setPadding(dp(16), dp(8), dp(16), dp(8))
                isClickable = true
                setOnClickListener { finish() }
            },
        )
        header.addView(
            TextView(this).apply {
                text = ui("本地配置迁移", "Local configuration migration", "Migração de configuração local")
                textSize = 18f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(tone(Color.WHITE, Color.rgb(30, 30, 34)))
            },
        )
        root.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val scroll = ScrollView(this)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(20))
        }
        scroll.addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val imeBottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            view.setPadding(systemBars.left, systemBars.top, systemBars.right, maxOf(systemBars.bottom, imeBottom))
            insets
        }

        content.addView(sectionLabel(ui("本地配置迁移", "Local configuration migration", "Migração de configuração local")))
        content.addView(TextView(this).apply {
            text = ui(
                "将所有可迁移的本地配置导出到版本化文件，或从另一台 Android 设备恢复。分享模式默认脱敏；个人迁移中的凭据必须使用密码保护。系统权限、OAuth 会话、设备路径和运行时状态不会迁移。导入前会显示来源、版本和变更摘要，并自动保留备份。",
                "Export portable local configuration to a versioned bundle, or restore it on another Android device. Share mode is redacted by default; personal migration credentials require password protection. System permissions, OAuth sessions, device paths, and runtime state never migrate. Import shows the source, version, and change summary before keeping a local backup.",
                "Exporte todas as configurações locais portáteis para um arquivo versionado ou restaure em outro dispositivo Android. O modo de compartilhamento omite dados sensíveis por padrão; as credenciais na migração pessoal exigem proteção por senha. Permissões do sistema, sessões OAuth, caminhos do dispositivo e estado de execução não são migrados. A importação exibe origem, versão e resumo das alterações antes de manter um backup local.",
            )
            textSize = 13f
            setTextColor(tone(Color.rgb(180, 180, 180), Color.rgb(80, 80, 85)))
            setPadding(0, 0, 0, dp(16))
        })
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        actions.addView(actionText(ui("导出迁移文件 →", "Export migration bundle →", "Exportar pacote de migração →")) { showMigrationExportDialog() })
        actions.addView(actionText(ui("导入迁移文件 →", "Import migration bundle →", "Importar pacote de migração →")) { launchMigrationImportPicker() })
        content.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        content.addView(TextView(this).apply {
            text = ui("旧版 JSON 导入 →", "Import legacy JSON settings →", "Importar configurações JSON legadas →")
            textSize = 13f
            setTextColor(tone(Color.rgb(170, 170, 170), Color.rgb(90, 90, 95)))
            isClickable = true
            setOnClickListener { showLegacyImportWarning() }
            setPadding(0, dp(18), 0, dp(12))
        })
        content.addView(TextView(this).apply {
            text = ui(
                "旧版 JSON 导入由兼容层处理；新导出始终使用带版本和校验的 .omb 文件。",
                "Legacy JSON import remains available through the compatibility layer; new exports always use versioned, digested .omb bundles.",
                "A importação de JSON legado continua disponível pela camada de compatibilidade; novas exportações sempre usam pacotes .omb versionados e verificados.",
            )
            textSize = 11f
            setTextColor(tone(Color.rgb(120, 120, 120), Color.rgb(150, 150, 155)))
        })
        return root
    }

    private fun actionText(text: String, onClick: () -> Unit): View = TextView(this).apply {
        this.text = text
        textSize = 15f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        setTextColor(tone(Color.rgb(94, 234, 212), Color.rgb(15, 118, 110)))
        isClickable = true
        setPadding(0, dp(8), 0, dp(8))
        setOnClickListener { onClick() }
    }

    private fun showMigrationExportDialog() {
        val modes = arrayOf(
            ui("分享（脱敏，不带凭据）", "Share (redacted, no credentials)", "Compartilhar (sem credenciais)"),
            ui("个人迁移（可选密码保护凭据）", "Personal migration (optional password-protected credentials)", "Migração pessoal (credenciais protegidas por senha)"),
        )
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("选择导出模式", "Choose export mode", "Escolher modo de exportação"))
            .setItems(modes) { _, which ->
                if (which == 0) {
                    launchMigrationExportPicker("share_redacted", false, null)
                } else {
                    showMigrationPasswordDialog { password ->
                        launchMigrationExportPicker("personal_migration", true, password)
                    }
                }
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun showMigrationPasswordDialog(onConfirmed: (String) -> Unit) {
        val field = EditText(this).apply {
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            hint = ui("至少输入一个密码字符", "Enter a password", "Digite uma senha")
        }
        val container = FrameLayout(this).apply {
            setPadding(dp(24), 0, dp(24), 0)
            addView(field, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("保护迁移凭据", "Protect migration credentials", "Proteger credenciais de migração"))
            .setMessage(ui(
                "密码不会写入文件名、摘要或日志。请在目标设备导入时输入相同密码。",
                "The password is never written to the filename, summary, or logs. Enter the same password on the destination device.",
                "A senha nunca é gravada no nome do arquivo, resumo ou logs. Digite a mesma senha no dispositivo de destino.",
            ))
            .setView(container)
            .setPositiveButton(ui("继续选择文件", "Choose destination", "Escolher destino")) { _, _ ->
                val password = field.text.toString()
                if (password.isBlank()) {
                    Toast.makeText(this, ui("密码不能为空", "Password cannot be empty", "A senha não pode ficar vazia"), Toast.LENGTH_SHORT).show()
                } else {
                    onConfirmed(password)
                }
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun launchMigrationExportPicker(mode: String, includeCredentials: Boolean, password: String?) {
        if (!OpenLessMigrationBundlePolicy.validateExport(mode, includeCredentials, password)) {
            Toast.makeText(this, ui("导出选项无效", "Invalid export options", "Opções de exportação inválidas"), Toast.LENGTH_SHORT).show()
            return
        }
        pendingExportMode = mode
        pendingExportIncludeCredentials = includeCredentials
        pendingExportPassword = password
        val timestamp = android.text.format.DateFormat.format("yyyyMMdd-HHmm", System.currentTimeMillis())
        val intent = android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(android.content.Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(android.content.Intent.EXTRA_TITLE, "openless-migration-$timestamp.omb")
        }
        runCatching { startActivityForResult(intent, requestCodeExportSave) }.onFailure {
            clearPendingExport()
            Toast.makeText(this, ui("找不到文件管理器", "No file manager available", "Nenhum gerenciador de arquivos disponível"), Toast.LENGTH_LONG).show()
        }
    }

    private fun clearPendingExport() {
        pendingExportMode = null
        pendingExportIncludeCredentials = false
        pendingExportPassword = null
    }

    private fun launchMigrationImportPicker() {
        val intent = android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(android.content.Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
        }
        runCatching { startActivityForResult(intent, requestCodeImportOpen) }
            .onFailure { Toast.makeText(this, ui("找不到文件选择器", "No file picker available", "Nenhum seletor de arquivos disponível"), Toast.LENGTH_SHORT).show() }
    }

    private fun showLegacyImportWarning() {
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("导入旧版 JSON", "Import legacy JSON", "Importar JSON legado"))
            .setMessage(
                ui(
                    "旧版 JSON 是明文兼容格式，可能包含 API key 或 token，不具备 .omb 的密码加密和完整性校验。请只导入可信来源；新版 .omb 解压后的 documents.json 必须通过“导入迁移文件”导入。",
                    "Legacy JSON is a plaintext compatibility format and may contain API keys or tokens; it does not have the password encryption or integrity checks of .omb. Import only from a trusted source. The documents.json extracted from a new .omb bundle must be imported through “Import migration bundle”.",
                    "O JSON legado é um formato de compatibilidade em texto simples e pode conter chaves de API ou tokens; ele não possui criptografia por senha nem verificação de integridade do .omb. Importe apenas de fontes confiáveis. O documents.json extraído de um pacote .omb deve ser importado por “Importar pacote de migração”.",
                ),
            )
            .setPositiveButton(ui("选择文件", "Choose file", "Escolher arquivo")) { _, _ -> launchLegacyImportPicker() }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun launchLegacyImportPicker() {
        val intent = android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(android.content.Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }
        runCatching { startActivityForResult(intent, requestCodeLegacyImportOpen) }
            .onFailure { Toast.makeText(this, ui("找不到文件选择器", "No file picker available", "Nenhum seletor de arquivos disponível"), Toast.LENGTH_SHORT).show() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data == null) {
            if (requestCode == requestCodeExportSave) clearPendingExport()
            return
        }
        when (requestCode) {
            requestCodeExportSave -> {
                val uri = data.data
                val mode = pendingExportMode
                val includeCredentials = pendingExportIncludeCredentials
                val password = pendingExportPassword.orEmpty()
                clearPendingExport()
                if (uri == null || mode == null) return
                if (includeCredentials && password.isEmpty()) {
                    showMigrationPasswordDialog { restoredPassword -> performMigrationExport(uri, mode, true, restoredPassword) }
                } else {
                    performMigrationExport(uri, mode, includeCredentials, password)
                }
            }
            requestCodeImportOpen -> {
                val uri = data.data ?: return
                Thread {
                    val result = runCatching {
                        val bytes = OpenLessContentReader.readBytes(this, uri.toString(), maxMigrationBundleBytes)
                            ?: error("read selected document failed")
                        val bundleBase64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                        val envelope = org.json.JSONObject(OpenLessNative.nativeInspectLocalMigrationBundle(bundleBase64))
                        check(envelope.optBoolean("ok")) { envelope.optString("error", "invalid migration bundle") }
                        bundleBase64 to envelope.getJSONObject("payload")
                    }
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        result.onSuccess { (bundleBase64, inspection) -> showMigrationImportSummary(bundleBase64, inspection) }
                            .onFailure { error ->
                                Toast.makeText(this, ui("读取或校验失败：${error.message}", "Read or validation failed: ${error.message}", "Falha na leitura ou validação: ${error.message}"), Toast.LENGTH_LONG).show()
                            }
                    }
                }.start()
            }
            requestCodeLegacyImportOpen -> {
                val uri = data.data ?: return
                Thread {
                    val json = OpenLessContentReader.readBytes(this, uri.toString(), 4 * 1024 * 1024)
                        ?.toString(Charsets.UTF_8)
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        if (json.isNullOrBlank()) {
                            Toast.makeText(this, ui("读取旧版配置失败或文件超过 4 MiB", "Read failed or legacy file exceeds 4 MiB", "Falha na leitura ou arquivo legado excede 4 MiB"), Toast.LENGTH_SHORT).show()
                        } else {
                            showImportCategoryDialog(json)
                        }
                    }
                }.start()
            }
        }
    }

    private fun showImportCategoryDialog(json: String) {
        val present = OpenLessSettingsExport.categoriesPresent(json)
        if (present.isEmpty()) {
            Toast.makeText(
                this,
                ui(
                    "这不是旧版设置 JSON；如果文件是 .omb 解压目录中的 documents.json，请使用“导入迁移文件”导入整个 .omb 文件。",
                    "This is not a legacy settings JSON. If it is documents.json from an extracted .omb bundle, use “Import migration bundle” with the complete .omb file.",
                    "Este não é um JSON de configurações legado. Se for o documents.json extraído de um pacote .omb, use “Importar pacote de migração” com o arquivo .omb completo.",
                ),
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        val categories = present.toList()
        val labels = categories.map { ui(it.labelZh, it.labelEn, it.labelPt) }.toTypedArray()
        val checked = BooleanArray(categories.size) { true }
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("选择要导入的内容", "Choose what to import", "Escolher o que importar"))
            .setMultiChoiceItems(labels, checked) { _, which, isChecked -> checked[which] = isChecked }
            .setPositiveButton(ui("导入", "Import", "Importar")) { _, _ ->
                val selected = categories.filterIndexed { index, _ -> checked[index] }.toSet()
                if (selected.isEmpty()) {
                    Toast.makeText(this, ui("没有选择任何内容", "Nothing selected", "Nada selecionado"), Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                Thread {
                    val imported = runCatching { OpenLessSettingsExport.import(this, json, selected) }
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        val result = imported.getOrNull()
                        val message = if (result == null) {
                            ui("配置文件无效，导入失败", "Invalid settings file; import failed", "Arquivo de configurações inválido; falha na importação")
                        } else {
                            buildString {
                                append(ui("已导入 ${result.applied.size} 项", "Imported ${result.applied.size} categories", "${result.applied.size} categorias importadas"))
                                for ((category, reason) in result.errors) {
                                    append('\n').append(ui(category.labelZh, category.labelEn, category.labelPt)).append(": ").append(reason)
                                }
                            }
                        }
                        android.app.AlertDialog.Builder(this)
                            .setMessage(message)
                            .setPositiveButton(android.R.string.ok, null)
                            .show()
                        setContentView(buildContent())
                    }
                }.start()
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun performMigrationExport(
        uri: android.net.Uri,
        mode: String,
        includeCredentials: Boolean,
        password: String,
    ) {
        Thread {
            val result = runCatching {
                val envelope = org.json.JSONObject(
                    OpenLessNative.nativeExportLocalMigrationBundle(
                        mode,
                        includeCredentials,
                        password,
                    ),
                )
                check(envelope.optBoolean("ok")) { envelope.optString("error", "export failed") }
                val payload = envelope.getJSONObject("payload")
                val bytes = android.util.Base64.decode(payload.getString("bundleBase64"), android.util.Base64.DEFAULT)
                check(bytes.size <= maxMigrationBundleBytes) { "bundle exceeds size limit" }
                check(OpenLessContentWriter.writeBytes(this, uri.toString(), bytes)) { "write selected document failed" }
                payload.getJSONObject("inspection")
            }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                result.onSuccess { inspection ->
                    Toast.makeText(this, ui("已导出迁移文件（${inspection.optInt("documentCount")} 项）", "Migration bundle exported (${inspection.optInt("documentCount")} documents)", "Pacote de migração exportado (${inspection.optInt("documentCount")} documentos)"), Toast.LENGTH_LONG).show()
                }.onFailure { error ->
                    Toast.makeText(this, ui("导出失败：${error.message}", "Export failed: ${error.message}", "Falha ao exportar: ${error.message}"), Toast.LENGTH_LONG).show()
                }
            }
        }.start()
    }

    private fun migrationInspectionText(inspection: org.json.JSONObject): String = buildString {
        append(ui("格式：", "Format: ", "Formato: ")).append(inspection.optString("format")).append('\n')
        append(ui("版本：", "Version: ", "Versão: ")).append(inspection.optInt("formatVersion")).append('\n')
        append(ui("文档：", "Documents: ", "Documentos: ")).append(inspection.optInt("documentCount")).append('\n')
        append(ui("渠道：", "Channels: ", "Canais: ")).append(inspection.optJSONObject("sectionCounts")?.optInt("channels") ?: 0).append('\n')
        append(ui("词典 / 纠错 / 风格包：", "Dictionary / corrections / style packs: ", "Dicionário / correções / pacotes de estilo: "))
            .append(inspection.optJSONObject("sectionCounts")?.optInt("dictionary") ?: 0).append(" / ")
            .append(inspection.optJSONObject("sectionCounts")?.optInt("corrections") ?: 0).append(" / ")
            .append(inspection.optJSONObject("sectionCounts")?.optInt("stylePacks") ?: 0).append('\n')
        append(ui("凭据：", "Credentials: ", "Credenciais: ")).append(
            if (inspection.optBoolean("credentialsEncrypted")) ui("已加密", "password protected", "protegidas por senha") else ui("未携带", "not included", "não incluídas"),
        ).append('\n')
        val skipped = inspection.optInt("skippedHistory") + inspection.optInt("skippedActivity") + inspection.optInt("skippedTombstones")
        if (skipped > 0) appendLine(ui("已跳过历史、统计及删除标记：$skipped 项", "Skipped history, activity and deletion markers: $skipped", "Histórico, atividade e marcadores de exclusão ignorados: $skipped"))
        append(ui("系统权限不会迁移，目标设备需重新授权。", "System permissions do not migrate; authorize them again on the destination device.", "As permissões do sistema não são migradas; autorize-as novamente no dispositivo de destino."))
    }

    private fun showMigrationImportSummary(bundleBase64: String, inspection: org.json.JSONObject) {
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("确认迁移文件", "Review migration bundle", "Revisar pacote de migração"))
            .setMessage(migrationInspectionText(inspection))
            .setPositiveButton(ui("选择合并 / 替换", "Choose merge / replace", "Escolher mesclar / substituir")) { _, _ ->
                val encrypted = inspection.optBoolean("credentialsEncrypted")
                if (encrypted) {
                    showMigrationPasswordDialog { password -> showMigrationRestoreMode(bundleBase64, password) }
                } else {
                    showMigrationRestoreMode(bundleBase64, "")
                }
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun showMigrationRestoreMode(bundleBase64: String, password: String) {
        android.app.AlertDialog.Builder(this)
            .setTitle(ui("导入方式", "Restore mode", "Modo de restauração"))
            .setItems(arrayOf(ui("合并", "Merge", "Mesclar"), ui("替换", "Replace", "Substituir"))) { _, which ->
                previewMigration(bundleBase64, password, if (which == 0) "merge" else "replace")
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun previewMigration(bundleBase64: String, password: String, mode: String, allowStaleRetry: Boolean = true) {
        Thread {
            val previewResult = runCatching {
                val response = org.json.JSONObject(OpenLessNative.nativePreviewLocalMigrationBundle(bundleBase64, password, mode))
                check(response.optBoolean("ok")) { response.optString("error", "preview failed") }
                response.getJSONObject("payload").also { preview ->
                    check(preview.optString("observedGeneration").isNotBlank()) { "preview missing observed generation" }
                    check(preview.optString("observedAndroidRevision").isNotBlank()) { "preview missing Android revision" }
                }
            }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                previewResult.onSuccess { preview ->
                    chooseMigrationConflicts(bundleBase64, password, preview.getJSONArray("conflicts"), 0, org.json.JSONArray()) { choices ->
                        confirmMigration(bundleBase64, password, mode, preview, choices, allowStaleRetry)
                    }
                }.onFailure { error ->
                    Toast.makeText(this, ui("预览失败：${error.message}", "Preview failed: ${error.message}", "Falha na pré-visualização: ${error.message}"), Toast.LENGTH_LONG).show()
                }
            }
        }.start()
    }

    private fun chooseMigrationConflicts(
        bundleBase64: String,
        password: String,
        conflicts: org.json.JSONArray,
        index: Int,
        choices: org.json.JSONArray,
        onComplete: (org.json.JSONArray) -> Unit,
    ) {
        if (index >= conflicts.length()) {
            onComplete(choices)
            return
        }
        val conflict = conflicts.getJSONObject(index)
        val kind = conflict.optString("kind")
        val reason = conflict.optString("reason")
        val credential = if (conflict.optBoolean("isCredentialUnit")) ui("（凭据关联渠道）", " (credential-linked channel)", " (canal vinculado a credenciais)") else ""
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
        }
        content.addView(TextView(this).apply {
            text = buildString {
                appendLine("$kind / ${conflict.optString("documentId")}")
                append("$reason$credential")
            }
            textSize = 14f
            setTextColor(tone(Color.rgb(220, 220, 220), Color.rgb(50, 50, 55)))
            setPadding(0, 0, 0, dp(8))
        })
        val options = RadioGroup(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        fun option(text: String): RadioButton = RadioButton(this).apply {
            this.text = text
            textSize = 15f
            minHeight = dp(48)
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(tone(Color.WHITE, Color.rgb(35, 35, 40)))
            buttonTintList = android.content.res.ColorStateList(
                arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                intArrayOf(tone(Color.rgb(94, 234, 212), Color.rgb(15, 118, 110)), tone(Color.rgb(190, 190, 190), Color.rgb(90, 90, 95))),
            )
        }
        val keepLocal = option(ui("保留当前设备", "Keep this device", "Manter este dispositivo")).apply { id = View.generateViewId() }
        val useBundle = option(ui("使用迁移文件", "Use migration file", "Usar arquivo de migração")).apply { id = View.generateViewId() }
        options.addView(keepLocal)
        options.addView(useBundle)
        content.addView(options, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle(ui("选择冲突 ${index + 1}/${conflicts.length()}", "Choose conflict ${index + 1}/${conflicts.length()}", "Resolver conflito ${index + 1}/${conflicts.length()}"))
            .setView(content)
            .setPositiveButton(ui("继续", "Continue", "Continuar"), null)
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val side = when (options.checkedRadioButtonId) {
                    keepLocal.id -> "local"
                    useBundle.id -> "remote"
                    else -> null
                }
                if (side == null) {
                    Toast.makeText(this, ui("必须选择一侧", "Choose one side", "Escolha uma das opções"), Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                choices.put(org.json.JSONObject().put("conflictId", conflict.getString("conflictId")).put("side", side))
                dialog.dismiss()
                chooseMigrationConflicts(bundleBase64, password, conflicts, index + 1, choices, onComplete)
            }
        }
        dialog.show()
    }

    private fun confirmMigration(
        bundleBase64: String,
        password: String,
        mode: String,
        preview: org.json.JSONObject,
        choices: org.json.JSONArray,
        allowStaleRetry: Boolean,
    ) {
        val message = buildString {
            append(ui(
                "两种模式都会保留你明确选择的本机冲突项。历史、统计和系统权限不会被替换。",
                "Both modes honor your Keep this device choices. History, activity and system permissions are not replaced.",
                "Ambos os modos respeitam suas escolhas de manter este dispositivo. Histórico, atividade e permissões do sistema não são substituídos.",
            ))
            val removed = preview.getJSONArray("removedDocuments")
            if (mode == "replace" && removed.length() > 0) {
                appendLine().appendLine().append(ui(
                    "以下本机独有配置将移除（冲突中明确保留的项目除外）：",
                    "Receiver-only configuration to remove, except items explicitly kept in conflict choices:",
                    "Configurações exclusivas deste dispositivo que serão removidas (exceto itens mantidos explicitamente nos conflitos):",
                ))
                for (i in 0 until removed.length()) {
                    val item = removed.getJSONObject(i)
                    appendLine().append(item.optString("kind")).append(" / ").append(item.optString("id"))
                }
            }
        }
        android.app.AlertDialog.Builder(this)
            .setTitle(if (mode == "replace") ui("确认替换", "Confirm Replace", "Confirmar substituição") else ui("确认合并", "Confirm Merge", "Confirmar mesclagem"))
            .setMessage(message)
            .setPositiveButton(ui("应用配置", "Apply configuration", "Aplicar configuração")) { _, _ ->
                Thread {
                    val result = runCatching {
                        val response = org.json.JSONObject(OpenLessNative.nativeImportLocalMigrationBundle(
                            bundleBase64, password, mode, choices.toString(),
                            preview.getString("observedGeneration"), preview.getString("observedAndroidRevision"),
                        ))
                        check(response.optBoolean("ok")) { response.optString("error", "import failed") }
                    }
                    runOnUiThread {
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        result.onSuccess {
                            Toast.makeText(this, ui("导入完成，备份已保留", "Import complete; backup retained", "Importação concluída; backup mantido"), Toast.LENGTH_LONG).show()
                            setContentView(buildContent())
                        }.onFailure { error ->
                            if (allowStaleRetry && error.message?.contains("migration_bundle_stale_preview") == true) {
                                Toast.makeText(this, ui("本机配置已变化，请重新确认预览", "Local configuration changed; review the new preview", "A configuração local mudou; revise a nova pré-visualização"), Toast.LENGTH_LONG).show()
                                previewMigration(bundleBase64, password, mode, allowStaleRetry = false)
                            } else {
                                Toast.makeText(this, ui("导入未完成：${error.message}", "Import not completed: ${error.message}", "Importação não concluída: ${error.message}"), Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                }.start()
            }
            .setNegativeButton(ui("取消", "Cancel", "Cancelar"), null)
            .show()
    }

    private fun sectionLabel(text: String): View = TextView(this).apply {
        this.text = text
        textSize = 12f
        setTextColor(tone(Color.rgb(150, 150, 150), Color.rgb(110, 110, 115)))
        setPadding(0, 0, 0, dp(8))
    }
}

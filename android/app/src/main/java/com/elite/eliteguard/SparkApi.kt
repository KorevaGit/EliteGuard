package com.elite.eliteguard

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpCookie
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val BASE = "https://spark.elitesochi.com"
data class PairCode(val session: String, val fingerprint: String) {
    companion object {
        fun parse(raw: String): PairCode? = runCatching {
            val uri = android.net.Uri.parse(raw.trim())
            val s = uri.getQueryParameter("s") ?: return null
            val f = uri.getQueryParameter("f") ?: return null
            if (uri.scheme?.lowercase() != "elitesip" || uri.host != "pair" ||
                !s.matches(Regex("[0-9a-fA-F]{32}")) || !f.matches(Regex("[0-9a-fA-F]{16}"))) null
            else PairCode(s.lowercase(), f.lowercase())
        }.getOrNull()
    }
}
sealed interface PairSource { data class Qr(val code: PairCode): PairSource; data class Number(val code: String): PairSource }
data class User(val id: Int, val first: String, val last: String, val number: String, val dismissed: Boolean, val workplaceId: Int?) {
    val name get() = listOf(last, first).filter { it.isNotBlank() }.joinToString(" ")
}
data class Line(val id: Int = 0, val number: String = "", val label: String = "", val password: String = "") {
    fun json() = JSONObject().put("id", id).put("extension", number).put("label", label).put("sip_password", password)
}
data class Workplace(val id: Int, val userId: Int, val first: String, val last: String, val number: String,
    val label: String, val format: String, val presetId: Int?, val presetName: String, val machines: Int,
    val sipPassword: String, val note: String, val lines: List<Line>, val passwordSource: String = "manual") {
    val name get() = listOf(last, first).filter { it.isNotBlank() }.joinToString(" ")
}
data class Machine(val id: Int, val name: String, val state: String, val applied: Boolean, val lastSeen: String?, val version: String)
data class Detail(val workplace: Workplace, val machines: List<Machine>, val conflicts: List<String>)
data class Preset(val id: Int, val name: String)
data class StaffDefaults(val presetId: Int?, val password: String, val standardSource: String = "")
data class Preview(val code: String, val state: String, val name: String, val version: String)
data class WorkplaceInput(val userId: Int, val first: String, val last: String, val number: String, val label: String,
    val password: String, val format: String, val presetId: Int?, val note: String, val lines: List<Line>, val passwordSource: String = "manual") {
    fun json() = JSONObject().put("bitrix_user_id", userId).put("first_name", first).put("last_name", last)
        .put("extension", number).put("label", label).put("sip_password", password).put("sip_password_source", passwordSource).put("work_format", format)
        .put("preset_id", presetId ?: JSONObject.NULL).put("note", note)
        .put("lines", JSONArray().also { a -> lines.forEach { a.put(it.json()) } })
}

private fun JSONObject.str(k: String) = optString(k).takeUnless { it == "null" } ?: ""
private fun JSONObject.intOrNull(k: String): Int? = if (isNull(k) || !has(k)) null else optInt(k)
private fun JSONObject.workplace() = Workplace(optInt("id"), optInt("bitrix_user_id"), str("first_name"), str("last_name"),
    str("extension"), str("label"), str("work_format"), intOrNull("preset_id"), str("preset_name"), optInt("machines"),
    str("sip_password"), str("note"), optJSONArray("lines").objects().map { Line(it.optInt("id"), it.str("extension"), it.str("label"), it.str("sip_password")) }, str("sip_password_source"))
private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).map { getJSONObject(it) }

class SparkApi(context: Context) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)
    private val vault = TokenVault()
    private val cookies = java.net.CookieManager(null, java.net.CookiePolicy.ACCEPT_ALL)
    private val refreshMutex = Mutex()
    private var token: String? = vault.read(prefs.getString("token", null))
    init {
        vault.read(prefs.getString("refresh_cookie", null))?.let { value ->
            cookies.cookieStore.add(URI(BASE), HttpCookie("refresh_token", value).apply { path = "/"; isHttpOnly = true })
        }
    }
    var userName: String = prefs.getString("user_name", "") ?: ""
        private set
    val signedIn get() = token != null

    suspend fun login(login: String, password: String, local: Boolean) {
        val response = request("POST", "/api/auth/login", JSONObject().put("login", login).put("password", password)
            .put("method", if (local) "local" else "bitrix"), auth = false)
        setToken(response.str("access_token"))
        userName = response.optString("name", login).ifBlank { login }
        prefs.edit().putString("user_name", userName).apply()
    }
    suspend fun logout() {
        runCatching { request("POST", "/api/auth/logout", auth = true, retry = false) }
        setToken(null)
        cookies.cookieStore.removeAll()
        prefs.edit().remove("refresh_cookie").apply()
    }
    suspend fun users(q: String): List<User> = request("GET", "/api/elitesip/bitrix-users?q=${java.net.URLEncoder.encode(q, "UTF-8")}")
        .optJSONArray("items").objects().map { User(it.optInt("user_id"), it.str("first_name"), it.str("last_name"),
            it.str("call_number"), it.str("date_of_dismissal").isNotBlank(), it.intOrNull("workplace_id")) }
    suspend fun workplaces(): List<Workplace> = request("GET", "/api/elitesip/workplaces").optJSONArray("items").objects().map { it.workplace() }
    suspend fun detail(id: Int): Detail = request("GET", "/api/elitesip/workplaces/$id").let { r ->
        Detail(r.getJSONObject("workplace").workplace(), r.optJSONArray("machines").objects().map {
            val check = it.optJSONObject("checkin")
            Machine(it.optInt("id"), it.str("device_name"), it.str("state"), it.optBoolean("applied"),
                check?.str("last_seen_at"), check?.str("app_version") ?: "")
        }, r.optJSONArray("conflicts")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList())
    }
    suspend fun presets(): List<Preset> = request("GET", "/api/elitesip/presets").optJSONArray("items").objects()
        .filter { it.isNull("archived_at") && it.optInt("published_revision") > 0 }.map { Preset(it.optInt("id"), it.str("name")) }
    suspend fun defaults(): StaffDefaults = request("GET", "/api/elitesip/staff-defaults").let { StaffDefaults(it.intOrNull("preset_id"), it.str("sip_password"), it.str("standard_password_source")) }
    suspend fun saveDefaults(value: StaffDefaults) { request("PUT", "/api/elitesip/staff-defaults", JSONObject()
        .put("preset_id", value.presetId ?: JSONObject.NULL).put("sip_password", value.password)) }
    suspend fun create(input: WorkplaceInput): Workplace = request("POST", "/api/elitesip/workplaces", input.json()).workplace()
    suspend fun update(id: Int, input: WorkplaceInput): JSONObject = request("PUT", "/api/elitesip/workplaces/$id", input.json())
    suspend fun delete(id: Int) { request("DELETE", "/api/elitesip/workplaces/$id") }
    suspend fun push(id: Int): JSONObject = request("POST", "/api/elitesip/workplaces/$id/push")
    suspend fun revoke(id: Int) { request("POST", "/api/elitesip/machines/$id/revoke") }
    suspend fun preview(source: PairSource): Preview {
        val path = when(source) {
            is PairSource.Qr -> "/api/elitesip/pair/${source.code.session}?f=${source.code.fingerprint}"
            is PairSource.Number -> "/api/elitesip/pair-code/${source.code}"
        }
        return request("GET", path).let { Preview(it.str("code"), it.str("state"), it.str("device_name"), it.str("app_version")) }
    }
    suspend fun claim(source: PairSource, id: Int): JSONObject = when(source) {
        is PairSource.Qr -> request("POST", "/api/elitesip/pair/${source.code.session}/claim", JSONObject()
            .put("fingerprint", source.code.fingerprint).put("workplace_id", id))
        is PairSource.Number -> request("POST", "/api/elitesip/workplaces/$id/machines", JSONObject().put("code", source.code))
    }

    private fun setToken(value: String?) {
        token = value
        prefs.edit().apply { if (value == null) remove("token") else putString("token", vault.encrypt(value)) }.apply()
    }
    private suspend fun request(method: String, path: String, body: JSONObject? = null, auth: Boolean = true, retry: Boolean = true): JSONObject {
        val used = if (auth) token else null
        val (status, data) = raw(method, path, body, used)
        if (status == 401 && auth && retry) {
            refreshMutex.withLock {
                if (token == used) {
                    val (refreshStatus, refreshData) = raw("POST", "/api/auth/refresh", JSONObject(), null)
                    if (refreshStatus == 200) setToken(JSONObject(refreshData).str("access_token"))
                    else if (refreshStatus == 401 || refreshStatus == 403) setToken(null)
                    else error("Не удалось продлить сессию. Проверьте соединение.")
                }
            }
            if (token == null) error("Сессия истекла — войдите снова")
            return request(method, path, body, auth, retry = false)
        }
        if (status == 401 && auth) { setToken(null); error("Сессия истекла — войдите снова") }
        if (status !in 200..299) {
            val error = runCatching { JSONObject(data) }.getOrNull()
            throw IllegalStateException(error?.optString("detail")?.takeIf { it.isNotBlank() }
                ?: error?.optString("error")?.takeIf { it.isNotBlank() }
                ?: error?.optString("message")?.takeIf { it.isNotBlank() } ?: "Ошибка сервера ($status)")
        }
        return if (data.isBlank()) JSONObject() else JSONObject(data)
    }
    private suspend fun raw(method: String, path: String, body: JSONObject?, bearer: String?): Pair<Int, String> = withContext(Dispatchers.IO) {
        val url = URL(BASE + path)
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method; connectTimeout = 30_000; readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            if (bearer != null) setRequestProperty("Authorization", "Bearer $bearer")
            cookies.cookieStore.get(URI(BASE)).takeIf { it.isNotEmpty() }?.let { setRequestProperty("Cookie", it.joinToString("; ") { c -> "${c.name}=${c.value}" }) }
            if (body != null) {
                doOutput = true; setRequestProperty("Content-Type", "application/json")
                outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
        }
        try {
            connection.headerFields.filterKeys { it != null && it.equals("Set-Cookie", true) }.values.flatten().forEach {
                runCatching { HttpCookie.parse(it).forEach { cookie ->
                    cookies.cookieStore.add(URI(BASE), cookie)
                    if (cookie.name == "refresh_token") prefs.edit().apply {
                        if (cookie.maxAge == 0L) remove("refresh_cookie") else putString("refresh_cookie", vault.encrypt(cookie.value))
                    }.apply()
                } }
            }
            connection.responseCode to (if (connection.responseCode < 400) connection.inputStream else connection.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
        } finally { connection.disconnect() }
    }
}

private class TokenVault {
    private val alias = "eliteguard_access_token"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun encrypt(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray()), Base64.NO_WRAP)
    }
    fun read(value: String?): String? = if (value == null) null else runCatching {
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
        String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)))
    }.getOrNull()
}

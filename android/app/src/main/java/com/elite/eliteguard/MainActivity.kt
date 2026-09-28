package com.elite.eliteguard

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var incoming by mutableStateOf<PairCode?>(null)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        incoming = intent?.dataString?.let(PairCode::parse)
        setContent {
            SparkTheme {
                val dark = isSystemInDarkTheme()
                SideEffect {
                    WindowCompat.getInsetsController(window, window.decorView).apply {
                        isAppearanceLightStatusBars = !dark
                        isAppearanceLightNavigationBars = !dark
                    }
                }
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    Box(Modifier.safeDrawingPadding()) {
                        EliteApp(incoming) { incoming = null }
                    }
                }
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        incoming = intent.dataString?.let(PairCode::parse)
    }
}

private sealed interface Screen { data object Home: Screen; data class Profile(val id: Int): Screen;
    data class Form(val user: User? = null, val workplace: Workplace? = null): Screen; data object Defaults: Screen;
    data class Pair(val workplace: Workplace): Screen }

@Composable private fun EliteApp(incoming: PairCode?, clearIncoming: () -> Unit) {
    val context = LocalContext.current
    val api = remember { SparkApi(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var signedIn by remember { mutableStateOf(api.signedIn) }
    var screen by remember { mutableStateOf<Screen>(Screen.Home) }
    var error by remember { mutableStateOf<String?>(null) }
    var waiting by remember { mutableStateOf<Pair<PairSource, Preview>?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    fun run(block: suspend () -> Unit) { scope.launch { try { block() } catch (e: Exception) {
        if (!api.signedIn) { signedIn = false; screen = Screen.Home }
        error = e.message ?: "Неизвестная ошибка"
    } } }
    LaunchedEffect(incoming, signedIn) {
        if (incoming != null && signedIn) {
            try {
                val preview = api.preview(PairSource.Qr(incoming))
                if (preview.state == "waiting") waiting = PairSource.Qr(incoming) to preview
                else error = if (preview.state == "expired") "Код устарел" else "Машина уже привязана"
            } catch (e: Exception) { error = e.message }
            clearIncoming()
        }
    }
    BackHandler(screen != Screen.Home) { screen = Screen.Home; refresh++ }
    if (!signedIn) LoginScreen { login, password, local -> run { api.login(login, password, local); signedIn = true } }
    else when (val current = screen) {
        Screen.Home -> HomeScreen(api, refresh, waiting, { waiting = it }, { screen = it },
            { run { api.logout(); signedIn = false; waiting = null } }, ::run, { error = it })
        is Screen.Profile -> ProfileScreen(api, current.id, refresh, waiting, { screen = it }, ::run, { error = it })
        is Screen.Form -> FormScreen(api, current.user, current.workplace, { id -> screen = Screen.Profile(id); refresh++ },
            { screen = Screen.Home }, ::run, { error = it })
        Screen.Defaults -> DefaultsScreen(api, { screen = Screen.Home }, ::run, { error = it })
        is Screen.Pair -> PairScreen(api, current.workplace, waiting, { waiting = null }, { screen = Screen.Profile(current.workplace.id); refresh++ }, ::run, { error = it })
    }
    if (error != null) AlertDialog(onDismissRequest = { error = null }, title = { Text("EliteGuard") },
        text = { Text(error.orEmpty()) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
}

@Composable private fun LoginScreen(login: (String, String, Boolean) -> Unit) {
    var user by remember { mutableStateOf("") }; var password by remember { mutableStateOf("") }; var local by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("EliteGuard", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(28.dp))
        Row { FilterChip(!local, { local = false }, label = { Text("Битрикс") }); Spacer(Modifier.width(8.dp)); FilterChip(local, { local = true }, label = { Text("Spark") }) }
        OutlinedTextField(user, { user = it }, label = { Text(if (local) "Логин Spark" else "Логин Битрикс") }, singleLine = true)
        OutlinedTextField(password, { password = it }, label = { Text("Пароль") }, visualTransformation = PasswordVisualTransformation(), singleLine = true)
        Spacer(Modifier.height(16.dp))
        Button(onClick = { login(user, password, local) }, enabled = user.isNotBlank() && password.isNotBlank()) { Text("Войти") }
    }
}

@Composable private fun Header(title: String, back: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        if (back != null) TextButton(onClick = back) { Text("‹ Назад") }
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
        actions()
    }
}
@Composable private fun ErrorText(text: String) { Text(text, color = MaterialTheme.colorScheme.error) }
@Composable private fun Field(value: String, change: (String) -> Unit, label: String, secret: Boolean = false) {
    OutlinedTextField(value, change, label = { Text(label) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None)
}
@Composable private fun PresetPicker(presets: List<Preset>, selected: Int?, change: (Int?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box { OutlinedButton(onClick = { expanded = true }) { Text("Предустановка: ${presets.firstOrNull { it.id == selected }?.name ?: "не выбрана"}") }
        DropdownMenu(expanded, { expanded = false }) {
            DropdownMenuItem(text = { Text("Не выбрана") }, onClick = { change(null); expanded = false })
            presets.forEach { p -> DropdownMenuItem(text = { Text(p.name) }, onClick = { change(p.id); expanded = false }) }
        }
    }
}

@Composable private fun HomeScreen(api: SparkApi, refresh: Int, waiting: Pair<PairSource, Preview>?, setWaiting: (Pair<PairSource, Preview>?) -> Unit,
    navigate: (Screen) -> Unit, logout: () -> Unit, run: (suspend () -> Unit) -> Unit, fail: (String) -> Unit) {
    var workplaces by remember { mutableStateOf(emptyList<Workplace>()) }; var users by remember { mutableStateOf(emptyList<User>()) }
    var query by remember { mutableStateOf("") }; var number by remember { mutableStateOf("") }; var showNumber by remember { mutableStateOf(false) }
    val context = LocalContext.current
    LaunchedEffect(refresh) { run { workplaces = api.workplaces().sortedBy { it.name } } }
    LaunchedEffect(query) { if (query.trim().length < 2) users = emptyList() else { delay(350); run { users = api.users(query.trim()) } } }
    fun check(source: PairSource) { run { val p = api.preview(source); if (p.state == "waiting") setWaiting(source to p)
        else fail(if (p.state == "expired") "Код устарел" else "Машина уже привязана") } }
    Column {
        Header("EliteGuard", actions = {
            TextButton(onClick = { navigate(Screen.Form()) }) { Text("＋") }
            TextButton(onClick = { navigate(Screen.Defaults) }) { Text("⚙") }
            TextButton(onClick = logout) { Text("Выйти") }
        })
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Button(onClick = {
                val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                GmsBarcodeScanning.getClient(context, options).startScan().addOnSuccessListener { barcode ->
                    PairCode.parse(barcode.rawValue.orEmpty())?.let { check(PairSource.Qr(it)) } ?: fail("Это не QR клиента EliteSIP")
                }.addOnFailureListener { fail(it.message ?: "Не удалось открыть сканер") }
            }) { Text("Сканировать QR") }
            Spacer(Modifier.width(8.dp)); OutlinedButton(onClick = { showNumber = true }) { Text("Номер машины") }
        }
        if (waiting != null) Card(Modifier.fillMaxWidth().padding(16.dp)) { Row(Modifier.padding(16.dp)) {
            Text("${waiting.second.name.ifBlank { "Машина" }} · код ${waiting.second.code}\nВыберите сотрудника")
            Spacer(Modifier.weight(1f)); TextButton(onClick = { setWaiting(null) }) { Text("×") }
        } }
        Field(query, { query = it }, "Фамилия, имя или номер")
        if (query.trim().length >= 2) LazyColumn { items(users) { user -> ListItem(
            headlineContent = { Text(user.name.ifBlank { "Без имени" }) },
            supportingContent = { Text("доб. ${user.number} ${if (user.dismissed) "· уволен" else ""}") },
            modifier = Modifier.clickable { navigate(user.workplaceId?.let(Screen::Profile) ?: Screen.Form(user = user)) }) } }
        else {
            Text("Активные машины: ${workplaces.sumOf { it.machines }}", Modifier.padding(16.dp))
            LazyColumn { items(workplaces) { wp -> ListItem(headlineContent = { Text(wp.name.ifBlank { wp.label }) },
                supportingContent = { Text("доб. ${wp.number} · машин: ${wp.machines}") },
                modifier = Modifier.clickable { navigate(Screen.Profile(wp.id)) }) } }
        }
    }
    if (showNumber) AlertDialog(onDismissRequest = { showNumber = false }, title = { Text("Номер машины") },
        text = { Field(number, { number = it }, "Шесть цифр") },
        confirmButton = { TextButton(onClick = { showNumber = false; check(PairSource.Number(number.filter(Char::isDigit))); number = "" },
            enabled = number.filter(Char::isDigit).length == 6) { Text("Проверить") } },
        dismissButton = { TextButton(onClick = { showNumber = false }) { Text("Отмена") } })
}

@Composable private fun ProfileScreen(api: SparkApi, id: Int, refresh: Int, waiting: Pair<PairSource, Preview>?, navigate: (Screen) -> Unit,
    run: (suspend () -> Unit) -> Unit, fail: (String) -> Unit) {
    var detail by remember(id) { mutableStateOf<Detail?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }; var revoke by remember { mutableStateOf<Machine?>(null) }
    LaunchedEffect(id, refresh) { run { detail = api.detail(id) } }
    Column {
        Header(detail?.workplace?.name?.ifBlank { detail?.workplace?.label } ?: "Сотрудник", { navigate(Screen.Home) },
            actions = { TextButton(onClick = { run { detail = api.detail(id) } }) { Text("↻") } })
        val d = detail
        if (d == null) { CircularProgressIndicator(); return@Column }
        val wp = d.workplace
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Добавочный: ${wp.number}")
            Text("Подпись: ${wp.label}")
            Text("Формат: ${if (wp.format == "remote") "Удалёнка" else "Офис"}")
            Text("Предустановка: ${wp.presetName.ifBlank { "не выбрана" }}")
            Text("Изменения в Spark поступят на машины в течение 15 минут.", style = MaterialTheme.typography.bodySmall)
            OutlinedButton(onClick = { navigate(Screen.Form(workplace = wp)) }) { Text("Изменить сотрудника") }
            if (d.machines.any { it.state != "revoked" }) OutlinedButton(onClick = { run {
                val result = api.push(id); fail(result.optString("warning").takeIf { it.isNotBlank() }
                    ?: "Настройки отправлены на ${result.optInt("pushed")} машин"); detail = api.detail(id)
            } }) { Text("Отправить настройки заново") }
            if (d.conflicts.isNotEmpty()) ErrorText("На этом добавочном уже работают: ${d.conflicts.joinToString()}")
            Button(onClick = { navigate(Screen.Pair(wp)) }, enabled = wp.presetId != null && wp.number.isNotBlank() && d.conflicts.isEmpty()) {
                Text(if (waiting == null) "Привязать машину" else "Привязать ждущую машину")
            }
            if (wp.presetId == null) Text("Для привязки выберите предустановку")
            Text("Машины", style = MaterialTheme.typography.titleMedium)
            if (d.machines.isEmpty()) Text("Машин пока нет")
            d.machines.forEach { m -> Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
                Text(m.name.ifBlank { "Машина" }, style = MaterialTheme.typography.titleMedium)
                Text(when { m.state == "revoked" -> "Отвязана"; m.state == "legacy" -> "Ждёт обновления"
                    m.lastSeen == null -> "Не выходила на связь"; !m.applied -> "Применяет настройки"; else -> "Работает" })
                if (m.lastSeen != null) Text("На связи: ${m.lastSeen} · ${m.version}")
                if (m.state != "revoked") TextButton(onClick = { revoke = m }) { Text("Отвязать машину") }
            } } }
            OutlinedButton(onClick = { confirmDelete = true }, enabled = d.machines.none { it.state != "revoked" }) { Text("Удалить пользователя") }
            if (d.machines.any { it.state != "revoked" }) Text("Перед удалением отвяжите все машины")
        }
    }
    if (revoke != null) AlertDialog(onDismissRequest = { revoke = null }, title = { Text("Отвязать машину?") },
        text = { Text("Машина сбросится при следующей проверке, в течение 15 минут.") },
        confirmButton = { TextButton(onClick = { val m = revoke!!; revoke = null; run { api.revoke(m.id); detail = api.detail(id) } }) { Text("Отвязать") } },
        dismissButton = { TextButton(onClick = { revoke = null }) { Text("Отмена") } })
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Удалить пользователя?") },
        text = { Text("Профиль будет удалён из Spark.") },
        confirmButton = { TextButton(onClick = { confirmDelete = false; run { api.delete(id); navigate(Screen.Home) } }) { Text("Удалить") } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Отмена") } })
}

@Composable private fun FormScreen(api: SparkApi, user: User?, workplace: Workplace?, saved: (Int) -> Unit, back: () -> Unit,
    run: (suspend () -> Unit) -> Unit, fail: (String) -> Unit) {
    val manual = user == null && (workplace == null || workplace.userId == 0)
    var first by remember { mutableStateOf(workplace?.first ?: "") }; var last by remember { mutableStateOf(workplace?.last ?: "") }
    var number by remember { mutableStateOf(workplace?.number ?: "") }; var label by remember { mutableStateOf(workplace?.label ?: user?.last.orEmpty()) }
    var password by remember { mutableStateOf(workplace?.sipPassword ?: "") }; var standard by remember { mutableStateOf(workplace?.passwordSource == "standard" || workplace == null) }
    var remote by remember { mutableStateOf(workplace?.format == "remote") }; var preset by remember { mutableStateOf(workplace?.presetId) }
    var presets by remember { mutableStateOf(emptyList<Preset>()) }; var defaults by remember { mutableStateOf(StaffDefaults(null, "")) }
    var lines by remember { mutableStateOf(workplace?.lines ?: emptyList()) }; var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { run {
        presets = api.presets()
        defaults = api.defaults()
        if (workplace == null) { preset = defaults.presetId; standard = defaults.standardSource == "freepbx" }
    } }
    Column {
        Header(if (workplace != null) "Изменить сотрудника" else if (user == null) "Ручной профиль" else "Новый сотрудник", back)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (manual) { Field(first, { first = it }, "Имя"); Field(last, { last = it; if (label.isBlank()) label = it }, "Фамилия") }
            else { Text("Сотрудник Битрикса: ${user?.name ?: workplace?.name}"); Text("Добавочный: ${user?.number ?: workplace?.number}") }
            if (manual) Field(number, { number = it }, "Добавочный")
            Field(label, { label = it }, "Подпись")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(standard, { standard = it }, enabled = defaults.standardSource == "freepbx"); Text("Стандартный SIP-пароль")
            }
            if (!standard) Field(password, { password = it }, "SIP-пароль", secret = true)
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(remote, { remote = it }); Spacer(Modifier.width(8.dp)); Text("Удалёнка") }
            PresetPicker(presets, preset) { preset = it }
            if (manual) {
                Text("Дополнительные номера", style = MaterialTheme.typography.titleMedium)
                lines.forEachIndexed { i, line -> Card { Column(Modifier.padding(12.dp)) {
                    Field(line.number, { value -> lines = lines.toMutableList().also { it[i] = line.copy(number = value) } }, "Добавочный")
                    Field(line.label, { value -> lines = lines.toMutableList().also { it[i] = line.copy(label = value) } }, "Подпись")
                    Field(line.password, { value -> lines = lines.toMutableList().also { it[i] = line.copy(password = value) } }, "SIP-пароль", true)
                    TextButton(onClick = { lines = lines.filterIndexed { index, _ -> index != i } }) { Text("Удалить номер") }
                } } }
                if (lines.size < 8) TextButton(onClick = { lines = lines + Line() }) { Text("Добавить номер") }
            }
            val useStandard = standard
            val actualPassword = if (useStandard) "" else password
            val valid = label.isNotBlank() && (if (useStandard) defaults.standardSource == "freepbx" else actualPassword.isNotBlank()) && (!manual ||
                ((first.isNotBlank() || last.isNotBlank()) && number.isNotBlank() && number.all(Char::isDigit) &&
                lines.all { it.number.isNotBlank() && it.password.isNotBlank() }))
            Button(onClick = { busy = true; run {
                try {
                    val input = WorkplaceInput(user?.id ?: workplace?.userId ?: 0, first.trim(), last.trim(), number.trim(),
                        label.trim(), actualPassword, if (remote) "remote" else "office", preset, workplace?.note.orEmpty(), lines,
                        if (useStandard) "standard" else "manual")
                    if (workplace == null) saved(api.create(input).id)
                    else { val result = api.update(workplace.id, input); saved(workplace.id)
                        fail(result.optString("warning").takeIf { it.isNotBlank() } ?: "Сохранено") }
                } finally { busy = false }
            } }, enabled = valid && !busy) { Text(if (workplace == null) "Создать профиль" else "Сохранить") }
        }
    }
}

@Composable private fun DefaultsScreen(api: SparkApi, back: () -> Unit, run: (suspend () -> Unit) -> Unit, fail: (String) -> Unit) {
    var value by remember { mutableStateOf(StaffDefaults(null, "")) }; var presets by remember { mutableStateOf(emptyList<Preset>()) }
    LaunchedEffect(Unit) { run { value = api.defaults(); presets = api.presets() } }
    Column {
        Header("Стандартные настройки", back)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            PresetPicker(presets, value.presetId) { value = value.copy(presetId = it) }
            Text("Стандартный SIP-пароль берётся отдельно для каждого номера из FreePBX.")
            Button(onClick = { run { api.saveDefaults(value.copy(password = "")); back() } }) { Text("Сохранить") }
        }
    }
}

@Composable private fun PairScreen(api: SparkApi, workplace: Workplace, waiting: Pair<PairSource, Preview>?, clearWaiting: () -> Unit,
    back: () -> Unit, run: (suspend () -> Unit) -> Unit, fail: (String) -> Unit) {
    var source by remember { mutableStateOf(waiting?.first) }; var preview by remember { mutableStateOf(waiting?.second) }
    var manual by remember { mutableStateOf("") }; var number by remember { mutableStateOf("") }; var done by remember { mutableStateOf(false) }
    val context = LocalContext.current
    fun load(value: PairSource) { run { val p = api.preview(value); if (p.state != "waiting") fail(if (p.state == "expired") "Код устарел" else "Машина уже привязана")
        else { source = value; preview = p } } }
    Column {
        Header("Привязка машины", back)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (done) { Text("Машина привязана. Она получит номер и настройки от Spark."); Button(onClick = back) { Text("Готово") } }
            else if (source == null || preview == null) {
                Button(onClick = {
                    val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                    GmsBarcodeScanning.getClient(context, options).startScan().addOnSuccessListener {
                        PairCode.parse(it.rawValue.orEmpty())?.let { code -> load(PairSource.Qr(code)) } ?: fail("Это не QR клиента EliteSIP")
                    }.addOnFailureListener { fail(it.message ?: "Не удалось открыть сканер") }
                }) { Text("Сканировать QR") }
                Field(manual, { manual = it }, "Ссылка из QR")
                OutlinedButton(onClick = { PairCode.parse(manual)?.let { load(PairSource.Qr(it)) } ?: fail("Некорректная ссылка") }) { Text("Проверить ссылку") }
                Field(number, { number = it }, "Шестизначный код")
                OutlinedButton(onClick = { load(PairSource.Number(number.filter(Char::isDigit))) }, enabled = number.filter(Char::isDigit).length == 6) { Text("Проверить код") }
            } else {
                Text("Привязать машину?", style = MaterialTheme.typography.titleLarge)
                Text("Машина: ${preview!!.name.ifBlank { "без имени" }}")
                Text("Код на экране: ${preview!!.code}")
                Text("EliteSIP: ${preview!!.version}")
                Text("Сотрудник: ${workplace.name.ifBlank { workplace.label }}")
                Text("Добавочный: ${workplace.number}")
                Text("Предустановка: ${workplace.presetName}")
                Text("Сверьте код с экраном машины.")
                Button(onClick = { run { api.claim(source!!, workplace.id); clearWaiting(); done = true } }) { Text("Привязать") }
                TextButton(onClick = { source = null; preview = null }) { Text("Другая машина") }
            }
        }
    }
}

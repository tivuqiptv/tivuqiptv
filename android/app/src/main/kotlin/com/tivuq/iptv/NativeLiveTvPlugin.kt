package com.tivuq.iptv

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class NativeLiveTvPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private var overlay: NativeLiveTvOverlay? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                val rawChannels = call.argument<List<Map<String, Any?>>>("channels").orEmpty()
                val channels = rawChannels.mapIndexed { index, item ->
                    NativeChannel(
                        originalIndex = index,
                        name = item["name"]?.toString().orEmpty(),
                        url = item["url"]?.toString().orEmpty(),
                        category = item["category"]?.toString() ?: "Tümü",
                        favorite = item["favorite"] as? Boolean ?: false
                    )
                }
                val primaryColor = call.argument<Number>("primaryColor")?.toInt()
                    ?: Color.rgb(33, 150, 243)
                val autoHideMs = call.argument<Number>("autoHideMs")?.toLong() ?: 3000L
                val sidebarOpacity = call.argument<Number>("sidebarOpacity")?.toFloat() ?: 0.1f
                val selectedUrl = call.argument<String>("selectedUrl")
                val profileName = call.argument<String>("profileName") ?: "Misafir"
                overlay?.dispose()
                overlay = NativeLiveTvOverlay(
                    activity = activity,
                    channel = channel,
                    channels = channels,
                    primaryColor = primaryColor,
                    autoHideMs = autoHideMs,
                    sidebarOpacity = sidebarOpacity,
                    selectedUrl = selectedUrl,
                    profileName = profileName,
                    requestAction = { action ->
                        overlay?.setVisible(false)
                        setFlutterVisible(true)
                        channel.invokeMethod("action", mapOf("name" to action))
                    }
                ).also { it.show() }
                setFlutterVisible(false)
                result.success(true)
            }
            "updatePlaying" -> {
                overlay?.updatePlaying(call.argument<String>("url"))
                result.success(true)
            }
            "showFlutter" -> {
                overlay?.setVisible(false)
                setFlutterVisible(true)
                result.success(true)
            }
            "resumeNative" -> {
                overlay?.setVisible(true)
                setFlutterVisible(false)
                result.success(true)
            }
            "hide" -> {
                overlay?.dispose()
                overlay = null
                setFlutterVisible(true)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun setFlutterVisible(visible: Boolean) {
        findFlutterView(activity.findViewById(android.R.id.content))?.visibility =
            if (visible) View.VISIBLE else View.GONE
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    companion object {
        const val CHANNEL = "com.tivuq.iptv/native_live_tv"
    }
}

private data class NativeChannel(
    val originalIndex: Int,
    val name: String,
    val url: String,
    val category: String,
    var favorite: Boolean
)

private enum class NativeRemoteMode { WATCHING, CHANNELS, CATEGORIES, HEADER, FOOTER, TOP_NAV }

private class NativeLiveTvOverlay(
    private val activity: Activity,
    private val channel: MethodChannel,
    private val channels: List<NativeChannel>,
    private val primaryColor: Int,
    private val autoHideMs: Long,
    private val sidebarOpacity: Float,
    selectedUrl: String?,
    private val profileName: String,
    private val requestAction: (String) -> Unit
) {
    private val handler = Handler(Looper.getMainLooper())
    private val root = FrameLayout(activity)
    private val sidebar = LinearLayout(activity)
    private val channelList = ListView(activity)
    private val categoryList = ListView(activity)
    private val categoryStrip = LinearLayout(activity)
    private val search = EditText(activity)
    private val controls = TextView(activity)
    private val channelNumber = TextView(activity)
    private val topNav = LinearLayout(activity)
    private val progress = ProgressBar(activity)
    private var filtered = channels.toList()
    private val categories = listOf("Tümü", "Favoriler") +
        channels.map { it.category }.filter { it != "Tümü" && it != "Favoriler" }.distinct()
    private var selectedCategory = channels.firstOrNull { it.url == selectedUrl }?.category ?: "Tümü"
    private var playingUrl = selectedUrl
    private var focusedChannel = 0
    private var focusedCategory = 0
    private var focusedHeader = 1
    private var topNavIndex = 0
    private var mode = NativeRemoteMode.CHANNELS
    private var numberInput = ""
    private var volume = 80
    private var searchQuery = ""

    private val hideSidebar = Runnable {
        if (mode == NativeRemoteMode.CHANNELS) closeSidebar()
    }
    private val hideControls = Runnable { animateOut(controls, 0f, dp(120).toFloat()) }
    private val submitNumber = Runnable { submitChannelNumber() }

    init {
        root.isFocusable = true
        root.isFocusableInTouchMode = true
        root.setBackgroundColor(Color.TRANSPARENT)
        root.setOnKeyListener { _, keyCode, event ->
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener true
            handleKey(keyCode)
            true
        }
        buildUi()
        applyFilter()
        updatePlaying(selectedUrl)
    }

    fun show() {
        val content = activity.findViewById<FrameLayout>(android.R.id.content)
        content.addView(
            root,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        root.requestFocus()
        resetSidebarTimer()
        showControls()
    }

    fun setVisible(visible: Boolean) {
        root.visibility = if (visible) View.VISIBLE else View.GONE
        if (visible) root.requestFocus()
    }

    fun dispose() {
        handler.removeCallbacksAndMessages(null)
        (root.parent as? ViewGroup)?.removeView(root)
    }

    fun updatePlaying(url: String?) {
        playingUrl = url
        progress.visibility = View.GONE
        channelList.invalidateViews()
        val selected = channels.firstOrNull { it.url == url }
        if (selected != null) {
            controls.text = "${filtered.indexOfFirst { it.url == url }.takeIf { it >= 0 }?.plus(1) ?: selected.originalIndex + 1}. ${selected.name}"
        }
    }

    private fun buildUi() {
        root.addView(
            progress,
            FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER)
        )
        buildSidebar()
        buildControls()
        buildTopNav()
        buildChannelNumber()
    }

    private fun buildSidebar() {
        sidebar.orientation = LinearLayout.VERTICAL
        sidebar.setPadding(dp(12), dp(20), dp(12), 0)
        sidebar.background = solid(Color.argb((255 * sidebarOpacity).toInt().coerceIn(0, 255), 15, 12, 29))

        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(4), dp(8))
        }
        val menu = text("☰", 22f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            setOnClickListener { openCategories() }
        }
        header.addView(menu, LinearLayout.LayoutParams(dp(30), dp(38)))
        search.hint = "Kanal ara"
        search.setHintTextColor(Color.argb(110, 255, 255, 255))
        search.setTextColor(Color.WHITE)
        search.textSize = 13f
        search.isSingleLine = true
        search.setPadding(dp(12), 0, dp(12), 0)
        search.background = rounded(Color.argb(170, 29, 25, 51), dp(19), Color.argb(45, 255, 255, 255), 1)
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                searchQuery = value?.toString().orEmpty()
                applyFilter()
            }
            override fun afterTextChanged(value: Editable?) = Unit
        })
        header.addView(search, LinearLayout.LayoutParams(0, dp(38), 1f).apply {
            marginStart = dp(8)
            marginEnd = dp(8)
        })
        val settings = text("⚙", 21f, Color.LTGRAY, true).apply {
            gravity = Gravity.CENTER
            setOnClickListener { requestFlutterAction("settings") }
        }
        header.addView(settings, LinearLayout.LayoutParams(dp(34), dp(38)))
        sidebar.addView(header, LinearLayout.LayoutParams.MATCH_PARENT, dp(58))

        val categoryScroller = HorizontalScrollView(activity).apply {
            isHorizontalScrollBarEnabled = false
            addView(categoryStrip)
        }
        categoryStrip.orientation = LinearLayout.HORIZONTAL
        sidebar.addView(categoryScroller, LinearLayout.LayoutParams.MATCH_PARENT, dp(42))
        rebuildCategoryStrip()

        channelList.divider = null
        channelList.isVerticalScrollBarEnabled = false
        channelList.adapter = ChannelAdapter()
        channelList.setOnItemClickListener { _, _, position, _ -> playAt(position) }
        channelList.setOnItemLongClickListener { _, _, position, _ ->
            val item = filtered.getOrNull(position) ?: return@setOnItemLongClickListener true
            item.favorite = !item.favorite
            channel.invokeMethod(
                "toggleFavorite",
                mapOf("url" to item.url, "favorite" to item.favorite)
            )
            if (selectedCategory == "Favoriler") applyFilter() else refreshChannels()
            true
        }
        sidebar.addView(channelList, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        categoryList.divider = null
        categoryList.visibility = View.GONE
        categoryList.adapter = CategoryAdapter()
        categoryList.setOnItemClickListener { _, _, position, _ -> selectCategory(position) }
        sidebar.addView(categoryList, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        val footer = text(profileName, 13f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), 0, dp(12), 0)
            background = solid(Color.argb(70, 255, 255, 255))
            setOnClickListener { requestFlutterAction("profiles") }
        }
        sidebar.addView(footer, LinearLayout.LayoutParams.MATCH_PARENT, dp(62))

        root.addView(
            sidebar,
            FrameLayout.LayoutParams(dp(320), FrameLayout.LayoutParams.MATCH_PARENT, Gravity.START)
        )
    }

    private fun buildControls() {
        controls.setTextColor(Color.WHITE)
        controls.textSize = 20f
        controls.typeface = Typeface.DEFAULT_BOLD
        controls.gravity = Gravity.CENTER_VERTICAL
        controls.setPadding(dp(24), 0, dp(24), 0)
        controls.background = rounded(Color.argb(205, 0, 0, 0), dp(16), Color.argb(75, 255, 255, 255), 1)
        root.addView(
            controls,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, dp(68), Gravity.BOTTOM or Gravity.START).apply {
                setMargins(dp(40), 0, 0, dp(40))
            }
        )
    }

    private fun buildTopNav() {
        topNav.orientation = LinearLayout.HORIZONTAL
        topNav.gravity = Gravity.CENTER
        topNav.setPadding(dp(16), dp(8), dp(16), dp(8))
        topNav.background = rounded(Color.argb(225, 19, 16, 34), dp(30), Color.argb(35, 255, 255, 255), 1)
        listOf("Canlı TV", "Filmler", "Diziler").forEachIndexed { index, label ->
            topNav.addView(text(label, 14f, Color.WHITE, true).apply {
                gravity = Gravity.CENTER
                setPadding(dp(18), 0, dp(18), 0)
                setOnClickListener { navigateTop(index) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(38)))
        }
        topNav.translationY = -dp(90).toFloat()
        root.addView(
            topNav,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, dp(54), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                topMargin = dp(16)
            }
        )
        refreshTopNavFocus()
    }

    private fun buildChannelNumber() {
        channelNumber.setTextColor(Color.WHITE)
        channelNumber.textSize = 32f
        channelNumber.typeface = Typeface.DEFAULT_BOLD
        channelNumber.gravity = Gravity.CENTER
        channelNumber.setPadding(dp(24), dp(12), dp(24), dp(12))
        channelNumber.background = rounded(Color.argb(215, 0, 0, 0), dp(12), primaryColor, 1)
        channelNumber.visibility = View.GONE
        root.addView(
            channelNumber,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
        )
    }

    private fun handleKey(keyCode: Int) {
        if (keyCode == KeyEvent.KEYCODE_MENU || keyCode == KeyEvent.KEYCODE_SETTINGS) {
            requestFlutterAction("settings")
            return
        }
        if (keyCode in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 ||
            keyCode in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9
        ) {
            val digit = if (keyCode >= KeyEvent.KEYCODE_NUMPAD_0) {
                keyCode - KeyEvent.KEYCODE_NUMPAD_0
            } else {
                keyCode - KeyEvent.KEYCODE_0
            }
            appendChannelNumber(digit)
            return
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            volume = (volume + 5).coerceAtMost(100)
            channel.invokeMethod("volume", mapOf("value" to volume))
            return
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            volume = (volume - 5).coerceAtLeast(0)
            channel.invokeMethod("volume", mapOf("value" to volume))
            return
        }
        when (mode) {
            NativeRemoteMode.WATCHING -> handleWatching(keyCode)
            NativeRemoteMode.CHANNELS -> handleChannels(keyCode)
            NativeRemoteMode.CATEGORIES -> handleCategories(keyCode)
            NativeRemoteMode.HEADER -> handleHeader(keyCode)
            NativeRemoteMode.FOOTER -> handleFooter(keyCode)
            NativeRemoteMode.TOP_NAV -> handleTopNav(keyCode)
        }
    }

    private fun handleWatching(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_UP -> playRelative(1)
            KeyEvent.KEYCODE_DPAD_DOWN -> playRelative(-1)
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> openSidebar()
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> openTopNav()
        }
    }

    private fun handleChannels(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (focusedChannel < filtered.lastIndex) focusedChannel++ else mode = NativeRemoteMode.FOOTER
                refreshChannels()
            }
            KeyEvent.KEYCODE_DPAD_UP -> {
                if (focusedChannel > 0) focusedChannel-- else mode = NativeRemoteMode.HEADER
                refreshChannels()
            }
            KeyEvent.KEYCODE_DPAD_LEFT -> openCategories()
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> playAt(focusedChannel)
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.KEYCODE_PAGE_DOWN -> switchCategory(1)
            KeyEvent.KEYCODE_MEDIA_REWIND, KeyEvent.KEYCODE_PAGE_UP -> switchCategory(-1)
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> closeSidebar()
        }
        resetSidebarTimer()
    }

    private fun handleCategories(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_DOWN -> focusedCategory = (focusedCategory + 1).coerceAtMost(categories.lastIndex)
            KeyEvent.KEYCODE_DPAD_UP -> focusedCategory = (focusedCategory - 1).coerceAtLeast(0)
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> selectCategory(focusedCategory)
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> closeSidebar()
        }
        categoryList.invalidateViews()
        categoryList.setSelection(focusedCategory)
    }

    private fun handleHeader(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_LEFT -> focusedHeader = 0
            KeyEvent.KEYCODE_DPAD_RIGHT -> focusedHeader = 1
            KeyEvent.KEYCODE_DPAD_DOWN -> mode = NativeRemoteMode.CHANNELS
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                if (focusedHeader == 1) requestFlutterAction("settings") else search.requestFocus()
            }
            KeyEvent.KEYCODE_BACK -> closeSidebar()
        }
    }

    private fun handleFooter(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_UP -> {
                mode = NativeRemoteMode.CHANNELS
                focusedChannel = filtered.lastIndex.coerceAtLeast(0)
                refreshChannels()
            }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> requestFlutterAction("profiles")
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_DPAD_LEFT -> closeSidebar()
        }
    }

    private fun handleTopNav(key: Int) {
        when (key) {
            KeyEvent.KEYCODE_DPAD_LEFT -> topNavIndex = (topNavIndex - 1).coerceAtLeast(0)
            KeyEvent.KEYCODE_DPAD_RIGHT -> topNavIndex = (topNavIndex + 1).coerceAtMost(2)
            KeyEvent.KEYCODE_DPAD_DOWN -> closeTopNav()
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> navigateTop(topNavIndex)
            KeyEvent.KEYCODE_BACK -> requestFlutterAction("exit")
        }
        refreshTopNavFocus()
    }

    private fun playRelative(delta: Int) {
        if (filtered.isEmpty()) return
        var index = filtered.indexOfFirst { it.url == playingUrl }
        if (index < 0) index = 0
        index = (index + delta + filtered.size) % filtered.size
        playAt(index)
    }

    private fun playAt(position: Int) {
        val selected = filtered.getOrNull(position) ?: return
        focusedChannel = position
        playingUrl = selected.url
        progress.visibility = View.VISIBLE
        channel.invokeMethod(
            "changeChannel",
            mapOf("url" to selected.url, "originalIndex" to selected.originalIndex)
        )
        controls.text = "${position + 1}. ${selected.name}"
        refreshChannels()
        showControls()
    }

    private fun applyFilter() {
        filtered = channels.filter {
            val matchesSearch = searchQuery.isEmpty() ||
                it.name.lowercase(Locale.getDefault()).contains(searchQuery.lowercase(Locale.getDefault()))
            val matchesCategory = if (searchQuery.isNotEmpty()) {
                true
            } else {
                selectedCategory == "Tümü" ||
                    (selectedCategory == "Favoriler" && it.favorite) ||
                    it.category == selectedCategory
            }
            matchesSearch && matchesCategory
        }
        focusedChannel = filtered.indexOfFirst { it.url == playingUrl }.coerceAtLeast(0)
        refreshChannels()
    }

    private fun selectCategory(position: Int) {
        selectedCategory = categories.getOrNull(position) ?: return
        focusedCategory = position
        applyFilter()
        rebuildCategoryStrip()
        categoryList.visibility = View.GONE
        channelList.visibility = View.VISIBLE
        mode = NativeRemoteMode.CHANNELS
    }

    private fun switchCategory(delta: Int) {
        var index = categories.indexOf(selectedCategory).coerceAtLeast(0)
        index = (index + delta + categories.size) % categories.size
        selectCategory(index)
    }

    private fun openSidebar() {
        mode = NativeRemoteMode.CHANNELS
        sidebar.animate().translationX(0f).setDuration(300).start()
        resetSidebarTimer()
        refreshChannels()
    }

    private fun closeSidebar() {
        mode = NativeRemoteMode.WATCHING
        handler.removeCallbacks(hideSidebar)
        sidebar.animate().translationX(-dp(320).toFloat()).setDuration(300).start()
    }

    private fun openCategories() {
        mode = NativeRemoteMode.CATEGORIES
        focusedCategory = categories.indexOf(selectedCategory).coerceAtLeast(0)
        channelList.visibility = View.GONE
        categoryList.visibility = View.VISIBLE
        categoryList.invalidateViews()
    }

    private fun openTopNav() {
        mode = NativeRemoteMode.TOP_NAV
        topNavIndex = 0
        topNav.animate().translationY(0f).setDuration(250).start()
        refreshTopNavFocus()
    }

    private fun closeTopNav() {
        mode = NativeRemoteMode.WATCHING
        topNav.animate().translationY(-dp(90).toFloat()).setDuration(250).start()
    }

    private fun navigateTop(index: Int) {
        if (index == 0) {
            closeTopNav()
        } else {
            requestFlutterAction(if (index == 1) "movies" else "series")
        }
    }

    private fun appendChannelNumber(digit: Int) {
        if (numberInput.length >= 4) return
        numberInput += digit.toString()
        channelNumber.text = numberInput
        channelNumber.visibility = View.VISIBLE
        handler.removeCallbacks(submitNumber)
        handler.postDelayed(submitNumber, 3000)
    }

    private fun submitChannelNumber() {
        val index = (numberInput.toIntOrNull() ?: 0) - 1
        numberInput = ""
        channelNumber.visibility = View.GONE
        playAt(index)
    }

    private fun requestFlutterAction(action: String) {
        requestAction(action)
    }

    private fun showControls() {
        controls.visibility = View.VISIBLE
        controls.animate().translationY(0f).alpha(1f).setDuration(200).start()
        handler.removeCallbacks(hideControls)
        if (autoHideMs > 0) handler.postDelayed(hideControls, autoHideMs)
    }

    private fun resetSidebarTimer() {
        handler.removeCallbacks(hideSidebar)
        if (autoHideMs > 0) handler.postDelayed(hideSidebar, autoHideMs)
    }

    private fun refreshChannels() {
        (channelList.adapter as? ChannelAdapter)?.notifyDataSetChanged()
        if (focusedChannel >= 0) {
            channelList.post {
                val centeredTop = ((channelList.height - dp(56)) / 2).coerceAtLeast(0)
                channelList.setSelectionFromTop(focusedChannel, centeredTop)
            }
        }
    }

    private fun rebuildCategoryStrip() {
        categoryStrip.removeAllViews()
        categories.forEachIndexed { index, category ->
            val selected = category == selectedCategory
            categoryStrip.addView(text(category, 12f, Color.WHITE, selected).apply {
                gravity = Gravity.CENTER
                setPadding(dp(14), 0, dp(14), 0)
                background = rounded(
                    if (selected) primaryColor else Color.argb(25, 255, 255, 255),
                    dp(17),
                    if (selected) primaryColor else Color.argb(35, 255, 255, 255),
                    1
                )
                setOnClickListener { selectCategory(index) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply {
                marginEnd = dp(6)
            })
        }
    }

    private fun refreshTopNavFocus() {
        for (index in 0 until topNav.childCount) {
            val view = topNav.getChildAt(index) as TextView
            view.background = if (index == topNavIndex) {
                rounded(Color.argb(55, 255, 255, 255), dp(20), Color.WHITE, 2)
            } else null
        }
    }

    private inner class ChannelAdapter : ArrayAdapter<NativeChannel>(activity, android.R.layout.simple_list_item_1, filtered) {
        override fun getCount(): Int = filtered.size
        override fun getItem(position: Int): NativeChannel? = filtered.getOrNull(position)

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val row = (convertView as? TextView) ?: text("", 14f, Color.WHITE, false).apply {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(14), 0, dp(12), 0)
            }
            val item = filtered[position]
            val focused = mode == NativeRemoteMode.CHANNELS && position == focusedChannel
            val playing = item.url == playingUrl
            row.text = "${position + 1}    ${item.name}${if (item.favorite) "   ♥" else ""}"
            row.setTextColor(if (focused || playing) Color.WHITE else Color.rgb(205, 205, 210))
            row.typeface = if (focused || playing) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            row.background = rounded(
                when {
                    focused -> Color.argb(35, 255, 255, 255)
                    playing -> withAlpha(primaryColor, 45)
                    else -> Color.argb((128 * sidebarOpacity).toInt().coerceIn(0, 255), 30, 25, 51)
                },
                dp(8),
                if (focused) Color.WHITE else if (playing) withAlpha(primaryColor, 145) else Color.TRANSPARENT,
                if (focused) 2 else 1
            )
            row.layoutParams = android.widget.AbsListView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56))
            return row
        }
    }

    private inner class CategoryAdapter : ArrayAdapter<String>(activity, android.R.layout.simple_list_item_1, categories) {
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val row = (convertView as? TextView) ?: text("", 14f, Color.WHITE, false).apply {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), 0, dp(16), 0)
            }
            val selected = categories[position] == selectedCategory
            val focused = position == focusedCategory
            row.text = categories[position] + if (selected) "   ✓" else ""
            row.typeface = if (selected || focused) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            row.background = rounded(
                if (selected) withAlpha(primaryColor, 45) else if (focused) Color.argb(35, 255, 255, 255) else Color.TRANSPARENT,
                dp(12),
                if (focused) Color.WHITE else Color.TRANSPARENT,
                if (focused) 2 else 1
            )
            row.layoutParams = android.widget.AbsListView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52))
            return row
        }
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean) = TextView(activity).apply {
        text = value
        textSize = size
        setTextColor(color)
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        maxLines = 1
    }

    private fun solid(color: Int) = GradientDrawable().apply { setColor(color) }

    private fun rounded(color: Int, radius: Int, strokeColor: Int, strokeWidth: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
        if (strokeColor != Color.TRANSPARENT) setStroke(dp(strokeWidth), strokeColor)
    }

    private fun withAlpha(color: Int, alpha: Int): Int = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()

    private fun animateOut(view: View, x: Float, y: Float) {
        view.animate().translationX(x).translationY(y).alpha(0f).setDuration(200).withEndAction {
            view.visibility = View.GONE
        }.start()
    }
}

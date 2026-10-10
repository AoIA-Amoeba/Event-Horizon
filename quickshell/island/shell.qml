import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtCore
import QtQuick.Controls

ShellRoot {
    id: root

    IpcHandler {
        target: "island"
        function toggleMute(): void { win.keyboardMute() }
        function volumeDown(): void { win.keyboardVolume(-0.05) }
        function volumeUp(): void { win.keyboardVolume(0.05) }
        function openLauncher(): void { win.toggleLauncher() }
        function toggleNotifications(): void { win.showLastNotification() }
    }

    NotificationServer {
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        onNotification: notification => win.presentNotification(notification)
    }

    PanelWindow {
        id: win

        readonly property int pillHeight: 32
        readonly property color surface: Qt.rgba(30 / 255, 30 / 255, 46 / 255, 0.68)
        readonly property color raised: Qt.rgba(49 / 255, 50 / 255, 68 / 255, 0.58)
        readonly property color foreground: "#cdd6f4"
        readonly property color muted: "#a6adc8"
        readonly property color accent: "#89b4fa"

        anchors.top: true
        anchors.left: true
        anchors.right: true
        margins.top: 5
        WlrLayershell.layer: WlrLayer.Overlay
        implicitHeight: notificationVisible ? 124
            : expanded ? (page === "Launcher" ? 442 : page === "Wi-Fi" ? 390 : page === "Weather" ? 306 : 250) : pillHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: island }
        WlrLayershell.keyboardFocus: expanded && (page === "Timer" || page === "Launcher")
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        property bool expanded: false
        property string page: "Music"
        property string launcherQuery: ""
        property var launcherHistory: []
        readonly property var launcherApplications: Array.from(DesktopEntries.applications.values)
            .filter(entry => !entry.noDisplay)
        readonly property var launcherResults: {
            const query = launcherQuery.trim().toLowerCase()
            const apps = launcherApplications.filter(entry => !query
                || (entry.name ?? "").toLowerCase().includes(query)
                || (entry.genericName ?? "").toLowerCase().includes(query)
                || (entry.comment ?? "").toLowerCase().includes(query)
                || (entry.keywords ?? []).join(" ").toLowerCase().includes(query))
            return apps.sort((a, b) => {
                const ai = launcherHistory.indexOf(a.id)
                const bi = launcherHistory.indexOf(b.id)
                if (ai >= 0 || bi >= 0) {
                    if (ai < 0) return 1
                    if (bi < 0) return -1
                    if (ai !== bi) return ai - bi
                }
                return a.name.localeCompare(b.name)
            })
        }
        readonly property var battery: UPower.displayDevice
        property bool lowBatteryProfileActive: false
        property bool profileCheckPending: false
        property bool profileCheckForRestore: false
        property string previousPowerProfile: ""
        property string requestedPowerProfile: ""
        property bool cameraInUse: false
        property bool screenRecording: false
        property string recordingOutputPath: ""
        readonly property string videosDirectory: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
            || (Quickshell.env("HOME") + "/Videos")
        property string recordingStatus: "Ready to record your screen"
        property bool countdownRunning: false
        property bool countdownPaused: false
        property string countdownInput: "5m"
        property int countdownHours: 0
        property int countdownMinutes: 5
        property int countdownSeconds: 0
        property string countdownLabel: "Tea"
        property string countdownStatus: "Enter a duration, like 25m or 1:30"
        property real countdownDuration: 0
        property real countdownEndsAt: 0
        property real countdownRemaining: 0
        property date currentTime: new Date()
        property var activeNotification: null
        property string notificationSummary: ""
        property string notificationBody: ""
        property string notificationApp: ""
        property string notificationIcon: ""
        property bool notificationVisible: false
        property int notificationBurstCount: 0
        property int notificationTimeout: 6500
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource
        PwObjectTracker {
            objects: [win.sink, win.source].concat(Pipewire.nodes.values, Pipewire.links.values)
        }
        property var player: {
            const players = Mpris.players.values
            return players.find(p => p.isPlaying)
                ?? players.find(p => (p.trackTitle ?? "") !== "" && p.canControl)
                ?? players.find(p => p.canControl)
                ?? null
        }
        readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property var wifiNetworks: wifiDevice && wifiDevice.networks
            ? wifiDevice.networks.values.slice().sort((a, b) => Number(b.connected) - Number(a.connected) || b.signalStrength - a.signalStrength)
            : []
        readonly property var ethernetDevice: Networking.devices.values.find(d => d.type === DeviceType.Ethernet) ?? null
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property var connectedBluetooth: adapter && adapter.devices
            ? adapter.devices.values.filter(d => d.connected) : []
        property real weatherLatitude: NaN
        property real weatherLongitude: NaN
        property real weatherTemperature: 0
        property real weatherFeelsLike: 0
        property int weatherCode: -1
        property string weatherPlace: ""
        property var weatherForecast: []
        readonly property string networkName: {
            if (ethernetDevice && ethernetDevice.connected) return "Ethernet"
            if (wifiDevice && wifiDevice.connected && wifiDevice.networks) {
                const active = wifiDevice.networks.values.find(n => n.connected)
                if (active) return active.name
            }
            return wifiRadioOn ? "Not connected" : "Wi-Fi off"
        }
        property bool wifiRadioOn: false
        property real cpuUsage: 0
        property real memoryUsed: 0
        property real memoryTotal: 0
        property real previousCpuTotal: -1
        property real previousCpuIdle: 0
        property var cpuHistory: []
        property var memoryHistory: []
        function queryWifiRadio() {
            wifiQuery.running = true
        }

        function weatherText(code) {
            if (code === 0) return "Clear sky"
            if (code === 1 || code === 2) return "Partly cloudy"
            if (code === 3) return "Overcast"
            if (code === 45 || code === 48) return "Fog"
            if (code >= 51 && code <= 57) return "Drizzle"
            if (code >= 61 && code <= 67) return "Rain"
            if (code >= 71 && code <= 77) return "Snow"
            if (code >= 80 && code <= 82) return "Showers"
            if (code >= 85 && code <= 86) return "Snow showers"
            if (code >= 95) return "Thunderstorm"
            return "Weather"
        }

        function weatherIcon(code) {
            if (code === 0) return "☀"
            if (code === 1 || code === 2) return "⛅"
            if (code === 3) return "☁"
            if (code === 45 || code === 48) return "≋"
            if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "☂"
            if (code >= 71 && code <= 86) return "❄"
            if (code >= 95) return "ϟ"
            return "☁"
        }

        function requestWeather() {
            weatherGeo.command = ["curl", "--fail", "--silent", "--show-error",
                "https://ipwho.is/?fields=success,city,region,country,latitude,longitude"]
            weatherGeo.running = true
        }

        function batteryEta() {
            if (!battery || !battery.ready) return ""
            const charging = battery.state === UPowerDeviceState.Charging
                || battery.state === UPowerDeviceState.PendingCharge
            const seconds = charging ? battery.timeToFull : battery.timeToEmpty
            if (!seconds || seconds <= 0) return ""
            const minutes = Math.round(seconds / 60)
            const hours = Math.floor(minutes / 60)
            const remainingMinutes = minutes % 60
            return hours > 0 ? `${hours}h ${remainingMinutes}m` : `${remainingMinutes}m`
        }

        function batteryLowMode() {
            return battery && battery.ready && battery.isLaptopBattery
                && battery.state === UPowerDeviceState.Discharging
                && battery.percentage <= 0.20
        }

        function batteryColor() {
            if (!battery || !battery.ready || !battery.isLaptopBattery) return "#ffffff"
            if (battery.state === UPowerDeviceState.Charging
                    || battery.state === UPowerDeviceState.PendingCharge
                    || battery.state === UPowerDeviceState.FullyCharged) return "#a6e3a1"
            if (battery.percentage <= 0.10) return "#f38ba8"
            if (batteryLowMode()) return "#f9e2af"
            return "#ffffff"
        }

        function batteryPowerDirection() {
            if (!battery || !battery.ready) return ""
            if (battery.state === UPowerDeviceState.Charging
                    || battery.state === UPowerDeviceState.PendingCharge) return "going in"
            if (battery.state === UPowerDeviceState.Discharging) return "coming out"
            if (battery.state === UPowerDeviceState.FullyCharged) return "full"
            return "idle"
        }

        function detectCameraInUse() {
            if (!Pipewire.ready) return false
            const nodes = Pipewire.nodes.values
            const links = Pipewire.links.values
            return nodes.some(node => {
                if (!node || !node.ready || !(node.type & PwNodeType.VideoSource)) return false
                return links.some(link => link && link.source === node
                    && link.state === PwLinkState.Active
                    && link.target && link.target.isStream)
            })
        }

        function syncLowBatteryProfile() {
            if (profileCheckPending) return
            if (batteryLowMode() && !lowBatteryProfileActive) {
                profileCheckForRestore = false
                profileCheckPending = true
                profileQuery.running = true
            } else if (!batteryLowMode() && lowBatteryProfileActive) {
                profileCheckForRestore = true
                profileCheckPending = true
                profileQuery.running = true
            }
        }

        function setPowerProfile(profile) {
            requestedPowerProfile = profile
            profileSet.command = ["powerprofilesctl", "set", profile]
            profileSet.running = true
        }

        function toggleScreenRecording() {
            if (screenRecording) {
                screenRecorder.signal(2)
                return
            }
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss")
            recordingOutputPath = videosDirectory + "/Screen Recording " + stamp + ".mp4"
            recordingStatus = "Starting screen recording…"
            screenRecorder.command = ["wf-recorder", "-f", recordingOutputPath]
            screenRecorder.running = true
        }

        function parseCountdown(text) {
            const clean = (text ?? "").trim().toLowerCase()
            if (!clean) return 0
            const clock = clean.match(/^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$/)
            if (clock) {
                const seconds = clock[3] !== undefined
                    ? Number(clock[1]) * 3600 + Number(clock[2]) * 60 + Number(clock[3])
                    : Number(clock[1]) * 60 + Number(clock[2])
                return seconds * 1000
            }
            if (/^\d+(?:\.\d+)?$/.test(clean)) return Number(clean) * 60000
            if (!/^\d+(?:\.\d+)?\s*[hms]?(?:\s*\d+(?:\.\d+)?\s*[hms]?)*$/.test(clean)) return 0
            const units = { h: 3600, m: 60, s: 1 }
            const pattern = /(\d+(?:\.\d+)?)\s*(h|m|s)?/g
            let total = 0
            let lastUnit = null
            let match
            while ((match = pattern.exec(clean)) !== null) {
                const unit = match[2] || (lastUnit === "h" ? "m" : (lastUnit === "m" ? "s" : "m"))
                total += Number(match[1]) * units[unit]
                lastUnit = unit
            }
            return Math.round(total * 1000)
        }

        function startCountdown() {
            const duration = countdownPending()
            if (duration <= 0) {
                countdownStatus = "Choose a duration first"
                return
            }
            countdownDuration = duration
            countdownRemaining = duration
            countdownEndsAt = Date.now() + duration
            countdownPaused = false
            countdownRunning = true
            countdownStatus = "Countdown running"
        }

        function toggleCountdown() {
            if (!countdownRunning) return
            if (countdownPaused) {
                countdownEndsAt = Date.now() + countdownRemaining
                countdownPaused = false
                countdownStatus = "Countdown running"
            } else {
                countdownRemaining = Math.max(0, countdownEndsAt - Date.now())
                countdownPaused = true
                countdownStatus = "Countdown paused"
            }
        }

        function restartCountdown() {
            if (countdownDuration <= 0) return
            countdownRemaining = countdownDuration
            countdownEndsAt = Date.now() + countdownDuration
            countdownPaused = false
            countdownRunning = true
            countdownStatus = "Countdown running"
        }

        function stopCountdown() {
            countdownRunning = false
            countdownPaused = false
            countdownRemaining = 0
            countdownStatus = "Countdown stopped"
        }

        function countdownText() {
            const total = Math.max(0, Math.ceil(countdownRemaining / 1000))
            const hours = Math.floor(total / 3600)
            const minutes = Math.floor((total % 3600) / 60)
            const seconds = total % 60
            const pad = value => value < 10 ? `0${value}` : `${value}`
            return hours > 0 ? `${hours}:${pad(minutes)}:${pad(seconds)}` : `${minutes}:${pad(seconds)}`
        }

        function countdownPreview() {
            const pad = value => value < 10 ? `0${value}` : `${value}`
            return countdownHours > 0
                ? `${countdownHours}:${pad(countdownMinutes)}:${pad(countdownSeconds)}`
                : `${countdownMinutes}:${pad(countdownSeconds)}`
        }

        function countdownPending() {
            return (countdownHours * 3600 + countdownMinutes * 60 + countdownSeconds) * 1000
        }

        function countdownEndTime() {
            return Qt.formatTime(new Date(countdownEndsAt), "HH:mm")
        }

        function adjustCountdown(unit, delta) {
            if (unit === "h") countdownHours = Math.max(0, Math.min(23, countdownHours + delta))
            else if (unit === "m") countdownMinutes = Math.max(0, Math.min(59, countdownMinutes + delta))
            else countdownSeconds = Math.max(0, Math.min(59, countdownSeconds + delta))
        }

        function launchIslandApp(entry) {
            if (!entry) return
            Quickshell.execDetached(["gtk-launch", entry.id])
            const next = launcherHistory.filter(id => id !== entry.id)
            next.unshift(entry.id)
            launcherHistory = next.slice(0, 12)
            launcherQuery = ""
            page = "Music"
            expanded = false
        }

        function closeLauncher() {
            launcherQuery = ""
            page = "Music"
            expanded = false
        }

        function presentNotification(notification) {
            if (!notification) return
            if (activeNotification && activeNotification !== notification)
                activeNotification.expire()
            if (notificationVisible)
                notificationBurstCount += 1
            else
                notificationBurstCount = 1
            notification.tracked = true
            activeNotification = notification
            notificationSummary = notification.summary || "Notification"
            notificationBody = notification.body || ""
            notificationApp = notification.appName || notification.desktopEntry || ""
            notificationIcon = notification.appIcon || notification.desktopEntry || ""
            notificationVisible = true
            notificationTimeout = notification.expireTimeout > 0
                ? Math.min(notification.expireTimeout, 12000) : 6500
            notificationTimer.restart()
        }

        function showLastNotification() {
            if (notificationSummary === "") return
            notificationVisible = true
            notificationTimeout = 6500
            notificationTimer.restart()
        }

        function dismissNotification() {
            notificationTimer.stop()
            if (activeNotification)
                activeNotification.dismiss()
            activeNotification = null
            notificationVisible = false
            notificationBurstCount = 0
        }

        Connections {
            target: win.activeNotification
            function onClosed(reason) {
                notificationTimer.stop()
                win.activeNotification = null
                win.notificationVisible = false
                win.notificationBurstCount = 0
            }
        }

        function toggleLauncher() {
            if (expanded && page === "Launcher") {
                closeLauncher()
                return
            }
            launcherQuery = ""
            page = "Launcher"
            expanded = true
            Qt.callLater(() => launcherSearch.forceActiveFocus())
        }

        onPageChanged: if (page === "Launcher" && expanded)
            Qt.callLater(() => launcherSearch.forceActiveFocus())
        onExpandedChanged: if (expanded && page === "Launcher")
            Qt.callLater(() => launcherSearch.forceActiveFocus())

        function toggleOutputMute() {
            if (!sink || !sink.ready) return
            sink.audio.muted = !sink.audio.muted
        }

        function toggleMicrophoneMute() {
            if (!source || !source.ready) return
            source.audio.muted = !source.audio.muted
        }

        function showVolumePeek() {
            page = "Volume"
            expanded = true
            closeTimer.stop()
            volumePeekTimer.restart()
        }

        function keyboardMute() {
            if (!sink || !sink.ready) return
            sink.audio.muted = !sink.audio.muted
            showVolumePeek()
        }

        function keyboardVolume(delta) {
            if (!sink || !sink.ready) return
            if (sink.audio.muted) sink.audio.muted = false
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta))
            showVolumePeek()
        }

        function fetchWeather() {
            if (!Number.isFinite(weatherLatitude) || !Number.isFinite(weatherLongitude)) {
                requestWeather()
                return
            }
            weatherFetch.command = ["curl", "--fail", "--silent", "--show-error",
                "https://api.open-meteo.com/v1/forecast?latitude=" + weatherLatitude
                + "&longitude=" + weatherLongitude
                + "&current=temperature_2m,apparent_temperature,weather_code"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=5&timezone=auto"]
            weatherFetch.running = true
        }

        Process {
            id: wifiQuery
            command: ["nmcli", "-t", "-f", "WIFI", "radio", "all"]
            stdout: StdioCollector {
                onStreamFinished: win.wifiRadioOn = text.trim() === "enabled"
            }
            onExited: exitCode => {
                if (exitCode === 0) wifiPoll.restart()
            }
        }

        Process {
            id: wifiToggle
            onExited: win.queryWifiRadio()
        }

        Process {
            id: profileQuery
            command: ["powerprofilesctl", "get"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const current = text.trim()
                    if (!current) {
                        win.profileCheckPending = false
                        return
                    }
                    if (win.profileCheckForRestore) {
                        if (current === "power-saver" && win.previousPowerProfile) {
                            win.setPowerProfile(win.previousPowerProfile)
                        } else {
                            win.lowBatteryProfileActive = false
                            win.previousPowerProfile = ""
                            win.profileCheckPending = false
                        }
                    } else if (win.batteryLowMode() && current !== "power-saver") {
                        win.previousPowerProfile = current
                        win.setPowerProfile("power-saver")
                    } else {
                        win.profileCheckPending = false
                    }
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0) win.profileCheckPending = false
            }
        }

        Process {
            id: profileSet
            onExited: exitCode => {
                win.profileCheckPending = false
                if (exitCode !== 0) return
                if (win.requestedPowerProfile === "power-saver") {
                    win.lowBatteryProfileActive = true
                } else {
                    win.lowBatteryProfileActive = false
                    win.previousPowerProfile = ""
                }
                win.syncLowBatteryProfile()
            }
        }

        Process {
            id: screenRecorder
            onStarted: {
                win.screenRecording = true
                win.recordingStatus = "Recording screen · " + win.recordingOutputPath.split("/").pop()
            }
            onExited: exitCode => {
                win.screenRecording = false
                win.recordingStatus = exitCode === 0 || exitCode === 130
                    ? "Saved · " + win.recordingOutputPath.split("/").pop()
                    : "Recorder stopped with an error"
            }
        }

        Connections {
            target: win.battery
            function onPercentageChanged() { win.syncLowBatteryProfile() }
            function onStateChanged() { win.syncLowBatteryProfile() }
            function onReadyChanged() { win.syncLowBatteryProfile() }
        }

        Process {
            id: weatherGeo
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const place = JSON.parse(text)
                        if (place.error || !Number.isFinite(Number(place.latitude)) || !Number.isFinite(Number(place.longitude))) return
                        win.weatherLatitude = Number(place.latitude)
                        win.weatherLongitude = Number(place.longitude)
                        win.weatherPlace = place.city || place.region || place.country_name || "Current location"
                        win.fetchWeather()
                    } catch (error) {
                        console.warn("Weather location lookup failed:", error)
                    }
                }
            }
        }

        Process {
            id: weatherFetch
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text)
                        win.weatherTemperature = result.current.temperature_2m
                        win.weatherFeelsLike = result.current.apparent_temperature
                        win.weatherCode = result.current.weather_code
                        win.weatherForecast = result.daily.time.map((day, i) => ({
                            date: day,
                            code: result.daily.weather_code[i],
                            high: result.daily.temperature_2m_max[i],
                            low: result.daily.temperature_2m_min[i]
                        }))
                    } catch (error) {
                        console.warn("Weather forecast update failed:", error)
                    }
                }
            }
        }

        Process {
            id: systemStats
            command: ["sh", "-c", "awk '/^cpu / {idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; print total, idle} /^MemTotal:/ {total=$2} /^MemAvailable:/ {available=$2} END {print total, available}' /proc/stat /proc/meminfo"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.trim().split("\n")
                    if (lines.length < 2) return
                    const cpu = lines[0].trim().split(/\s+/).map(Number)
                    const mem = lines[1].trim().split(/\s+/).map(Number)
                    if (cpu.length >= 2 && mem.length >= 2) {
                        if (win.previousCpuTotal >= 0) {
                            const totalDelta = cpu[0] - win.previousCpuTotal
                            const idleDelta = cpu[1] - win.previousCpuIdle
                            if (totalDelta > 0) {
                                win.cpuUsage = Math.round(100 * (1 - idleDelta / totalDelta))
                                win.cpuHistory = win.cpuHistory.concat([win.cpuUsage]).slice(-48)
                            }
                        }
                        win.previousCpuTotal = cpu[0]
                        win.previousCpuIdle = cpu[1]
                        win.memoryTotal = mem[0] / 1024 / 1024
                        win.memoryUsed = (mem[0] - mem[1]) / 1024 / 1024
                        if (mem[0] > 0)
                            win.memoryHistory = win.memoryHistory.concat([(mem[0] - mem[1]) / mem[0] * 100]).slice(-48)
                    }
                }
            }
        }

        Timer {
            id: wifiPoll
            interval: 5000
            onTriggered: win.queryWifiRadio()
        }

        Timer {
            id: closeTimer
            interval: 220
            onTriggered: win.expanded = false
        }

        Timer {
            id: volumePeekTimer
            interval: 1800
            onTriggered: if (!islandHover.hovered) win.expanded = false
        }

        Timer {
            id: countdownTicker
            interval: 250
            repeat: true
            running: win.countdownRunning && !win.countdownPaused
            onTriggered: {
                win.countdownRemaining = win.countdownEndsAt - Date.now()
                if (win.countdownRemaining <= 0) {
                    win.countdownRemaining = 0
                    win.countdownRunning = false
                    win.countdownPaused = false
                    win.countdownStatus = "Countdown finished"
                    countdownAlert.running = true
                }
            }
        }

        Timer {
            id: notificationTimer
            interval: win.notificationTimeout
            onTriggered: {
                if (win.activeNotification)
                    win.activeNotification.expire()
                win.activeNotification = null
                win.notificationVisible = false
                win.notificationBurstCount = 0
            }
        }

        Timer {
            interval: 1000
            repeat: true
            running: true
            onTriggered: win.currentTime = new Date()
        }

        Process {
            id: countdownAlert
            command: ["notify-send", "-u", "critical", "Timer finished", "Your countdown has ended."]
        }

        Timer {
            interval: 2000
            repeat: true
            running: true
            onTriggered: systemStats.running = true
        }

        Timer {
            interval: 15000
            repeat: true
            running: true
            onTriggered: win.syncLowBatteryProfile()
        }

        Timer {
            interval: 500
            repeat: true
            running: true
            onTriggered: win.cameraInUse = win.detectCameraInUse()
        }

        Timer {
            interval: 30 * 60 * 1000
            repeat: true
            running: true
            onTriggered: win.fetchWeather()
        }

        Timer {
            interval: 6 * 60 * 60 * 1000
            repeat: true
            running: true
            onTriggered: win.requestWeather()
        }

        Component.onCompleted: {
            queryWifiRadio()
            systemStats.running = true
            requestWeather()
            syncLowBatteryProfile()
            cameraInUse = detectCameraInUse()
        }

        TextMetrics {
            id: titleMetrics
            font.family: "JetBrainsMono Nerd Font"
            font.bold: true
            font.pixelSize: 13
            text: win.countdownRunning ? win.countdownText() : Qt.formatTime(win.currentTime, "HH:mm")
        }

        Rectangle {
            id: island
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: win.notificationVisible ? 430 : win.expanded ? 430 : Math.min(Math.max(titleMetrics.width + 30, 112), 560)
            height: win.notificationVisible ? 112 : win.expanded ? (win.page === "Launcher" ? 430 : win.page === "Wi-Fi" ? 378 : win.page === "Weather" ? 294 : 238) : win.pillHeight
            radius: win.notificationVisible || win.expanded ? 18 : 11
            color: win.surface
            border.width: 1
            border.color: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.18)
            clip: true

            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
            Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
            Behavior on radius { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }

            HoverHandler {
                id: islandHover
                onHoveredChanged: {
                    if (hovered) {
                        closeTimer.stop()
                        volumePeekTimer.stop()
                        win.expanded = true
                    } else {
                        closeTimer.restart()
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: win.pillHeight
                anchors.leftMargin: 14
                anchors.rightMargin: win.screenRecording
                    ? (win.cameraInUse ? 120 : 96)
                    : (win.cameraInUse ? 38 : 14)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: win.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.bold: true
                font.pixelSize: 13
                opacity: win.expanded ? 0.65 : 1
                visible: !win.notificationVisible && !(win.expanded && win.page === "Launcher")
                text: win.countdownRunning ? win.countdownText() : Qt.formatTime(win.currentTime, "HH:mm")
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            Row {
                id: notificationToast
                anchors.centerIn: parent
                width: parent.width - 34
                height: 76
                spacing: 12
                visible: win.notificationVisible

                Item {
                    width: 42
                    height: 42
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: win.raised
                    }
                    Image {
                        id: notificationAppImage
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        source: {
                            const icon = win.notificationIcon
                            if (!icon) return ""
                            if (icon.startsWith("/")) return `file://${icon}`
                            if (icon.includes("://")) return icon
                            return Quickshell.iconPath(icon, true)
                        }
                        sourceSize.width: 52
                        sourceSize.height: 52
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: notificationAppImage.status !== Image.Ready
                        text: "●"
                        color: win.accent
                        font.pixelSize: 19
                    }
                }

                Column {
                    width: parent.width - 42 - 28 - 24
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: win.notificationSummary
                        color: win.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.bold: true
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: win.notificationApp
                            + (win.notificationBurstCount > 1 ? ` · +${win.notificationBurstCount - 1} more` : "")
                        color: win.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: win.notificationBody
                        color: win.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                    }
                }

                Rectangle {
                    width: 28
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 9
                    color: win.raised
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: win.muted
                        font.pixelSize: 16
                    }
                    TapHandler { onTapped: win.dismissNotification() }
                }
            }

            Item {
                id: cameraIndicator
                width: 18
                height: 18
                anchors.right: parent.right
                anchors.rightMargin: win.screenRecording ? 96 : 14
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: win.pillHeight / 2
                visible: !win.notificationVisible && win.cameraInUse && !(win.expanded && win.page === "Launcher")

                Rectangle {
                    id: cameraPulse
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: "#f38ba8"
                    SequentialAnimation {
                        running: cameraIndicator.visible
                        loops: Animation.Infinite
                        NumberAnimation { target: cameraPulse; property: "scale"; from: 0.8; to: 1.8; duration: 850; easing.type: Easing.InOutSine }
                        NumberAnimation { target: cameraPulse; property: "scale"; from: 1.8; to: 0.8; duration: 850; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation {
                        running: cameraIndicator.visible
                        loops: Animation.Infinite
                        NumberAnimation { target: cameraPulse; property: "opacity"; from: 0.9; to: 0.1; duration: 850; easing.type: Easing.InOutSine }
                        NumberAnimation { target: cameraPulse; property: "opacity"; from: 0.1; to: 0.9; duration: 850; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uf030"
                    color: "#f38ba8"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }

            Item {
                id: recordingIndicator
                width: 84
                height: 20
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: win.pillHeight / 2
                visible: !win.notificationVisible && win.screenRecording && !(win.expanded && win.page === "Launcher")

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Item {
                        width: 9
                        height: 9
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            id: recordingDot
                            anchors.centerIn: parent
                            width: 7
                            height: 7
                            radius: 4
                            color: "#f38ba8"
                            SequentialAnimation {
                                running: recordingIndicator.visible
                                loops: Animation.Infinite
                                NumberAnimation { target: recordingDot; property: "scale"; from: 0.9; to: 1.25; duration: 750; easing.type: Easing.InOutSine }
                                NumberAnimation { target: recordingDot; property: "scale"; from: 1.25; to: 0.9; duration: 750; easing.type: Easing.InOutSine }
                            }
                            SequentialAnimation {
                                running: recordingIndicator.visible
                                loops: Animation.Infinite
                                NumberAnimation { target: recordingDot; property: "opacity"; from: 1; to: 0.7; duration: 750; easing.type: Easing.InOutSine }
                                NumberAnimation { target: recordingDot; property: "opacity"; from: 0.7; to: 1; duration: 750; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RECORDING"
                        color: "#f38ba8"
                        font.family: "JetBrainsMono Nerd Font"
                        font.bold: true
                        font.pixelSize: 8
                    }
                }
            }

            Row {
                id: tabs
                anchors.top: parent.top
                anchors.topMargin: 36
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                visible: win.expanded && !win.notificationVisible && win.page !== "Launcher"

                Grid {
                    width: tabs.width
                    columns: 6
                    rowSpacing: 3
                    columnSpacing: 4
                    Repeater {
                        model: ["Launcher", "Music", "Wi-Fi", "Bluetooth", "Battery", "Volume", "Timer", "System", "Weather", "Record"]
                        delegate: Rectangle {
                        required property string modelData
                        width: (tabs.width - 20) / 6
                        height: 23
                        radius: 9
                        color: win.page === modelData ? win.raised : "transparent"
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: win.page === parent.modelData ? win.accent : win.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        TapHandler {
                            onTapped: {
                                win.page = parent.modelData
                                if (win.page === "Launcher")
                                    Qt.callLater(() => launcherSearch.forceActiveFocus())
                            }
                        }
                        }
                    }
                }
            }

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: win.page === "Launcher" ? parent.top : tabs.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: win.page === "Launcher" ? 12 : 8
                anchors.leftMargin: 17
                anchors.rightMargin: 17
                anchors.bottomMargin: 12
                visible: win.expanded && !win.notificationVisible

                Column {
                    anchors.fill: parent
                    spacing: 10
                    visible: win.page === "Launcher"

                    Row {
                        width: parent.width
                        height: 36
                        spacing: 10

                        TextInput {
                            id: launcherSearch
                            width: parent.width - 38
                            height: parent.height
                            verticalAlignment: TextInput.AlignVCenter
                            text: win.launcherQuery
                            color: win.foreground
                            selectionColor: win.accent
                            selectedTextColor: "#11111b"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            activeFocusOnPress: true
                            selectByMouse: true
                            onTextEdited: {
                                win.launcherQuery = text
                                launcherResults.currentIndex = 0
                            }
                            Keys.onDownPressed: {
                                if (launcherResults.count > 0)
                                    launcherResults.currentIndex = Math.min(launcherResults.currentIndex + 1, launcherResults.count - 1)
                            }
                            Keys.onUpPressed: {
                                launcherResults.currentIndex = Math.max(launcherResults.currentIndex - 1, 0)
                            }
                            Keys.onReturnPressed: if (launcherResults.count > 0)
                                win.launchIslandApp(launcherResults.currentItem.modelData)
                            Keys.onEnterPressed: if (launcherResults.count > 0)
                                win.launchIslandApp(launcherResults.currentItem.modelData)
                            Keys.onEscapePressed: win.closeLauncher()
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "⌕  Search apps…"
                                color: win.muted
                                font: parent.font
                                visible: launcherSearch.text.length === 0
                            }
                        }

                        Rectangle {
                            width: 28
                            height: 28
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 8
                            color: win.raised
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: win.foreground
                                font.pixelSize: 16
                            }
                            TapHandler { onTapped: win.closeLauncher() }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: win.raised
                    }

                    ListView {
                        id: launcherResults
                        width: parent.width
                        height: parent.height - 49
                        clip: true
                        spacing: 3
                        model: win.launcherResults
                        currentIndex: count > 0 ? 0 : -1
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: launcherResults.width
                            height: 44
                            radius: 8
                            color: launcherResults.currentIndex === index ? win.raised : "transparent"

                            HoverHandler {
                                onHoveredChanged: if (hovered) launcherResults.currentIndex = index
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12

                                Image {
                                    width: 28
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                                    sourceSize.width: 56
                                    sourceSize.height: 56
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }

                                Column {
                                    width: parent.width - 50
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        color: win.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.bold: true
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: modelData.genericName || modelData.comment || "Application"
                                        color: win.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            TapHandler { onTapped: win.launchIslandApp(modelData) }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: launcherResults.count === 0
                            text: win.launcherQuery ? "No matching applications" : "No applications found"
                            color: win.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    spacing: 12
                    visible: win.page === "Music"

                    Image {
                        id: artwork
                        width: 78
                        height: 78
                        anchors.verticalCenter: parent.verticalCenter
                        source: win.player ? (win.player.trackArtUrl ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                        Rectangle {
                            anchors.fill: parent
                            color: win.raised
                            radius: 11
                            z: -1
                        }
                    }

                    Column {
                        width: parent.width - artwork.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Text {
                            width: parent.width
                            text: win.player && win.player.trackTitle
                                ? win.player.trackTitle : "Nothing playing"
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: win.player
                                ? [win.player.trackArtist, win.player.trackAlbum].filter(v => v).join(" · ")
                                : "Start playback in an MPRIS player"
                            color: win.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: 18
                            Text {
                                text: "⏮"
                                color: win.player && win.player.canGoPrevious ? win.foreground : "#585b70"
                                font.pixelSize: 17
                                TapHandler { onTapped: if (win.player && win.player.canGoPrevious) win.player.previous() }
                            }
                            Text {
                                text: win.player && win.player.isPlaying ? "⏸" : "▶"
                                color: win.player && win.player.canTogglePlaying ? win.accent : "#585b70"
                                font.pixelSize: 17
                                TapHandler { onTapped: if (win.player && win.player.canTogglePlaying) win.player.togglePlaying() }
                            }
                            Text {
                                text: "⏭"
                                color: win.player && win.player.canGoNext ? win.foreground : "#585b70"
                                font.pixelSize: 17
                                TapHandler { onTapped: if (win.player && win.player.canGoNext) win.player.next() }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: win.page === "Wi-Fi"
                    Row {
                        id: wifiHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        width: parent.width
                        height: 24
                        spacing: 7
                        Text {
                            text: win.wifiRadioOn ? "Wi-Fi" : "Wi-Fi off"
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: 13
                        }
                        Item { width: parent.width - 188; height: 1 }
                        Text {
                            text: win.wifiDevice && win.wifiDevice.scannerEnabled ? "Scanning" : "Rescan"
                            color: win.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            TapHandler {
                                onTapped: if (win.wifiDevice) win.wifiDevice.scannerEnabled = true
                            }
                        }
                        Rectangle {
                            width: 34
                            height: 18
                            radius: 9
                            color: win.wifiRadioOn ? win.accent : win.raised
                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                y: 2
                                x: win.wifiRadioOn ? parent.width - width - 2 : 2
                                color: win.foreground
                            }
                            TapHandler {
                                onTapped: {
                                    wifiToggle.command = ["nmcli", "radio", "wifi", win.wifiRadioOn ? "off" : "on"]
                                    wifiToggle.running = true
                                }
                            }
                        }
                    }
                    Flickable {
                        anchors.top: wifiHeader.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 7
                        clip: true
                        contentHeight: networkRows.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: networkRows
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: win.wifiNetworks
                                delegate: Rectangle {
                                    required property var modelData
                                    width: networkRows.width
                                    height: 38
                                    radius: 9
                                    color: modelData.connected ? "#263349" : win.raised
                                    border.width: modelData.connected ? 1 : 0
                                    border.color: win.accent
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 63
                                            spacing: 2
                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                color: win.foreground
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.bold: true
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                width: parent.width
                                                text: modelData.connected ? "Connected" : (modelData.known ? "Saved network" : "Available network")
                                                color: modelData.connected ? win.accent : win.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 55
                                            horizontalAlignment: Text.AlignRight
                                            text: (modelData.security === WifiSecurityType.Open ? "" : "  ") + Math.round(modelData.signalStrength * 100) + "%"
                                            color: win.muted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                        }
                                    }
                                    TapHandler {
                                        onTapped: {
                                            if (modelData.connected) return
                                            if (modelData.security === WifiSecurityType.Open || modelData.known)
                                                modelData.connect()
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: win.wifiNetworks.length === 0
                                text: win.wifiRadioOn ? "Looking for nearby networks…" : "Turn Wi-Fi on to see networks"
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                padding: 8
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 10
                    visible: win.page === "Weather"
                    Row {
                        width: parent.width
                        height: 74
                        spacing: 12
                        Text {
                            width: 64
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: win.weatherCode >= 0 ? win.weatherIcon(win.weatherCode) : "☁"
                            color: "#f9e2af"
                            font.pixelSize: 45
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: win.weatherPlace || "Finding your location…"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 12
                            }
                            Text {
                                text: win.weatherCode >= 0 ? win.weatherText(win.weatherCode) : "Loading forecast…"
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                            Text {
                                text: win.weatherCode >= 0
                                    ? `Feels like ${Math.round(win.weatherFeelsLike)}°C` : ""
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }
                        Item { width: parent.width - 218; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.weatherCode >= 0 ? `${Math.round(win.weatherTemperature)}°` : "--°"
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 28
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: win.raised
                    }
                    Row {
                        width: parent.width
                        spacing: 3
                        Repeater {
                            model: win.weatherForecast
                            delegate: Column {
                                required property var modelData
                                width: (parent.width - 12) / 5
                                spacing: 5
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd")
                                    color: win.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: win.weatherIcon(modelData.code)
                                    color: "#f9e2af"
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: `${Math.round(modelData.high)}° / ${Math.round(modelData.low)}°`
                                    color: win.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                }
                            }
                        }
                    }
                    Text {
                        text: "Open-Meteo · updates every 30 min"
                        color: win.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 12
                    visible: win.page === "Battery"
                    Row {
                        width: parent.width
                        spacing: 12
                        Item {
                            width: 43
                            height: 39
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                x: 2
                                y: 9
                                width: 34
                                height: 21
                                radius: 5
                                color: "transparent"
                                border.width: 1.5
                                border.color: win.batteryColor()
                                Rectangle {
                                    x: 3
                                    y: 3
                                    width: Math.max(0, (parent.width - 8) * (win.battery && win.battery.ready ? Math.max(0, Math.min(1, win.battery.percentage)) : 0))
                                    height: parent.height - 6
                                    radius: 2
                                    color: parent.border.color
                                }
                            }
                            Rectangle {
                                x: 37
                                y: 15
                                width: 4
                                height: 9
                                radius: 2
                                color: win.batteryColor()
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: win.battery && win.battery.ready && win.battery.isLaptopBattery
                                    ? `${Math.round(win.battery.percentage * 100)}%` : "Battery unavailable"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 20
                            }
                            Text {
                                text: {
                                    if (!win.battery || !win.battery.ready) return ""
                                    const eta = win.batteryEta()
                                    if (win.battery.state === UPowerDeviceState.Charging)
                                        return eta ? "Charging · " + eta + " to full" : "Charging"
                                    if (win.battery.state === UPowerDeviceState.FullyCharged) return "Fully charged"
                                    if (win.battery.state === UPowerDeviceState.PendingCharge) return "Plugged in · charging soon"
                                    return eta ? "On battery · " + eta + " left" : "On battery"
                                }
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                            Text {
                                visible: win.batteryLowMode()
                                text: "LOW BATTERY MODE"
                                color: win.batteryColor()
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 8
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: win.raised
                    }
                    Row {
                        width: parent.width
                        spacing: 0
                        Column {
                            width: (parent.width - 1) / 2
                            spacing: 4
                            Text {
                                text: "POWER"
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                            Text {
                                text: win.battery && win.battery.ready && Number.isFinite(win.battery.changeRate)
                                    ? `${Math.abs(win.battery.changeRate).toFixed(1)} W` : "—"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 13
                            }
                            Text {
                                text: win.batteryPowerDirection()
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }
                        Rectangle {
                            width: 1
                            height: 42
                            color: win.raised
                        }
                        Column {
                            width: (parent.width - 1) / 2
                            spacing: 4
                            Text {
                                text: "CHARGE"
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                            Text {
                                text: win.battery && win.battery.ready && Number.isFinite(win.battery.energy)
                                    ? `${win.battery.energy.toFixed(1)} Wh` : "—"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 13
                            }
                            Text {
                                text: win.battery && win.battery.ready && Number.isFinite(win.battery.energyCapacity)
                                    ? `of ${win.battery.energyCapacity.toFixed(1)} Wh` : ""
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 12
                    visible: win.page === "Volume"
                    Row {
                        width: parent.width
                        spacing: 12
                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: "#101018"
                            border.width: 2
                            border.color: win.sink && win.sink.ready && !win.sink.audio.muted ? "#94e2d5" : win.raised
                            Text {
                                anchors.centerIn: parent
                                text: win.sink && win.sink.ready && win.sink.audio.muted ? "󰖁" : "󰕾"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 17
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: win.toggleOutputMute()
                            }
                        }
                        Column {
                            width: parent.width - 56
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Row {
                                width: parent.width
                                Text {
                                    text: "Volume"
                                    color: win.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                                Item { width: parent.width - 45; height: 1 }
                                Text {
                                    text: win.sink && win.sink.ready ? `${Math.round(win.sink.audio.volume * 100)}%` : "—"
                                    color: win.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }
                            }
                            Item {
                                id: volumeTrack
                                width: parent.width
                                height: 28
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: win.raised
                                    Rectangle {
                                        width: parent.width * (win.sink && win.sink.ready ? Math.max(0, Math.min(1, win.sink.audio.volume)) : 0)
                                        height: parent.height
                                        radius: 3
                                        color: "#a6e3a1"
                                    }
                                }
                                Row {
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: 3
                                    spacing: 2
                                    Repeater {
                                        model: 24
                                        Rectangle {
                                            required property int index
                                            width: (volumeTrack.width - 46) / 24
                                            height: 2
                                            radius: 1
                                            color: win.sink && win.sink.ready && !win.sink.audio.muted
                                                && index < Math.round(win.sink.audio.volume * 24)
                                                ? "#a6e3a1" : win.raised
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (win.sink && win.sink.ready) win.sink.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
                                    onPositionChanged: if (pressed && win.sink && win.sink.ready) win.sink.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Rectangle {
                            width: 122
                            height: 28
                            radius: 14
                            color: win.sink && win.sink.ready && win.sink.audio.muted ? win.accent : win.raised
                            Text {
                                anchors.centerIn: parent
                                text: win.sink && win.sink.ready && win.sink.audio.muted ? "Unmute" : "Mute"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.toggleOutputMute()
                            }
                        }
                        Rectangle {
                            width: 122
                            height: 28
                            radius: 14
                            color: win.source && win.source.ready && win.source.audio.muted ? win.accent : win.raised
                            Text {
                                anchors.centerIn: parent
                                text: win.source && win.source.ready && win.source.audio.muted ? "Unmute mic" : "Mic"
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.toggleMicrophoneMute()
                            }
                        }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    height: 88
                    visible: win.page === "Timer"
                    spacing: 14

                    Item {
                        width: 62
                        height: 62
                        anchors.verticalCenter: parent.verticalCenter
                        Canvas {
                            id: countdownRing
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const cx = width / 2
                                const cy = height / 2
                                const radius = 28
                                ctx.lineWidth = 4
                                ctx.strokeStyle = "#45475a"
                                ctx.beginPath()
                                ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                                ctx.stroke()
                                const fraction = win.countdownRunning && win.countdownDuration > 0
                                    ? Math.max(0, Math.min(1, win.countdownRemaining / win.countdownDuration)) : 1
                                ctx.strokeStyle = win.countdownPaused ? "#a6adc8" : "#89b4fa"
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.arc(cx, cy, radius, -Math.PI / 2,
                                    -Math.PI / 2 + Math.PI * 2 * fraction, false)
                                ctx.stroke()
                            }
                            Connections {
                                target: win
                                function onCountdownRemainingChanged() { countdownRing.requestPaint() }
                                function onCountdownRunningChanged() { countdownRing.requestPaint() }
                                function onCountdownPausedChanged() { countdownRing.requestPaint() }
                                function onCountdownDurationChanged() { countdownRing.requestPaint() }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: win.countdownRunning ? win.countdownText() : win.countdownPreview()
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: win.countdownHours > 0 || win.countdownRunning && win.countdownDuration >= 3600000 ? 11 : 14
                        }
                    }

                    Column {
                        width: parent.width - 76
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Column {
                            width: parent.width
                            spacing: 1
                            TextInput {
                                id: timerLabelInput
                                width: parent.width
                                height: 18
                                visible: !win.countdownRunning
                                text: win.countdownLabel
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 11
                                onTextEdited: win.countdownLabel = text
                            }
                            Text {
                                width: parent.width
                                visible: win.countdownRunning
                                text: win.countdownLabel
                                color: win.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.bold: true
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: win.countdownRunning
                                    ? (win.countdownPaused ? "Held" : "Running")
                                    : "Set a countdown"
                                color: win.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }

                        Row {
                            width: parent.width
                            height: 28
                            spacing: 6
                            visible: win.countdownRunning
                            Repeater {
                                model: ["toggle", "restart", "stop"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: modelData === "toggle" ? parent.width - 96 : 42
                                    height: parent.height
                                    radius: 16
                                    color: win.raised
                                    border.width: 1
                                    border.color: "#585b70"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData === "toggle"
                                            ? (win.countdownPaused ? "▶  Resume" : "Ⅱ  Hold")
                                            : modelData === "restart" ? "↻" : "■"
                                        color: modelData === "stop" ? win.accent : win.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: modelData === "toggle" ? 9 : 12
                                    }
                                    TapHandler {
                                        onTapped: {
                                            if (modelData === "toggle") win.toggleCountdown()
                                            else if (modelData === "restart") win.restartCountdown()
                                            else win.stopCountdown()
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 26
                            spacing: 5
                            visible: !win.countdownRunning
                            Repeater {
                                model: [
                                    { unit: "h", value: win.countdownHours },
                                    { unit: "m", value: win.countdownMinutes },
                                    { unit: "s", value: win.countdownSeconds }
                                ]
                                delegate: Row {
                                    required property var modelData
                                    width: (parent.width - 10) / 3
                                    height: parent.height
                                    spacing: 1
                                    Rectangle {
                                        width: 17
                                        height: parent.height
                                        radius: 5
                                        color: win.raised
                                        Text { anchors.centerIn: parent; text: "−"; color: win.foreground; font.pixelSize: 10 }
                                        TapHandler { onTapped: win.adjustCountdown(parent.parent.modelData.unit, -1) }
                                    }
                                    Text {
                                        width: parent.width - 36
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.value + modelData.unit
                                        color: "#d6d9dc"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                    }
                                    Rectangle {
                                        width: 17
                                        height: parent.height
                                        radius: 5
                                        color: win.raised
                                        Text { anchors.centerIn: parent; text: "+"; color: win.foreground; font.pixelSize: 10 }
                                        TapHandler { onTapped: win.adjustCountdown(parent.parent.modelData.unit, 1) }
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 25
                            spacing: 6
                            visible: !win.countdownRunning
                            Repeater {
                                model: ["start", "clear"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: (parent.width - 6) / 2
                                    height: parent.height
                                    radius: 15
                                    color: modelData === "start" ? win.accent : win.raised
                                    border.width: 1
                                    border.color: "#585b70"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData === "start" ? "Start" : "Clear"
                                        color: modelData === "start" ? "#11111b" : win.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                    }
                                    TapHandler {
                                        onTapped: {
                                            if (modelData === "start") win.startCountdown()
                                            else {
                                                win.countdownHours = 0
                                                win.countdownMinutes = 0
                                                win.countdownSeconds = 0
                                                win.countdownStatus = "Timer cleared"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 9
                    visible: win.page === "Bluetooth"
                    Text {
                        text: win.adapter
                            ? (win.adapter.enabled ? "Bluetooth on" : "Bluetooth off")
                            : "Bluetooth adapter unavailable"
                        color: win.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.bold: true
                        font.pixelSize: 13
                    }
                    Text {
                        width: parent.width
                        text: win.connectedBluetooth.length
                            ? "Connected: " + win.connectedBluetooth.map(d => d.name || d.address).join(", ")
                            : (win.adapter && win.adapter.enabled ? "No connected devices" : "")
                        color: win.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: win.adapter !== null
                        text: win.adapter && win.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
                        color: win.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        TapHandler { onTapped: if (win.adapter) win.adapter.enabled = !win.adapter.enabled }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 9
                    visible: win.page === "Record"
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.screenRecording ? "SCREEN RECORDING" : "SCREEN RECORDER"
                        color: win.screenRecording ? "#f38ba8" : win.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.bold: true
                        font.pixelSize: 13
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: win.recordingStatus
                        color: win.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 138
                        height: 31
                        radius: 10
                        color: win.screenRecording ? "#f38ba8" : win.raised
                        Text {
                            anchors.centerIn: parent
                            text: win.screenRecording ? "■  Stop recording" : "●  Start recording"
                            color: win.screenRecording ? "#1e1e2e" : win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: 10
                        }
                        TapHandler { onTapped: win.toggleScreenRecording() }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Videos folder · MP4"
                        color: win.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 4
                    visible: win.page === "System"
                    Row {
                        width: parent.width
                        Text {
                            text: "PROCESSOR"
                            color: win.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                        Item { width: parent.width - 140; height: 1 }
                        Text {
                            text: `${win.cpuUsage}%`
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: 12
                        }
                    }
                    Canvas {
                        id: cpuGraph
                        width: parent.width
                        height: 34
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const values = win.cpuHistory
                            if (values.length < 2) return
                            ctx.beginPath()
                            for (let i = 0; i < values.length; i++) {
                                const x = i * width / (values.length - 1)
                                const y = height - 2 - Math.max(0, Math.min(100, values[i])) / 100 * (height - 4)
                                if (i === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.strokeStyle = "#89b4fa"
                            ctx.lineWidth = 2
                            ctx.stroke()
                        }
                        Connections {
                            target: win
                            function onCpuHistoryChanged() { cpuGraph.requestPaint() }
                        }
                    }
                    Row {
                        width: parent.width
                        Text {
                            text: "MEMORY"
                            color: win.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                        Item { width: parent.width - 140; height: 1 }
                        Text {
                            text: `${win.memoryUsed.toFixed(1)} / ${win.memoryTotal.toFixed(1)} GB`
                            color: win.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.bold: true
                            font.pixelSize: 12
                        }
                    }
                    Canvas {
                        id: memoryGraph
                        width: parent.width
                        height: 34
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const values = win.memoryHistory
                            if (values.length < 2) return
                            ctx.beginPath()
                            for (let i = 0; i < values.length; i++) {
                                const x = i * width / (values.length - 1)
                                const y = height - 2 - Math.max(0, Math.min(100, values[i])) / 100 * (height - 4)
                                if (i === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.strokeStyle = "#cba6f7"
                            ctx.lineWidth = 2
                            ctx.stroke()
                        }
                        Connections {
                            target: win
                            function onMemoryHistoryChanged() { memoryGraph.requestPaint() }
                        }
                    }
                }

            }
        }
    }
}

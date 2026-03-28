import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: window

    MatugenColors { id: _theme }

    // ─────────────────────────────────────────────
    // PROPERTIES & IPC RECEIVER
    // ─────────────────────────────────────────────
    property string widgetArg: ""
    property string targetWallName: ""
    property bool initialFocusSet: false
    property int visibleItemCount: -1
    property int scrollAccum: 0
    property int scrollThreshold: 500

    // Filter System
    property string currentFilter: "All"
    property string searchQuery: ""
    property var colorMap: ({})
    property int cacheVersion: 0

    // ── DDG Online Search (commented out — enable when ddg_search.sh is set up) ──
    // property bool isOnlineSearch: false
    // property bool isSearchPaused: false
    // property bool hasSearched: false
    // property bool isDownloadingWallpaper: false
    // property string currentDownloadName: ""
    // property bool isSearchActive: false
    // property bool isScrollingBlocked: window.currentFilter === "Search" && window.hasSearched && window.isSearchActive && !window.isSearchPaused

    // ── Video wallpaper state (commented out — enable when linux-wallpaperengine/mpvpaper is set up) ──
    // readonly property string mpvCommand: "pkill mpvpaper; mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' '*' '%1'"

    readonly property var filterData: [
        { name: "All",        hex: "",        label: "All"   },
        // { name: "Video",   hex: "",        label: "Vid"   },  // uncomment when mpvpaper/linux-wallpaperengine is set up
        { name: "Red",        hex: "#FF4500", label: ""      },
        { name: "Orange",     hex: "#FFA500", label: ""      },
        { name: "Yellow",     hex: "#FFD700", label: ""      },
        { name: "Green",      hex: "#32CD32", label: ""      },
        { name: "Blue",       hex: "#1E90FF", label: ""      },
        { name: "Purple",     hex: "#8A2BE2", label: ""      },
        { name: "Pink",       hex: "#FF69B4", label: ""      },
        { name: "Monochrome", hex: "#A9A9A9", label: ""      },
        // { name: "Search",  hex: "",        label: "Search" }   // uncomment when ddg_search.sh is set up
    ]

    // ─────────────────────────────────────────────
    // PATHS
    // Changed: ~/Images/Wallpapers → ~/Pictures/Wallpapers
    // Changed: swww → awww
    // ─────────────────────────────────────────────
    readonly property string homeDir:  "file://" + Quickshell.env("HOME")
    readonly property string thumbDir: homeDir + "/.cache/wallpaper_picker/thumbs"
    readonly property string searchDir: homeDir + "/.cache/wallpaper_picker/search_thumbs"   // used by DDG search when enabled
    readonly property string srcDir:   Quickshell.env("HOME") + "/Pictures/Wallpapers"

    // awww apply command with random transition
    readonly property string awwwCommand: "awww img '%1' --transition-type %2 --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1"
    readonly property var transitions: ["grow", "outer", "any", "wipe", "wave", "pixel", "center"]

    // ── mpvpaper command (commented out — enable when mpvpaper is set up) ──
    // readonly property string mpvCommand: "pkill mpvpaper; mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality' '*' '%1'"

    readonly property int itemWidth:   400
    readonly property int itemHeight:  420
    readonly property int borderWidth: 3
    readonly property int spacing:     10
    readonly property real skewFactor: -0.35

    // ─────────────────────────────────────────────
    // RESET & VISIBILITY
    // ─────────────────────────────────────────────
    function resetSearch() {
        window.currentFilter = "All";
        window.searchQuery = "";
        // ── DDG reset (uncomment when DDG search is enabled) ──
        // window.hasSearched = false;
        // window.isSearchPaused = false;
        // window.isDownloadingWallpaper = false;
        // window.isSearchActive = false;
        // if (searchInput) searchInput.text = "";
        // Quickshell.execDetached(["bash", "-c", "echo 'stop' > /tmp/ddg_search_control; pkill -f '[g]et_ddg_links.py'; rm -rf '" + decodeURIComponent(window.searchDir.replace("file://", "")) + "'/*"]);
    }

    onVisibleChanged: {
        if (!visible) resetSearch();
    }

    // ─────────────────────────────────────────────
    // NOTIFICATION STATE
    // ─────────────────────────────────────────────
    property bool isLoading: folderModel.status === FolderListModel.Loading ||
                             srcModel.status === FolderListModel.Loading

    property bool showSpinner: (window.currentFilter !== "Search" && window.isLoading)
    // ── DDG spinner (uncomment when DDG enabled) ──
    // property bool showSpinner: window.isDownloadingWallpaper ||
    //     (window.currentFilter === "Search" && window.hasSearched && (window.visibleItemCount === 0 || window.isSearchActive) && !window.isSearchPaused) ||
    //     (window.currentFilter !== "Search" && window.isLoading)

    property string currentNotification: {
        // ── DDG notifications (uncomment when DDG enabled) ──
        // if (window.isDownloadingWallpaper) return "Downloading wallpaper...";
        // if (window.currentFilter === "Search") {
        //     if (!window.hasSearched) return "Type something to search...";
        //     if (window.isSearchPaused) return "Search Paused";
        //     if (window.visibleItemCount === 0) return "Searching DDG (FHD+)...";
        //     if (window.isSearchActive) return "Generating thumbnails...";
        //     return "";
        // }

        if (isLoading) return "Generating thumbnails...";
        if (window.visibleItemCount === 0) return "No wallpapers found";
        if (window.currentFilter === "All") return "";

        return window.currentFilter;
    }

    property bool showNotification: currentNotification !== ""

    // ─────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────
    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);
        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    function isDownloaded(name) {
        if (!name) return false;
        for (let i = 0; i < srcModel.count; i++) {
            if (srcModel.get(i, "fileName") === name) return true;
        }
        return false;
    }

    onWidgetArgChanged: {
        if (widgetArg !== "") {
            targetWallName = widgetArg;
            initialFocusSet = false;
            tryFocus();
        }
    }

    function tryFocus() {
        if (initialFocusSet) return;
        if (proxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);
            if (cleanTarget !== "") {
                for (let i = 0; i < proxyModel.count; i++) {
                    let fname = proxyModel.get(i).fileName || "";
                    if (window.getCleanName(fname) === cleanTarget) {
                        foundIndex = i;
                        break;
                    }
                }
            }
            let finalIndex = foundIndex !== -1 ? foundIndex : 0;
            view.currentIndex = finalIndex;
            view.positionViewAtIndex(finalIndex, ListView.Center);
            initialFocusSet = true;
        }
    }

    function updateVisibleCount() {
        if (!proxyModel || proxyModel.count === 0) {
            window.visibleItemCount = 0;
            return;
        }
        let count = 0;
        for (let i = 0; i < proxyModel.count; i++) {
            let fname = proxyModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) count++;
        }
        window.visibleItemCount = count;
    }

    // ─────────────────────────────────────────────
    // DDG ONLINE SEARCH
    // Commented out — uncomment when ddg_search.sh + get_ddg_links.py are set up
    // ─────────────────────────────────────────────
    // function triggerOnlineSearch() {
    //     if (searchInput.text.trim() === "") return;
    //     proxyModel.clear();
    //     view.currentIndex = 0;
    //     view.positionViewAtIndex(0, ListView.Center);
    //     window.isOnlineSearch = true;
    //     window.hasSearched = true;
    //     window.isSearchPaused = false;
    //     window.isSearchActive = true;
    //     window.searchQuery = searchInput.text.trim();
    //     let rawSearchDir = decodeURIComponent(window.searchDir.replace(/^file:\/\//, ""));
    //     let scriptPath = decodeURIComponent(Qt.resolvedUrl("ddg_search.sh").toString().replace(/^file:\/\//, ""));
    //     const cmd = `
    //         exec > /tmp/qs_ddg_run.log 2>&1
    //         echo 'stop' > /tmp/ddg_search_control
    //         pkill -f "[g]et_ddg_links.py" || true
    //         sleep 0.5
    //         rm -rf "${rawSearchDir}"/* || true
    //         rm -f "${rawSearchDir}/../search_map.txt" || true
    //         echo 'run' > /tmp/ddg_search_control
    //         bash "${scriptPath}" "${window.searchQuery}" &
    //     `;
    //     Quickshell.execDetached(["bash", "-c", cmd]);
    //     searchInput.focus = false;
    //     view.forceActiveFocus();
    // }

    // ─────────────────────────────────────────────
    // COLOR FILTERING
    // ─────────────────────────────────────────────
    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";
        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";

        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;

        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";

        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let d = max - min;
        let h = 0;
        let s = max === 0 ? 0 : d / max;
        let v = max;

        if (max !== min) {
            if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }
        h = h * 360;

        if (s < 0.05 || v < 0.08) return "Monochrome";
        if (h >= 345 || h < 15)   return "Red";
        if (h >= 15  && h < 45)   return "Orange";
        if (h >= 45  && h < 75)   return "Yellow";
        if (h >= 75  && h < 165)  return "Green";
        if (h >= 165 && h < 260)  return "Blue";
        if (h >= 260 && h < 315)  return "Purple";
        if (h >= 315 && h < 345)  return "Pink";
        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        // ── Video filter (uncomment when mpvpaper/linux-wallpaperengine is set up) ──
        // if (filter === "Search") return true;
        // if (filter === "Video") return isVid;

        if (filter === "All") return !isVid;   // hide video files until mpvpaper is set up
        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";
        return window.getHexBucket(hexColor) === filter;
    }

    // ─────────────────────────────────────────────
    // COLOR MARKER SYSTEM
    // ─────────────────────────────────────────────
    FolderListModel {
        id: markerModel
        folder: "file://" + Quickshell.env("HOME") + "/.cache/wallpaper_picker/colors_markers"
        showDirs: false
        nameFilters: ["*_HEX_*"]
        onCountChanged: window.processMarkers()
        onStatusChanged: { if (status === FolderListModel.Ready) window.processMarkers() }
    }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        // ── Download completion check (uncomment when DDG is enabled) ──
        // onCountChanged: {
        //     if (window.isDownloadingWallpaper && window.isDownloaded(window.currentDownloadName)) {
        //         window.isDownloadingWallpaper = false;
        //     }
        // }
    }

    function processMarkers() {
        let newMap = {};
        for (let i = 0; i < markerModel.count; i++) {
            let markerName = markerModel.get(i, "fileName") || "";
            if (!markerName) continue;
            let splitIdx = markerName.lastIndexOf("_HEX_");
            if (splitIdx !== -1) {
                let fName  = markerName.substring(0, splitIdx);
                let hexCode = markerName.substring(splitIdx + 5);
                newMap[fName] = "#" + hexCode;
            }
        }
        window.colorMap = newMap;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    function triggerColorExtraction() {
        const extractScript = `
            COLOR_DIR="$HOME/.cache/wallpaper_picker/colors_markers"
            THUMBS="$HOME/.cache/wallpaper_picker/thumbs"
            CSV="$HOME/.cache/wallpaper_picker/colors.csv"
            mkdir -p "$COLOR_DIR"
            if [ -f "$CSV" ]; then
                while IFS=, read -r fname hexcode; do
                    cleanhex=$(echo "$hexcode" | tr -d '\r#' | cut -c 1-6)
                    if [ -n "$cleanhex" ] && [ -n "$fname" ]; then
                        touch "$COLOR_DIR/$fname""_HEX_$cleanhex" 2>/dev/null
                    fi
                done < "$CSV"
                mv "$CSV" "$CSV.bak" 2>/dev/null
            fi
            if command -v magick &> /dev/null; then CMD="magick"; else CMD="convert"; fi
            for file in "$THUMBS"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    found=0
                    for marker in "$COLOR_DIR/$filename"_HEX_*; do
                        if [ -e "$marker" ]; then found=1; break; fi
                    done
                    if [ $found -eq 0 ]; then
                        hex=$($CMD "$file" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$hex" ]; then
                            touch "$COLOR_DIR/$filename""_HEX_$hex"
                        fi
                    fi
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", extractScript]);
    }

    // ─────────────────────────────────────────────
    // NAVIGATION HELPERS
    // ─────────────────────────────────────────────
    function stepToNextValidIndex(direction) {
        if (proxyModel.count === 0) return;
        let start = view.currentIndex;
        let current = start;
        for (let i = 0; i < proxyModel.count; i++) {
            current = (current + direction + proxyModel.count) % proxyModel.count;
            let fname = proxyModel.get(current).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                view.currentIndex = current;
                return;
            }
        }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) {
                currentIdx = i;
                break;
            }
        }
        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters() {
        if (proxyModel.count === 0) return;
        let targetIndex = -1;
        let firstValidIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        for (let i = 0; i < proxyModel.count; i++) {
            let fname = proxyModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) firstValidIndex = i;
                if (cleanTarget !== "" && window.getCleanName(fname) === cleanTarget) {
                    targetIndex = i;
                    break;
                }
            }
        }
        let indexToFocus = (targetIndex !== -1) ? targetIndex : firstValidIndex;
        if (indexToFocus !== -1) view.currentIndex = indexToFocus;
        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        // ── Search focus (uncomment when DDG enabled) ──
        // if (window.currentFilter === "Search") searchInput.forceActiveFocus();
        // else view.forceActiveFocus();
        view.forceActiveFocus();
        window.applyFilters();
    }

    // ─────────────────────────────────────────────
    // TIMERS
    // ─────────────────────────────────────────────
    Timer {
        id: scrollThrottle
        interval: 150
    }

    // ── DDG search active timer (uncomment when DDG enabled) ──
    // Timer {
    //     id: searchActiveTimer
    //     interval: 3000
    //     onTriggered: window.isSearchActive = false
    // }

    // ─────────────────────────────────────────────
    // SHORTCUTS
    // ─────────────────────────────────────────────
    Shortcut { sequence: "Left";   onActivated: window.stepToNextValidIndex(-1) }
    Shortcut { sequence: "Right";  onActivated: window.stepToNextValidIndex(1) }
    Shortcut { sequence: "Return"; enabled: true; onActivated: { if (view.currentItem) view.currentItem.pickWallpaper() } }
    Shortcut { sequence: "Escape"; onActivated: { if (window.currentFilter !== "All") window.currentFilter = "All" } }
    Shortcut { sequence: "Tab";    onActivated: window.cycleFilter(1) }
    Shortcut { sequence: "Backtab"; onActivated: window.cycleFilter(-1) }

    // ─────────────────────────────────────────────
    // MODELS
    // ─────────────────────────────────────────────
    ListModel {
        id: proxyModel
    }

    // ─────────────────────────────────────────────
    // CAROUSEL VIEW
    // ─────────────────────────────────────────────
    ListView {
        id: view
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        orientation: ListView.Horizontal
        clip: false
        interactive: true
        cacheBuffer: 2000
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2)
        preferredHighlightEnd:   (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2)
        highlightMoveDuration: window.initialFocusSet ? 500 : 0
        focus: true

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale";   from: 0.5; to: 1; duration: 400; easing.type: Easing.OutBack }
            }
        }
        addDisplaced: Transition {
            NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutCubic }
        }

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }

        model: proxyModel

        // ── Debouncer: bridges file system changes to smooth UI updates ──
        Timer {
            id: countChangeDebouncer
            interval: 100
            onTriggered: {
                if (folderModel.status !== FolderListModel.Ready && folderModel.count === 0) return;
                let startIdx = proxyModel.count;
                let endIdx   = folderModel.count;
                if (endIdx < startIdx) {
                    proxyModel.clear();
                    startIdx = 0;
                }
                for (let i = startIdx; i < endIdx; i++) {
                    let fn = folderModel.get(i, "fileName");
                    let fu = folderModel.get(i, "fileUrl");
                    if (fn !== undefined) proxyModel.append({ "fileName": fn, "fileUrl": String(fu) });
                }
                window.updateVisibleCount();

                // ── DDG scroll lock (uncomment when DDG enabled) ──
                // if (window.isScrollingBlocked && startIdx === 0 && proxyModel.count > 0) {
                //     view.currentIndex = 0;
                //     view.positionViewAtIndex(0, ListView.Center);
                // }

                window.tryFocus();
                if (window.initialFocusSet && window.targetWallName !== "") {
                    let cleanTarget = window.getCleanName(window.targetWallName);
                    for (let i = 0; i < proxyModel.count; i++) {
                        let fname = proxyModel.get(i).fileName || "";
                        if (window.getCleanName(fname) === cleanTarget) {
                            view.currentIndex = i;
                            break;
                        }
                    }
                }
            }
        }

        // ── Native file system watcher ──
        FolderListModel {
            id: folderModel
            folder: window.thumbDir
            // ── DDG folder switch (uncomment when DDG enabled) ──
            // folder: window.currentFilter === "Search" ? window.searchDir : window.thumbDir
            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif"]
            // ── Video nameFilters (uncomment when mpvpaper is set up) ──
            // nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
            showDirs: false
            sortField: FolderListModel.Name

            onFolderChanged: {
                proxyModel.clear();
                view.currentIndex = 0;
                view.positionViewAtIndex(0, ListView.Center);
            }

            onCountChanged: {
                // ── DDG search active trigger (uncomment when DDG enabled) ──
                // if (window.currentFilter === "Search" && window.hasSearched) {
                //     window.isSearchActive = true;
                //     searchActiveTimer.restart();
                // }
                countChangeDebouncer.restart();
            }

            onStatusChanged: {
                if (status === FolderListModel.Ready) countChangeDebouncer.restart();
            }
        }

        // ── Scroll wheel handler ──
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (wheel) => {
                if (scrollThrottle.running) { wheel.accepted = true; return; }
                let dx = wheel.angleDelta.x;
                let dy = wheel.angleDelta.y;
                let delta = Math.abs(dx) > Math.abs(dy) ? dx : dy;
                scrollAccum += delta;
                if (Math.abs(scrollAccum) >= scrollThreshold) {
                    window.stepToNextValidIndex(scrollAccum > 0 ? -1 : 1);
                    scrollAccum = 0;
                    scrollThrottle.start();
                }
                wheel.accepted = true;
            }
        }

        // ─────────────────────────────────────────────
        // WALLPAPER CARD DELEGATE
        // ─────────────────────────────────────────────
        delegate: Item {
            id: delegateRoot

            readonly property string safeFileName: fileName !== undefined ? String(fileName) : ""
            readonly property bool isCurrent:         ListView.isCurrentItem
            readonly property bool isVisuallyEnlarged: isCurrent
            readonly property bool isVideo:            safeFileName.startsWith("000_")
            readonly property bool matchesFilter:      window.checkItemMatchesFilter(safeFileName, isVideo, window.cacheVersion, window.currentFilter)

            readonly property real targetWidth:  isVisuallyEnlarged ? (window.itemWidth * 1.5) : (window.itemWidth * 0.5)
            readonly property real targetHeight: isVisuallyEnlarged ? (window.itemHeight + 30) : window.itemHeight

            width:   matchesFilter ? (targetWidth + window.spacing) : 0
            visible: width > 0.1 || opacity > 0.01
            opacity: matchesFilter ? (isVisuallyEnlarged ? 1.0 : 0.6) : 0.0
            scale:   matchesFilter ? 1.0 : 0.5
            height:  matchesFilter ? targetHeight : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 15
            z: isVisuallyEnlarged ? 10 : 1

            Behavior on scale   { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on width   { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on height  { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

            function pickWallpaper() {
                window.targetWallName = safeFileName;
                let cleanName = window.getCleanName(safeFileName);

                let reloadScript = Qt.resolvedUrl("matugen_reload.sh").toString();
                if (reloadScript.startsWith("file://")) reloadScript = decodeURIComponent(reloadScript.substring(7));

                // ── DDG download logic (uncomment when DDG enabled) ──
                // if (window.currentFilter === "Search" && window.hasSearched) { ... }

                const originalFile = window.srcDir + "/" + cleanName;
                const thumbFile    = Quickshell.env("HOME") + "/.cache/wallpaper_picker/thumbs/" + safeFileName;

                let wallpaperCmd = "";
                if (isVideo) {
                    // ── Video apply (uncomment when mpvpaper/linux-wallpaperengine is set up) ──
                    // wallpaperCmd = window.mpvCommand.arg(originalFile);
                    console.log("Video wallpapers not yet set up — mpvpaper/linux-wallpaperengine needed");
                    return;
                } else {
                    const randomTransition = window.transitions[Math.floor(Math.random() * window.transitions.length)];
                    // Using awww instead of swww
                    wallpaperCmd = "pkill mpvpaper 2>/dev/null; " + window.awwwCommand.arg(originalFile).arg(randomTransition);
                }

                const fullScript = wallpaperCmd + " & matugen image '" + thumbFile + "' && bash '" + reloadScript + "'";
                Quickshell.execDetached(["bash", "-c", fullScript]);
                Quickshell.execDetached(["bash", "-c", "echo 'close' > /tmp/qs_widget_state"]);
            }

            MouseArea {
                anchors.fill: parent
                enabled: delegateRoot.matchesFilter
                onClicked: {
                    view.currentIndex = index;
                    delegateRoot.pickWallpaper();
                }
            }

            // ── Skewed card visuals ──
            Item {
                anchors.centerIn: parent
                width:  parent.width > 0 ? parent.width * (targetWidth / (targetWidth + window.spacing)) : 0
                height: parent.height

                transform: Matrix4x4 {
                    property real s: window.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                // Background fill (prevents bleed from card edges)
                Image {
                    anchors.fill: parent
                    source: fileUrl !== undefined ? fileUrl : ""
                    sourceSize: Qt.size(1, 1)
                    fillMode: Image.Stretch
                    visible: true
                    asynchronous: true
                }

                // Main image with counter-skew to appear straight
                Item {
                    anchors.fill: parent
                    anchors.margins: window.borderWidth
                    Rectangle { anchors.fill: parent; color: "black" }
                    clip: true

                    Image {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -50
                        width:  (window.itemWidth * 1.5) + ((window.itemHeight + 30) * Math.abs(window.skewFactor)) + 50
                        height: window.itemHeight + 30
                        fillMode: Image.PreserveAspectCrop
                        source: fileUrl !== undefined ? fileUrl : ""
                        asynchronous: true

                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    // ── Video badge (uncomment when mpvpaper/linux-wallpaperengine is set up) ──
                    // Rectangle {
                    //     visible: delegateRoot.isVideo
                    //     anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 10
                    //     width: 32; height: 32; radius: 6; color: "#60000000"
                    //     transform: Matrix4x4 {
                    //         property real s: -window.skewFactor
                    //         matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                    //     }
                    //     Canvas {
                    //         anchors.fill: parent; anchors.margins: 8
                    //         onPaint: {
                    //             var ctx = getContext("2d");
                    //             ctx.fillStyle = "#EEFFFFFF";
                    //             ctx.beginPath(); ctx.moveTo(4,0); ctx.lineTo(14,8); ctx.lineTo(4,16); ctx.closePath(); ctx.fill();
                    //         }
                    //     }
                    // }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // FLOATING FILTER BAR
    // ─────────────────────────────────────────────
    Rectangle {
        id: filterBarBackground
        anchors.top: parent.top
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        z: 20
        height: 56
        width: filterRow.width + 24
        radius: height / 2
        color: Qt.rgba(_theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.85)
        border.color: Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.5)
        border.width: 1

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: 12

            // ── Notification / loading indicator ──
            Rectangle {
                id: notifDrawer
                height: 44
                property real paddingLeft: window.showSpinner ? 40 : 16
                property real targetWidth: window.showNotification ? Math.min(notifTextDrawer.implicitWidth + paddingLeft + 16, 300) : 0
                width: targetWidth
                visible: width > 0.1
                radius: height / 2
                clip: true
                color: "transparent"
                border.width: 0
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }

                Item {
                    visible: window.showSpinner
                    width: 44; height: 44
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Canvas {
                        id: notifSpinner
                        width: 14; height: 14
                        anchors.centerIn: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.lineWidth = 2;
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.3);
                            ctx.beginPath(); ctx.arc(7, 7, 5, 0, Math.PI * 2); ctx.stroke();
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7);
                            ctx.beginPath(); ctx.arc(7, 7, 5, 0, Math.PI * 0.5); ctx.stroke();
                        }
                        RotationAnimation on rotation {
                            loops: Animation.Infinite; from: 0; to: 360; duration: 800
                            running: window.showSpinner && window.showNotification
                        }
                    }
                }

                Text {
                    id: notifTextDrawer
                    anchors.left: parent.left
                    anchors.leftMargin: window.showSpinner ? 40 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 300 - anchors.leftMargin - 16)
                    text: window.currentNotification
                    color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                    font.family: "JetBrains Mono"; font.pixelSize: 14; font.bold: true
                    elide: Text.ElideRight
                    opacity: window.showNotification ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }
                }
            }

            // ── Filter pills ──
            Repeater {
                model: window.filterData
                delegate: Item {
                    // ── Video filter hidden (uncomment when mpvpaper is set up) ──
                    visible: modelData.name !== "Search" // && modelData.name !== "Video"
                    width:  !visible ? 0 : ((modelData.name === "All") ? 44 : (modelData.hex === "" ? filterText.contentWidth + 24 : 36))
                    height: !visible ? 0 : 36
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: modelData.hex === ""
                                ? (window.currentFilter === modelData.name ? _theme.surface2 : "transparent")
                                : modelData.hex
                        border.color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(0,0,0, 0.2)
                        border.width: window.currentFilter === modelData.name ? 2 : 1
                        scale: window.currentFilter === modelData.name ? 1.15 : (filterMouse.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                        Text {
                            id: filterText
                            visible: modelData.hex === "" && modelData.name !== "All"
                            text: modelData.label
                            anchors.centerIn: parent
                            color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            font.family: "JetBrains Mono"
                            font.bold: window.currentFilter === modelData.name
                            Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                        }

                        // "All" icon — four squares
                        Canvas {
                            visible: modelData.name === "All"
                            width: 14; height: 14
                            anchors.centerIn: parent
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.fillRect(0, 0, 6, 6); ctx.fillRect(8, 0, 6, 6);
                                ctx.fillRect(0, 8, 6, 6); ctx.fillRect(8, 8, 6, 6);
                            }
                        }

                        // ── Video play icon (uncomment when mpvpaper is set up) ──
                        // Canvas {
                        //     visible: modelData.name === "Video"
                        //     width: 14; height: 16
                        //     anchors.centerIn: parent; anchors.horizontalCenterOffset: 2
                        //     property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                        //     onActiveColorChanged: requestPaint()
                        //     onPaint: {
                        //         var ctx = getContext("2d"); ctx.reset();
                        //         ctx.fillStyle = activeColor;
                        //         ctx.beginPath(); ctx.moveTo(0,0); ctx.lineTo(14,8); ctx.lineTo(0,16); ctx.closePath(); ctx.fill();
                        //     }
                        // }
                    }

                    MouseArea {
                        id: filterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: window.currentFilter = modelData.name
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            // ── DDG search box (uncomment when ddg_search.sh is set up) ──
            // Rectangle {
            //     id: searchBox
            //     height: 44
            //     width: window.currentFilter === "Search" ? 360 : 44
            //     radius: height / 2; clip: true
            //     color: window.currentFilter === "Search" ? _theme.surface2 : "transparent"
            //     border.color: window.currentFilter === "Search" ? _theme.text : Qt.rgba(0,0,0, 0.2)
            //     border.width: window.currentFilter === "Search" ? 2 : 1
            //     Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }
            //     // ... (full search box implementation)
            // }
        }
    }

    // ─────────────────────────────────────────────
    // INIT
    // ─────────────────────────────────────────────
    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p '" + decodeURIComponent(window.searchDir.replace("file://", "")) + "'"
        ]);
        view.forceActiveFocus();
        window.processMarkers();
        window.triggerColorExtraction();
    }

    Component.onDestruction: {
        resetSearch();
    }
}

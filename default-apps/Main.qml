import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Default Apps: reads installed apps and the current defaults through
// defaultapps.sh and writes new ones to the freedesktop mimeapps.list files (plus
// kdeglobals / xdg-terminals.list for the terminal), which Dolphin/KDE, GTK/GLib,
// xdg-open and the desktop portal all follow.
Item {
  id: root

  property var pluginApi: null

  readonly property string script: (pluginApi?.pluginDir ?? "") + "/defaultapps.sh"

  // An app is offered for a category if it supports any of its MIME types. Choosing
  // it sets every listed type it supports; types that already point to another app
  // on purpose are kept (see defaultapps.sh "set").
  readonly property var categories: [
    { key: "browser",  label: "Web browser",  icon: "world",
      mimes: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"] },
    { key: "files",    label: "File manager", icon: "folder",
      mimes: ["inode/directory"] },
    { key: "terminal", label: "Terminal",     icon: "terminal-2", terminal: true },
    { key: "text",     label: "Text editor",  icon: "file-text",
      mimes: ["text/plain", "text/markdown", "text/x-csrc", "text/x-c++src", "text/x-python",
              "application/x-shellscript", "application/json", "application/xml", "application/toml"] },
    { key: "image",    label: "Images",       icon: "photo",
      mimes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml", "image/bmp", "image/tiff", "image/avif"] },
    { key: "video",    label: "Videos",       icon: "movie",
      mimes: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg"] },
    { key: "audio",    label: "Music",        icon: "music",
      mimes: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/x-wav", "audio/aac", "audio/mp4", "audio/x-opus+ogg"] },
    { key: "pdf",      label: "PDF",          icon: "file-type-pdf",
      mimes: ["application/pdf"] },
    { key: "archive",  label: "Archives",     icon: "file-zip",
      mimes: ["application/zip", "application/x-tar", "application/x-compressed-tar", "application/x-7z-compressed",
              "application/vnd.rar", "application/gzip", "application/x-xz-compressed-tar"] },
    { key: "mail",     label: "Email",        icon: "mail",
      mimes: ["x-scheme-handler/mailto"] }
  ]

  property var apps: []           // [{ id, name, icon, mimes: [], cats: [], nodisplay }]
  property var defaults: ({})     // mime -> { source: "user"|"system"|"none", ids: [] }
  property var terminal: ({ id: "", source: "none" })
  property var warnings: []
  property bool loading: false

  property var jobs: []           // queued "set" commands, run one after another

  Component.onCompleted: refresh()

  // ----- reading -----

  function refresh() {
    if (scanProc.running) return;
    const mimes = [];
    for (const c of categories) if (c.mimes) mimes.push(...c.mimes);
    loading = true;
    scanProc.command = ["bash", script, "scan"].concat(mimes);
    scanProc.running = true;
  }

  function app(id) {
    return apps.find(a => a.id === id) || null;
  }

  function appName(id) {
    const a = app(id);
    return a ? a.name : id.replace(/\.desktop$/, "");
  }

  // Installed default for one MIME type: first installed app of the winning entry
  function resolved(mime) {
    const d = defaults[mime];
    if (!d) return { id: "", source: "none" };
    for (const id of d.ids) if (app(id)) return { id: id, source: d.source };
    return { id: d.ids[0] || "", source: d.ids.length ? d.source : "none" };
  }

  // Current default of a category: the first MIME type's app if set, otherwise the
  // app that handles most of the category's types
  function currentInfo(cat) {
    if (cat.terminal) return terminal;
    const first = resolved(cat.mimes[0]);
    if (first.id) return first;
    const count = {};
    let best = { id: "", source: "none" }, bestN = 0;
    for (const m of cat.mimes) {
      const r = resolved(m);
      if (!r.id) continue;
      count[r.id] = (count[r.id] || 0) + 1;
      if (count[r.id] > bestN) { bestN = count[r.id]; best = r; }
    }
    return best;
  }

  function current(cat) {
    return currentInfo(cat).id;
  }

  // Short explanation shown under each drop-down
  function status(cat) {
    const info = currentInfo(cat);
    if (!info.id)
      return cat.terminal ? "Not set" : "Not set: each app picks its own";
    if (!cat.terminal && !app(info.id))
      return "Default app is not installed";
    let s = info.source === "system" ? "System default" : "";
    if (!cat.terminal) {
      const others = cat.mimes.filter(m => { const r = resolved(m); return r.id && r.id !== info.id; }).length;
      if (others > 0)
        s += (s ? ", " : "") + others + (others === 1 ? " type opens" : " types open") + " with another app";
    }
    return s;
  }

  // Apps offered for a category, sorted by name: { key, name } for NComboBox
  function candidates(cat) {
    const list = [];
    for (const a of apps) {
      const ok = cat.terminal ? a.cats.indexOf("TerminalEmulator") >= 0
                              : cat.mimes.some(m => a.mimes.indexOf(m) >= 0);
      if (!ok) continue;
      // NoDisplay apps are valid handlers but usually helpers; only offer them
      // for the category's main type
      if (a.nodisplay && !cat.terminal && a.mimes.indexOf(cat.mimes[0]) < 0) continue;
      list.push({ key: a.id, name: a.nodisplay ? a.name + " (hidden app)" : a.name });
    }
    list.sort((x, y) => x.name.localeCompare(y.name));
    const cur = current(cat);
    if (cur && !list.some(e => e.key === cur))
      list.unshift({ key: cur, name: appName(cur) + (app(cur) ? "" : " (not installed)") });
    return list;
  }

  // ----- writing -----

  function setDefault(cat, appId) {
    if (!appId || appId === current(cat)) return;
    let cmd;
    if (cat.terminal) {
      cmd = ["bash", script, "set-terminal", appId];
    } else {
      const a = app(appId);
      const mimes = cat.mimes.filter(m => a && a.mimes.indexOf(m) >= 0);
      if (mimes.length === 0) mimes.push(cat.mimes[0]);
      cmd = ["bash", script, "set", appId, current(cat)].concat(mimes);
    }
    jobs = jobs.concat([{ label: cat.label, appId: appId, command: cmd }]);
    runNext();
  }

  function runNext() {
    if (setProc.running || jobs.length === 0) return;
    const job = jobs[0];
    jobs = jobs.slice(1);
    setProc.label = job.label;
    setProc.appId = job.appId;
    setProc.command = job.command;
    setProc.running = true;
  }

  Process {
    id: scanProc
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: exitCode => {
      root.loading = false;
      if (exitCode !== 0) {
        ToastService.showError("Default Apps", String(stderr.text).trim() || "Could not read installed apps");
        return;
      }
      const apps = [], defaults = {}, warnings = [];
      let terminal = { id: "", source: "none" };
      for (const line of String(stdout.text).split("\n")) {
        const f = line.split("\t");
        if (f[0] === "APP") {
          apps.push({ id: f[1], name: f[2], icon: f[3] || "",
                      mimes: (f[4] || "").split(";").filter(s => s),
                      cats: (f[5] || "").split(";").filter(s => s),
                      nodisplay: f[6] === "1" });
        } else if (f[0] === "DEFAULT") {
          defaults[f[1]] = { source: f[2], ids: (f[3] || "").split(";").filter(s => s) };
        } else if (f[0] === "TERMINAL") {
          terminal = { id: f[1] || "", source: f[2] || "none" };
        } else if (f[0] === "WARN") {
          warnings.push(f[1]);
        }
      }
      root.apps = apps;
      root.defaults = defaults;
      root.terminal = terminal;
      root.warnings = warnings;
    }
  }

  Process {
    id: setProc
    property string label: ""
    property string appId: ""
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: exitCode => {
      if (exitCode === 0) {
        const kept = String(stdout.text).split("\n").filter(l => l.startsWith("KEPT\t"));
        let msg = setProc.label + ": " + root.appName(setProc.appId);
        if (kept.length > 0)
          msg += " (kept " + kept.length + (kept.length === 1 ? " type that has" : " types that have") + " its own app)";
        ToastService.showNotice("Default Apps", msg);
      } else {
        ToastService.showError("Default Apps", String(stderr.text).trim() || "Could not set " + setProc.label);
      }
      if (root.jobs.length > 0) root.runNext();
      else root.refresh();
    }
  }

  IpcHandler {
    target: "plugin:default-apps"
    function refresh() { root.refresh(); }
  }
}

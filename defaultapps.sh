#!/usr/bin/env bash
# Backend for the "Default Apps" Noctalia plugin.
#
#   defaultapps.sh scan MIME...            installed apps + current defaults
#   defaultapps.sh set APP OLD MIME...     make APP the default for MIMEs (see below)
#   defaultapps.sh set-terminal APP        make APP the default terminal
#
# Defaults follow the freedesktop "Association between MIME types and applications"
# spec (mimeapps.list), which Dolphin/KDE, GTK/GLib, xdg-open and the desktop portal
# all implement. The script reads and writes those files itself instead of using
# xdg-mime, so it can tell an explicitly set default from a fallback guess, and handle
# desktop-specific files and [Removed Associations].
#
# scan prints tab-separated lines:
#   APP      <id> <name> <icon> <mimetypes;> <categories;> <nodisplay 0|1>
#   DEFAULT  <mime> <source: user|system|none> <app ids from the winning file;>
#   TERMINAL <id> <source: kde|xdg|none>
#   WARN     <message>
#
# set prints one line per MIME type:  SET <mime>  or  KEPT <mime> <current app>
set -euo pipefail

config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}

# Desktop names from XDG_CURRENT_DESKTOP, lowercased (spec: "niri" -> niri-mimeapps.list)
desktops() { tr ':' '\n' <<< "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]' | sed '/^$/d'; }

# mimeapps.list files in lookup order, each with "user" or "system"
mimeapps_files() {
  local d dir IFS_old=$IFS
  for d in $(desktops); do echo "user $config/$d-mimeapps.list"; done
  echo "user $config/mimeapps.list"
  IFS=:
  for dir in ${XDG_CONFIG_DIRS:-/etc/xdg}; do
    IFS=$IFS_old
    for d in $(desktops); do echo "system $dir/$d-mimeapps.list"; done
    echo "system $dir/mimeapps.list"
    IFS=:
  done
  IFS=$IFS_old
  for d in $(desktops); do echo "user $data/applications/$d-mimeapps.list"; done
  echo "user $data/applications/mimeapps.list"
  IFS=:
  for dir in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    IFS=$IFS_old
    for d in $(desktops); do echo "system $dir/applications/$d-mimeapps.list"; done
    echo "system $dir/applications/mimeapps.list"
    IFS=:
  done
  IFS=$IFS_old
}

# ini_get FILE SECTION KEY -> value (empty if missing)
ini_get() {
  [ -f "$1" ] || return 0
  awk -v sec="[$2]" -v key="$3" '
    /^\[/ { s = ($0 == sec); next }
    s && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
  ' "$1"
}

# ini_set FILE SECTION KEY VALUE -> set (or with VALUE "" remove) KEY in SECTION
ini_set() {
  local f=$1 tmp
  mkdir -p "$(dirname "$f")"; touch "$f"
  tmp=$(mktemp)
  awk -v sec="[$2]" -v key="$3" -v val="$4" '
    # blank lines are held back so a new key lands right after the last entry of the section
    function put()   { if (!done && val != "") print key "=" val; done = 1 }
    function flush() { for (; blanks > 0; blanks--) print "" }
    /^\[/ { if (s) put(); flush(); s = ($0 == sec); if (s) seen = 1; print; lines++; next }
    /^[[:space:]]*$/ { blanks++; next }
    s && index($0, key "=") == 1 { flush(); put(); next }
    { flush(); print; lines++ }
    END {
      if (s) put()
      flush()
      if (!seen && val != "") { if (lines) print ""; print sec; print key "=" val }
    }
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
}

app_dirs() {
  echo "$data/applications"
  local IFS=:
  for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do echo "$d/applications"; done
}

# Path of an installed desktop file id (first match, as the spec says)
app_path() {
  local id=$1 dir rel
  while read -r dir; do
    rel=${id//-//}            # ids may stand for subdirectories (kde-foo.desktop -> kde/foo.desktop)
    [ -f "$dir/$id" ] && { echo "$dir/$id"; return; }
    [ -f "$dir/$rel" ] && { echo "$dir/$rel"; return; }
  done < <(app_dirs)
}

scan_apps() {
  declare -A seen=()
  local dir f rel id
  while read -r dir; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' f; do
      rel=${f#"$dir"/}
      id=${rel//\//-}                    # desktop file id: subdirs joined with "-"
      [ -n "${seen[$id]:-}" ] && continue
      seen[$id]=1
      awk -v id="$id" -F= '
        /^\[/ { insec = ($0 == "[Desktop Entry]"); next }
        !insec { next }
        $1 == "Name" && name == "" { name = substr($0, 6) }
        $1 == "Icon"       { icon = substr($0, 6) }
        $1 == "MimeType"   { mime = substr($0, 10) }
        $1 == "Categories" { cats = substr($0, 12) }
        $1 == "Type"       { type = $2 }
        $1 == "Hidden"    && $2 == "true" { hidden = 1 }
        $1 == "NoDisplay" && $2 == "true" { nodisplay = 1 }
        END {
          # Hidden entries count as deleted. NoDisplay apps are still valid handlers
          # (other programs offer them too), so they are listed but marked.
          if (type == "Application" && !hidden && name != "")
            printf "APP\t%s\t%s\t%s\t%s\t%s\t%d\n", id, name, icon, mime, cats, nodisplay
        }' "$f"
    done < <(find -L "$dir" -name '*.desktop' -print0 2>/dev/null)
  done < <(app_dirs)
}

# Current default for a MIME type: the first mimeapps.list in lookup order that has
# an entry. Entries listing only uninstalled apps are skipped later by the plugin.
lookup_default() {
  local mime=$1 src file val
  while read -r src file; do
    val=$(ini_get "$file" "Default Applications" "$mime")
    if [ -n "$val" ]; then printf 'DEFAULT\t%s\t%s\t%s\n' "$mime" "$src" "$val"; return; fi
  done < <(mimeapps_files)
  printf 'DEFAULT\t%s\tnone\t\n' "$mime"
}

# Explicit user default (the file the user's desktop actually reads first)
user_default() {
  local d val
  for d in $(desktops); do
    val=$(ini_get "$config/$d-mimeapps.list" "Default Applications" "$1")
    [ -n "$val" ] && { echo "${val%%;*}"; return; }
  done
  val=$(ini_get "$config/mimeapps.list" "Default Applications" "$1")
  echo "${val%%;*}"
}

set_default() {  # set_default MIME APP
  local mime=$1 app=$2 d f removed
  ini_set "$config/mimeapps.list" "Default Applications" "$mime" "$app;"
  # A desktop-specific file (e.g. niri-mimeapps.list) wins over mimeapps.list,
  # so keep an existing entry there in sync instead of being overridden by it
  for d in $(desktops); do
    f="$config/$d-mimeapps.list"
    [ -n "$(ini_get "$f" "Default Applications" "$mime")" ] && ini_set "$f" "Default Applications" "$mime" "$app;"
  done
  # [Removed Associations] would make GLib ignore the app for this type
  for f in "$config/mimeapps.list" $(for d in $(desktops); do echo "$config/$d-mimeapps.list"; done); do
    removed=$(ini_get "$f" "Removed Associations" "$mime")
    if [[ ";$removed" == *";$app;"* ]]; then
      removed=$(sed "s/\(^\|;\)$(sed 's/[.]/\\./g' <<< "$app");/\1/" <<< "$removed")
      ini_set "$f" "Removed Associations" "$mime" "$removed"
    fi
  done
}

kde_get() { ini_get "$config/kdeglobals" General "$1"; }

refresh_kde() {
  # Rebuild KDE's app database so running KDE apps (Dolphin) see the change
  command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
}

case ${1:-} in
  scan)
    shift
    scan_apps
    for mime in "$@"; do lookup_default "$mime"; done
    term=$(kde_get TerminalService)
    if [ -n "$term" ]; then printf 'TERMINAL\t%s\tkde\n' "$term"
    elif [ -s "$config/xdg-terminals.list" ]; then printf 'TERMINAL\t%s\txdg\n' "$(grep -v '^#' "$config/xdg-terminals.list" | head -n1)"
    else printf 'TERMINAL\t\tnone\n'; fi
    command -v xdg-terminal-exec >/dev/null 2>&1 \
      || printf 'WARN\txdg-terminal-exec is not installed: the terminal choice only reaches KDE apps (Dolphin)\n'
    ;;

  set)
    # set APP OLD MIME...: the first MIME type is always set. Each other type is only
    # set if it has no explicit user default yet, already points to APP, or points to
    # OLD (the category's previous default) - so a deliberate per-type choice, e.g.
    # SVG -> Inkscape, is kept.
    app=${2:?app id}; old=${3-}; shift 3
    [ $# -gt 0 ] || { echo "no MIME types given" >&2; exit 2; }
    [ -n "$(app_path "$app")" ] || { echo "$app is not installed" >&2; exit 1; }
    first=1
    for mime in "$@"; do
      cur=$(user_default "$mime")
      if [ $first = 1 ] || [ -z "$cur" ] || [ "$cur" = "$app" ] || [ "$cur" = "$old" ]; then
        set_default "$mime" "$app"
        printf 'SET\t%s\n' "$mime"
      else
        printf 'KEPT\t%s\t%s\n' "$mime" "$cur"
      fi
      first=0
    done
    refresh_kde
    ;;

  set-terminal)
    app=${2:?app id}
    path=$(app_path "$app")
    [ -n "$path" ] || { echo "$app is not installed" >&2; exit 1; }
    # Full Exec line without field codes (%f, %U, ...), so wrappers like
    # "flatpak run org.x.Terminal" or "env FOO=1 term" keep working
    exec_cmd=$(awk -F= '/^\[/ { s = ($0 == "[Desktop Entry]") } s && $1 == "Exec" { print substr($0, 6); exit }' "$path" \
               | sed -E 's/%[a-zA-Z]//g; s/[[:space:]]+$//')
    [ -n "$exec_cmd" ] || exec_cmd=${app%.desktop}
    # KDE (Dolphin's "Open Terminal"): TerminalService wins, TerminalApplication for older code
    ini_set "$config/kdeglobals" General TerminalApplication "$exec_cmd"
    ini_set "$config/kdeglobals" General TerminalService "$app"
    # xdg-terminal-exec (used by GLib and launchers): desktop-specific list first
    for d in $(desktops); do
      [ -f "$config/$d-xdg-terminals.list" ] && printf '%s\n' "$app" > "$config/$d-xdg-terminals.list"
    done
    printf '%s\n' "$app" > "$config/xdg-terminals.list"
    refresh_kde
    ;;

  *)
    echo "usage: $0 scan MIME... | set APP OLD MIME... | set-terminal APP" >&2
    exit 2
    ;;
esac

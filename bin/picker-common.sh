# Shared helpers for the wallpaper and theme pickers. Sourced, not run.
#
# The scans run each time a picker opens, so the helpers return through
# REPLY rather than printing into $(...): a subshell per lookup per theme
# added more than half a second to opening the theme picker.

state_dir="$HOME/.local/state/omarchy"
current_link="$state_dir/current/background"
thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nooxshell/thumbnails"
mkdir -p "$thumb_dir"

is_video() {
  [[ ${1,,} =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]
}

is_image() {
  [[ ${1,,} =~ \.(jpg|jpeg|png|gif|bmp|webp|jxl)$ ]]
}

# REPLY = a copy of the image Qt can decode, at the given size. Qt has no
# JPEG-XL plugin, so a .jxl is converted once and cached (named after the
# file, and redone when the file is newer); anything else is used as is.
displayable() {
  local img="$1" size="$2"
  REPLY="$img"
  [[ -n $img && ${img,,} == *.jxl ]] || return 0
  REPLY="$thumb_dir/jxl-$size-${img//\//%}.jpg"
  if [[ ! -f $REPLY || $img -nt $REPLY ]]; then
    vipsthumbnail "$img" --size "$size" --smartcrop=centre -o "$REPLY" 2>/dev/null ||
      magick "$img" -resize "$size^" -gravity center -extent "$size" "$REPLY" 2>/dev/null
  fi
  [[ -f $REPLY ]] || REPLY=""
}

# Intros need OWE and the background handover that came with Omarchy 4.5,
# which also shipped omarchy-theme-bg-intro. On an older Omarchy an intro
# never starts, and the picker would wait out its timeout for nothing.
intros_supported() {
  command -v owe >/dev/null 2>&1 &&
    [[ -x ${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-theme-bg-intro ||
      -x /usr/share/omarchy/bin/omarchy-theme-bg-intro ]]
}

intros_enabled() {
  intros_supported &&
    [[ ! -f $state_dir/toggles/background-intros-off ]] &&
    [[ $(hyprctl -j getoption animations:enabled 2>/dev/null | jq -r '.bool' 2>/dev/null) != "false" ]]
}

# REPLY = the intro OWE plays for a background, backgrounds/intros/<stem>.<video>,
# found the way omarchy-theme-bg-boot-intro --resolve-only finds it.
resolve_intro() {
  local background="$1" stem ext
  REPLY=""
  [[ -L $background ]] && background=$(readlink -f "$background")
  [[ ${background,,} =~ \.(jpg|jpeg|png|bmp|webp)$ ]] || return 0
  stem=${background##*/}
  stem=${stem%.*}
  for ext in mp4 m4v mov webm mkv avi; do
    if [[ -f ${background%/*}/intros/$stem.$ext ]]; then
      REPLY="${background%/*}/intros/$stem.$ext"
      return 0
    fi
  done
}

# REPLY = the first frame of a background intro, which is where the picker's
# zoom lands so OWE can take over from it.
intro_first_frame() {
  local intro="$1" size="$2"
  REPLY="$thumb_dir/intro-$size-${intro//\//%}.jpg"
  if [[ ! -f $REPLY || $intro -nt $REPLY ]]; then
    ffmpeg -v error -y -i "$intro" -frames:v 1 \
      -vf "scale=${size%x*}:${size#*x}:force_original_aspect_ratio=increase" -q:v 2 "$REPLY" 2>/dev/null
  fi
  [[ -f $REPLY ]] || REPLY=""
}

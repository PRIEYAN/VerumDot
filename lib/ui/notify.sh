#!/usr/bin/env bash
# ui/notify.sh — desktop notifications.
#
# Wraps notify-send so that (a) a machine without a notification daemon
# degrades to a log line instead of an error on stderr, and (b) the
# replace-in-place hint is easy to use. That hint is what stops a slider
# from stacking forty notifications as it is dragged; every call site that
# wanted it previously had to spell out
# `-h string:x-canonical-private-synchronous:<tag>` by hand.

hypr::use core/log core/guard

readonly NOTIFY_APP="${NOTIFY_APP:-VerumDot}"

# notify::send [-u <urgency>] [-t <ms>] [-i <icon>] [-r <tag>] <title> [body]
#
#   -u  low | normal | critical          (default: normal)
#   -t  expiry in milliseconds
#   -i  icon name
#   -r  replace tag: a later notification with the same tag replaces the
#       earlier one rather than stacking beneath it
notify::send() {
  local urgency=normal timeout="" icon="" tag="" args=()

  while (( $# )); do
    case $1 in
      -u) urgency=$2; shift 2 ;;
      -t) timeout=$2; shift 2 ;;
      -i) icon=$2;    shift 2 ;;
      -r) tag=$2;     shift 2 ;;
      --) shift; break ;;
      *)  break ;;
    esac
  done

  local title=${1:-} body=${2:-}

  if ! guard::has notify-send; then
    log::info "notify: ${title}${body:+ — $body}"
    return 0
  fi

  args=(-a "$NOTIFY_APP" -u "$urgency")
  [[ -n $timeout ]] && args+=(-t "$timeout")
  [[ -n $icon    ]] && args+=(-i "$icon")
  [[ -n $tag     ]] && args+=(-h "string:x-canonical-private-synchronous:$tag")

  # An icon name the current theme lacks makes some daemons reject the whole
  # notification, so retry without it rather than losing the message.
  notify-send "${args[@]}" "$title" "$body" 2>/dev/null && return 0
  notify-send -a "$NOTIFY_APP" -u "$urgency" "$title" "$body" 2>/dev/null
}

# Convenience wrappers; the urgency is the whole difference and spelling it
# out at each call site was noise.
notify::info()  { notify::send -u normal   "$@"; }
notify::warn()  { notify::send -u critical "$@"; }

# notify::transient <tag> <title> [body] — a short, self-replacing toast, for
# feedback on a setting the user is actively changing.
notify::transient() {
  local tag=$1; shift
  notify::send -t 1500 -r "$tag" "$@"
}

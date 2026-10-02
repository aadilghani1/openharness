export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"
export npm_config_prefix="$HOME/.local"
export BROWSER=hn-browser
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec /usr/lib/harness-os/session
fi
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

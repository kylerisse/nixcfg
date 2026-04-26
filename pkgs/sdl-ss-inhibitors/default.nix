{ writeShellApplication
, glib
, lib
,
}:
writeShellApplication {
  name = "sdl-ss-inhibitors";
  runtimeInputs = [ glib ];
  text = ''
    : "''${DISPLAY:=:0}"
    export DISPLAY

    list=$(gdbus call --session \
      --dest org.gnome.SessionManager \
      --object-path /org/gnome/SessionManager \
      --method org.gnome.SessionManager.GetInhibitors 2>/dev/null) || {
      echo "Could not query org.gnome.SessionManager (no session bus?)" >&2
      exit 1
    }

    ids=$(printf '%s\n' "$list" | grep -oE 'Inhibitor[0-9]+' || true)

    if [ -z "$ids" ]; then
      echo "No inhibitors active."
      exit 0
    fi

    while IFS= read -r id; do
      app=$(gdbus call --session \
        --dest org.gnome.SessionManager \
        --object-path "/org/gnome/SessionManager/$id" \
        --method org.gnome.SessionManager.Inhibitor.GetAppId 2>/dev/null || echo '(unknown)')
      reason=$(gdbus call --session \
        --dest org.gnome.SessionManager \
        --object-path "/org/gnome/SessionManager/$id" \
        --method org.gnome.SessionManager.Inhibitor.GetReason 2>/dev/null || echo '(unknown)')
      flags=$(gdbus call --session \
        --dest org.gnome.SessionManager \
        --object-path "/org/gnome/SessionManager/$id" \
        --method org.gnome.SessionManager.Inhibitor.GetFlags 2>/dev/null || echo '(unknown)')
      printf '%s  app=%s  reason=%s  flags=%s\n' "$id" "$app" "$reason" "$flags"
    done <<< "$ids"
  '';

  meta = with lib; {
    description = "List active screensaver/idle inhibitors registered with the session manager";
    license = licenses.mit;
    maintainers = [ "kylerisse" ];
    mainProgram = "sdl-ss-inhibitors";
    platforms = platforms.linux;
  };
}

#!/usr/bin/env bash

# 1. Coupe immédiatement tous les lecteurs multimédia actifs
playerctl -a pause 2>/dev/null

# 2. Si un asset audio existe, on le joue en priorité
AUDIO_SAMPLE="$HOME/dotfiles/scripts/persona-killer/assets/mass_destruction_intro.ogg"

if [ -f "$AUDIO_SAMPLE" ]; then
    pw-play "$AUDIO_SAMPLE" &
fi

# 3. Notification test d'embuscade
notify-send -t 3000 -u critical "⚠️ EMBUSCADE ⚠️" "BABY BABY BABY BABY— YEAAAAAH !"
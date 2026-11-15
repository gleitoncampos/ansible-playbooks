# vibemix — junta microfone(s) + som do sistema numa única fonte de captura.
#
#   vibemix up            todas as saídas e entradas, e acompanha troca de dispositivo
#   vibemix up <trecho>   fixa numa saída só (ex.: vibemix up HyperX)
#   vibemix down          desmonta
#   vibemix status        o que está no ar
#   vibemix devices       lista saídas e entradas com estado
#
# Trocar o nome exibido: export VIBEMIX_LABEL=OutroNome antes do 'up'.

# O parser de argumentos de módulo do pipewire-pulse corta no primeiro espaço,
# com qualquer forma de aspas. Por isso o label vive sem espaços.
VIBEMIX_LABEL="${VIBEMIX_LABEL:-Vibe_Mix_mic+sistema}"
VIBEMIX_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vibemix.state"
VIBEMIX_WATCHER="$HOME/.config/vibemix/vibemix-watch.sh"
VIBEMIX_WATCHER_PID="${XDG_STATE_HOME:-$HOME/.local/state}/vibemix.watcher.pid"

_vibemix_modulos_do_mix() {
    # ids na ordem de desmontagem: remap primeiro, loopbacks, barramento por último.
    # Descobrir pelos argumentos é mais confiável que guardar id: sobrevive a
    # reboot, restart do pipewire e a loopback criado depois pelo watcher.
    pactl list short modules 2>/dev/null | awk -F'\t' '
        $2=="module-remap-source" && $3 ~ /source_name=vibemix/      {print 1 "\t" $1}
        $2=="module-loopback"     && $3 ~ /sink=vibemix_bus/         {print 2 "\t" $1}
        $2=="module-null-sink"    && $3 ~ /sink_name=vibemix_bus/    {print 3 "\t" $1}
    ' | sort -n | cut -f2
}

_vibemix_up() {
    if [ -f "$VIBEMIX_STATE" ] || [ -n "$(_vibemix_modulos_do_mix)" ]; then
        echo "vibemix: já está no ar. Use 'vibemix down' antes." >&2
        return 1
    fi

    local src desc alvo="$1" modo sink=""
    src=$(pactl get-default-source) || return 1
    case "$src" in vibemix*) echo "vibemix: default source já é um mix ($src)." >&2; return 1 ;; esac

    if [ -n "$alvo" ]; then
        modo=fixo
        sink=$(pactl list short sinks | awk -v p="$alvo" 'index($2,p){print $2; exit}')
        if [ -z "$sink" ]; then
            echo "vibemix: nenhuma saída casa com \"$alvo\". Disponíveis:" >&2
            pactl list short sinks | awk '{print "  " $2 "   [" $NF "]"}' >&2
            return 1
        fi
        local estado
        estado=$(pactl list short sinks | awk -v s="$sink" '$2==s{print $NF}')
        if [ "$estado" != "RUNNING" ]; then
            echo "vibemix: atenção — a saída escolhida está $estado, não RUNNING." >&2
            echo "  $sink" >&2
            echo "  Se o som sair por outro dispositivo, o mix grava silêncio." >&2
            pactl list short sinks | awk '$NF=="RUNNING"{print "  tocando agora: " $2}' >&2
        fi
    else
        modo=todos
    fi

    desc="${VIBEMIX_LABEL// /_}"
    [ "$desc" != "$VIBEMIX_LABEL" ] && echo "vibemix: espaço no nome não sobrevive ao pipewire-pulse; usando \"$desc\"." >&2

    pactl load-module module-null-sink sink_name=vibemix_bus channel_map=stereo \
        sink_properties=device.description="${desc}_barramento" >/dev/null || return 1

    local watcher_pid=""
    if [ "$modo" = todos ]; then
        rm -f "$VIBEMIX_WATCHER_PID"
        setsid bash "$VIBEMIX_WATCHER" >/dev/null 2>&1 &
        sleep 1   # deixa o watcher ligar os loopbacks antes de conferir
        # o PID vem do próprio watcher: $! aqui é o setsid, que já saiu
        watcher_pid=$(cat "$VIBEMIX_WATCHER_PID" 2>/dev/null)
    else
        pactl load-module module-loopback latency_msec=50 sink=vibemix_bus source="$sink.monitor" >/dev/null \
            || { _vibemix_desmonta_modulos; return 1; }
        pactl load-module module-loopback latency_msec=50 sink=vibemix_bus source="$src" >/dev/null \
            || { _vibemix_desmonta_modulos; return 1; }
    fi

    pactl load-module module-remap-source master=vibemix_bus.monitor source_name=vibemix \
        channel_map=front-left,front-right source_properties=device.description="$desc" >/dev/null \
        || { [ -n "$watcher_pid" ] && kill "$watcher_pid" 2>/dev/null; _vibemix_desmonta_modulos; return 1; }

    mkdir -p "$(dirname "$VIBEMIX_STATE")"
    {
        echo "ORIG_SOURCE=\"$src\""
        echo "MODO=\"$modo\""
        echo "WATCHER_PID=\"$watcher_pid\""
    } > "$VIBEMIX_STATE"

    pactl set-default-source vibemix || return 1

    echo "vibemix: no ar como \"$desc\" (modo $modo)"
    if [ "$modo" = todos ]; then
        echo "  capturando de:"
        pactl list short modules | grep 'module-loopback' | grep 'sink=vibemix_bus' \
            | sed -n 's/.*source=\([^[:space:]]*\).*/    \1/p'
        echo "  dispositivo novo entra sozinho enquanto o mix estiver no ar"
    else
        echo "  saída    : $sink"
        echo "  microfone: $src"
    fi
    echo "  captura  : vibemix (agora é o Default Source)"
}

_vibemix_desmonta_modulos() {
    local m falhou=0
    for m in $(_vibemix_modulos_do_mix); do
        pactl unload-module "$m" 2>/dev/null || { echo "vibemix: não consegui descarregar o módulo $m" >&2; falhou=1; }
    done
    return $falhou
}

_vibemix_down() {
    local ORIG_SOURCE MODO WATCHER_PID
    # shellcheck disable=SC1090
    [ -f "$VIBEMIX_STATE" ] && . "$VIBEMIX_STATE"

    # o watcher morre primeiro, senão ele recria os loopbacks que estamos tirando.
    # kill no grupo (-PID): o 'pactl subscribe' do pipeline não é filho direto.
    [ -z "$WATCHER_PID" ] && WATCHER_PID=$(cat "$VIBEMIX_WATCHER_PID" 2>/dev/null)
    if [ -n "$WATCHER_PID" ]; then
        kill -- "-$WATCHER_PID" 2>/dev/null || kill "$WATCHER_PID" 2>/dev/null
    fi
    pkill -f "$VIBEMIX_WATCHER" 2>/dev/null
    # confere que morreu mesmo; se insistir, KILL
    if [ -n "$WATCHER_PID" ]; then
        local i=0
        while kill -0 "$WATCHER_PID" 2>/dev/null && [ $i -lt 10 ]; do sleep 0.2; i=$((i+1)); done
        kill -0 "$WATCHER_PID" 2>/dev/null && kill -KILL -- "-$WATCHER_PID" 2>/dev/null
    fi
    rm -f "$VIBEMIX_WATCHER_PID"

    if [ -z "$(_vibemix_modulos_do_mix)" ] && [ ! -f "$VIBEMIX_STATE" ]; then
        echo "vibemix: não está no ar." >&2
        return 1
    fi

    _vibemix_desmonta_modulos || { echo "vibemix: estado mantido em $VIBEMIX_STATE." >&2; return 1; }

    if [ -n "$ORIG_SOURCE" ]; then
        pactl set-default-source "$ORIG_SOURCE" 2>/dev/null
        echo "vibemix: desmontado. Default Source de volta para $ORIG_SOURCE"
    else
        echo "vibemix: desmontado."
    fi
    rm -f "$VIBEMIX_STATE"
}

_vibemix_status() {
    local ids
    ids=$(_vibemix_modulos_do_mix)
    if [ -n "$ids" ]; then
        echo "vibemix: NO AR"
        [ -f "$VIBEMIX_STATE" ] && sed 's/^/  /' "$VIBEMIX_STATE"
        echo "  default source atual: $(pactl get-default-source)"
        echo "  capturando de:"
        pactl list short modules | grep 'module-loopback' | grep 'sink=vibemix_bus' \
            | sed -n 's/.*source=\([^[:space:]]*\).*/    \1/p'
        pgrep -f "$VIBEMIX_WATCHER" >/dev/null && echo "  watcher: ativo" || echo "  watcher: parado"
    else
        echo "vibemix: parado"
        echo "  default source atual: $(pactl get-default-source)"
        [ -f "$VIBEMIX_STATE" ] && echo "  (estado velho em $VIBEMIX_STATE — 'vibemix down' limpa)"
    fi
}

_vibemix_devices() {
    echo "saídas:"
    pactl list short sinks | awk '{print "  " $2 "   [" $NF "]"}'
    echo "padrão: $(pactl get-default-sink)"
    echo
    echo "entradas:"
    pactl list short sources | grep -v '\.monitor' | awk '{print "  " $2 "   [" $NF "]"}'
    echo "padrão: $(pactl get-default-source)"
}

vibemix() {
    case "$1" in
        up)      _vibemix_up "$2" ;;
        down)    _vibemix_down ;;
        status)  _vibemix_status ;;
        devices) _vibemix_devices ;;
        *)       echo "uso: vibemix {up [saída]|down|status|devices}" >&2; return 2 ;;
    esac
}

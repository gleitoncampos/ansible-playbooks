#!/usr/bin/env bash
# Mantém um loopback de cada saída e cada entrada real para dentro do vibemix_bus.
# Roda em segundo plano enquanto o mix está no ar; reage a dispositivo que aparece
# ou some (troca de fone, dongle plugado depois).

BUS=vibemix_bus
PIDFILE="${XDG_STATE_HOME:-$HOME/.local/state}/vibemix.watcher.pid"

# roda sob setsid, então é líder do próprio grupo: 'kill 0' leva junto o
# 'pactl subscribe' do pipeline, que senão fica órfão reparentado no init.
mkdir -p "$(dirname "$PIDFILE")"
echo $$ > "$PIDFILE"

# desarmar antes do 'kill 0': o sinal alcança o próprio processo e, com o trap
# ainda armado, o bash fica preso no handler e nunca sai.
_limpa() {
    trap - EXIT TERM INT
    rm -f "$PIDFILE"
    kill 0 2>/dev/null
    exit 0
}
trap _limpa EXIT TERM INT

_ja_ligados() {
    pactl list short modules 2>/dev/null \
        | grep 'module-loopback' \
        | grep "sink=$BUS" \
        | sed -n 's/.*source=\([^[:space:]]*\).*/\1/p'
}

_remove_mortos() {
    # dispositivo desplugado deixa o loopback para trás apontando para source
    # que não existe mais; trocando de fone várias vezes, isso acumula.
    local validas id fonte
    validas=$(pactl list short sources 2>/dev/null | cut -f2)
    while IFS=$'\t' read -r id _ args; do
        case "$args" in *sink=$BUS*) ;; *) continue ;; esac
        fonte=$(echo "$args" | sed -n 's/.*source=\([^[:space:]]*\).*/\1/p')
        [ -z "$fonte" ] && continue
        echo "$validas" | grep -qxF "$fonte" || pactl unload-module "$id" 2>/dev/null
    done < <(pactl list short modules 2>/dev/null | grep 'module-loopback')
}

_sincroniza() {
    local ligados nome
    _remove_mortos
    ligados=$(_ja_ligados)

    # saídas: captura o monitor de cada sink, menos o próprio barramento
    while IFS=$'\t' read -r _ nome _; do
        case "$nome" in vibemix*) continue ;; esac
        echo "$ligados" | grep -qxF "$nome.monitor" && continue
        pactl load-module module-loopback latency_msec=50 sink="$BUS" source="$nome.monitor" >/dev/null 2>&1
    done < <(pactl list short sinks 2>/dev/null)

    # entradas: microfones reais, sem monitor e sem os nós do próprio mix
    while IFS=$'\t' read -r _ nome _; do
        case "$nome" in vibemix*|*.monitor) continue ;; esac
        echo "$ligados" | grep -qxF "$nome" && continue
        pactl load-module module-loopback latency_msec=50 sink="$BUS" source="$nome" >/dev/null 2>&1
    done < <(pactl list short sources 2>/dev/null)
}

_sincroniza

pactl subscribe 2>/dev/null | while read -r linha; do
    case "$linha" in
        *"on sink"*|*"on source"*) _sincroniza ;;
    esac
done

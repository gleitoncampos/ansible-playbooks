# frente: lista as Frentes do Olimpo, escolhe por número, entra na pasta e abre o claude
frente() {
    local base=~/trabalho/olimpo-ecossistema/_trabalho/Frentes
    local dirs=() d
    for d in "$base"/*/; do dirs+=("$(basename "$d")"); done
    local PS3="Frente (número, Enter repete a lista, Ctrl+D sai): "
    select d in "${dirs[@]}"; do
        [ -n "$d" ] || { echo "Número inválido."; continue; }
        cd "$base/$d" && printf '\e]0;%s\a' "$d" && sleep 5 && claude
        return
    done
}

# organiza: entra na pasta de organização do Olimpo e abre o claude
organiza() {
    cd ~/trabalho/olimpo-ecossistema/_organizacao && sleep 5 && claude
}

# moiras: entra na pasta de manutenção do Olimpo e abre o claude
moiras() {
    cd ~/trabalho/olimpo-ecossistema/_manutencao && sleep 5 && claude
}

#!/bin/bash

################################################################################
# Script de Migração: Fiberhome (UNM2000) -> Huawei (MA5800)
#
# Principais Funcionalidades:
#   - Offset de PON: Ajuste automático de Fiberhome (1-16) para Huawei (0-15).
#   - Agrupamento por Slot: Otimização de comandos 'interface gpon' evitando 'quit' repetitivos.
#   - Suporte QinQ Stacking: Configuração de S-VLAN + C-VLAN com 'user-vlan 1001' e 'vlan attrib stacking'.
#   - VLAN Fallback: Criação automática de VLAN baseada em Slot/PON para ONUs sem serviço no .cfg.
#   - Limpeza de Lixo: Tratamento do bug '65535' e remoção de caracteres invisíveis no processamento.
#   - Expansão de Ranges: Suporte nativo para ranges de ONUs (ex: o 1,3-7,10) do arquivo Porterior.
#
# Parâmetros:
#   $1 - Arquivo CSV (ONUList_fix.csv)
#   $2 - Arquivo de configuração da OLT (.cfg)
#   $3 - (Opcional) Nome do Perfil QinQ (ex: QINQDHCP ou QINQIPOE)
#
# Saídas:
#   - saida.txt: Configuração de ONTs agrupadas por interface.
#   - add_service.txt: Comandos service-port (Modo Tradicional ou Stacking).
#   - add_vlans.txt: Criação de VLANs, Atributos e Uplink.
#   - onus_sem_vlan.txt: Log de ONUs que utilizaram VLAN Fallback (Slot+PON).
#
# Desenvolvedor: Joca
# GitHub: https://github.com/jocaplanaltonet
# Contato: joca@planaltonet.net.br | +55 81 98247-9774
# Versão: 1.0.1 (Estável) | Data: 16/04/2026
################################################################################

csv_file=$1
config_file=$2
perfil_qinq=$3

if [[ -z "$csv_file" || -z "$config_file" ]]; then
    echo "Uso: $0 <csv> <cfg> [perfil_qinq]"
    exit 1
fi

saida_onus="saida.txt"; saida_services="add_service.txt"; saida_vlans="add_vlans.txt"; saida_erros="onus_sem_vlan.txt"
> "$saida_onus"; > "$saida_services"; > "$saida_vlans"; > "$saida_erros"

expand_range() {
    local input=$1
    IFS=',' read -ra ADDR <<< "$input"
    for i in "${ADDR[@]}"; do
        [[ $i == *"-"* ]] && seq ${i%-*} ${i#*-} || echo $i
    done
}

ultimo_slot=""
total_onus=$(tail -n +2 "$csv_file" | wc -l)
contador=0; qtd_comum=0; qtd_qinq=0; qtd_sem_vlan=0
declare -A vlans_registradas

echo "🚀 Iniciando Processamento V8 (Agrupamento por Slot e Limpeza Total)..."

# O segredo está no sort -V (Version sort), que entende que 2 vem antes de 10
tail -n +2 "$csv_file" | sort -t',' -k2,2V -k3,3V -k4,4V | while IFS=',' read -r device_name slot pon onu sn; do
    
    # Limpeza absoluta de lixo das variáveis do CSV
    slot=$(echo "$slot" | tr -cd '[:digit:]'); pon=$(echo "$pon" | tr -cd '[:digit:]')
    onu=$(echo "$onu" | tr -cd '[:digit:]'); sn=$(echo "$sn" | tr -d '\r\n\t "' | xargs)
    device_name=$(echo "$device_name" | tr -d '\r\n\t"' | xargs)
    [[ -z "$slot" ]] && continue

    pon_hw=$((pon - 1))
    cvlan=""; svlan=""

    # 1. Busca VLAN Comum e Limpa 65535/Lixo
    while read -r line; do
        range_str=$(echo "$line" | grep -oP 'o \K[0-9,-]+')
        onus_na_linha=($(expand_range "$range_str"))
        pos=1
        for o in "${onus_na_linha[@]}"; do
            if [[ "$o" == "$onu" ]]; then
                temp=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="33024") print $(i+1)}' | cut -d',' -f$pos | sed 's/65535//g' | tr -cd '[:digit:]')
                [[ -n "$temp" ]] && cvlan="$temp"
                break 2
            fi
            ((pos++))
        done
    done < <(grep "set ep sl $slot p $pon o " "$config_file" | grep "33024")

    # 2. Busca S-VLAN
    if [[ -n "$perfil_qinq" ]]; then
        while read -r line; do
            range_str=$(echo "$line" | grep -oP 'o \K[0-9,-]+')
            onus_na_linha=($(expand_range "$range_str"))
            pos=1
            for o in "${onus_na_linha[@]}"; do
                if [[ "$o" == "$onu" ]]; then
                    temp=$(echo "$line" | awk -v p="$perfil_qinq" '{for(i=1;i<=NF;i++) if($i==p) print $(i+1)}' | cut -d',' -f$pos | sed 's/65535//g' | tr -cd '[:digit:]')
                    [[ -n "$temp" ]] && svlan="$temp"
                    break 2
                fi
                ((pos++))
            done
        done < <(grep "set ep sl $slot p $pon o " "$config_file" | grep "$perfil_qinq")
    fi

    # --- LÓGICA DE VLAN (FALLBACK) ---
    if [[ -z "$cvlan" && -z "$svlan" ]]; then
        ((qtd_sem_vlan++))
        pon_format=$(printf "%02d" $pon)
        v_srv="${slot}${pon_format}"; v_native=$v_srv; v_type="comum"
        echo "Fallback $v_srv para SN:$sn (Sl:$slot P:$pon)" >> "$saida_erros"
    elif [[ -n "$svlan" ]]; then
        ((qtd_qinq++)); v_srv=$svlan; v_native=${cvlan:-1001}; v_type="qinq"
    else
        ((qtd_comum++)); v_srv=$cvlan; v_native=$cvlan; v_type="comum"
    fi

    # --- ESCRITA NO SAIDA.TXT (O PULO DO GATO DO AGRUPAMENTO) ---
    if [[ "$slot" != "$ultimo_slot" ]]; then
        # Se não é o primeiro slot do arquivo, fecha o anterior
        if [[ -n "$ultimo_slot" ]]; then
            echo " quit" >> "$saida_onus"
            echo "!" >> "$saida_onus"
        fi
        # Abre a interface do novo slot
        echo "interface gpon 0/$slot" >> "$saida_onus"
        ultimo_slot=$slot
    fi

    # Adiciona a ONT sem sair da interface
    echo " ont add $pon_hw $onu sn-auth $sn omci ont-lineprofile-name MIG_FH ont-srvprofile-name MIG_FH desc \"$device_name\"" >> "$saida_onus"
    echo " ont port native-vlan $pon_hw $onu eth 1 vlan $v_native" >> "$saida_onus"

    # --- SERVICE PORT E VLAN UPLINK (Sempre linha única) ---
    if [ "$v_type" = "qinq" ]; then
        echo "service-port vlan $v_srv gpon 0/$slot/$pon_hw ont $onu gemport 1 multi-service user-vlan 1001 tag-transform translate-and-add inner-vlan $v_native" >> "$saida_services"
    else
        echo "service-port vlan $v_srv gpon 0/$slot/$pon_hw ont $onu gemport 1 multi-service user-vlan $v_srv tag-transform translate" >> "$saida_services"
    fi

    if [[ -z "${vlans_registradas[$v_srv]}" ]]; then
        { echo "vlan $v_srv smart"; [ "$v_type" = "qinq" ] && echo "vlan attrib $v_srv stacking"; echo "port vlan $v_srv 0/8 0"; } >> "$saida_vlans"
        vlans_registradas[$v_srv]=1
    fi

    ((contador++))
    echo -ne "🔄 [$contador/$total_onus] Slot Atual:$slot | Comum:$qtd_comum QinQ:$qtd_qinq Fallback:$qtd_sem_vlan\r"
done

# Fecha o último slot do arquivo
echo " quit" >> "$saida_onus"
echo "!" >> "$saida_onus"

echo -e "\n\n✅ Finalizado! Agora o disse-me-disse acabou: Slots agrupados e arquivos limpos."

#!/bin/bash
clear

################################################################################
# Script de Migração de ONUs da OLT Fiberhome(RP1000 ou Porterior) para OLT Huawei (MA5800)
#
# Objetivo:
#   - Processar arquivo CSV com dados das ONUs Exportada do UNM2000
#   - Extrair informações do arquivo de configuração da OLT (.cfg)
#   - Gerar comandos para configuração das ONUs e serviços, incluindo suporte
#     para VLANs padrão e QINQIPOE (quando fornecido)
#
# Parâmetros:
#   $1 - Arquivo CSV contendo a lista de ONUs
#   $2 - Arquivo de configuração da OLT (.cfg)
#   $3 - (Opcional) Nome do serviço QINQIProfile para ativar extração de VLANs QINQ
#
# Saídas:
#   - saida.txt: comandos para configuração das ONUs
#   - add_service_hw.txt: comandos service-port para ONUs
#   - add_vlans.txt: comandos VLAN para uplink
#   - ont-profiles.txt: perfis ont-lineprofile e ont-srvprofile fixos
#   - resumo.txt: informações de fallback (se houver)
#
# Desenvolvedor:
#   Joca
#   GitHub: https://github.com/jocaplanaltonet
#   Contato: joca@planaltonet.net.br
#   Contato: +55 81 98247 9774
#
# Data: 2025-08-06
################################################################################


# Parâmetros obrigatórios: CSV e CFG
if [[ $# -lt 2 ]]; then
  echo "Uso: $0 arquivo.csv arquivo.cfg [qinqsrvcname]"
  exit 1
fi

csv_file="$1"
cfg_file="$2"
qinqsrvcname="${3:-}"  # opcional

output_file="saida.txt"
summary_file="resumo.txt"
service_file="add_service_hw.txt"
vlan_file="add_vlans.txt"
ont_profile_file="ont-profiles.txt"
hw_uplink="0/8 0"

> "$output_file"
> "$summary_file"
> "$service_file"
> "$vlan_file"
> "$ont_profile_file"

declare -A vlan_written
declare -A onu_has_qinq   # marca ONUs que já tiveram QINQIPOE para evitar service-port padrão

expand_ranges() {
  local input=$1
  local output=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}
      end=${BASH_REMATCH[2]}
      for ((i=start; i<=end; i++)); do
        output+=($i)
      done
    else
      output+=($part)
    fi
  done
  echo "${output[@]}"
}

fallback_onus=()
cont_ok=0
cont_fallback=0
cont_qinq=0
line_count=$(tail -n +2 "$csv_file" | wc -l)
processed=0

# Função para extrair VLAN padrão para uma ONU na linha padrão
get_vlan_standard() {
  local slot=$1
  local pon=$2
  local onu=$3
  local vlan=""

  mapfile -t lines < <(grep -E "set ep sl $slot p $pon o " "$cfg_file")
  for line in "${lines[@]}"; do
    onus_field=$(echo "$line" | grep -oP 'o\s+\K[^ ]+')
    expanded_onus=($(expand_ranges "$onus_field"))

    pos=0
    for i in "${!expanded_onus[@]}"; do
      if [[ "${expanded_onus[$i]}" == "$onu" ]]; then
        pos=$((i+1))
        break
      fi
    done

    if (( pos > 0 )); then
      vlan_chunk=$(echo "$line" | grep -oP '33024\s+\K[0-9,]+')
      IFS=',' read -ra vlan_array <<< "$vlan_chunk"
      if (( ${#vlan_array[@]} >= pos )); then
        candidate_vlan="${vlan_array[$((pos-1))]}"
        candidate_vlan=$(echo "$candidate_vlan" | tr -d '\r\t ')
        if [[ "$candidate_vlan" != "65535" && "$candidate_vlan" != "" ]]; then
          vlan="$candidate_vlan"
          break
        fi
      fi
    fi
  done
  echo "$vlan"
}

# Função para extrair VLAN e svlan para uma ONU na linha QINQIPOE
get_vlan_qinq() {
  local slot=$1
  local pon=$2
  local onu=$3
  local qinq_vlan=""
  local qinq_svlan=""

  mapfile -t lines < <(grep -E "set ep sl $slot p $pon o " "$cfg_file" | grep "$qinqsrvcname")
  for line in "${lines[@]}"; do
    # extrai lista ONUs da linha
    onus_field=$(echo "$line" | grep -oP 'o\s+\K[^ ]+')
    expanded_onus=($(expand_ranges "$onus_field"))

    pos=0
    for i in "${!expanded_onus[@]}"; do
      if [[ "${expanded_onus[$i]}" == "$onu" ]]; then
        pos=$((i+1))
        break
      fi
    done

    if (( pos > 0 )); then
      # extrai lista svlan (após QINQIPOE)
      svlan_chunk=$(echo "$line" | grep -oP "$qinqsrvcname\s+\K[0-9,]+")
      IFS=',' read -ra svlan_array <<< "$svlan_chunk"
      if (( ${#svlan_array[@]} >= pos )); then
        qinq_svlan="${svlan_array[$((pos-1))]}"
        qinq_svlan=$(echo "$qinq_svlan" | tr -d '\r\t ')
      fi

      # inner-vlan será a VLAN padrão (clear_vlan)
      clear_vlan=$(get_vlan_standard "$slot" "$pon" "$onu")
      qinq_vlan="$qinq_svlan"

      # retorna svlan e clear_vlan (inner-vlan)
      echo "$qinq_vlan $clear_vlan"
      return
    fi
  done
  echo ""  # não encontrado
}

tail -n +2 "$csv_file" | while IFS=',' read -r DeviceName slotNumber PonNumber OnuNumber PhysicalAddress; do
  DeviceName=$(echo "$DeviceName" | tr -d '\r\t' | xargs)
  slotNumber=$(echo "$slotNumber" | tr -d '\r\t' | xargs)
  PonNumber=$(echo "$PonNumber" | tr -d '\r\t' | xargs)
  OnuNumber=$(echo "$OnuNumber" | tr -d '\r\t' | xargs)
  PhysicalAddress=$(echo "$PhysicalAddress" | tr -d '\r\t' | xargs)

  if [[ -z "$slotNumber" || -z "$PonNumber" || -z "$OnuNumber" || -z "$PhysicalAddress" || "$DeviceName" =~ "Export Time" ]]; then
    continue
  fi

  # Primeiro verifica QINQIPOE se parâmetro informado
  has_qinq=0
  qinq_svlan=""
  clear_vlan=""
  if [[ -n "$qinqsrvcname" ]]; then
    read -r qinq_svlan clear_vlan <<< $(get_vlan_qinq "$slotNumber" "$PonNumber" "$OnuNumber")
    if [[ -n "$qinq_svlan" && -n "$clear_vlan" ]]; then
      has_qinq=1
      ((cont_qinq++))
      onu_has_qinq["$slotNumber-$PonNumber-$OnuNumber"]=1
    fi
  fi

  if (( has_qinq == 1 )); then
    # Gera config da ONU padrão (sem vlan pois QINQIPOE ONU não usa service-port padrão)
    {
      echo "interface gpon 0/$slotNumber"
      echo "ont add $PonNumber $OnuNumber sn-auth $PhysicalAddress omci ont-lineprofile-name 100 ont-srvprofile-id 100 desc \"$DeviceName\""
      echo "ont port native-vlan $PonNumber $OnuNumber eth 1 vlan $clear_vlan priority 0"
      echo "quit"
      echo ""
    } >> "$output_file"

    # Gera service-port QINQIPOE
    echo "service-port vlan $qinq_svlan gpon 0/$slotNumber/$PonNumber ont $OnuNumber gemport 1 multi-service user-vlan 1001 tag-transform translate-and-add inner-vlan $clear_vlan inner-priority 0" >> "$service_file"

    # VLAN para uplink
    if [[ -z "${vlan_written[$qinq_svlan]}" ]]; then
      {
        echo "vlan $qinq_svlan smart"
        echo "vlan desc $qinq_svlan description \"${slotNumber}_${PonNumber}\""
        echo "port vlan $qinq_svlan $hw_uplink"
        echo ""
      } >> "$vlan_file"
      vlan_written["$qinq_svlan"]=1
    fi

    ((cont_ok++))  # Conta ONU como ok (vlan extraída)
  else
    # Caso não tenha QINQIPOE, extrai VLAN padrão
    clear_vlan=$(get_vlan_standard "$slotNumber" "$PonNumber" "$OnuNumber")
    if [[ -z "$clear_vlan" ]]; then
      clear_vlan="${slotNumber}${PonNumber}"
      ((cont_fallback++))
      echo "⚠ ONU $slotNumber/$PonNumber/$OnuNumber (SN: $PhysicalAddress) gerada via fallback - não encontrada ou VLAN inválida no .cfg" >> "$summary_file"
      fallback_onus+=("$PhysicalAddress")
    else
      ((cont_ok++))
    fi

    # Gera config da ONU padrão
    {
      echo "interface gpon 0/$slotNumber"
      echo "ont add $PonNumber $OnuNumber sn-auth $PhysicalAddress omci ont-lineprofile-name 100 ont-srvprofile-id 100 desc \"$DeviceName\""
      echo "ont port native-vlan $PonNumber $OnuNumber eth 1 vlan $clear_vlan priority 0"
      echo "quit"
      echo ""
    } >> "$output_file"

    # Gera service-port padrão somente se ONU não está em QINQIPOE
    key="$slotNumber-$PonNumber-$OnuNumber"
    if [[ -z "${onu_has_qinq[$key]}" ]]; then
      echo "service-port vlan $clear_vlan gpon 0/$slotNumber/$PonNumber ont $OnuNumber gemport 1 multi-service user-vlan $clear_vlan tag-transform translate" >> "$service_file"
    fi

    # VLAN para uplink padrão
    if [[ -z "${vlan_written[$clear_vlan]}" ]]; then
      {
        echo "vlan $clear_vlan smart"
        echo "vlan desc $clear_vlan description \"${slotNumber}_${PonNumber}\""
        echo "port vlan $clear_vlan $hw_uplink"
        echo ""
      } >> "$vlan_file"
      vlan_written["$clear_vlan"]=1
    fi
  fi

  ((processed++))
  percent=$(( processed * 100 / line_count ))
  echo -ne "🔄 Processando: $processed de $line_count ONUs... [$percent%] SN: $PhysicalAddress\r"

done

echo -e "\n✅ Processamento concluído."

# Somente lista as ONUs fallback no resumo, sem as contagens
if (( cont_fallback > 0 )); then
    echo -e "\nLista de ONUs geradas via fallback - não encontradas ou VLAN inválida no .cfg:" >> "$summary_file"
    for sn in "${fallback_onus[@]}"; do
        echo "- $sn" >> "$summary_file"
    done
fi

# Cria o arquivo ont-profiles.txt com os perfis fixos
cat > "$ont_profile_file" <<EOF
ont-lineprofile gpon profile-id 100 profile-name "MIG_FH"
  mapping-mode port
  tcont 4 dba-profile-id 500
  gem add 1 eth tcont 4
  gem mapping 1 0 eth 1
  commit
  quit

ont-srvprofile gpon profile-id 100 profile-name "MIG_FH"
  ont-port eth 1 
  port vlan eth 1 transparent
  commit
EOF

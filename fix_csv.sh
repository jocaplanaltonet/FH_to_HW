#!/bin/bash

# Função de Ajuda
show_help() {
    echo "================================================================="
    echo "   Filtro de Colunas UNM2000 para Migração Huawei"
    echo "================================================================="
    echo "Uso:"
    echo "  $0 [arquivo_entrada.csv]"
    echo ""
    echo "Exemplo:"
    echo "  $0 ONUList.csv  -> Gera: ONUList_fix.csv"
    echo ""
    echo "Argumentos:"
    echo "  arquivo_entrada.csv : O arquivo exportado do UNM2000"
    echo "================================================================="
}

# Verifica se o argumento foi passado ou se pediu ajuda
if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Configuração de arquivos
INPUT_FILE="$1"

# Extrai o nome sem a extensão e define o novo nome de saída
FILENAME_BASE=$(basename "$INPUT_FILE" | cut -f 1 -d '.')
OUTPUT_FILE="${FILENAME_BASE}_fix.csv"

# Verifica se o arquivo de entrada existe
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "❌ Erro: O arquivo '$INPUT_FILE' não foi encontrado."
    exit 1
fi

# Nomes exatos das colunas que queremos buscar no CSV do UNM2000
COL1="Device Name"
COL2="Slot Number"
COL3="PON Number"
COL4="ONU Number"
COL5="Physical Address"

echo "🔄 Processando: $INPUT_FILE"
echo "📂 Destino: $OUTPUT_FILE"

# O AWK faz a busca dinâmica pelos nomes das colunas
awk -F',' -v c1="$COL1" -v c2="$COL2" -v c3="$COL3" -v c4="$COL4" -v c5="$COL5" '
BEGIN { 
    OFS="," 
}
NR==1 {
    # Limpa aspas e caracteres invisíveis do Windows (^M)
    gsub(/"/, "", $0);
    gsub(/\r/, "", $0);
    
    # Mapeia a posição de cada coluna pelo nome
    for (i=1; i<=NF; i++) {
        if ($i == c1) p1=i;
        if ($i == c2) p2=i;
        if ($i == c3) p3=i;
        if ($i == c4) p4=i;
        if ($i == c5) p5=i;
    }

    # Verifica se todas as colunas obrigatórias foram localizadas
    if (!p1 || !p2 || !p3 || !p4 || !p5) {
        print "❌ Erro: Colunas não encontradas! Verifique o cabeçalho do arquivo." > "/dev/stderr";
        exit 1;
    }
    
    # Escreve o novo cabeçalho limpo
    print "DeviceName", "slotNumber", "PonNumber", "OnuNumber", "PhysicalAddress";
    next;
}
{
    # Limpa aspas e lixo da linha de dados
    gsub(/"/, "", $0);
    gsub(/\r/, "", $0);
    
    # Imprime apenas as colunas desejadas nas posições corretas
    if ($p1 != "") {
        print $p1, $p2, $p3, $p4, $p5
    }
}' "$INPUT_FILE" > "$OUTPUT_FILE"

# Verifica se o comando anterior deu certo
if [ $? -eq 0 ]; then
    echo "✅ Sucesso! Gerado: $OUTPUT_FILE"
else
    echo "❌ Ocorreu um erro no processamento."
fi

# Changelog - Migrador Fiberhome para Huawei

## [1.0.3] - 2026-04-16

### Adicionado
- **Perfil DBA Automático**: Inclusão da criação do `dba-profile` (ID 100, Nome: MIG_FH) com largura de banda de 1G (type4 max 1024000) no topo do arquivo de perfis.
- **Vinculação de TCONT**: O `ont-lineprofile` agora utiliza automaticamente o `dba-profile-name "MIG_FH"` para garantir a sincronia dos recursos de banda.

### Corrigido
- **Limpeza de Caracteres Especiais**: Removido o caractere separador `!` de todos os arquivos gerados (`.txt`), tornando-os 100% compatíveis com scripts de automação CLI (Netmiko/Paramiko).
- **Ajuste de Fluxo GPON**: Removido o excesso de comandos `quit` e centralizada a lógica de saída por Slot, otimizando o tempo de execução na OLT.

### Alterado
- **Cabeçalho de Identificação**: Atualização do desenvolvedor para apenas **Joca**, conforme solicitado.
- **Perfis Adaptativos**: O `ont-srvprofile` foi ajustado para modo `adaptive`, permitindo que ONTs de diferentes modelos (1, 2 ou 4 portas) sejam provisionadas sem erro de compatibilidade de hardware.

---

## [1.0.2] - 2026-04-16

### Adicionado
- **Geração de Perfis de ONT**: Criação automática do arquivo `ont-profiles.txt` contendo o Line Profile e Service Profile necessários para o provisionamento inicial.
- **Fallback de VLAN por Slot/PON**: Implementada a lógica de criação de VLAN dinâmica (Ex: Slot 17 Pon 1 -> VLAN 1701) para ONUs que não possuem serviço mapeado no arquivo `.cfg`.

### Corrigido
- **Extermínio do Bug 65535**: Implementada filtragem pesada via `tr -cd '[:digit:]'` para impedir que lixo eletrônico da Fiberhome quebrasse os comandos `service-port` e `vlan smart`.
- **Ordenação Numérica (Sort -V)**: Corrigida a lógica de leitura do CSV; agora o script processa Slots em ordem natural (1, 2, 3...) em vez de ordem alfanumérica (1, 10, 11...).

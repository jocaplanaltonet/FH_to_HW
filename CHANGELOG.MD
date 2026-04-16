# Changelog - Migrador Fiberhome para Huawei

## [1.0.1] - 2026-04-16

### Adicionado
- **VLAN Fallback Dinâmica**: Sistema que gera automaticamente VLANs baseadas no Slot/PON (ex: Slot 17 Pon 1 -> VLAN 1701) para ONUs sem serviço mapeado no `.cfg`.
- **Log de Exceções**: Criação do arquivo `onus_sem_vlan.txt` para rastrear seriais e posições das ONTs que usaram a regra de fallback.

### Corrigido
- **Bug do 65535**: Implementada limpeza profunda via `sed` e `tr` para eliminar valores residuais da Fiberhome que quebravam os comandos da Huawei.
- **QINQ Stacking**: Fixado o comando de `service-port` para usar `user-vlan 1001` e `vlan attrib stacking`, garantindo compatibilidade com QinQ em OLTs MA5800.
- **Agrupamento de Slots**: Corrigida a lógica de interfaces; agora o script agrupa todas as ONTs de um slot e só emite o comando `quit` quando o slot realmente muda.
- **Ordenação Numérica**: Ajustado o processamento do CSV para seguir a ordem natural dos Slots (1, 2, 3... em vez de 1, 10, 11).

### Alterado
- **Cabeçalho Profissional**: Atualização das informações de licença, desenvolvedor e parâmetros de uso no script principal.
- **Otimização de Linha Única**: Garantia de que comandos `service-port` e `vlan smart` saiam em uma única linha, sem quebras indesejadas.

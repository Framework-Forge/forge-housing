# Segurança residencial

O proprietário contrata Alarme residencial ou Segurança monitorada em Serviços e configura em Segurança. Os valores iniciais estão em shared/security.lua: alarme 5000, segurança 25000, câmeras 1500. O upgrade desconta o alarme já contratado. Pagamentos usam PRBridge (banco ou item money).

O ponto físico de desarme é o prop ba_prop_battle_secpanel, posicionado e reposicionado pelo proprietário com o gizmo do PRBridge. Usa o modo `Config.Interactions.general` e o desafio Circuit Breaker. O modelo precisa estar disponível na versão do jogo instalada. Cada câmera usa Brute Force para ser desativada individualmente. Falhar ou cancelar não desarma. Desativar câmera não cancela um incidente existente. Os desafios exigem o provedor Glitch no PRBridge e glitch-minigames iniciado.

A segurança monitora entradas e câmeras colocadas (15 metros), excluindo proprietário, administradores e portadores de chave. A prioridade é entrada/área interna. Câmeras não são obrigatórias. Desligue ambos os controles para festas. O alarme básico avisa o proprietário online; o evento de servidor forge-housing:security:ownerAlert está disponível para integrar o canal definitivo de notificação posteriormente. O serviço monitorado usa PS Dispatch depois de 120 segundos sem desarme. Sem policiais em serviço, tenta entregar quando houver destinatário.

Compre câmeras na categoria Câmeras de segurança da loja de móveis. Somente móveis visíveis participam da detecção. A lista permite visualizar, pesquisar, configurar direção, campo de visão padrão 50.0 do Forge Police, sem zoom configurável e coordenadas da lente (até três metros do objeto). ENTER durante a visualização registra a miniatura pelo mesmo fluxo screenshot-basic/screencapture usado no Forge Police. Os valores de câmera enviados às funções nativas usam números de ponto flutuante. Configurações antigas de zoom são ignoradas; a roda do mouse não altera o campo de visão. A visão aplica a correção de direção de 180 graus usada pelo Forge Police e usa a posição da lente cadastrada ou do prop, como o Forge Police. A sobreposição usa moldura nativa, nome da câmera, indicador AO VIVO e REC com quadrado vermelho piscando. O filtro padrão é scanline_cam_cheap com intensidade 1.0. A Forge HUD fica oculta durante a visualização e volta ao sair. Não há limites configuráveis de direção; a rotação horizontal é livre. Brute Force desabilita apenas aquela câmera, que deve ser reparada presencialmente com a interação configurada e o desafio Firewall Pulse. Salvar configurações não altera seu estado. Feeds e permissões são revalidados durante a visualização.

Estado persistido em data/security_state.json, privado do servidor; remoção do imóvel elimina o registro. Incidentes têm horário absoluto e permanecem após reinício. Modificações usam revisão, checagem de acesso e confirmação de gravação. Nenhuma alteração foi feita em ox_doorlock, PRBridge, Forge Police ou PS Dispatch.

## Validação no jogo
1. Reinicie forge-housing e depois forge-realtor em momento adequado; não foram reiniciados automaticamente.
2. Entre como proprietário, contrate, posicione o ponto e ative o serviço.
3. Entre com um visitante sem chave: alarme avisa o proprietário; monitoramento conta 120 segundos e dispara PS Dispatch.
4. Complete Circuit Breaker antes de 120 segundos: cancela o incidente e desarma ambos. Cancelamento/falha mantém a contagem.
5. Com duas câmeras, use Brute Force em uma: somente ela fica indisponível; a outra e o incidente continuam.
6. Confira visão, zoom, limites, miniatura, sincronização entre dois jogadores e persistência após reinício.

Luac valida sintaxe. Os testes Lua simulam pagamentos, permissões, temporizadores, desafios e persistência; controles nativos, renderização e minigames precisam da validação dentro do FiveM.

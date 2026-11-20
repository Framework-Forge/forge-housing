# Interiores bob74 e pares de portas

O catálogo `shared/ipl_catalog.lua` acrescenta 116 opções ao `Config.Shells`. O Realtor usa esse mesmo catálogo, sem duplicá-lo. As entradas `IPL · …` são interiores em coordenadas fixas; os shells existentes continuam sendo objetos criados na posição da propriedade.

## Cadastro e edição

1. Escolha MLO, Shell ou IPL na etapa Interior. Para Shell/IPL, PGUP/PGDN alternam os modelos; WASD e mouse permitem visitar. ENTER confirma e BACKSPACE cancela.
2. Para Shell, após escolher o modelo, posicione com a câmera livre do PRBridge: WASD desloca, Q/E ajustam altura, Z/X giram a shell; ENTER confirma e BACKSPACE cancela. Depois configure a entrada A e sua saída interna, confirmando o ponto com ENTER.
3. Para cada entrada adicional B, C etc., defina sua saída interna pelo botão correspondente. Mantenha as saídas pelo menos um metro afastadas.
4. Salve. Entrar por A leva à saída A; usar a saída B leva somente à entrada B. O par pertence à porta, não ao jogador.
5. Para mover os acessos depois, abra Gerenciar imóveis → Gerenciar → Pares de entrada e saída. Defina os pontos e pressione Salvar no rodapé.

Até 16 pares. A posição e direção são capturadas onde o personagem está. A localização interna não depende mais exclusivamente do doorOffset padrão.

As casas antigas continuam com o ponto padrão até seus pares serem configurados. Apartamentos antigos mantêm a saída existente. MLOs continuam com portas físicas; esses pares são para os interiores acessados por teleporte.

## Persistência e sincronização

Os pares usam o JSON door_data existente; não há migração SQL. As posições internas dos shells são relativas ao shell; as de IPL são coordenadas do mundo. A origem do shell é preservada quando a entrada externa muda, sem deslocar os móveis. O servidor rejeita edições desatualizadas e gravações concorrentes, persiste antes de avisar todos os clientes e recria os pontos de saída dos ocupantes.

Casas comuns compartilham o mundo no bucket 0. Apenas apartamentos antigos atribuídos automaticamente mantêm seu isolamento por compatibilidade. Dois jogadores na mesma propriedade podem entrar por pares diferentes. O carregamento não reaplica estilos periodicamente.

A seleção do modelo do interior no formulário de edição fica somente para consulta: reposicionar portas não migra os móveis nem transforma um shell existente em outro interior. Escolha o modelo no cadastro.

## Catálogo e limites

As entradas registram a origem do arquivo bob74, export, interior e build mínimo. Estão incluídos interiores residenciais, estabelecimentos e partes internas separadas (como andares de garagem e depósitos). Variações decorativas do mesmo interior não são imóveis diferentes. Recursos exclusivamente externos, correções de mapa, placas, grafites, água, navios e outros conjuntos de cenário não são shells residenciais e não entram no catálogo.

bob74_ipl deve estar iniciado. DLCs recentes exigem o build indicado no catálogo. Se o provedor não disponibilizar o interior ou o build for incompatível, a seleção falha com uma mensagem, sem cadastrar a saída. Pontos iniciais vêm das coordenadas documentadas no bob74; quando ausentes, usa-se a origem nativa apenas para a visita e o corretor confirma a saída. A visita deve ser validada no jogo, especialmente nesses interiores.

## Validação executada

- luac: scripts Lua ativos dos dois recursos, incluindo novos testes.
- Testes Lua: pares A/B, dois jogadores, retorno legado, origem fixa, conflitos de gravação, falha do banco e referências dos 116 exports instalados.
- Regressão: móveis, gizmo, interações, zonas e higiene.
- Build dos dois painéis e svelte-check do Realtor.

Esses testes simulam os serviços/natives; não substituem testar colisões e streaming no FiveM. Teste dois jogadores entrando por A/B, saindo pelo mesmo par e pelo outro, editando os pontos com alguém dentro e reconectando depois. Não foi reiniciado nenhum recurso automaticamente.

## Reserva e etapas

O cadastro possui cinco abas livres: Informações, Interior, Área/Jardim, Entradas/Saídas e Revisão. Pendências são indicadas sem bloquear a navegação. Pontos de higiene no gerenciamento usam acordeões.

IPLs ocupados aparecem como já cadastrados. Variações que compartilham o mesmo espaço são bloqueadas juntas. A reserva temporária dura 120 segundos e é renovada durante a seleção; cancelamento ou desconexão a libera. O bloqueio permanece durante a gravação. Excluir o imóvel libera o IPL após a remoção persistida e a atualização do servidor. Imóveis duplicados preexistentes não são apagados automaticamente.

Shells usam uma margem de separação baseada nas dimensões do modelo; origens legadas sem dimensões usam 60 metros. A posição e rotação ficam no JSON das portas. As saídas internas usam coordenadas locais e acompanham a rotação. Esta checagem não substitui verificar colisões com o cenário no jogo.

Não há alteração de modelo ou deslocamento de imóveis já criados: isso exigiria migrar também móveis, áreas e pontos de interação.

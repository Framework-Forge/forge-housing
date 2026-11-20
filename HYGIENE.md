# Higiene residencial

Integração baseada na referência local `renzu_hygiene`, sem iniciar esse recurso ou usar renzu_hud, renzu_popui ou esx_status.

## Configuração

- `shared/hygiene.lua`: ativação, velocidades dos níveis, duração das ações, modelos reconhecidos e avisos.
- Realtor > Móveis > Função de higiene: configurar pia, chuveiro ou vaso; distância, orientação e deslocamento do marcador. A configuração integra os móveis comprados após salvar o catálogo. Móveis antigos com modelos reconhecidos funcionam automaticamente.
- Realtor > Gerenciar imóvel > Pontos de higiene: o boss entra no imóvel e usa Criar ponto. O tablet é ocultado para caminhar até a instalação: E confirma, BACKSPACE cancela. Reposicionar altera o ponto; Posicionar animação define posições e direções diferentes para mãos, rosto, banho, xixi e cocô. Os campos X/Y/Z permitem ajuste fino. Cada pose deve estar dentro da distância de interação do ponto. Salvar pontos aplica a configuração para todos; não depende do botão Salvar imóvel. Em shells, coordenadas ficam relativas ao shell; em IPL/MLO são coordenadas do mundo. O marcador fica 0,8 m acima do ponto para evitar o piso. Ações sem pose personalizada usam o ponto e sua direção.
- Pontos manuais são destinados a instalações sem prop reconhecido. Não sobreponha um ponto manual a um móvel que já oferece a interação.
- O modelo `ligoshower` está disponível no stream. Cadastre-o no catálogo para vendê-lo; não há compra nem migração automática.

## Estado e integração

Higiene, bexiga e intestino ficam apenas no client do Housing, no cache PRBridge (`housing:hygiene`, `housing:pee`, `housing:poop`). Reiniciar Housing, reconectar ou trocar de personagem reinicia os níveis. Não há gravação desses níveis no servidor nem alteração de fome, sede, stress ou saúde. Aumentos de fome/sede observados no cache alimentam as necessidades. Acidentes reduzem a higiene local, sem efeitos sobre outros jogadores.

Forge HUD recebe uma cópia por evento local e consulta `GetHygieneStatus` ao iniciar. Os três indicadores aparecem no editor modular do HUD. A configuração dos pontos é persistida separadamente em `data/hygiene_points.json`, com autorização de boss no servidor e revisão contra sobrescritas concorrentes. Idioma segue exclusivamente o PRBridge, com pt-BR/en/fr/es.

Os pontos usam o modo escolhido em `Config.Interactions.hygiene` em `shared/config.lua`. O padrão é `"interact"` e a outra opção é `"target"`. Em `shared/hygiene.lua`, use `Config.Hygiene.notifications = false` para silenciar os avisos de sujeira, urgência e acidentes. O HUD, as necessidades e as mensagens de falha das ações continuam funcionando. Ações usam progresso cancelável, animação, áudio local e água local no banho. Não foram adicionados itens consumíveis de inventário, efeitos de mau cheiro sobre terceiros ou sincronização de necessidades pelo servidor.

## Validação no FiveM

1. Reiniciar Housing, Realtor e HUD em uma janela de teste, após a compilação.
2. Comprar/posicionar pia, vaso e chuveiro e verificar pontos Interact; guardar, mover e excluir e conferir a remoção dos pontos.
3. Testar mãos, rosto, banho, xixi, cocô e descarga; cancelar deve manter os níveis.
4. Criar ponto fixo em MLO e em shell; verificar outro jogador e retorno ao imóvel.
5. Verificar saída da casa durante a ação, troca de personagem, idioma e HUD reiniciado.

Os testes automatizados não substituem a validação de animações, colisões, orientação do prop e foco no FiveM.

## Editor em três etapas

1. **Interact e ações:** selecione uma ou várias ações e use Criar interact com laser. Mire na superfície e pressione E; BACKSPACE cancela. O marcador usa o ponto atingido pelo raycast PRBridge com 3 cm de afastamento da superfície. Pode combinar mãos, rosto, banho, xixi, cocô e descarga no mesmo ponto.
2. **Efeito de água:** cada ação de mãos/rosto/banho pode ter um jato próprio ou Sem efeito. O gizmo mostra o jato durante o ajuste de posição e rotação; a escala fica no painel. O efeito é local e acompanha a execução dessa ação.
3. **Animação do personagem:** posicione um clone local animado com o gizmo. A animação usada na prévia é a mesma da execução. Posição e direção ficam independentes do marcador e da água; a pose precisa estar dentro do raio de interação.

O tablet Forge Imóveis e seu objeto/animação são ocultados durante os editores e restaurados depois. Confirmar atualiza o rascunho; Salvar pontos persiste e publica para os clientes. Cancelar não altera o rascunho. Pontos novos precisam ter as poses de todas as ações (exceto descarga). Pontos antigos continuam compatíveis. Campos decimais aceitam os valores capturados sem arredondamento obrigatório.

Não foi necessário alterar PRBridge: foram usados seu raycast e gizmo existentes. A partícula do GTA é encapsulada no Housing para compartilhar a mesma implementação entre prévia e execução. A aparência e o alinhamento final devem ser conferidos no FiveM.

### Água independente e duração

O ponto Interact, a pose do personagem e a saída de água são coordenadas independentes. Na etapa 2, Posicionar água começa no marcador somente na primeira edição; depois reabre na posição de água salva. Os campos Saída de água X/Y/Z também permitem ajustes. Reposicionar o marcador não apaga nem move as poses e os efeitos.

Tipo Torneira usa core/ent_sht_water; Chuveiro usa scr_mp_house/ent_amb_shower, com scr_mp_house/ent_amb_shower_steam quando Vapor estiver marcado. Configurações antigas sem tipo assumem torneira para mãos/rosto e chuveiro para banho. A criação e remoção de todos os handles pertencem ao Housing: fim/cancelamento da prévia ou ação e parada do recurso limpam seus efeitos. Carregar os pontos nunca inicia partículas; durante o editor, a prévia é a única exceção.

Na etapa 1, Interact X/Y/Z mostra e permite editar a coordenada do marcador manualmente. Decimais são aceitos; campos vazios/não numéricos são recusados. As mudanças só entram em vigor em Salvar pontos, sem mover água nem animação. Em shells, os valores são relativos ao shell; em IPL/MLO são coordenadas do mundo.


### Água e saneamento
- A regra de corte de água já existente (`IsUtilityAvailable('agua')`) bloqueia mãos, rosto, banho e descarga. Urinar/defecar continuam disponíveis. A recuperação do abastecimento segue o pagamento das contas existente.
- Após concluir xixi/cocô, o vaso fica sujo. Após 60 segundos sem descarga, os ocupantes veem moscas no ponto e pequenos focos alternados próximos ao personagem. Uma descarga remove a sujeira daquele vaso para todos; outros vasos sujos permanecem.
- A sujeira é temporária, compartilhada no servidor e limpa ao reiniciar forge-housing. Não altera status pessoais nem a lógica de cobrança. O client atualiza ao receber eventos e consulta novamente a cada cinco segundos enquanto estiver no imóvel.
- Higiene pessoal abaixo de 20 (mesmo limite do aviso atual) gera moscas no personagem. Ao recuperar a higiene, sair da sessão ou morrer, esse efeito é removido. Status continuam no cache client do PRBridge.
- Moscas: `core / ent_amb_fly_swarm`, conforme o catálogo de partículas GTA: https://gist.github.com/alexguirre/af70f0122957f005a5c12bef2618a786 .
- O callback de movimento do gizmo deve retornar `true` e usar a coordenada proposta, pois é chamado antes de mover a entidade.

Validação em jogo: reposicione a água nos três eixos; use um vaso e espere 60 segundos com dois ocupantes; dê descarga pelo segundo ocupante; teste corte/restauração de água; saia/reentre na propriedade e confirme a limpeza dos efeitos. Testes automatizados não validam a aparência nativa das partículas.

### Corrida e acidentes
A perda de higiene é multiplicada por 3 correndo e por 5 em sprint, configurável em `Config.Hygiene.runningHygieneMultiplier` e `sprintingHygieneMultiplier`. A atividade é consultada em cada atualização do status (10 segundos por padrão). Parado/andando mantém a taxa normal; veículos não multiplicam a perda.
Acidentes de xixi/cocô ativam `soiled` no cache local, causando moscas mesmo com higiene acima de 20. O estado permanece até concluir um banho ou trocar de personagem; lavar mãos/rosto não remove a sujeira do acidente. O prazo existente para ocorrer o acidente permanece inalterado.

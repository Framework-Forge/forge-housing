# Móveis, armazenamento e editor

## Comportamento
- Baús: visitantes próximos ao móvel, dentro da zona da propriedade e na instância correta, podem abrir sem chave da casa.
- Cofres: mesma presença física, com validação da senha no servidor. Alterar a senha continua restrito à administração do imóvel.
- Guardar/mostrar: persiste `hidden` no JSON de móveis, preservando ID, conteúdo, senha e compra. O snapshot da propriedade atualiza objetos e targets dos observadores. Não exige alteração de schema SQL.
- Jogar fora: exige confirmação; armazenamento com itens não pode ser descartado. Guardar permanece disponível sem esvaziar.
- Permissões para editar, guardar e excluir continuam limitadas aos responsáveis autorizados pelo imóvel.

## Editor
- Catálogo escuro com destaque laranja, busca, categorias, estoque e carrinho.
- Itens da casa reúnem os botões de editar, guardar/mostrar e lixeira.
- A seleção abre o gizmo do PRBridge. A interface de móveis é ocultada durante a edição e recupera o foco após o encerramento do gizmo.
- C reabre a edição do objeto selecionado. Cancelar ou sair da zona restaura a posição anterior.
- Guardar aguarda um salvamento de posição em andamento antes de ler os dados, evitando sobrescrever a posição recém-editada.

## Validação
Sintaxe dos arquivos Lua alterados conferida com luac e Lua 5.4. Testes simulados cobrem visitante, senha, zona/instância, guardar/mostrar, descarte, sincronização e ciclo do gizmo. Interface compilada e exercitada em Chromium com respostas NUI simuladas.

Ainda requer teste dentro do FiveM: proprietário e visitante no mesmo imóvel; baú e cofre com senha correta/incorreta; guardar/mostrar observado pelos dois; editar com C e cancelar; fechar e reabrir o editor. Não houve reinício automático dos recursos.

# Móveis interativos — 22/09/2026

## Correções

- A remoção individual agora retira também o registro local do objeto. Antes, o objeto era apagado, mas seu ID permanecia na lista e bloqueava a recriação ao aplicar mudanças de posição/metadados.
- Referências a entidades que já não existem são removidas antes da recriação. Falhas ao carregar modelo ou registrar interação não deixam objetos órfãos; a próxima consulta de revisão solicita uma nova cópia dos móveis.
- O editor mantém a entidade e os targets ao concluir um reposicionamento, restaurando sua colisão. A aplicação das alterações continua vindo do servidor. Ao fechar, a seleção é encerrada antes de apagar as prévias do carrinho.
- Baús/cofres são preparados antes da cobrança. Falha nessa preparação recusa a compra sem débito. Atualização sem linha afetada no banco é tratada como falha; o caminho existente de devolução do pagamento e do estoque é utilizado.
- As atualizações permanecem destinadas aos ocupantes e observadores válidos da propriedade, incluindo visitantes.

## Validação

Arquivos Lua alterados validados com luac e Lua 5.4. Testes com nativas simuladas reproduzem o registro obsoleto no código anterior e verificam a correção, três clientes, remoção/recriação de objetos, recuperação após falha de modelo/target e preservação das interações no editor. Testes de servidor cobrem compra de cofre, baú, guarda-roupa e item comum com estoque limitado, falta de estoque, preparação recusada e falhas no banco com devolução.

Ainda é necessário confirmar no FiveM com dois jogadores, comprando e reposicionando esses móveis, usando seus targets e saindo/entrando na casa. Não houve reinício de recursos, alteração de ox_doorlock ou ajuste de dinheiro/dados antigos. Móveis já persistidos são carregados novamente ao entrar; compras antigas não persistidas exigem verificar os registros antes de qualquer compensação.

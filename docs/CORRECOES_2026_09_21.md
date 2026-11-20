# Correções de Forge Housing e Forge Realtor — 21/09/2026

Aplicadas na pasta `resources/[housing]`. A pasta `[Docs]/COPIA DE CORRECOES` foi somente referência; não foi substituída nem executada.

## Comparação e resultado

| Pedido | Encontrado na cópia | Alteração aplicada |
| --- | --- | --- |
| Dar chave/admin fora da casa | Lista por proximidade já corrigida | Lista por proximidade, mesmo routing bucket, opção de ID e acesso pelo target da entrada/jardim. Servidor valida concessões. |
| Trancas e grupos | Correção incompleta | Criação no servidor, estado inicialmente trancado, grupo `forge-housing`, nome `Rua/nome #ID 01`, `02` etc. |
| Showcase após venda | Bloqueio de proprietário já existia | Target e servidor exigem imóvel sem proprietário e disponível para venda; servidor revalida após confirmação. |
| Permissões após transferência | Cópia ainda tinha fluxo antigo | Lista das trancas reconstruída com proprietário, chaves e administradores atuais; acessos anteriores removidos na transferência. |
| Transferência e pagamento | Texto e banco obrigatório ainda existiam | Oferta estruturada com imóvel, proprietário, comprador e valor; comprador escolhe dinheiro/banco e confirma. Rejeição e falha de persistência não concluem a venda; cobrança estornada em falha da atualização. |
| Remover proprietário | Não implementado | Botão no Realtor; exige permissão configurada para excluir imóveis ou ACE administrativo. Preserva cadastro, móveis e impostos, revoga acessos e disponibiliza para venda. |
| Editar trancas | Não implementado | Botão no Realtor para distância, tranca automática e estado; IDs limitados às portas do imóvel. Recuperação de portas pendentes se a criação falhar. |
| Adaptador de garagem | Cópia usava JG diretamente | `pr_lib.garage` centraliza seleção, criação, gravação e registro; Forge, JG e compatibilidade QB/QBX. |

A correção de armazenamento de móveis encontrada na cópia não foi transplantada: é uma mudança separada dos oito itens solicitados. As integrações antigas de OX Target da cópia também não foram reintroduzidas.

## Garagens

Padrão: `auto`, procurando Forge Garage, JG Advanced Garages, QBX Garages e QB Garages, nessa ordem. Para escolher explicitamente no servidor e nos clientes:

```cfg
setr pr_bridge:garage "auto"
# Alternativa: setr pr_bridge:garage "jg-advancedgarages"
```

Forge usa o editor e as zonas que ele próprio salva. JG usa posição e target nativo do PR Bridge para abrir/guardar, segundo a [integração oficial](https://docs.jgscripts.com/advanced-garages/integrations/forge-housing) e os [eventos oficiais](https://docs.jgscripts.com/advanced-garages/commands-events-and-exports/events). QBX usa o [contrato RegisterGarage/canAccess](https://github.com/Qbox-project/qbx_garages/blob/main/server/main.lua).

Trocar o sistema de garagem não migra veículos, nomes ou zonas já armazenados entre fornecedores. Garagens Forge só com nome precisam ser reposicionadas pelo editor se forem usadas com JG. A configuração existente de garagem pública do Forge foi preservada.

## Portas existentes

O carregamento reconhece nomes antigos `ps_mloproperty<ID>_<índice>`, salva seus IDs no `door_data` antes de atualizar nome/grupo e reaplica os acessos atuais. Não recria portas existentes. Nome/grupo ficam independentes da identificação estável. O grupo pode ser alterado por `Config.DoorGroup` no Forge Housing, inclusive para `housing System` se esse for o nome desejado.

Portas físicas são as de casas MLO. Entradas virtuais de shells continuam usando o acesso do Housing. Uma falha ao criar portas preserva o imóvel e os dados pendentes; use “Recriar trancas pendentes” no Realtor depois de resolver a causa registrada no servidor.

## Validação realizada

- Testes em Lua 5.4 com os módulos reais e simulações de jogadores, banco, exports e callbacks.
- Chaves/admin, proximidade e bucket, compra e transferência, dinheiro/banco, recusa, saldo insuficiente, conflito/falha de banco, estorno, troca de acessos, grupo/nome e portas simples/duplas.
- Adaptador: seleção automática/forçada, retorno duplicado do editor, vínculo Forge pertencente ao imóvel, eventos JG e encerramento de targets, fornecedor parado, registro QBX.
- Callback do comprador testado com a mesma estrutura de oferta enviada pelo servidor.
- Interface Svelte compilada para `forge-realtor/html`; avisos preexistentes de acessibilidade e Browserslist não impedem a compilação.
- Testes não substituem validação no FiveM. JG não foi executado em jogo neste ambiente.

## Roteiro no servidor

Reinicie a base para carregar o PR Bridge e os consumidores atualizados. Não foi aplicado restart automaticamente. Garagem escolhida e `ox_doorlock` devem iniciar antes do Housing; Realtor depois do Housing.

1. Com corretor autorizado, abra `/housing`. Selecione um imóvel MLO já existente. Confira no doorlock o grupo e nomes e teste trancar/destrancar.
2. Com proprietário e segundo jogador próximos do lado de fora, use target da entrada → Gerenciar propriedade → Dar chave. Repita com acesso administrativo. Confira se a pessoa aparece sem entrar na casa.
3. Afaste o segundo jogador além de 5 m; a concessão deve ser recusada. Jogadores em instâncias diferentes também não podem receber por proximidade.
4. Confira o acesso do recebedor à casa e garagem. Remova a chave/admin e tente novamente, sem reconectar.
5. Em um imóvel não vendido e disponível para venda, teste Showcase como corretor. Depois da compra a opção deve desaparecer; tentar o evento também não autoriza visita.
6. Proprietário → Transferir imóvel: ofereça uma venda. Comprador deve ver proprietário atual, seu próprio nome, imóvel e valor; escolher dinheiro ou banco e confirmar. Confira o débito na conta escolhida e o crédito ao vendedor. Repita recusando, sem saldo e gratuitamente.
7. Após a transferência, o comprador deve trancar/destrancar imediatamente. O antigo proprietário e os acessos anteriores devem perder a autorização comum das portas. Para esse teste use jogadores sem bypass administrativo global.
8. Realtor → Editar trancas: altere distância, tempo automático (0 desativa) e estado. Confira com outro jogador. Reinicie e confirme persistência. Não use “Reposicionar porta” de shell em MLO; a lista de IDs é preservada.
9. Realtor → Remover proprietário: confirme, confira a casa ainda cadastrada e à venda, as portas trancadas e os acessos antigos revogados. Um corretor sem o nível necessário deve ser recusado pelo servidor.
10. Crie uma casa com porta simples e outra com porta dupla. Confira `forge-housing`, nomes sequenciais e estado trancado. Tentar selecionar uma porta já cadastrada deve ser recusado.
11. Configure e edite a garagem pelo Realtor, conclua o cadastro e teste guardar/retirar. Com JG selecionado, confirme os dois targets; com Forge, confirme o editor e o vínculo salvo. Refaça após reconectar.
12. Confira F8 e log do servidor durante os testes. Não devem ocorrer erros de callback nem de comparação com retorno SQL.

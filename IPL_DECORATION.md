# Personalização dos IPLs e tablet do morador

O tablet do morador possui Faturas, Gerenciamento, Compras, Serviços e, em imóveis IPL, Personalizar IPL. Serviços contém somente os avisos de funcionalidades futuras; não cobra nem instala alarmes/câmeras. Compras abre o mobiliário ou o catálogo imobiliário existente.

O boss da imobiliária acessa **IPLs**, abaixo de Móveis. Pode filtrar por interior/categoria, consultar nomes dos modelos/entity sets e editar preços individualmente. O preço é compartilhado pela mesma categoria/opção entre interiores compatíveis. `Config.IPLDecor.defaultPrice` vale R$ 1.000 por opção até o boss definir outro valor; zero permite uma opção gratuita. Preços aceitam valores inteiros em moeda do servidor.

## Catálogo

`data/ipl_decor_catalog.json` é uma lista permitida gerada a partir dos arquivos locais do bob74_ipl, sem executar nativos no jogo. Inclui 116 interiores; 95 possuem opções cosméticas extraídas. Nos demais, o painel informa a ausência de opções. Não inventa faixas de cores nem promete opções de DLC não instalado. Portas, cofres, carregamento de exteriores e outras operações estruturais não são vendidas como decoração.

Os métodos documentados do provedor são convertidos em operações de entity sets, tintas e IPLs. Temas executivos incluem a mudança do identificador do interior. Variações numéricas de um conjunto são exclusivas; detalhes independentes são ligados/desligados separadamente. Identificadores técnicos de texturas permanecem nos nomes originais no admin.

Fontes: [bob74_ipl](https://github.com/Bob74/bob74_ipl/wiki) e [FiveM: SetInteriorEntitySetColor](https://github.com/citizenfx/natives/blob/master/INTERIOR/SetInteriorEntitySetColor.md). O GTA não possui a mesma lista de categorias para todos os interiores. Cores dependem da paleta documentada no provedor.

O gerador `tools/generate_ipl_decor.py` requer Python e `lupa`; deve ser executado novamente e revisado quando o bob74_ipl for atualizado. Não modifica o provedor. Os hashes dos arquivos fonte ficam no catálogo para auditoria.

## Prévia e compra

O morador precisa estar dentro do imóvel e ser proprietário ou administrador dele. A escolha é pré-visualizada apenas no cliente que edita. “Ver no ambiente” esconde temporariamente o tablet; ENTER/BACKSPACE retorna. Fechar ou trocar de seção descarta a prévia. Nenhuma cobrança ocorre durante a escolha.

“Salvar e revisar valor” solicita orçamento ao servidor, com opções permitidas, revisão do imóvel e revisão de preços. O jogador escolhe banco ou dinheiro e confirma. Só opções diferentes das salvas são cobradas. O orçamento expira após 120 segundos, não pode ser repetido e é invalidado por mudança de proprietário, permissões, preços ou visual.

Os preços e escolhas são persistidos em `data/ipl_decor_state.json`, criado no primeiro salvamento. Faça backup desse arquivo. Em falha de gravação, o pagamento é estornado. Excluir a propriedade remove seu registro visual. Não há migração SQL.

Clientes que carregaram o interior recebem o visual confirmado por evento; quem entra depois consulta o servidor. Revisões antigas são descartadas. A aplicação ocorre ao entrar e ao salvar, sem reaplicar texturas periodicamente. A restauração da prévia recupera entity sets/IPLs capturados e tintas padrão do provedor (não há getter de cor correspondente nessa API).

## Validação

Testes Lua cobrem permissões, presença, opções inválidas, preços, confirmação repetida, estado desatualizado, saldo, estorno, persistência, exclusão e restauração da prévia. O teste de navegador cobre navegação, compra, filtros e edição de preços. Builds e luac também são executados.

É necessário conferir no FiveM a aparência/collision dos temas concretos e dois jogadores no mesmo interior. Os testes de nativos usam simulações. Layouts de temas podem mudar elementos embutidos; confira acessos e móveis após uma troca. Recursos externos que controlam o mesmo IPL devem ter responsabilidades distintas, como já ocorre entre garagem e residência.


### Correções de atualização durante a sessão

- As receitas de IPL agora são consolidadas antes da aplicação: a limpeza de um estilo não remove o próprio IPL escolhido. O interior novo é carregado antes da remoção do anterior.
- O jogador mantém suas coordenadas na troca; a associação ao ambiente antigo é invalidada. A reentrada reutiliza o interior ativo e reaplica a revisão salva.
- A confirmação da compra e o evento de sincronização usam a mesma guarda de revisão. Prévia e fechamento do tablet não revertem uma compra confirmada. Aplicações pendentes são retomadas quando o interior carregar.
- Banco e dinheiro têm seleção explícita e saldos fornecidos pelo servidor via PRBridge. O débito e eventual estorno usam a mesma conta, sem alternância automática.
- Compras lista os móveis da residência, com guardar/mostrar e acesso direto ao reposicionamento. Móveis guardados devem ser mostrados antes de reposicionar. Permissões e persistência continuam no servidor.

Validação local: luac (75 arquivos), regressões Lua incluindo troca de tema/broadcast/reentrada/estorno, build de ambas as NUIs, svelte-check e teste de navegação no navegador. O teste visual definitivo depende do FiveM: dois ocupantes dentro do mesmo imóvel, alterar acabamento, pagar pelo banco, fechar tablet, sair/entrar e verificar ambos os jogadores sem reconectar.

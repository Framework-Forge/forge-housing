# Zona do imóvel e debug

O PRBridge devolve minZ/maxZ absolutos e espessura no drawPolyzone3D. O Realtor já preservava esses campos no cadastro. Não foi comprovada perda desses dados no banco da casa relatada.

Correções: o Housing deixa de deslocar os vértices verticalmente e de acrescentar 3 m ao teto do MLO. A distância de carregamento passa a cobrir todos os vértices e as alturas da zona, com margem de 10 m e mínimo de 40 m. A autorização de leitura para visitantes de MLO usa o mesmo cálculo, preservando o mínimo anterior de 65 m e a separação por routing bucket. Isso evita que quartos afastados/andares altos fiquem fora do alcance arbitrário da porta.

O boss encontra no tablet: Gerenciar imóveis > Gerenciar > Limites da zona > Visualizar zona (debug). Fechar o tablet mantém o desenho; BACKSPACE desliga. Piso azul, teto laranja e paredes translúcidas. Texto mostra ID, limites aplicados, altura do jogador, dentro/fora, áreas com móveis ativos e quantidade de props carregados. F8 imprime os limites recebidos no cadastro, aplicados e o raio. O debug é local, somente leitura, e não altera a propriedade nem a zona ativa do jogo.

Validação: luac e Lua 5.4 em cada Lua alterado; teste executando callback do Realtor, construção real do Housing e contains real do PRBridge, com andares altos, limites inferior/superior, XY e zona legada sem minZ/maxZ. Testes de visitantes e ciclo do debug; regressões de móveis e portas. Build da NUI concluído com avisos antigos de acessibilidade em outros componentes.

Ainda requer conferência no FiveM da casa afetada: ativar debug, fechar tablet, fotografar limites e copiar a linha [forge-housing:zone] do F8. Não foram recriadas zonas salvas nem alterados dados financeiros. Recarregar forge-housing e forge-realtor para usar os scripts/NUI atualizados, preferencialmente fora dos interiores.

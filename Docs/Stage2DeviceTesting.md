# Checklist físico — Etapa 2

Registre commit, iOS, VR Box, perfil óptico, firmware/nome/perfil de cada Joy-Con e duração. Marque somente itens executados.

## Home e mira

- Instale Release com Team real no iPhone 15; monte com Dynamic Island à esquerda.
- Confira Home 3D, chão em perspectiva, cenário 360° e disparidade próxima/distante. Verifique os eixos usando o [protocolo da Etapa 1](DeviceTesting.md).
- Gire a cabeça: as janelas ficam no mundo. Confira relógio/data/bateria, legibilidade e calibração antes de avaliar conforto.
- Aponte, observe o anel de permanência e afaste para cancelar. Permanecer no botão após seleção não deve repetir o clique.
- Teste oito destinos, duas páginas da biblioteca e indicação explícita de conteúdo em desenvolvimento.
- Abra Menu por mira. Teste cada atalho, controles, lentes, distância, recuperação de janela e restauração de layout.
- Recentralize em diferentes headings: cenário parado, interface suavemente à frente, relação entre janelas preservada.
- Entre na preparação 2D: não deve haver seleção espacial ao fundo. Retorne sem disparar gesto anterior.

## Joy-Cons

- Siga [Controllers.md](Controllers.md). Teste esquerdo, direito e par separadamente; registre a representação escolhida pelo iOS.
- Confira nome, botões, eixos e bateria quando anunciada. Compare letras lógicas/físicas e remapeie.
- Teste analógico: direção, zona neutra, cursor parado e sensibilidade. Com dois, teste rolagem; com um, apontamento e direcional livre para rolar.
- Aponte laser para bordas/cantos: ponto, destaque e seleção devem coincidir. Área vazia não executa ação.
- A + ZR simultâneos produzem uma ação, sem repetição no hold. Solte e pressione para repetir.
- Agarre/mova/solte painéis, ajuste profundidade, teste limites e desconexão. Janelas não devem atravessar a câmera ou ficar atrás por arrasto.
- Desconecte durante foco/arrasto, troque fonte com botões mantidos e teste fallback. Nenhum clique involuntário.
- Teste Automático, Controle e Cabeça; direcional remapeado não pode selecionar e rolar simultaneamente.

## Movimento experimental

- Habilite somente se a API anunciar atitude; calibre na posição neutra.
- Teste yaw/pitch/roll isolados e combinados. Use inversões/troca de eixos conforme a forma real de segurar.
- Se dados/eixos forem inconsistentes, use Analógico e registre a limitação. Não há posição física rastreada do controle.

## Ciclo de vida e desempenho

- Bloqueie/desbloqueie, abra Central de Controle e alterne apps durante foco, hold e arrasto. Após retomada, exija nova entrada válida.
- Feche/reabra e confira persistência: fonte, modo, sensibilidade, permanência, mapeamento, distância e lentes.
- Teste 15 minutos em escala 0,85, depois 0,5/1,0. Registre FPS/CPU/GPU, frame pacing, temperatura, conforto e bateria.
- Use Instruments Allocations/Leaks, Time Profiler e Metal System Trace. Atlas não deve ser recriado por frame; buffers devem ser reutilizados; memória não deve crescer continuamente ao abrir/fechar painéis.

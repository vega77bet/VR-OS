# Protocolo no iPhone 15 + VR Box

Preencha data, commit, versão de iOS, modelo do visor, perfil óptico e temperatura ambiente. Nenhum item desta lista deve ser marcado como aprovado sem execução física.

## Preparação e instalação

Gere o projeto com XcodeGen, selecione Team real, conecte o iPhone e execute VROS em Release. Confirme tela horizontal inteira, sem barras, topo/Dynamic Island à esquerda. Não conceda câmera: ela não é solicitada. Se os sensores estiverem indisponíveis, o diagnóstico deve informar isso.

## Eixos isolados

Com controles ocultos e o aparelho no visor, mantenha os ombros parados. Recentralize antes de cada série, espere a transição terminar e faça movimentos pequenos primeiro.

| Ação física | Resultado exigido |
|---|---|
| Girar cabeça para direita | Referências da direita entram no centro; frente se desloca para esquerda |
| Girar cabeça para esquerda | Referências da esquerda entram no centro; frente vai para direita |
| Olhar para cima | Objetos suspensos/teto entram em visão; horizonte desce |
| Olhar para baixo | Piso ocupa mais da visão; horizonte sobe |
| Inclinar cabeça para direita | Horizonte inclina para esquerda na imagem; ambiente continua nivelado no mundo |

Repita em amplitudes maiores e combinando eixos. Verifique ausência de saltos perto de ±180° de rumo e próximo da vertical. Não confunda a direção de movimento do cenário na tela com a direção da câmera.

## Estéreo e óptica

1. Fora do visor, confirme identificação E / D nas respectivas metades físicas.
2. No visor, cubra alternadamente cada lente. Objetos próximos devem apresentar disparidade maior que objetos distantes; esquerda e direita não podem estar trocadas.
3. O elemento central deve parecer à frente das referências distantes, com piso/paredes geometricamente coerentes. Não deve haver mistura de uma metade com a outra nas bordas.
4. Varie IPD virtual em pequenos passos e confira fusão sem duplicação. O ajuste virtual não substitui a posição física das lentes.
5. Ajuste centros e escala por olho; compare cada olho isoladamente. Observe linhas do piso/horizonte para calibrar intensidade e coeficientes de distorção. Intensidade zero deve remover a correção.
6. Teste extremos permitidos de calibração: bordas pretas são esperadas fora da área válida, mas nunca pixels do outro olho.
7. Encerre e reabra o app, confirmando persistência. Restaure padrões e repita.

## Recenter e interrupções

Repita recentralização dez vezes com yaw/pitch/roll diferentes. O rumo atual deve tornar-se frente com transição curta; pitch e roll devem permanecer, sem alterar profundidade/IPD. Olhando quase verticalmente, recenter deve ser ignorado com segurança ou preservar o último heading estável.

Bloqueie/desbloqueie o aparelho, abra/feche Central de Controle, mande o app ao fundo e volte. Confirme pausa dos sensores/frames, reinício sem congelamento ou salto de referência e funcionamento posterior de recenter. Abra a calibração e retorne: sensores/renderização também pausam. Negue/restrinja movimento se o sistema permitir e confira diagnóstico. Repita vinte ciclos para investigar crescimento de memória.

## Desempenho e estabilidade

Em Release, teste pelo menos 15 minutos em escala 0,85 e depois 0,5/1,0, com e sem cabo. Registre FPS, CPU, GPU, estado térmico e oscilações; não use só média para alegar estabilidade. Use Instruments Metal System Trace, Time Profiler e Allocations/Leaks. Confirme limite de frames em voo, ausência de crescimento contínuo de memória após aquecimento e recriação de texturas somente ao mudar tamanho/escala. GPU Frame Capture deve mostrar duas câmeras e dois alvos distintos, com ordem E/D correta.

O alvo é o orçamento de 16,67 ms por frame a 60 Hz, sem promessa prévia de resultado. FPS do overlay é cadência de submissão e não prova apresentação ou latência sensor-fóton; filme movimento e tela com câmera de alta velocidade para medir essa latência, se necessário. Registre desconforto, borrão e ghosting separadamente de quedas de FPS.

Somente depois de aprovar compilação, sinais reais, estéreo, óptica, lifecycle e estabilidade esta etapa pode ser considerada validada para avançar à Etapa 2.

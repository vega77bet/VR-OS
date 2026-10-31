# Rastreamento: convenções e validação

Este motor usa vetores coluna, quaternions Hamilton normalizados e composição da direita para a esquerda. Não utiliza ângulos de Euler para acompanhar movimento.

## Espaços de coordenadas

- **D — dispositivo Core Motion**, independente da orientação UIKit: +X para a direita do telefone em retrato, +Y para seu topo, +Z saindo da tela em direção ao observador.
- **R — referência Core Motion `.xArbitraryZVertical`**: +Z para cima; X/Y no plano horizontal, com heading arbitrário definido ao iniciar sensores. Não depende de câmeras nem magnetômetro. Pode acumular deriva de yaw.
- **H — cabeça/tela**: +X para o lado direito físico da imagem, +Y para o topo da imagem e +Z em direção aos olhos; a câmera olha por −Z.
- **W — mundo do motor**, destro: +X direita, +Y cima, −Z frente inicial.

O aplicativo fixa **`UIInterfaceOrientation.landscapeRight`**: USB/Home ficam à direita, topo/Dynamic Island à esquerda. Não confundir com `UIDeviceOrientation.landscapeRight`, cujo nome é oposto para paisagem. A tela precisa ficar voltada para os olhos. A montagem inversa ainda não é suportada.

A base `B = D←H = Rz(−π/2)` tem colunas `(0,−1,0)`, `(1,0,0)`, `(0,0,1)`. Portanto o eixo direito da imagem corresponde a −Y do dispositivo e o eixo superior corresponde a +X do dispositivo.

`A = W←R = Rx(−π/2)` converte Z vertical em Y vertical: X de referência vira X de mundo, Y vira −Z, Z vira +Y.

## Direção da atitude e inversão

A matriz de atitude de Core Motion representa `D←R`. O invariante de gravidade é:

```
q.act([0, 0, -1]) ≈ motion.gravity
```

A câmera precisa de uma **pose**, que leva coordenadas locais ao mundo. Logo:

```
Q(W←H) = A(W←R) × inverse(q(D←R)) × B(D←H)
```

A inversão é uma troca de referencial, não uma correção empírica de sinais. O renderizador constrói a matriz de vista invertendo a pose rígida completa de cada olho. Não aplicar outra conjugação ao rastreamento.

Referências Apple para auditoria:

- [CMAttitude](https://developer.apple.com/documentation/coremotion/cmattitude).
- [Referências de atitude](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe).
- [Dados processados de movimento](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data).
- [Orientação de interface](https://developer.apple.com/documentation/uikit/uiinterfaceorientation).
- *Event Handling Guide for iOS*, edição 2013-01-28, seção “Device Attitude and the Reference Frame”, p. 67: descreve `R × gravityReference = gravityDevice`. Essa relação permite verificar a direção com uma leitura física, independentemente da forma de empacotar matrizes.

## Previsão limitada e leitura por frame

`HeadTrackingManager` consulta a amostra fundida mais recente imediatamente antes de renderizar; não cria uma fila de callbacks. O renderer deve solicitar **uma pose por frame** e reutilizá-la nos dois olhos. `CMLogItem.timestamp` e `CACurrentMediaTime()` são tempos monotônicos em segundos desde o boot; não usar `Date`.

A velocidade angular medida está em D. Ela é convertida a H por `inverse(B)` e integrada à direita da pose por uma exponencial de quaternion. O intervalo é a idade da amostra, limitado a 20 ms. Não há suavização do movimento nem previsão especulativa adicional de scan-out. Uma amostra com mais de 250 ms é rejeitada e a última pose permanece congelada, com status de interrupção. O benefício de latência e qualquer overshoot exigem medição no iPhone físico.

## Recenter e ciclo de vida

O recenter extrai o heading pela projeção do vetor frontal no plano XZ e atualiza apenas um quaternion de correção sobre Y do mundo. Pitch, roll, gravidade, IPD e distâncias da cena não são redefinidos. A correção transita durante 250 ms com curva suave; o rastreamento físico continua sem filtro durante essa transição. A cena necessariamente muda de heading ao escolher uma nova frente; a transição evita um salto instantâneo. Ao olhar exatamente na vertical, heading é indefinido: a correção anterior permanece.

A primeira amostra válida estabelece a frente inicial. Ao interromper a aplicação, `stop()` encerra Core Motion. Uma retomada inicia uma referência arbitrária nova; o primeiro sample é rebaseado para conservar o heading visível anterior. Pitch/roll seguem a gravidade atual. É necessário testar a retomada real do sistema, além da fonte injetada dos testes.

Amostras inválidas ou obsoletas são rejeitadas. Uma pausa curta sem reinício retoma a orientação física absoluta, incluindo movimento ocorrido durante a pausa; somente o reinício conhecido rebaseia o heading. Um fluxo inativo ou sem dados por mais de um segundo tenta reiniciar no máximo uma vez por segundo. O `deinit` da fonte encerra o serviço. `start`, `stop`, `recenter` e a leitura da pose pertencem ao main actor.

`recenter()` é o ponto único de entrada que um adaptador futuro de controle Bluetooth poderá chamar; esta etapa não implementa Bluetooth.

## Testes de eixos

`Tests/TrackingTests.swift` parte de um fixture independente de dispositivo em paisagem ereta: quaternion `(-0.5, +0.5, -0.5, +0.5)` em ordem XYZW. Sua gravidade é −X do dispositivo. Cada teste aplica uma rotação física sobre um eixo do dispositivo e verifica o vetor frontal/superior obtido:

| Movimento físico | Eixo físico | Resultado esperado da câmera |
| --- | --- | --- |
| Cabeça à direita | −X de D | frente ganha X positivo |
| Cabeça à esquerda | +X de D | frente ganha X negativo |
| Olhar acima | −Y de D | frente ganha Y positivo |
| Olhar abaixo | +Y de D | frente ganha Y negativo |
| Inclinar topo à direita | −Z de D | vetor superior ganha X positivo |

Também há testes de previsão limitada, recenter repetido, continuidade ao iniciar recenter, preservação de inclinação, olhar vertical, falta de sensores, amostras inválidas/obsoletas e interrupção/retomada por fonte injetada. Eles validam o código e a matemática; não substituem a conferência da convenção com `motion.gravity` e os seis movimentos no aparelho.

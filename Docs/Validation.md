# Registro de validação — Etapa 1

Data: 2026-10-31. Ambiente local: Linux x86_64; sem Xcode, SDK iOS, simulador Apple ou iPhone. Testes reais de hardware não foram realizados. Não existe certificado/Team de assinatura disponível neste ambiente.

## Evidência local

- `git diff --check`: passou.
- Parser YAML do `project.yml`, bundle ID preservado, orientação horizontal única, presença de módulos/shaders: passou.
- Parser plist do manifesto de privacidade: passou.
- Revisão independente de coordenadas: confrontou o invariante Apple `attitude × gravityReference = gravityDevice`, base física de paisagem, transformação de vista e projeção Metal. Não encontrou inversões na análise estática. Isso não substitui o teste dos sensores reais.
- Revisão de recursos: buffers estáticos, callbacks com capturas fracas, duas submissões em voo, texturas antigas retidas por comandos Metal até conclusão. Nenhuma garantia de ausência de vazamentos sem Instruments.

## Compilação e XCTest

**Execução final aprovada:** [GitHub Actions 41220190996](https://github.com/vega77bet/VR-OS/actions/runs/41220190996), código-fonte no commit `fcf4811f89596c6faff6bc242d320ef62789922e`. Runner `macos-15-intel`, Xcode 16.4, SDK iOS 18.5, simulador iPhone 16 Pro / iOS 18.5. A documentação posterior não altera o código validado.

| Verificação | Resultado observado |
| --- | --- |
| XcodeGen / projeto nativo | Aprovado |
| Release `iphoneos`, destino genérico iPhone, sem assinatura | `BUILD SUCCEEDED` |
| XCTest nativo macOS — `VROSMath` | 19 executados, 0 falhas, 0 pulados |
| XCTest iOS Simulator — `VROS` | 27 executados, 0 falhas, 0 pulados |
| Pipelines e ABI Swift/Metal | Aprovado no simulador |
| Composição SBS real, textura vermelha E / azul D, largura ímpar | Aprovado no simulador |
| Distorção ativa, centros/escalas assimétricos, UVs e máscara preta | Aprovado no simulador |
| Layout: declaração de orientação horizontal única | Aprovado no bundle do app hospedeiro |
| Política de interrupção/retomada e amostras obsoletas | 4 testes aprovados com fonte injetada |

Na suíte iOS: 6 testes de calibração, 6 de estéreo/cena, 7 de orientação/recenter, 4 de lifecycle e 4 de Metal/layout. Os 19 testes do macOS reutilizam parte desses mesmos testes; não são 46 casos distintos. Nenhum teste Metal foi pulado nesta execução: o dispositivo Metal do simulador estava disponível e os shaders foram executados em alvos offscreen.

[Artefato de evidências](https://github.com/vega77bet/VR-OS/actions/runs/41220190996/artifacts/13050275478): aplicativo de dispositivo `.app` **sem assinatura**, projeto `VROS.xcodeproj`, `MathTests.xcresult` e `Tests.xcresult`. SHA-256 do ZIP informado pelo GitHub: `c2d1f4f6bb071bc43d5258a81baf6cd60f7cebea3dff4439703f1962dc649db2`. Retenção até 2026-11-14; os resultados resumidos aqui permanecem no repositório.

O simulador usa assinatura ad hoc local, sem Team de distribuição. Isso não fornece assinatura nem valida instalação no iPhone físico. Houve tentativas anteriores substituídas durante a inicialização do simulador e uma falha de configuração do nome do framework de testes; a configuração foi corrigida antes da execução aprovada. O primeiro boot do simulador é demorado neste runner, por isso o workflow inicia o dispositivo explicitamente e limita o tempo de teste.

A suíte contém testes de sinais de yaw/pitch/roll, bases, previsão limitada, recenter, lifecycle via fonte injetada, IPD, disparidade, projeção, metades físicas, cena volumétrica e persistência de calibração. Os testes Metal criam pipelines e executam o shader real em alvos offscreen, incluindo isolamento E/D e distorção não nula com centros assimétricos; são explicitamente pulados se não houver dispositivo Metal, sem simular um resultado aprovado.

Para desacoplar a matemática da inicialização do simulador, o scheme macOS `VROSMath` compila os mesmos seis arquivos de produção. O workflow guarda evidências separadas para as duas suítes. Os avisos de extração de metadados App Intents indicam ausência dessa dependência, que não é utilizada pelo app; não houve erro de compilação na execução final.

## Pendências de validação física

- Instalação e execução assinadas no iPhone 15.
- Correspondência entre sinais Core Motion reais e movimento físico em cada eixo.
- Fusão binocular e adequação da distorção/centros às lentes do VR Box do usuário.
- Interrupções e retomadas reais de Core Motion/iOS.
- FPS sustentado a 60 Hz, frame pacing, latência sensor-fóton, temperatura e autonomia.
- Memory Graph, Allocations/Leaks e Metal System Trace no dispositivo.

O protocolo reproduzível está em [DeviceTesting.md](DeviceTesting.md). Sem esses resultados, a etapa está implementada para avaliação, mas não certificada como validada em hardware. A Etapa 2 não deve começar com base somente nos testes sintéticos.

## Limitações conhecidas

3DoF sem translação; possível deriva de yaw na referência inercial; uma montagem horizontal suportada; perfis ópticos provisórios; sem correção cromática, timewarp ou tracking de controles. O recenter suaviza mudança de rumo durante 250 ms, o que deve ser avaliado quanto a conforto. A previsão compensa somente a idade da amostra, limitada a 20 ms. A cena fica congelada quando não há dados válidos e indica o estado no diagnóstico. Movimento físico durante uma pausa conhecida não é reconstruído: o heading é rebaseado ao voltar, enquanto pitch/roll seguem a gravidade atual.

O overlay mede frames submetidos e tempos CPU/GPU disponíveis, não garante scan-out a 60 FPS nem equivalência a Meta Quest. A interface de calibração/diagnóstico é usada antes de colocar o aparelho no visor.

Não foi produzido IPA instalável, pois isso requer compilação e assinatura válidas.

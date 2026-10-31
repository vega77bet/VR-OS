# Registro de validação — Etapa 1

Data: 2026-10-31. Ambiente local: Linux x86_64; sem Xcode, SDK iOS, simulador Apple ou iPhone. Testes reais de hardware não foram realizados. Não existe certificado/Team de assinatura disponível neste ambiente.

## Evidência local

- `git diff --check`: passou.
- Parser YAML do `project.yml`, bundle ID preservado, orientação horizontal única, presença de módulos/shaders: passou.
- Parser plist do manifesto de privacidade: passou.
- Revisão independente de coordenadas: confrontou o invariante Apple `attitude × gravityReference = gravityDevice`, base física de paisagem, transformação de vista e projeção Metal. Não encontrou inversões na análise estática. Isso não substitui o teste dos sensores reais.
- Revisão de recursos: buffers estáticos, callbacks com capturas fracas, duas submissões em voo, texturas antigas retidas por comandos Metal até conclusão. Nenhuma garantia de ausência de vazamentos sem Instruments.

## Compilação e XCTest

O workflow `.github/workflows/ios.yml` compila para iPhone sem assinatura e executa XCTest no simulador em runner macOS. Na [primeira execução remota](https://github.com/vega77bet/VR-OS/actions/runs/41218458302), commit `f99423497bc811d412b1491030f5ee85d56462b3`, a geração do projeto e a compilação Release para `iphoneos` **passaram** no Xcode 16.4. O resultado de XCTest e das revisões seguintes será registrado após conclusão.

A suíte contém testes de sinais de yaw/pitch/roll, bases, previsão limitada, recenter, lifecycle via fonte injetada, IPD, disparidade, projeção, metades físicas, cena volumétrica e persistência de calibração. Os testes Metal criam pipelines e executam o shader real em alvos offscreen, incluindo isolamento E/D e distorção não nula com centros assimétricos; são explicitamente pulados se não houver dispositivo Metal, sem simular um resultado aprovado.

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

# Validação da Etapa 2

Branch `vr-os-2-stage-2`, derivada de `8f518573e4c1f57dcaea085ee1fb3d6d9832501b`. Ambiente local Linux sem Xcode, iPhone ou Joy-Con. Compilação e XCTest serão realizados no runner macOS do GitHub Actions. Resultados serão registrados após conclusão; código escrito não equivale a teste aprovado.

## Verificações locais

- `git diff --check`: aprovado.
- YAML e existência dos fontes dos targets: aprovado.
- Revisão da fonte única de geometria visual/interativa e da arbitragem de entrada.
- Regressões incluídas: distância não abre janelas fechadas; biblioteca não fica oculta pelo destino anterior; ausência de seleção em controle preserva acesso pela cabeça; direcional remapeado não rola adicionalmente; recenter não reinicia repetidamente o dwell; navegação cancela arrasto.

## Resultado remoto

Pendente da primeira execução.

## Limites da validação

Sensores reais, eixos físicos dos Joy-Cons, lentes/VR Box, legibilidade, conforto, 60 FPS sustentados, latência movimento-fóton, autonomia e vazamentos no iPhone 15 permanecem dependentes de teste físico. Simulador não comprova esses resultados.

O CI produz `.app` de dispositivo sem assinatura, projeto Xcode, relatórios e capturas GPU. Sem certificado/Team real não há IPA instalável.

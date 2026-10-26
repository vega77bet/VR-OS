# VR-OS V21 — Ajustes nativos do sistema VR

Versão **4.7.0 (build 21)**. O aplicativo **Ajustes** aparece como sexto item na Central de Apps, depois dos cinco atalhos web. É um aplicativo iOS **nativo em SwiftUI + UITableView**, com interface cinza-escura inspirada nos Ajustes do iPhone. Não é uma página web e não controla as preferências restritas do iOS.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| VROS/VRSettingsCatalog.swift | 9 categorias, IDs estáveis, grupos, subpáginas, busca em português sem acentos |
| VROS/VRSettingsSession.swift | Um único estado compartilhado entre olhos, persistência, ações, confirmações e scroll |
| VROS/VRSettingsScreen.swift | UIKit UITableView agrupada, UISlider, UISwitch, busca, navegação e células cinza |
| VROS/VRSettingsInputGeometry.swift | Limites puros testáveis dos gestos de pinça, busca, voltar e fechar |
| VROS/VROSApp.swift | App Ajustes no launcher, integração com ARKit, câmera, Cinema, janelas e Vision |
| VROS/VRPinchDetector.swift | Histerese e sensibilidade configurável para mãos |

As duas vistas são desenhadas dentro da máscara óptica curva introduzida na V20. Cada olho tem uma UITableView; ambos exibem as mesmas páginas, busca e opções. Ao rolar com o dedo, o olho que está sendo manipulado controla temporariamente o deslocamento e o outro acompanha. A pinça usa a tabela esquerda como referência, mas as duas vistas se movem sincronizadas.

## Categorias reais

- **Visor e lentes:** Referência / VR Box + / Compacto, tamanho, IPD visual, altura, zoom digital, curva e restauração do visor.
- **Câmera:** ARKit/0,5x ultrawide real, imagem integral/preencher e direção do movimento 3DoF.
- **Mãos e gestos:** esqueleto, cursor, tamanho do cursor e sensibilidade da pinça, aplicada de verdade ao Vision.
- **Janelas:** opacidade, distância padrão de novas janelas de texto/web e recentralização.
- **Aparência:** Grafite, Cosmos, Aurora, Synthwave e exibição do HUD.
- **Cinema:** FOV, inversão da cabeça, imersão, ordem dos olhos e ocultação automática de controles.
- **Internet e apps:** zoom web, exclusão confirmada dos favoritos e explicação sobre DRM.
- **Geral:** restauro confirmado das preferências locais e informações do armazenamento.
- **Sobre:** versão/build reais do Info.plist instalado e limitações de privacidade/captura.

## Gestos e comportamento

- **Toque nativo:** listas com rolagem inercial e grupos arredondados, caixas de interruptor, sliders UIKit, botões +/- e navegação de subpáginas.
- **Pinça:** curta ativa um item; segurar e mover a mão rola a tabela; pinçar o trilho de um slider o ajusta; botões +/- possuem áreas exatas de detecção UIKit.
- **Segurança:** perder a mão no Vision **cancela** a pinça; não ativa um item por acidente. Excluir favoritos ou restaurar ajustes exige duas ativações de confirmação.
- **Busca:** encontra categorias pelo título e pelas opções contidas, inclusive buscas sem acentos como “pinca” e “camera”.
- **Armazenamento:** salva preferências de visor, câmera, Cinema, web, esqueleto, HUD, cursor e opacidade localmente no iPhone via UserDefaults.

## Limitações

A interface é inspirada no design dos Ajustes da Apple, com identidade de VR-OS; não substitui o app Ajustes do iOS nem altera Wi-Fi, Bluetooth ou Apple ID.

O 0,5x real usa a lente traseira ultrawide via AVFoundation e rastreia mão com Vision e rotação de cabeça 3DoF via CoreMotion. **Não mantém posicionamento ARKit 6DoF no modo ultrawide.** A imagem monocular é duplicada para os dois olhos, não é captura estéreo real.

O CI verifica compilação iOS Release e testes automatizados de geometria, busca, categorias, pinch, cinema e controles, mas **não substitui teste físico no iPhone 15 dentro do VR Box**. A IPA produzida é **sem assinatura**.

## Roteiro de teste físico

1. Central de Apps → Ajustes; abrir, fechar e abrir novamente. Verificar fundo cinza e as duas vistas.
2. Rolar lista com o dedo no olho esquerdo e no direito, depois com Vision. A outra lista deve acompanhar.
3. Buscar “pinca”, “camera”, “IPD” e “zoom”; entrar, voltar e sair.
4. Alterar perfis de visor, IPD visual, altura e zoom; conferir ambos os olhos e persistência após reiniciar.
5. Alterar sensibilidade, cursor/esqueleto, opacidade e distância de novas janelas. Testar notas e sites.
6. Testar sliders reais sem perder o controle no meio do arraste; clicar +/- por pinça e evitar mudar o valor ao pinçar o título.
7. Alternar para 0,5x e voltar ao ARKit; testar comportamento sem permissão ou sem ultrawide.
8. Salvar opções do Cinema e confirmar que persistem depois de reiniciar.
9. Confirmar limpeza de favoritos e restauro geral em dois toques; verificar os valores restaurados.
10. Parar o uso em caso de tontura ou esforço ocular; verificar orientação, legibilidade e aquecimento por 10–15 minutos.

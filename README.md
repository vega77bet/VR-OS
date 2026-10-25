# VR-OS 2.0 — protótipo para iPhone + VR Box

Aplicativo **experimental** iOS, em modo paisagem, com:

- Imagem da câmera traseira duplicada em duas metades (uma por olho).
- Interface com várias janelas, botão para abrir, fechar pelo X e mover segurando pinça.
- Reconhecimento de mão com **Vision / VNDetectHumanHandPoseRequest**, sem serviços externos.
- Pinça (indicador + polegar) para selecionar, com estabilização e limiares de histerese.
- Leitura de orientação da cabeça pelo **CoreMotion** e comando de recentralização.

## Controles

Coloque a mão no campo de visão da câmera traseira. Uma bolinha ciano marca o indicador; quando a pinça é detectada, fica verde. Faça pinça sobre **Janela**, **Notas** ou **Centro** na barra inferior para comandar o sistema. Segure a pinça sobre uma janela e mova a mão para arrastá-la. Faça pinça sobre o **X** para fechar.

Os botões também aceitam toque na tela para facilitar os testes sem o VR Box.

## Build

O GitHub Actions usa XcodeGen e Xcode em macOS para construir um **IPA sem assinatura**. O arquivo é disponibilizado como artifact da execução. A instalação deve ser assinada por uma ferramenta como AltStore.

## Limitações atuais

- **Não** implementa visão 3D real do mundo físico: a câmera é monocular, e as duas metades repetem a mesma imagem com deslocamento visual apenas das janelas.
- As janelas são **simuladas em estéreo na tela**, não usam mapeamento espacial nem ancoragem ARKit persistente. O CoreMotion cria deslocamento limitado.
- O rastreamento pelo Vision é **2D**; não mede a profundidade exata das mãos.
- O enquadramento, a rotação da imagem e a calibração óptica dependem do modelo de VR Box; podem exigir ajustes depois do teste no iPhone 15.
- Não há acesso para executar outros aplicativos do iOS dentro das janelas.
- A detecção das mãos, renderização e instalação **não foram validadas num iPhone real**.
- Use somente em ambiente seguro, parado, longe de obstáculos.

## Tecnologia

SwiftUI, AVFoundation (preview + frames de vídeo), Apple Vision, CoreMotion, XcodeGen. Requer iOS 16 ou superior.

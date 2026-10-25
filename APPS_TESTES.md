# VR-OS — Central de Apps (V12)

O botão **Apps** aparece na barra principal, ao lado de Janela e Cinema.

## Abrir uma janela flutuante

1. Toque em **Apps** no dock ou selecione com pinça.
2. Escolha **YouTube**, **Netflix** ou **Navegador**.
3. Abre-se uma janela de site no espaço VR, sem sair do modo principal.
4. **Pegue a linha branca abaixo da janela com a pinça** para deslocá-la no espaço e aproximar/afastar a profundidade estimada da mão.
5. No navegador, toque na barra de endereço, escreva uma URL HTTPS ou uma pesquisa e use a seta. Use os botões **voltar**, **avançar**, **recarregar**, **início** e **Safari**.
6. Abra quantas janelas o desempenho do aparelho permitir; feche as que não estiver usando.

## Compatibilidade honesta

- A experiência dos sites dentro do aplicativo é feita por `WKWebView`, uma superfície de navegador da Apple.
- As duas metades do VR precisam de uma web view cada; uma sessão de navegação mantém os endereços alinhados e a rolagem da direita acompanha a esquerda. A interação por toque acontece na metade esquerda.
- A versão tenta silenciar os elementos de áudio/vídeo da web view direita, mas **não garante reprodução de vídeo sincronizada ou estereoscópica para os dois olhos**. Os sites são janelas 2D flutuantes em um visor estereoscópico.
- **YouTube** pode impor limitações ao login e playback em navegadores integrados.
- **Netflix** pode negar playback protegido por DRM em web views e exigir o Safari/app oficial; o projeto não tenta remover proteções.
- O botão **Safari** abre o site fora do VR-OS como alternativa.
- A seleção de links/pesquisa depende de toque na tela; a pinça foi preservada para abrir apps e mover a janela pela alça branca. Ainda não há clique em links arbitrários por pinça.
- O sistema atual continua com cinema 2D/SBS/H-SBS/OU, fototeca e seleção de assentos da V11.

**Validação necessária:** instalar o IPA assinado em iPhone real, conferir a posição das janelas, navegação, rolagem, login, áudio duplicado e desempenho com múltiplas web views. Compilação não garante que os serviços de streaming liberem suas mídias.

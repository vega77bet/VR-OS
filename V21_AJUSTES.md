4. Alterar perfis de visor, IPD visual, altura e zoom; conferir ambos os olhos e persistência após reiniciar.
5. Alterar sensibilidade, cursor/esqueleto, opacidade e distância de novas janelas. Testar notas e sites.
6. Testar sliders reais sem perder o controle no meio do arraste; clicar +/- por pinça e evitar mudar o valor ao pinçar o título.
7. Alternar para 0,5x e voltar ao ARKit; testar comportamento sem permissão ou sem ultrawide.
8. Salvar opções do Cinema e confirmar que persistem depois de reiniciar.
9. Confirmar limpeza de favoritos e restauro geral em dois toques; verificar os valores restaurados.
10. Parar o uso em caso de tontura ou esforço ocular; verificar orientação, legibilidade e aquecimento por 10–15 minutos.

## Refinamentos de estabilidade (revisão final)

- **Rolagem estéreo:** qualquer olho pode receber o scroll de toque. O outro é posicionado diretamente na mesma altura, sem reconstruir a cena VR. Scroll por Vision usa o olho esquerdo como referência; a perda da mão cancela um gesto em andamento sem clicar.
- **Cursor recuperável:** mesmo que o usuário desligue “Mostrar cursor” para o ambiente VR, os Ajustes exibem um **cursor temporário de calibração**, para que ele consiga voltar a ligar a opção pela pinça.
- **Busca limpa ao reabrir:** a navegação de Ajustes começa sempre na lista completa, sem texto da busca anterior.
- **Sliders persistentes:** a tabela atualiza os valores visíveis sem recriar as células enquanto um slider está sendo arrastado.
- **Sensibilidade real:** testes de Vision confirmam que o limiar configurado altera o reconhecimento de pinça, mas mantém confirmação de dois quadros e histerese para evitar cliques espúrios.
- **Câmera protegida:** ao alternar 0,5x em Ajustes, a ultrawide libera a câmera antes de retomar o ARKit; caso a captura falhe, a Home restaura ARKit. A alternância do modo de câmera não é guardada como modo de inicialização permanente.
- **Restaurar preferências:** retorna as opções expostas neste app ao padrão e exige confirmação dupla. Preserva filmes, sites e outros conteúdos do usuário.

**Teste ainda obrigatório antes de declarar ausência de bugs físicos:** conferir em iPhone 15 dentro do VR Box a ordem dos olhos, acessibilidade dos botões, estabilidade do cursor, legibilidade, rolagem e calibração real das lentes; testes de compilação e geometria não validam esses pontos.

## Auditoria da branch V21

Na auditoria da branch `vr-os-21-native-settings-app`, foram revisados o catálogo, a sessão compartilhada, as duas `UITableView`, a geometria de entrada, o detector de pinça Vision, o runtime ARKit/3DoF, a câmera ultrawide e as integrações de Cinema, WebKit e preferências locais. A navegação usa IDs estáveis do catálogo; ações de restauração e favoritos têm confirmação dupla; e a troca 0,5x libera a captura antes de retomar o ARKit.

Verificação automatizada mais recente no GitHub Actions: testes Swift de geometria/catálogo/pinça, geração do projeto Xcode, compilação Release para `generic/platform=iOS` e empacotamento da IPA sem assinatura concluíram com sucesso. O artefato gerado foi `VR-OS-21-Native-Settings-unsigned-IPA`.

O check de `pull_request` também observa a base V20 usada pelo PR da V21. Permanecem fora do alcance do CI: câmera física, permissões reais, posição dos olhos no VR Box, conforto, legibilidade, teclado, rolagem óptica e calibração do iPhone 15; esses pontos exigem teste físico.


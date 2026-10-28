# V47 — Controle por alvo

O VR-OS agora possui um modo de entrada independente da câmera traseira.

## Como funciona

- O alvo circular é movido pela orientação relativa do iPhone usando Core Motion.
- O alvo aparece na mesma coordenada dentro dos dois olhos.
- Um botão só é acionado depois de o alvo permanecer sobre a mesma área pelo tempo configurado.
- O anel do alvo mostra o progresso; mover a cabeça para outro item cancela o clique.
- O intervalo padrão é de 1 segundo e pode ser ajustado entre 0,5 e 2 segundos em Ajustes > Mãos e gestos.
- O alvo continua disponível quando Vision ou ARKit não conseguem iniciar a câmera.
- O botão de recentralização do alvo será usado para recuperar uma posição confortável após colocar o iPhone no VR Box.

## Segurança de interação

O alvo só dispara áreas que já possuem hit-test no VR-OS. Textos informativos, áreas vazias e movimentos de janelas não são tratados como cliques. O clique é disparado uma única vez por permanência e precisa de uma nova entrada para disparar novamente.

## Testes

DwellControlTests cobre tempo mínimo, cancelamento ao trocar de alvo e alteração do atraso. A validação em aparelho físico ainda é necessária para calibrar a resposta do giroscópio, a posição do VR Box e o comportamento com a câmera indisponível.

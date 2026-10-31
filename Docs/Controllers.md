# Controles GameController e Joy-Cons — Etapa 2

O app utiliza exclusivamente o framework público **GameController**. Não implementa protocolo Bluetooth próprio, pareamento interno, rastreamento de mãos ou posição 6DoF. A implementação detecta o perfil que o iOS efetivamente disponibiliza; nenhum Joy-Con físico foi conectado neste ambiente de desenvolvimento.

## Parear no iPhone

1. Carregue os Joy-Cons e desconecte-os do Nintendo Switch se necessário.
2. No iPhone, abra **Ajustes → Bluetooth**.
3. Mantenha pressionado o pequeno botão SYNC do Joy-Con até as luzes indicarem busca e selecione o controle encontrado pelo iOS. Para usar os dois, repita para o outro Joy-Con.
4. Volte ao VR-OS e abra **Controles**. Confira nome, entradas/eixos detectados e selecione a fonte ativa quando houver mais de uma.
5. Use primeiro o modo **Analógico** e verifique cada entrada antes de colocar o telefone no VR Box. A interface do aplicativo não promete iniciar o pareamento nos Ajustes.

Consulte também [o procedimento Apple para parear controles](https://support.apple.com/111099). O app exige iOS 17 ou superior. Compatibilidade do modelo, firmware e forma de apresentar um par precisam ser verificadas no iPhone usado no teste.

## Perfis e capacidades

`GCController.controllers()` enumera os controles reconhecidos. As notificações públicas de conexão e desconexão atualizam o registro, e `physicalInputProfile.buttons` / `dpads` determinam as entradas disponíveis. Um Joy-Con esquerdo, direito ou par pode ser exposto de forma diferente; o código não conclui capacidades pelo nome do produto.

| Configuração | Comportamento implementado | Validação física |
| --- | --- | --- |
| Joy-Con direito | Usa botões/eixos/atitude somente se expostos pelo perfil | Pendente |
| Joy-Con esquerdo | Mesma detecção; um único analógico pode orientar o ponteiro | Pendente |
| Par reconhecido como uma fonte pelo iOS | Usa o perfil combinado disponibilizado pelo sistema | Pendente |
| Dois Joy-Cons expostos como fontes separadas | Usuário seleciona uma fonte ativa; o app não funde protocolos/IMUs de dois dispositivos | Pendente |
| Perfil sem analógico nem atitude | Botões disponíveis continuam mapeáveis; use a mira da cabeça para apontar | Pendente |
| Bateria do controle | Exibida apenas se `GCDeviceBattery` informar estado conhecido e nível válido | Pendente |

IDs identificam a conexão atual, não uma identidade persistente do hardware. Ao trocar, desconectar ou retomar, botões já pressionados ficam bloqueados até serem soltos. Um controle desconectado não pode continuar enviando ações por um snapshot antigo. O registro e as regras de disponibilidade são testáveis sem hardware.

## Botões

Os nomes **A/B/X/Y são os botões lógicos da Apple**, conforme a posição do perfil, e não uma garantia de correspondência com as letras impressas no Joy-Con. O usuário pode remapear entradas detectadas. A tabela descreve o padrão de software; nenhuma linha equivale a um botão fisicamente confirmado neste ambiente.

| Entrada pública detectada | Ação padrão | Estado |
| --- | --- | --- |
| Gatilho direito / equivalente ZR | Selecionar | Implementado; hardware pendente |
| Botão lógico A, inferior | Selecionar | Implementado; hardware pendente |
| Gatilho esquerdo / equivalente ZL | Agarrar janela enquanto mantido | Implementado; hardware pendente |
| Botão lógico B, direito | Voltar | Implementado; hardware pendente |
| Botão lógico X, esquerdo | Aplicativos | Implementado; hardware pendente |
| Botão lógico Y, superior | Recentralizar | Implementado; hardware pendente |
| Menu / equivalente + | Menu rápido | Implementado; hardware pendente |
| Opções / equivalente − | Início | Implementado; hardware pendente |
| Ombros, cliques dos analógicos, direcional, Home | Remapeáveis quando expostos | Implementado; hardware pendente |

O mapeamento efetivo remove entradas indisponíveis e reúne aliases numa única ação: manter A e ZR simultaneamente não deve duplicar seleção. Quando nenhuma entrada mapeada para seleção existe no perfil, a camada adiciona uma alternativa entre os botões realmente disponíveis, com preferência por A, gatilho direito, X e ombros. Se há apenas um botão, esse fallback pode tomar o lugar da sua ação padrão; confira o mapeamento efetivo antes de usar o visor.

## Modos do ponteiro

**Analógico é o padrão.** O integrador de interação usa o analógico direito quando disponível, ou o esquerdo em perfis de um analógico. O outro eixo pode servir à navegação/rolagem. Sensibilidade e modo de entrada ficam salvos. Sem eixos expostos, o app não inventa valores: utilize a mira da cabeça e os botões disponíveis.

**Movimento é experimental e opt-in.** O adaptador só oferece amostras se `controller.motion` existir e `motion.hasAttitude` for verdadeiro. Sensores que exigem ativação manual usam a API pública `sensorsActive`, apenas para o controle ativo e quando o modo foi habilitado. `hasAttitudeAndRotationRate` é obsoleta desde iOS 14; `hasAttitude` é a capacidade relevante. Não existe uma propriedade pública `readsMotionData` usada por esta implementação.

`ControllerInputFrame.motionOrientation` contém o quaternion **bruto normalizado** de `GCMotion.attitude`, em ordem Hamilton XYZW. A documentação Apple define atitude como orientação do corpo relativa ao referencial do controle, mas não fornece uma convenção física única para a posição de uso de um Joy-Con no VR Box. Por isso esse valor não recebe a transformação do Core Motion da cabeça e não é apresentado como uma pose mundial validada.

O integrador calibra uma orientação inicial e trabalha com variação relativa; inversão horizontal, vertical e troca dos eixos estão disponíveis para validar a montagem real. Esses ajustes não comprovam, por si sós, a precisão de um Joy-Con. Se as respostas físicas não forem consistentes, retorne ao analógico. Não há integração de aceleração para estimar posição. A origem do laser é virtual e não representa a localização física da mão.

## Teste físico necessário

- Execute cada configuração separadamente: esquerdo, direito e par.
- Registre iOS, firmware, nome e botões/eixos/capacidades exibidos.
- Teste cada botão e remapeie equivalentes antes de usar o visor.
- Desconecte durante foco, seleção e arrasto; confirme cancelamento e fallback sem clique involuntário.
- Troque a fonte ativa com botões pressionados e confirme que só a próxima pressão após soltura produz ação.
- No modo analógico, teste zona neutra, direção, sensibilidade e a retenção do cursor sem movimento do eixo.
- Habilite movimento somente se a capacidade estiver disponível; calibre apontando em frente, teste yaw/pitch/roll isoladamente e confira os ajustes de eixos.
- Não classifique movimento como funcional em hardware sem executar esses testes. Registre latência, tremor, deriva, bateria e conforto sem assumir 60 FPS sustentados.

## Referências públicas

- [GCController](https://developer.apple.com/documentation/gamecontroller/gccontroller)
- [GCPhysicalInputProfile](https://developer.apple.com/documentation/gamecontroller/gcphysicalinputprofile)
- [GCMotion](https://developer.apple.com/documentation/gamecontroller/gcmotion)
- [GCMotion.hasAttitude](https://developer.apple.com/documentation/gamecontroller/gcmotion/hasattitude)
- [GCMotion.attitude](https://developer.apple.com/documentation/gamecontroller/gcmotion/attitude)
- [GCMotion.sensorsActive](https://developer.apple.com/documentation/gamecontroller/gcmotion/sensorsactive)
- [GCDeviceBattery](https://developer.apple.com/documentation/gamecontroller/gcdevicebattery)

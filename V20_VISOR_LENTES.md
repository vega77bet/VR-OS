# VR-OS V20 — visor binocular em formato de lente

Versão **4.6.0**, build **20**. Baseada na V19 (0,5x real, Vision mãos/pinça e CoreMotion 3DoF).

## Objetivo

Recriar os **dois blocos curvos** da imagem do usuário, mais próximos do centro da tela e com fundo preto. **Não é reconstrução óptica 3D calibrada**: a câmera traseira ainda envia a mesma imagem monocular para os dois olhos.

A antiga Home dividia a tela em uma HStack de duas metades fixas. Agora o VRHomeView calcula a posição em relação à **tela completa**, usando VRLensSettings.placement para os centros e dimensões e VRLensAperture para a máscara curva.

## Perfil Referência (padrão)

| Medida | Porcentagem da tela |
|---|---:|
| Largura da abertura de cada olho | 28,5% |
| Altura de cada olho | 60% |
| Distância entre centros | 30% da largura |
| Centros horizontais | 35% e 65% da largura |
| Centro vertical | 62,5% da altura |

Esses números reproduzem aproximadamente a imagem enviada (1536×735): duas aberturas ~438×441 pixels, com centros X≈538 e X≈998 e Y≈459.

**VR Box +** aumenta o visor para 36% da largura por olho e 87% da altura, centralizando em Y=50%, com centros afastados 37,8% da largura. **Compacto** usa 26,5% da largura, 66% da altura, Y=54% e centros separados por 29,5%.

Os valores são percentuais da tela, **não medidas físicas em mm**. O algoritmo impede sobreposição e corte pelas bordas, mesmo quando tamanho e espaçamento estão nos extremos.

## Controles

Acesse **Visor** no oitavo botão do dock, por toque ou pinça:

1. Perfis: Referência, VR Box +, Compacto.
2. Tamanho ±: 75% a 140% do perfil.
3. IPD ±: aproxima ou separa os centros *visuais* dos olhos. Não mede o IPD físico da pessoa.
4. Altura ±: desloca as duas áreas verticalmente.
5. Zoom ±: 80% a 130% da **imagem digital da câmera**. Acima de 100% recorta o enquadramento; isso **não muda a lente ultrawide física 0,5x**.
6. Curva ±: de área retangular até máscara com bordas convexas.

Configurações são mantidas no UserDefaults. O painel é escalado para caber mesmo quando o usuário escolhe uma abertura muito pequena, e as hitboxes por pinça obedecem ao mesmo fator.

## Compatibilidade

**ARKit normal:** máscara do visor envolve a câmera, as janelas e os menus. O tamanho de viewport passado ao rastreamento da mão e à projeção espacial corresponde à nova abertura.

**Ultrawide real 0,5x:** a mesma máscara é aplicada ao fluxo da lente física. Vision e CoreMotion permanecem ativos com mão/pinça e orientação 3DoF, mas **não há posição ARKit 6DoF**. O modo Tela toda mostra o frame completo (pode causar barras pretas), enquanto Preencher recorta as laterais.

**Cinema:** as mesmas duas aberturas e o mesmo desenho curvo são aplicados às cenas do Cinema; o modo continua usando SceneKit, sem recriar suas câmeras ou o player.

**Central de Apps:** o menu antigo com sete linhas ficava maior que o visor compacto; a V20 mostra apenas as linhas que cabem e tem botões **Anterior/Próxima**. Todas as páginas funcionam por pinça ou toque. Os cartões do menu Temas diminuem quando o visor é baixo.

**Dock:** oito ícones distribuídos pela área útil de cada lente, agora com o botão Visor. A hitbox de pinça segue a geometria exibida.

## Limites reais

A máscara não aumenta o campo de visão físico da lente do VR Box ou do sensor. O efeito depende de distância olho-tela, encaixe e lente real. Zoom digital e Preencher podem **reduzir** a área de cena que aparece. A V20 não implementa correção radial calibrada da óptica, IPD em milímetros, nem câmera traseira estéreo verdadeira.

Os testes automáticos do GitHub validam os percentuais da imagem, limites de tamanho/IPD, clique por pinça no painel e paginação dos sete apps. A build Release iOS e a IPA unsigned são geradas no CI.

**Ainda é necessário testar no iPhone 15 com o VR Box real.** Para isso: comparar o perfil Referência com a imagem, depois VR Box +, ajustar IPD visual, altura, zoom; testar mão, menus, 0,5x, retorno ao ARKit e Cinema. Não usar se provocar tontura ou esforço ocular. O IPA unsigned exige assinatura para instalar.

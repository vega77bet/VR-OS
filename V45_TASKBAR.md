# V45 — Barra de tarefas

V45 replaces the old dock with a single, predictable binocular taskbar.

The taskbar uses the supplied VR-OS SVG family for its eight primary actions:
Central, Apps, Cinema, Arquivos, Fotos, Navegador, Ajustes and Janela.
The first integration imports the default and active vector states into the
Xcode asset catalog; the remaining states stay available for the next screens.

Rendering and Vision hit-testing share the same VRTaskbarGeometry rectangles.
The bar has a dedicated bottom safe area, selected feedback, enlarged pinch
hit regions and reduced-motion support. The old 0.5x camera action is not
exposed by the new taskbar.

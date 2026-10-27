# V45 — Barra de tarefas

V45 replaces the old eight-button dock with a single, predictable binocular
taskbar. It uses one geometry model for rendering and Vision hit-testing, so
the left and right eyes receive the same action coordinates.

Primary actions:
- Central
- Apps
- Cinema
- Arquivos
- Fotos
- Navegador
- Ajustes
- Janela

The bar keeps 44pt-class interaction targets, selected-state feedback, a
bottom safe area and reduced-motion support. The old camera 0.5x action is no
longer exposed by the taskbar.

The supplied SVG asset pack is represented through stable action names and
will replace the temporary SF Symbol fallbacks when its xcassets catalog is
imported into the application target.

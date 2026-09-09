# Resumen sobre la identidad existente · 6 de septiembre de 2026

Punto de partida: el Resumen tal como está en producción (`HEAD 96f2038`, hero navy + tarjetas). Se restauraron desde ese commit `resumen-gerencia.tsx`, `inteligencia-comercial.tsx`, `gerencia.tsx`, `gerencia.css` y sus pruebas; los tres componentes del intento (IndicadorVisual, AnalistasVisuales, EvolucionLlegadas) se retiraron del árbol. El intento sigue guardado en `../bloque-a-2026-09-06/intento-no-aprobado/` y su baseline intermedio en `../bloque-a-2026-09-06/evidencia/baseline/`.

Tres ajustes, todos justificados por el playbook UI-UX (carga cognitiva, «si todo destaca nada destaca», móvil):

1. La tarjeta «Conversión del mes» se quita de la fila de KPI: repetía el mismo número y la misma base que el héroe. Quedan tres tarjetas que sí añaden información (leads que cerraron, capital exacto con TC, citas con pactadas).
2. Un solo acento en las tarjetas y en las barras de «Mejores analistas». Los cuatro colores por tarjeta eran decorativos y las barras verde/ámbar/rojo insinuaban cumplimiento donde solo hay posición.
3. Móvil: las tres pastillas del héroe pasan a una fila compacta en vez de tres bloques altos.

Sin cambios en datos, fórmulas, permisos ni backend. Pruebas: 338/338 en `screens/hoy` y `components/gerencia`; typecheck limpio. Sin commit: pendiente de la revisión de Miguel.

Capturas: `antes-*` = producción, `despues-*` = con los tres ajustes; `comparacion-*.png` lado a lado.

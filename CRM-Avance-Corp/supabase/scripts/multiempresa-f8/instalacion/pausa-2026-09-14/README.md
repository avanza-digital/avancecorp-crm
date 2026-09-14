# Pausa segura F8 — 14/09/2026

Pausa solicitada por Miguel. Dos SQL de producto aprobados, sin instalar.
La rama exclusiva fue eliminada y su ausencia confirmada. Producción conserva
279 migraciones, F3 ON y F4–F7 OFF; objetos F8 ausentes.

- `estado.json`: estado comprobado al detenerse.
- `paridad-edge.json`: 19 Edge / 55 archivos iguales en ese corte.
- `revision-reconstruccion-pedido.txt`: evidencia enviada al reviewer aislado.
- `revision-reconstruccion-claude.txt`: CHANGES_REQUESTED; no PASS de instalación.

Los tres ensayos fallidos fueron revertidos. La alternativa que conserva public
solo está preparada. Evaluación completa y correcciones del PRIMARY pendientes
por la pausa; no ejecutar el borrador automáticamente. El reviewer no recibió
su SQL completo: las hipótesis y el orden inferido deben cotejarse con el código.
No seguir literalmente su sugerencia de borrar filas de pg_default_acl.

Estos archivos no contienen dumps, contraseñas, tokens ni fixtures. Los accesos
y borradores privados permanecen fuera de Git. Ningún corte sustituye las
capturas actuales obligatorias de una nueva instalación.

Punto de retoma en el vault: F8 - pausa segura de instalacion (2026-09-14).

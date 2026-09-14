# Evidencia de instalación F8 apagada — 14/09/2026

Resultado y límites: [acta de publicación](../../PUBLICACION-2026-09-14.md).
Estos archivos contienen metadatos, conteos y huellas; no contienen filas de
clientes, sesiones, contraseñas, claves privadas ni dumps de producción.

- `preflight-final.json`: precondiciones vivas antes del merge.
- `rama-premerge.json`: solo dos migraciones adicionales en la rama ensayada.
- `merge-respuesta.json`, `post-estado.json`: operación y ledger posterior.
- `post-recibo-sql.json`: sentencias literales y orden de ambos archivos.
- `post-catalogo-*.json`, `post-recibo-paridad.json`: catálogos del mismo
  intervalo de 13 segundos y comparación posterior con el manifiesto exacto
  [revisado](../reanudacion-2026-09-14/diferencias-aceptadas.json).
  Se guardan compactos; sus datos son idénticos a la captura privada original.
- `post-seguridad.json`: control, flags, RLS, ACL y cobertura.
- `huellas-antes-merge.json`, `post-huellas.json`, `post-actividad.json`,
  `post-fuentes-anteriores.json`, `post-auditoria-resumen.json`: conservación
  del corte anterior y actividad concurrente identificada. Auth/perfiles
  cambiaron; no se declara igualdad bit a bit ni se restaura su estado anterior.
- `edge-premerge.json`, `post-edge-recibo.json`, `post-edge-inventario.json`:
  55 archivos cotejados antes del merge; después, 19 inventarios y hashes de
  bundle idénticos, sin una nueva descarga de todos los archivos.
- `post-config-api.json`, `post-http.json`: configuración pública y disponibilidad.
- `post-rama-eliminada.json`: eliminación de la rama propia y lectura posterior.
- `manifest.json`: tamaños y SHA-256 de los archivos de evidencia.

No se presentan las pruebas sintéticas como aceptación del piloto real. G7
permanece abierto; las comisiones se calculan fuera del CRM.

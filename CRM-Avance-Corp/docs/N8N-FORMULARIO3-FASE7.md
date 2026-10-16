# Formulario 3 — fase 7: celda rara, clientes sin registrar y resumen diario

15/10/2026. Estado: **PUBLICADA Y VERIFICADA en producción** (19:02 Lima), desde `2ed57674` (PR #300 fusionada en `main`). Miguel autorizó publicar en n8n.

## Qué cambia

1. **Una celda rara ya no frena la vuelta.** `prepararFilaSegura` (en `scripts/n8n/formulario3.fase7.mjs`) recupera solo el error de tipo de celda de `texto()`. Esa fila queda como recibo `rechazado` con la columna afectada («Celda con un dato inesperado en «ciudad»») y las demás siguen. Un `row_number` inválido o un cambio de cabecera siguen frenando todo.
2. **Aviso del cliente que no se pudo registrar.** `cerrarVuelta` reúne en un solo error las filas para revisar (rechazos y `ya_cliente` cuyo estado no está en la lista de estados correctos de `clasificarRespuestaPuerta`) y las pendientes. Formato: `Revisar filas de la hoja: 3 (rechazada), 4 (cliente sin registrar). Pendientes para reintentar: 5.` El aviso por correo copia solo ese texto (números y etiquetas fijas); cualquier otro error sigue sin contenido crudo.
3. **Latido y resumen diario.**
   - Nodo «Registrar latido», colgado de «Identificar fila» y con `executeOnce`: hace un upsert en la tabla `CJpN45ukEXmZInuG` con `leido_en` y `filas_leidas` cada vez que la hoja se lee con al menos una fila.
   - Flujo `Chn5g93IgxNlkF3K` («Avance Corp — Resumen diario de Formulario 3»): a las 19:00 Lima cuenta los recibos desde las 19:00 del día anterior (sin huecos ni solapes).
   - Avisa con ⚠️ si la última lectura tiene más de 20 minutos. Si un día no llega el correo, algo falla (n8n, Gmail o el resumen).

## Evidencia

- `node --test scripts/n8n/` → **57/57 PASS** (incluye fases 1–6). Los tests importan el clasificador real del CRM (`resultado-importacion.ts`) y prueban todos sus estados de «ya es cliente», con y sin asesor.
- **Mutantes:** 12 sobre las defensas nuevas, todos MUERTOS (estado de cliente, celda rara, pendientes, latido colgado de otro nodo, latido debajo, ventana horaria, margen de 20 min, copia del error al correo, patrón del asesor, versión exigida, versión publicada, tablas del banco).
- **Codex, plan:** CHANGES REQUIRED, 7 hallazgos incorporados.
- **Codex, código:** CHANGES REQUIRED.
  - Aceptados: versión exigida (`VERSION_FASE6`) y versión publicada; banco sin ninguna tabla productiva; nombre del asesor sin `():`, que evita que un error pase por éxito; comparador del latido con todos los ajustes del nodo.
  - Hoja vacía: el latido solo se escribe si hay filas. Se mantiene así y el correo lo dice («el flujo está detenido o la hoja quedó vacía»): vaciar una hoja acumulativa también merece revisión.
- **Banco aislado** `IbHjfwXuPbxeKNrt` (filas ficticias, CRM simulado, tablas de prueba), ejecución manual 268:
  - el latido corrió antes de la importación (`executionIndex` 5, 4 filas);
  - fila 3 (VERDADERO en «ciudad») → `rechazado`;
  - fila 4 → `ya_cliente` sin registrar;
  - fila 5 → `pendiente`;
  - error final exacto: `Revisar filas de la hoja: 3 (rechazada), 4 (cliente sin registrar). Pendientes para reintentar: 5. [line 217]`. El sufijo `[line N]` está contemplado en el aviso.
- **Resumen**, ejecución manual 269:
  - leyó los 152 recibos (paginación completa);
  - 116 nuevos y 36 duplicados, igual que el acta de fase 6;
  - asunto `[PRUEBA]`, porque el disparo no fue el programado;
  - el latido vacío generó el aviso ⚠️;
  - Gmail `SENT`.
- **Error Trigger real del banco:** banco publicado una sola vez con su copia de avisos `bq7R13pHeI7g1Q58`.
  - Ejecución de producción 272 → aviso 273.
  - Correo `[PRUEBA F7]` enviado: «Revisar filas de la hoja: 3 (rechazada), 4 (cliente sin registrar). Pendientes para reintentar: 5.», sin el sufijo `[line N]`.
  - Las dos copias se despublicaron enseguida: no hubo más ejecuciones.
- Pre-push: app 429 archivos / 6.915 tests PASS. `npm run check:scripts` PASS.
- **NOT RUN:** primer correo programado del resumen (16/10, 19:00 Lima; hoy ya había pasado la hora al publicar).

## Publicación (hecha el 15/10, 18:58–19:05 Lima)

1. **Aviso** `4jfthNhVJLiZUeIo`: `prepararAlerta` nuevo, publicado como versión activa `505bcd5e`.
2. **Importador** `BjI5m1PKVWhO0NDb`:
   - Sin ninguna vuelta en curso, ni antes ni después de despublicar.
   - `operacionesFase7` aceptó la fase 6 exacta (`e2f62a7e`).
   - La primera comprobación detectó que el envío había convertido el texto `̀-ͯ` de `normalizarRespuesta` en caracteres. Era equivalente, pero no idéntico. Se reenvió escribiendo `\u0300` y el código quedó igual al del repo.
   - `verificarFase7` PASS como borrador. Publicado como versión `b6c88f1b`; `verificarFase7(..., { publicado: true })` PASS.
3. **Resumen** `Chn5g93IgxNlkF3K`: publicado como versión `452ba77d`.
4. **Primera vuelta real** (00:05 UTC):
   - latido `leido_en` 19:05:12 Lima, `filas_leidas` 152;
   - 0 ejecuciones con error;
   - 152 recibos intactos (la hoja no tenía filas nuevas).
5. **Banco archivado** (`IbHjfwXuPbxeKNrt`, `bq7R13pHeI7g1Q58`). Sus tablas de prueba (`5Ls25BfGtRY9fovr`, `YKjmAhMrzJc6qxGg`, `L8xIasab8hOzYxc5`) quedan con datos ficticios: el MCP no permite borrar tablas.

**Volver atrás:** `restore_workflow_version` a `e2f62a7e`, publicar y pasar `verificarFase6`. Despublicar el resumen. Los leads y los recibos no se tocan.

**Cambios futuros del importador:** se parte de `cargarDefinicionOperativaF7()` y se verifican con `verificarFase7`; la fase 6 queda como base histórica.

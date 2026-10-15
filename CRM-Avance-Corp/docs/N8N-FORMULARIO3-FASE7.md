# Formulario 3 — fase 7: celda rara, clientes sin registrar y resumen diario

15/10/2026. Estado: **código, pruebas y banco listos; sin publicar en el importador**. La publicación necesita que Miguel autorice publicar flujos en n8n (el clasificador de permisos la bloqueó).

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
- **NOT RUN:** Error Trigger real del banco y publicación de los tres flujos (requieren publicar en n8n); primer correo programado de las 19:00.

## Publicación (pendiente)

1. Publicar el aviso compatible (`4jfthNhVJLiZUeIo`, `prepararAlerta` nuevo) y comprobarlo.
2. Comprobar que no hay ninguna vuelta en curso, despublicar el importador `BjI5m1PKVWhO0NDb` y volver a comprobarlo.
3. Aplicar `operacionesFase7(actual)` y volver a leer el flujo.
4. Pasar `verificarFase7(actual)`, publicar y pasar `verificarFase7(actual, TABLA_LATIDO, { publicado: true })`.
5. Publicar el resumen `Chn5g93IgxNlkF3K`.
6. Observar: el latido se mueve cada 5 minutos, 0 errores y los 152 recibos siguen intactos.
7. Archivar el banco (`IbHjfwXuPbxeKNrt`, `bq7R13pHeI7g1Q58`) y vaciar sus tablas de prueba.

**Volver atrás:** `restore_workflow_version` a `e2f62a7e`, publicar y pasar `verificarFase6`. Despublicar el resumen. Los leads y los recibos no se tocan.

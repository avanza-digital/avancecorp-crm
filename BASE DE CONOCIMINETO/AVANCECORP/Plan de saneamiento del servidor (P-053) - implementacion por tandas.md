# Plan de saneamiento del servidor (P-053) — implementación por tandas

Plan de implementación de los hallazgos de [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]]. Cada tanda = una rama de banco + migración + gate RLS + auditor-rls + release, con su prueba de cierre dicha. Las tandas 1–3 son chicas y van primero; la 4 responde a la pregunta de los duplicados de productos; la 7 es el refactor grande y va por contagio, no por campaña.

**Reglas transversales:** nada se borra sin pasar antes por REVOKE (apagado reversible) + tiempo de observación. Toda migración se ensaya en rama de banco con la receta de [[banco-branch-replay-manual]]. Toda lógica nueva nace en `private`; los envoltorios solo autorizan.

---

## Tanda 1 — Rastro de auditoría completo (cierra el único ROTO)

**Problema:** los co-titulares de cuentas mancomunadas se agregan/eliminan sin rastro (`contrato_titulares`: 0 entradas en audit_log vs 1 083 de contratos). Además `actividades_cliente` (camino de escritura ya expuesto, 0 filas — cablear ANTES de que estrene datos) y `agenda_ics` (rotación de token sin rastro) tampoco auditan.

**Qué se hace (1 migración):**
1. `CREATE TRIGGER trg_audit_contrato_titulares AFTER INSERT OR UPDATE OR DELETE ON public.contrato_titulares ... EXECUTE FUNCTION public.log_audit_change()` — id es uuid, aplica tal cual (verificado).
2. Lo mismo con `private.log_audit_crm` sobre `crm.actividades_cliente` y `crm.agenda_ics` (familia crm; agenda_ics no tiene `id` pero sí `perfil_id` uuid — el fallback de log_audit_crm funciona, verificado).
3. `crm.usuario_eventos` **NO recibe trigger**: su `id` es BIGINT y `log_audit_crm` castea `::uuid` — abortaría todo DML. Es en sí una bitácora append-only: se declara como tal con `COMMENT ON TABLE`.
4. `suscripciones_push` y `novedades_leidas`: se declaran sin auditoría a propósito (dato técnico sin valor probatorio), con COMMENT.

**Prueba de cierre (en rama):** insertar/actualizar/borrar una fila de prueba en cada tabla → aparece en audit_log con quién/cuándo/antes/después; el mutante (quitar el trigger) hace fallar la prueba. Gate RLS entero.
**Riesgo:** bajo. **Esfuerzo:** una sesión. **Decisión de Miguel:** ninguna.

## Tanda 2 — Malla anti-NaN del dinero (ANTES del 10/09)

**Problema:** en PG17 `NaN > 0` es TRUE. La regla canónica (`x <> 'NaN' and x > 0`) vive completa solo en `cierres_externos.monto`. Sin ningún CHECK: `cronograma_pagos.monto_programado/monto_pagado` (4 219 filas) y todos los campos de `cierre_mes_vendedor` y `periodos_cerrados.ponderacion_referido`. Solo `>= 0` (NaN pasa): `lead_asignaciones.monto_estimado` y los 6 de `ajustes_mes_cerrado`. Un NaN contamina toda suma del portal o del sellado mensual.

**Qué se hace (1 migración):** añadir a cada columna el CHECK que corresponda — `> 0` donde cero es inválido (monto_programado), `>= 0 and <> 'NaN'` donde cero es legítimo (pendientes, ajustes), `between 0 and 1 and <> 'NaN'` en ponderaciones. Pre-verificado: **0 filas violan hoy** y las tablas del sellado están vacías — los CHECKs entran sin tocar datos.
**Prueba de cierre:** en rama, intentar meter NaN y negativo en cada columna → rechazo con error claro; el sellado de prueba del cierre de mes sigue pasando.
**Riesgo:** bajo (cero datos afectados). **Esfuerzo:** una sesión. **Fecha dura: publicada antes del primer sellado real del 10/09.**

## Tanda 3 — Cierre de superficie (grants heredados + puertas de borrado)

**Problema:** `anon` y `authenticated` tienen los 8 privilegios (incluido TRUNCATE, que la RLS **no** gobierna) sobre las 10 tablas core del portal, `audit_log` incluida; 5 RPCs `admin_*` ejecutables por `anon`; un admin puede borrar cuotas pagadas por API sin que nada lo audite (`cronograma_admin_elimina` + trigger solo-UPDATE); `superadmin_elimina_perfiles` no limita el rol del perfil objetivo; la edge `eliminar-cliente` cascadea `crm.cuentas_bancarias` sin saberlo (5 clientes expuestos).

**Qué se hace:**
1. Migración de REVOKEs: todo de `anon` en las 10 tablas; TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de `authenticated`; EXECUTE de `anon`/PUBLIC en las 5 RPCs admin y las funciones de trigger; `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` en crm y private (que la próxima función no nazca abierta).
2. En la misma tanda: trigger de auditoría en DELETE de `cronograma_pagos` (reusa log_audit_change) y condición `rol='cliente'` (o la que Miguel decida) en `superadmin_elimina_perfiles`.
3. La edge `eliminar-cliente`: añadir chequeo previo «este cliente tiene cuentas bancarias / actividades en el CRM» → bloquear o avisar (decisión de Miguel cuál de las dos).
**Prueba de cierre:** smoke del portal completo con cuenta admin real (pagos, dashboard, novedades siguen funcionando — `authenticated` conserva lo que usa); gate RLS 1175; intento de DELETE de cuota por API → rechazado o auditado.
**Riesgo:** medio (tocar grants del portal vivo → por eso rama + smoke). **Esfuerzo:** 1–2 sesiones. **Decisiones de Miguel:** el alcance de `superadmin_elimina_perfiles` y bloquear-vs-avisar en eliminar-cliente.

## Tanda 4 — Productos y contratos duplicados (los «4 pares»)

**F0 · Decisión previa (Miguel):** ¿la frontera catalogada (para la que nacieron los 6 `*_contrato_producto`) se estrena o no?

**F1 · Un solo criterio de «producto seleccionable» (va sí o sí):**
- Crear `private.producto_condiciones_seleccionables(...)` con el predicado único (activo + no legacy + versión publicada + vigencia + condición activa).
- Reescribir sus 3 copias para que lo consuman: el WHERE de `crm.productos_inversion_seleccion_fn`, el `seleccionable_nuevo` de `public.productos_inversion_seleccion_fn` y el EXISTS de `crm.cerrar_altas_legacy_productos`. Las DOS funciones selectoras se quedan (columnas distintas por superficie es diseño legítimo); solo el criterio se unifica.
- **Prueba de cierre:** paridad byte a byte — se captura la salida de ambas selectoras (md5 del jsonb agregado) antes y después en la rama, deben ser idénticas; mutante: relajar el predicado único debe cambiar ambas a la vez.

**F2 · El trío dormido, según F0:**
- **Si se estrena:** un solo cuerpo interno en `private` por operación (crear/actualizar/actualizar-con-cuenta) que incluya la coreografía del GUC `crm.producto_condicion_id` UNA vez (con guardar-y-restaurar, la variante correcta para anidamiento — hoy crm resetea a `''` y public restaura: esa divergencia muere aquí). `crm.*` y `public.*` quedan como envoltorios de 5 líneas que solo ponen el gate de su superficie.
- **Si no se estrena:** retiro en 3 pasos — (1) quitar el guard `to_regprocedure` de `cerrar_altas_legacy_productos`; (2) REVOKE EXECUTE de las 6 (apagado reversible); (3) DROP semanas después si nada gritó. Antes del REVOKE: re-medir logs (ventana de 24 h, repetir varios días) — hoy: cero tráfico, cero llamadores en fronts, edges vivas y base.
**Esfuerzo:** F1 una sesión; F2A dos sesiones; F2B una. **Riesgo:** bajo (nadie las llama hoy).

## Tanda 5 — Retiros programados (todo con OK explícito de Miguel)

**Problema:** superficie viva que nadie usa: `crm.contrato_pdf_snapshot_v2` (muerta confirmada — ni ejecutable), `contrato_pdf_archivo_fn` / `registrar_candidato_usuario_fn` / `crear_contrato_con_cuenta_producto` (superadas por el flujo vigente; cero hits en fronts, 16 edges vivas y logs), `metricas_distribucion_leads_fn` v1 (cero tráfico), las 2 RPCs `pagos_admin_*` sin front, y la edge `diagnostico-push` (stub 410 desplegado y ACTIVE).

**Qué se hace:** mismo protocolo de 3 pasos: re-medir logs varios días → REVOKE (o pausar la edge) → observar → DROP. **Antes:** (a) abrir a mano el Apps Script de la hoja del puente y confirmar que no llama ninguna (este entorno no puede leerlo); (b) que Miguel diga qué consume el rol `crm_metricas_bridge` (conexión directa, invisible en estos logs).
**Aparte, decisión de producto (no retiro):** las 4 funciones esperando pantalla (`resumen_tareas_fn`, `resumen_cartera_clientes_fn` → previews mi-cartera/ficha-360; `contratos_por_periodo_comercial_fn`, `corregir_fecha_cierre_comercial` → UI de período comercial): publicar la pantalla o retirar el par.

## Tanda 6 — Modelo de datos (medio plazo, sin fecha dura)

1. **Documentos:** corregir a mano los 3 perfiles divergentes (2 DNI nulos, 1 malformado — con Miguel, son datos reales de clientes) → CHECK de formato por tipo en `perfiles` y `contrato_titulares` (copiando la regla de `cierres_externos`). Hoy esos 3 quedan fuera de todo cruce por DNI.
2. **Listas fijas:** tabla de referencia (o dominio) para las listas repetidas en 4+ tablas — `moneda` (×7) y `categoria` (×4) primero; los 7 motivos de descarte (hoy por triplicado) migran a FK contra `enfriamiento_politica`. Las listas ×2 se quedan como están (tolerables).
3. **NOT NULL:** las 10 columnas de timestamps/autoría del portal 100 % pobladas (`creado_en`, `actualizado_en`, `contratos.creado_por`) → `SET NOT NULL` en una migración (cero datos que tocar, verificado).
4. **Índices, una sola tanda medida en rama (planes antes/después):** crear los 5 índices FK de tablas que crecen (`lead_sla_etapas.politica_id`, `tareas.asignado_supervisor_id`, `lead_sla_ciclos.politica_id`, `leads.asignado_supervisor_id`, `producto_condiciones.version_id`) y soltar los 8 redundantes (siempre el no-UNIQUE; `idx_perfiles_rol` con verificación extra de latencia de los helpers).

## Tanda 7 — El refactor grande, por contagio (roles · errores · zona horaria)

**Problema:** matriz de roles copiada en ~114 funciones (20 con el gate entero inline), textos de error duplicados (70 ocurrencias en 4 familias), `America/Lima` en 47 funciones, `v_actor`/`v_uid` partido 40/35.

**Cómo se ataca (sin campaña de 114 ediciones):**
1. **Regla desde hoy:** toda función nueva autoriza con helpers (`private.rol_crm`, familia `puede_*`), nunca lista inline; el actor se llama `v_actor`. (Se escribe en el CLAUDE.md del CRM.)
2. **Pase chico inmediato:** las **20 funciones con `rol_crm in (...)` inline** migran a un helper de capacidad en una tanda — son copias literales, cambio mecánico, verificable con el gate RLS 1175.
3. **Catálogo de errores:** helpers `private.err_no_autorizado()`, `err_contrato_no_encontrado(...)` etc. — se usan en código nuevo y en cada función que se toque; no se persiguen las 199.
4. **Zona horaria:** no se reemplaza el literal por una función (cambiaría planes de ejecución); se agrega **una prueba de guardia** a la suite: consulta a `pg_proc` que falle si aparece cualquier zona horaria distinta de `America/Lima` — el punto único de verdad pasa a ser el test.
5. **El resto baja por contagio:** P-050/051/052 reescribe las 16 de capital y 21 de leads → sus gates migran gratis en ese mismo pase; toda función tocada por otra razón migra su gate.

## Fuera de tanda (arreglos puntuales independientes)

- **Bug `crm-usuarios`:** password inicial = documento sin relleno → un pasaporte de 6–7 caracteres muere en el mínimo de 8 de Auth. Fix de una línea (padStart o password aleatorio) + redeploy de la edge (con las reglas de deploy de edges: contrastar árbol↔función viva antes).
- **D3 · convención del log partido** (`crm.leads` con esquema vs `contratos` sin): decisión aparte — mínimo viable: documentarla y que toda tabla nueva siga la de su familia (Tanda 1 ya lo hace); normalizar lo histórico solo si algún reporte lo necesita.
- **Comentarios (167 funciones sin COMMENT):** se exige en toda función nueva/tocada; no se persigue el stock.

## Orden y dependencias

| Semana | Tanda | Gate |
|---|---|---|
| Esta (antes del 10/09) | T1 rastro + T2 anti-NaN | ninguna decisión pendiente |
| Siguiente | T3 superficie | 2 decisiones chicas de Miguel |
| Cuando toque productos | T4-F1 criterio único | ninguna |
| Tras decisión F0 | T4-F2 | decisión frontera |
| Tras Apps Script + bridge | T5 retiros | OK de Miguel por pieza |
| Con P-050/051/052 | T7 (contagio) + T6 | — |

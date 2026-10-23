---
tags: [auditoria, base-de-datos, postgres, rls, integridad, crm]
fecha: 2026-10-22
estado: entregada, sin aplicar nada
---

# Auditoría de tablas: ¿cumplen las reglas básicas de Postgres? (2026-10-22)

**Pregunta de Miguel (22/10, tras lo de los leads duplicados):** revisar con agentes si todas las demás tablas
cumplen las reglas básicas de Postgres para que la lógica del negocio funcione y los datos sean consistentes.

**VERDICT: ATENCIÓN. Sin ningún P0.** La base está bien armada en lo grueso: claves, llaves foráneas, RLS,
ledgers inmutables y claves naturales del dinero están en la base. Lo que falta son candados finos que hoy
sostiene el código, y **tres desajustes de datos reales** que conviene mirar ya (abajo, «Datos rotos hoy»).

Nada se escribió en la base ni en el código. Todo lo medido es de solo lectura sobre producción.

## Cómo se hizo

| Paso | Qué |
|---|---|
| Catálogo | `supabase db dump --linked --schema crm,private` (solo estructura): **151 tablas** (118 `crm` + 33 `private`), 281 FK, 73 policies, 374 triggers. No existe esquema `audit`: la bitácora es `public.audit_log` vía `private.log_audit_crm()` / `log_audit_sin_secretos()`. |
| Hechos de prod | filas por tabla, constraints sin validar, FK sin índice, columnas `_id` sin FK, tablas sin fecha de alta/cambio, montos sin moneda. |
| Tres agentes (Opus) | A = claves e integridad referencial · B = unicidad y reglas de negocio · C = RLS, grants, bitácora y comentarios. Cada hallazgo con evidencia (línea del DDL) y su SQL de comprobación. |
| Verificación | cada SQL de los agentes se corrió en producción (solo lectura) y se anotó el resultado real. |
| Agrupación | Jev (skill `agrupar-hallazgos`) sobre los 38 hallazgos: 2 fusiones seguras (acreditaciones A-3+B-1; respaldos A-5+B-14). El resto, agrupado a mano. |

Evidencia completa: `CRM-Avance-Corp/docs/auditorias/tablas-postgres-2026-10-22/` (informes A/B/C, verificaciones,
hechos, catálogo DDL sin funciones y `resumen-tablas.json`).

## Lo que está bien (medido)

| Regla | Estado |
|---|---|
| RLS en toda tabla | 150/151 (falta `private.respaldo_cierre_agosto_2026`, 17 filas, sin permisos a nadie) |
| `anon` | 0 permisos en `crm` y `private` |
| Cerrado por defecto | 124/151 sin permiso a `authenticated`; 101 con RLS sin policies (solo las tocan funciones DEFINER) |
| Clave primaria | 148/151 (faltan 2 respaldos y `private.pares_autoridad`) |
| FK | 281, todas validadas, ninguna con trigger apagado, 0 huérfanos por FK |
| Tipos | 0 `float`, 0 `money`, 0 `timestamp` sin zona; dinero con escala 2 y moneda `PEN/USD` (o columnas `_pen`/`_usd`) |
| Claves naturales del dinero | un cierre por mes, uno por vendedor y mes, metas por mes/vendedor, tipo de cambio por día, una acreditación por lead/episodio/fuente, una cuenta de pago por contrato, un responsable abierto por inversionista, un titular principal por inversión, una inversión por contrato |
| Ledgers inmutables | más de 40 tablas con trigger que rechaza UPDATE/DELETE |
| Bitácora | 117/118 tablas de `crm` con `log_audit_*` |
| `crm.leads` | candados `uq_leads_telefono_vivo` y `uq_leads_dni_vivo` funcionan: 0 vivos repetidos por teléfono o DNI; 0 teléfonos mal formateados |
| Copias de datos | acreditación↔episodio↔analista, titular principal↔inversión, contexto↔actividad, lead↔inversionista_leads: **0 desajustes hoy** |

## Datos rotos hoy (lo único que pide acción ya)

| # | Qué | Cifra | Prioridad |
|---|---|---|---|
| D-1 | **Ventas acreditadas en la conversión que la cartera no tiene.** Acreditaciones con fuente `contrato` cuyo contrato está activo en el portal pero **no tiene fila en `crm.inversiones`** (y en 40 casos el lead tampoco tiene `contrato_id`). | **45 de 218**: septiembre 39, octubre 4, marzo 1, mayo 1 | **P1** · decidir si `crm.inversiones` debe cubrirlas (cartera por persona, postventa, capital) o si es por diseño |
| D-2 | **Leads convertidos desde el 01/09 sin acreditación**, sin contrato y sin cierre externo vivo. No entran en el sello de septiembre (ya sellado: 161 acreditaciones). | **2** (convertidos el 16/09 y el 18/09) | **P1** · revisar los dos leads |
| D-3 | Filas del ledger de rentabilidad que apuntan a contratos que ya no existen y **no constan en ninguna auditoría de eliminación** (borrados antes de la auditoría o desde el portal). | 12 filas / 11 contratos (otras 42 filas sí constan) | P2 |
| D-4 | `leads.contrato_id` colgante (contrato borrado y recreado). Caso conocido, pendiente de Miguel. | 6 (los 6 constan en `contratos_eliminados_auditoria`) | P2 (ya abierto) |
| D-5 | Teléfono de un lead vivo = `telefono_alternativo` de otro vivo (hueco del candado anti-duplicado; reportado hoy aparte). | 15 pares | P2 (ya propuesto) |
| D-6 | `producto_condiciones.legacy_contrato_id` apunta a contratos borrados. Inofensivo: no se ofrecen. | 110 | P3 |

Aclaración útil: `leads.contrato_id` está vacío en **175 de 333** leads convertidos (96 con cierre externo vivo,
26 con inversión por inversionista, 53 restantes). **No es la fuente de la venta**: la fuente son
`conversion_acreditaciones` e `inversiones`. Quien lea `leads.contrato_id` para saber «qué vendió» se equivoca.

## Candados que faltan (sin datos rotos hoy, los sostiene el código)

### P1 (cuatro)

1. **`crm.conversion_acreditaciones` sin trigger de inmutabilidad** (B-1 + A-3). Es la tabla que decide qué venta
   cuenta y para quién. Sus vecinas (`lead_asignaciones`, `cierre_mes_vendedor`, `periodos_cerrados`) sí lo tienen.
   Nada impide cambiar `analista_id`, `lead_id` o `fuente_id` de una fila sellada, ni borrarla; y ninguna llave ata
   el episodio al mismo lead ni el analista al del episodio. Hoy: 0 desajustes; 161 selladas de septiembre.
2. **Datos personales de `crm.leads` sin recorte por columna** (C-1). `authenticated` tiene `SELECT` de TABLA, así
   que los permisos por columna no recortan nada: todo rol que ve el lead ve `dni`, `fecha_nacimiento` y `genero`,
   incluida Coordinación con la consulta global del 15/10 (antes los recibía tapados). **Decisión de Miguel.**
3. **Un analista puede reescribir el consentimiento INDECOPI de sus leads** (C-2): `UPDATE` por columna sobre
   `consentimiento_en`/`consentimiento_fuente`, sin trigger que lo frene; 3 937 leads con consentimiento. Queda en
   la bitácora, pero es permiso de más.
4. **DNI sin tapar en `public.audit_log`** (C-3): `verificaciones_lead` (1 621 filas), `recordatorios_disponibilidad`,
   `solicitudes_tasa` e `inversionista_datos_contacto` usan `log_audit_crm()` a secas; `crm.leads` sí tapa. Lo leen
   admin/superadmin del portal.

### P2

- **Regla «convertido ⇒ venta viva» no existe en la base** (A-1): `leads.contrato_id → contratos` es `ON DELETE SET
  NULL` y ningún CHECK liga la etapa a una fuente. Es lo que produce D-4.
- **CASCADE desde `public.perfiles` sin candado** en `cuentas_bancarias.cliente_id`, `actividades_cliente.cliente_id`
  y `tareas.perfil_id` (A-2). Riesgo bajo hoy: `contratos.cliente_id` es RESTRICT y `perfiles` tiene trigger de baja;
  1 cuenta bancaria expuesta.
- **Bitácoras e historiales sin trigger append-only** (B-2 + C-7): `usuario_eventos` (ni bitácora), `verificaciones_lead`,
  `inversionista_gestiones`, `cartera_lecturas` (16 353), `correcciones_correo_acceso`, `private.agenda_reparto_cambios`,
  `inversion_solicitud_origenes`, `tipo_cambio_trabajos`, `private.membresias_purgadas`; y los historiales de vigencia
  `inversionista_responsables`, `inversionista_leads`, `inversionista_identificadores` (solo debería poder cerrarse el tramo).
- **Configuración y permisos con candado o bitácora incompletos** (B-3 + C-5): `conversion_pesos` sin
  `trg_config_versionada_inmutable`; `capital_valoracion_politica` sin auditar DELETE; `cuotas_cuenta_pagada` deja
  reescribir `contrato_id`; en `private`: `pares_autoridad` (9 pares, sin PK), `agenda_reparto_diaria/destinos` y las 4
  tablas de exenciones/topes de los vigías sin ninguna bitácora.
- **Códigos `text` sin CHECK** (B-4, B-5, B-15): `cierre_mes_vendedor.estado` y sus contadores (sin `>= 0`),
  `verificaciones_lead.veredicto`, `postventa_operaciones.comando`, `conversion_acreditaciones.origen`,
  `lead_asignaciones.origen/categoria_interes`, `inversionista_identificadores.fuente`, roles en `private.pares_autoridad`
  y `usuarios_retirados`. Valores reales hoy: todos coherentes.
- **`crm.leads.telefono` sin CHECK de formato en INSERT** (B-6): solo se valida en UPDATE; el trigger de normalizado
  no rechaza nada. Hoy 0 fuera de formato.
- **«Una sola primera conversión vigente por persona» solo en el código** (B-7). Hoy 0 duplicados.
- **Vigencias sin CHECK de rango ni EXCLUDE** en `inversionista_identificadores`, `inversionista_leads`,
  `inversionista_responsables` (B-8). Hoy 0 solapes.
- **Escrituras directas desde la pantalla** en 8 tablas (C-4 + B-10), ya medidas en `PLAN-CIERRE-SALTOS.md`; dos son
  políticas que se sobrescriben sin versión (`enfriamiento_politica`, `politica_abandono`) y en una el autor lo declara
  el navegador.
- **Respaldos de cierre** (C-6 + A-5 + B-14): `respaldo_cierre_agosto_2026` sin RLS y con 17 filas (no 0);
  ambos sin PK, sin NOT NULL ni candado. El de septiembre: 169 filas, sin duplicados.

### P3

A-4 (4 columnas `_id` sin FK y sin comentario), A-6 (FK sin índice: ninguna duele), A-7 (ON DELETE declarados que
nunca corren; SET NULL en columnas de autoría; 5 actividades sin autor), A-8 (residuales: solo
`objetivos_legacy_archivo`, `objetivos_vendedores_legacy_archivo` e `inversion_backfill_lotes` están vacías de verdad;
`backfill_multiempresa_mapa` 471, `backfill_cuentas_p0xx` 511, `conciliacion_cuentas_p0xx` 41 y `piloto_f8` 1/4 tienen
datos), B-9 (dinero/tasas `numeric` sin escala declarada; hoy 0 con más de 2 decimales), B-11 (NOT NULL que el negocio
implica; hoy 0 nulos), B-12 (formato de nombre/correo; hoy 0), B-13 (`inversiones` sin BEFORE DELETE; 33 sin evento que
las proteja), C-8 (la única policy DELETE, documentada), C-9 (`solicitudes_tasa` con grant y sin gate de actor
activo; 19 tablas con policies para `authenticated` pero sin grant), C-10 (permisos por columna de `leads` sin regla
fija: 5 columnas sin SELECT propio), C-11/C-12/C-13 (35 tablas sin comentario, 27 % de columnas comentadas, PII sin
marca «DATO PERSONAL»), C-14 (nombres: 9 tablas en singular, 28 booleanos sin `es_`/`tiene_`, FK sin `_id`).

## Decisiones de Miguel

1. **D-1:** ¿las 43 ventas de sep/oct acreditadas sin fila en `crm.inversiones` deben estar en la cartera? Si sí, hay
   que cargarlas y poner el candado «acreditación por contrato ⇒ inversión».
2. **D-2:** los 2 leads convertidos del 16/09 y 18/09 sin acreditación: ¿venta real sin registrar o conversión por error?
3. **C-1:** ¿Coordinación (consulta global) debe ver `dni`, `fecha_nacimiento` y `genero`? Si no, pasar `crm.leads` a
   privilegios por columna o servir esos campos por RPC que redacte.
4. **Orden de los candados P1** (uno por PR, LEVEL 3, con `auditor-rls` + gate `test-rls` + Codex): propuesta
   1 → 4 → 3 → 2.

## Lo que NO se hizo

- Nada aplicado en la base ni en el código. Sin migraciones.
- Sin revisión de Codex: fue auditoría de solo lectura; Codex entra al implementar cada candado.
- No se tocó `public` (portal): solo se leyeron sus FK y triggers para evaluar A-2.

Relacionado: [[Leads - marca y filtro de reasignados (2026-09-28)]] · [[Conversion unica en todo el CRM - plan de migraciones]] ·
[[Auditoria ACID, CAP e idempotencia del CRM (2026-09-24)]] · [[Reemplazar inversion - plan por fases (2026-10-17)]] ·
`SERVIDOR-CRM/mapa-capas-2026-09-17/PLAN-CIERRE-SALTOS.md`.

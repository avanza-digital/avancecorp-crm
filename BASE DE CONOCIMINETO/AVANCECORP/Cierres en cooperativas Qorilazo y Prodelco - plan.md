# Cierres en cooperativas (Qorilazo y Prodelco) — plan

**Estado: ✅ EN PRODUCCIÓN 2026-08-13 (servidor + edge). Falta SOLO el release del front y la
prueba visual de Miguel.** La migración `20260812000259_crm_cierres_externos` sobrevivió a TRES
NO-GO de Codex (9 bloqueantes reales corregidos: correo al final + reserva sellada, índice único
GLOBAL del depósito, guarda NaN, carrera MVCC, reintento del dueño, tope absoluto,
`depositos_reclamados` append-only) y su ciclo final quedó en verde: oráculo 28 casos · RLS
914/914 · advisors 0 ERROR · DEFINER 159→167 · front 1.690/1.690 (commit `ae45e19`). Se aplicó
**DIRECTO a producción con el guion `aplicar-cierres-externos-prod.sh`** (autorizado por Miguel:
el merge de branches está roto del lado de Supabase — proyectos de branch sin registrar en la
Management API, 404 tres de tres; ticket de soporte en curso, branch `cierres-externos-v3` vivo
a propósito). La edge `crm-convertir-lead` quedó **redesplegada (v10)** el mismo día, verificada
byte a byte contra la fuente local.

**Las 6 decisiones de negocio de Miguel (2026-08-12) que rigen la versión construida:**
1. Nadie de cooperativa termina en el portal (la conversión Avance APARTA el lead antes de
   crear Auth/perfil/correo; el cierre en coop se rechaza mientras el apartado viva).
2. Número de transacción del depósito obligatorio y ÚNICO (global; el certificado de la coop
   pasó a opcional).
3. Solo soles en cooperativas.
4. Gerencia puede ANULAR un cierre falso: deja de contar en dinero Y en conversión, con motivo
   y autoría, de una sola dirección.
5. Solo gerencia corrige el número de depósito.
6. Vista de revisión «Ver cierres del mes» en «Hoy», junto al desglose «Por empresa»
   (supervisor y gerencia).

**Decisiones de implementación que REFINAN lo de abajo** (el detalle viejo queda como historia):
- La RPC de lectura se llama **`crm.cierres_externos_fn(p_periodo)`** (no `cartera_externa_fn`) y es
  SECURITY DEFINER con allowlist + ámbito por array — INVOKER era imposible sobre una tabla
  deny-by-default sin policies. Devuelve: `cierres` (filas, histórico del ámbito, tope 200 + total),
  `totales` (por cooperativa×moneda, para los mini-totales sin aritmética en cliente) y
  `por_empresa` (mes pedido, por vendedor×cooperativa×moneda). El lector global (directorio)
  recibe agregados SIN filas (PII solo para operadores).
- El §2bis NO mete claves nuevas en `cumplimiento_metas_fn`: su payload lo valida un
  `v.strictObject` en el front desplegado y una clave nueva lo ROMPE. El desglose por empresa
  viaja en `cierres_externos_fn`; en cumplimiento solo crecen los VALORES (UNION ALL de externos
  en la CTE `reales`, categoría `nuevo`, snapshot de metas como los contratos). La parte «Avance»
  del desglose = `capital_real` − agregados coop (resta de dos números servidos).
- Gate de `convertir_lead_externo` con **allowlist `coalesce`**: con `rol_crm` NULL el `not in`
  de `convertir_lead` no dispara (trampa NULL); el gate RLS lo cazó en vivo. Ojo: `convertir_lead`
  (Avance) arrastra esa trampa en prod — deniega por ámbito igual, corregirlo es migración aparte.
- El vencimiento (`p_vence_en`) exige fecha futura al CONVERTIR; al corregir no (una corrección
  tardía debe poder reenviar un vencimiento ya pasado).
- ✅ **RESUELTO 2026-08-12 (decisión 4 de Miguel)**: la anulación EXISTE — `crm.anular_cierre_externo`,
  solo gerencia, motivo obligatorio, una sola dirección; el cierre anulado deja de contar en
  dinero Y en conversión sin borrar la fila ni reabrir el lead. En Avance (donde eliminar el
  contrato solo quita el dinero) el mismo criterio queda para su propio ciclo — toca el portal.

## El pedido (Miguel, textual en esencia)

Los vendedores venden inversiones de **3 empresas**: Avance Corp (la que tiene portal y circuito completo) y **dos cooperativas: COOPAC Qorilazo y COOPAC Prodelco**. Los inversionistas de las cooperativas **no entran al portal ni reciben correo**, pero **sí le cuentan al vendedor en su cuota mensual y en su % de conversión** (base para comisiones). «No me importan estas personas como clientes, solo me importa que entran dentro de la gestión del vendedor.» Además: deben verse en **Mi cartera** con un **distintivo** de a qué cooperativa pertenecen.

## Por qué la ruta elegida es barata

- La [[Conversion mensual - definicion cerrada|conversión mensual]] **no mira contratos ni portal**: cuenta episodios del ledger `crm.lead_asignaciones` con `resultado='convertido'`. Si el cierre externo cierra el episodio igual que hoy, **la fórmula no se toca** (referidos 15 %, descartados en el divisor, arrastre — todo intacto).
- Lo único que bloquea es que hoy el ÚNICO camino a «convertido» es la edge `crm-convertir-lead` (crea usuario de Auth + `public.perfiles` + correo Resend) y el invariante del trigger «convertido ⇒ perfil_id no nulo».
- La cuota en soles (`crm.cumplimiento_metas_fn`) hoy solo suma `public.contratos`; hay que sumarle los cierres externos.

## Decisión de fondo

**Los inversionistas de cooperativas NO tocan `public.perfiles` ni nada del portal.** Regla [[../AVANCECORP/Acceso y roles del CRM|CRM y portal separados]]: crear perfiles sin login contaminaría el portal (listados de admin, dedup por DNI de clientes, fallback `perfil_legacy` de Pagos). Viven en el CRM: el **lead** (identidad y teléfono) + una **tabla nueva de cierres externos** (la inversión).

Misma etapa `convertido` (NO una etapa nueva): una etapa nueva rompería todos los filtros por igualdad literal (lección §4bis C4 del [[Conversion mensual - plan de implementacion|plan de conversión]]: un estado nuevo hace desaparecer al asesor de 4 pantallas). El distintivo sale de datos, no de una etapa.

## 1 · Lo que llena el vendedor al convertir

Al pulsar **Convertir**, primera pregunta: **«¿Dónde invirtió?»** → `Avance Corp` | `COOPAC Qorilazo` | `COOPAC Prodelco`.

- **Avance Corp** → flujo actual intacto (portal + correo + contrato opcional). Ni una línea cambia.
- **Cooperativa** → formulario corto:

| Campo | ¿Obligatorio? | Detalle |
|---|---|---|
| Cooperativa | **Sí** | Qorilazo o Prodelco (ya elegida en el paso 1) |
| Monto invertido REAL | **Sí** | > 0, 2 decimales; es el que suma a la cuota |
| Moneda | **Sí** | PEN/USD, precargada del lead |
| Nombre completo | **Sí** | Precargado del lead, editable |
| Documento (tipo + número) | **Sí** | Precargado si el lead lo tiene; misma validación DNI/CE/Pasaporte del flujo Avance. Es el ancla de identidad (nadie invierte en una COOPAC sin documento) |
| Referencia del contrato en la coop | No | Nº o código del contrato/certificado que emitió la cooperativa; sirve para auditar comisiones |
| Vencimiento de la inversión | No | Para que el vendedor sepa cuándo volver a tocar la puerta (renovación = ingreso futuro) |
| Nota | No | Texto libre |

**Lo que NO se pide (a propósito):** correo (no hay portal ni bienvenida), cuenta bancaria (la coop paga por su lado), plazo/tasa/cronograma, producto del catálogo. El teléfono ya viene del lead.

**Fecha del cierre: automática (hoy), no editable** — así el mes de la conversión y de la cuota es el mes real del cierre, sin retro-dataciones que muevan métricas.

## 2 · Qué ve el vendedor después

- **Ficha del lead:** «Convertido · COOPAC QorilazO» *(chip por cooperativa)* + monto, referencia, vencimiento y nota del cierre.
- **MI CARTERA:** sección propia **«En cooperativas»** debajo de la cartera Avance:
  - filas: nombre · chip QORILAZO/PRODELCO · monto y moneda · fecha de cierre · teléfono · «Ver detalle» (mini-ficha con datos del lead + datos del cierre; no es la ficha de cliente del portal porque no hay perfil).
  - mini-totales propios por moneda («En cooperativas: S/ X · US$ Y»), **separados** de los totales Avance y PEN/USD nunca sumados ([[../AVANCECORP/Inicio|regla de layout]]). El dinero en coops no es capital administrado por Avance; mezclarlo mentiría en los tiles.
  - Sección aparte (no mezclada en la lista paginada): `cartera_pagina_fn` es keyset (F2) y meter un UNION de dos fuentes en su cursor es riesgo real sin beneficio; los cierres externos serán pocos al inicio y caben en una lista simple.
- **Cuota:** el tile «Tu cumplimiento del mes» sube solo (bebe de `cumplimiento_metas_fn`).
- **Conversión:** el tile sube solo (bebe de `conversion_mensual_fn`, sin cambios).
- Supervisor y gerencia **heredan** ambos números por sus mismas RPCs.

## 2bis · Reportes de supervisor y gerencia — desglose por empresa (pedido explícito de Miguel)

> «En los reportes para supervisor y gerencia debe aparecer bien claro cuánto tiene por Avance Corp el vendedor y cuánto por las cooperativas.»

- El payload de `cumplimiento_metas_fn` gana, por vendedor, un bloque `por_empresa`: **Avance · Qorilazo · Prodelco**, cada uno con capital por moneda (PEN/USD separados, nunca sumados) y nº de cierres. El TOTAL sigue siendo la suma (la cuota es una sola), pero el desglose viaja siempre.
- **Pantallas:** el panel del supervisor y los de gerencia (equipo, resumen) muestran por vendedor la fila de producción partida en tres — «Avance S/ X · US$ Y» / «Qorilazo …» / «Prodelco …» — con los mismos chips de la cartera. Donde hoy hay un solo número de capital, se abre el desglose (expandible o columnas, se decide en el front con el patrón de cada pantalla).
- La **conversión** no se desglosa por empresa (un cierre es un cierre); lo que se desglosa es la **producción** (capital y nº de cierres).
- ⚠️ **Orden de deploy** (regla [[../AVANCECORP/Inicio|orden por dirección]]): las claves nuevas en la RESPUESTA de `cumplimiento_metas_fn` exigen verificar el parser del front viejo; si es estricto, primero release de front tolerante y luego el servidor. La RPC nueva de conversión externa, en cambio, exige servidor primero. La secuencia fina se fija en implementación.
- ⚠️ **Esta Fase 1 va primero, a propósito (decisión de Miguel, 2026-08-11 noche):** la migración B del [[Conversion mensual - plan de implementacion|plan de conversión mensual]] («unificar `cumplimiento_metas_fn`», §3.2) también hace `create or replace` de esta misma función. B se escribe DESPUÉS, copiando byte a byte el cuerpo que esta Fase 1 deje en producción — no al revés, y no en paralelo.

## 3 · Métricas — definición exacta

- **Conversión:** el cierre externo cierra el episodio del ledger con `resultado='convertido'` y `resultado_en=now()`, idéntico al cierre Avance → numerador del mes, mismo peso (no referido ×1, referido ×0,15 si el episodio nació referido). **Cero cambios en `conversion_mensual_fn`.**
- **Cuota:** `cumplimiento_metas_fn` suma además de contratos: `capital_real += monto` (en su moneda) y `contratos_real += 1`, categoría **'nuevo'** (la meta operativa es única normalizada nuevo/PEN según [[Configuración operativa CRM 2026-08-07]]), atribuido al `vendedor_id` snapshot del cierre, validado contra el snapshot mensual de metas igual que un contrato (fuera del snapshot → sin atribución, nunca cae a otro).
- **Comisiones por cooperativa:** el desglose vive en la tabla de cierres (vendedor × cooperativa × mes); un panel de gerencia para verlo es fase aparte (ver Pendientes).

## 4 · Modelo de datos (servidor)

**Tabla nueva `crm.cierres_externos`** — RLS on, **cero grants directos** (patrón `conversion_pesos`/`lead_asignaciones`): solo se llega por RPC SECURITY DEFINER.

- `id`, `lead_id` FK **UNIQUE** (un cierre externo por lead; casa con el índice «una conversión por lead» del ledger), `cooperativa` CHECK in ('qorilazo','prodelco'), `monto` numeric(14,2) >0, `moneda` CHECK PEN/USD, `documento_tipo`, `documento`, `nombre_completo` (snapshot al cierre), `referencia_externa` null, `vence_en` date null, `nota` null, `vendedor_id` (snapshot, quien cobra el cierre), `creado_por`, `creado_en`.
- Inmutable por trigger salvo la RPC de corrección.

**RPC `crm.convertir_lead_externo(p_lead_id, p_cooperativa, p_monto, p_moneda, p_documento_tipo, p_documento, p_nombre, p_referencia, p_vence_en, p_nota)`** — SECURITY DEFINER, mismos gates que `crm.convertir_lead` (rol, ámbito, lead activo/no cerrado/con vendedor asignado): inserta el cierre, y bajo la válvula `crm.op_privilegiada` pone `etapa='convertido'`, `convertido_en=now()`, `perfil_id` queda NULL; el trigger del ledger cierra el episodio como hoy. Registra `crm.actividades` tipo 'conversion' con metadata `{cooperativa, monto, moneda}`.

**Invariante del trigger (ajuste):** «convertido ⇒ perfil_id no nulo **o existe cierre externo del lead**».

**RPC `crm.corregir_cierre_externo(...)`** — solo gerencia: corrige monto/cooperativa/referencia/vencimiento/nota (deja actividad). **La conversión en sí no se deshace** (igual que hoy con Avance: el contrato se anula, el lead convertido no se reabre).

**Lectura:** RPC `crm.cartera_externa_fn()` (INVOKER si devuelve filas con PII — regla RETOMAR-43; el alcance lo pone la RLS del lead vía join) para la sección de Mi cartera, + los datos del cierre embebidos donde la ficha del lead ya lee.

`npm run gen:types` tras el cambio de esquema.

## 5 · Casos borde ya resueltos

- **El mismo prospecto luego quiere invertir en Avance Corp:** lead nuevo (los índices `uq_leads_*_vivo` liberan DNI/teléfono al convertir) y sigue el camino normal. Dos cierres en meses distintos = dos conversiones legítimas.
- **Referido cerrado en cooperativa:** cuenta al 15 % igual que uno de Avance (el peso sale del snapshot del episodio, no de dónde invirtió).
- **Lead sin vendedor asignado:** no se puede convertir (regla vigente, se mantiene).
- **Demo mode:** el store simula el cierre externo local, como hace con `convertir`.
- **Descartado que reabre y cierra en coop:** mismas reglas de ciclo que hoy.

## 6 · Fases y gates

1. **Servidor** (1 migración): ciclo de branch completo — oráculo SQL de la RPC (casos: convertido cuenta en conversión y cuota, referido al 15 %, doble cierre rechazado, fuera de ámbito 42501, corrección solo gerencia), suite RLS (línea base 862), advisors 0 ERROR, conteo de DEFINER exacto, **auditor-rls + Codex refutando el diseño ANTES del merge**. Trampas RETOMAR-46: branch por pooler 5432, migraciones por psql + registro manual, relanzar gate = `reset_branch`.
2. **Front:** diálogo con selector de empresa, sección «En cooperativas» en Mi cartera, chips, mini-ficha, demo, **y el desglose por empresa en los paneles de supervisor y gerencia (§2bis)**; tests sobre línea base ~1.619; revisor-a11y.
3. **Deploy:** **servidor primero** (el front llama RPCs nuevas — regla [[../AVANCECORP/Inicio|orden por dirección]]), luego release del front vía `/release-crm` (lo invoca Miguel) con la verificación del `.env`/ref de Supabase dentro del ZIP.
4. **Prueba visual de Miguel** con la cuenta piloto.

## Pendientes que este plan NO cubre (decisión aparte)

- **Panel de gerencia de comisiones** (cierres externos del mes por vendedor × cooperativa). Los datos quedan listos; la pantalla es otra iteración.
- **Recordatorio automático al vencimiento** de la inversión en coop (agenda). El dato `vence_en` queda guardado desde v1.
- **Metas separadas por empresa** (hoy la cuota es una sola en soles; si un día Miguel quiere meta Avance ≠ meta coops, es revisión del modelo de metas).

Relacionadas: [[Conversion mensual - definicion cerrada]] · [[Conversion mensual - plan de implementacion]] · [[Configuración operativa CRM 2026-08-07]] · [[Como se mide la conversion del asesor]] · [[Canales de origen de leads CRM]]

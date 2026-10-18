# Plazo de carga por mes, decidido por Gerencia — diseño (14/10/2026)

Pedido de Miguel (14/10): «necesitamos abrir septiembre porque los analistas se demoraron
en cargar sus ventas; una configuración para que gerencia lo decida». Decisiones suyas:
**solo Gerencia** decide · **sin tope** de fecha · alcance **ampliar el plazo Y reabrir un
mes ya sellado** desde la pantalla.

Contexto: septiembre ya se reabrió hoy por script
(`supabase/scripts/reexpresion-septiembre-2026/`, leer su `LEEME.md` y los 4 SQL: son la
especificación probada de la reapertura). El job 3 `crm-cierre-mes-diario` está EN PAUSA.

## 1. Regla de negocio

- **Plazo de carga de un mes M** = instante (extremo EXCLUIDO, America/Lima) hasta el que:
  (a) una conversión de M se acredita (`private.conversion_decidir_plazo`);
  (b) el ciclo automático NO sella M (`private.cierre_mes_ventana_desde`);
  (c) tampoco `crm.cerrar_periodo` a mano (su candado de ventana usa la misma función).
- **Base** (hoy, fija en código): 00:00 Lima del día 11 de M+1 = «último día incluido: el 10».
- Gerencia fija el **último día incluido D** → plazo = `(D + 1)::timestamp at time zone 'America/Lima'`.
  Reglas: plazo ≥ base (nunca antes del 10: decisión de Miguel del 15/08), D ≥ hoy en Lima
  (fecha futura o el mismo día), motivo 5–300 caracteres, M ≤ mes en curso y **con metas publicadas**
  (revisión Codex r2: el ciclo solo sella meses con metas, `private.cierre_mes_pendiente`; un mes sin metas con
  plazo quedaría saltado al sellarse el siguiente y luego sin sello ni decisión modificable → 22023 «… no tiene
  metas publicadas: no tiene cierre ni plazo de carga», comprobado tras los candados y antes de mirar el sello). Sin
  tope superior: mientras M no se selle, los meses siguientes esperan (el ciclo sella del más antiguo al más nuevo y
  `crm.cerrar_periodo` responde «Falta cerrar M» para M+1; probado en `prueba.sql` B12).
- Gerencia puede volver a decidir (ampliar o acortar) mientras M esté abierto; vale la última decisión.
- **Reabrir** un mes sellado = misma acción «fijar plazo» sobre un mes sellado. Solo se permite si:
  0. M tiene **metas publicadas** (revisión Codex r2; si no, el motivo «… no tiene metas publicadas: el ciclo no lo
     volvería a cerrar», y la puerta ya lo corta antes con el 22023 de la regla de metas);
  1. M es el **último** mes sellado y es el **mes anterior al mes en curso** (en octubre solo
     septiembre; no se reabre agosto en octubre);
  2. no hay deudas **nacidas** de M (`crm.ajustes_mes_cerrado.periodo_origen = M`);
  3. la foto de M **no absorbió** deudas (`crm.cierre_mes_vendedor.ajuste_numerador/pen/usd = 0`);
  4. cada rastro tardío de M (`crm.inversion_ajustes_mes_cerrado.periodo_origen = M`) es una
     venta en **cooperativa** coherente (fecha_comercial en M, `ce.fecha_imputacion =
     ia.fecha_imputacion`, mes de imputación NO sellado) cuyo **analista efectivo**
     (`private.analista_efectivo_cierre`) tiene meta en M (última revisión de `crm.meta_periodos`);
  5. no hay ventas en cooperativa con fecha comercial en M imputadas a otro mes SIN rastro.
  Efecto (idéntico al script 01): respaldo completo; se retiran rastros tardíos, foto y sello;
  esas ventas vuelven a M (`fecha_imputacion = fecha_comercial`); las acreditaciones de M
  quedan sin marcas de sello. Con el plazo nuevo en el futuro, el ciclo lo vuelve a sellar solo.
- **Reevaluación**: al fijar el plazo de M, las acreditaciones de M en `fuera_de_plazo` o
  `mes_sellado` con `acreditado_en < plazo nuevo` se recalculan con
  `conversion_decidir_plazo` (+ exclusión de fuente demo/cartera, igual que el escritor).
  Si la identidad canónica ya tiene otra captación acreditada (regla del escritor,
  `P0409 'La identidad ya tiene una captacion acreditada'`, que el escritor comprueba ANTES de
  decidir el estado, también para una fuente demo o de cartera), se dejan como están y se
  cuentan como conflicto (revisión Codex r1, P3). El escritor `conversion_acreditar_fuente` NO las
  reevalúa solo (devuelve la fila tal cual si fuente/fecha/origen no cambian).

## 2. Servidor (UNA migración `AAAAMMDDHHMMSS_crm_plazo_carga_mes.sql`)

### Tablas (esquema `crm`, RLS ON en el mismo paso, deny-by-default, `revoke all` a
public/anon/authenticated/service_role, auditoría `private.log_audit_crm`, append-only,
`COMMENT ON` en todo)
- `crm.reaperturas_mes`: `id uuid pk`, `periodo date` (primer día), `motivo text`,
  `decidido_por uuid → public.perfiles`, `reabierto_en timestamptz default clock_timestamp()`,
  `transaccion xid8 not null default pg_current_xact_id()` (con `reabierto_en`, la llave; las dos
  las fija un trigger y la pareja es única: revisión Codex r1, P3), `respaldo jsonb not null`
  (sello, foto[], acreditaciones[] del mes, rastros_tardios[], cierres_externos[] antes del
  cambio), `resumen jsonb not null`.
- `crm.plazos_carga_mes`: `id uuid pk`, `periodo date` (primer día), `ultimo_dia date`,
  `plazo_hasta timestamptz` con CHECK `plazo_hasta = ((ultimo_dia + 1)::timestamp at time zone
  'America/Lima')` y CHECK `plazo_hasta >= private.conversion_plazo_base(periodo)`, `motivo`
  (5–300), `decidido_por uuid → public.perfiles`, `decidido_en timestamptz default
  clock_timestamp()`, `reapertura_id uuid null → crm.reaperturas_mes`. Índice (periodo, decidido_en desc).
- Sin `negocio_id`: el CRM no tiene tenant en el cierre de mes (igual que
  `crm.periodos_cerrados`); declararlo en el COMMENT y en el informe.

### Núcleo (`private`)
- `private.conversion_plazo_base(date) returns timestamptz` IMMUTABLE: la fórmula de hoy
  (con su validación 22023 de primer día de mes finito).
- `private.conversion_plazo_hasta(date)` pasa a **STABLE**: última decisión de
  `crm.plazos_carga_mes` para ese periodo (`order by decidido_en desc, id desc`) o la base.
- `private.conversion_decidir_plazo(...)` y `private.cierre_mes_ventana_desde(date)`:
  IMMUTABLE → **STABLE** (cuerpo intacto). Comprobar en el banco que ninguna función
  IMMUTABLE, índice, default ni CHECK siga dependiendo de ellas.
- CHECK de `crm.conversion_acreditaciones` `plazo_hasta = private.conversion_plazo_hasta(periodo_comercial)`
  (nombre por catálogo) → reemplazar por `conversion_acreditaciones_plazo_minimo_check`:
  `plazo_hasta >= private.conversion_plazo_base(periodo_comercial)`. (Con el plazo variable,
  el CHECK viejo rompería el UPDATE del trigger del sello sobre filas ya decididas.)
- `private.reapertura_autoriza(p_periodo date[, p_cierre uuid]) returns boolean` STABLE: existe una
  fila de `crm.reaperturas_mes` con ese periodo, `transaccion = pg_current_xact_id_if_assigned()` y
  `reabierto_en = now()` (y, con cierre, que esa reapertura lo respaldó). Alcance: la transacción
  SUPERIOR entera, incluidas sus subtransacciones (el id y `now()` son los de la superior); si se
  deshace la subtransacción que insertó la fila, deja de autorizar. Es una sola llamada a la
  puerta. Patrón: `private.inversion_eliminacion_autoriza` (20261005200945).
- Candados con autorización (cuerpos VIVOS + una rama nueva; nada más cambia):
  - `private.trg_cierre_mes_append_only()`: DELETE permitido si `reapertura_autoriza(old.periodo)`.
  - `private.f4_fuente_inmutable()`: DELETE en `inversion_ajustes_mes_cerrado` si
    `reapertura_autoriza(old.periodo_origen)`; en `cierres_externos` UPDATE, cambio de
    `fecha_imputacion` solo si autorizado para el mes de `old.fecha_comercial`, el nuevo valor
    es `fecha_comercial` y NINGUNA otra columna de la fila cambia (también con la válvula
    `crm.op_privilegiada` abierta: revisión Codex r1, P2).
  - `private.trg_cierres_externos_inmutables()`: la válvula se abre también con la
    autorización, **solo para UPDATE** del mes de `old.fecha_comercial`.
- `private.conversion_reevaluar_plazo(p_periodo date) returns jsonb` (reevaluadas, conflictos).
- `private.reabrir_mes(p_periodo date, p_motivo text, p_por uuid) returns uuid`: candados
  2–5, respaldo + fila en `crm.reaperturas_mes`, y las operaciones del script 01 en el mismo
  orden (rastros → foto → sello; imputación; marcas, con `ajuste_anulacion_en_sello` por SQL
  dinámico si la columna existe). Sin `ALTER TABLE` ni GUC.
- `crm.cerrar_periodo(date)`: cuerpo vivo + una segunda mirada a la ventana DESPUÉS de tomar el
  candado global y el mensual (revisión Codex r1, P1). Sin ella, un sello que leyó la ventana y
  esperaba el candado mientras Gerencia ampliaba el plazo de ese mes sellaba igual; con «sin
  tope», incluso un mes que ya no es el anterior y que la pantalla no puede reabrir. Ahora se
  niega (22023) y el ciclo lo anota en su `fallo`; al día siguiente ya ve el plazo nuevo.

### Puertas (`crm`, SECURITY DEFINER, `set search_path = ''`, gate explícito)
- `crm.fijar_plazo_carga_mes(p_periodo date, p_ultimo_dia date, p_motivo text) returns jsonb`.
  Gate: `auth.uid()` no nulo y `private.rol_crm(uid) = 'gerencia'` → si no, 42501.
  Validaciones → 22023 con mensaje claro en español. Candado global + mensual de
  `crm.periodos_cerrados` (mismas llamadas que `crm.cerrar_periodo`) ANTES de leer el sello.
  Si M está sellado → `private.reabrir_mes`; si no reabrible → P0409 con el motivo.
  Inserta la decisión, reevalúa y devuelve:
  `{ ok, mes:'YYYY-MM', ultimo_dia, plazo_hasta, reabierto:boolean, reapertura_id|null,
     acreditaciones_reevaluadas:int, conflictos_identidad:int,
     ventas_devueltas:[{cooperativa,monto,moneda,fecha_comercial,imputada_antes_a}] }`.
  `grant execute` a `authenticated` (el gate va dentro).
- `crm.plazos_carga_mes_fn() returns jsonb` (solo Gerencia; 42501 al resto). Meses: los que el
  ciclo todavía debe sellar (con metas, posteriores al último sellado) + los abiertos con una
  decisión vigente posteriores al último sellado (revisión Codex r1, P2; desde la regla de metas de
  r2 es redundante —todo mes con decisión tiene metas y `crm.meta_periodos` es inmutable— y se
  conserva como defensa) + el mes anterior + el mes en curso, ordenados. Un nombre en blanco sale
  «(sin nombre · …)»:
  ```json
  { "version": 1, "hoy": "2026-10-14", "zona": "America/Lima",
    "meses": [ { "mes": "2026-09", "mes_nombre": "septiembre 2026", "sellado": false,
      "plazo_base_ultimo_dia": "2026-10-10", "plazo_ultimo_dia": "2026-10-20",
      "ampliado": true,
      "decision": { "ultimo_dia": "2026-10-20", "motivo": "…", "decidido_por": "NOMBRE",
                    "decidido_en": "timestamptz" } | null,
      "reabrible": false, "motivo_no_reabrible": "texto" | null,
      "ultima_reapertura": { "reabierto_en": "timestamptz", "decidido_por": "NOMBRE" } | null } ] }
  ```
  `reabrible`/`motivo_no_reabrible` salen de la MISMA función de comprobación que usa
  `reabrir_mes` (no copiar la regla). No cambiar el payload de `crm.cierre_mes_estado_fn`
  (el front lo valida con `strictObject`); su `cierra_el` ya refleja el plazo nuevo solo.

### Lo que NO se toca
`public` (salvo DML ya existente en triggers), el cron, `crm.cierre_mes_estado_fn` (forma),
`crm.ciclo_cierre_mes`, el escritor de acreditaciones, Facturación. (`crm.cerrar_periodo` sí:
solo la segunda mirada a la ventana.)

### Guardas del proyecto
Preflight con `md5(pg_get_functiondef)` de cada función que se reemplaza (anclado a lo vivo
del banco = producción) y existencia de triggers/constraint; registros de huellas (F7, vigías,
exenciones analíticas) re-declarados si alguna función tocada está anclada; ledger
`MIGRACIONES.md`; reversa exacta; `npm run gen:types`.

## 3. Pantalla (solo Gerencia)
- Tarjeta «Plazo de carga» en Configuración, solo Gerencia (15/10/2026, Miguel: «esto debe salir pero en configuración»; primero se publicó en Hoy de Gerencia)
  (`app/src/screens/hoy/aviso-cierre-mes.tsx`): por mes, «Septiembre 2026 · se puede cargar
  hasta el 20 oct.» (+ «ampliado por X el …» y el motivo); botón **«Ampliar plazo»** (mes
  abierto) o **«Reabrir septiembre»** (sellado y `reabrible`); si sellado y no reabrible,
  el motivo en una línea.
- Modal: fecha (min = máx(hoy, plazo base)), motivo (5–300), confirmar. Al reabrir, una
  línea: «Se retira el cierre de septiembre; se vuelve a sellar solo al vencer este plazo».
- Al guardar: aviso de éxito con el resumen (reevaluadas, ventas devueltas) e invalidar
  `cierreMesEstado` y la consulta nueva. Errores del servidor tal cual (son mensajes de negocio).
- Contrato con `valibot` `strictObject` (como `lib/cierre-de-mes.ts`), llamadas en
  `data/crm-api.ts` + `data/crm-queries.ts`. Reglas de Miguel: español sin siglas, nombre
  ≥16 px y detalle ≥14 px, horizontal, navy `#111e3d` + azul `#2563eb`, tema claro, sin verde.

## 4. Verificación
Banco Docker PROPIO con esquema de producción; pruebas SQL por escenario con mutantes
(quitar cada autorización/candado → la prueba cae); `test-rls.mjs` (roles); advisors;
`npm run check`; E2E Docker propio; `auditor-rls`; Codex. Aplicar en producción y publicar:
solo Miguel (`!` y `/release-crm`). Después: Gerencia fija el plazo de septiembre → reactivar job 3.

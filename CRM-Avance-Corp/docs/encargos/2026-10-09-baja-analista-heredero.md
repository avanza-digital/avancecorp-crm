# Encargo a Codex (IMPLEMENTADOR) — Analista dado de baja: su capital pasa al responsable actual del cliente

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Escribes SOLO dentro de este worktree:
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/baja-analista-heredero-20261009/CRM-Avance-Corp`.
No hagas commit, push, ni toques producción, red, Docker ni otros worktrees. No invoques a Claude ni a otro agente.
No edites migraciones ya commiteadas. Todo en español (identificadores, comentarios). Al terminar, informe breve:
archivos creados, decisiones, dudas abiertas.

## Decisión de negocio (Miguel, 09/10/2026, cerrada)

«Cuando el analista se desactiva ya no debe aparecer más, y al que se migra toda su información es el que debe
aparecer» — y eligió «Todo a Betzabeth»: aplica a TODOS los meses en las lecturas vivas (Facturación, metas,
rankings, Cartera), no solo desde la baja. Los snapshots de meses SELLADOS no se tocan (solo agosto 2026 está sellado;
se leen de su propia tabla, no de estas funciones). La regla de adopción por cadena de upgrade (30/08) se conserva
para analistas activos.

**Regla (a nivel de sistema, toda vía):** el analista al que se le cuenta un capital/operación se calcula como hoy;
si ese analista tiene la membresía CRM desactivada (`crm.equipo.activo is false`) Y la persona/cliente tiene un
responsable ACTUAL que sí está activo en el CRM y es otra persona, se le cuenta a ese responsable. Si no hay
responsable activo, se queda como está (no se inventa dueño). Analistas que no están en `crm.equipo` (cuentas de
empresa) no cambian.

- Responsable actual de un CONTRATO: `public.perfiles.asesor_perfil_id` del cliente (`public.contratos.cliente_id`).
- Responsable actual de un CIERRE EXTERNO (cooperativa): `crm.inversionistas.responsable_relacion_id` de
  `coalesce(ce.inversionista_id, l.inversionista_id)` (l = `crm.leads` del `ce.lead_id`).
- Medido en prod el 09/10: en los 45 contratos de analistas inactivos, asesor_perfil_id = responsable_relacion_id
  (45/45). La baja (`crm.fijar_membresia_activa_fn`) ya mueve ambos al reemplazo.

## Datos medidos en producción (solo lectura, 09/10)

- Inactivos en `crm.equipo`: PIERINA LEVANO PURIZACA (baja 01/09/2026), NOELIA SALAZAR RUIZ (baja 06/10), IVETT
  TEEVIN (baja 27/08), y 2 perfiles DEMO sin contratos reales.
- Contratos no demo con `analista_cierre_id` inactivo: Pierina 35 (responsables actuales: Betzabeth y Vladimir),
  Noelia 7 (→ Elizabeth Chiroque), Ivett 3 (SIN responsable activo → se quedan con Ivett).
- Cadena: un solo contrato hoy se atribuye por cadena a un inactivo: 2026-01-001570 (renovación 07/10 de Betzabeth,
  origen upgrade 000373 de Pierina) → debe pasar a Betzabeth.
- `crm.operaciones_cartera` con `vendedor_id` = Pierina: 4 (agosto). 1 operación en todo el sistema tiene
  `vendedor_id` ≠ `analista_cierre_id` de su contrato nuevo (vendedor activo; no la afecta la regla).
- `crm.cierres_externos` de inactivos: 4 de Noelia (qorilazo, setiembre, S/ 88.000) → responsable Elizabeth Chiroque.

## Diseño (implementarlo así; si encuentras un error, dilo en el informe en vez de improvisar otro diseño)

Una sola fuente de la regla, tres funciones nuevas en `private` (LANGUAGE sql, STABLE, SECURITY INVOKER,
`set search_path to ''`, nombres calificados, `revoke execute ... from public, anon, authenticated`, `COMMENT ON`):

1. `private.heredero_de_baja(p_analista uuid, p_responsable uuid) returns uuid` — devuelve `p_responsable` si
   `p_analista` está en `crm.equipo` con `activo is false`, `p_responsable` no es null, es distinto de `p_analista` y
   está en `crm.equipo` con `activo is true`; en cualquier otro caso devuelve `p_analista` (null → null).
   Cuidado con NULL: usar `is true` / `is false` explícitos (ver memoria «if not (…) no rechaza un NULL»).
2. `private.analista_efectivo_contrato(p_contrato_id uuid, p_respaldo uuid) returns uuid` =
   `heredero_de_baja(coalesce(private.analista_atribuido_cadena(p_contrato_id), p_respaldo), <asesor_perfil_id del
   cliente del contrato>)`.
3. `private.analista_efectivo_cierre(p_cierre_externo_id uuid) returns uuid` = `heredero_de_baja(ce.vendedor_id,
   <responsable_relacion_id de coalesce(ce.inversionista_id, l.inversionista_id)>)`.

`private.analista_atribuido_cadena` NO cambia (su huella `3c9cec305b014ad8c933df25057d3e8b` se exige en preflight).

Consumidores a reescribir (cuerpos VIVOS en `supabase/scripts/baja-analista-heredero/vivo/*.sql`, con su md5 en el
nombre del informe abajo; genera los cuerpos nuevos a máquina desde esos archivos, cambiando SOLO estas expresiones):

| Función (huella viva) | Cambio |
|---|---|
| `private.capital_episodios` (c9e58c1da9dd7a5d52991c9e47dc19d5) | las 6 `coalesce(private.analista_atribuido_cadena(X), Y)` → `private.analista_efectivo_contrato(X, Y)`; las 3 `ce.vendedor_id` de atribución (columna analista_id, `mv.vendedor_id = …` y el filtro `= any(p_visibles)`) → `private.analista_efectivo_cierre(ce.id)` |
| `private.conversion_episodios` (a0f6bab39ae1f046aa4b919ea9ce78ea) | las 2 de la pierna 'operacion' (una partida en dos líneas) → `analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id)`. Las piernas de leads NO cambian (ledger inmutable) |
| `private.metricas_cartera_por_vendedor` (c1a0bab01e474af758f0feff8819414f) | las 2 → `analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id)` |
| `crm.altas_nuevas_por_analista_fn` (ac3136ea697cc25fc7263cb8b23ad8f8) | la 1 → `analista_efectivo_contrato(c.id, c.analista_cierre_id)` |
| `private.contratos_afectados_por_anulacion` (efbe1fbb1ceb1a1bb8b5d5c03baf3897) | la 1 → `analista_efectivo_contrato(c.id, c.analista_cierre_id)` |
| `crm.atribucion_contrato_fn` (02ad7d7247859fcf9e2c1ece9e2bc22e) | `atribucion_efectiva.analista_id/analista_nombre` = el efectivo; `cadena` y `adoptada` conservan su significado (solo cadena de upgrade); clave NUEVA `heredada` = el efectivo difiere de `coalesce(cadena, c.analista_cierre_id)` (la regla de baja actuó). El front (`contrato-detalle.tsx:562`) solo rotula «adoptada de la cadena del upgrade» si `adoptada`; no lo rompas |
| `private.cartera_f5_fuentes` (fa15f7765d0892c790c7a4b6822e756e) | `analista_origen_id` de contratos: aplicar `private.heredero_de_baja(coalesce(<atrib_map>, c.analista_cierre_id), <asesor del cliente>)` conservando los mapas (es optimización medida: 42 → 11 ms; no vuelvas a llamar a la cadena por fila); cierres externos: `ce.vendedor_id` → `private.analista_efectivo_cierre(ce.id)` |

Misma firma, mismo LANGUAGE, volatilidad, SECURITY DEFINER/INVOKER, `search_path`, dueño (`postgres`) y ACL que la
viva en cada una. Ninguna puerta cambia de firma → no hace falta regenerar tipos.

## Entregables

1. `supabase/migrations/20261009200000_crm_baja_analista_heredero.sql` — sigue el patrón de
   `supabase/migrations/20260930172255_crm_cartera_f5_fuentes_mapas.sql` y `supabase/migrations/LEEME.md`:
   - cabecera con decisión, datos medidos, reversa y cómo aplicar;
   - `begin; … commit;` con un `DO $mig$` idempotente y fail-closed: PREFLIGHT de las 8 huellas vivas (7 + cadena);
     si las 7 ya tienen la huella nueva → `raise notice` «ya aplicada» y salir;
   - ORÁCULO en la misma transacción sobre `private.capital_episodios('-infinity','infinity',true,'{}')` y
     `private.cartera_f5_fuentes()`: antes/después, las filas son las mismas salvo `analista_id`/`en_roster`
     (resp. `analista_origen_id`); toda fila que cambia tenía un analista inactivo y ahora tiene el responsable
     activo; y DESPUÉS no queda ninguna fila atribuida a un inactivo que tenga responsable activo distinto. Si algo
     no cuadra → `raise exception` (se deshace todo). `raise notice` con el conteo de filas movidas por analista;
   - POSTFLIGHT: huellas nuevas (déjalas como `'PENDIENTE_MEDIR_EN_BANCO'` — Claude las mide en el banco Docker y
     las rellena) + invariantes que la huella no cubre (dueño, ACL no nula y la esperada, prosecdef, provolatile,
     `search_path` vacío; con `is not true`);
   - `COMMENT ON` de las 3 funciones nuevas y de las 7 reescritas (mencionar la regla de baja).
2. `supabase/scripts/baja-analista-heredero/reversa.sql` — restaura los 7 cuerpos vivos EXACTOS (desde `vivo/`) y
   borra las 3 funciones nuevas; con preflight/postflight de huellas.
3. `supabase/scripts/baja-analista-heredero/ensayo-sintetico.sql` — para el banco Docker, todo dentro de una
   transacción que termina en `rollback` (o `DO` que termina en `raise`): siembra analistas A (activo), P (inactivo
   con heredero activo H), I (inactivo sin responsable activo), clientes, contratos (nuevo, upgrade de P + renovación
   registrada por H, contrato de A), una operación de cartera y un cierre externo de P; y comprueba, con salida
   PASS/FAIL por caso: P → H en capital_episodios (contrato, desglose y cooperativa), cartera_f5_fuentes,
   atribucion_contrato_fn (`heredada` true, `adoptada` sin cambiar), metricas_cartera_por_vendedor,
   altas_nuevas_por_analista_fn; I se queda en I; A sin cambios; casos NULL. Mira `supabase/scripts/ensayo-atr2-cadena-sintetica.sql`
   para el patrón de siembra (y los NOT NULL / triggers reales de las tablas en las migraciones).
4. `supabase/scripts/baja-analista-heredero/LEEME.md` — qué hace, cómo ensayar, cómo aplicar
   (`supabase db query --linked --file …` lo corre Miguel con `!`), cómo revertir.
5. Entrada nueva AL FINAL de `supabase/migrations/MIGRACIONES.md` con el formato de las anteriores (estado:
   «en banco, sin aplicar»).

Lee antes: `supabase/migrations/LEEME.md`, la migración patrón citada, `supabase/scripts/baja-analista-heredero/vivo/`.

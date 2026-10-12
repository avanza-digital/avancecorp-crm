---
tags: [facturacion, plan, crm, jerarquia]
fecha: 2026-10-08
estado: propuesta — espera decisiones de Miguel (LEVEL 3)
---

> Plan de la fase 2 de [[Facturacion - auditoria completa (2026-10-08)]]. Sin código. Toca un trigger y funciones del núcleo: plan corto + OK de Miguel antes de escribir nada; ciclo banco → gate → advisors → auditor-rls → Codex → aplica Miguel con `!`. Verificado por Claude en el código: el bloque `$normalizar_directorio$` (`20260828210351:420-421`) movió a los subordinados de Directorio a la única Gerencia sin evento (explica las 2 derivas de prod), y `private.registrar_evento_usuario` exige sesión y descarta choques en silencio (`20260807203740:652-667`). La fase 3 ([[Facturacion - plan fase 3 numeros y hoja Excel (2026-10-08)]]) reescribe `facturacion_diaria_fn`: si esta fase la toca antes, aquella se regenera sobre la huella nueva.

# Facturación · Fase 2 — un evento por cada cambio de supervisor (PLAN CORTO)

Solo lectura (worktree `facturacion-fase1-20261008`, `c0bff295`); nada tocado. Rutas `AAAAMMDD…:línea` = `supabase/migrations/`. **LEVEL 3.**

## 1. Problema
Facturación pone el «supervisor de entonces» leyendo **solo** eventos `jerarquia_actualizada` (`20260916205617:148-173`):
sin tramo usa el de hoy (`:180`) y el `antes` del primer evento vale desde siempre (`-infinity`, `:162`). La baja con
reemplazo mueve subordinados **sin** ese evento (`20260925180145:520-522`; solo `membresia_desactivada`, `:600-612`).
Producción 08/10: 16 eventos, todos primeras asignaciones (`antes` NULL); 0 bajas con traslado; 14 vendedores activos sin
evento; 2 derivas (Carmen Jaramillo, Jorge Marzano: evento 10/08 → Carlos Valles; hoy Administrador) = el bloque
`$normalizar_directorio$` de `20260828210351:391-453`, que movió supervisores con UPDATE (`:420-421`) **sin** evento.

## 2. Vías que cambian `crm.equipo.supervisor_id` (última definición vigente)
| Vía | Dónde | ¿Evento? (`detalle`) | Quién |
|---|---|---|---|
| `crm.actualizar_jerarquia_usuario_fn` | `20260807203740:1506`, UPDATE `:1571-1573` | **Sí** `:1578-1585` `{supervisor_anterior, supervisor_nuevo}`; su replay lo busca por actor+idempotencia `:1541-1555` | Gerencia `:1594-1597` |
| `crm.registrar_vendedor_usuario_fn` (alta) | `20260821233241:7`, INSERT `:200-206` | **Sí** `:225-231` (`anterior` null); su replay lo exige `:63-84` | Gerencia `:252-258` |
| `crm.fijar_membresia_activa_fn` (baja con reemplazo) | `20260925180145:339`, UPDATE `:520-522` | **No** | Gerencia; `eliminar_usuario_fn` sin reemplazo `:156` |
| Bloque único `$normalizar_directorio$` | `20260828210351:420-421`, `:432-433` | **No** | migración (postgres) |
| `crm.purgar_membresia_crm` → FK `on delete set null` | `20260830090000:503`; FK cimientos `:43` | **No** | solo service_role `:512` |
| Escritura directa | GRANT UPDATE a service_role (cimientos `:542`); consola, p. ej. `scripts/carlos-valles-directorio-a-gerencia.sql:55-80` | **No** (ese guion inserta eventos a mano) | service_role, postgres |

No mueven supervisor: `asignar_rol_usuario_fn` (`20260821212628:341-347` alta con NULL, `:371-373` solo `rol_crm`) ni
capacidad (`20260717215535:59-62`). Edge Functions y app solo **leen** `crm.equipo`. `eliminar_usuario_fn` no purga a
quien tiene subordinados: la FK `supervisor_id` cuenta como historial (`20260925180145:51-77`).
**Escritor de hoy:** `private.registrar_evento_usuario` (`20260807203740:642-668`) exige `auth.uid()` (`:651-653`) y hace
`on conflict do nothing` (`:667`). `crm.usuario_eventos` (`:610-640`): `actor_id NOT NULL` (`:612`),
`unique(actor_id, accion, idempotencia)` (`:626-627`), `creado_en = clock_timestamp()` (`:625`), RLS sin policies ni API (`:636-640`).
**Triggers de `crm.equipo` hoy** (ninguno escribe eventos): touch (cimientos `:301`), auditoría → `public.audit_log` (`:403`),
ICS (`20260803164348:634-636`), validar jerarquía (`20260807203740:895-898`), no borrar (`20260830090000:563-566`), par
(`20260830170000:269-272`), retirado ×2 (`20260925180145:46,234`).
**Lectores del evento:** Facturación, los 2 replays de arriba, `test-facturacion.sql` y `test-usuarios-jerarquia.sql`
(cuenta 4 y 3 eventos exactos, `:1518-1527`). Nadie más lee `actor_id`.

## 3. Diseño recomendado: **A** — un trigger en `crm.equipo` es el ÚNICO escritor del evento
A cubre las 6 vías y las futuras (también la migración que causó las derivas), en la misma transacción y sin duplicar
por construcción; no toca la baja (D-2/D-19) ni Facturación. Contra: `actor` puede quedar vacío y 2 RPC se re-anclan.
B (evento en cada función) solo arregla la baja, deja fuera migración/consola/service_role/cascada y pediría un vigía.
Con A no hace falta vigía (regla de Miguel 23/09: prevenir antes que vigilar).

## 4. Migraciones (sin escribir; hora real con `/nueva-migracion`)
**M1 `20261009120000_crm_jerarquia_evento_en_toda_via.sql`** (orden: tabla → núcleo → triggers → RPC → comentarios)
1. `crm.usuario_eventos.actor_id` admite NULL = «cambio sin sesión» (**D1**) + COMMENT.
2. `private.trg_equipo_evento_jerarquia()` (definer, dueño postgres, `search_path=''`, sin EXECUTE): inserta directo
   (no por `registrar_evento_usuario`) actor `auth.uid()`, `detalle {supervisor_anterior: OLD, supervisor_nuevo: NEW, via}`,
   idempotencia = la de la RPC si la declaró para ESE perfil (GUC local `crm.jerarquia_rpc='<perfil>|<uuid>'`), si no
   aleatoria; **sin** `on conflict`: si choca, aborta (nunca pierde un evento en silencio).
3. `AFTER UPDATE OF supervisor_id … WHEN (old.supervisor_id IS DISTINCT FROM new.supervisor_id)` + `AFTER INSERT … WHEN
   (new.supervisor_id IS NOT NULL)`: la baja deja 1 evento por subordinado; la cascada SET NULL, el suyo.
4. Candado `BEFORE INSERT` en `crm.usuario_eventos`: `jerarquia_actualizada` solo desde el trigger o con la válvula
   `crm.relleno_jerarquia='on'` (mismo idioma que `crm.purgando_membresia`, `20260830090000:448`).
5. `actualizar_jerarquia_usuario_fn` y `registrar_vendedor_usuario_fn`: reemplazo ANCLADO al cuerpo vivo (md5 de la
   medición; patrón `20260830090000:406-426`): fijan/limpian el GUC y dejan de llamar a `registrar_evento_usuario`
   para la jerarquía. Mismo actor, acción, objetivo, idempotencia y claves → sus replays no cambian.
6. Postflight: 0 cuerpos en `pg_proc` que emitan el evento a mano; ensayo en subbloque que siempre acaba en `raise`
   (cambio sin sesión → actor NULL; baja → 1 evento por subordinado; replay → `idempotente:true`). Luego `gen:types`.

**M2 `…_crm_jerarquia_relleno_con_evidencia.sql`** solo con **D2**. **M3 `…_crm_facturacion_tramo_inicial_estable.sql`**
solo con **D3**: en el primer tramo `coalesce(e.antes, e.despues)` (primer supervisor conocido). Sin M3, si cambia el
supervisor de alguien con primer evento `antes` NULL (hoy 16), lo vendido antes de ese evento se muda al nuevo.
Ciclo: banco Docker a paridad → M1 → gates → advisors → `auditor-rls` → Codex r1 → Miguel aplica con `!`. No el 10/10.

## 5. Relleno con evidencia
**Fuentes:** `public.audit_log` de `crm.equipo` (fecha exacta y antes/después; `20260910230000:70` dice 0 filas al 10/09
y la medida del 08/10 falló por tipo: `fila_id` es texto, 42883 → re-medir) · fotos `crm.metas_vendedor.supervisor_id` +
`publicada_en` (`20260807203757:34-45`) y `crm.cierre_mes_vendedor` (`20260815002914:129`) · regla de
`20260828210351:391-453` + eventos que acotan la fecha (el del 10/08 y el guion de Carlos, que exige 0 subordinados,
`carlos-valles…sql:46-52`; desactivar lo valida, `20260828210351:302-325`).
**Regla para no inventar:** (1) antes y después constan; nunca `antes` NULL. (2) Fecha exacta, o ventana sin ventas del
analista dentro (la fecha no mueve dinero). (3) Si sería el PRIMER evento (rige desde `-infinity`): ninguna foto previa lo
contradice y Miguel aprueba el diff por mes, sellados incluidos. (4) Los 14 sin eventos NO se rellenan salvo auditoría:
con M1 su primer cambio llevará `antes` = el de hoy y lo que hoy se ve queda congelado. (5) `via:'relleno'`, evidencia,
`creado_en` probado, idempotencia fija; el postflight aborta si el diff no es el aprobado.
**Esperado:** Carmen y Jorge (Carlos → Administrador, ventana 10/08 → 29/08); los supervisores venden desde el 16/09
(`20260916205617:20-21`) → probablemente 0 ventas en la ventana. **Medir antes con** `sql-fase2/medir-relleno.sql`
(read-only): R1 auditoría, R2 derivas y cota, R3 clase de evidencia de los sin evento, R4 exposición a D3, R5 purgas,
R6 diff exacto del relleno por mes/analista/moneda (marca sellados) y las huellas md5 para anclar M1.

## 6. Pruebas
`test-facturacion.sql`: el montaje usa la válvula en sus inserts (`:119,189,229`) y borra lo que deja el trigger tras sus
UPDATE (`:113,188,228,309,319`). Casos nuevos: 13 baja real por `fijar_membresia_activa_fn` con analista **sin eventos**
(estado de prod) → 1 evento por subordinado, lo anterior queda con el que sale, lo posterior con el reemplazo, que no ve lo
anterior · 14 cambio sin sesión → actor NULL · 15 cascada de purga → evento · 16 replay de `actualizar_jerarquia…` →
idempotente y 1 evento · 17 alta → 4 eventos, 1 de jerarquía, replay idempotente · 18 insert a mano sin válvula →
rechazado · 19 mutante sin trigger → 13 rojo · (20 si D3).
**Enganche:** bloque K de `test-rls.mjs` (`:9408-9413`) pasa a ejecutar el oráculo con `psqlBancoSinSecretos`
(`:23-37`) y exigir su token; sin banco o con `CRM_RLS_EXIGE_FACTURACION=1` (`:9260-9266`) = FALLO; más
`npm run test:facturacion:banco`. M1 entra en el `\ir` de `test-usuarios-jerarquia.sql` (`:374-378`) y en `MIGRATIONS`
de `gate-config-operativa.mjs:49-59` (`gate:config`): los conteos 4 y 3 no deben cambiar.

## 7. Reversa
M1 (`scripts/rollback-jerarquia-evento-en-toda-via.sql`, ensayada ×2): quitar 3 triggers y 2 funciones, reponer las 2 RPC
(anclado por md5), `actor_id SET NOT NULL` solo si no hay NULL (si hay, se declara; los eventos no se borran). M3: cuerpo
anterior. M2 no tiene reversa limpia (por eso solo con evidencia y diff aprobado; en último caso, borrar por idempotencia exacta).

## 8. Riesgos
Trigger roto = ningún cambio de jerarquía pasa (postflight + banco + gate) · candado mal puesto rompe alta/replays (casos
16-17) · seed y montajes ahora dejan eventos con actor NULL (ajustar oráculos) · bloqueos: trigger nuevo en `crm.equipo` y
ALTER en `crm.usuario_eventos` → `lock_timeout` 5 s, horario valle · esquive declarado (no vigilado): `DISABLE TRIGGER` del
dueño o `session_replication_role=replica` · el relleno cambia meses cerrados en Facturación (no la foto sellada, que sale de metas).

## 9. Qué decide Miguel
**D0** A (recomendado) o B. **D1** evento sin sesión con actor vacío (recomendado; «un rastro nunca puede tumbar lo que
audita», `20260829230000:85`) o un id fijo «sistema». **D2** tras `medir-relleno.sql`, aprobar cada relleno con su diff
(por defecto solo Carmen y Jorge si `ventas_en_ventana = 0`). **D3** congelar el tramo inicial al primer supervisor
conocido (cambia la regla del 16/09, `20260916205617:29-33`) o dejarlo.


## Anexo — consulta de medición (SOLO LECTURA, no ejecutada todavía)

La corre Miguel con `!` desde `CRM-Avance-Corp/`: `supabase db query --linked -f <este SQL> --output-format json > salida.json`. Abre con `begin transaction read only;` y cierra con `rollback;`.

```sql
-- medir-relleno.sql — Facturación, fase 2 (jerarquía). SOLO LECTURA.
--
-- PARA QUÉ: antes de escribir la migración del evento de jerarquía y de decidir
-- cualquier relleno, medir en PRODUCCIÓN qué historia de supervisores se puede
-- reconstruir CON EVIDENCIA y qué cambiaría en Facturación si se rellenara.
-- No inventa nada: solo cuenta, lista y SIMULA (en memoria) el efecto.
--
-- CÓMO LO CORRE MIGUEL (con `!`, desde CRM-Avance-Corp):
--   supabase db query --linked -f <ruta>/medir-relleno.sql --output-format json > medir-relleno.json
-- (o con el runner de la auditoría, que exige que el archivo abra con
--  «begin transaction read only;» y cierre con «rollback;»).
--
-- POR QUÉ ES SEGURO
--   · Transacción READ ONLY: cualquier INSERT/UPDATE/DELETE/CREATE fallaría (25006).
--   · No llama a ninguna función que escriba; private.capital_episodios es STABLE.
--   · El resultado viaja en un GUC LOCAL (set_config(..., true)), que no es una
--     escritura y muere con el ROLLBACK. `db query --linked` solo devuelve la
--     última sentencia con filas y no trae NOTICE: por eso un bloque DO + un GUC.
--   · Cada sección va en su propio subbloque: si una falla, deja {"error": ...}
--     y las demás siguen.
--
-- SECCIONES DEL RESULTADO
--   R0_resumen                 cifras para leer de un vistazo
--   H_inventario               triggers vivos de crm.equipo, funciones que escriben
--                              crm.equipo (¿emiten el evento?), FKs con SET NULL,
--                              privilegios, columnas de crm.usuario_eventos y
--                              HUELLAS (md5) que la migración usará de ancla
--   H_cron_que_nombra_equipo   jobs de pg_cron que tocan crm.equipo
--   R1_auditoria_equipo        public.audit_log de crm.equipo: ¿existe rastro con
--                              fecha exacta y antes/después de cada cambio?
--   R2_derivas                 supervisor de HOY ≠ el del último evento (Carmen,
--                              Jorge…): eventos propios, eventos del jefe anterior
--                              (cota superior de la fecha) y fotos de metas
--   R3_sin_eventos             personas sin ningún evento: fotos de metas/cierre,
--                              auditoría y ventas por mes → CLASE de evidencia
--   R4_primer_evento_sin_antes exposición a la decisión D3 (tramo inicial estable)
--   R5_*                       purgas, retiros y eventos huérfanos
--   R6_simulacion_relleno      candidatos con evidencia y el DIFF exacto de
--                              Facturación (mes, analista, de → a, capital) si se
--                              rellenaran; marca meses sellados
--
-- Columnas verificadas contra las migraciones del repo:
--   crm.equipo(perfil_id, rol_crm, supervisor_id, activo, creado_en, actualizado_en)  cimientos:40-50
--   crm.usuario_eventos(id, actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)  20260807203740:610-628
--   public.audit_log(tabla, operacion, fila_id, usuario_id, ts, data_antes, data_despues)  cimientos:390, 20260925002615:104
--     (fila_id es TEXT en producción: la medida del 08/10 falló con 42883 al compararlo con uuid)
--   crm.meta_periodos(id, periodo, revision, publicada_en) / crm.metas_vendedor(meta_periodo_id, vendedor_id, supervisor_id)  20260807203757:12-45
--   crm.cierre_mes_vendedor(periodo, vendedor_id, supervisor_id) / crm.periodos_cerrados(periodo)  20260815002914:77-130
--   private.capital_episodios(timestamptz, timestamptz, boolean, uuid[]) → fecha, medida, moneda, analista_id, monto  20260829200000:50
--   Reconstrucción del «supervisor de entonces»: copia de crm.facturacion_diaria_fn (20260916205617:148-199).

begin transaction read only;
set local statement_timeout = '180s';
set local lock_timeout = '5s';

do $medir$
declare
  v_res jsonb := '{}'::jsonb;
  v_tmp jsonb;
begin
  -- ── R0. Resumen ───────────────────────────────────────────────────────────
  begin
    v_tmp := jsonb_build_object(
      'generado_en_lima', (now() at time zone 'America/Lima')::text,
      'eventos_jerarquia', (select count(*) from crm.usuario_eventos ue
                             where ue.accion = 'jerarquia_actualizada'),
      'eventos_jerarquia_con_antes_null', (select count(*) from crm.usuario_eventos ue
                             where ue.accion = 'jerarquia_actualizada'
                               and ue.detalle ->> 'supervisor_anterior' is null),
      'personas_con_eventos', (select count(distinct ue.objetivo_id) from crm.usuario_eventos ue
                             where ue.accion = 'jerarquia_actualizada'),
      'vendedores_y_supervisores_sin_eventos', (select count(*) from crm.equipo e
                             where e.rol_crm in ('vendedor', 'supervisor')
                               and not exists (select 1 from crm.usuario_eventos ue
                                               where ue.accion = 'jerarquia_actualizada'
                                                 and ue.objetivo_id = e.perfil_id)),
      'filas_auditoria_crm_equipo', (select count(*) from public.audit_log al
                             where al.tabla = 'crm.equipo'),
      'meses_sellados', (select coalesce(jsonb_agg(pc.periodo order by pc.periodo), '[]'::jsonb)
                         from crm.periodos_cerrados pc)
    );
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R0_resumen', v_tmp);

  -- ── H. Inventario vivo (confirma en producción lo que dice el repo) ───────
  begin
    v_tmp := jsonb_build_object(
      'columnas_crm_equipo', (
        select coalesce(jsonb_agg(a.attname::text order by a.attnum), '[]'::jsonb)
        from pg_catalog.pg_attribute a
        where a.attrelid = 'crm.equipo'::regclass and a.attnum > 0 and not a.attisdropped),
      'triggers_crm_equipo', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'nombre', t.tgname::text,
                 'habilitado', t.tgenabled::text,
                 'definicion', pg_catalog.pg_get_triggerdef(t.oid))
               order by t.tgname), '[]'::jsonb)
        from pg_catalog.pg_trigger t
        where t.tgrelid = 'crm.equipo'::regclass and not t.tgisinternal),
      'funciones_que_escriben_crm_equipo', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'funcion', p.oid::regprocedure::text,
                 'security_definer', p.prosecdef,
                 'md5_prosrc', pg_catalog.md5(p.prosrc),
                 'nombra_supervisor_id', p.prosrc ~* 'supervisor_id',
                 'emite_jerarquia_actualizada', p.prosrc ~ 'jerarquia_actualizada',
                 'execute_authenticated', pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
                 'execute_service_role', pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'))
               order by p.oid::regprocedure::text), '[]'::jsonb)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where n.nspname not in ('pg_catalog', 'information_schema')
          and p.prokind in ('f', 'p')
          and p.prosrc ~* '(update\s+(only\s+)?"?crm"?\."?equipo"?|insert\s+into\s+"?crm"?\."?equipo"?|delete\s+from\s+(only\s+)?"?crm"?\."?equipo"?|merge\s+into\s+"?crm"?\."?equipo"?)'),
      'fks_hacia_crm_equipo_que_borran_o_anulan', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'tabla', c.conrelid::regclass::text,
                 'restriccion', c.conname::text,
                 'al_borrar', c.confdeltype::text)
               order by c.conrelid::regclass::text, c.conname), '[]'::jsonb)
        from pg_catalog.pg_constraint c
        where c.contype = 'f' and c.confrelid = 'crm.equipo'::regclass
          and c.confdeltype in ('n', 'd', 'c')),
      'privilegios_crm_equipo', jsonb_build_object(
        'service_role_insert', pg_catalog.has_table_privilege('service_role', 'crm.equipo', 'INSERT'),
        'service_role_update', pg_catalog.has_table_privilege('service_role', 'crm.equipo', 'UPDATE'),
        'service_role_delete', pg_catalog.has_table_privilege('service_role', 'crm.equipo', 'DELETE'),
        'authenticated_update_supervisor_id',
          pg_catalog.has_column_privilege('authenticated', 'crm.equipo', 'supervisor_id', 'UPDATE'),
        'authenticated_insert', pg_catalog.has_table_privilege('authenticated', 'crm.equipo', 'INSERT')),
      'usuario_eventos', jsonb_build_object(
        'actor_id_not_null', (select a.attnotnull from pg_catalog.pg_attribute a
                              where a.attrelid = 'crm.usuario_eventos'::regclass and a.attname = 'actor_id'),
        'restricciones', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'nombre', c.conname::text, 'def', pg_catalog.pg_get_constraintdef(c.oid))
                                 order by c.conname), '[]'::jsonb)
                          from pg_catalog.pg_constraint c
                          where c.conrelid = 'crm.usuario_eventos'::regclass),
        'triggers', (select coalesce(jsonb_agg(t.tgname::text order by t.tgname), '[]'::jsonb)
                     from pg_catalog.pg_trigger t
                     where t.tgrelid = 'crm.usuario_eventos'::regclass and not t.tgisinternal),
        'eventos_por_accion', (select coalesce(jsonb_object_agg(x.accion, x.n), '{}'::jsonb)
                               from (select ue.accion, count(*) as n
                                     from crm.usuario_eventos ue group by ue.accion) x)),
      -- Anclas para la migración: una función viva NO se reteclea. md5(prosrc) es
      -- estable; pg_get_functiondef depende del search_path de la sesión.
      'huellas', (
        select jsonb_object_agg(f.firma,
                 case when to_regprocedure(f.firma) is null then null
                 else (select jsonb_build_object(
                         'md5_prosrc', pg_catalog.md5(p.prosrc),
                         'security_definer', p.prosecdef,
                         'proconfig', pg_catalog.array_to_string(p.proconfig, ','),
                         'dueno', pg_catalog.pg_get_userbyid(p.proowner))
                       from pg_catalog.pg_proc p where p.oid = to_regprocedure(f.firma)) end)
        from (values
          ('crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)'),
          ('crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)'),
          ('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)'),
          ('crm.asignar_rol_usuario_fn(uuid,text,timestamptz,uuid)'),
          ('crm.purgar_membresia_crm(uuid,text)'),
          ('crm.eliminar_usuario_fn(uuid,text,timestamptz,timestamptz)'),
          ('private.registrar_evento_usuario(text,uuid,jsonb,uuid)'),
          ('private.trg_validar_equipo_usuario_crm()'),
          ('private.log_audit_crm()'),
          ('crm.facturacion_diaria_fn(date)')
        ) as f(firma))
    );
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('H_inventario', v_tmp);

  begin
    v_tmp := (
      select coalesce(jsonb_object_agg(v.version,
               exists (select 1 from supabase_migrations.schema_migrations sm where sm.version = v.version)),
             '{}'::jsonb)
      from (values ('20260807203740'), ('20260821212628'), ('20260821233241'), ('20260828210351'),
                   ('20260830090000'), ('20260916205617'), ('20260925180145')) as v(version));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('H_migraciones_registradas', v_tmp);

  begin
    if to_regclass('cron.job') is not null then
      execute $q$
        select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'cuando', j.schedule)
                                  order by j.jobname), '[]'::jsonb)
        from cron.job j
        where j.command ~* 'crm\.equipo'
      $q$ into v_tmp;
    else
      v_tmp := to_jsonb('sin pg_cron'::text);
    end if;
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('H_cron_que_nombra_equipo', v_tmp);

  -- ── R1. Auditoría de crm.equipo (trg_audit_equipo → public.audit_log) ─────
  --    ¿Hay rastro con fecha exacta y antes/después? (20260910230000:70 dice que
  --    el 10/09 había 0 filas: se vuelve a medir, bien tipado).
  begin
    v_tmp := (
      with
      aud as (
        select al.operacion,
               al.fila_id::text as perfil_txt,
               coalesce(pg_catalog.to_jsonb(al) ->> 'ts',
                        pg_catalog.to_jsonb(al) ->> 'creado_en',
                        pg_catalog.to_jsonb(al) ->> 'created_at')::timestamptz as en,
               al.data_antes ->> 'supervisor_id' as de,
               al.data_despues ->> 'supervisor_id' as a_sup,
               al.usuario_id::text as por_txt
        from public.audit_log al
        where al.tabla = 'crm.equipo'
      ),
      cambios as (
        select x.*,
               exists (select 1 from crm.usuario_eventos j
                       where j.accion = 'jerarquia_actualizada'
                         and j.objetivo_id::text = x.perfil_txt
                         and (j.detalle ->> 'supervisor_nuevo') is not distinct from x.a_sup
                         and j.creado_en between x.en - interval '5 minutes'
                                             and x.en + interval '5 minutes') as con_evento
        from aud x
        where (x.operacion = 'UPDATE' and x.de is distinct from x.a_sup)
           or (x.operacion = 'INSERT' and x.a_sup is not null)
           or x.operacion = 'DELETE'
      )
      select jsonb_build_object(
        'trigger_auditoria_habilitado', exists (
          select 1 from pg_catalog.pg_trigger t
          where t.tgrelid = 'crm.equipo'::regclass and t.tgname = 'trg_audit_equipo'
            and t.tgenabled <> 'D'),
        'filas', (select count(*) from aud),
        'por_operacion', (select coalesce(jsonb_object_agg(z.operacion, z.n), '{}'::jsonb)
                          from (select a.operacion, count(*) as n from aud a group by a.operacion) z),
        'desde_lima', (select (min(a.en) at time zone 'America/Lima')::text from aud a),
        'hasta_lima', (select (max(a.en) at time zone 'America/Lima')::text from aud a),
        'cambios_de_supervisor', (select count(*) from cambios c where c.operacion = 'UPDATE'),
        'cambios_de_supervisor_sin_evento', (select count(*) from cambios c
                                             where c.operacion = 'UPDATE' and not c.con_evento),
        'detalle', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'operacion', c.operacion,
                   'en_lima', (c.en at time zone 'America/Lima')::text,
                   'perfil_id', c.perfil_txt, 'persona', pp.nombre_completo,
                   'de_id', c.de, 'de', pd.nombre_completo,
                   'a_id', c.a_sup, 'a', pa.nombre_completo,
                   'hecho_por', pu.nombre_completo,
                   'con_evento', c.con_evento)
                 order by c.en), '[]'::jsonb)
          from cambios c
          left join public.perfiles pp on pp.id::text = c.perfil_txt
          left join public.perfiles pd on pd.id::text = c.de
          left join public.perfiles pa on pa.id::text = c.a_sup
          left join public.perfiles pu on pu.id::text = c.por_txt)
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R1_auditoria_equipo', v_tmp);

  -- ── R2. Derivas: el supervisor de HOY no es el del último evento ──────────
  begin
    v_tmp := (
      with
      ult as (
        select distinct on (ue.objetivo_id)
               ue.objetivo_id, ue.creado_en,
               (ue.detalle ->> 'supervisor_nuevo')::uuid as segun
        from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
        order by ue.objetivo_id, ue.creado_en desc, ue.id desc
      ),
      der as (
        select u.objetivo_id as perfil_id, u.creado_en as ultimo_evento, u.segun,
               e.supervisor_id as hoy, e.rol_crm, e.activo,
               e.actualizado_en, (e.perfil_id is not null) as en_equipo
        from ult u
        left join crm.equipo e on e.perfil_id = u.objetivo_id
        where e.supervisor_id is distinct from u.segun
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'perfil_id', d.perfil_id, 'persona', pp.nombre_completo,
               'rol', d.rol_crm, 'activo', d.activo, 'existe_en_equipo', d.en_equipo,
               'supervisor_hoy_id', d.hoy, 'supervisor_hoy', ph.nombre_completo,
               'segun_ultimo_evento_id', d.segun, 'segun_ultimo_evento', ps.nombre_completo,
               'ultimo_evento_lima', (d.ultimo_evento at time zone 'America/Lima')::text,
               'equipo_actualizado_lima', (d.actualizado_en at time zone 'America/Lima')::text,
               'eventos_propios', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'accion', x.accion,
                          'en_lima', (x.creado_en at time zone 'America/Lima')::text,
                          'detalle', x.detalle) order by x.creado_en), '[]'::jsonb)
                 from crm.usuario_eventos x where x.objetivo_id = d.perfil_id),
               'eventos_del_jefe_anterior_despues', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'accion', x.accion,
                          'en_lima', (x.creado_en at time zone 'America/Lima')::text,
                          'via', x.detalle ->> 'via',
                          'motivo', x.detalle ->> 'motivo') order by x.creado_en), '[]'::jsonb)
                 from crm.usuario_eventos x
                 where x.objetivo_id = d.segun and x.creado_en > d.ultimo_evento),
               -- Cota superior: desactivar al jefe anterior exige que ya no tenga
               -- subordinados activos (20260828210351:302-325) y el guion de Carlos
               -- lo comprueba aparte (carlos-valles-directorio-a-gerencia.sql:46-52).
               'cota_superior_lima', (
                 select (min(x.creado_en) at time zone 'America/Lima')::text
                 from crm.usuario_eventos x
                 where x.objetivo_id = d.segun and x.creado_en > d.ultimo_evento
                   and x.accion in ('membresia_desactivada', 'rol_cambiado')),
               'fotos_metas_desde_ultimo_evento', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'periodo', mp.periodo, 'revision', mp.revision,
                          'publicada_lima', (mp.publicada_en at time zone 'America/Lima')::text,
                          'supervisor_id', mv.supervisor_id) order by mp.publicada_en), '[]'::jsonb)
                 from crm.metas_vendedor mv
                 join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
                 where mv.vendedor_id = d.perfil_id and mp.publicada_en > d.ultimo_evento))
             order by pp.nombre_completo), '[]'::jsonb)
      from der d
      left join public.perfiles pp on pp.id = d.perfil_id
      left join public.perfiles ph on ph.id = d.hoy
      left join public.perfiles ps on ps.id = d.segun);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R2_derivas', v_tmp);

  -- ── R3. Personas SIN ningún evento: ¿qué evidencia hay de su historia? ────
  --    Clases: cambio_auditado (relleno posible con fecha exacta) ·
  --    foto_distinta_sin_fecha (una foto contradice al de hoy: NO rellenar sin
  --    decisión) · constante_con_evidencia (todas las fotos = hoy: no hace falta
  --    relleno) · sin_evidencia (se queda sin evento; con el trigger, su primer
  --    cambio futuro congela lo que hoy se ve).
  begin
    v_tmp := (
      with
      conev as (
        select distinct ue.objetivo_id from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
      ),
      ven as (
        select e.analista_id,
               date_trunc('month', (e.fecha at time zone 'America/Lima'))::date as mes,
               e.moneda, count(*) as ops, sum(e.monto) as cap
        from private.capital_episodios(
               ('2020-01-01'::timestamp at time zone 'America/Lima'),
               ('2030-01-01'::timestamp at time zone 'America/Lima'),
               true, '{}'::uuid[]) e
        where e.medida = 'stock' and e.analista_id is not null
        group by 1, 2, 3
      ),
      gente as (
        select e.perfil_id from crm.equipo e
        where e.rol_crm in ('vendedor', 'supervisor')
          and not exists (select 1 from conev c where c.objetivo_id = e.perfil_id)
        union
        select v.analista_id from ven v
        where not exists (select 1 from conev c where c.objetivo_id = v.analista_id)
      ),
      ficha as (
        select g.perfil_id, e.rol_crm, e.activo, e.supervisor_id as hoy,
               e.creado_en, e.actualizado_en,
               (select count(*) from public.audit_log al
                 where al.tabla = 'crm.equipo' and al.fila_id::text = g.perfil_id::text) as filas_auditoria,
               (select count(*) from public.audit_log al
                 where al.tabla = 'crm.equipo' and al.fila_id::text = g.perfil_id::text
                   and al.operacion = 'UPDATE'
                   and (al.data_antes ->> 'supervisor_id') is distinct from (al.data_despues ->> 'supervisor_id'))
                 as cambios_auditados,
               (select count(*) from crm.metas_vendedor mv where mv.vendedor_id = g.perfil_id) as fotos_metas,
               (select count(*) from crm.metas_vendedor mv
                 where mv.vendedor_id = g.perfil_id
                   and mv.supervisor_id is distinct from e.supervisor_id) as fotos_metas_distintas,
               (select count(*) from crm.cierre_mes_vendedor cm where cm.vendedor_id = g.perfil_id) as fotos_cierre,
               (select count(*) from crm.cierre_mes_vendedor cm
                 where cm.vendedor_id = g.perfil_id
                   and cm.supervisor_id is distinct from e.supervisor_id) as fotos_cierre_distintas
        from gente g
        left join crm.equipo e on e.perfil_id = g.perfil_id
      ),
      clasif as (
        select f.*,
               case
                 when f.rol_crm is null then 'sin_fila_en_equipo'
                 when f.cambios_auditados > 0 then 'cambio_auditado'
                 when f.fotos_metas_distintas + f.fotos_cierre_distintas > 0 then 'foto_distinta_sin_fecha'
                 when f.fotos_metas + f.fotos_cierre > 0 then 'constante_con_evidencia'
                 else 'sin_evidencia'
               end as clase
        from ficha f
      )
      select jsonb_build_object(
        'personas', (select count(*) from clasif),
        'activas', (select count(*) from clasif c where c.activo),
        'por_clase', (select coalesce(jsonb_object_agg(z.clase, z.n), '{}'::jsonb)
                      from (select c.clase, count(*) as n from clasif c group by c.clase) z),
        'detalle', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'perfil_id', c.perfil_id, 'persona', pp.nombre_completo,
                   'rol', c.rol_crm, 'activo', c.activo, 'clase', c.clase,
                   'supervisor_hoy', ph.nombre_completo,
                   'equipo_creado_lima', (c.creado_en at time zone 'America/Lima')::text,
                   'equipo_actualizado_lima', (c.actualizado_en at time zone 'America/Lima')::text,
                   'filas_auditoria', c.filas_auditoria, 'cambios_auditados', c.cambios_auditados,
                   'fotos_metas', c.fotos_metas, 'fotos_metas_distintas', c.fotos_metas_distintas,
                   'fotos_cierre', c.fotos_cierre, 'fotos_cierre_distintas', c.fotos_cierre_distintas,
                   'fotos_metas_detalle', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'periodo', mp.periodo, 'revision', mp.revision,
                              'publicada_lima', (mp.publicada_en at time zone 'America/Lima')::text,
                              'supervisor', psm.nombre_completo,
                              'igual_a_hoy', mv.supervisor_id is not distinct from c.hoy)
                            order by mp.publicada_en), '[]'::jsonb)
                     from crm.metas_vendedor mv
                     join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
                     left join public.perfiles psm on psm.id = mv.supervisor_id
                     where mv.vendedor_id = c.perfil_id),
                   'ventas_por_mes', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'mes', v.mes, 'moneda', v.moneda,
                              'operaciones', v.ops, 'capital', v.cap)
                            order by v.mes, v.moneda), '[]'::jsonb)
                     from ven v where v.analista_id = c.perfil_id))
                 order by c.clase, pp.nombre_completo), '[]'::jsonb)
          from clasif c
          left join public.perfiles pp on pp.id = c.perfil_id
          left join public.perfiles ph on ph.id = c.hoy)
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R3_sin_eventos', v_tmp);

  -- ── R4. Primer evento con supervisor_anterior NULL (decisión D3) ──────────
  --    Antes de ese evento Facturación imputa al supervisor de HOY
  --    (20260916205617:162 + :180). Si después cambia, lo de antes se MUDA.
  --    Con D3 se imputaría al PRIMER supervisor conocido (estable).
  begin
    v_tmp := (
      with
      ev as (
        select ue.objetivo_id, ue.creado_en,
               (ue.detalle ->> 'supervisor_anterior')::uuid as antes,
               (ue.detalle ->> 'supervisor_nuevo')::uuid as despues,
               row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
        from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
      ),
      primero as (
        select ev.objetivo_id, ev.creado_en, ev.despues, eq.supervisor_id as hoy,
               (ev.creado_en at time zone 'America/Lima')::date as dia
        from ev
        left join crm.equipo eq on eq.perfil_id = ev.objetivo_id
        where ev.n = 1 and ev.antes is null
      ),
      eps as (
        select (e.fecha at time zone 'America/Lima')::date as dia, e.moneda, e.analista_id, e.monto
        from private.capital_episodios(
               ('2020-01-01'::timestamp at time zone 'America/Lima'),
               ('2030-01-01'::timestamp at time zone 'America/Lima'),
               true, '{}'::uuid[]) e
        where e.medida = 'stock'
          and e.analista_id in (select p.objetivo_id from primero p)
      )
      select jsonb_build_object(
        'personas', (select count(*) from primero),
        'con_ventas_antes_del_primer_evento', (
          select count(distinct p.objetivo_id) from primero p
          join eps ep on ep.analista_id = p.objetivo_id and ep.dia < p.dia),
        'hoy_distinto_del_primer_supervisor', (
          select count(*) from primero p where p.hoy is distinct from p.despues),
        'operaciones_que_cambiarian_con_D3', (
          select count(*) from primero p
          join eps ep on ep.analista_id = p.objetivo_id and ep.dia < p.dia
          where p.hoy is distinct from p.despues),
        'detalle', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'persona', pp.nombre_completo,
                   'primer_evento_lima', (p.creado_en at time zone 'America/Lima')::text,
                   'primer_supervisor', p1.nombre_completo,
                   'supervisor_hoy', ph.nombre_completo,
                   'ventas_antes', (select count(*) from eps ep
                                    where ep.analista_id = p.objetivo_id and ep.dia < p.dia),
                   'capital_antes_pen', (select coalesce(sum(ep.monto), 0) from eps ep
                                         where ep.analista_id = p.objetivo_id and ep.dia < p.dia
                                           and ep.moneda = 'PEN'),
                   'capital_antes_usd', (select coalesce(sum(ep.monto), 0) from eps ep
                                         where ep.analista_id = p.objetivo_id and ep.dia < p.dia
                                           and ep.moneda = 'USD'))
                 order by p.creado_en), '[]'::jsonb)
          from primero p
          left join public.perfiles pp on pp.id = p.objetivo_id
          left join public.perfiles p1 on p1.id = p.despues
          left join public.perfiles ph on ph.id = p.hoy
          where p.hoy is distinct from p.despues
             or exists (select 1 from eps ep where ep.analista_id = p.objetivo_id and ep.dia < p.dia))
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R4_primer_evento_sin_antes', v_tmp);

  -- ── R5. Purgas (la FK supervisor_id ON DELETE SET NULL, cimientos:43), retiros
  --    y eventos de personas que ya no están en crm.equipo ──────────────────
  begin
    v_tmp := (
      select coalesce(jsonb_agg(jsonb_build_object(
               'perfil_id', m.perfil_id, 'rol_crm', m.rol_crm,
               'activo_al_purgar', m.activo_al_purgar,
               'purgado_lima', (m.purgado_en at time zone 'America/Lima')::text,
               'fue_supervisor_segun_eventos', exists (
                 select 1 from crm.usuario_eventos ue
                 where ue.accion = 'jerarquia_actualizada'
                   and (ue.detalle ->> 'supervisor_nuevo' = m.perfil_id::text
                        or ue.detalle ->> 'supervisor_anterior' = m.perfil_id::text)),
               'fue_supervisor_segun_auditoria', exists (
                 select 1 from public.audit_log al
                 where al.tabla = 'crm.equipo'
                   and (al.data_antes ->> 'supervisor_id' = m.perfil_id::text
                        or al.data_despues ->> 'supervisor_id' = m.perfil_id::text)))
             order by m.purgado_en), '[]'::jsonb)
      from private.membresias_purgadas m);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R5_membresias_purgadas', v_tmp);

  begin
    v_tmp := (
      select coalesce(jsonb_agg(jsonb_build_object(
               'perfil_id', r.perfil_id, 'rol_crm', r.rol_crm, 'resultado', r.resultado,
               'retirado_lima', (r.retirado_en at time zone 'America/Lima')::text)
             order by r.retirado_en), '[]'::jsonb)
      from private.usuarios_retirados r);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R5_usuarios_retirados', v_tmp);

  begin
    v_tmp := jsonb_build_object(
      'eventos_jerarquia_de_personas_sin_fila_en_equipo', (
        select count(*) from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
          and not exists (select 1 from crm.equipo e where e.perfil_id = ue.objetivo_id)),
      'vendedores_activos_sin_supervisor', (
        select count(*) from crm.equipo e
        where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id is null));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R5_huerfanos', v_tmp);

  -- ── R6. SIMULACIÓN del relleno (en memoria, nada se escribe) ──────────────
  --    Candidatos SOLO con evidencia:
  --      · 'auditoria': un cambio de supervisor de public.audit_log sin evento
  --        (fecha exacta, antes y después del propio rastro);
  --      · 'cota_jefe_anterior': una deriva (R2) sin rastro de auditoría, con
  --        antes = el del último evento, después = el de hoy y fecha = la cota
  --        superior (primer membresia_desactivada/rol_cambiado del jefe
  --        anterior). La fecha solo es aceptable si ventas_en_ventana = 0.
  --    Se reconstruye el «supervisor de entonces» de cada venta con y sin esos
  --    eventos (misma regla que crm.facturacion_diaria_fn) y se lista el DIFF.
  begin
    v_tmp := (
      with
      ev_real as (
        select ue.id, ue.objetivo_id, ue.creado_en,
               (ue.detalle ->> 'supervisor_anterior')::uuid as antes,
               (ue.detalle ->> 'supervisor_nuevo')::uuid as despues
        from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
      ),
      aud as (
        select al.fila_id::text as perfil_txt,
               coalesce(pg_catalog.to_jsonb(al) ->> 'ts',
                        pg_catalog.to_jsonb(al) ->> 'creado_en',
                        pg_catalog.to_jsonb(al) ->> 'created_at')::timestamptz as en,
               al.data_antes ->> 'supervisor_id' as de,
               al.data_despues ->> 'supervisor_id' as a_sup
        from public.audit_log al
        where al.tabla = 'crm.equipo' and al.operacion = 'UPDATE'
          and (al.data_antes ->> 'supervisor_id') is distinct from (al.data_despues ->> 'supervisor_id')
      ),
      aud_sin_evento as (
        select a.* from aud a
        where not exists (
          select 1 from ev_real j
          where j.objetivo_id::text = a.perfil_txt
            and j.despues::text is not distinct from a.a_sup
            and j.creado_en between a.en - interval '5 minutes' and a.en + interval '5 minutes')
      ),
      ult as (
        select distinct on (r.objetivo_id) r.objetivo_id, r.creado_en, r.despues
        from ev_real r
        order by r.objetivo_id, r.creado_en desc, r.id desc
      ),
      deriva as (
        select u.objetivo_id, u.creado_en as desde, u.despues as segun, e.supervisor_id as hoy,
               (select min(x.creado_en) from crm.usuario_eventos x
                 where x.objetivo_id = u.despues and x.creado_en > u.creado_en
                   and x.accion in ('membresia_desactivada', 'rol_cambiado')) as cota
        from ult u
        join crm.equipo e on e.perfil_id = u.objetivo_id
        where e.supervisor_id is distinct from u.despues
          and e.supervisor_id is not null and u.despues is not null
      ),
      sint as (
        select a.perfil_txt::uuid as objetivo_id, a.en as creado_en,
               nullif(a.de, '')::uuid as antes, nullif(a.a_sup, '')::uuid as despues,
               'auditoria'::text as fuente, a.en as ventana_desde
        from aud_sin_evento a
        union all
        select d.objetivo_id, d.cota, d.segun, d.hoy, 'cota_jefe_anterior'::text, d.desde
        from deriva d
        where d.cota is not null
          and not exists (select 1 from aud_sin_evento a
                          where a.perfil_txt = d.objetivo_id::text and a.en > d.desde)
      ),
      hipo as (
        select r.id, r.objetivo_id, r.creado_en, r.antes, r.despues from ev_real r
        union all
        select 9000000000000000000::bigint + row_number() over (order by s.objetivo_id, s.creado_en),
               s.objetivo_id, s.creado_en, s.antes, s.despues
        from sint s
      ),
      n_real as (
        select r.objetivo_id, r.antes, r.despues,
               (r.creado_en at time zone 'America/Lima')::date as dia_cambio,
               row_number() over (partition by r.objetivo_id order by r.creado_en, r.id) as n
        from ev_real r
      ),
      t_real as (
        select a.objetivo_id, '-infinity'::date as desde, a.dia_cambio as hasta, a.antes as sup
        from n_real a where a.n = 1
        union all
        select a.objetivo_id, a.dia_cambio, coalesce(b.dia_cambio, 'infinity'::date), a.despues
        from n_real a
        left join n_real b on b.objetivo_id = a.objetivo_id and b.n = a.n + 1
      ),
      n_hipo as (
        select h.objetivo_id, h.antes, h.despues,
               (h.creado_en at time zone 'America/Lima')::date as dia_cambio,
               row_number() over (partition by h.objetivo_id order by h.creado_en, h.id) as n
        from hipo h
      ),
      t_hipo as (
        select a.objetivo_id, '-infinity'::date as desde, a.dia_cambio as hasta, a.antes as sup
        from n_hipo a where a.n = 1
        union all
        select a.objetivo_id, a.dia_cambio, coalesce(b.dia_cambio, 'infinity'::date), a.despues
        from n_hipo a
        left join n_hipo b on b.objetivo_id = a.objetivo_id and b.n = a.n + 1
      ),
      eps as (
        select (e.fecha at time zone 'America/Lima')::date as dia, e.moneda, e.analista_id, e.monto
        from private.capital_episodios(
               ('2020-01-01'::timestamp at time zone 'America/Lima'),
               ('2030-01-01'::timestamp at time zone 'America/Lima'),
               true, '{}'::uuid[]) e
        where e.medida = 'stock'
          and e.analista_id in (select s.objetivo_id from sint s)
      ),
      atrib as (
        select ep.dia, ep.moneda, ep.analista_id, ep.monto,
               coalesce((select t.sup from t_real t
                          where t.objetivo_id = ep.analista_id
                            and ep.dia >= t.desde and ep.dia < t.hasta limit 1),
                        eq.supervisor_id) as sup_real,
               coalesce((select t.sup from t_hipo t
                          where t.objetivo_id = ep.analista_id
                            and ep.dia >= t.desde and ep.dia < t.hasta limit 1),
                        eq.supervisor_id) as sup_hipo
        from eps ep
        left join crm.equipo eq on eq.perfil_id = ep.analista_id
      ),
      cambia as (
        select date_trunc('month', x.dia)::date as mes,
               x.analista_id, x.sup_real, x.sup_hipo, x.moneda,
               count(*) as ops, sum(x.monto) as cap
        from atrib x
        where x.sup_real is distinct from x.sup_hipo
        group by 1, 2, 3, 4, 5
      )
      select jsonb_build_object(
        'candidatos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'perfil_id', s.objetivo_id, 'persona', pp.nombre_completo,
                   'fuente', s.fuente,
                   'fecha_propuesta_lima', (s.creado_en at time zone 'America/Lima')::text,
                   'ventana_desde_lima', (s.ventana_desde at time zone 'America/Lima')::text,
                   'antes_id', s.antes, 'antes', pa.nombre_completo,
                   'despues_id', s.despues, 'despues', pd.nombre_completo,
                   'seria_primer_evento', not exists (
                     select 1 from ev_real r
                     where r.objetivo_id = s.objetivo_id and r.creado_en < s.creado_en),
                   'ventas_en_ventana', (
                     select count(*) from eps ep
                     where ep.analista_id = s.objetivo_id
                       and ep.dia >= (s.ventana_desde at time zone 'America/Lima')::date
                       and ep.dia <= (s.creado_en at time zone 'America/Lima')::date),
                   'ventas_antes_de_la_fecha', (
                     select count(*) from eps ep
                     where ep.analista_id = s.objetivo_id
                       and ep.dia < (s.creado_en at time zone 'America/Lima')::date),
                   'fotos_metas_previas_que_contradicen_antes', (
                     select count(*) from crm.metas_vendedor mv
                     join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
                     where mv.vendedor_id = s.objetivo_id and mp.publicada_en < s.creado_en
                       and mv.supervisor_id is distinct from s.antes))
                 order by s.creado_en), '[]'::jsonb)
          from sint s
          left join public.perfiles pp on pp.id = s.objetivo_id
          left join public.perfiles pa on pa.id = s.antes
          left join public.perfiles pd on pd.id = s.despues),
        'derivas_sin_fecha_probable', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'perfil_id', d.objetivo_id,
                   'motivo', 'sin auditoria y sin evento del jefe anterior que acote la fecha')), '[]'::jsonb)
          from deriva d
          where d.cota is null
            and not exists (select 1 from aud_sin_evento a
                            where a.perfil_txt = d.objetivo_id::text and a.en > d.desde)),
        'operaciones_que_cambian_de_supervisor', (select coalesce(sum(c.ops), 0) from cambia c),
        'detalle_por_mes', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'mes', c.mes,
                   'mes_sellado', exists (select 1 from crm.periodos_cerrados pc where pc.periodo = c.mes),
                   'analista', pa.nombre_completo,
                   'de', p1.nombre_completo, 'a', p2.nombre_completo,
                   'moneda', c.moneda, 'operaciones', c.ops, 'capital', c.cap)
                 order by c.mes, pa.nombre_completo, c.moneda), '[]'::jsonb)
          from cambia c
          left join public.perfiles pa on pa.id = c.analista_id
          left join public.perfiles p1 on p1.id = c.sup_real
          left join public.perfiles p2 on p2.id = c.sup_hipo)
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R6_simulacion_relleno', v_tmp);

  perform set_config('medir.jerarquia', v_res::text, true);
end
$medir$;

select current_setting('medir.jerarquia', true)::jsonb as resultado;

rollback;
```

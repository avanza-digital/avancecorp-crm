ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 3: toca dos lectores SECURITY DEFINER de Citas y re-sella el censo analítico): REFUTA la migración «Citas: marca es_cliente por cita» (20261019170214)

Contexto. CRM de Avance Corp (Supabase/Postgres, esquema `crm` expuesto, `private` interno). El módulo Citas (Gerencia y Supervisión) lee un JSON mensual de `crm.citas_gerencia_consulta_fn(date,date)` (y `_v2_fn`, que delega en `private.citas_gerencia_consulta_corte(date,date,uuid)` cuando hay corte de capital valorado, o vuelve a `_fn` si no). Cada elemento de `citas[]` ya trae `vence_en`, `creado_en`, `estado_comercial`, `analista_id`, `supervisor_id`, `moneda`, `monto_estimado`, `origen` (origen del lead), `asistencia_registrada_en`, `cierre_posterior`. El total `citas_clientes` (citas con `tareas.perfil_id`) existe, pero NO hay marca por cita.

Decisión de Miguel (Gerencia, 19/10/2026): la pestaña nueva «Proyección» de Citas separa por analista Referidos · Clientes · Leads. «Clientes» = cita con una persona que YA ERA cliente cuando el analista generó la cita. Medido en producción: desde agosto hay 1 139 citas y NINGUNA cumple hoy esa condición (cada persona tiene un solo lead, `leads.inversionista_id` es único; las reinversiones de clientes van por el flujo «cliente existente» sin cita). Aun así pidió prepararlo («las dos: referidos y clientes»).

Tu trabajo: REFUTAR la migración. Busca (a) cómo el parche anclado podría instalar una lectura parcial, cambiar la verja por rol o romper el censo analítico; (b) fugas o privilegios de la auxiliar nueva `private.cita_con_cliente(uuid,timestamptz)`; (c) errores de SEMÁNTICA de «ya era cliente» (identidades fusionadas, cierres externos, anulaciones, el mismo instante, un lead convertido con citas posteriores, `perfil_id`); (d) coste; (e) reversión. No reescribas la migración: señala con archivo/línea y evidencia.

## Hechos verificados en producción (tú no tienes base ni red)
- `md5(prosrc)` vivos: `private.citas_gerencia_consulta(date,date)` = `d07e19d9731f3a7c6aef2a82f5745d58` (20 180 bytes); `private.citas_gerencia_consulta_corte(date,date,uuid)` = `89ef3e8cc067c344641f247e519007a6` (20 324 bytes). Ambos SECURITY DEFINER, owner postgres, `proconfig = {search_path=""}`, STABLE; verja: `if v_uid is null or v_rol not in ('gerencia','supervisor') then raise ...` y `v_visibles := array(select private.vendedor_ids_visibles(v_uid))`.
- El ancla `'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)` aparece EXACTAMENTE una vez en cada uno (posición 6375). Ninguno contiene `es_cliente`. El bloque donde vive (lector v1, migración 20260913225755, líneas 113-132):
```
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'lead_id',t.lead_id,'nombre',t.nombre_completo,'telefono',t.telefono,
    'analista_id',t.vendedor_id,'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,t.asignado_supervisor_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'vence_en',t.vence_en,'estado',t.estado,'estado_comercial',t.estado_comercial,'cancelada_por',t.cancelada_por,
    'modalidad',t.modalidad_canonica,'origen',t.origen,
    'moneda',t.moneda,'monto_estimado',t.monto_estimado,
    'resultado',t.resultado_canonico,
    'nota',coalesce(t.detalle_cierre_reunion,t.nota,''),
    'reagendada_de',anterior.id,
    'creado_en',t.creado_en,
    'manual_propio',coalesce(t.alta_manual and t.lead_creado_por=t.vendedor_id,false),
    'registro_manual',coalesce(t.alta_manual,false),
    'asistencia_registrada_en',case when t.estado='completada' then a.creado_en end,
    'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)
  ) order by t.vence_en,t.id),'[]'::jsonb) into v_filas
  from historial t
  left join historial anterior on anterior.id=t.reagendada_de and anterior.lead_id=t.lead_id
  left join cierres c on c.lead_id=t.lead_id
```
  `historial` es `select t.*, l.nombre_completo, ... from ... join crm.tareas t on t.id=e.tarea_id join crm.leads l on l.id=e.lead_id` (así que `t.perfil_id`, `t.lead_id` y `t.creado_en` existen en `t`). Las citas sin lead NO entran en `historial` (sigue igual).
- `crm.tareas.perfil_id uuid null` (tareas de perfil/postventa: hoy 4 llamadas y 1 whatsapp con perfil, 0 reuniones). `crm.leads.inversionista_id uuid` con índice único parcial `where inversionista_id is not null` (comentario: «enlace vivo lead->persona (nullable en captación; obligatorio al convertir)»). `crm.inversionista_leads(id, inversionista_id, lead_id único, rol='canonico', desde, hasta, creado_en, creado_por)` con índice en `inversionista_id`. `crm.inversionistas(id, estado, perfil_id, ..., inversionista_canonico_id, fusionado_en, ...)` con índice `inversionistas_canonico_idx(inversionista_canonico_id)`. `crm.cierres_externos(id, lead_id, ..., creado_en, anulado_en, ..., inversionista_id, es_cierre_inicial, ...)` con índice en `inversionista_id`.
- `private.inversionista_canonica(p_id uuid)`: sube por `inversionista_canonico_id` hasta 16 niveles y devuelve la raíz (o `p_id`). `private.cierre_anulado(p_lead_id uuid)`: true si el cierre inicial externo del lead está anulado, o hay anulación en `crm.cierres_avance_anulados` no rehabilitada, o inversión eliminada con conversión anulada no recuperada.
- Censo analítico (`private.assert_analitica_leads_citas()`): exige que todo «contador crudo» (`private.contadores_crudos_leads_citas()`, regla no transcrita) esté declarado en `private.analitica_leads_citas_exenciones(objeto, tipo, huella, razon, declarado_en, clase)` con huella vigente; que todo llamador de `citas_episodios`/`conversion_cierres` esté declarado; que `analitica_lc_sello.sello = private.huella_exenciones_analitica_lc()` donde esa huella es `md5(string_agg(concat_ws('|', objeto, huella, coalesce(clase,'(sin clase)'), razon), chr(10) order by objeto))`. La huella de cada objeto se calcula como `md5(regexp_replace(regexp_replace(lower(prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))` (así lo hace 20260927172931). Los dos lectores están declarados con clase `analitica`.
- Prueba en producción, SOLO LECTURA, con la misma lógica de la auxiliar en línea sobre las 608 citas generadas en octubre de 2026: `con_cliente = 0`, `con_perfil = 0`, `referidos = 13`, `citas de leads que ya tienen persona (convertidos después) = 70`; `EXPLAIN ANALYZE` 151 ms en total (la recursión `miembros` se evalúa 70 veces, el resto son index scans).
- Receta copiada (20260927172931): lock de `exenciones` y `sello` en share row exclusive; preflight con md5 del prosrc; reemplazo anclado con conteo exacto; `update exenciones set huella = ...`; `update analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id`; postflight de atributos, huella y sello.
- El front (Valibot `v.object`, ignora claves desconocidas) aceptará `es_cliente` como OPCIONAL y, mientras falte, usa un respaldo (lead convertido antes de la cita).

## Preguntas concretas
1. ¿Puede el `do $parche$` dejar producción a medias (p. ej. v1 parcheado y `_corte` no) o alterar algo más que la clave añadida? ¿El `execute` de `pg_get_functiondef` conserva owner, SECURITY DEFINER, `search_path` y ACL en Postgres 15/17?
2. `private.cita_con_cliente` es SECURITY INVOKER con `search_path=''` y EXECUTE solo para postgres. Llamada desde un DEFINER (postgres) ¿funciona? ¿Hay alguna vía por la que `authenticated` la ejecute o lea PII a través de ella?
3. Semántica de «ya era cliente»: ¿qué caso real queda mal clasificado? Piensa en: lead convertido y con citas posteriores (hoy 70 citas de leads con persona: ¿se marcan? ¿deberían?), persona fusionada (`inversionista_canonico_id`), cierre externo anulado o reactivado, conversión anulada y luego recuperada, `convertido_en` igual a `creado_en`, lead con `perfil_id` pero sin persona.
4. Censo: ¿la auxiliar (usa `exists` sobre `crm.leads` y `crm.cierres_externos`, sin `count(`, sin `citas_episodios`/`conversion_cierres`) puede caer en `contadores_crudos_leads_citas()` y hacer fallar el `assert` del postflight? Si cayera, ¿cómo se declara correctamente (clase)?
5. ¿Basta actualizar `huella` sin tocar `razon`/`declarado_en`? ¿Algo en el sello o en el trigger `trg_analitica_lc_clase_solo_aprieta` lo rechaza?
6. Coste y bloqueo: `lock_timeout 5s`, `statement_timeout 90s`, lock en share row exclusive de las dos tablas de censo. ¿Riesgo para lecturas concurrentes de Citas durante el merge?
7. Reversión: ¿la nota de cabecera basta? ¿Qué faltaría para revertir sin dejar el sello roto?
8. ¿Qué prueba falta antes de instalar (rama Supabase sin datos; banco Docker con esquema de producción disponible)?

## Archivos (transcritos íntegros)

### supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql
```sql
-- Proyección de citas (19/10/2026), Fase 0: cada cita dice si la persona YA ERA
-- CLIENTE cuando el analista la generó. Hasta hoy el lector de Citas sólo
-- entregaba el total `citas_clientes`; la pestaña «Proyección» separa por
-- analista Referidos · Clientes · Leads y necesita la marca por cita.
-- Plan en el vault: «Citas - proyeccion semanal y diaria por analista, plan
-- (2026-10-19)», Fase 0 (decisión de Miguel, 19/10: «las dos: referidos y clientes»).
--
-- Qué cambia: se añade la clave `es_cliente` a cada elemento de `citas[]` en los
-- dos lectores privados de Citas (v1 y el de cortes valorados), por reemplazo
-- anclado único sobre la definición viva, como en 20260927172931. No cambia el
-- alcance por rol, la población, el capital ni la forma pública de las puertas.
--
-- Cómo se revierte: reinstalar las dos definiciones anteriores (huellas
-- md5(prosrc) d07e19d9731f3a7c6aef2a82f5745d58 y 89ef3e8cc067c344641f247e519007a6)
-- con el mismo reemplazo anclado a la inversa, re-sellar el censo analítico y
-- `drop function private.cita_con_cliente(uuid,timestamptz)`.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

do $preflight$
begin
  if pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure))
     is distinct from 'd07e19d9731f3a7c6aef2a82f5745d58' then
    raise exception 'PREFLIGHT es_cliente: el lector v1 de Citas cambió; conciliar antes de aplicar';
  end if;
  if pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta_corte(date,date,uuid)'::regprocedure))
     is distinct from '89ef3e8cc067c344641f247e519007a6' then
    raise exception 'PREFLIGHT es_cliente: el lector de cortes de Citas cambió; conciliar antes de aplicar';
  end if;
  if pg_catalog.to_regprocedure('private.cita_con_cliente(uuid,timestamptz)') is not null then
    raise exception 'PREFLIGHT es_cliente: la función auxiliar ya existe';
  end if;
  perform private.assert_analitica_leads_citas();
end;
$preflight$;

-- La persona ya era cliente antes de `p_antes` si ella, o cualquier registro de
-- identidad fusionado con ella, tenía una conversión vigente o un cierre externo
-- no anulado antes de ese instante. Un lead sin persona enlazada devuelve false
-- sin leer nada más. SECURITY INVOKER a propósito: sólo la ejecuta postgres desde
-- los lectores DEFINER de Citas; nadie más tiene EXECUTE.
create function private.cita_con_cliente(p_lead uuid, p_antes timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $function$
  with recursive persona as (
    select distinct private.inversionista_canonica(x.inversionista_id) as id
    from (
      select l.inversionista_id from crm.leads l
       where l.id = p_lead and l.inversionista_id is not null
      union
      select il.inversionista_id from crm.inversionista_leads il
       where il.lead_id = p_lead
    ) x
  ), miembros as (
    select p.id, 1 as n from persona p
    union all
    select i.id, m.n + 1
    from crm.inversionistas i join miembros m on i.inversionista_canonico_id = m.id
    where m.n < 16
  ), leads_persona as (
    select p_lead as id
    union
    select l.id from crm.leads l where l.inversionista_id in (select id from miembros)
    union
    select il.lead_id from crm.inversionista_leads il where il.inversionista_id in (select id from miembros)
  )
  select exists (
    select 1 from crm.leads o
    where o.id in (select id from leads_persona)
      and o.etapa = 'convertido' and o.convertido_en < p_antes
      and not private.cierre_anulado(o.id)
  ) or exists (
    select 1 from crm.cierres_externos ce
    where ce.anulado_en is null and ce.creado_en < p_antes
      and (ce.lead_id in (select id from leads_persona)
           or ce.inversionista_id in (select id from miembros))
  );
$function$;
alter function private.cita_con_cliente(uuid,timestamptz) owner to postgres;
revoke all on function private.cita_con_cliente(uuid,timestamptz) from public, anon, authenticated, service_role;
comment on function private.cita_con_cliente(uuid,timestamptz) is
  'Citas: true si la persona del lead ya era cliente (conversión vigente o cierre externo no anulado, propio o de una identidad fusionada) antes del instante dado. Auxiliar de los lectores de Citas; sólo postgres.';

-- Reemplazo anclado único en los dos lectores. Si el ancla no aparece
-- exactamente una vez, no se instala nada.
do $parche$
declare
  v_objetos text[] := array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'];
  v_ancla text := $a$'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)$a$;
  v_nuevo text := $n$'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false),
    'es_cliente',t.perfil_id is not null or private.cita_con_cliente(t.lead_id,t.creado_en)$n$;
  v_objeto text;
  v_def text;
  v_veces integer;
begin
  foreach v_objeto in array v_objetos loop
    v_def := pg_catalog.pg_get_functiondef(v_objeto::regprocedure);
    v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_veces is distinct from 1 then
      raise exception 'es_cliente: el ancla aparece % veces en % (se esperaba 1)', v_veces, v_objeto;
    end if;
    if strpos(v_def, 'es_cliente') > 0 then
      raise exception 'es_cliente: % ya contiene la clave', v_objeto;
    end if;
    execute replace(v_def, v_ancla, v_nuevo);
  end loop;
end;
$parche$;

-- Los dos lectores siguen declarados con su razón y su clase; sólo cambia la
-- huella del cuerpo, y el sello de la lista se vuelve a calcular.
update private.analitica_leads_citas_exenciones e
set huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
from pg_catalog.pg_proc p
where e.objeto in ('private.citas_gerencia_consulta(date,date)',
                   'private.citas_gerencia_consulta_corte(date,date,uuid)')
  and p.oid = e.objeto::regprocedure;

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
declare
  v_objeto text;
  v_fn record;
  v_veces integer;
begin
  foreach v_objeto in array array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'] loop
    select p.prosecdef, p.provolatile, p.proconfig, r.rolname, p.prosrc
      into v_fn
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = v_objeto::regprocedure;
    if v_fn.rolname is distinct from 'postgres' or not v_fn.prosecdef
       or v_fn.provolatile is distinct from 's'
       or v_fn.proconfig is distinct from array['search_path=""']::text[] then
      raise exception 'POSTFLIGHT es_cliente: atributos inesperados en %', v_objeto;
    end if;
    v_veces := (length(v_fn.prosrc) - length(replace(v_fn.prosrc, '''es_cliente'',t.perfil_id is not null or private.cita_con_cliente(t.lead_id,t.creado_en)', '')))
      / length('''es_cliente'',t.perfil_id is not null or private.cita_con_cliente(t.lead_id,t.creado_en)');
    if v_veces is distinct from 1 then
      raise exception 'POSTFLIGHT es_cliente: % no quedó con la clave exactamente una vez', v_objeto;
    end if;
    if strpos(v_fn.prosrc, 'v_rol not in (''gerencia'',''supervisor'')') = 0
       or strpos(v_fn.prosrc, 'private.vendedor_ids_visibles(v_uid)') = 0 then
      raise exception 'POSTFLIGHT es_cliente: la verja por rol de % no está intacta', v_objeto;
    end if;
    if not exists (
      select 1
      from private.analitica_leads_citas_exenciones e
      join pg_catalog.pg_proc p on p.oid = v_objeto::regprocedure
      where e.objeto = v_objeto
        and e.huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
          pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    ) then
      raise exception 'POSTFLIGHT es_cliente: % no quedó declarado con su huella instalada', v_objeto;
    end if;
  end loop;
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname, p.prosrc
    into v_fn
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'private.cita_con_cliente(uuid,timestamptz)'::regprocedure;
  if v_fn.rolname is distinct from 'postgres' or v_fn.prosecdef
     or v_fn.provolatile is distinct from 's'
     or v_fn.proconfig is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT es_cliente: atributos inesperados en la auxiliar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid = 'private.cita_con_cliente(uuid,timestamptz)'::regprocedure
      and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'POSTFLIGHT es_cliente: la auxiliar tiene EXECUTE fuera de postgres';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_fn(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_v2_fn(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT es_cliente: anon no debe ejecutar las puertas de Citas';
  end if;
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT es_cliente: el sello analítico no coincide';
  end if;
  perform private.assert_analitica_leads_citas();
end;
$postflight$;
commit;
```

## Protocolo de revisión (global)

# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.


## Formato de respuesta
VERDICT (APPROVE / CHANGES_REQUESTED / REJECT) · SUMMARY · FINDINGS P0–P3 (archivo:línea, evidencia, hipótesis separadas) · RISKS / TEST GAPS · NEXT ACTIONS · CONFIDENCE. Responde en español.

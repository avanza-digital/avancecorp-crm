ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

Responde en español. Tu trabajo es intentar REFUTAR que esta migración y su pantalla son seguras y exactas. No tienes
base de datos ni red: todo lo que necesitas está transcrito abajo.

# Protocolo global
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

# Verificación global
# Verification Gate global

**A task must not be considered complete merely because the code was written.**

El PRIMARY identifica el stack y los comandos reales de cada proyecto antes de
modificar archivos. Lee instrucciones, manifests, lockfiles, scripts, CI y
configuración de tests/lint/build. Usa la navegación requerida por el proyecto.

Orden: cambio → validación estática relevante → tests relevantes → build cuando
aplique → review según riesgo → correcciones → verificación final → entrega.

- Si existe `.ai/VERIFICATION.md`, usar sus comandos concretos. Respetar gates de
  AGENTS.md, CLAUDE.md, CONTRIBUTING.md y CI. No copiar comandos de otro proyecto.
- Node: usar el gestor del lockfile y los scripts definidos en package.json.
- Python, Rust, Go, Java, .NET, Swift u otros: usar los comandos documentados
  por el repo; no suponer que existen pytest, cargo, Maven o Xcode por el nombre.
- Migraciones, contratos API, autorización y datos: añadir las validaciones
  de dominio y entorno aislado que correspondan; no usar producción como banco.
- Documentación/configuración: validar el formato, rutas y comandos; para
  scripts, sintaxis y casos de comportamiento relevantes.
- No instalar dependencias, crear CI, cambiar ramas o desplegar solo por cargar
  esta configuración. Esas acciones dependen de la tarea autorizada.
- Reportar PASS, FAIL y NOT RUN con motivo. No afirmar pruebas no ejecutadas.
- La revisión no sustituye checks y no da autoridad de cierre al reviewer.
- En tareas con dos PRIMARY simultáneos usar working trees separados. Nunca
  crear uno automáticamente ni confundir dos ramas con aislamiento de carpetas.

Para verificar la instalación global en esta Mac:

```bash
node --test ~/.config/ai-collaboration/global.test.mjs
~/.local/bin/claude-review --help
~/.local/bin/codex-review-mcp --check
```

Validar JSON global y ejecutar `bash -n` individualmente para cada wrapper/hook.
Tras cambiar flags/versiones, comprobar handshake MCP y una revisión real con
evidencia saneada. `--check` verifica MCP efectivos y flags; `--strict-config` se
aplica al lanzamiento del servidor, porque Codex 0.153.4 no lo admite en `mcp list`.

Esta instalación no agrega workflows a futuros repositorios. El PRIMARY utiliza
los gates existentes y propone CI adecuado solo si la tarea lo necesita.

# Reglas del proyecto que aplican (CLAUDE.md, resumidas)

- Funciones: `security definer` solo justificado, con `set search_path = ''`, nombres calificados y verificación de rol
  dentro. Toda función lleva `COMMENT ON`. Una migración por cambio lógico; cada migración dice cómo revertirse.
- Nunca editar una migración ya commiteada. Ninguna migración del CRM toca objetos de `public` sin OK de Miguel (esta
  solo LEE `public.contratos` y `public.perfiles`, como ya hacía la función).
- Producción la aplica Miguel; antes, ensayo en producción que acaba siempre en error y lo deshace todo.
- La pantalla no habla con tablas; los tipos del backend no se escriben a mano (aquí la RPC devuelve `jsonb` y el
  front la valida con un esquema valibot).

# La tarea (PRIMARY: Claude) — Facturación fase 6, decisión de Miguel del 10/10/2026

En la ficha del inversionista, cada inversión muestra «Analista de la operación» = `analista_origen_nombre`. Ese dato es
la ATRIBUCIÓN efectiva («a quién cuenta»): cadena de upgrade y, desde el 09/10, la regla de baja (si el analista dejó el
equipo, cuenta para quien heredó al cliente). En producción (10/10, solo lectura) eso no es quien vendió en 46 de 820
inversiones, todas de 2 analistas dados de baja.

Miguel eligió «los dos nombres»: «Analista de la operación» = quien VENDIÓ y, debajo, «Cuenta para» = a quién cuenta,
solo cuando son personas distintas. No cambia ninguna cifra.

Quién vendió: `public.contratos.analista_cierre_id` (Avance) o `crm.cierres_externos.vendedor_id` (cooperativa). Son
los mismos campos de partida que usa la atribución (`private.cartera_f5_fuentes`) antes de aplicar cadena y baja.

Hechos de producción medidos hoy (solo lectura):
- `crm.inversionista_ficha_fn(uuid,integer,integer)`: SECURITY DEFINER, dueño postgres, ACL
  `{postgres=X/postgres,authenticated=X/postgres}`, md5(pg_get_functiondef) `d0c6543bc7226e027fb8364f137fd02a`,
  sin comentario. Ninguna otra función la llama (pg_proc).
- El banco Docker tiene la misma huella de la ficha y de `private.cartera_f5_fuentes`.
- Orden de despliegue: servidor primero (el front viejo ignora claves nuevas: `v.object` de valibot las quita), luego
  el front, que tolera el servidor viejo (claves opcionales → una sola línea, como antes).

Archivos (worktree aislado, rama `crm/ficha-analista-venta` desde `avancecorp/main` 82e5edde):
- `supabase/migrations/20261010203951_crm_ficha_analista_venta.sql` (generada)
- `supabase/scripts/ficha-analista-venta/`: `generar.py` (cuerpo nuevo = vivo + 2 fragmentos; escribe migración,
  reversa, ensayo y registro; `--verificar`), `vivo/` (cuerpo de producción al byte), `banco-prueba.py`.
- Front: `app/src/lib/inversionistas.ts`, `app/src/components/app/inversionista-ficha.tsx`, prueba en
  `app/src/screens/cartera-inversionistas.test.tsx`.

## Cuerpo VIVO de producción (vivo/crm.inversionista_ficha_fn.sql, md5 d0c6543b…)

```sql
CREATE OR REPLACE FUNCTION crm.inversionista_ficha_fn(p_inversionista uuid, p_pagina_inversiones integer DEFAULT 1, p_pagina_historial integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
    end;
  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
    exception when sqlstate 'P0409' or sqlstate 'P0429' then v_motivo:=sqlerrm;
      when lock_not_available or deadlock_detected then
        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en,null::text empresa
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
        and not (v_postventa and exists(select 1 from crm.inversionista_gestiones g
          where g.id::text=a.metadata->>'postventa_gestion_id'
            and private.inversionista_canonica(g.inversionista_id)=v_id))
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en,'avance'::text empresa
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
    union all
    select g.id,'postventa',g.tipo,g.detalle,g.creado_en,g.empresa
      from crm.inversionista_gestiones g where v_postventa
        and private.inversionista_canonica(g.inversionista_id)=v_id
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado,t.inversionista_id,t.postventa_revision
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids))
      or (v_postventa and private.inversionista_canonica(t.inversionista_id)=v_id))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      'condiciones_coopac',case when f.empresa<>'avance' then (select
        jsonb_build_object('plazo_meses',ce.plazo_meses,'tasa_anual',ce.tasa_anual)
        from crm.cierres_externos ce where ce.id=f.fuente_id
          and ce.plazo_meses is not null and ce.tasa_anual is not null) end,
      'contrato',case when f.empresa='avance' then (select jsonb_build_object(
        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
        ||case when private.contrato_pdf_archivo_base(f.fuente_id) is not null then
          jsonb_build_array(jsonb_build_object('id',f.fuente_id,'nombre','Contrato vigente','tipo','contrato_pdf'))
          else '[]'::jsonb end
        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
      'proxima_cuota',case when f.empresa='avance' then (
        select jsonb_build_object('fecha',c.fecha_programada,'moneda',f.moneda,
          'monto',c.monto_programado,'estado',c.estado,'tipo',c.tipo)
        from public.cronograma_pagos c where c.contrato_id=f.fuente_id and c.estado='pendiente'
        order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
      'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
        (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f),'[]'),
    'continuidad',jsonb_build_object('proximo_vencimiento',(
      select coalesce(max(f.vence_en) filter(where f.vence_en<=(now() at time zone 'America/Lima')::date),
        min(f.vence_en) filter(where f.vence_en>(now() at time zone 'America/Lima')::date))
      from fuentes f where f.estado in ('activo','vigente','vencido') and isfinite(f.vence_en))),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id,h.origen) from (
      select * from historial order by creado_en desc,id,origen limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles(v_id) p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$function$
```

## Diff del cuerpo: vivo → nuevo (solo dos inserciones)

```diff
--- supabase/scripts/ficha-analista-venta/vivo/crm.inversionista_ficha_fn.sql	2026-10-10 15:39:51
+++ /dev/fd/12	2026-10-10 19:04:55
@@ -73,6 +73,10 @@
       'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
     'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
       'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
+      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la
+      -- cooperativa), aparte de a quién CUENTA hoy (analista_origen_*: cadena de upgrade y baja).
+      'analista_venta_id',av.analista_id,
+      'analista_venta_nombre',(select nombre_completo from public.perfiles where id=av.analista_id),
       'condiciones_coopac',case when f.empresa<>'avance' then (select
         jsonb_build_object('plazo_meses',ce.plazo_meses,'tasa_anual',ce.tasa_anual)
         from crm.cierres_externos ce where ce.id=f.fuente_id
@@ -105,7 +109,10 @@
         order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
       'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
         (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
-      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f),'[]'),
+      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f
+      cross join lateral (select case when f.empresa='avance'
+        then (select c.analista_cierre_id from public.contratos c where c.id=f.fuente_id)
+        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id=f.fuente_id) end as analista_id) av),'[]'),
     'continuidad',jsonb_build_object('proximo_vencimiento',(
       select coalesce(max(f.vence_en) filter(where f.vence_en<=(now() at time zone 'America/Lima')::date),
         min(f.vence_en) filter(where f.vence_en>(now() at time zone 'America/Lima')::date))
```

## Migración completa (20261010203951_crm_ficha_analista_venta.sql)

```sql
-- Facturación fase 6 (Miguel, 10/10/2026, «los dos nombres»): la ficha del inversionista distingue quién VENDIÓ cada
-- inversión de a quién CUENTA hoy.
--
-- Hoy «Analista de la operación» enseña analista_origen_nombre, que es la atribución efectiva: cadena de upgrade y, tras
-- una baja, quien heredó al cliente (20261009200000). En producción (10/10, solo lectura) no es quien vendió en 46 de
-- 820 inversiones, todas de 2 analistas dados de baja.
--
-- Cambio: crm.inversionista_ficha_fn añade a cada inversión analista_venta_id y analista_venta_nombre: el analista de
-- cierre del contrato (public.contratos.analista_cierre_id) o el vendedor de la cooperativa
-- (crm.cierres_externos.vendedor_id). La pantalla enseña los dos nombres solo cuando son personas distintas.
-- El cuerpo nuevo es el vivo (huella d0c6543bc7226e027fb8364f137fd02a) con DOS fragmentos insertados y nada más; esta migración lo
-- comprueba por texto. Sin cambios de firma, permisos, cifras ni filas visibles: los dos datos salen de la misma fila
-- que ya se ve. La función no tenía comentario; se añade.
--
-- Reversa: supabase/scripts/ficha-analista-venta/reversa.sql (cuerpo anterior al byte y sin comentario).
-- Kit, banco y ensayo: supabase/scripts/ficha-analista-venta/ (LEEME.md). Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $migracion$
declare
  v_firma constant regprocedure := 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure;
  v_antes text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into v_antes, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
  -- Ya aplicada (cuerpo y comentario): repetir no hace nada.
  if md5(v_antes) = '9d981c6ca6eb214a318678e85bd851d6' and v_comentario = 'Ficha de un inversionista (cartera multiempresa F5): persona, capacidades, inversiones paginadas de 25 en 25, continuidad, totales por empresa y moneda, historial y tareas. En cada inversión, analista_origen_* es a quién CUENTA hoy (cadena de upgrade y, tras una baja, quien heredó al cliente) y analista_venta_* quién la VENDIÓ (analista de cierre del contrato o vendedor de la cooperativa). Fase 6 de Facturación, 10/10/2026.' then
    raise notice 'Ficha con analista de venta: ya aplicada';
    return;
  end if;
  if md5(v_antes) is distinct from 'd0c6543bc7226e027fb8364f137fd02a' then
    raise exception 'PREFLIGHT: crm.inversionista_ficha_fn no es la medida (huella %); volver a generar el kit', md5(v_antes);
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'PREFLIGHT: permisos, dueño o modo de la ficha distintos de los medidos (%, %, %)',
      v_acl, v_dueno, v_definer;
  end if;
  if v_comentario is not null then
    raise exception 'PREFLIGHT: la ficha ya tiene comentario; revisar a mano';
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION crm.inversionista_ficha_fn(p_inversionista uuid, p_pagina_inversiones integer DEFAULT 1, p_pagina_historial integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
    end;
  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
    exception when sqlstate 'P0409' or sqlstate 'P0429' then v_motivo:=sqlerrm;
      when lock_not_available or deadlock_detected then
        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en,null::text empresa
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
        and not (v_postventa and exists(select 1 from crm.inversionista_gestiones g
          where g.id::text=a.metadata->>'postventa_gestion_id'
            and private.inversionista_canonica(g.inversionista_id)=v_id))
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en,'avance'::text empresa
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
    union all
    select g.id,'postventa',g.tipo,g.detalle,g.creado_en,g.empresa
      from crm.inversionista_gestiones g where v_postventa
        and private.inversionista_canonica(g.inversionista_id)=v_id
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado,t.inversionista_id,t.postventa_revision
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids))
      or (v_postventa and private.inversionista_canonica(t.inversionista_id)=v_id))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la
      -- cooperativa), aparte de a quién CUENTA hoy (analista_origen_*: cadena de upgrade y baja).
      'analista_venta_id',av.analista_id,
      'analista_venta_nombre',(select nombre_completo from public.perfiles where id=av.analista_id),
      'condiciones_coopac',case when f.empresa<>'avance' then (select
        jsonb_build_object('plazo_meses',ce.plazo_meses,'tasa_anual',ce.tasa_anual)
        from crm.cierres_externos ce where ce.id=f.fuente_id
          and ce.plazo_meses is not null and ce.tasa_anual is not null) end,
      'contrato',case when f.empresa='avance' then (select jsonb_build_object(
        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
        ||case when private.contrato_pdf_archivo_base(f.fuente_id) is not null then
          jsonb_build_array(jsonb_build_object('id',f.fuente_id,'nombre','Contrato vigente','tipo','contrato_pdf'))
          else '[]'::jsonb end
        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
      'proxima_cuota',case when f.empresa='avance' then (
        select jsonb_build_object('fecha',c.fecha_programada,'moneda',f.moneda,
          'monto',c.monto_programado,'estado',c.estado,'tipo',c.tipo)
        from public.cronograma_pagos c where c.contrato_id=f.fuente_id and c.estado='pendiente'
        order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
      'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
        (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f
      cross join lateral (select case when f.empresa='avance'
        then (select c.analista_cierre_id from public.contratos c where c.id=f.fuente_id)
        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id=f.fuente_id) end as analista_id) av),'[]'),
    'continuidad',jsonb_build_object('proximo_vencimiento',(
      select coalesce(max(f.vence_en) filter(where f.vence_en<=(now() at time zone 'America/Lima')::date),
        min(f.vence_en) filter(where f.vence_en>(now() at time zone 'America/Lima')::date))
      from fuentes f where f.estado in ('activo','vigente','vencido') and isfinite(f.vence_en))),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id,h.origen) from (
      select * from historial order by creado_en desc,id,origen limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles(v_id) p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$function$
$def$;

  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into v_despues, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
  if md5(v_despues) is distinct from '9d981c6ca6eb214a318678e85bd851d6' then
    raise exception 'POSTFLIGHT: el cuerpo instalado no es el generado (huella %)', md5(v_despues);
  end if;
  -- Por texto: quitar los dos fragmentos devuelve el cuerpo anterior al byte.
  if (replace(replace(v_despues, $fragmento$      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la
      -- cooperativa), aparte de a quién CUENTA hoy (analista_origen_*: cadena de upgrade y baja).
      'analista_venta_id',av.analista_id,
      'analista_venta_nombre',(select nombre_completo from public.perfiles where id=av.analista_id),
$fragmento$, ''),
      $fragmento$
      cross join lateral (select case when f.empresa='avance'
        then (select c.analista_cierre_id from public.contratos c where c.id=f.fuente_id)
        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id=f.fuente_id) end as analista_id) av$fragmento$, '') = v_antes) is not true then
    raise exception 'POSTFLIGHT: el cuerpo nuevo cambia algo más que los dos fragmentos';
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'POSTFLIGHT: cambiaron los permisos, el dueño o el modo de la ficha';
  end if;

  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is 'Ficha de un inversionista (cartera multiempresa F5): persona, capacidades, inversiones paginadas de 25 en 25, continuidad, totales por empresa y moneda, historial y tareas. En cada inversión, analista_origen_* es a quién CUENTA hoy (cadena de upgrade y, tras una baja, quien heredó al cliente) y analista_venta_* quién la VENDIÓ (analista de cierre del contrato o vendedor de la cooperativa). Fase 6 de Facturación, 10/10/2026.';

  if current_setting('crm.ficha_analista_venta_ensayo', true) = 'on' then
    raise exception 'ENSAYO FICHA PASS: cuerpo % -> %, solo los dos fragmentos, permisos iguales, comentario puesto — SE DESHACE TODO',
      left(md5(v_antes), 8), left(md5(v_despues), 8);
  end if;
end
$migracion$;
commit;
```

## Reversa (reversa.sql)

```sql
-- REVERSA de 20261010203951_crm_ficha_analista_venta: vuelve a poner el cuerpo anterior de crm.inversionista_ficha_fn al byte
-- (huella d0c6543bc7226e027fb8364f137fd02a) y le quita el comentario. Idempotente; se niega ante un cuerpo desconocido. No toca
-- supabase_migrations (si hiciera falta, se desregistra a mano). La pantalla nueva tolera el cuerpo anterior: los dos
-- datos son opcionales y, sin ellos, la ficha enseña una sola línea como antes.
-- Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $reversa$
declare
  v_firma constant regprocedure := 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure;
  v_actual text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into v_actual, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
  if md5(v_actual) = 'd0c6543bc7226e027fb8364f137fd02a' and v_comentario is null then
    raise notice 'Reversa de la ficha: ya está el cuerpo anterior';
    return;
  end if;
  if md5(v_actual) is distinct from '9d981c6ca6eb214a318678e85bd851d6' then
    raise exception 'REVERSA: cuerpo desconocido de la ficha (huella %); revisar a mano', md5(v_actual);
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA: permisos, dueño o modo distintos de los esperados; revisar a mano';
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION crm.inversionista_ficha_fn(p_inversionista uuid, p_pagina_inversiones integer DEFAULT 1, p_pagina_historial integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
    end;
  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
    exception when sqlstate 'P0409' or sqlstate 'P0429' then v_motivo:=sqlerrm;
      when lock_not_available or deadlock_detected then
        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en,null::text empresa
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
        and not (v_postventa and exists(select 1 from crm.inversionista_gestiones g
          where g.id::text=a.metadata->>'postventa_gestion_id'
            and private.inversionista_canonica(g.inversionista_id)=v_id))
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en,'avance'::text empresa
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
    union all
    select g.id,'postventa',g.tipo,g.detalle,g.creado_en,g.empresa
      from crm.inversionista_gestiones g where v_postventa
        and private.inversionista_canonica(g.inversionista_id)=v_id
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado,t.inversionista_id,t.postventa_revision
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids))
      or (v_postventa and private.inversionista_canonica(t.inversionista_id)=v_id))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      'condiciones_coopac',case when f.empresa<>'avance' then (select
        jsonb_build_object('plazo_meses',ce.plazo_meses,'tasa_anual',ce.tasa_anual)
        from crm.cierres_externos ce where ce.id=f.fuente_id
          and ce.plazo_meses is not null and ce.tasa_anual is not null) end,
      'contrato',case when f.empresa='avance' then (select jsonb_build_object(
        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
        ||case when private.contrato_pdf_archivo_base(f.fuente_id) is not null then
          jsonb_build_array(jsonb_build_object('id',f.fuente_id,'nombre','Contrato vigente','tipo','contrato_pdf'))
          else '[]'::jsonb end
        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
      'proxima_cuota',case when f.empresa='avance' then (
        select jsonb_build_object('fecha',c.fecha_programada,'moneda',f.moneda,
          'monto',c.monto_programado,'estado',c.estado,'tipo',c.tipo)
        from public.cronograma_pagos c where c.contrato_id=f.fuente_id and c.estado='pendiente'
        order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
      'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
        (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f),'[]'),
    'continuidad',jsonb_build_object('proximo_vencimiento',(
      select coalesce(max(f.vence_en) filter(where f.vence_en<=(now() at time zone 'America/Lima')::date),
        min(f.vence_en) filter(where f.vence_en>(now() at time zone 'America/Lima')::date))
      from fuentes f where f.estado in ('activo','vigente','vencido') and isfinite(f.vence_en))),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id,h.origen) from (
      select * from historial order by creado_en desc,id,origen limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles(v_id) p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$function$
$def$;
  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is null;

  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into v_despues, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
  if md5(v_despues) is distinct from 'd0c6543bc7226e027fb8364f137fd02a' or v_comentario is not null
     or v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA POSTFLIGHT: el estado final no es el anterior; se deshace';
  end if;
  raise notice 'Reversa de la ficha hecha';
end
$reversa$;
commit;
```

## Registro (registrar.sql; el texto de la migración va embebido donde se indica)

```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20261010203951_crm_ficha_analista_venta.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si la ficha no tiene el cuerpo y el
-- comentario nuevos o si la versión ya está registrada con otro nombre u otro texto.
-- Generado por generar.py: md5 del texto de la migración c491579b0bacbfdc25ae047a18d4940a.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_ficha_analista_venta'));
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) = '9d981c6ca6eb214a318678e85bd851d6'
             and obj_description(p.oid, 'pg_proc') = 'Ficha de un inversionista (cartera multiempresa F5): persona, capacidades, inversiones paginadas de 25 en 25, continuidad, totales por empresa y moneda, historial y tareas. En cada inversión, analista_origen_* es a quién CUENTA hoy (cadena de upgrade y, tras una baja, quien heredó al cliente) y analista_venta_* quién la VENDIÓ (analista de cierre del contrato o vendedor de la cooperativa). Fase 6 de Facturación, 10/10/2026.'
      from pg_proc p where p.oid = 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure) is not true then
    raise exception 'REGISTRO: la ficha no tiene el cuerpo nuevo; aplica primero 20261010203951';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261010203951' and coalesce(name, '') <> 'crm_ficha_analista_venta') then
    raise exception 'REGISTRO: la versión 20261010203951 ya está registrada con otro nombre';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261010203951' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from 'c491579b0bacbfdc25ae047a18d4940a')) then
    raise exception 'REGISTRO: la versión 20261010203951 ya está registrada con OTRO texto; revisar a mano';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261010203951', 'crm_ficha_analista_venta', array[$migracion_20261010203951$<TEXTO EXACTO DE LA MIGRACIÓN, transcrito arriba>$migracion_20261010203951$])
on conflict (version) do nothing;
select version, name, md5(statements[1]) as md5_texto from supabase_migrations.schema_migrations where version = '20261010203951';
commit;
```

## Ensayo de producción: la migración con esta línea tras `statement_timeout` (generar.py comprueba que quitarla devuelve la migración al byte)

```sql
set local crm.ficha_analista_venta_ensayo = 'on';
```

## Generador (generar.py)

```python
#!/usr/bin/env python3
"""Fase 6 de Facturación: genera el cuerpo nuevo de crm.inversionista_ficha_fn a partir del VIVO de producción y
escribe la migración, la reversa, el ensayo de producción y el registro. --verificar no escribe."""
import argparse
import hashlib
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
VERSION, NOMBRE = '20261010203951', 'crm_ficha_analista_venta'
MIGRACION = CARPETA.parents[1] / 'migrations' / f'{VERSION}_{NOMBRE}.sql'
VIVO = CARPETA / 'vivo' / 'crm.inversionista_ficha_fn.sql'
REVERSA = CARPETA / 'reversa.sql'
ENSAYO = CARPETA / 'ensayo-produccion.sql'
REGISTRAR = CARPETA / 'registrar.sql'

FIRMA = 'crm.inversionista_ficha_fn(uuid,integer,integer)'
HUELLA_VIVA = 'd0c6543bc7226e027fb8364f137fd02a'  # md5(pg_get_functiondef) en producción, 10/10/2026
ACL = '{postgres=X/postgres,authenticated=X/postgres}'
COMENTARIO = (
    'Ficha de un inversionista (cartera multiempresa F5): persona, capacidades, inversiones paginadas de 25 en 25, '
    'continuidad, totales por empresa y moneda, historial y tareas. En cada inversión, analista_origen_* es a quién '
    'CUENTA hoy (cadena de upgrade y, tras una baja, quien heredó al cliente) y analista_venta_* quién la VENDIÓ '
    '(analista de cierre del contrato o vendedor de la cooperativa). Fase 6 de Facturación, 10/10/2026.'
)

# Los dos fragmentos que se INSERTAN en el cuerpo vivo. Nada más cambia.
ANCLA_CLAVES = "      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),\n"
CLAVES = (
    "      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la\n"
    "      -- cooperativa), aparte de a quién CUENTA hoy (analista_origen_*: cadena de upgrade y baja).\n"
    "      'analista_venta_id',av.analista_id,\n"
    "      'analista_venta_nombre',(select nombre_completo from public.perfiles where id=av.analista_id),\n"
)
ANCLA_LATERAL = "from pagina f),'[]'),\n"
LATERAL = (
    "\n      cross join lateral (select case when f.empresa='avance'"
    "\n        then (select c.analista_cierre_id from public.contratos c where c.id=f.fuente_id)"
    "\n        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id=f.fuente_id) end as analista_id) av"
)
LINEA_ENSAYO = "set local crm.ficha_analista_venta_ensayo = 'on';\n"
ANCLA_ENSAYO = "set local statement_timeout = '60s';\n"


def md5(texto):
    return hashlib.md5(texto.encode()).hexdigest()


def literal(texto):
    return "'" + texto.replace("'", "''") + "'"


def cuerpo_nuevo(vivo):
    assert md5(vivo) == HUELLA_VIVA, 'vivo/ no es el cuerpo medido en producción'
    assert vivo.count(ANCLA_CLAVES) == 1 and vivo.count(ANCLA_LATERAL) == 1, 'anclas ausentes o repetidas'
    assert CLAVES not in vivo and LATERAL not in vivo
    nuevo = vivo.replace(ANCLA_CLAVES, ANCLA_CLAVES + CLAVES).replace(
        ANCLA_LATERAL, ANCLA_LATERAL.replace('from pagina f', 'from pagina f' + LATERAL))
    assert nuevo.count(CLAVES) == 1 and nuevo.count(LATERAL) == 1
    # Quitar los dos fragmentos devuelve el vivo al byte (la migración repite esta prueba en SQL).
    assert nuevo.replace(CLAVES, '', 1).replace(LATERAL, '', 1) == vivo
    for etiqueta in ('$def$', '$fragmento$', '$migracion$', '$reversa$'):
        assert etiqueta not in nuevo and etiqueta not in CLAVES + LATERAL
    return nuevo


SELECT_ESTADO = """  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into @@DESTINO@@, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
"""

MIGRACION_PLANTILLA = """-- Facturación fase 6 (Miguel, 10/10/2026, «los dos nombres»): la ficha del inversionista distingue quién VENDIÓ cada
-- inversión de a quién CUENTA hoy.
--
-- Hoy «Analista de la operación» enseña analista_origen_nombre, que es la atribución efectiva: cadena de upgrade y, tras
-- una baja, quien heredó al cliente (20261009200000). En producción (10/10, solo lectura) no es quien vendió en 46 de
-- 820 inversiones, todas de 2 analistas dados de baja.
--
-- Cambio: crm.inversionista_ficha_fn añade a cada inversión analista_venta_id y analista_venta_nombre: el analista de
-- cierre del contrato (public.contratos.analista_cierre_id) o el vendedor de la cooperativa
-- (crm.cierres_externos.vendedor_id). La pantalla enseña los dos nombres solo cuando son personas distintas.
-- El cuerpo nuevo es el vivo (huella @@HUELLA_VIVA@@) con DOS fragmentos insertados y nada más; esta migración lo
-- comprueba por texto. Sin cambios de firma, permisos, cifras ni filas visibles: los dos datos salen de la misma fila
-- que ya se ve. La función no tenía comentario; se añade.
--
-- Reversa: supabase/scripts/ficha-analista-venta/reversa.sql (cuerpo anterior al byte y sin comentario).
-- Kit, banco y ensayo: supabase/scripts/ficha-analista-venta/ (LEEME.md). Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $migracion$
declare
  v_firma constant regprocedure := '@@FIRMA@@'::regprocedure;
  v_antes text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
@@SELECT_ANTES@@
  -- Ya aplicada (cuerpo y comentario): repetir no hace nada.
  if md5(v_antes) = '@@HUELLA_NUEVA@@' and v_comentario = @@COMENTARIO@@ then
    raise notice 'Ficha con analista de venta: ya aplicada';
    return;
  end if;
  if md5(v_antes) is distinct from '@@HUELLA_VIVA@@' then
    raise exception 'PREFLIGHT: crm.inversionista_ficha_fn no es la medida (huella %); volver a generar el kit', md5(v_antes);
  end if;
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'PREFLIGHT: permisos, dueño o modo de la ficha distintos de los medidos (%, %, %)',
      v_acl, v_dueno, v_definer;
  end if;
  if v_comentario is not null then
    raise exception 'PREFLIGHT: la ficha ya tiene comentario; revisar a mano';
  end if;

  execute $def$
@@NUEVO@@$def$;

@@SELECT_DESPUES@@
  if md5(v_despues) is distinct from '@@HUELLA_NUEVA@@' then
    raise exception 'POSTFLIGHT: el cuerpo instalado no es el generado (huella %)', md5(v_despues);
  end if;
  -- Por texto: quitar los dos fragmentos devuelve el cuerpo anterior al byte.
  if (replace(replace(v_despues, $fragmento$@@CLAVES@@$fragmento$, ''),
      $fragmento$@@LATERAL@@$fragmento$, '') = v_antes) is not true then
    raise exception 'POSTFLIGHT: el cuerpo nuevo cambia algo más que los dos fragmentos';
  end if;
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'POSTFLIGHT: cambiaron los permisos, el dueño o el modo de la ficha';
  end if;

  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is @@COMENTARIO@@;

  if current_setting('crm.ficha_analista_venta_ensayo', true) = 'on' then
    raise exception 'ENSAYO FICHA PASS: cuerpo % -> %, solo los dos fragmentos, permisos iguales, comentario puesto — SE DESHACE TODO',
      left(md5(v_antes), 8), left(md5(v_despues), 8);
  end if;
end
$migracion$;
commit;
"""

REVERSA_PLANTILLA = """-- REVERSA de @@VERSION@@_@@NOMBRE@@: vuelve a poner el cuerpo anterior de crm.inversionista_ficha_fn al byte
-- (huella @@HUELLA_VIVA@@) y le quita el comentario. Idempotente; se niega ante un cuerpo desconocido. No toca
-- supabase_migrations (si hiciera falta, se desregistra a mano). La pantalla nueva tolera el cuerpo anterior: los dos
-- datos son opcionales y, sin ellos, la ficha enseña una sola línea como antes.
-- Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $reversa$
declare
  v_firma constant regprocedure := '@@FIRMA@@'::regprocedure;
  v_actual text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
@@SELECT_ACTUAL@@
  if md5(v_actual) = '@@HUELLA_VIVA@@' and v_comentario is null then
    raise notice 'Reversa de la ficha: ya está el cuerpo anterior';
    return;
  end if;
  if md5(v_actual) is distinct from '@@HUELLA_NUEVA@@' then
    raise exception 'REVERSA: cuerpo desconocido de la ficha (huella %); revisar a mano', md5(v_actual);
  end if;
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA: permisos, dueño o modo distintos de los esperados; revisar a mano';
  end if;

  execute $def$
@@VIVO@@$def$;
  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is null;

@@SELECT_DESPUES@@
  if md5(v_despues) is distinct from '@@HUELLA_VIVA@@' or v_comentario is not null
     or v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA POSTFLIGHT: el estado final no es el anterior; se deshace';
  end if;
  raise notice 'Reversa de la ficha hecha';
end
$reversa$;
commit;
"""

REGISTRAR_PLANTILLA = """-- REGISTRO en supabase_migrations.schema_migrations de @@VERSION@@_@@NOMBRE@@.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si la ficha no tiene el cuerpo y el
-- comentario nuevos o si la versión ya está registrada con otro nombre u otro texto.
-- Generado por generar.py: md5 del texto de la migración @@MD5_TEXTO@@.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('@@NOMBRE@@'));
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) = '@@HUELLA_NUEVA@@'
             and obj_description(p.oid, 'pg_proc') = @@COMENTARIO@@
      from pg_proc p where p.oid = '@@FIRMA@@'::regprocedure) is not true then
    raise exception 'REGISTRO: la ficha no tiene el cuerpo nuevo; aplica primero @@VERSION@@';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '@@VERSION@@' and coalesce(name, '') <> '@@NOMBRE@@') then
    raise exception 'REGISTRO: la versión @@VERSION@@ ya está registrada con otro nombre';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '@@VERSION@@' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from '@@MD5_TEXTO@@')) then
    raise exception 'REGISTRO: la versión @@VERSION@@ ya está registrada con OTRO texto; revisar a mano';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('@@VERSION@@', '@@NOMBRE@@', array[$migracion_@@VERSION@@$@@TEXTO@@$migracion_@@VERSION@@$])
on conflict (version) do nothing;
select version, name, md5(statements[1]) as md5_texto from supabase_migrations.schema_migrations where version = '@@VERSION@@';
commit;
"""

CABECERA_ENSAYO = (
    f'-- ENSAYO DE PRODUCCIÓN de {VERSION}_{NOMBRE}: la migración entera, que acaba SIEMPRE en error y lo deshace todo.\n'
    '-- Resultado correcto: «ENSAYO FICHA PASS: … — SE DESHACE TODO». Cualquier otro error es un fallo.\n'
    '-- Generado por generar.py (no editar a mano).\n'
)


def rellenar(plantilla, valores):
    for clave, valor in valores.items():
        plantilla = plantilla.replace(f'@@{clave}@@', valor)
    assert '@@' not in plantilla, 'marcador sin rellenar'
    return plantilla


def generar():
    vivo = VIVO.read_text()
    nuevo = cuerpo_nuevo(vivo)
    comunes = {'VERSION': VERSION, 'NOMBRE': NOMBRE, 'FIRMA': FIRMA, 'ACL': ACL, 'HUELLA_VIVA': HUELLA_VIVA,
               'HUELLA_NUEVA': md5(nuevo), 'COMENTARIO': literal(COMENTARIO)}
    migracion = rellenar(MIGRACION_PLANTILLA, {
        **comunes, 'NUEVO': nuevo, 'CLAVES': CLAVES, 'LATERAL': LATERAL,
        'SELECT_ANTES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_antes').rstrip('\n'),
        'SELECT_DESPUES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_despues').rstrip('\n')})
    reversa = rellenar(REVERSA_PLANTILLA, {
        **comunes, 'VIVO': vivo,
        'SELECT_ACTUAL': SELECT_ESTADO.replace('@@DESTINO@@', 'v_actual').rstrip('\n'),
        'SELECT_DESPUES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_despues').rstrip('\n')})
    assert migracion.count(ANCLA_ENSAYO) == 1 and LINEA_ENSAYO not in migracion
    ensayo = CABECERA_ENSAYO + migracion.replace(ANCLA_ENSAYO, ANCLA_ENSAYO + LINEA_ENSAYO)
    # Quitar lo añadido devuelve la migración al byte: el ensayo prueba exactamente lo que se aplicará.
    assert ensayo[len(CABECERA_ENSAYO):].replace(LINEA_ENSAYO, '', 1) == migracion
    etiqueta = f'$migracion_{VERSION}$'
    assert etiqueta not in migracion
    registrar = rellenar(REGISTRAR_PLANTILLA, {**comunes, 'MD5_TEXTO': md5(migracion), 'TEXTO': migracion})
    return {MIGRACION: migracion, REVERSA: reversa, ENSAYO: ensayo, REGISTRAR: registrar}, md5(nuevo)


def principal():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verificar', action='store_true')
    args = parser.parse_args()
    salidas, huella_nueva = generar()
    if args.verificar:
        malos = [p.name for p, contenido in salidas.items() if not p.exists() or p.read_text() != contenido]
        if malos:
            raise SystemExit(f'FAIL: desactualizados {malos}; correr generar.py')
        print(f'PASS: migración, reversa, ensayo y registro al día (cuerpo nuevo {huella_nueva}, '
              f'texto {md5(salidas[MIGRACION])})')
        return
    for ruta, contenido in salidas.items():
        ruta.write_text(contenido)
    print(f'escritos {[p.name for p in salidas]} (cuerpo nuevo {huella_nueva})')


if __name__ == '__main__':
    principal()
```

## Banco (banco-prueba.py)

```python
#!/usr/bin/env python3
"""Banco de la fase 6 (ficha del inversionista con analista de venta) contra el banco Docker con el esquema de
producción. Deja el banco como estaba (cuerpo vivo, sin comentario). Las fichas se piden como usuarios reales del banco
(gerencia, supervisores, vendedores, Directorio) en transacciones que se deshacen.

La cartera multiempresa del banco está apagada (bandera y conciliación de datos sintéticos): en cada foto se sustituye
crm.cartera_inversionistas_estado_fn por un doble que la da por habilitada, igual en la foto de antes y en la de después,
así que la comparación sigue siendo exacta."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
sys.path.insert(0, str(CARPETA))
import generar as G  # noqa: E402

CLAVES_NUEVAS = ('analista_venta_id', 'analista_venta_nombre')
CONTENEDOR = 'supabase_db_avancecorp-fact0c-20261009'
RESULTADOS = []

DOBLE = """
create or replace function crm.cartera_inversionistas_estado_fn() returns jsonb language sql as
$doble$ select jsonb_build_object('version',1,'habilitada',true,'escritura_habilitada',false,'motivo',null) $doble$;
create schema banco_ficha;
create function banco_ficha.ficha_segura(p uuid) returns jsonb language plpgsql as $segura$
begin
  return coalesce(crm.inversionista_ficha_fn(p), 'null'::jsonb);
exception when others then
  return jsonb_build_object('error', sqlstate, 'mensaje', sqlerrm);
end $segura$;
grant usage on schema banco_ficha to authenticated;
grant execute on function banco_ficha.ficha_segura(uuid) to authenticated;
"""


def psql(sql, usuario='supabase_admin'):
    r = subprocess.run(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-U', usuario, '-d', 'postgres', '-At', '-q',
                        '-v', 'ON_ERROR_STOP=1'], input=sql, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def valor(sql):
    rc, out, err = psql(sql)
    assert rc == 0, err
    return out.strip()


def caso(nombre, ok, detalle=''):
    RESULTADOS.append((nombre, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {nombre}{' — ' + detalle if detalle else ''}")


def estado():
    fila = valor(f"""select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '') || '|'
      || coalesce(md5(obj_description(p.oid, 'pg_proc')), 'sin comentario')
    from pg_proc p where p.oid = '{G.FIRMA}'::regprocedure""")
    huella, acl, comentario = fila.split('|')
    return huella, acl, comentario


def foto(actores, inversionistas, preparar=''):
    """{actor: {inversionista: ficha}} pidiendo cada ficha como ese actor; todo se deshace."""
    lista = ','.join(inversionistas)
    salida = {}
    for actor in actores:
        rc, out, err = psql(f"""begin;
{DOBLE}
{preparar}
select set_config('request.jwt.claims', json_build_object('sub', '{actor}', 'role', 'authenticated')::text, true)
  as _claims \\gset
set local role authenticated;
select jsonb_object_agg(i::text, banco_ficha.ficha_segura(i)) from unnest('{{{lista}}}'::uuid[]) i;
rollback;
""")
        assert rc == 0, err
        salida[actor] = json.loads(out.strip().splitlines()[-1])
    return salida


def sin_claves_nuevas(ficha):
    if not isinstance(ficha, dict) or 'inversiones' not in ficha:
        return ficha
    copia = dict(ficha)
    copia['inversiones'] = [{k: v for k, v in inv.items() if k not in CLAVES_NUEVAS} for inv in ficha['inversiones']]
    return copia


def diferencias(antes, despues):
    """Fichas (actor, inversionista) que cambian en algo más que las dos claves nuevas."""
    return [(a, i) for a in antes for i in antes[a] if sin_claves_nuevas(despues[a][i]) != antes[a][i]]


def inversiones(foto_):
    for actor, fichas in foto_.items():
        for inv_id, ficha in fichas.items():
            if isinstance(ficha, dict) and 'inversiones' in ficha:
                for inv in ficha['inversiones']:
                    yield actor, inv_id, inv


def errores_de_venta(foto_, esperado):
    """Inversiones sin las dos claves o con un analista de venta distinto del registrado en su fila."""
    malos = []
    for actor, inv_id, inv in inversiones(foto_):
        if any(k not in inv for k in CLAVES_NUEVAS):
            malos.append((actor, inv['fuente_id'], 'faltan claves'))
            continue
        e = esperado.get(inv['fuente_id'])
        if e is None or inv['analista_venta_id'] != e['id'] or inv['analista_venta_nombre'] != e['nombre']:
            malos.append((actor, inv['fuente_id'], inv.get('analista_venta_id')))
    return malos


def bloque_do(texto, etiqueta):
    inicio = texto.index(f'do {etiqueta}\n')
    fin = texto.index(f'{etiqueta};\n', inicio) + len(f'{etiqueta};\n')
    return texto[inicio:fin]


def negativa(nombre, sabotaje, bloque, esperado):
    rc, _, err = psql(f'begin;\n{sabotaje}\n{bloque}rollback;\n')
    caso(nombre, rc != 0 and esperado in err, err.strip().splitlines()[0] if err.strip() else 'no falló')


def principal():
    global CONTENEDOR
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contenedor', default=CONTENEDOR)
    args = parser.parse_args()
    CONTENEDOR = args.contenedor

    salidas, huella_nueva = G.generar()
    migracion, reversa, ensayo, registrar = (salidas[G.MIGRACION], salidas[G.REVERSA], salidas[G.ENSAYO],
                                             salidas[G.REGISTRAR])
    vivo = G.VIVO.read_text()
    acl_viva = G.ACL
    if estado() != (G.HUELLA_VIVA, acl_viva, 'sin comentario'):
        raise SystemExit(f'El banco no está en el estado de producción: {estado()}')

    # Actores y datos del banco.
    gerencia = valor("select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo order by perfil_id limit 1")
    supervisores = valor("select string_agg(perfil_id::text, ' ' order by perfil_id) from crm.equipo "
                         "where rol_crm = 'supervisor' and activo").split()
    vendedores = valor("select string_agg(perfil_id::text, ' ' order by perfil_id) from crm.equipo "
                       "where rol_crm = 'vendedor' and activo").split()
    directorio = valor("select string_agg(id::text, ' ' order by id) from public.perfiles p where p.activo "
                       "and p.rol = 'directorio' and not exists (select 1 from crm.equipo e where e.perfil_id = p.id)"
                       ).split()
    actores = [gerencia, *supervisores, *vendedores, *directorio]
    invs = valor("select string_agg(id::text, ' ' order by id) from crm.inversionistas").split()
    esperado = json.loads(valor("""select jsonb_object_agg(f.fuente_id::text, jsonb_build_object('id', v.id,
        'nombre', (select p.nombre_completo from public.perfiles p where p.id = v.id)))
      from private.cartera_f5_fuentes() f
      cross join lateral (select case when f.empresa = 'avance'
        then (select c.analista_cierre_id from public.contratos c where c.id = f.fuente_id)
        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id = f.fuente_id) end as id) v"""))
    # La baja: el vendedor con más inversiones en fichas deja el equipo y sus clientes pasan a otro vendedor activo,
    # como hace la baja real (responsable del cliente y de la relación).
    x = valor("""select f.analista_origen_id from private.cartera_f5_fuentes() f
      join crm.equipo e on e.perfil_id = f.analista_origen_id and e.rol_crm = 'vendedor' and e.activo
      where f.inversionista_id is not null group by 1 order by count(*) desc, 1 limit 1""")
    y = next(v for v in vendedores if v != x)
    baja = f"""set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = '{x}';
update public.perfiles set asesor_perfil_id = '{y}' where asesor_perfil_id = '{x}';
update crm.inversionistas set responsable_relacion_id = '{y}' where responsable_relacion_id = '{x}';
set local session_replication_role = origin;"""
    print(f'banco: {len(actores)} actores, {len(invs)} inversionistas, baja de {x[:8]} → {y[:8]}')

    # ANTES (cuerpo vivo).
    antes = foto(actores, invs)
    antes_baja = foto([gerencia], invs, baja)
    con_inversiones = {a: sum(1 for f in antes[a].values() if isinstance(f, dict) and f.get('inversiones'))
                       for a in actores}
    caso('la prueba no es vacía: gerencia, Directorio y al menos un vendedor ven inversiones',
         con_inversiones[gerencia] > 0 and all(con_inversiones[d] > 0 for d in directorio) and directorio != []
         and any(con_inversiones[v] > 0 for v in vendedores), str(con_inversiones))

    # Ensayo, negativas y registro antes de aplicar.
    rc, _, err = psql(ensayo)
    caso('ensayo: acaba en «ENSAYO FICHA PASS» y no deja nada',
         rc != 0 and 'ENSAYO FICHA PASS' in err and estado() == (G.HUELLA_VIVA, acl_viva, 'sin comentario'),
         err.strip().splitlines()[0] if err.strip() else '')
    bloque = bloque_do(migracion, '$migracion$')
    sabotaje_cuerpo = vivo.replace('begin\n  perform private.cartera_f5_exigir();',
                                   'begin\n  -- cambio ajeno\n  perform private.cartera_f5_exigir();', 1)
    assert sabotaje_cuerpo != vivo
    negativa('negativa: cuerpo distinto del medido', sabotaje_cuerpo + ';', bloque, 'PREFLIGHT: crm.inversionista_ficha_fn no es la medida')
    negativa('negativa: permisos distintos (anon con EXECUTE)',
             f'grant execute on function {G.FIRMA} to anon;', bloque, 'PREFLIGHT: permisos')
    negativa('negativa: ya tiene comentario', f"comment on function {G.FIRMA} is 'otro';", bloque,
             'PREFLIGHT: la ficha ya tiene comentario')
    envuelto = registrar.rsplit('commit;\n', 1)[0] + 'rollback;\n'
    rc, _, err = psql(envuelto)
    caso('registro antes de aplicar: se niega', rc != 0 and 'REGISTRO: la ficha no tiene el cuerpo nuevo' in err)

    # APLICAR y repetir.
    rc, _, err = psql(migracion)
    caso('aplicar', rc == 0 and estado()[0] == huella_nueva and estado()[1] == acl_viva
         and estado()[2] == G.md5(G.COMENTARIO), err.strip()[:200])
    rc, _, err = psql(migracion)
    caso('repetir: «ya aplicada» y nada cambia', rc == 0 and 'ya aplicada' in err and estado()[0] == huella_nueva)
    rc, out, err = psql(envuelto)
    caso('registro después de aplicar (deshecho): registra el texto exacto',
         rc == 0 and f'{G.VERSION}|{G.NOMBRE}|{G.md5(migracion)}' in out, err.strip()[:200])

    # DESPUÉS.
    despues = foto(actores, invs)
    difs = diferencias(antes, despues)
    caso('después: cada ficha de cada actor es la de antes más las dos claves', not difs, str(difs[:3]))
    malos = errores_de_venta(despues, esperado)
    total = sum(1 for _ in inversiones(despues))
    caso(f'después: las {total} inversiones traen quién vendió, el de su fila', total > 0 and not malos, str(malos[:3]))
    lector = [inv for a in directorio for _, _, inv in inversiones({a: despues[a]})]
    caso('Directorio: solo Avance y con las dos claves',
         lector != [] and all(inv['empresa'] == 'avance' and all(k in inv for k in CLAVES_NUEVAS) for inv in lector))
    despues_baja = foto([gerencia], invs, baja)
    difs = diferencias(antes_baja, despues_baja)
    distintos = [inv for _, _, inv in inversiones(despues_baja)
                 if inv['analista_venta_id'] == x and inv['analista_origen_id'] not in (x, None)]
    caso('baja: igual que antes salvo las claves; vendió el que se fue y cuenta para quien heredó',
         not difs and len(distintos) > 0 and not errores_de_venta(despues_baja, esperado),
         f'{len(distintos)} inversiones con dos nombres')

    # MUTANTES: cada uno debe hacer fallar la comprobación que lo vigila.
    nuevo = G.cuerpo_nuevo(vivo)
    m1 = nuevo.replace("'analista_venta_id',av.analista_id,", "'analista_venta_id',f.analista_origen_id,", 1)
    m1 = m1.replace('where id=av.analista_id),', 'where id=f.analista_origen_id),', 1)
    assert m1 != nuevo
    caso('mutante: venta = a quién cuenta → la baja lo detecta',
         errores_de_venta(foto([gerencia], invs, baja + '\n' + m1 + ';'), esperado) != [])
    m2 = nuevo.replace("      'numero_transaccion',case", "      'numero_transaccion_x',case", 1)
    assert m2 != nuevo
    caso('mutante: otra clave cambia → la comparación antes/después lo detecta',
         diferencias(antes, foto(actores, invs, m2 + ';')) != [])

    # REVERSA.
    rc, _, err = psql(reversa)
    caso('reversa: cuerpo anterior al byte, sin comentario, mismos permisos',
         rc == 0 and estado() == (G.HUELLA_VIVA, acl_viva, 'sin comentario'), err.strip()[:200])
    rc, _, err = psql(reversa)
    caso('reversa repetida: no hace nada', rc == 0 and 'ya está el cuerpo anterior' in err)
    caso('tras la reversa: fichas idénticas a las de antes', foto(actores, invs) == antes)
    negativa('reversa negativa: cuerpo desconocido', sabotaje_cuerpo + ';', bloque_do(reversa, '$reversa$'),
             'REVERSA: cuerpo desconocido')

    final = estado()
    caso('el banco queda como estaba', final == (G.HUELLA_VIVA, acl_viva, 'sin comentario'), str(final))
    fallos = [n for n, ok in RESULTADOS if not ok]
    print(f'\n{len(RESULTADOS) - len(fallos)}/{len(RESULTADOS)} PASS')
    sys.exit(1 if fallos else 0)


if __name__ == '__main__':
    principal()
```

## Salida del banco (Docker con el esquema de producción, 10/10)

```
banco: 10 actores, 40 inversionistas, baja de 857a97da → 58d6c111
PASS  la prueba no es vacía: gerencia, Directorio y al menos un vendedor ven inversiones — {'a716c39f-d059-4d74-a772-dd4130382d8a': 28, '5b3ce2a4-8a96-4cf0-86eb-fe8be62bb3d9': 0, '866e171f-0f7f-4511-a6a8-a4f44afccc59': 28, 'a0c29740-e1f0-45e9-80c7-0433bf32d0df': 0, '58d6c111-5c85-4169-8f2e-a78177b7e397': 0, '80b39a64-34da-440b-9a7d-aeb8403cc20f': 0, '857a97da-9fc8-4e9d-b319-aeb7f2dc2ca6': 28, '8778a96a-60c2-4b66-a530-9d50681c7d2c': 0, 'a26f50cc-a01d-4abd-bab3-88abf132986d': 0, 'dc21703e-a894-4536-80b9-7dc4901b211e': 19}
PASS  ensayo: acaba en «ENSAYO FICHA PASS» y no deja nada — ERROR:  ENSAYO FICHA PASS: cuerpo d0c6543b -> 9d981c6c, solo los dos fragmentos, permisos iguales, comentario puesto — SE DESHACE TODO
PASS  negativa: cuerpo distinto del medido — ERROR:  PREFLIGHT: crm.inversionista_ficha_fn no es la medida (huella 1aabe1149537381ab97eff207ae9cf8c); volver a generar el kit
PASS  negativa: permisos distintos (anon con EXECUTE) — ERROR:  PREFLIGHT: permisos, dueño o modo de la ficha distintos de los medidos ({postgres=X/postgres,authenticated=X/postgres,anon=X/postgres}, postgres, t)
PASS  negativa: ya tiene comentario — ERROR:  PREFLIGHT: la ficha ya tiene comentario; revisar a mano
PASS  registro antes de aplicar: se niega
PASS  aplicar
PASS  repetir: «ya aplicada» y nada cambia
PASS  registro después de aplicar (deshecho): registra el texto exacto
PASS  después: cada ficha de cada actor es la de antes más las dos claves — []
PASS  después: las 103 inversiones traen quién vendió, el de su fila — []
PASS  Directorio: solo Avance y con las dos claves
PASS  baja: igual que antes salvo las claves; vendió el que se fue y cuenta para quien heredó — 28 inversiones con dos nombres
PASS  mutante: venta = a quién cuenta → la baja lo detecta
PASS  mutante: otra clave cambia → la comparación antes/después lo detecta
PASS  reversa: cuerpo anterior al byte, sin comentario, mismos permisos — NOTICE:  Reversa de la ficha hecha
PASS  reversa repetida: no hace nada
PASS  tras la reversa: fichas idénticas a las de antes
PASS  reversa negativa: cuerpo desconocido — ERROR:  REVERSA: cuerpo desconocido de la ficha (huella 1aabe1149537381ab97eff207ae9cf8c); revisar a mano
PASS  el banco queda como estaba — ('d0c6543bc7226e027fb8364f137fd02a', '{postgres=X/postgres,authenticated=X/postgres}', 'sin comentario')

20/20 PASS
```

## Diff del front

```diff
diff --git a/CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx b/CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
index f25f5f19..7269b1ab 100644
--- a/CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
@@ -27,6 +27,12 @@ import { GestionInversionistaDialogo } from './gestion-inversionista-dialogo'
 
 const AYUDA_UPGRADE_COOPERATIVA = 'Registra un aporte adicional vinculado a una inversión vigente. La inversión original se conserva; la reinversión se registra por separado.'
 const coopAmpliable = (i: InversionFuente) => i.empresa !== 'avance' && !i.es_demo && ['vigente', 'activo'].includes(i.estado)
+// Fase 6 de Facturación (10/10/2026): quién VENDIÓ la inversión y, solo si es otra persona, para quién CUENTA hoy
+// (cadena de upgrade o baja del analista). Sin el dato del servidor queda una sola línea, como antes.
+const analistasDeLaOperacion = (i: InversionFuente): ReadonlyArray<readonly [string, string | null | undefined]> =>
+  i.analista_venta_id && i.analista_venta_id !== i.analista_origen_id
+    ? [['Analista de la operación', i.analista_venta_nombre], ['Cuenta para', i.analista_origen_nombre]]
+    : [['Analista de la operación', i.analista_origen_nombre]]
 
 export function ResumenEmpresas({totales, compacto = false, registrado = false}: {totales: ResumenEmpresa[]; compacto?: boolean; registrado?: boolean}) {
   return <div className="@container/resumen"><dl className={compacto ? 'grid grid-cols-2 gap-x-5 gap-y-3 @lg/resumen:grid-cols-[repeat(auto-fit,minmax(10rem,1fr))]' : 'grid gap-3 @md/resumen:grid-cols-2 @3xl/resumen:grid-cols-3'}>
@@ -110,7 +116,7 @@ function InversionDetalle({inversion, posicion, onDocumento, onOperacion, onRecu
         <div><dt className="text-muted-foreground">Rentabilidad anual</dt><dd>{i.contrato.tasa_anual}% · {i.contrato.tipo_interes === 'compuesto' ? 'al vencimiento' : i.contrato.modalidad}</dd></div>
       </>}
       {i.fecha_comercial !== i.fecha_imputacion && <div><dt className="text-muted-foreground">Fecha de imputación</dt><dd>{fmtFecha(i.fecha_imputacion)}</dd></div>}
-      <div><dt className="text-muted-foreground">Analista de la operación</dt><dd>{i.analista_origen_nombre || 'Sin información'}</dd></div>
+      {analistasDeLaOperacion(i).map(([rotulo, nombre]) => <div key={rotulo}><dt className="text-muted-foreground">{rotulo}</dt><dd>{nombre || 'Sin información'}</dd></div>)}
       {i.numero_transaccion && <div><dt className="text-muted-foreground">Depósito</dt><dd>{i.numero_transaccion}</dd></div>}
     </dl>
     {i.proxima_cuota && <p className="mt-3 text-xs">Próxima cuota: {fmtFecha(i.proxima_cuota.fecha)} · {money(i.proxima_cuota.monto, i.proxima_cuota.moneda)}</p>}
diff --git a/CRM-Avance-Corp/app/src/lib/inversionistas.ts b/CRM-Avance-Corp/app/src/lib/inversionistas.ts
index b5d81a70..d96a0ce8 100644
--- a/CRM-Avance-Corp/app/src/lib/inversionistas.ts
+++ b/CRM-Avance-Corp/app/src/lib/inversionistas.ts
@@ -42,6 +42,9 @@ export const InversionFuenteSchema = v.object({
   perfil_id: IdOpcional, lead_id: IdOpcional, numero: TextoOpcional, capital: Importe,
   moneda: Moneda, estado: v.string(), fecha_comercial: TextoOpcional, fecha_imputacion: TextoOpcional,
   vence_en: TextoOpcional, analista_origen_id: IdOpcional, analista_origen_nombre: TextoOpcional,
+  // Quién VENDIÓ (fase 6 de Facturación, 10/10/2026); analista_origen_* es a quién CUENTA hoy. Opcionales: un
+  // servidor anterior no los envía.
+  analista_venta_id: v.optional(IdOpcional), analista_venta_nombre: v.optional(TextoOpcional),
   es_inicial: v.nullable(v.boolean()), es_demo: v.boolean(), creado_en: v.string(),
   contrato: v.nullable(v.object({fecha_inicio: v.string(), tasa_anual: Importe,
     modalidad: v.picklist(['mensual', 'trimestral', 'semestral', 'anual']), tipo_interes: v.picklist(['simple', 'compuesto']),
diff --git a/CRM-Avance-Corp/app/src/screens/cartera-inversionistas.test.tsx b/CRM-Avance-Corp/app/src/screens/cartera-inversionistas.test.tsx
index c9ef2e31..4762b78d 100644
--- a/CRM-Avance-Corp/app/src/screens/cartera-inversionistas.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/cartera-inversionistas.test.tsx
@@ -88,6 +88,33 @@ describe('F5: cartera y ficha con acceso vigente', () => {
     expect(screen.getByText('12 meses')).toBeInTheDocument()
     expect(screen.getByRole('button',{name:/Copiar correo/i})).toBeInTheDocument()
   })
+  it('cada inversión dice quién la vendió y, solo si es otra persona, para quién cuenta (fase 6)', async () => {
+    const SE_FUE='55555555-5555-4555-8555-555555555555', FUENTE_2='66666666-6666-4666-8666-666666666666'
+    const d=structuredClone(fichaF5)
+    d.inversiones=[
+      {...inversionF5, numero:'SIN DATO DEL SERVIDOR'},
+      {...inversionF5, fuente_id:FUENTE_2, numero:'MISMA PERSONA', analista_venta_id:ACTOR_F5, analista_venta_nombre:'ANALISTA F5'},
+      {...inversionF5, fuente_id:SE_FUE, numero:'VENDIÓ OTRA', analista_venta_id:SE_FUE, analista_venta_nombre:'ANALISTA QUE SE FUE'},
+    ]
+    d.inversiones_total=3
+    // Por el esquema real: sin las dos claves en el esquema, valibot las quitaría y la tercera saldría con una línea.
+    const {parse}=await import('valibot')
+    const {FichaInversionistaSchema}=await import('@/lib/inversionistas')
+    api.ficha.mockResolvedValue(parse(FichaInversionistaSchema,d))
+    const {user}=montar()
+    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
+    const analistas=async (numero:string)=>{
+      const boton=await screen.findByRole('button',{name:`Ver inversión ${numero}`})
+      await user.click(boton)
+      const detalle=document.getElementById(boton.getAttribute('aria-controls') ?? '')
+      if(!detalle) throw new Error(`sin detalle para ${numero}`)
+      return within(detalle).getAllByRole('term').map(t=>`${t.textContent}: ${t.nextElementSibling?.textContent}`)
+        .filter(l=>l.startsWith('Analista de la operación') || l.startsWith('Cuenta para'))
+    }
+    expect(await analistas('SIN DATO DEL SERVIDOR')).toEqual(['Analista de la operación: ANALISTA F5'])
+    expect(await analistas('MISMA PERSONA')).toEqual(['Analista de la operación: ANALISTA F5'])
+    expect(await analistas('VENDIÓ OTRA')).toEqual(['Analista de la operación: ANALISTA QUE SE FUE', 'Cuenta para: ANALISTA F5'])
+  })
   it('conserva los totales del núcleo aunque la página solo contenga una inversión', async () => {
     const d=structuredClone(fichaF5)
     d.inversiones_total=40
```

## Pruebas del front

- La prueba nueva pasa (vitest). Mutantes con Python, cada uno MUERE: quitar las dos claves del esquema valibot; poner
  `false` en la condición (siempre una línea); quitar la comparación con `analista_origen_id` (dos líneas aunque sea la
  misma persona).
- `npm run check` (oxlint + typecheck + pruebas con cobertura): PASS, 410 archivos y 6.612 pruebas.

# Qué te pido (intenta refutar; con archivo/línea o fragmento citado)

1. ¿Puede la ficha nueva enseñar algo que el lector no veía ya (otra persona, otra empresa, Directorio fuera de Avance,
   demo)? ¿El lateral puede multiplicar o perder filas?
2. ¿Las guardas son completas? Preflight (huella, ACL, dueño, modo, comentario), postflight (huella + prueba por texto
   con `replace`), idempotencia, ensayo que siempre deshace, reversa estricta, registro.
3. ¿«Quién vendió» está bien definido así? Renovaciones y upgrades de Avance, cooperativas, contratos importados sin
   `analista_cierre_id`, coherencia con `analista_origen_*`.
4. Front: ¿la regla de una o dos líneas es correcta en todos los casos (dato nulo, misma persona, servidor viejo)?
   ¿Algún problema de accesibilidad con la lista `dl`?
5. ¿Falta alguna prueba que cambie la decisión?

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 (con evidencia), RISKS/TEST GAPS, NEXT ACTIONS, CONFIDENCE.

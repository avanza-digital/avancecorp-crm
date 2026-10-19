ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow the review protocol (transcrito al final).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí (los
archivos llevan número de línea). Formato: VERDICT (PASS/CHANGES_REQUESTED/BLOCK), SUMMARY, RESPUESTA a cada
pregunta P1–P6 (sí/no + por qué, con evidencia archivo:línea), FINDINGS P0–P3, RIESGOS y test gaps, NEXT ACTIONS,
CONFIDENCE. Pídete REFUTAR: busca lo que el código no cierra o lo que rompe, no lo que está bien.
**Ronda 2 de máximo 2 (la última).** La ronda 1 revisó el DISEÑO (CHANGES_REQUESTED, 2 P1 + 2 P2); esta revisa el CÓDIGO.

# Encargo: Gestión Diaria cuenta las llamadas a CLIENTES — CÓDIGO (migración + reversa + oráculo + ensayo) — LEVEL 3
Generado el 2026-10-19 en la rama `crm/llamadas-clientes-gestion-diaria-20261019` (desde `avancecorp/main` a1c103f8).

## Qué es (resumen de la ronda 1)
CRM interno (Supabase/Postgres 17). El marcador de Gestión Diaria (Mi día, Equipo, Hoy del supervisor, cortes, Pulso,
Hábitos) sale de UN lector `private.gestion_diaria_llamadas_eventos` que solo leía `crm.actividades` (leads). Las llamadas
a clientes viven en `crm.inversionista_gestiones` (cierre de tarea de llamada de postventa; tabla SIN policy SELECT) y en
el legado `crm.actividades_cliente`. Decisión de Miguel: suman al mismo número, a la tasa de contacto y a los cortes.

## Cómo se atendió cada hallazgo de la ronda 1
- [P1] «El gate no protege al ayudante» → ACEPTADO: sección 2b en `assert_gestion_diaria_analista` (forma DEFINER, dueño,
  STABLE, search_path, ACL exacta, sin contador crudo, espejo por estructura, huella sellada) + 11 mutantes propios que se
  niegan si el gate ya está en rojo (detección en vacío).
- [P1] «Espejo de visibilidad no cubre el permiso» → ACEPTADO en parte: el ayudante FILTRA (nunca lanza) por
  `vendedor_ids_visibles` + `puede_acceder_crm` + rol vendedor/supervisor/gerencia sin lector global + banderas de
  postventa; la métrica es por AUTOR (una reasignación no borra histórico; documentado y probado). NO se aplica
  `postventa_visible(persona)`: es la visibilidad por persona de la RLS de tareas, distinta del Registro de clientes
  (`gestiones_clientes_eventos`, que también autoriza por autor).
- [P2] «Personas distintas sin identidad común» → ACEPTADO: `leads_tocados` sigue contando SOLO leads (NULL excluido);
  el texto de pantalla no promete «personas».
- [P2] «Universo distinto al Registro» → ACEPTADO: misma regla de estado (`coalesce(metadata->>'estado', t.estado)`) y
  el legado `actividades_cliente` con la misma regla antiespejo.
- Rechazado con evidencia: filtro contra doble conteo lead/cliente (0 llamadas sobre leads convertidos tras su
  conversión en 30 días; `registrar_llamada_v3` rechaza leads cerrados).
- HALLAZGO PROPIO durante el ensayo (no de Codex): el plan llamaba a `crm.postventa_estado_fn()` para la bandera; esa
  puerta pasa por `private.postventa_modo()` que hace `select … for share nowait`, y PostgREST ejecuta las puertas
  STABLE en transacción de SOLO LECTURA → «cannot execute SELECT FOR SHARE in a read-only transaction» (reproducido en
  el banco). Se cambió a la misma lectura sin candado que usa `private.postventa_visible_actor` (RLS de tareas):
  `resolver_en_puertas_bajo_candado()` + las dos banderas activas (o piloto F8). Divergencia declarada: el Registro
  exige además la cobertura de la cartera F5 (`cartera_inversionistas_estado_fn`); el marcador no.

## Datos de producción que importan (19/10/2026)
- Gates vivos: `assert_gestion_diaria_analista` ROJO por `crm.equipo_visible_fn` (cambió el 15/10, consulta de
  Coordinación; lo re-sella aparte `20261016211001`, trabajo de otra sesión en pausa); `assert_gestion_diaria_pulso`
  ROJO por lo anterior y por el censo analítico (otras 10 piezas ajenas, desde el 01/10). La migración NO re-sella lo ajeno:
  su postflight acepta SOLO esos dos rojos (por el texto exacto del error) y aborta ante cualquier otro.
- Huellas vivas: lector 27d25609…, agregador 7c5d14e6…, gate analista eb2c03fd…, citas 12012959…, pulso bdccbb6e…
  (iguales en el banco, medidas por `md5(pg_get_functiondef)`).
- `crm.inversionista_gestiones`: sin policy SELECT. `crm.tareas`: `tareas_select` (vendedor_ids_visibles/gerencia) y
  `tareas_postventa_lectura` (`inversionista_id is null or private.postventa_visible(inversionista_id)`).
- `private.vendedor_ids_visibles(uuid)`: gerencia → todo el equipo (incluye históricos); supervisor → su subárbol;
  vendedor → él mismo; otro rol o actor distinto sin lector global → vacío.
- Catálogo de resultado de llamada de cliente (postventa v2, `20261005224214`): los MISMOS 7 que los leads.

## Resultado del ensayo (banco propio con el esquema de producción, 19/10)
ENSAYO OK · 11 mutantes nuevos detectados por assert_gestion_diaria_analista · 24 mutantes viejos detectados por el
paraguas (con 20261016211001 SIMULADO en el banco: roster re-sellado y censo ajeno neutralizado SOLO en el banco) ·
oráculo GESTION_DIARIA_LLAMADAS_CLIENTES_OK (5 bloques) · censo analítico intacto · reversa devuelve lector, agregador
y los tres gates EXACTOS de producción · reinstalación determinista · cadena completa como analista y como supervisor
en `begin read only` OK.

## Preguntas concretas
P1. ¿El ayudante (migración, bloque «CAPA 2 · NÚCLEO») puede devolver una fila que el actor no deba ver? ¿Algún camino
    en que `visibles` quede no vacío para un actor sin derecho? ¿Alguna función invocada puede LANZAR en solo lectura?
P2. ¿La clasificación (tipo/util) y el predicado de estado/tipo de tarea son exactamente los del Registro
    (`gestiones_clientes_eventos`, transcrito)? Señala cualquier fila que uno cuente y el otro no (salvo la divergencia
    declarada de cobertura F5).
P3. Re-sellado por `replace()` anclado (bloque GATE) + preflight de anclas: ¿puede quedar un gate con placeholders, con
    una huella vieja o re-sellar algo ajeno sin querer? ¿Compone bien si `20261016211001` se aplica ANTES o DESPUÉS?
P4. Postflight: ¿acepta algún rojo que no debería? ¿Aborta ante un rojo propio? ¿Falta alguna comprobación?
P5. Reversa: ¿devuelve EXACTAMENTE producción en los dos órdenes (antes/después de 211001)? ¿La expresión regular de la
    sección 2b puede fallar o borrar de más?
P6. Oráculo y mutantes: ¿qué caso negativo falta? ¿Algún mutante es vacuo (lo detecta algo distinto de lo que dice)?

## ARCHIVOS TRANSCRITOS

### supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql
```
    1  -- 20261019170422_crm_gestion_diaria_llamadas_clientes.sql
    2  -- GESTIÓN DIARIA: las llamadas a CLIENTES cuentan en el número de llamadas del analista.
    3  --
    4  -- QUÉ PASABA. El marcador de Gestión Diaria (Mi día, Equipo, «Llamadas de hoy» del supervisor, cortes de jornada,
    5  -- mínimo de llamadas útiles, Pulso y Hábitos) sale de UN lector, `private.gestion_diaria_llamadas_eventos`, que lee
    6  -- solo `crm.actividades` (tabla de leads, `lead_id not null`). Las llamadas a clientes se registran al cerrar una
    7  -- tarea de llamada de postventa y quedan en `crm.inversionista_gestiones` (tipo `cierre`, resultado en `metadata`),
    8  -- que el marcador nunca miraba. Medido en producción el 19/10/2026: Vladimir Jurado cerró 5 llamadas a clientes
    9  -- (3 «agendó reunión», 2 «volver a llamar») y su marcador decía «1 llamada» (la única a un lead).
   10  --
   11  -- DECISIONES DE MIGUEL (19/10/2026): (1) las llamadas a clientes SUMAN al mismo número «Llamadas»; (2) entran en la
   12  -- TASA DE CONTACTO; (3) cuentan hacia los cortes de jornada y el mínimo de llamadas útiles.
   13  -- Revisión de diseño de Codex (r1, 19/10, CHANGES_REQUESTED): aceptados (a) gate propio para el ayudante, (b) el
   14  -- ayudante FILTRA por la visibilidad del actor en vez de lanzar error (no rompe el Pulso de un lector global),
   15  -- (c) «leads tocados» sigue contando SOLO leads (no se promete «personas distintas»: lead y cliente no comparten
   16  -- identidad), (d) misma regla de estado y de legado que el Registro de clientes (`gestiones_clientes_eventos`).
   17  -- Rechazado con evidencia: filtro contra el doble conteo lead/cliente (0 llamadas sobre leads convertidos en 30 días
   18  -- y la encuesta rechaza leads cerrados; un filtro podría borrar llamadas legítimas del mismo día).
   19  --
   20  -- QUÉ HACE.
   21  --   1. Nuevo ayudante `private.gestion_diaria_llamadas_clientes_eventos(p_ini, p_fin, p_vendedor_ids)`
   22  --      (SECURITY DEFINER, justificación: `crm.inversionista_gestiones` NO tiene policy de lectura, deny-by-default; la
   23  --      cadena del marcador corre como el actor). Es un ESPEJO de la visibilidad, no una puerta: devuelve solo los
   24  --      autores pedidos que estén en `private.vendedor_ids_visibles(auth.uid())`, exige sesión y
   25  --      `private.puede_acceder_crm()`, rol vendedor/supervisor/gerencia (nunca un lector global), y devuelve vacío si
   26  --      la postventa no está encendida: `private.resolver_en_puertas_bajo_candado()` y las dos banderas
   27  --      `ficha_360_neutral` + `postventa_neutral` activas (o el actor en el piloto F8), LEÍDAS SIN CANDADO DE FILA.
   28  --      No llama a `crm.postventa_estado_fn()`: esa puerta pasa por `private.postventa_modo()`, que toma `for share`,
   29  --      y PostgREST ejecuta las puertas STABLE (toda la cadena del marcador) en una transacción de SOLO LECTURA, donde
   30  --      `SELECT FOR SHARE` es un error (reproducido en el banco el 19/10/2026). Es la misma lectura sin candado que ya
   31  --      hace `private.postventa_visible_actor` para la RLS de `crm.tareas`. Divergencia declarada con el Registro de
   32  --      clientes: aquel exige además la cobertura de la cartera F5 (`crm.cartera_inversionistas_estado_fn`); si la
   33  --      cartera entrara en «requiere conciliación», el Registro ocultaría las gestiones de clientes y el marcador no.
   34  --      Los NULL de `p_vendedor_ids` se ignoran (una gestión siempre tiene autor). La métrica es POR QUIEN REGISTRÓ:
   35  --      una reasignación de cartera no borra llamadas históricas.
   36  --      Qué es una llamada a cliente: cierre (`tipo = 'cierre'`) de una tarea de tipo `llamada` con estado
   37  --      `completada` (misma regla que el Registro: `coalesce(metadata->>'tipo_tarea', t.tipo)` y
   38  --      `coalesce(metadata->>'estado', t.estado)`), más el camino legado `crm.actividades_cliente` sin espejo de cierre.
   39  --      Traducción (idéntica a la del Registro de clientes y al catálogo de 7 resultados de los leads):
   40  --        no_contesto, numero_errado, no_es_la_persona → `llamada_no_contestada`; el resto → `llamada_realizada`;
   41  --        útil = resultado ∉ {numero_errado, no_es_la_persona, sin_resultado} (un cierre antiguo sin resultado cuenta
   42  --        como llamada, pero no como contestada ni útil; el legado `llamada_realizada` sí es contacto, como en el
   43  --        Registro).
   44  --   2. `private.gestion_diaria_llamadas_eventos` (INVOKER, misma firma y mismo retorno) devuelve leads ∪ clientes:
   45  --      el cuerpo vivo + `union all` del ayudante. Las filas de clientes llevan `lead_id` NULL.
   46  --   3. `private.gestion_diaria_llamadas` (agregador): cuerpo vivo con UN cambio, `leads_tocados` excluye el NULL
   47  --      (`array_agg(distinct l.lead_id) filter (where l.lead_id is not null)`): sigue contando leads, nunca +1 por los
   48  --      clientes. Todo lo demás (llamadas, contestadas, útiles, por resultado, por hora, primera/última) incluye a los
   49  --      clientes por construcción.
   50  --   4. Re-sella TRES gates a partir de su cuerpo VIVO con reemplazos anclados: `private.assert_gestion_diaria_analista()`
   51  --      (huella del agregador, huella del lector y la sección 2b nueva), `private.assert_gestion_diaria_citas()` (huella
   52  --      del agregador: G4b exige revisar la lista de citas con la cifra) y `private.assert_gestion_diaria_pulso()` (huellas
   53  --      del agregador y del lector). En el del analista, tres reemplazos
   54  --      (huella del agregador, huella del lector, y una sección 2b nueva que exige al ayudante forma DEFINER, dueño
   55  --      postgres, STABLE, search_path vacío, EXECUTE exactamente postgres y authenticated, sin contador crudo, su espejo
   56  --      de visibilidad por estructura y su huella sellada). No toca la huella de `crm.equipo_visible_fn()` (en rojo
   57  --      desde el 15/10 por la consulta de Coordinación: la re-sella `20261016211001`, trabajo aparte en pausa).
   58  --   5. Mutantes nuevos `private.assert_gestion_diaria_llamadas_clientes_mutantes()` (solo banco): 11 mutaciones que el
   59  --      gate debe detectar; se niega si el gate ya está en rojo (un gate rojo detecta cualquier mutante en vacío).
   60  --
   61  -- EFECTO EN PRODUCCIÓN. Los números del día en que se aplica se recalculan con las llamadas a clientes ya registradas.
   62  -- Los cortes ya reconocidos no se reabren: el reconocimiento se guarda por alerta (`crm.alertas_reconocimientos`),
   63  -- no por cifra. Apagar la postventa vuelve a retirar esas llamadas del marcador (misma bandera que el Registro).
   64  -- Lo que NO cambia: cómo se registra una llamada a cliente; el sub-número «leads distintos» del Pulso
   65  -- (`count(distinct lead_id)` ignora el NULL: sigue siendo solo leads); la cola, los compromisos y la cartera.
   66  --
   67  -- POSTFLIGHT. Verifica forma, ACL, huellas y la sección 2b del gate; corre el gate y acepta SOLO el rojo ajeno de
   68  -- `crm.equipo_visible_fn()` (documentado arriba); cualquier otro rojo aborta la transacción.
   69  -- REVERSIÓN: supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql (devuelve lector, agregador y gate a sus
   70  -- cuerpos de producción del 19/10 y retira el ayudante y los mutantes). Ensayo: ensayar.mjs (banco propio con el
   71  -- esquema de producción; huellas medidas en dos pasadas).
   72  
   73  begin;
   74  set local lock_timeout = '5s';
   75  set local statement_timeout = '120s';
   76  set local quote_all_identifiers = off;
   77  
   78  -- ── PREFLIGHT ─────────────────────────────────────────────────────────────────
   79  do $preflight$
   80  declare
   81    v_gate text;
   82    v_n integer;
   83  begin
   84    if to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])') is not null
   85       or to_regprocedure('private.assert_gestion_diaria_llamadas_clientes_mutantes()') is not null then
   86      raise exception 'PREFLIGHT llamadas_clientes: ya instalada (total o parcialmente)';
   87    end if;
   88    -- Los dos cuerpos que se reemplazan son los VIVOS en producción (medidos el 19/10/2026, iguales en el banco).
   89    if md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure))
   90         is distinct from '27d25609c74e04c58f82e36af45d7327' then
   91      raise exception 'PREFLIGHT llamadas_clientes: private.gestion_diaria_llamadas_eventos no es el cuerpo vivo del 19/10 (md5 %)',
   92        md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
   93    end if;
   94    if md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure))
   95         is distinct from '7c5d14e65cc0e55e57214589d11e9c9d' then
   96      raise exception 'PREFLIGHT llamadas_clientes: private.gestion_diaria_llamadas no es el cuerpo vivo del 19/10 (md5 %)',
   97        md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
   98    end if;
   99    -- El gate vivo trae las tres anclas EXACTAMENTE una vez (compone con otros re-sellados del mismo gate).
  100    v_gate := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  101    foreach v_n in array array[
  102      (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / length('''7c5d14e65cc0e55e57214589d11e9c9d'''),
  103      (length(v_gate) - length(replace(v_gate, '''27d25609c74e04c58f82e36af45d7327''', ''))) / length('''27d25609c74e04c58f82e36af45d7327'''),
  104      (length(v_gate) - length(replace(v_gate, '  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,', ''))) / length('  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,')
  105    ] loop
  106      if v_n <> 1 then
  107        raise exception 'PREFLIGHT llamadas_clientes: el gate private.assert_gestion_diaria_analista no trae una ancla exactamente una vez (%)', v_n;
  108      end if;
  109    end loop;
  110    if v_gate like '%gestion_diaria_llamadas_clientes_eventos%' then
  111      raise exception 'PREFLIGHT llamadas_clientes: el gate ya nombra al ayudante';
  112    end if;
  113    -- Los otros dos gates que sellan el agregador (citas) y el agregador + lector (pulso): cada huella exactamente una vez.
  114    v_gate := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
  115    if (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / 34 <> 1
  116       or v_gate like '%27d25609c74e04c58f82e36af45d7327%' then
  117      raise exception 'PREFLIGHT llamadas_clientes: el gate de citas no sella el agregador exactamente una vez';
  118    end if;
  119    v_gate := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
  120    if (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / 34 <> 1
  121       or (length(v_gate) - length(replace(v_gate, '''27d25609c74e04c58f82e36af45d7327''', ''))) / 34 <> 1 then
  122      raise exception 'PREFLIGHT llamadas_clientes: el gate del pulso no sella el agregador y el lector exactamente una vez';
  123    end if;
  124    -- Las fuentes que lee el ayudante tienen la forma esperada.
  125    if to_regclass('crm.inversionista_gestiones') is null or to_regclass('crm.actividades_cliente') is null
  126       or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
  127       or to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null
  128       or to_regprocedure('private.piloto_f8_actor_activo(uuid)') is null
  129       or to_regprocedure('private.rol_crm(uuid)') is null or to_regprocedure('private.es_lector_global()') is null
  130       or to_regprocedure('private.puede_acceder_crm()') is null then
  131      raise exception 'PREFLIGHT llamadas_clientes: faltan fuentes o ayudantes de visibilidad';
  132    end if;
  133  end $preflight$;
  134  
  135  -- ── CAPA 2 · NÚCLEO · el ayudante de las llamadas a clientes ──────────────────
  136  -- SECURITY DEFINER justificado: crm.inversionista_gestiones no tiene policy de lectura (deny-by-default) y la cadena
  137  -- del marcador corre como el actor. Espejo de la visibilidad: solo autores pedidos que el actor puede ver.
  138  create function private.gestion_diaria_llamadas_clientes_eventos(
  139    p_ini timestamptz,
  140    p_fin timestamptz,
  141    p_vendedor_ids uuid[]
  142  ) returns table (
  143    vendedor_id uuid,
  144    id uuid,
  145    lead_id uuid,
  146    tipo text,
  147    creado_en timestamptz,
  148    resultado text,
  149    util boolean,
  150    hora integer
  151  )
  152  language sql
  153  stable
  154  security definer
  155  set search_path = ''
  156  as $$
  157    with actor as (
  158      -- Espejo de la visibilidad del actor (vendedor_ids_visibles), con la puerta de acceso al CRM, el rol que puede
  159      -- ver postventa y las banderas de postventa leídas SIN candado de fila (como private.postventa_visible_actor):
  160      -- la cadena del marcador corre en transacciones de solo lectura. Sin sesión, sin acceso, con un rol que no ve
  161      -- postventa o con la postventa apagada: ningún autor visible. Un lector sin equipo visible no ve llamadas a clientes.
  162      select case
  163        when (select auth.uid()) is null or private.puede_acceder_crm() is not true then array[]::uuid[]
  164        when coalesce(private.rol_crm((select auth.uid())) in ('vendedor', 'supervisor', 'gerencia'), false) is not true
  165             or coalesce(private.es_lector_global(), false) then array[]::uuid[]
  166        when private.resolver_en_puertas_bajo_candado() is not true then array[]::uuid[]
  167        when not (coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2
  168                            from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false)
  169                  or coalesce(private.piloto_f8_actor_activo((select auth.uid())), false)) then array[]::uuid[]
  170        else coalesce((select array_agg(v.id) from private.vendedor_ids_visibles((select auth.uid())) as v(id)), array[]::uuid[])
  171      end as visibles
  172    ),
  173    autores as (
  174      select distinct p.id
  175      from unnest(p_vendedor_ids) as p(id), actor a
  176      where p.id is not null and p.id = any (a.visibles)
  177    ),
  178    cierres as (
  179      -- Postventa: el cierre de una tarea de llamada, completada (misma regla que gestiones_clientes_eventos).
  180      select g.creado_por as autor, g.id, g.creado_en,
  181             coalesce(g.metadata->>'tipo_tarea', t.tipo) as tarea_tipo,
  182             coalesce(g.metadata->>'estado', t.estado) as estado,
  183             coalesce(g.metadata->>'resultado', 'sin_resultado') as resultado,
  184             null::text as tipo_legado
  185      from crm.inversionista_gestiones g
  186      join crm.tareas t on t.id = g.tarea_id
  187      where g.tipo = 'cierre'
  188        and g.creado_por in (select au.id from autores au)
  189        and g.creado_en >= p_ini and g.creado_en < p_fin
  190      union all
  191      -- Camino legado (crm.actividades_cliente), solo sin espejo de cierre F6: la misma regla antiespejo del Registro.
  192      select a.creado_por, a.id, a.creado_en, 'llamada', 'completada', 'sin_resultado', a.tipo
  193      from crm.actividades_cliente a
  194      where a.tipo in ('llamada_realizada', 'llamada_no_contestada')
  195        and a.creado_por in (select au.id from autores au)
  196        and a.creado_en >= p_ini and a.creado_en < p_fin
  197        and not exists (select 1 from crm.inversionista_gestiones g where g.tarea_id = a.tarea_id and g.tipo = 'cierre')
  198    )
  199    select c.autor,
  200           c.id,
  201           null::uuid,
  202           coalesce(c.tipo_legado,
  203                    case when c.resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
  204                         then 'llamada_no_contestada' else 'llamada_realizada' end),
  205           c.creado_en,
  206           c.resultado,
  207           (c.tipo_legado is not null) or c.resultado not in ('numero_errado', 'no_es_la_persona', 'sin_resultado'),
  208           extract(hour from c.creado_en at time zone 'America/Lima')::integer
  209    from cierres c
  210    where c.tarea_tipo = 'llamada' and c.estado = 'completada';
  211  $$;
  212  comment on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) is
  213    'NÚCLEO (Gestión Diaria, 19/10/2026): las llamadas a CLIENTES del marcador: cierres completados de tareas de llamada de postventa (crm.inversionista_gestiones, resultado en metadata) y el legado crm.actividades_cliente sin espejo de cierre, en la ventana [p_ini, p_fin), con la misma forma que el lector de leads (lead_id NULL). DEFINER justificado: la tabla no tiene policy de lectura; es un ESPEJO de la visibilidad del actor (vendedor_ids_visibles + puede_acceder_crm + rol vendedor/supervisor/gerencia sin lector global + banderas de postventa leídas sin candado, como postventa_visible_actor), devuelve solo autores visibles y vale en transacciones de solo lectura. Traducción idéntica al Registro de clientes: no_contesto/numero_errado/no_es_la_persona → no contestada; útil = resultado fuera de numero_errado/no_es_la_persona/sin_resultado; el legado llamada_realizada es contacto.';
  214  revoke all on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[])
  215    from public, anon, authenticated, service_role;
  216  grant execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) to authenticated;
  217  
  218  -- ── el lector único: leads ∪ clientes (cuerpo vivo + union all) ───────────────
  219  create or replace function private.gestion_diaria_llamadas_eventos(
  220    p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
  221  returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
  222    resultado text,util boolean,hora integer)
  223  language sql stable security invoker set search_path='' as $$
  224    select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
  225      coalesce(a.metadata->>'resultado','sin_resultado'),
  226      coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
  227      extract(hour from a.creado_en at time zone 'America/Lima')::integer
  228    from crm.actividades a where
  229      (a.creado_por=any(p_vendedor_ids)
  230        or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
  231      and a.tipo in ('llamada_realizada','llamada_no_contestada')
  232      and a.creado_en>=p_ini and a.creado_en<p_fin
  233    union all
  234    -- Las llamadas a clientes (19/10/2026): mismo contrato, lead_id NULL, bajo el espejo de visibilidad del ayudante.
  235    select c.vendedor_id,c.id,c.lead_id,c.tipo,c.creado_en,c.resultado,c.util,c.hora
  236    from private.gestion_diaria_llamadas_clientes_eventos(p_ini,p_fin,p_vendedor_ids) c;
  237  $$;
  238  comment on function private.gestion_diaria_llamadas_eventos(timestamptz, timestamptz, uuid[]) is
  239    'NÚCLEO (Gestión Diaria): el lector único de llamadas del marcador, por autor y ventana [p_ini, p_fin): llamadas a leads (crm.actividades, bajo la RLS del actor) ∪ llamadas a clientes (private.gestion_diaria_llamadas_clientes_eventos, espejo de visibilidad; lead_id NULL). Desde el 19/10/2026 las llamadas a clientes cuentan en el mismo número (decisión de Miguel).';
  240  
  241  -- ── el agregador: cuerpo vivo con UN cambio (leads_tocados excluye el NULL de los clientes) ─
  242  CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
  243   RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
  244   LANGUAGE sql
  245   STABLE
  246   SET search_path TO ''
  247  AS $function$
  248    with vendedores as (
  249      select distinct v.id from unnest(p_vendedor_ids) as v(id)
  250    ),
  251    ll as (
  252      select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
  253    ),
  254    agg as (
  255      select l.vendedor_id,
  256             cardinality(array_agg(l.id)) as llamadas,
  257             -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
  258             -- 100 % aunque una fila histórica llevara un resultado incoherente
  259             -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
  260             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
  261             coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
  262             -- Leads tocados = leads distintos. Las llamadas a clientes (19/10/2026) traen lead_id NULL y
  263             -- no cuentan aquí: lead y cliente no comparten identidad.
  264             cardinality(array_agg(distinct l.lead_id) filter (where l.lead_id is not null)) as leads_tocados,
  265             min(l.creado_en) as primera_llamada_en,
  266             max(l.creado_en) as ultima_llamada_en
  267      from ll l
  268      group by l.vendedor_id
  269    ),
  270    por_resultado as (
  271      select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
  272      from (
  273        select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
  274        from ll l
  275        group by l.vendedor_id, l.resultado
  276      ) r
  277      group by r.vendedor_id
  278    ),
  279    por_hora as (
  280      select h.vendedor_id,
  281             jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
  282      from (
  283        select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
  284               coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
  285        from ll l
  286        group by l.vendedor_id, l.hora
  287      ) h
  288      group by h.vendedor_id
  289    ),
  290    citas as (
  291      -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
  292      -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
  293      -- tarea y cuentan igual que allí.
  294      select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
  295      from crm.tareas t
  296      where (t.vendedor_id in (select v.id from vendedores v)
  297        or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
  298        and t.tipo = 'reunion'
  299        and t.creado_en >= p_ini
  300        and t.creado_en <  p_fin
  301      group by t.vendedor_id
  302    )
  303    select v.id,
  304           coalesce(a.llamadas, 0),
  305           coalesce(a.contestadas, 0),
  306           coalesce(a.utiles, 0),
  307           coalesce(a.leads_tocados, 0),
  308           coalesce(c.citas_agendadas, 0),
  309           a.primera_llamada_en,
  310           a.ultima_llamada_en,
  311           coalesce(r.por_resultado, '{}'::jsonb),
  312           coalesce(h.por_hora, '[]'::jsonb)
  313    from vendedores v
  314    left join agg a on a.vendedor_id is not distinct from v.id
  315    left join por_resultado r on r.vendedor_id is not distinct from v.id
  316    left join por_hora h on h.vendedor_id is not distinct from v.id
  317    left join citas c on c.vendedor_id is not distinct from v.id
  318    order by v.id;
  319  $function$;
  320  comment on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) is
  321    'NÚCLEO (Gestión Diaria): la definición única de llamada (realizada + no contestada, a leads Y a clientes desde el 19/10/2026), contacto (realizada y útil), útil (resultado ∉ numero_errado/no_es_la_persona; en leads sin resultado cuenta como útil; en clientes sin resultado no), leads tocados (solo leads: las llamadas a clientes no suman aquí), citas agendadas (tarea reunion creada en la ventana), primera/última llamada, desglose por resultado y por hora Lima, por analista y ventana [p_ini, p_fin). Bajo la RLS del actor; sin contadores crudos.';
  322  
  323  -- ── GATE · re-sellar private.assert_gestion_diaria_analista desde su cuerpo VIVO ─
  324  do $gate$
  325  declare
  326    v_def text;
  327    v_seccion text;
  328  begin
  329    v_def := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  330    -- Huellas nuevas del agregador y del lector (medidas en el banco, dos pasadas).
  331    v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''1325886469e34ee651d69672ca1a72c5''');
  332    v_def := replace(v_def, '''27d25609c74e04c58f82e36af45d7327''', '''a209ec1be82b2eeff40c7f6488342d69''');
  333    -- Sección 2b: el ayudante DEFINER de las llamadas a clientes.
  334    v_seccion := $s$  -- 2b. El ayudante DEFINER de las llamadas a CLIENTES (19/10/2026): forma exacta (DEFINER, dueño
  335    --     postgres, STABLE, search_path vacío), EXECUTE exactamente postgres y authenticated, sin contador crudo,
  336    --     su espejo de visibilidad por estructura y su cuerpo sellado. Es un ESPEJO de la visibilidad del actor
  337    --     (vendedor_ids_visibles + puede_acceder_crm + banderas de postventa sin candado), no una puerta.
  338    v_id := to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])');
  339    if v_id is null or not exists (
  340      select 1 from pg_proc p
  341      where p.oid = v_id and p.prosecdef
  342        and p.proowner = 'postgres'::regrole::oid
  343        and p.provolatile = 's'
  344        and p.proconfig @> array['search_path=""']
  345    ) then
  346      raise exception 'Contrato del ayudante de llamadas a clientes alterado (debe ser DEFINER, stable, search_path vacio, dueno postgres)';
  347    end if;
  348    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
  349       or exists (
  350         select 1 from pg_proc p
  351         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  352         where p.oid = v_id
  353           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
  354       ) then
  355      raise exception 'ACL del ayudante de llamadas a clientes alterada';
  356    end if;
  357    if exists (select 1 from pg_proc p where p.oid = v_id
  358               and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
  359      raise exception 'El ayudante de llamadas a clientes cuenta a crudo';
  360    end if;
  361    if not exists (select 1 from pg_proc p where p.oid = v_id
  362                   and p.prosrc like '%private.vendedor_ids_visibles(%'
  363                   and p.prosrc like '%private.puede_acceder_crm()%'
  364                   and p.prosrc like '%private.resolver_en_puertas_bajo_candado()%'
  365                   and p.prosrc like '%''postventa_neutral''%'
  366                   and p.prosrc not like '%for share%') then
  367      raise exception 'El ayudante de llamadas a clientes perdio su espejo de visibilidad (vendedor_ids_visibles, puede_acceder_crm, resolver_en_puertas y banderas de postventa sin candado)';
  368    end if;
  369    if md5(pg_get_functiondef(v_id)) is distinct from '1e4618d5810b64d543aadd89fa31013b' then
  370      raise exception 'El cuerpo de private.gestion_diaria_llamadas_clientes_eventos cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
  371        md5(pg_get_functiondef(v_id));
  372    end if;
  373  
  374  $s$;
  375    v_def := replace(v_def,
  376      '  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,',
  377      v_seccion || '  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,');
  378    if v_def not like '%1325886469e34ee651d69672ca1a72c5%' or v_def not like '%a209ec1be82b2eeff40c7f6488342d69%'
  379       or v_def not like '%-- 2b. El ayudante DEFINER de las llamadas a CLIENTES%' then
  380      raise exception 'GATE llamadas_clientes: algun reemplazo anclado no aplico';
  381    end if;
  382    execute v_def;
  383    -- El gate de citas (G4b) sella el agregador: misma cifra, lista de citas revisada (las llamadas a clientes no son citas).
  384    v_def := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
  385    v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''1325886469e34ee651d69672ca1a72c5''');
  386    if v_def not like '%1325886469e34ee651d69672ca1a72c5%' then
  387      raise exception 'GATE llamadas_clientes: el reemplazo en el gate de citas no aplico';
  388    end if;
  389    execute v_def;
  390    -- El gate del pulso sella el agregador y el lector.
  391    v_def := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
  392    v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''1325886469e34ee651d69672ca1a72c5''');
  393    v_def := replace(v_def, '''27d25609c74e04c58f82e36af45d7327''', '''a209ec1be82b2eeff40c7f6488342d69''');
  394    if v_def not like '%1325886469e34ee651d69672ca1a72c5%' or v_def not like '%a209ec1be82b2eeff40c7f6488342d69%' then
  395      raise exception 'GATE llamadas_clientes: el reemplazo en el gate del pulso no aplico';
  396    end if;
  397    execute v_def;
  398  end $gate$;
  399  comment on function private.assert_gestion_diaria_analista() is
  400    'Trinquete de Gestión Diaria F3 (el día del analista): puerta y núcleos INVOKER con ACL exacta, huellas selladas (puerta, núcleo, agregador, lector, umbrales, roster), ayudante DEFINER de las llamadas a clientes (19/10/2026: forma, ACL, espejo de visibilidad y huella), cola v2 en su forma y perilla del abandono bajo RLS. Re-sellado el 19/10/2026 para contar las llamadas a clientes.';
  401  
  402  -- ── MUTANTES (solo banco) ─────────────────────────────────────────────────────
  403  create function private.assert_gestion_diaria_llamadas_clientes_mutantes() returns text
  404  language plpgsql volatile security definer set search_path = '' as $function$
  405  declare
  406    v_detectados integer := 0;
  407    v_mutacion text;
  408    v_nombre text;
  409    v_previo text;
  410  begin
  411    if coalesce(current_setting('gestion_diaria.banco', true), '') <> 'on' then
  412      raise exception 'Los mutantes solo corren en el banco (set gestion_diaria.banco = on)';
  413    end if;
  414    -- Un gate en rojo detecta cualquier mutante en vacío: se exige verde antes de mutar.
  415    begin
  416      v_previo := private.assert_gestion_diaria_analista();
  417    exception when others then
  418      raise exception 'GATE EN ROJO antes de mutar (mutantes no concluyentes): %', sqlerrm;
  419    end;
  420    for v_nombre, v_mutacion in select * from (values
  421      ('1 ayudante invoker',          'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) security invoker'),
  422      ('2 ayudante para anon',        'grant execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) to anon'),
  423      ('3 ayudante volatile',         'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) volatile'),
  424      ('4 ayudante sin search_path',  'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) reset search_path'),
  425      ('5 ayudante sin EXECUTE',      'revoke execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) from authenticated'),
  426      ('6 ayudante borrado',          'drop function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[])'),
  427      ('7 ayudante sin espejo de visibilidad', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_en >= p_ini and g.creado_en < p_fin and coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2 from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false) and private.resolver_en_puertas_bajo_candado() and private.puede_acceder_crm() $b$$m$),
  428      ('8 ayudante sin bandera de postventa', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_por in (select private.vendedor_ids_visibles((select auth.uid()))) and private.puede_acceder_crm() and g.creado_en >= p_ini and g.creado_en < p_fin $b$$m$),
  429      ('9 ayudante con contador crudo', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_por in (select private.vendedor_ids_visibles((select auth.uid()))) and private.puede_acceder_crm() and coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2 from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false) and private.resolver_en_puertas_bajo_candado() and g.creado_en >= p_ini and g.creado_en < p_fin and (select cou$m$ || $m$nt(*) from crm.tareas t where t.id = g.tarea_id) = 1 $b$$m$),
  430      ('10 lector solo leads',        $m$create or replace function private.gestion_diaria_llamadas_eventos(p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[]) returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz, resultado text,util boolean,hora integer) language sql stable security invoker set search_path='' as $b$ select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en, coalesce(a.metadata->>'resultado','sin_resultado'), coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'), extract(hour from a.creado_en at time zone 'America/Lima')::integer from crm.actividades a where (a.creado_por=any(p_vendedor_ids) or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null)) and a.tipo in ('llamada_realizada','llamada_no_contestada') and a.creado_en>=p_ini and a.creado_en<p_fin $b$$m$),
  431      ('11 agregador cuenta el nulo', $m$create or replace function private.gestion_diaria_llamadas(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamptz, ultima_llamada_en timestamptz, por_resultado jsonb, por_hora jsonb) language sql stable security invoker set search_path to '' as $b$ select v.id, 0, 0, 0, cardinality(array_agg(distinct l.lead_id)), 0, null::timestamptz, null::timestamptz, '{}'::jsonb, '[]'::jsonb from unnest(p_vendedor_ids) v(id) left join private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids) l on l.vendedor_id is not distinct from v.id group by v.id $b$$m$)
  432    ) as m(nombre, sql) loop
  433      begin
  434        begin
  435          execute v_mutacion;
  436        exception when others then
  437          raise exception 'MUTANTE % NO APLICABLE: %', v_nombre, sqlerrm;
  438        end;
  439        perform private.assert_gestion_diaria_analista();
  440        raise exception 'MUTANTE % NO DETECTADO: paso el gate', v_nombre;
  441      exception when others then
  442        if sqlerrm like 'MUTANTE %' then raise; end if;
  443        v_detectados := v_detectados + 1;
  444      end;
  445    end loop;
  446    return format('OK: %s mutantes detectados por private.assert_gestion_diaria_analista()', v_detectados);
  447  end;
  448  $function$;
  449  comment on function private.assert_gestion_diaria_llamadas_clientes_mutantes() is
  450    'Mutantes del ayudante de llamadas a clientes de Gestión Diaria (solo banco, exige set gestion_diaria.banco = on): se niega si el gate ya está en rojo (detección en vacío); cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta o si la mutación no aplica.';
  451  revoke all on function private.assert_gestion_diaria_llamadas_clientes_mutantes() from public, anon, authenticated, service_role;
  452  
  453  -- ── POSTFLIGHT ────────────────────────────────────────────────────────────────
  454  do $postflight$
  455  declare
  456    v_id oid := to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])');
  457    v_gate text := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  458    v_msg text;
  459  begin
  460    -- Forma y ACL del ayudante; huellas de lo instalado = lo que sella el gate.
  461    if v_id is null or not exists (select 1 from pg_proc p where p.oid = v_id and p.prosecdef and p.provolatile = 's'
  462                                     and p.proowner = 'postgres'::regrole::oid and p.proconfig @> array['search_path=""']) then
  463      raise exception 'POSTFLIGHT llamadas_clientes: el ayudante no tiene la forma esperada';
  464    end if;
  465    if not has_function_privilege('authenticated', v_id, 'EXECUTE') or has_function_privilege('anon', v_id, 'EXECUTE') then
  466      raise exception 'POSTFLIGHT llamadas_clientes: ACL del ayudante inesperada';
  467    end if;
  468    if v_gate not like '%' || md5(pg_get_functiondef(v_id)) || '%'
  469       or v_gate not like '%' || md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)) || '%'
  470       or v_gate not like '%' || md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure)) || '%' then
  471      raise exception 'POSTFLIGHT llamadas_clientes: el gate no sella las huellas instaladas (ayudante %, lector %, agregador %)',
  472        md5(pg_get_functiondef(v_id)),
  473        md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)),
  474        md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  475    end if;
  476    if v_gate like '%MD5_%PENDIENTE%' then
  477      raise exception 'POSTFLIGHT llamadas_clientes: el gate quedo con placeholders';
  478    end if;
  479    -- El lector devuelve filas de clientes con el contrato esperado (tipo y util coherentes) para cualquier ventana:
  480    -- como postgres (dueño) el ayudante no ve autores (sin sesión), así que aquí solo se prueba que ejecuta.
  481    perform 1 from private.gestion_diaria_llamadas_eventos(now() - interval '1 day', now(), array[gen_random_uuid()]);
  482    if pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure) like '%MD5_%PENDIENTE%'
  483       or pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure) like '%MD5_%PENDIENTE%' then
  484      raise exception 'POSTFLIGHT llamadas_clientes: un gate quedo con placeholders';
  485    end if;
  486    -- El gate de citas (G4b) debe quedar VERDE: sellaba el agregador y no depende del roster.
  487    v_msg := private.assert_gestion_diaria_citas();
  488    raise notice 'POSTFLIGHT llamadas_clientes: gate de citas %', v_msg;
  489    -- Los gates del analista y del pulso: verdes, o rojos SOLO por el roster ajeno (crm.equipo_visible_fn, 15/10;
  490    -- lo re-sella aparte 20261016211001).
  491    begin
  492      v_msg := private.assert_gestion_diaria_analista();
  493      raise notice 'POSTFLIGHT llamadas_clientes: gate del dia del analista %', v_msg;
  494    exception when others then
  495      if sqlerrm like 'El cuerpo de crm.equipo_visible_fn() cambio:%' then
  496        raise notice 'POSTFLIGHT llamadas_clientes: el gate del analista sigue en rojo SOLO por crm.equipo_visible_fn (ajeno, 15/10): %', sqlerrm;
  497      else
  498        raise exception 'POSTFLIGHT llamadas_clientes: el gate del dia del analista esta en rojo por otra causa: %', sqlerrm;
  499      end if;
  500    end;
  501    begin
  502      v_msg := private.assert_gestion_diaria_pulso();
  503      raise notice 'POSTFLIGHT llamadas_clientes: gate del pulso %', v_msg;
  504    exception when others then
  505      if sqlerrm like 'El cuerpo de crm.equipo_visible_fn() cambio:%' then
  506        raise notice 'POSTFLIGHT llamadas_clientes: el gate del pulso sigue en rojo SOLO por crm.equipo_visible_fn (ajeno, 15/10): %', sqlerrm;
  507      elsif sqlerrm like 'Contadores crudos de leads/citas SIN declarar:%' and sqlerrm not like '%llamadas_clientes%'
  508            and sqlerrm not like '%gestion_diaria_llamadas(%' and sqlerrm not like '%gestion_diaria_llamadas_eventos%' then
  509        raise notice 'POSTFLIGHT llamadas_clientes: el gate del pulso sigue en rojo SOLO por el censo analitico ajeno (otras piezas, desde el 01/10): %', sqlerrm;
  510      else
  511        raise exception 'POSTFLIGHT llamadas_clientes: el gate del pulso esta en rojo por otra causa: %', sqlerrm;
  512      end if;
  513    end;
  514  end $postflight$;
  515  
  516  commit;
```

### supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql
```
    1  -- REVERSA de 20261019170422_crm_gestion_diaria_llamadas_clientes.sql
    2  -- Devuelve el lector y el agregador a sus cuerpos de producción del 19/10/2026 (copiados byte a byte del
    3  -- volcado vivo), deshace los tres reemplazos anclados del gate (compone con otros re-sellados del mismo gate) y
    4  -- retira el ayudante y los mutantes. No borra datos: la migración no escribe filas.
    5  begin;
    6  set local lock_timeout = '5s';
    7  set local quote_all_identifiers = off;
    8  
    9  do $reversa$
   10  declare
   11    v_def text;
   12    v_seccion text;
   13    v_md5_ayudante text;
   14    v_md5_lector text;
   15    v_md5_agregador text;
   16  begin
   17    if to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])') is null then
   18      raise exception 'REVERSA llamadas_clientes: no esta instalada';
   19    end if;
   20    v_md5_ayudante := md5(pg_get_functiondef('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
   21    v_md5_lector := md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
   22    v_md5_agregador := md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
   23  
   24    -- 1. El gate: quitar la sección 2b y devolver las dos huellas de producción.
   25    v_def := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
   26    v_seccion := substring(v_def from '  -- 2b\. El ayudante DEFINER de las llamadas a CLIENTES.*?\n\n(?=  -- 3\. La cola de la que bebe la pantalla)');
   27    if v_seccion is null then
   28      raise exception 'REVERSA llamadas_clientes: el gate no trae la seccion 2b con su ancla';
   29    end if;
   30    v_def := replace(v_def, v_seccion, '');
   31    v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   32    v_def := replace(v_def, '''' || v_md5_lector || '''', '''27d25609c74e04c58f82e36af45d7327''');
   33    -- Primera pasada del ensayo (gate instalado con marcadores provisionales): también se devuelven.
   34    v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   35    v_def := replace(v_def, '''MD5_LECTOR_PENDIENTE_000000000000''', '''27d25609c74e04c58f82e36af45d7327''');
   36    if v_def like '%gestion_diaria_llamadas_clientes_eventos%' then
   37      raise exception 'REVERSA llamadas_clientes: el gate sigue nombrando al ayudante';
   38    end if;
   39    execute v_def;
   40    -- Los gates de citas y del pulso: devolver las huellas de producción (también los marcadores de la primera pasada).
   41    v_def := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
   42    v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   43    v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   44    execute v_def;
   45    v_def := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
   46    v_def := replace(v_def, '''' || v_md5_agregador || '''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   47    v_def := replace(v_def, '''' || v_md5_lector || '''', '''27d25609c74e04c58f82e36af45d7327''');
   48    v_def := replace(v_def, '''MD5_AGREGADOR_PENDIENTE_0000000000''', '''7c5d14e65cc0e55e57214589d11e9c9d''');
   49    v_def := replace(v_def, '''MD5_LECTOR_PENDIENTE_000000000000''', '''27d25609c74e04c58f82e36af45d7327''');
   50    execute v_def;
   51  end $reversa$;
   52  comment on function private.assert_gestion_diaria_analista() is
   53    'Trinquete de Gestión Diaria F3 (el día del analista): puerta y núcleos INVOKER con ACL exacta, huellas selladas (puerta, núcleo, agregador, lector, umbrales, roster), cola v2 en su forma y perilla del abandono bajo RLS.';
   54  
   55  -- 2. El lector: cuerpo de producción (20260924201358, vivo el 19/10/2026, md5 27d25609…).
   56  create or replace function private.gestion_diaria_llamadas_eventos(
   57    p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
   58  returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
   59    resultado text,util boolean,hora integer)
   60  language sql stable security invoker set search_path='' as $$
   61    select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
   62      coalesce(a.metadata->>'resultado','sin_resultado'),
   63      coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
   64      extract(hour from a.creado_en at time zone 'America/Lima')::integer
   65    from crm.actividades a where
   66      (a.creado_por=any(p_vendedor_ids)
   67        or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
   68      and a.tipo in ('llamada_realizada','llamada_no_contestada')
   69      and a.creado_en>=p_ini and a.creado_en<p_fin;
   70  $$;
   71  comment on function private.gestion_diaria_llamadas_eventos(timestamptz, timestamptz, uuid[]) is null;
   72  
   73  -- 3. El agregador: cuerpo de producción (vivo el 19/10/2026, md5 7c5d14e6…).
   74  CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
   75   RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
   76   LANGUAGE sql
   77   STABLE
   78   SET search_path TO ''
   79  AS $function$
   80    with vendedores as (
   81      select distinct v.id from unnest(p_vendedor_ids) as v(id)
   82    ),
   83    ll as (
   84      select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
   85    ),
   86    agg as (
   87      select l.vendedor_id,
   88             cardinality(array_agg(l.id)) as llamadas,
   89             -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
   90             -- 100 % aunque una fila histórica llevara un resultado incoherente
   91             -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
   92             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
   93             coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
   94             cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
   95             min(l.creado_en) as primera_llamada_en,
   96             max(l.creado_en) as ultima_llamada_en
   97      from ll l
   98      group by l.vendedor_id
   99    ),
  100    por_resultado as (
  101      select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
  102      from (
  103        select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
  104        from ll l
  105        group by l.vendedor_id, l.resultado
  106      ) r
  107      group by r.vendedor_id
  108    ),
  109    por_hora as (
  110      select h.vendedor_id,
  111             jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
  112      from (
  113        select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
  114               coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
  115        from ll l
  116        group by l.vendedor_id, l.hora
  117      ) h
  118      group by h.vendedor_id
  119    ),
  120    citas as (
  121      -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
  122      -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
  123      -- tarea y cuentan igual que allí.
  124      select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
  125      from crm.tareas t
  126      where (t.vendedor_id in (select v.id from vendedores v)
  127        or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
  128        and t.tipo = 'reunion'
  129        and t.creado_en >= p_ini
  130        and t.creado_en <  p_fin
  131      group by t.vendedor_id
  132    )
  133    select v.id,
  134           coalesce(a.llamadas, 0),
  135           coalesce(a.contestadas, 0),
  136           coalesce(a.utiles, 0),
  137           coalesce(a.leads_tocados, 0),
  138           coalesce(c.citas_agendadas, 0),
  139           a.primera_llamada_en,
  140           a.ultima_llamada_en,
  141           coalesce(r.por_resultado, '{}'::jsonb),
  142           coalesce(h.por_hora, '[]'::jsonb)
  143    from vendedores v
  144    left join agg a on a.vendedor_id is not distinct from v.id
  145    left join por_resultado r on r.vendedor_id is not distinct from v.id
  146    left join por_hora h on h.vendedor_id is not distinct from v.id
  147    left join citas c on c.vendedor_id is not distinct from v.id
  148    order by v.id;
  149  $function$;
  150  comment on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) is
  151    'NÚCLEO (Gestión Diaria): la definición única de llamada (realizada + no contestada), contacto (realizada), útil (resultado ∉ numero_errado/no_es_la_persona; sin resultado cuenta como útil), leads tocados, citas agendadas (tarea reunion creada en la ventana), primera/última llamada, desglose por resultado y por hora Lima, por analista y ventana [p_ini, p_fin). Bajo la RLS del actor; sin contadores crudos.';
  152  
  153  -- 4. Ayudante y mutantes fuera.
  154  drop function private.assert_gestion_diaria_llamadas_clientes_mutantes();
  155  drop function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]);
  156  
  157  do $postflight$
  158  begin
  159    if md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)) <> '27d25609c74e04c58f82e36af45d7327'
  160       or md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure)) <> '7c5d14e65cc0e55e57214589d11e9c9d' then
  161      raise exception 'REVERSA llamadas_clientes: el lector o el agregador no volvieron al cuerpo de produccion (% / %)',
  162        md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)),
  163        md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  164    end if;
  165  end $postflight$;
  166  commit;
```

### supabase/scripts/gestion-diaria-llamadas-clientes/test-gestion-diaria-llamadas-clientes.sql
```
    1  -- Oráculo de «las llamadas a clientes cuentan» (Gestión Diaria, 19/10/2026) sobre el banco.
    2  -- Corre como postgres; las LECTURAS bajo prueba cambian a role authenticated con la identidad del actor en
    3  -- request.jwt.claim.sub (como PostgREST). Siembra un segundo equipo, un cliente con sus tareas y cierres (cirugía
    4  -- del fixture con los triggers de usuario apagados) y UNA llamada a lead por la puerta real; termina con ROLLBACK.
    5  -- Lo ESPERADO se calcula ANTES, como postgres, con la regla escrita a mano (nunca con la función bajo prueba),
    6  -- por DELTAS sobre lo que ya hubiera en el banco. Acaba imprimiendo GESTION_DIARIA_LLAMADAS_CLIENTES_OK o revienta
    7  -- con el nombre de la comprobación.
    8  begin;
    9  set local statement_timeout = '120s';
   10  
   11  -- ── Actores: el equipo 1 lo trae la siembra del banco; el equipo 2 nace aquí ──
   12  create temporary table o_actores on commit drop as
   13  select 'b0000000-0000-4000-8000-000000000002'::uuid as v1,
   14         'b0000000-0000-4000-8000-000000000001'::uuid as sup1,
   15         'b0000000-0000-4000-8000-000000000003'::uuid as ger,
   16         'c0000000-0000-4000-8000-000000000001'::uuid as sup2,
   17         'c0000000-0000-4000-8000-000000000002'::uuid as v2,
   18         'c0000000-0000-4000-8000-000000000009'::uuid as cliente_perfil;
   19  
   20  do $equipo2$
   21  declare a o_actores;
   22  begin
   23    select * into a from o_actores;
   24    if not exists (select 1 from crm.equipo where perfil_id = a.v1 and rol_crm = 'vendedor' and activo and supervisor_id = a.sup1)
   25       or not exists (select 1 from crm.equipo where perfil_id = a.ger and rol_crm = 'gerencia' and activo) then
   26      raise exception 'FIXTURE: falta la siembra del banco (v1 bajo sup1, gerencia)';
   27    end if;
   28    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
   29                            confirmation_token, recovery_token, email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data)
   30    values (a.sup2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.sup2@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}'),
   31           (a.v2,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.v2@avancecorp.test',   '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}'),
   32           (a.cliente_perfil, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.cliente@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}');
   33    insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
   34    values (a.sup2, 'ORACULO SUPERVISOR 2', 'analista', true, 'DNI', false, false, false),
   35           (a.v2,   'ORACULO VENDEDOR 2',   'analista', true, 'DNI', false, false, false),
   36           (a.cliente_perfil, 'ORACULO CLIENTE', 'cliente', true, 'DNI', false, false, false);
   37    insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (a.sup2, 'supervisor', null, true);
   38    insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (a.v2, 'vendedor', a.sup2, true);
   39  end $equipo2$;
   40  
   41  -- ── Ventana Lima de hoy ───────────────────────────────────────────────────────
   42  create temporary table o_ventana on commit drop as
   43  select ((now() at time zone 'America/Lima')::date) as hoy,
   44         (((now() at time zone 'America/Lima')::date)::timestamp) at time zone 'America/Lima' as ini,
   45         (((now() at time zone 'America/Lima')::date + 1)::timestamp) at time zone 'America/Lima' as fin;
   46  
   47  -- ── Lo esperado ANTES de escribir (regla escrita a mano) ──────────────────────
   48  create temporary table o_base on commit drop as
   49  with leads as (
   50    select a.id, a.tipo, coalesce(a.metadata->>'resultado', 'sin_resultado') as resultado,
   51           coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona') as util, a.lead_id
   52    from crm.actividades a, o_ventana w, o_actores o
   53    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
   54  ), clientes as (
   55    select g.id,
   56           case when coalesce(g.metadata->>'resultado', 'sin_resultado') in ('no_contesto', 'numero_errado', 'no_es_la_persona') then 'llamada_no_contestada' else 'llamada_realizada' end as tipo,
   57           coalesce(g.metadata->>'resultado', 'sin_resultado') as resultado,
   58           coalesce(g.metadata->>'resultado', 'sin_resultado') not in ('numero_errado', 'no_es_la_persona', 'sin_resultado') as util
   59    from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id, o_ventana w, o_actores o
   60    where g.tipo = 'cierre' and g.creado_por = o.v1 and g.creado_en >= w.ini and g.creado_en < w.fin
   61      and coalesce(g.metadata->>'tipo_tarea', t.tipo) = 'llamada' and coalesce(g.metadata->>'estado', t.estado) = 'completada'
   62    union all
   63    select a.id, a.tipo, 'sin_resultado', true
   64    from crm.actividades_cliente a, o_ventana w, o_actores o
   65    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
   66      and not exists (select 1 from crm.inversionista_gestiones g where g.tarea_id = a.tarea_id and g.tipo = 'cierre')
   67  ), todo as (
   68    select id, tipo, resultado, util, lead_id from leads
   69    union all select id, tipo, resultado, util, null from clientes
   70  )
   71  select (select coalesce(cardinality(array_agg(id)), 0) from todo) as llamadas,
   72         (select coalesce(cardinality(array_agg(id) filter (where tipo = 'llamada_realizada' and util)), 0) from todo) as contestadas,
   73         (select coalesce(cardinality(array_agg(id) filter (where util)), 0) from todo) as utiles,
   74         (select coalesce(cardinality(array_agg(distinct lead_id) filter (where lead_id is not null)), 0) from todo) as leads_tocados,
   75         (select coalesce(cardinality(array_agg(id)), 0) from leads) as llamadas_leads,
   76         (select coalesce(cardinality(array_agg(id)), 0) from clientes) as llamadas_clientes,
   77         (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select resultado as k, cardinality(array_agg(id)) as n from todo group by 1) r) as por_resultado;
   78  
   79  -- ── Fixture del cliente: tareas y cierres de postventa (cirugía con triggers apagados) ─
   80  create temporary table o_ids (k text primary key, v uuid) on commit drop;
   81  do $cliente$
   82  declare
   83    a o_actores; w o_ventana; v_inv1 uuid := gen_random_uuid(); v_inv2 uuid := gen_random_uuid();
   84    v_t uuid; v_i integer; v_res text; v_ts timestamptz;
   85    -- (clave, tipo de tarea, estado, resultado, momento) — v1 salvo T14
   86    v_casos text[][] := array[
   87      ['T1',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
   88      ['T2',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
   89      ['T3',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
   90      ['T4',  'llamada',  'completada', 'volver_a_llamar', 'ahora'],
   91      ['T5',  'llamada',  'completada', 'volver_a_llamar', 'ahora'],
   92      ['T6',  'llamada',  'completada', 'no_contesto',     'ahora'],
   93      ['T7',  'llamada',  'completada', 'numero_errado',   'ahora'],
   94      ['T8',  'llamada',  'cancelada',  null,              'ahora'],
   95      ['T9',  'reunion',  'completada', null,              'ahora'],
   96      ['T10', 'whatsapp', 'completada', 'respondio',       'ahora'],
   97      ['T11', 'llamada',  'completada', null,              'ahora'],
   98      ['T12', 'llamada',  'completada', 'volver_a_llamar', 'ayer'],
   99      ['T13', 'llamada',  'completada', 'no_contesto',     'inicio'],
  100      ['T14', 'llamada',  'completada', 'agendo_reunion',  'ahora']
  101    ];
  102  begin
  103    select * into a from o_actores;
  104    select * into w from o_ventana;
  105    alter table crm.inversionistas disable trigger user;
  106    alter table crm.tareas disable trigger user;
  107    alter table crm.inversionista_gestiones disable trigger user;
  108    alter table crm.actividades_cliente disable trigger user;
  109    insert into crm.inversionistas (id, estado, responsable_relacion_id, creado_por) values (v_inv1, 'activo', a.v1, a.ger), (v_inv2, 'activo', a.v2, a.ger);
  110    insert into o_ids values ('inv1', v_inv1), ('inv2', v_inv2);
  111    for v_i in 1..array_length(v_casos, 1) loop
  112      v_t := gen_random_uuid();
  113      v_res := v_casos[v_i][4];
  114      v_ts := case v_casos[v_i][5] when 'ahora' then now() when 'ayer' then w.ini - interval '1 second' else w.ini end;
  115      insert into crm.tareas (id, inversionista_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_por, creado_en, postventa_revision,
  116                              cancelada_por, resultado_reunion)
  117      values (v_t, case when v_casos[v_i][1] = 'T14' then v_inv2 else v_inv1 end,
  118              case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end,
  119              v_casos[v_i][2], 'Oraculo ' || v_casos[v_i][1], v_ts - interval '1 hour', v_casos[v_i][3], true,
  120              case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end, v_ts - interval '2 hours', 2,
  121              case when v_casos[v_i][3] = 'cancelada' then 'asesor' end,
  122              case when v_casos[v_i][2] = 'reunion' and v_casos[v_i][3] = 'completada' then 'sin_clasificar' end);
  123      insert into crm.inversionista_gestiones (inversionista_id, tarea_id, tipo, detalle, metadata, creado_por, creado_en)
  124      values (case when v_casos[v_i][1] = 'T14' then v_inv2 else v_inv1 end, v_t, 'cierre', 'Oraculo ' || v_casos[v_i][1],
  125              jsonb_strip_nulls(jsonb_build_object('estado', v_casos[v_i][3], 'tipo_tarea', v_casos[v_i][2],
  126                'resultado', case when v_casos[v_i][2] = 'reunion' then null else v_res end,
  127                'resultado_reunion', case when v_casos[v_i][2] = 'reunion' then 'sin_clasificar' end)),
  128              case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end, v_ts);
  129      insert into o_ids values (v_casos[v_i][1], v_t);
  130    end loop;
  131    -- Legado: A1 cuenta (realizada, sin tarea); A2 NO (su tarea T6 ya tiene cierre F6).
  132    insert into crm.actividades_cliente (cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por, creado_en)
  133    values (a.cliente_perfil, a.v1, null, 'llamada_realizada', 'Oraculo A1 legado', a.v1, now()),
  134           (a.cliente_perfil, a.v1, (select v from o_ids where k = 'T6'), 'llamada_no_contestada', 'Oraculo A2 espejo', a.v1, now());
  135    alter table crm.actividades_cliente enable trigger user;
  136    alter table crm.inversionista_gestiones enable trigger user;
  137    alter table crm.tareas enable trigger user;
  138    alter table crm.inversionistas enable trigger user;
  139  end $cliente$;
  140  
  141  -- ── UNA llamada a lead por la puerta real (como el analista) ─────────────────
  142  create temporary table o_lead (id uuid) on commit drop;
  143  do $lead$
  144  declare a o_actores; v jsonb; v_id uuid := gen_random_uuid(); v_manana date; v_ts timestamptz;
  145  begin
  146    select * into a from o_actores;
  147    perform set_config('request.jwt.claim.sub', a.ger::text, true);
  148    perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  149    v := crm.crear_lead_si_disponible(
  150      p_nombre_completo => 'ORACULO LLAMADAS CLIENTES LEAD', p_telefono => '999677001',
  151      p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
  152      p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
  153      p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v1, p_nota => 'fixture del oraculo', p_telefono_alternativo => null);
  154    insert into o_lead select l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v1 and l.activo;
  155    if not exists (select 1 from o_lead) then raise exception 'FIXTURE: no se pudo crear el lead (%)', v; end if;
  156    perform set_config('request.jwt.claim.sub', a.v1::text, true);
  157    perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  158    v_manana := ((now() at time zone 'America/Lima')::date + 1);
  159    if extract(isodow from v_manana) = 7 then v_manana := v_manana + 1; end if;
  160    v_ts := (v_manana + time '10:00') at time zone 'America/Lima';
  161    v := crm.registrar_llamada_v3(gen_random_uuid(), v_id, 'volver_a_llamar', null, 'Pide que la llamen manana',
  162           jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts));
  163    if (v->>'ok')::boolean is not true then raise exception 'LEAD: %', v; end if;
  164  end $lead$;
  165  
  166  grant select on o_actores, o_ventana, o_base, o_ids, o_lead to authenticated;
  167  
  168  -- ── Lecturas bajo la RLS ──────────────────────────────────────────────────────
  169  -- Delta esperado para v1: clientes +10 llamadas (T1–T7, T11, T13, A1), +6 contestadas (T1–T5, A1), +8 útiles
  170  -- (T1–T6, T13, A1); lead +1/+1/+1 y +1 lead tocado. Total: +11 llamadas, +7 contestadas, +9 útiles, +1 lead.
  171  -- por_resultado: agendo_reunion +3, volver_a_llamar +3 (2 clientes + 1 lead), no_contesto +2, numero_errado +1,
  172  -- sin_resultado +2 (T11 y A1).
  173  do $lecturas$
  174  declare
  175    a o_actores; b o_base; w o_ventana; r jsonb; m jsonb; v_n integer; v_c integer; v_k text; v_fila jsonb; v_pct numeric;
  176  begin
  177    select * into a from o_actores; select * into b from o_base; select * into w from o_ventana;
  178  
  179    -- 1. El analista v1 ve su día con las llamadas a clientes dentro.
  180    perform set_config('request.jwt.claim.sub', a.v1::text, true);
  181    perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  182    set local role authenticated;
  183    r := crm.gestion_diaria_analista_fn();
  184    reset role;
  185    m := r->'marcador';
  186    v_pct := round(100.0 * (b.contestadas + 7) / (b.utiles + 9));
  187    if (m->>'llamadas')::int <> b.llamadas + 11 or (m->>'contestadas')::int <> b.contestadas + 7 or (m->>'utiles')::int <> b.utiles + 9
  188       or (m->>'leads_tocados')::int <> b.leads_tocados + 1 or (m->>'tasa_contacto_pct')::numeric <> v_pct
  189       or m->>'nivel' <> (case when v_pct >= 45 then 'bien' when v_pct >= 25 then 'atencion' else 'bajo' end) then
  190      raise exception '1: marcador inesperado (base %): %', row_to_json(b), m;
  191    end if;
  192    for v_k, v_n in select * from (values ('agendo_reunion', 3), ('volver_a_llamar', 3), ('no_contesto', 2), ('numero_errado', 1), ('sin_resultado', 2)) t loop
  193      if coalesce((m#>>array['por_resultado', v_k])::int, 0) <> coalesce((b.por_resultado->>v_k)::int, 0) + v_n then
  194        raise exception '1: por_resultado[%] esperaba % y trajo %', v_k, coalesce((b.por_resultado->>v_k)::int, 0) + v_n, m->'por_resultado';
  195      end if;
  196    end loop;
  197    select sum((h->>'llamadas')::int), sum((h->>'contestadas')::int) into v_n, v_c from jsonb_array_elements(m->'por_hora') h;
  198    if v_n <> (m->>'llamadas')::int or v_c < (m->>'contestadas')::int or v_c - (m->>'contestadas')::int > (m->>'llamadas')::int - (m->>'utiles')::int then
  199      raise exception '1: por_hora rompe los invariantes del front (suma %, contestadas por hora %): %', v_n, v_c, m;
  200    end if;
  201    if (m->>'primera_llamada_en')::timestamptz > (m->>'ultima_llamada_en')::timestamptz
  202       or (m->>'primera_llamada_en')::timestamptz > w.ini then
  203      raise exception '1: primera/ultima llamada: la de las 00:00 Lima (T13) debio ser la primera: %', m;
  204    end if;
  205    raise notice 'ORACULO: 1 analista en verde';
  206  
  207    -- 2. Su supervisor ve lo mismo en el día del analista y en la vista de equipo (marcador y cortes).
  208    perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  209    perform set_config('request.jwt.claims', json_build_object('sub', a.sup1, 'role', 'authenticated')::text, true);
  210    set local role authenticated;
  211    r := crm.gestion_diaria_analista_fn(null, a.v1);
  212    if (r#>>'{marcador,llamadas}')::int <> b.llamadas + 11 or (r#>>'{marcador,contestadas}')::int <> b.contestadas + 7 then
  213      raise exception '2: el supervisor no ve las llamadas a clientes de su analista: %', r->'marcador';
  214    end if;
  215    r := crm.gestion_diaria_equipo_fn(w.hoy);
  216    select f into v_fila from jsonb_array_elements(r->'equipo') f where (f->>'analista_id')::uuid = a.v1;
  217    if v_fila is null or (v_fila#>>'{marcador,llamadas}')::int <> b.llamadas + 11 or (v_fila#>>'{marcador,contestadas}')::int <> b.contestadas + 7
  218       or v_fila->>'ultima_llamada_en' is null and v_fila#>>'{marcador,ultima_llamada_en}' is null then
  219      raise exception '2: la vista de equipo no trae las llamadas a clientes: %', v_fila;
  220    end if;
  221    select f into v_fila from jsonb_array_elements(r#>'{cortes,equipo}') f where (f->>'analista_id')::uuid = a.v1;
  222    if v_fila is null or coalesce((v_fila#>>'{primer_corte,llamadas}')::int, 0) + coalesce((v_fila#>>'{primer_corte,llamadas_recuperacion}')::int, 0)
  223         + coalesce((v_fila#>>'{segundo_corte,llamadas}')::int, 0) + coalesce((v_fila#>>'{segundo_corte,llamadas_recuperacion}')::int, 0) = 0
  224       and (v_fila#>>'{primer_corte,estado}') <> 'sin_cartera' then
  225      raise exception '2: los cortes de jornada no ven ninguna llamada: %', v_fila;
  226    end if;
  227    -- Paridad con el Registro de clientes: mismas 10 llamadas y 6 contestadas de clientes para v1 hoy.
  228    r := crm.gestiones_resumen_fn(w.hoy, w.hoy, array[a.v1]);
  229    if (r#>>'{totales,clientes,llamadas}')::int <> b.llamadas_clientes + 10 or (r#>>'{totales,clientes,contestadas}')::int < 6 then
  230      raise exception '2: el Registro de clientes y el marcador no cuentan lo mismo: %', r->'totales';
  231    end if;
  232    -- Otro equipo: la puerta lo niega.
  233    begin
  234      perform crm.gestion_diaria_analista_fn(null, a.v2);
  235      raise exception '2: el supervisor 1 leyo un analista del equipo 2';
  236    exception when insufficient_privilege then null;
  237    end;
  238    reset role;
  239    raise notice 'ORACULO: 2 supervisor en verde';
  240  
  241    -- 3. El ayudante es un espejo: filtra, nunca lanza.
  242    --    v2 pidiendo a v1 y a sí mismo: solo lo suyo (T14). sup2 pidiendo a v1: nada. v1 pidiendo a v2: nada suyo ajeno.
  243    perform set_config('request.jwt.claim.sub', a.v2::text, true);
  244    perform set_config('request.jwt.claims', json_build_object('sub', a.v2, 'role', 'authenticated')::text, true);
  245    set local role authenticated;
  246    select cardinality(array_agg(e.id)), cardinality(array_agg(e.id) filter (where e.vendedor_id = a.v1)) into v_n, v_c
  247      from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2, null]) e;
  248    if coalesce(v_n, 0) <> 1 or coalesce(v_c, 0) <> 0 then raise exception '3: v2 vio % filas (% de v1); esperaba 1 y 0', v_n, v_c; end if;
  249    reset role;
  250    perform set_config('request.jwt.claim.sub', a.sup2::text, true);
  251    perform set_config('request.jwt.claims', json_build_object('sub', a.sup2, 'role', 'authenticated')::text, true);
  252    set local role authenticated;
  253    select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  254    if coalesce(v_n, 0) <> 0 then raise exception '3: el supervisor 2 vio % llamadas a clientes de v1', v_n; end if;
  255    select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v2]) e;
  256    if coalesce(v_n, 0) <> 1 then raise exception '3: el supervisor 2 debio ver la unica de su analista (vio %)', v_n; end if;
  257    reset role;
  258    perform set_config('request.jwt.claim.sub', a.v1::text, true);
  259    perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  260    set local role authenticated;
  261    select cardinality(array_agg(e.id)), cardinality(array_agg(e.id) filter (where e.vendedor_id <> a.v1)) into v_n, v_c
  262      from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2]) e;
  263    if coalesce(v_n, 0) <> b.llamadas_clientes + 10 or coalesce(v_c, 0) <> 0 then raise exception '3: v1 vio % filas (% ajenas)', v_n, v_c; end if;
  264    reset role; -- las comprobaciones fila a fila cruzan tablas privadas: como postgres, con la identidad de v1 (el ayudante lee auth.uid())
  265    -- Clasificación fila a fila (T7 número errado: no contestada y no útil; T11 sin resultado: realizada y no útil; A1 legado: contacto).
  266    if not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
  267                   join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id = (select v from o_ids where k = 'T7')
  268                     and e.tipo = 'llamada_no_contestada' and e.util is false and e.resultado = 'numero_errado')
  269       or not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
  270                   join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id = (select v from o_ids where k = 'T11')
  271                     and e.tipo = 'llamada_realizada' and e.util is false and e.resultado = 'sin_resultado')
  272       or not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
  273                   join crm.actividades_cliente ac on ac.id = e.id where ac.detalle = 'Oraculo A1 legado'
  274                     and e.tipo = 'llamada_realizada' and e.util is true)
  275       or exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
  276                   join crm.actividades_cliente ac on ac.id = e.id where ac.detalle = 'Oraculo A2 espejo')
  277       or exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
  278                   join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id in (select v from o_ids where k in ('T8', 'T9', 'T10', 'T12'))) then
  279      raise exception '3: la clasificacion fila a fila no es la esperada';
  280    end if;
  281    if exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e where e.lead_id is not null) then
  282      raise exception '3: una llamada a cliente trae lead_id';
  283    end if;
  284    reset role;
  285    raise notice 'ORACULO: 3 espejo de visibilidad en verde';
  286  
  287    -- 4. Gerencia ve a los dos; Pulso y Hábitos ejecutan.
  288    perform set_config('request.jwt.claim.sub', a.ger::text, true);
  289    perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  290    set local role authenticated;
  291    select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2]) e;
  292    if coalesce(v_n, 0) <> b.llamadas_clientes + 11 then raise exception '4: gerencia vio % (esperaba %)', v_n, b.llamadas_clientes + 11; end if;
  293    r := crm.gestion_diaria_analista_fn(null, a.v1);
  294    if (r#>>'{marcador,llamadas}')::int <> b.llamadas + 11 then raise exception '4: gerencia no ve el dia de v1 completo: %', r->'marcador'; end if;
  295    r := crm.gestion_diaria_pulso_fn(w.hoy);
  296    if r is null or r->'generado_en' is null and r->'dia' is null then raise exception '4: pulso vacio: %', r; end if;
  297    r := crm.gestion_diaria_habitos_fn(w.hoy, 7);
  298    if r is null then raise exception '4: habitos vacio'; end if;
  299    reset role;
  300    raise notice 'ORACULO: 4 gerencia, pulso y habitos en verde';
  301  
  302    -- 5. Sin sesión: nada. Con la postventa apagada: las llamadas a clientes desaparecen del marcador.
  303    perform set_config('request.jwt.claim.sub', '', true);
  304    perform set_config('request.jwt.claims', '', true);
  305    select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  306    if coalesce(v_n, 0) <> 0 then raise exception '5: sin sesion el ayudante devolvio % filas', v_n; end if;
  307    alter table crm.multiempresa_flags disable trigger user;
  308    update crm.multiempresa_flags set activo = false, actualizado_por = null where nombre = 'postventa_neutral'; -- actualizado_por: la copia de configuración trae un perfil que no existe en el banco
  309    alter table crm.multiempresa_flags enable trigger user;
  310    perform set_config('request.jwt.claim.sub', a.v1::text, true);
  311    perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  312    set local role authenticated;
  313    r := crm.gestion_diaria_analista_fn();
  314    reset role;
  315    if (r#>>'{marcador,llamadas}')::int <> b.llamadas_leads + 1 then
  316      raise exception '5: con la postventa apagada el marcador debio traer solo leads (%): %', b.llamadas_leads + 1, r->'marcador';
  317    end if;
  318    alter table crm.multiempresa_flags disable trigger user;
  319    update crm.multiempresa_flags set activo = true, actualizado_por = null where nombre = 'postventa_neutral';
  320    alter table crm.multiempresa_flags enable trigger user;
  321    raise notice 'ORACULO: 5 sin sesion y bandera en verde';
  322  end $lecturas$;
  323  
  324  select 'GESTION_DIARIA_LLAMADAS_CLIENTES_OK' as resultado;
  325  rollback;
```

### supabase/scripts/gestion-diaria-llamadas-clientes/ensayar.mjs
```
    1  // Ensayo completo de «las llamadas a clientes cuentan» (Gestión Diaria, 19/10/2026) sobre el banco propio:
    2  // 1) foto ANTES (huellas = producción, estado de los gates, censo analítico); 2) SELLADO en dos pasadas (la
    3  // migración con placeholders instala sin postflight, se miden las tres huellas y se escriben en el archivo, se
    4  // deshace con la reversa); 3) instalación real; 4) en el banco SE SIMULA el re-sellado ajeno pendiente
    5  // (20261016211001: huellas de crm.equipo_visible_fn en el gate del analista y de private.trg_sla_recibo_guard en
    6  // el gate del resultado) para que el gate esté VERDE y los mutantes sean concluyentes; 5) gate, mutantes nuevos
    7  // (11) y viejos (24), oráculo, censo intacto; 6) reversa → huellas de producción, reinstalación determinista.
    8  // Nunca toca producción: banco.mjs fija contenedor y base.
    9  import { existsSync, readFileSync, writeFileSync } from 'node:fs';
   10  import assert from 'node:assert/strict';
   11  import { createHash } from 'node:crypto';
   12  import { db, contenedor, sql, ejecutar, md5Vivo, existe } from './banco.mjs';
   13  
   14  const VERSION = '20261019170422';
   15  const NOMBRE = 'crm_gestion_diaria_llamadas_clientes';
   16  const rutaMigracion = new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url);
   17  const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
   18  const reversa = leer('./reversa.sql');
   19  const oraculo = leer('./test-gestion-diaria-llamadas-clientes.sql');
   20  
   21  const AYUDANTE = 'private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])';
   22  const LECTOR = 'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])';
   23  const AGREGADOR = 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])';
   24  const GATE = 'private.assert_gestion_diaria_analista()';
   25  const MUTANTES = 'private.assert_gestion_diaria_llamadas_clientes_mutantes()';
   26  // Huellas vivas en producción el 19/10/2026 (medidas por pg_get_functiondef, iguales en el banco).
   27  const PROD = {
   28    lector: '27d25609c74e04c58f82e36af45d7327',
   29    agregador: '7c5d14e65cc0e55e57214589d11e9c9d',
   30    gate: 'eb2c03fd99f13cda077f8c02e4533ec4',
   31    citas: '12012959d2e751c43df86b847dcce037',
   32    pulso: 'bdccbb6e3fee574416a0987941ae344b',
   33    equipoVisible: '58bd05540d2a3eb576a7b648978707e7',
   34    equipoVisibleSellado: '200162f4519586a6c68d8ccf0cf591f7',
   35    trgRecibo: 'f111fdd9d8eb904fde961c6dcc7a9a9a',
   36  };
   37  const gate = () => { const r = ejecutar(`select ${GATE}`); return r.status === 0 ? r.stdout.trim() : 'ROJO: ' + (r.stderr.match(/ERROR:\s+(.*)/)?.[1] ?? r.stderr); };
   38  const censo = () => sql(`select coalesce(string_agg(objeto::text || '|' || declarada::text || '|' || huella_ok::text, ';' order by objeto::text), '') from private.contadores_crudos_leads_citas()`);
   39  const existeHoy = (txt) => sql(`select (${txt})::text`) === 'true';
   40  
   41  console.log(`banco ${contenedor}/${db}`);
   42  assert.equal(sql('select current_database()'), db);
   43  
   44  // 1. Si ya estaba instalada (segunda corrida), se retira con la reversa para ensayar limpio, y se deshacen las
   45  //    simulaciones banco-only de una corrida anterior si quedaron puestas.
   46  const desimular = (firma, viejo, nuevo) => sql(`do $x$ declare d text := pg_get_functiondef('${firma}'::regprocedure); begin
   47    if strpos(d, '${viejo}') > 0 then execute replace(d, '${viejo}', '${nuevo}'); end if; end $x$;`);
   48  if (existe(AYUDANTE)) { sql(reversa); console.log('instalación previa retirada con la reversa'); }
   49  desimular(GATE, PROD.equipoVisible, PROD.equipoVisibleSellado);
   50  desimular('private.assert_gestion_diaria_pulso()', '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado', '  perform private.assert_analitica_leads_citas();');
   51  assert.ok(!existe(AYUDANTE));
   52  assert.equal(md5Vivo(LECTOR), PROD.lector, 'El banco tiene el lector de producción');
   53  assert.equal(md5Vivo(AGREGADOR), PROD.agregador, 'El banco tiene el agregador de producción');
   54  assert.equal(md5Vivo('crm.equipo_visible_fn()'), PROD.equipoVisible, 'El banco tiene el roster vivo (consulta de Coordinación)');
   55  const censoAntes = censo();
   56  assert.equal(md5Vivo(GATE), PROD.gate, 'El banco tiene el gate del analista de producción (eb2c03fd…)');
   57  assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'El banco tiene el gate de citas de producción');
   58  assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'El banco tiene el gate del pulso de producción');
   59  const gateAntes = gate();
   60  console.log(`gate ANTES: ${gateAntes}`);
   61  assert.match(gateAntes, /^ROJO: (P0001: )?El cuerpo de crm\.equipo_visible_fn\(\) cambio/, 'ANTES: el gate está en rojo SOLO por el roster (ajeno, 15/10)');
   62  
   63  // 2. SELLADO en dos pasadas.
   64  let migracion = readFileSync(rutaMigracion, 'utf8');
   65  if (migracion.includes('_PENDIENTE_')) {
   66    const sinPostflight = migracion.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, 'select 1;');
   67    assert.notEqual(sinPostflight, migracion, 'no se encontró el bloque postflight');
   68    sql(sinPostflight);
   69    const sellos = {
   70      MD5_AYUDANTE_CLIENTES_PENDIENTE_00: md5Vivo(AYUDANTE),
   71      MD5_LECTOR_PENDIENTE_000000000000: md5Vivo(LECTOR),
   72      MD5_AGREGADOR_PENDIENTE_0000000000: md5Vivo(AGREGADOR),
   73    };
   74    for (const [k, v] of Object.entries(sellos)) {
   75      assert.match(v, /^[0-9a-f]{32}$/, `md5 de ${k}`);
   76      assert.ok(migracion.includes(k), `placeholder ${k} ausente`);
   77      migracion = migracion.replaceAll(k, v);
   78    }
   79    writeFileSync(rutaMigracion, migracion);
   80    sql(reversa);
   81    assert.ok(!existe(AYUDANTE), 'la instalación provisional se retiró');
   82    assert.equal(md5Vivo(GATE), PROD.gate, 'la reversa devolvió el gate de producción');
   83    assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'la reversa devolvió el gate de citas');
   84    assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'la reversa devolvió el gate del pulso');
   85    console.log(`md5 sellados en la migración: ${Object.values(sellos).join(' ')}`);
   86  }
   87  assert.ok(!migracion.includes('_PENDIENTE_'));
   88  
   89  // 3. Instalación real: el postflight acepta el rojo ajeno del roster.
   90  sql(migracion);
   91  assert.ok(existe(AYUDANTE) && existe(MUTANTES));
   92  const md5 = { ayudante: md5Vivo(AYUDANTE), lector: md5Vivo(LECTOR), agregador: md5Vivo(AGREGADOR), gate: md5Vivo(GATE),
   93    citas: md5Vivo('private.assert_gestion_diaria_citas()'), pulso: md5Vivo('private.assert_gestion_diaria_pulso()') };
   94  assert.match(sql('select private.assert_gestion_diaria_citas()'), /^OK/, 'gate de citas VERDE tras instalar (re-sellado)');
   95  assert.match(gate(), /^ROJO: (P0001: )?El cuerpo de crm\.equipo_visible_fn\(\) cambio/, 'tras instalar: el gate sigue en rojo SOLO por el roster');
   96  assert.match(ejecutar(`set gestion_diaria.banco = on; select ${MUTANTES}`).stderr, /GATE EN ROJO antes de mutar/, 'los mutantes se niegan con el gate en rojo');
   97  
   98  // 4. Simulación BANCO-ONLY del re-sellado ajeno (20261016211001) para poner el gate en verde.
   99  const simular = (firma, viejo, nuevo) => sql(`do $x$ declare d text := pg_get_functiondef('${firma}'::regprocedure); begin
  100    if strpos(d, '${viejo}') = 0 then raise exception 'simulacion: % no trae %', '${firma}', '${viejo}'; end if;
  101    execute replace(d, '${viejo}', '${nuevo}'); end $x$;`);
  102  simular(GATE, PROD.equipoVisibleSellado, PROD.equipoVisible);
  103  assert.match(gate(), /^OK/, 'gate del analista VERDE con el roster re-sellado (simulación de 211001)');
  104  // El pulso también exige el censo analítico, rojo en producción desde el 01/10 por otras 10 piezas ajenas: se
  105  // neutraliza SOLO en el banco (y se deshace antes de comprobar la identidad con producción).
  106  const PULSO = 'private.assert_gestion_diaria_pulso()';
  107  const CENSO_LINEA = '  perform private.assert_analitica_leads_citas();';
  108  const censoRojo = ejecutar('select private.assert_analitica_leads_citas()');
  109  assert.ok(censoRojo.status !== 0 && !/llamadas_clientes|gestion_diaria_llamadas/.test(censoRojo.stderr), 'el censo está rojo solo por piezas ajenas: ' + censoRojo.stderr.split('\n')[0]);
  110  simular(PULSO, CENSO_LINEA, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado');
  111  assert.match(sql(`select ${PULSO}`), /^OK/, 'gate del pulso VERDE (re-sellado + roster simulado + censo ajeno neutralizado)');
  112  const paraguasAntes = ejecutar('select private.assert_gestion_diaria()');
  113  if (paraguasAntes.status !== 0 && /trg_sla_recibo_guard/.test(paraguasAntes.stderr)) {
  114    const viejoTrg = paraguasAntes.stderr.match(/trg_sla_recibo_guard\(\) cambio: [^(]*\(md5 ([0-9a-f]{32})\)/)?.[1];
  115    const sellado = sql(`select substring(prosrc from '''private\\.trg_sla_recibo_guard\\(\\)''[^'']*''([0-9a-f]{32})''') from pg_proc where oid = 'private.assert_gestion_diaria_resultado()'::regprocedure`);
  116    assert.equal(viejoTrg, PROD.trgRecibo);
  117    simular('private.assert_gestion_diaria_resultado()', sellado, PROD.trgRecibo);
  118  }
  119  const paraguas = ejecutar('select private.assert_gestion_diaria()');
  120  console.log(`paraguas tras simular 211001: ${paraguas.status === 0 ? paraguas.stdout.trim() : 'ROJO ' + paraguas.stderr.split('\n')[0]}`);
  121  
  122  // 5. Mutantes nuevos y viejos, oráculo, censo.
  123  const mutantesNuevos = sql(`set gestion_diaria.banco = on; select ${MUTANTES}`);
  124  assert.match(mutantesNuevos, /^OK: 11 mutantes detectados/, mutantesNuevos);
  125  assert.match(gate(), /^OK/, 'gate tras los mutantes nuevos (nada quedó alterado)');
  126  let mutantesViejos = 'NOT RUN (paraguas en rojo por un guardián ajeno)';
  127  if (paraguas.status === 0) {
  128    mutantesViejos = sql('set gestion_diaria.banco = on; select private.assert_gestion_diaria_analista_mutantes()');
  129    assert.match(mutantesViejos, /^OK: 24 mutantes detectados/, mutantesViejos);
  130  }
  131  assert.match(ejecutar(`select ${MUTANTES}`).stderr, /solo corren en el banco/, 'Sin la marca de banco los mutantes se niegan');
  132  const salida = sql(oraculo);
  133  assert.match(salida, /GESTION_DIARIA_LLAMADAS_CLIENTES_OK/, salida);
  134  assert.equal(censo(), censoAntes, 'El censo analítico no cambia');
  135  
  136  // 6. Reversa (sobre el gate simulado: compone) → lector y agregador de producción; reinstalación determinista.
  137  sql(reversa);
  138  assert.ok(!existe(AYUDANTE) && !existe(MUTANTES), 'La reversa retira el ayudante y los mutantes');
  139  assert.equal(md5Vivo(LECTOR), PROD.lector, 'La reversa devuelve el lector de producción');
  140  assert.equal(md5Vivo(AGREGADOR), PROD.agregador, 'La reversa devuelve el agregador de producción');
  141  assert.match(gate(), /^OK/, 'gate verde tras la reversa (sigue con el roster simulado)');
  142  // Y sobre el gate de producción exacto: deshacer las simulaciones y comprobar la identidad byte a byte.
  143  simular(GATE, PROD.equipoVisible, PROD.equipoVisibleSellado);
  144  simular(PULSO, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado', CENSO_LINEA);
  145  assert.equal(md5Vivo(GATE), PROD.gate, 'La reversa + deshacer la simulación devuelven el gate EXACTO de producción');
  146  assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'La reversa devuelve el gate de citas EXACTO de producción');
  147  assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'La reversa devuelve el gate del pulso EXACTO de producción');
  148  sql(migracion);
  149  assert.equal(md5Vivo(AYUDANTE), md5.ayudante, 'La reinstalación es determinista (ayudante)');
  150  assert.equal(md5Vivo(LECTOR), md5.lector, 'La reinstalación es determinista (lector)');
  151  assert.equal(md5Vivo(AGREGADOR), md5.agregador, 'La reinstalación es determinista (agregador)');
  152  assert.equal(md5Vivo(GATE), md5.gate, 'La reinstalación es determinista (gate)');
  153  assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), md5.citas, 'La reinstalación es determinista (citas)');
  154  assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), md5.pulso, 'La reinstalación es determinista (pulso)');
  155  simular(GATE, PROD.equipoVisibleSellado, PROD.equipoVisible);
  156  assert.match(gate(), /^OK/, 'gate verde reinstalado (roster simulado)');
  157  simular(PULSO, CENSO_LINEA, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado');
  158  assert.match(sql(`select ${PULSO}`), /^OK/, 'pulso verde reinstalado (simulaciones del banco)');
  159  
  160  const verificacion = {
  161    version: VERSION, nombre: NOMBRE, banco: `${contenedor}/${db}`, ensayado_en: new Date().toISOString(),
  162    md5_ayudante: md5.ayudante, md5_lector: md5.lector, md5_agregador: md5.agregador, md5_gate: md5.gate, md5_gate_citas: md5.citas, md5_gate_pulso: md5.pulso,
  163    md5_gate_produccion_antes: PROD.gate,
  164    sha256_migracion: createHash('sha256').update(migracion).digest('hex'),
  165    sha256_reversa: createHash('sha256').update(reversa).digest('hex'),
  166    gate_antes: gateAntes, mutantes_nuevos: mutantesNuevos, mutantes_viejos: mutantesViejos,
  167    paraguas_con_211001_simulado: paraguas.status === 0 ? paraguas.stdout.trim() : 'ROJO',
  168    oraculo: 'GESTION_DIARIA_LLAMADAS_CLIENTES_OK', censo_intacto: true, reversa_a_produccion: true,
  169  };
  170  writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify(verificacion, null, 2) + '\n');
  171  console.log(`ENSAYO OK · ${mutantesNuevos} · viejos: ${mutantesViejos} · ayudante ${md5.ayudante} · lector ${md5.lector} · agregador ${md5.agregador} · gate ${md5.gate}`);
```

### verificacion.json
```
{
  "version": "20261019170422",
  "nombre": "crm_gestion_diaria_llamadas_clientes",
  "banco": "crm-banco-llamadas-clientes-20261019/postgres",
  "ensayado_en": "2026-10-19T17:28:51.659Z",
  "md5_ayudante": "1e4618d5810b64d543aadd89fa31013b",
  "md5_lector": "a209ec1be82b2eeff40c7f6488342d69",
  "md5_agregador": "1325886469e34ee651d69672ca1a72c5",
  "md5_gate": "a67f362d9e56094f26ad72bf3b96a070",
  "md5_gate_citas": "08c1b8ce4b3ae936b5c72ba8755f2c95",
  "md5_gate_pulso": "79b9ca5f88ded3ed2f4c516d02bee598",
  "md5_gate_produccion_antes": "eb2c03fd99f13cda077f8c02e4533ec4",
  "sha256_migracion": "e38106afa904236ea468911fbb93b085d12cbdf68d799298b0c7637caf80c69e",
  "sha256_reversa": "e939781dacc31552d6dace55de9c0b49ed6ebff27d7e8635d13936290be7fee1",
  "gate_antes": "ROJO: P0001: El cuerpo de crm.equipo_visible_fn() cambio: re-sellar el dia del analista de Gestion Diaria (md5 58bd05540d2a3eb576a7b648978707e7)",
  "mutantes_nuevos": "OK: 11 mutantes detectados por private.assert_gestion_diaria_analista()",
  "mutantes_viejos": "OK: 24 mutantes detectados por private.assert_gestion_diaria()",
  "paraguas_con_211001_simulado": "OK: Gestion Diaria [OK: registro de Gestion Diaria bajo la RLS (puerta y nucleo INVOKER), EXECUTE solo authenticated, indice presente, policies selladas por la base del historial por lead] [OK: resultado de llamada — puertas DEFINER selladas (EXECUTE solo authenticated), nucleo y trigger solo postgres, CHECK de forma validado, trigger anti-falsificacion habilitado, cuerpos propios y compuestos con su md5, historial por lead con metadata] [OK: dia del analista — puerta y nucleos INVOKER (EXECUTE solo authenticated) con su md5, sin contadores crudos, cola v2 y politica_abandono en su forma, cadena invoker con sus permisos, tareas_select sellada por la base de las tareas por cursor] [OK: equipo completo, agregado canónico y acceso por identidad] [OK: cortes Lima, política versionada OFF, RLS sin escrituras API] [OK: avisos persistentes sellados, RLS del lector y entregas únicas] [OK: configuración gerencial estricta, versionada y futura; control de avisos auditado] [OK: pendientes SLA agrupados y contexto de llamadas bajo RLS; tasa baja OFF] [OK: lectura completa bajo RLS; escrituras de cortes sin cómputo SLA] [OK: pendientes H3 paginados, ámbito canónico compartido, invoker/RLS y referencias mínimas] [OK: citas G4b INVOKER con ACL exacta (postgres y authenticated), misma definición que la cifra y fuentes del pulso selladas]",
  "oraculo": "GESTION_DIARIA_LLAMADAS_CLIENTES_OK",
  "censo_intacto": true,
  "reversa_a_produccion": true
}
```

## FUNCIONES VIVAS DE REFERENCIA (producción = banco)

### private_gestiones_clientes_eventos_date_date_uuid___boolean_integer_text___timestamptz_uuid_text_ (pg_get_functiondef vivo)
```
    1  CREATE OR REPLACE FUNCTION private.gestiones_clientes_eventos(p_desde date, p_hasta date, p_autores uuid[] DEFAULT NULL::uuid[], p_detalles boolean DEFAULT true, p_limite integer DEFAULT 500, p_tipos text[] DEFAULT NULL::text[], p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_antes_origen text DEFAULT NULL::text)
    2   RETURNS TABLE(id uuid, origen text, identidad jsonb, tipo text, detalle text, metadata jsonb, creado_por uuid, autor_nombre text, creado_en timestamp with time zone, operativa boolean, contacto boolean)
    3   LANGUAGE plpgsql
    4   SECURITY DEFINER
    5   SET search_path TO ''
    6  AS $function$
    7  declare v_ids uuid[]; v_f6 boolean; v_limite integer;
    8  begin
    9    perform private.gestiones_validar(p_desde,p_hasta,p_autores);
   10    if p_detalles is null or p_limite is null or p_limite not between 1 and 500 then
   11      raise exception 'Página de gestiones inválida' using errcode='22023'; end if;
   12    -- Los conteos recorren todas las filas autorizadas, sin resolver identidad ni PII.
   13    v_limite:=case when p_detalles then p_limite end;
   14    select array_agg(x) into v_ids from private.vendedor_ids_visibles(auth.uid()) x
   15      where p_autores is null or x=any(p_autores);
   16    v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
   17    return query
   18    with eventos as (
   19      select g.id,'postventa'::text origen,g.inversionista_id persona,null::uuid perfil,g.tarea_id,
   20        g.creado_por,g.creado_en,case when p_detalles then g.detalle end detalle,
   21        coalesce(g.metadata->>'tipo_tarea',t.tipo) tarea_tipo,
   22        coalesce(g.metadata->>'estado',t.estado) estado,
   23        coalesce(g.metadata->>'resultado','sin_resultado') resultado,
   24        coalesce(g.metadata->>'resultado_reunion',t.resultado_reunion,'sin_clasificar') resultado_reunion,
   25        null::text tipo_legacy
   26      from crm.inversionista_gestiones g join crm.tareas t on t.id=g.tarea_id
   27      where v_f6 and g.tipo='cierre' and g.creado_por=any(v_ids)
   28        and g.creado_en>=p_desde::timestamp at time zone 'America/Lima'
   29        and g.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
   30      union all
   31      select a.id,'perfil',null,a.cliente_id,a.tarea_id,a.creado_por,a.creado_en,case when p_detalles then a.detalle end,
   32        t.tipo,coalesce(t.estado,'completada'),'sin_resultado',coalesce(t.resultado_reunion,'sin_clasificar'),a.tipo
   33      from crm.actividades_cliente a left join crm.tareas t on t.id=a.tarea_id
   34      where a.creado_por=any(v_ids)
   35        and a.creado_en>=p_desde::timestamp at time zone 'America/Lima'
   36        and a.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
   37        -- Los espejos F6 no se convierten en una vía heredada al apagar la bandera.
   38        and not exists(select 1 from crm.inversionista_gestiones g where g.tarea_id=a.tarea_id and g.tipo='cierre')
   39    ), clasificados as (
   40      select e.*,coalesce(e.tipo_legacy,case when e.estado='completada' then
   41        case e.tarea_tipo when 'llamada' then case when e.resultado in ('no_contesto','numero_errado','no_es_la_persona') then 'llamada_no_contestada' else 'llamada_realizada' end
   42          when 'whatsapp' then case when e.resultado='respondio' then 'whatsapp_recibido' else 'whatsapp_enviado' end
   43          when 'reunion' then 'reunion_realizada' else 'nota' end else 'nota' end) clase
   44      from eventos e
   45    ), pagina as materialized (
   46      select e.* from clasificados e
   47      where (p_tipos is null or e.clase=any(p_tipos))
   48        and (p_antes_de is null or e.creado_en<p_antes_de
   49          or (e.creado_en=p_antes_de and (e.origen,e.id)>(p_antes_origen,p_antes_id)))
   50      order by e.creado_en desc,e.origen,e.id limit v_limite
   51    ), sujetos as materialized (
   52      select * from private.gestiones_clientes_identidades(coalesce((select jsonb_agg(to_jsonb(e))
   53        from (select distinct e.persona,e.perfil from pagina e where p_detalles) e),'[]'))
   54    )
   55    select e.id,e.origen,s.identidad,e.clase,
   56      case when (s.identidad->>'identidad_visible')::boolean then e.detalle end,
   57      case when p_detalles then jsonb_build_object('resultado',case when e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') then e.resultado end,
   58        'resultado_reunion',case when e.clase='reunion_realizada' then e.resultado_reunion end,'estado',e.estado,
   59        'tarea_id',case when (s.identidad->>'identidad_visible')::boolean then e.tarea_id end,
   60        'resultado_origen',case when (e.clase='reunion_realizada' and e.resultado_reunion='sin_clasificar')
   61          or (e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') and e.resultado='sin_resultado')
   62          then 'legacy_sin_resultado' else 'declarado' end) end,
   63      e.creado_por,case when p_detalles then coalesce(private.nombre_de_autor(e.creado_por),'—') end,e.creado_en,
   64      e.estado='completada' and e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota'),
   65      e.clase='llamada_realizada' and (e.tipo_legacy='llamada_realizada' or e.resultado not in ('sin_resultado','numero_errado','no_es_la_persona'))
   66    from pagina e left join sujetos s on s.persona is not distinct from e.persona and s.perfil is not distinct from e.perfil;
   67  end;
   68  $function$
   69  
```

### private_assert_gestion_diaria_analista__ (pg_get_functiondef vivo)
```
    1  CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_analista()
    2   RETURNS text
    3   LANGUAGE plpgsql
    4   STABLE SECURITY DEFINER
    5   SET search_path TO ''
    6  AS $function$
    7  declare
    8    v_firma text;
    9    v_md5 text;
   10    v_id oid;
   11  begin
   12    -- 1. Puerta y núcleos: INVOKER, estables, search_path vacío, owner postgres,
   13    --    EXECUTE exactamente para authenticated (la cadena corre como el actor).
   14    foreach v_firma in array array[
   15      'crm.gestion_diaria_analista_fn(date,uuid)',
   16      'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
   17      'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',
   18      'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])',
   19      'private.gestion_diaria_umbrales()'
   20    ] loop
   21      v_id := to_regprocedure(v_firma);
   22      if v_id is null or not exists (
   23        select 1 from pg_proc p
   24        where p.oid = v_id and not p.prosecdef
   25          and p.proowner = 'postgres'::regrole::oid
   26          and p.provolatile = 's'
   27          and p.proconfig @> array['search_path=""']
   28      ) then
   29        raise exception 'Contrato del dia del analista alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
   30      end if;
   31      if not has_function_privilege('authenticated', v_id, 'EXECUTE')
   32         or exists (
   33           select 1 from pg_proc p
   34           cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   35           where p.oid = v_id
   36             and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
   37         ) then
   38        raise exception 'ACL del dia del analista alterada: %', v_firma;
   39      end if;
   40      -- Ningún contador crudo en los cuerpos propios (trinquete del censo analítico).
   41      if exists (select 1 from pg_proc p where p.oid = v_id
   42                 and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
   43        raise exception 'Una funcion del dia del analista cuenta a crudo: %', v_firma;
   44      end if;
   45    end loop;
   46  
   47    -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).
   48    for v_firma, v_md5 in select * from (values
   49      ('crm.gestion_diaria_analista_fn(date,uuid)',                                                          'ba3d0502ae4bf0d010677562d47634a5'),
   50      ('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',    '4dd5313e606b57485cd105b125f412b7'),
   51      ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',                                    '7c5d14e65cc0e55e57214589d11e9c9d'),
   52      ('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])', '27d25609c74e04c58f82e36af45d7327'),
   53      ('private.gestion_diaria_umbrales()',                                                                   '151860fa342b98d4f2ce9ed7054e390b'),
   54      -- El roster ES la autorización para mirar el día de otro: si alguien lo
   55      -- reescribe, este gate se pone en rojo y hay que re-sellar a conciencia
   56      -- (md5 medido en producción el 20/09/2026).
   57      ('crm.equipo_visible_fn()',                                                                             '200162f4519586a6c68d8ccf0cf591f7')
   58    ) as m(firma, md5) loop
   59      if to_regprocedure(v_firma) is null
   60         or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
   61        raise exception 'El cuerpo de % cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
   62          v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
   63      end if;
   64    end loop;
   65  
   66    -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,
   67    --    search_path vacío, ejecutable por authenticated. (Su cuerpo no se sella
   68    --    aquí: pertenece al mundo SLA; el front valida el contrato de la página.)
   69    v_id := to_regprocedure('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)');
   70    if v_id is null or not exists (
   71      select 1 from pg_proc p
   72      where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
   73        and p.provolatile = 's' and p.proconfig @> array['search_path=""']
   74    ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
   75      raise exception 'crm.cola_accion_v2_fn perdio su forma o su EXECUTE';
   76    end if;
   77  
   78    -- 4. La perilla del abandono: fila única bajo RLS, legible por el actor.
   79    -- La perilla, sellada como las policies de F1: huella de la expresión y el
   80    -- conjunto de permisivas de lectura EXACTO (una permisiva nueva la abriría a
   81    -- quien no debe). Huella medida en producción el 20/09/2026.
   82    if to_regclass('crm.politica_abandono') is null
   83       or not (select relrowsecurity from pg_class where oid = 'crm.politica_abandono'::regclass)
   84       or not has_column_privilege('authenticated', 'crm.politica_abandono', 'dias_abandono', 'SELECT')
   85       or not has_column_privilege('authenticated', 'crm.politica_abandono', 'singleton', 'SELECT') then
   86      raise exception 'crm.politica_abandono perdio su forma (RLS o SELECT de singleton/dias_abandono)';
   87    end if;
   88    if (select md5(pg_get_expr(pol.polqual, pol.polrelid)) from pg_policy pol
   89         where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polname = 'politica_abandono_select')
   90       is distinct from '97d4f815a6e61ba941d22c4c4d47298d' then
   91      raise exception 'politica_abandono_select cambio desde la auditoria: re-auditar quien lee la perilla del abandono';
   92    end if;
   93    if (select array_agg(pol.polname::text order by pol.polname) from pg_policy pol
   94         where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polpermissive and pol.polcmd in ('r', '*'))
   95       is distinct from array['politica_abandono_select']::text[] then
   96      raise exception 'crm.politica_abandono tiene otras permisivas de lectura: re-auditar quien ve la perilla';
   97    end if;
   98  
   99    -- 5. La cadena invoker: tareas bajo RLS con su policy de lectura, y las
  100    --    columnas de leads que los núcleos leen y que llevan ACL propia.
  101    if not (select relrowsecurity from pg_class where oid = 'crm.tareas'::regclass)
  102       or not exists (select 1 from pg_policy where polrelid = 'crm.tareas'::regclass and polname = 'tareas_select' and polcmd = 'r')
  103       or not has_table_privilege('authenticated', 'crm.tareas', 'SELECT')
  104       or not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT')
  105       or not has_column_privilege('authenticated', 'crm.leads', 'sla_global_iniciado_en', 'SELECT')
  106       or not has_column_privilege('authenticated', 'crm.leads', 'descartado_en', 'SELECT')
  107       or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
  108       or not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
  109       or not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE') then
  110      raise exception 'La cadena invoker del dia del analista perdio un permiso (tareas, leads.tenencia_desde/sla_global_iniciado_en/descartado_en, equipo_visible_fn, ayudantes)';
  111    end if;
  112    -- tareas_select sellada por huella, por conjunto de permisivas y con la
  113    -- restrictiva del actor activo: UNA sola fuente, la base de las tareas por
  114    -- cursor (20260919235100). Constantes copiadas podrían divergir; llamándola no.
  115    perform private.assert_tareas_pendientes_base();
  116  
  117    return 'OK: dia del analista — puerta y nucleos INVOKER (EXECUTE solo authenticated) con su md5, sin contadores crudos, cola v2 y politica_abandono en su forma, cadena invoker con sus permisos, tareas_select sellada por la base de las tareas por cursor';
  118  end;
  119  $function$
  120  
```

### crm_equipo_visible_fn (pg_get_functiondef vivo)
```
    1  CREATE OR REPLACE FUNCTION crm.equipo_visible_fn()
    2   RETURNS TABLE(perfil_id uuid, nombre_completo text, rol_crm text, supervisor_id uuid, activo boolean)
    3   LANGUAGE sql
    4   STABLE SECURITY DEFINER
    5   SET search_path TO ''
    6  AS $function$
    7    select e.perfil_id, p.nombre_completo, e.rol_crm, e.supervisor_id, e.activo
    8    from crm.equipo e
    9    join public.perfiles p on p.id = e.perfil_id
   10    where private.puede_acceder_crm()
   11      and private.rol_crm(e.perfil_id) is not null
   12      and (
   13        (e.perfil_id = (select auth.uid()) and e.activo is true)
   14        or e.perfil_id in (
   15          select private.vendedor_ids_visibles((select auth.uid()))
   16        )
   17        or private.es_lector_global() or private.es_coordinacion_consulta()
   18      );
   19  $function$
   20  
```

### private.postventa_visible_actor / private.vendedor_ids_visibles / private.resolver_en_puertas_bajo_candado (vivos)
```
CREATE OR REPLACE FUNCTION private.postventa_visible_actor(p_persona uuid, p_actor uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_global boolean; v_piloto boolean;
begin
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  select count(*)=2 and bool_and(activo) into v_global
  from crm.multiempresa_flags
  where nombre in ('ficha_360_neutral','postventa_neutral');
  v_piloto:=private.piloto_f8_actor_activo(p_actor);
  if not coalesce(v_global,false) and not v_piloto then return false; end if;
  return (select coalesce(
    private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
    and exists(select 1 from crm.inversionistas i
      where i.id=private.inversionista_canonica(p_persona)
        and (private.rol_crm(p_actor)='gerencia'
          or i.responsable_relacion_id=p_actor
          or i.responsable_relacion_id in
            (select private.vendedor_ids_visibles(p_actor)))),false));
end;
$function$


CREATE OR REPLACE FUNCTION private.vendedor_ids_visibles(p_perfil_id uuid)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  v_rol := private.rol_crm(p_perfil_id);

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e; -- incluye históricos
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select e.perfil_id
        from crm.equipo e
        where e.perfil_id = p_perfil_id
        union -- corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  else
    return; -- coordinador/rol futuro: deny-by-default
  end if;
end;
$function$


CREATE OR REPLACE FUNCTION private.resolver_en_puertas_bajo_candado()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_aisl text := pg_catalog.current_setting('transaction_isolation');
begin
  -- F2.b [D-19]. Un solo sitio para el invariante «leer la bandera implica tener su candado».
  -- 1) READ COMMITTED obligatorio: bajo REPEATABLE READ o SERIALIZABLE la transacción vería una foto anterior al
  --    encendido aunque el candado la hubiese hecho esperar, que es justo el error que esto viene a impedir.
  if v_aisl <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', v_aisl
      using errcode = '0A000';
  end if;
  -- 2) El COMPARTIDO del encendido. Es de transacción: una vez tomado, el valor no puede cambiar hasta el commit, y
  --    el UPDATE de la bandera (que toma el EXCLUSIVO por el trigger de D-5) espera a que esta llamada termine.
  --    Reentrante: tomarlo dos veces en la misma transacción no cuesta nada.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  -- 3) Y ahora sí, el valor.
  return coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
end;
$function$


CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_pulso()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_oid oid;
begin
  for r in select * from (values
    ('crm.gestion_diaria_habitos_fn(date,integer)','df1762f1dd7f59febc47b43d853a55b4','s'),
    ('crm.gestion_diaria_pulso_fn(date)','ae43587d05ede1aa077f5924471c43ae','s'),
    ('private.gestion_diaria_fechas_activas(date,date)','9aa42ff2e0ba81c87afc8cc8c03038c8','s'),
    ('private.gestion_diaria_gestiones_eventos(timestamp with time zone,timestamp with time zone)','32d8e5c964b0b35f1d4e2754bda97724','s'),
    ('private.gestion_diaria_habitos_jornada(date,uuid[],timestamp with time zone)','8538b79265f65a36c3ccbe24625ba7de','s'),
    ('private.gestion_diaria_llamadas(timestamp with time zone,timestamp with time zone,uuid[])','1325886469e34ee651d69672ca1a72c5','s'),
    ('private.gestion_diaria_llamadas_eventos(timestamp with time zone,timestamp with time zone,uuid[])','a209ec1be82b2eeff40c7f6488342d69','s'),
    ('private.gestion_diaria_pulso_autores(timestamp with time zone,timestamp with time zone)','e73960545e7f637259db254c9e2a385b','s'),
    ('private.gestion_diaria_pulso_autorizar()','14091efcebf71186c3fa76f12e4f266c','s'),
    ('private.gestion_diaria_pulso_dia(date)','0221659e73a2556099974324564f2164','s'),
    ('private.gestion_diaria_pulso_metricas(jsonb,integer)','cf96bd3c57c5302eadaa4ef3a29d92aa','i'),
    ('private.gestion_diaria_pulso_roster()','f35b4f2402f1774ea3eba395c5b97f4f','s')
  ) as sellos(firma,huella,volatilidad) loop
    v_oid:=to_regprocedure(r.firma);
    if v_oid is null or not exists(select 1 from pg_proc p where p.oid=v_oid
      and not p.prosecdef and p.proowner='postgres'::regrole
      and p.provolatile::text=r.volatilidad and p.proconfig @> array['search_path=""']
      and md5(pg_get_functiondef(p.oid))=r.huella) then
      raise exception 'Cuerpo o forma de F5 alterados: %',r.firma;
    end if;
    if not has_function_privilege('authenticated',v_oid,'EXECUTE') or exists(
      select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=v_oid and a.grantee not in ('postgres'::regrole::oid,'authenticated'::regrole::oid)) then
      raise exception 'Permisos de F5 alterados: %',r.firma;
    end if;
  end loop;
  perform private.assert_gestion_diaria_analista();
  perform private.assert_gestion_diaria_equipo();
  perform private.assert_gestion_diaria_cortes();
  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado
  return 'OK: F5 invoker, fuentes compartidas selladas, ACL exactas, puertas F3/F4 y censo analítico conservados';
end $function$


CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_citas()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_firma text; v_huella text;
begin
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)', '904d3b0a853a6cf794943217fc957f03'),
    ('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)', 'fd2b0376be5e8c6728e4c33776e1a9e4')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and md5(pg_get_functiondef(p.oid)) = v_huella) then
      raise exception 'G4b: contrato, cuerpo o permisos alterados en %', v_firma;
    end if;
    -- ACL EXACTA (como F3/F5): EXECUTE solo para postgres y authenticated; PUBLIC es grantee 0.
    if exists (select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure(v_firma)
        and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)) then
      raise exception 'G4b: EXECUTE fuera de postgres y authenticated en %', v_firma;
    end if;
  end loop;
  -- La lista ES la cifra: si cambia la definición de citas agendadas, la partición del
  -- pulso, el roster canónico o las fuentes del pulso que dan la cifra de equipo, «fuera»
  -- y operación, la lista se revisa junto con ellas (auditor-rls P2-1).
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_llamadas(timestamp with time zone,timestamp with time zone,uuid[])', '1325886469e34ee651d69672ca1a72c5'),
    ('private.gestion_diaria_pulso_roster()', 'f35b4f2402f1774ea3eba395c5b97f4f'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pulso_autores(timestamp with time zone,timestamp with time zone)', 'e73960545e7f637259db254c9e2a385b'),
    ('private.gestion_diaria_pulso_dia(date)', '0221659e73a2556099974324564f2164'),
    ('private.gestion_diaria_pulso_metricas(jsonb,integer)', 'cf96bd3c57c5302eadaa4ef3a29d92aa'),
    ('crm.gestion_diaria_pulso_fn(date)', 'ae43587d05ede1aa077f5924471c43ae')
  ) as fuentes(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4b: cambió % y la lista de citas debe revisarse con la cifra', v_firma;
    end if;
  end loop;
  return 'OK: citas G4b INVOKER con ACL exacta (postgres y authenticated), misma definición que la cifra y fuentes del pulso selladas';
end;
$function$

```

## Protocolo global de revisión (transcrito)
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

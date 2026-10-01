ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 2–3: cambia el cuerpo de UNA función SQL `STABLE SECURITY DEFINER` de `private` que
la usan 10 funciones del CRM; sin tablas, policies ni grants). Intenta REFUTAR la equivalencia; no confirmes por cortesía.
Sin base ni red: todo está transcrito. Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS
P0–P3 con evidencia citada, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia.

## Contexto medido (30/09/2026, producción, transacciones deshechas)
La ficha de inversionista (`crm.inversionista_ficha_fn`, 490–535 ms, 1.575 llamadas en 4 días) calcula la cartera entera
(`private.cartera_f5_fuentes()`, 726 filas) SIETE veces por llamada (291 ms de 490, `track_functions` en transacción
deshecha): ficha → `cartera_f5_exigir` ×2 → `cartera_inversionistas_estado_fn` ×4 → fuentes; `postventa_estado_fn` ×1;
`cartera_f5_personas_visibles(uuid)` ×2; la CTE `fuentes` de la ficha ×1. Dentro de fuentes, por FILA se llama a
`private.inversionista_canonica()` (13.408 llamadas por ficha = 218 ms) y a `private.analista_atribuido_cadena()` (4.795 =
123 ms). Hoy: 0 personas con `inversionista_canonico_id`; `crm.operaciones_cartera` tiene 3 filas; 726 fuentes
(≈685 contratos + cierres externos).

Funciones que NO cambian (vivas; ambas STABLE; canónica es DEFINER, cadena es INVOKER):
```sql
-- private.inversionista_canonica(p_id uuid) returns uuid  (md5 def 34702897135078893b7d3a726b0c1816)
with recursive c as ( select i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i where i.id = p_id
  union all select i.id, i.inversionista_canonico_id, c.n + 1 from c join crm.inversionistas i on i.id = c.inversionista_canonico_id where c.n < 16 )
select case when p_id is null then null else coalesce((select c.id from c where c.inversionista_canonico_id is null order by c.n desc limit 1), p_id) end

-- private.analista_atribuido_cadena(p_contrato_id uuid) returns uuid  (md5 def 3c9cec305b014ad8c933df25057d3e8b)
with recursive cadena as ( select p_contrato_id as contrato_id, 0 as nivel, array[p_contrato_id] as visitados
  union all select o.contrato_origen_id, c.nivel + 1, c.visitados || o.contrato_origen_id from cadena c join crm.operaciones_cartera o on o.contrato_nuevo_id = c.contrato_id
  where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(c.visitados)) and c.nivel < 100 )
select con.analista_cierre_id from cadena cd join public.contratos con on con.id = cd.contrato_id where con.categoria = 'upgrade' order by cd.nivel asc limit 1
```
Restricciones del esquema relevantes: `crm.inversionistas` CHECK `inversionistas_no_autofusion` (id <> inversionista_canonico_id);
`crm.operaciones_cartera` CHECK `operaciones_cartera_forma` (los `upgrade` llevan `contrato_origen_id` NULL; las
`renovacion` con desglose completo lo llevan NOT NULL).

## Cuerpo VIVO (md5 de pg_get_functiondef 94fa33cfcca657f70a1a94f98c3bf482)
```sql
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
```

## Cuerpo NUEVO (md5 fa15f7765d0892c790c7a4b6822e756e; misma firma, STABLE, SECURITY DEFINER, search_path '', dueño postgres, ACL {postgres=X/postgres})
```sql
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
```

Diferencias exactas: (1) se antepone `with recursive paseo, canon, cadena, atrib, canon_map, atrib_map` a la consulta;
(2) `private.analista_atribuido_cadena(c.id)` → `(((select m from atrib_map)->>c.id::text)::uuid)` (dentro del mismo
`coalesce(…, c.analista_cierre_id)`); (3) las dos apariciones de `private.inversionista_canonica(x.id)` →
`coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)`. Nada más cambia.

Argumento de equivalencia. `canon`: para cada persona `origen`, el mismo paseo hacia la raíz (`n < 16`, es decir hasta 16
nodos) y la única fila con `inversionista_canonico_id is null` (fin del paseo) es la canónica; sin raíz dentro del tope
(cadena larga o ciclo) queda `origen`, como el `coalesce(…, p_id)` de la función. Un id que no exista en
`crm.inversionistas` no está en el mapa → `coalesce(…, x.id)` = `x.id`, como `coalesica(p_id)` devuelve `p_id`
(en la práctica no ocurre: `x.id` viene de FKs a inversionistas o de la propia tabla). `x.id` NULL: `->>` con clave NULL da
NULL y `coalesce(null, null)` = NULL, como `canonica(null)` = NULL; además la rama de cierres filtra `x.id is not null` y
la de contratos solo mete ids no nulos. `atrib`: misma cadena de renovaciones (visitados, `nivel < 100`) por cada
contrato raíz; `distinct on (raiz) … order by raiz, nivel asc` = `order by nivel asc limit 1`; contratos sin ancestro
`upgrade` no están en el mapa → NULL → `coalesce(NULL, c.analista_cierre_id)` como antes; ancestro `upgrade` con
`analista_cierre_id` NULL → `jsonb_object_agg` guarda `null` JSON → `->>` devuelve NULL → mismo `coalesce`.
Empates a igual `nivel` (dos ancestros upgrade al mismo nivel): la función original hace `order by nivel asc limit 1`
sin desempate; la nueva hace `distinct on (raiz) order by raiz, nivel asc` sin desempate — ambas dependen del orden
físico en ese caso; hoy el grafo es un árbol (3 operaciones) y el CHECK exige un origen por operación, pero un contrato
puede ser `contrato_nuevo_id` de dos operaciones distintas: ¿es un riesgo real?

## Evidencia
- Prototipo `pg_temp` en prod (deshecho): 726/726 filas, md5 del texto de fila idéntico; 42 → 11 ms por llamada.
- Punta a punta en prod con el reemplazo DENTRO de una transacción deshecha: 33/33 salidas idénticas por md5
  (29 `inversionista_ficha_fn`, `postventa_agenda_fn`, `cartera_inversionistas_estado_fn`,
  `cartera_inversionistas_filtrada_fn`, `postventa_estado_fn`) como gerencia; ficha 509 → 284 ms, agenda 164 → 97,
  cartera 193 → 126, estado 52 → 19.
- Un primer intento con subconsulta correlacionada sobre la CTE (`select k.canon from canon k where k.id = x.id`) salió
  MÁS lento (82 ms); los mapas jsonb leídos con `->>` son los que bajan a 11 ms.
- Banco Docker propio (imagen supabase/postgres 17.6.1.105; esquema public,crm,private volcado de prod; paridad de
  cuerpos crm 278 / private 536 con el MISMO md5 que prod): migración → repetida (ruta «ya aplicada») → reversa →
  repetida → migración → registrar → repetido; negativo con cuerpo ajeno: migración y reversa lo rechazan.
- Prueba sintética en el banco (supabase_admin, session_replication_role=replica, todo deshecho): 11 fuentes idénticas
  entre cuerpo vivo y nuevo con: hijo y nieto fusionados (P03→P02→P01), cadena de 17 niveles (supera el tope 16 → cada
  nodo es su propia canónica), ciclo A↔B, padre inexistente, perfil sin persona, upgrades encadenados (K1 nuevo → K2
  upgrade → K3 upgrade → K4 renovación: K4 atribuye al analista de K3), ciclo de operaciones K5↔K6, upgrade con analista
  NULL (K7) y su renovación (K8 → coalesce a su propio analista), cierres externos con persona fusionada y con persona en
  ciclo.
- Seguridad (prod, solo lectura): fuentes es DEFINER dueño postgres, ACL `{postgres=X/postgres}`; anon/authenticated/
  service_role NO la ejecutan; las 6 tablas leídas son de postgres con RLS no forzada → la función veía y ve TODAS las
  filas en ambas versiones (la visibilidad por actor la aplican los llamadores, que no cambian). Llamadores: 9 DEFINER y
  2 INVOKER (`cartera_f5_fuentes_reales`, `postventa_fuente`), todos de postgres.

## Migración (esqueleto, igual que 20260930000550)
`begin; set local lock_timeout='10s'; DO`: preflight (huella viva `94fa33cf…`, dueño/ACL/DEFINER/STABLE/search_path
con `is not true`; ruta idempotente si ya está `fa15f776…`); oráculo de filas ANTES; `execute $def$ CREATE OR REPLACE …
$def$`; oráculo DESPUÉS (mismo count y md5 o `raise`); postflight de huella e invariantes; `comment on function`; `commit`.
Reversa: restaura el cuerpo vivo byte a byte con las mismas guardas. Registro: fila `20260930172255 /
crm_cartera_f5_fuentes_mapas` con 1 sentencia.

## Preguntas concretas para refutar
1. ¿Hay algún caso en que `canon_map`/`atrib_map` devuelvan algo distinto de las funciones fila a fila? (NULL, ids
   inexistentes, ciclos, tope 16/100, empates a igual nivel, `jsonb_object_agg` con claves repetidas, contratos
   `es_demo`).
2. `(select m from canon_map)` dentro del `lateral`: ¿algún plan en que se reevalúe por fila y cambie el resultado (no
   solo el coste)?
3. STABLE + `statement_timestamp()`: igual que antes; ¿algún efecto del cambio en el `estado` calculado de cierres?
4. ¿Falta alguna guarda en migración/reversa/registro respecto al patrón de la casa?

---
tags: [facturacion, datos, decisiones, crm]
fecha: 2026-10-08
estado: categoría APLICADA (08/10 23:49, PR #230); limpieza de pruebas HECHA (111111 eliminado el 09/10 11:57) (09/10 10:13) salvo 2026-01-111111 (protegido por su operación de cartera)
---

# Facturación — fase 0: decisiones de datos (08/10/2026)

Parte de [[Facturacion - auditoria completa (2026-10-08)]]. Miguel contestó las cuatro preguntas el 08/10. Lo que
toca datos de producción NO se ha hecho: cada paso de escritura necesita su OK sobre las filas exactas.

**Primero, listar las filas exactas (solo lectura).** Consulta `listar-fase0.sql` (anexo abajo). La corre Miguel con
`!` desde `CRM-Avance-Corp/`: `supabase db query --linked -f <archivo> --output-format json > salida.json`.

## 1. «El tipo lo decide la operación de cartera» — decidido; falta elegir el CÓMO

Hoy el núcleo `private.capital_episodios` (`20260908211349`, l. ~893) clasifica por
`'contrato_' || coalesce(c.categoria, 'nuevo')`. 12 contratos con `categoria='nuevo'` son el `contrato_nuevo_id` de una
operación de cartera de tipo **upgrade** (S/ 2.092.254 + US$ 54.971 en sep–oct) y suman en «Capital nuevo».

| Opción | Qué es | A favor | En contra |
|---|---|---|---|
| **A · Núcleo** | El núcleo deriva el tipo de la operación de cartera cuando existe | Una sola regla para Facturación, Metas, Ranking, Gráficas y Resumen; cubre los casos futuros | Reescribe una función viva de dinero (LEVEL 3, A/B, huella); la tabla `contratos` sigue diciendo «nuevo» |
| **B · Datos + prevención** | Corregir `categoria` de los 12 por una puerta con bitácora y que la operación de upgrade fije la categoría del contrato | El dato queda bien en origen, todos los lectores coinciden | Hay que ver si `categoria` mueve la plantilla del PDF del contrato o algo firmado; una puerta nueva |

**Impacto en cualquier opción:** cambia Metas de **septiembre y octubre** de los analistas afectados (sale de «Capital
nuevo», entra en «Upgrade»). Septiembre todavía no está sellado: si se corrige antes de sellarlo, el cierre de
septiembre ya sale bien; después, «lo sellado no se reescribe». **Dinero nuevo vs. renovado:** en un upgrade NO aplica: un CHECK de `crm.operaciones_cartera` exige que
`capital_renovado` y `capital_adicional` vayan vacíos en los upgrades (`20260824231133:120-125`); el contrato entero cuenta.

**Falta que Miguel decida:** A o B (recomendado: **B**, con la prevención, si `categoria` no afecta al PDF firmado), y
si se aplica **antes** de sellar septiembre. Después: plan de migración, banco, gate, auditor-rls, Codex y `!`.

> Plan detallado de la decisión 1: [[Facturacion - plan corregir categoria de 12 upgrades (2026-10-08)]].

## 2. «Las ventas del perfil de pruebas son pruebas» — decidido; pasos pendientes de OK

Perfil vendedor de pruebas `d731f284…` (Miguel lo confirmó el 23/09). En Facturación suma S/ 8.800 + US$ 26.000 en
sep–oct (contratos 2026-01-001391, 001463, 001549, 455468 y una cooperativa de S/ 800), más 2026-01-111111 (S/ 1.000,
notas de prueba).

**Matiz importante:** **anular NO saca el capital de Facturación** (regla ATR-4, `lib/facturacion.ts:17-20`: la
anulación sanciona la conversión, no borra dinero). Por eso hacen falta dos cosas distintas:

1. **Conversión — anular cada cierre de prueba.** Desde la pantalla, con Gerencia: `anular-cierre-avance` (contratos) y
   la sección de cierres externos (la cooperativa). Es «la única puerta» de la conversión.
2. **Capital — marcar cada contrato como prueba** con `public.marcar_contrato_demo(contrato, true, motivo)`
   (`20260829181500`): solo Gerencia, motivo obligatorio, rechaza meses sellados y deja rastro en `public.audit_log`. **No
   tiene botón en la pantalla**: se ejecuta por SQL con la identidad de Miguel, primero ensayado en un `DO` que termina
   en `raise` (no escribe) y luego de verdad, con su `!`. La cooperativa no tiene marca de prueba: al anularla, el núcleo
   la pasa a `nula` y sale de Facturación.
3. **Después, desactivar el perfil** (al revés, lo vendido seguiría contando por `cobertura.fuera_de_roster`).

## Resultado de `listar-fase0.sql` en producción (08/10, 18:28 Lima, solo lectura)

**Decisión 1 — los 12 son todos de SEPTIEMBRE:** 8 en soles (S/ 2.092.254) y 4 en dólares (US$ 54.971), todos con
operación de tipo upgrade, todos activos. `capital_renovado` y `capital_adicional` vienen vacíos en los 12, como exige el
CHECK para los upgrades (no es un fallo).

| Contrato | Día | Moneda | Capital | Analista |
|---|---|---|---|---|
| 2026-01-001362 | 02/09 | PEN | 577.554 | Merlys Garcia |
| 2026-01-001369 | 03/09 | PEN | 100.000 | Astrid Centenaro |
| 2026-01-001401 | 08/09 | PEN | 1.116.900 | Jorge Marzano |
| 2026-01-001408 | 09/09 | USD | 3.100 | Lisseth Nuñez García |
| 2026-01-001400 | 09/09 | PEN | 120.000 | Betzabeth Fuenmayor Saavedra |
| 2026-01-001439 | 12/09 | USD | 25.000 | Lisseth Nuñez García |
| 2026-01-001440 | 12/09 | USD | 25.471 | Lisseth Nuñez García |
| 2026-01-001441 | 13/09 | PEN | 97.800 | Lisseth Nuñez García |
| 2026-01-001424 | 14/09 | USD | 1.400 | Astrid Centenaro |
| 2026-01-001425 | 14/09 | PEN | 10.000 | Betzabeth Fuenmayor Saavedra |
| 2026-01-001445 | 16/09 | PEN | 20.000 | Betzabeth Fuenmayor Saavedra |
| 2026-01-001447 | 17/09 | PEN | 50.000 | Linda Condori Gutierrez |

**Decisión 2 — dos grupos distintos:**
- **De septiembre y octubre (los de la pregunta):** 2026-01-001391 (US$ 5.000), 2026-01-111111 (S/ 1.000), 2026-01-001463
  (S/ 5.000), 2026-01-001549 (US$ 21.000), 2026-01-455468 (S/ 3.000) y la cooperativa `e6891c3e` (S/ 800, sin anular).
- **🔴 6 contratos de MAYO a JULIO que salen porque los REGISTRÓ ese perfil** (no necesariamente porque sean suyos):
  2026-01-000625 (US$ 2.200), 000644 (US$ 6.667), 000713 (S/ 33.334), 000761 (S/ 20.000), 000827 (S/ 100.000) y 001037
  (US$ 20.000). Pueden ser ventas REALES de otros analistas tecleadas por Miguel. **No se tocan** sin revisarlos uno por uno.
- La cooperativa `a112aead` (S/ 100.000, 19/08) es la demo de Qorilazo, ya anulada y excluida.

## 3. 2026-01-001490 y 001484 — no es duplicado

Miguel: «imagino que son inversiones reales y distintas porque la numeración de contrato es real». Se quedan los dos;
la alerta de posible duplicado se descarta. Nada que hacer.

## 4. Directorio ve Facturación — HECHO en la PR #229

Commit `c609cc99` (capacidad `verFacturacion` para Directorio, en lectura). El servidor ya se lo permitía.

## Anexo — `listar-fase0.sql` (solo lectura)

Vive en el scratchpad de la sesión del 08/10 (`auditoria-facturacion/sql-fase0/listar-fase0.sql`). Lista: los
contratos «nuevo» que son operación de cartera (número, día, moneda, capital, `capital_renovado`, `capital_adicional`,
analista) con totales por mes, y los contratos y cooperativas del perfil de pruebas. Abre con
`begin transaction read only;` y cierra con `rollback;`.

```sql
-- listar-fase0.sql — Facturación, fase 0 (decisiones de datos de Miguel, 08/10/2026). SOLO LECTURA.
-- Lista las filas EXACTAS que tocarían las dos correcciones de datos, para revisarlas antes de escribir nada:
--   (1) los contratos con categoria 'nuevo' que son el contrato nuevo de una operación de cartera
--       (hoy cuentan como «Capital nuevo»; Miguel decidió que manda la operación);
--   (2) las ventas del perfil vendedor de PRUEBAS d731f284… y el contrato 2026-01-111111
--       (Miguel decidió que son pruebas).
-- Forma: begin read only → una sola sentencia final con un jsonb → rollback. No escribe nada.
begin transaction read only;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

with
perfil_pruebas as (
  select p.id from public.perfiles p where p.id::text like 'd731f284%'
),
nuevos_de_cartera as (
  select c.numero_contrato, c.id as contrato_id, c.categoria, c.moneda, c.capital,
         (c.fecha_cierre_comercial)::date as dia,
         o.tipo as tipo_operacion, o.capital_renovado, o.capital_adicional, o.fecha_operacion,
         coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id,
         c.es_demo, c.estado
    from public.contratos c
    join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
   where coalesce(c.categoria, 'nuevo') = 'nuevo'
     and not c.es_demo
),
ventas_pruebas as (
  select c.numero_contrato, c.id as contrato_id, c.categoria, c.moneda, c.capital,
         (c.fecha_cierre_comercial)::date as dia, c.es_demo, c.estado,
         coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
    from public.contratos c
   where not c.es_demo
     and (coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) in (select id from perfil_pruebas)
          or c.creado_por in (select id from perfil_pruebas)
          or c.numero_contrato = '2026-01-111111')
),
coop_pruebas as (
  select x.id as cierre_externo_id, x.moneda, x.monto, x.creado_en, (x.anulado_en is not null) as anulado
    from crm.cierres_externos x
   where x.vendedor_id in (select id from perfil_pruebas)
)
select jsonb_build_object(
  'generado_en_lima', (now() at time zone 'America/Lima')::text,
  'perfil_pruebas', (select jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre_completo, 'activo', p.activo))
                       from public.perfiles p where p.id in (select id from perfil_pruebas)),
  '1_nuevos_que_son_operacion_de_cartera', (
    select jsonb_agg(jsonb_build_object(
             'numero', n.numero_contrato, 'dia', n.dia, 'moneda', n.moneda, 'capital', n.capital,
             'tipo_operacion', n.tipo_operacion, 'capital_renovado', n.capital_renovado,
             'capital_adicional', n.capital_adicional,
             'analista', (select pf.nombre_completo from public.perfiles pf where pf.id = n.analista_id),
             'estado', n.estado) order by n.dia)
      from nuevos_de_cartera n),
  '1_totales_por_mes_y_moneda', (
    select jsonb_object_agg(k, v) from (
      select to_char(date_trunc('month', n.dia), 'YYYY-MM') || '|' || n.moneda as k,
             jsonb_build_object('contratos', count(*), 'capital', sum(n.capital),
                                'capital_adicional', sum(n.capital_adicional)) as v
        from nuevos_de_cartera n group by 1) t),
  '2_contratos_de_prueba', (
    select jsonb_agg(jsonb_build_object('numero', v.numero_contrato, 'dia', v.dia, 'moneda', v.moneda,
                                        'capital', v.capital, 'estado', v.estado) order by v.dia)
      from ventas_pruebas v),
  '2_cooperativas_de_prueba', (
    select jsonb_agg(jsonb_build_object('id8', left(c.cierre_externo_id::text, 8), 'moneda', c.moneda,
                                        'monto', c.monto, 'creado_en_lima', (c.creado_en at time zone 'America/Lima')::text,
                                        'anulado', c.anulado))
      from coop_pruebas c)
) as resultado;
rollback;
```

## Limpieza de las ventas de prueba — ✅ HECHA 09/10 10:13 (Miguel con `!`)

**Miguel revisó contrato por contrato (09/10, con `ver-contratos-prueba.sql`):**
- PRUEBA: 2026-01-111111 («demo de prueba», S/ 1.000, Vladimir Jurado), 2026-01-455468 («PRUEBA PRUEBA», lead demo1234,
  S/ 3.000), 2026-01-000000 (ya era prueba; faltaba anular su cierre, lead «Jhosep Prueba») y la cooperativa `e6891c3e`
  («DEMO DEMO DEMO», S/ 800).
- REALES, no se tocan: 2026-01-001391 (Carbajal, US$ 5.000), 001463 (Cáceres, S/ 5.000), 001549 (Cruz Rangel, US$ 21.000) y los
  6 de mayo–julio. Los 9 están a nombre del perfil de pruebas «MIGUEL BRICEÑO» como analista.

**Hecho en producción (`limpiar-pruebas-2-REAL.sql` v3, todo o nada, firma ADMINISTRADOR AVANCE CORP `bf1c562e`):** «OK: 2
cierres y la cooperativa anulados; 1 contrato marcado como prueba» — `crm.anular_cierre_avance` sobre los leads de 455468 y
000000, `crm.anular_cierre_externo` sobre `e6891c3e` (los tres de octubre: sin ajuste de mes cerrado) y
`public.marcar_contrato_demo` sobre 455468 (S/ 3.000 salen de Facturación; la cooperativa anulada, S/ 800, también). Las mismas
puertas que la pantalla: Miguel ya no anula a mano.

**✅ 09/10 11:57 — 2026-01-111111 ELIMINADO** (Miguel quiso borrarlo él mismo; «Eliminar inversión» lo rechazaba con «parte de un upgrade o una renovación registrados»). Medido: era el contrato NUEVO de un upgrade SIN origen, fuera de `crm.inversiones`, septiembre abierto. Se eliminó con la MISMA función que «Eliminar contrato» del portal (Admin → Contratos) y del CRM (Cartera → cliente → Ver contrato): `crm.contrato_eliminar_auditado(contrato, actor ADMINISTRADOR)` — ENSAYO «LISTO» y REAL «OK», auditoría `d2744324…`, 1 archivo conservado; el trigger `trg_contratos_05_restaurar_operacion` borró su operación de upgrade. El cliente conserva su otro contrato (2026-01-001351). Ya no hace falta una puerta nueva para fichas de cartera de prueba: el borrado auditado lo cubre mientras el mes esté abierto (ver memoria «eliminar-contrato-vs-eliminar-inversion»).

**✅ 09/10 10:55 — Las 3 ventas reales pasaron a AVANCECORP** (Miguel: «todo eso ponlo a nombre de avance corp… ya tenemos un AVANCECORP, a ese quiero que lo pongas»; «se creó como un responsable para las ventas que haga la misma empresa»). AVANCECORP = `d0468985-abc8-4d12-bcf2-f6fbc5096de6`, avancecorp@miavance.com, cargo «Inversiones internas», rol CRM supervisor (≠ ADMINISTRADOR AVANCE CORP `bf1c562e`, la Gerencia que firma). Por la puerta de «Reasignar venta» (`public.reasignar_analista_contrato`), firmando como ADMINISTRADOR: «OK: 3 ventas a nombre de AVANCECORP» (2026-01-001391, 001463, 001549; S/ 5.000 + US$ 26.000), 3 filas en `crm.reasignaciones_analista`. Primero se preparó hacia ADMINISTRADOR AVANCE CORP; Miguel lo frenó antes del REAL (apartado como `reasignar-avance-2-REAL.v1-NO-USAR.sql`). La conversión de los leads de 001391 y 001549 sigue a nombre del perfil de pruebas (son ventas reales: cuentan en la empresa).
**✅ 09/10 10:58 — Los 6 de mayo–julio también pasaron a AVANCECORP** (Miguel: «pásalos todos a AVANCECORP»): 000625, 000644, 000713 (upgrade), 000761, 000827 y 001037 — S/ 153.334 + US$ 28.867, misma puerta y firma, «OK: 6 ventas de mayo a julio a nombre de AVANCECORP». **Miguel (09/10 11:02): el perfil de pruebas NO se desactiva («déjalo, con eso hacemos pruebas»).** Ya no tiene contratos reales a su nombre; le quedan conversiones de leads reales (Carbajal y Cruz Rangel en octubre; 3 de agosto, sellado) que siguen contando en la empresa.

**Por qué v3:** v1 elegía la Gerencia por el nombre del perfil de pruebas (en producción hay 3 y ninguna se llama así); v2 obligaba
a anular a mano y tomaba todos los leads del perfil desde septiembre (habría exigido anular también los reales); v3 anula y
marca por las puertas de la pantalla, solo lo que Miguel señaló, en una transacción con postflight.

### ver-contratos-prueba.sql (solo lectura)

```sql
-- ver-contratos-prueba.sql — SOLO LECTURA (09/10/2026). La ficha de cada contrato y cooperativa del perfil vendedor de
-- PRUEBAS «MIGUEL BRICEÑO» (d731f284): los que vende, los que registró y el 2026-01-111111. Para que Miguel decida, uno
-- por uno, cuáles son pruebas. Abre en solo lectura y termina en ROLLBACK: no escribe nada.
begin transaction read only;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

with
pruebas as (select 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'::uuid as id),
cs as (
  select c.*, coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
    from public.contratos c
   where coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = (select id from pruebas)
      or c.creado_por = (select id from pruebas)
      or c.numero_contrato = '2026-01-111111'
)
select jsonb_build_object(
  'contratos', (
    select jsonb_agg(jsonb_build_object(
             'numero', c.numero_contrato,
             'dia_comercial', c.fecha_cierre_comercial,
             'monto', c.moneda || ' ' || c.capital,
             'tasa_plazo', c.tasa_anual || '% · ' || c.modalidad || ' · ' || c.fecha_inicio || ' → ' || c.fecha_vencimiento,
             'cliente', (select p.nombre_completo from public.perfiles p where p.id = c.cliente_id),
             'otros_contratos_del_cliente', (select count(*) from public.contratos o
                                              where o.cliente_id = c.cliente_id and o.id <> c.id and not o.es_demo),
             'analista', (select p.nombre_completo from public.perfiles p where p.id = c.analista_id),
             'registrado_por', (select p.nombre_completo from public.perfiles p where p.id = c.creado_por),
             'registrado_en_lima', to_char(c.creado_en at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI'),
             'tipo', coalesce(c.categoria, 'nuevo'), 'estado', c.estado, 'ya_es_prueba', c.es_demo,
             'notas', c.notas_internas,
             'pdf', (select j.estado from private.contrato_pdf_jobs j where j.contrato_id = c.id order by j.revision desc limit 1),
             'lead', (select jsonb_build_object('nombre', l.nombre_completo, 'origen', l.origen, 'alta_manual', l.alta_manual,
                                                'convertido_en_lima', to_char(l.convertido_en at time zone 'America/Lima', 'DD/MM/YYYY'),
                                                'cierre_anulado', exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = l.id))
                        from crm.leads l where l.contrato_id = c.id order by l.convertido_en desc nulls last limit 1))
           order by c.fecha_cierre_comercial, c.numero_contrato)
      from cs c),
  'cooperativas', (
    select jsonb_agg(jsonb_build_object(
             'id8', left(x.id::text, 8), 'cooperativa', x.cooperativa, 'cliente', x.nombre_completo,
             'monto', x.moneda || ' ' || x.monto, 'nota', x.nota,
             'registrada_en_lima', to_char(x.creado_en at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI'),
             'anulada', x.anulado_en is not null) order by x.creado_en)
      from crm.cierres_externos x where x.vendedor_id = (select id from pruebas)),
  'leads_convertidos_sin_contrato', (
    select jsonb_agg(jsonb_build_object(
             'nombre', l.nombre_completo, 'origen', l.origen, 'alta_manual', l.alta_manual,
             'convertido_en_lima', to_char(l.convertido_en at time zone 'America/Lima', 'DD/MM/YYYY'),
             'cierre_anulado', exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = l.id))
           order by l.convertido_en)
      from crm.leads l
     where l.vendedor_id = (select id from pruebas) and l.etapa = 'convertido' and l.contrato_id is null)
) as resultado;

rollback;
```

### limpiar-pruebas-1-ENSAYO.sql (v3, no escribe)

```sql
-- limpiar-pruebas-1-ENSAYO.sql (v3, 09/10/2026) — Facturación, fase 0. Miguel revisó contrato por contrato el 09/10:
--   PRUEBA: 2026-01-111111 («demo de prueba»), 2026-01-455468 («PRUEBA PRUEBA», lead demo1234), 2026-01-000000 (ya
--           marcado como prueba; falta anular su cierre, lead «Jhosep Prueba») y la cooperativa e6891c3e («DEMO DEMO DEMO»).
--   REALES (no se tocan): 2026-01-001391, 001463, 001549 y los 6 de mayo a julio.
--
-- Lo que hará el REAL, todo por las MISMAS puertas que usa la pantalla, como Gerencia (ADMINISTRADOR AVANCE CORP):
--   1. crm.anular_cierre_avance → los cierres de los leads de 455468 y 000000 (conversión; no resta capital, ATR-4);
--   2. crm.anular_cierre_externo → la cooperativa e6891c3e (sale de la conversión y de Facturación);
--   3. public.marcar_contrato_demo → 111111 y 455468 (capital: salen de Facturación, metas y sello).
--
-- ESTE ARCHIVO NO ESCRIBE NADA: el bloque termina SIEMPRE en `raise exception` y Postgres deshace todo. El mensaje ES el
-- resultado: qué pasa con cada paso. Veredicto «LISTO PARA 2-REAL» o «REVISAR».
-- CÓMO LO CORRE MIGUEL (con `!`): supabase db query --linked -f <este archivo>. Un solo mensaje, READ COMMITTED explícito.
-- 09/10: el ENSAYO v3 mostró que 2026-01-111111 NO se puede marcar: tiene una operación de cartera (upgrade) y la puerta
-- lo rechaza a propósito (P0409); «Eliminar inversión» también lo rechaza y no existe puerta para deshacer una operación
-- de cartera. Miguel decide aparte. Aquí queda fuera: se marca SOLO 455468.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $ensayo$
declare
  c_firma_prefijo constant text := 'bf1c562e';   -- ADMINISTRADOR AVANCE CORP
  c_marcar constant text[] := array['2026-01-455468'];
  c_anular_de constant text[] := array['2026-01-455468', '2026-01-000000'];
  c_cooperativa constant text := 'e6891c3e';
  c_motivo constant text := 'Prueba del CRM, no es una venta: decision de Miguel del 09/10/2026 (auditoria de Facturacion).';
  v_n int;
  v_actor uuid;
  v_actor_nombre text;
  v_contratos uuid[] := '{}';
  v_leads uuid[] := '{}';
  v_coop uuid;
  v_id uuid;
  v_num text;
  v_res jsonb;
  v_pasos jsonb := '[]'::jsonb;
  v_ok int := 0;
  v_total int;
begin
  -- 1) Lo que se toca, resuelto como dueño (sin RLS de por medio) y comprobado.
  foreach v_num in array c_marcar loop
    select c.id into v_id from public.contratos c where c.numero_contrato = v_num and not c.es_demo;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe o ya es de prueba', v_num;
    end if;
    v_contratos := v_contratos || v_id;
  end loop;
  foreach v_num in array c_anular_de loop
    select count(*) into v_n
      from crm.leads l join public.contratos c on c.id = l.contrato_id
     where c.numero_contrato = v_num and l.etapa = 'convertido';
    if v_n <> 1 then
      raise exception 'ABORTA: el contrato % tiene % leads convertidos (se esperaba 1)', v_num, v_n;
    end if;
    select l.id into v_id
      from crm.leads l join public.contratos c on c.id = l.contrato_id
     where c.numero_contrato = v_num and l.etapa = 'convertido';
    v_leads := v_leads || v_id;
  end loop;
  select count(*) into v_n from crm.cierres_externos x where left(x.id::text, 8) = c_cooperativa;
  if v_n <> 1 then
    raise exception 'ABORTA: la cooperativa % no es UNA fila (hay %)', c_cooperativa, v_n;
  end if;
  select x.id into v_coop from crm.cierres_externos x where left(x.id::text, 8) = c_cooperativa;

  -- 2) La firma: UN solo perfil con ese prefijo y rol CRM gerencia vigente.
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta de Gerencia elegida (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id, p.nombre_completo into v_actor, v_actor_nombre from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';

  -- 3) Las puertas COMO esa Gerencia, paso por paso, sin parar en el primer fallo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  execute 'set local role authenticated';
  v_total := array_length(v_leads, 1) + 1 + array_length(v_contratos, 1);
  for i in 1 .. array_length(v_leads, 1) loop
    begin
      v_res := crm.anular_cierre_avance(v_leads[i], c_motivo);
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'anular cierre del lead de ' || c_anular_de[i],
                                                                 'ok', true, 'mes_cerrado', v_res -> 'mes_cerrado'));
      v_ok := v_ok + 1;
    exception when others then
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'anular cierre del lead de ' || c_anular_de[i],
                                                                 'ok', false, 'error', sqlerrm, 'sqlstate', sqlstate));
    end;
  end loop;
  begin
    v_res := crm.anular_cierre_externo(v_coop, c_motivo);
    v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'anular cooperativa ' || c_cooperativa,
                                                               'ok', true, 'mes_cerrado', v_res -> 'mes_cerrado'));
    v_ok := v_ok + 1;
  exception when others then
    v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'anular cooperativa ' || c_cooperativa,
                                                               'ok', false, 'error', sqlerrm, 'sqlstate', sqlstate));
  end;
  for i in 1 .. array_length(v_contratos, 1) loop
    begin
      v_res := public.marcar_contrato_demo(v_contratos[i], true, c_motivo);
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'marcar como prueba ' || c_marcar[i], 'ok', true));
      v_ok := v_ok + 1;
    exception when others then
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('paso', 'marcar como prueba ' || c_marcar[i],
                                                                 'ok', false, 'error', sqlerrm, 'sqlstate', sqlstate));
    end;
  end loop;
  execute 'reset role';

  raise exception 'ENSAYO (no se escribió nada) · veredicto: % · pasos ok: % de % · firma: % (%) · detalle: %',
    case when v_ok = v_total then 'LISTO PARA 2-REAL' else 'REVISAR' end,
    v_ok, v_total, v_actor_nombre, left(v_actor::text, 8), v_pasos;
end
$ensayo$;

rollback;
```

### limpiar-pruebas-2-REAL.sql (v3, ESCRIBIÓ en producción el 09/10 10:13)

```sql
-- limpiar-pruebas-2-REAL.sql (v3, 09/10/2026) — ESCRIBE EN PRODUCCIÓN. Solo después de un ENSAYO con veredicto
-- «LISTO PARA 2-REAL» (limpiar-pruebas-1-ENSAYO.sql) y con el OK de Miguel. Lo que Miguel decidió el 09/10, contrato
-- por contrato:
--   1. crm.anular_cierre_avance → los cierres de los leads de 2026-01-455468 (demo1234) y 2026-01-000000 (Jhosep Prueba);
--   2. crm.anular_cierre_externo → la cooperativa e6891c3e («DEMO DEMO DEMO», S/ 800);
--   3. public.marcar_contrato_demo → 2026-01-455468 (111111 no se puede: ver la nota de abajo).
-- Mismas puertas que la pantalla, firmando como ADMINISTRADOR AVANCE CORP. Las anulaciones no se deshacen; la marca de
-- prueba sí (la misma puerta con false). REALES, no se tocan: 001391, 001463, 001549 y los 6 de mayo a julio.
--
-- TODO O NADA, con postflight en la misma transacción. El resultado viaja como la ÚLTIMA fila (después del COMMIT).
-- 09/10: el ENSAYO v3 mostró que 2026-01-111111 NO se puede marcar: tiene una operación de cartera (upgrade) y la puerta
-- lo rechaza a propósito (P0409); «Eliminar inversión» también lo rechaza y no existe puerta para deshacer una operación
-- de cartera. Miguel decide aparte. Aquí queda fuera: se marca SOLO 455468.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $real$
declare
  c_firma_prefijo constant text := 'bf1c562e';   -- ADMINISTRADOR AVANCE CORP
  c_marcar constant text[] := array['2026-01-455468'];
  c_anular_de constant text[] := array['2026-01-455468', '2026-01-000000'];
  c_cooperativa constant text := 'e6891c3e';
  c_motivo constant text := 'Prueba del CRM, no es una venta: decision de Miguel del 09/10/2026 (auditoria de Facturacion).';
  v_n int;
  v_actor uuid;
  v_actor_nombre text;
  v_contratos uuid[] := '{}';
  v_leads uuid[] := '{}';
  v_coop uuid;
  v_id uuid;
  v_num text;
  v_sale jsonb;
begin
  -- 1) Lo que se toca, tal como lo vio el ensayo.
  foreach v_num in array c_marcar loop
    select c.id into v_id from public.contratos c where c.numero_contrato = v_num and not c.es_demo;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe o ya es de prueba', v_num;
    end if;
    v_contratos := v_contratos || v_id;
  end loop;
  foreach v_num in array c_anular_de loop
    select count(*) into v_n
      from crm.leads l join public.contratos c on c.id = l.contrato_id
     where c.numero_contrato = v_num and l.etapa = 'convertido'
       and not exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = l.id);
    if v_n <> 1 then
      raise exception 'ABORTA: el contrato % tiene % leads convertidos sin anular (se esperaba 1)', v_num, v_n;
    end if;
    select l.id into v_id
      from crm.leads l join public.contratos c on c.id = l.contrato_id
     where c.numero_contrato = v_num and l.etapa = 'convertido'
       and not exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = l.id);
    v_leads := v_leads || v_id;
  end loop;
  select count(*) into v_n from crm.cierres_externos x where left(x.id::text, 8) = c_cooperativa and x.anulado_en is null;
  if v_n <> 1 then
    raise exception 'ABORTA: la cooperativa % no es UNA fila sin anular (hay %)', c_cooperativa, v_n;
  end if;
  select x.id into v_coop from crm.cierres_externos x where left(x.id::text, 8) = c_cooperativa;

  -- 2) La firma.
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta de Gerencia elegida (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id, p.nombre_completo into v_actor, v_actor_nombre from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';

  -- 3) Las puertas como esa Gerencia. Cualquier error aborta TODO.
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_leads, 1) loop
    perform crm.anular_cierre_avance(v_leads[i], c_motivo);
  end loop;
  perform crm.anular_cierre_externo(v_coop, c_motivo);
  for i in 1 .. array_length(v_contratos, 1) loop
    perform public.marcar_contrato_demo(v_contratos[i], true, c_motivo);
  end loop;
  execute 'reset role';

  -- 4) Postflight en la MISMA transacción.
  select count(*) into v_n from crm.cierres_avance_anulados x
   where x.lead_id = any (v_leads) and x.anulado_por = v_actor and x.motivo = c_motivo;
  if v_n <> array_length(v_leads, 1) then
    raise exception 'ABORTA: % de % cierres quedaron anulados', v_n, array_length(v_leads, 1);
  end if;
  if not exists (select 1 from crm.cierres_externos x
                  where x.id = v_coop and x.anulado_en is not null and x.anulado_por = v_actor) then
    raise exception 'ABORTA: la cooperativa no quedó anulada';
  end if;
  select count(*) into v_n from public.contratos c where c.id = any (v_contratos) and c.es_demo;
  if v_n <> array_length(v_contratos, 1) then
    raise exception 'ABORTA: % de % contratos quedaron marcados como prueba', v_n, array_length(v_contratos, 1);
  end if;
  select count(*) into v_n from public.audit_log a
   where a.tabla = 'contratos' and a.operacion = 'demo_marca' and a.ts >= now()
     and a.fila_id = any (select x::text from unnest(v_contratos) x)
     and a.usuario_id = v_actor and a.data_despues ->> 'motivo' = c_motivo;
  if v_n <> array_length(v_contratos, 1) then
    raise exception 'ABORTA: hay % filas de motivo de la marca (se esperaban %)', v_n, array_length(v_contratos, 1);
  end if;
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}'::jsonb) into v_sale
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any (v_contratos) group by c.moneda) t;

  perform set_config('limpieza.real', jsonb_build_object(
    'resultado', 'OK: 2 cierres y la cooperativa anulados; 1 contrato marcado como prueba',
    'firma', v_actor_nombre, 'firma_id8', left(v_actor::text, 8),
    'cierres_anulados', c_anular_de, 'cooperativa_anulada', c_cooperativa,
    'marcados_como_prueba', c_marcar, 'sale_de_facturacion', v_sale)::text, false);
end
$real$;

commit;
select current_setting('limpieza.real', true)::jsonb as resultado;
```

### identificar-avancecorp.sql (solo lectura)

```sql
-- identificar-avancecorp.sql — SOLO LECTURA (09/10/2026). Los usuarios (no clientes) con «AVANCE» en el nombre o el correo,
-- para identificar el responsable de las ventas propias de la empresa antes de reasignarle nada.
begin transaction read only;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

select jsonb_agg(jsonb_build_object(
         'id8', left(p.id::text, 8),
         'nombre', p.nombre_completo,
         'correo', p.correo,
         'cargo', p.cargo,
         'rol_portal', p.rol,
         'rol_crm', private.rol_crm(p.id),
         'en_equipo_como', (select string_agg(e.rol_crm || case when e.activo then '' else ' (inactivo)' end, ', ')
                              from crm.equipo e where e.perfil_id = p.id),
         'activo', p.activo,
         'creado_en_lima', to_char(p.creado_en at time zone 'America/Lima', 'DD/MM/YYYY'),
         'ventas_a_su_nombre', (select count(*) from public.contratos c where c.analista_cierre_id = p.id and not c.es_demo),
         'leads_a_su_nombre', (select count(*) from crm.leads l where l.vendedor_id = p.id))
       order by p.nombre_completo) as usuarios_avance
  from public.perfiles p
 where (upper(p.nombre_completo) like '%AVANCE%' or upper(coalesce(p.correo, '')) like '%AVANCE%')
   and (p.rol <> 'cliente' or exists (select 1 from crm.equipo e where e.perfil_id = p.id));

rollback;
```

### reasignar-avance-1-ENSAYO.sql (v2, no escribe)

```sql
-- reasignar-avance-1-ENSAYO.sql (v2, 09/10/2026) — Decisión de Miguel: «ya tenemos un AVANCECORP, a ese quiero que lo
-- pongas». Las 3 ventas REALES que estaban a nombre del perfil de pruebas «MIGUEL BRICEÑO» (d731f284) pasan al perfil
-- AVANCECORP (NO a ADMINISTRADOR AVANCE CORP: la v1 apuntaba ahí y se apartó sin correr el REAL), por la MISMA puerta que
-- «Reasignar venta» de la pantalla: public.reasignar_analista_contrato (gerencia, motivo, fila inmutable en
-- crm.reasignaciones_analista). Firma la Gerencia ADMINISTRADOR AVANCE CORP (bf1c562e). Contratos: 2026-01-001391 (08/09,
-- US$ 5.000), 2026-01-001463 (20/09, S/ 5.000) y 2026-01-001549 (02/10, US$ 21.000).
--
-- El destino se busca por NOMBRE («AVANCECORP», sin espacios ni mayúsculas que importen) y tiene que ser UN solo perfil;
-- el mensaje enseña su id para fijarlo en el REAL, y todos los perfiles con «AVANCE» en el nombre.
-- ESTE ARCHIVO NO ESCRIBE NADA: termina SIEMPRE en `raise exception`. Veredicto «LISTO PARA 2-REAL» o «REVISAR».
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $ensayo$
declare
  c_perfil_pruebas constant uuid := 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2';
  c_firma_prefijo constant text := 'bf1c562e';   -- ADMINISTRADOR AVANCE CORP (firma)
  c_destino_nombre constant text := 'AVANCECORP';
  c_destino_prefijo constant text := 'd0468985';   -- identificado el 09/10: avancecorp@miavance.com, «Inversiones internas»
  c_numeros constant text[] := array['2026-01-001391', '2026-01-001463', '2026-01-001549'];
  c_motivo constant text := 'Venta de la empresa (AVANCECORP), no de un analista: estaba a nombre del perfil de pruebas. Decision de Miguel del 09/10/2026.';
  v_n int;
  v_firma uuid;
  v_destino uuid;
  v_destino_ficha jsonb;
  v_candidatos jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
  v_num text;
  v_res jsonb;
  v_pasos jsonb := '[]'::jsonb;
  v_ok int := 0;
  v_despues jsonb;
begin
  -- 0) Todos los perfiles con «AVANCE» en el nombre, para que Miguel vea a cuál apunta.
  select jsonb_agg(jsonb_build_object(
           'id8', left(p.id::text, 8), 'nombre', p.nombre_completo, 'activo', p.activo,
           'rol_crm', private.rol_crm(p.id),
           'en_equipo_como', (select string_agg(e.rol_crm, ',') from crm.equipo e where e.perfil_id = p.id))
           order by p.nombre_completo)
    into v_candidatos
    from public.perfiles p
   where upper(p.nombre_completo) like '%AVANCE%';

  -- 1) El destino: UN solo perfil llamado AVANCECORP y del equipo comercial (lo exige la puerta).
  select count(*) into v_n from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;
  if v_n <> 1 then
    raise exception 'ABORTA: hay % perfiles llamados AVANCECORP (se esperaba 1). Perfiles con AVANCE: %', v_n, v_candidatos;
  end if;
  select p.id, jsonb_build_object('id', p.id, 'nombre', p.nombre_completo, 'activo', p.activo,
                                  'rol_crm', private.rol_crm(p.id),
                                  'en_equipo_como', (select string_agg(e.rol_crm, ',') from crm.equipo e where e.perfil_id = p.id))
    into v_destino, v_destino_ficha
    from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;

  -- 2) Los 3: existen, no son de prueba y hoy están a nombre del perfil de pruebas.
  foreach v_num in array c_numeros loop
    select c.id into v_id from public.contratos c
     where c.numero_contrato = v_num and not c.es_demo and c.analista_cierre_id = c_perfil_pruebas;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe, es de prueba o ya no está a nombre del perfil de pruebas', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- 3) La firma: UN solo perfil con ese prefijo y rol CRM gerencia vigente.
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta que firma (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id into v_firma from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';

  -- 4) La puerta como esa Gerencia, contrato por contrato, sin parar en el primer fallo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_firma, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_firma::text, true);
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_ids, 1) loop
    begin
      v_res := public.reasignar_analista_contrato(v_ids[i], v_destino, c_motivo);
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('numero', c_numeros[i], 'ok', true));
      v_ok := v_ok + 1;
    exception when others then
      v_pasos := v_pasos || jsonb_build_array(jsonb_build_object('numero', c_numeros[i], 'ok', false,
                                                                 'error', sqlerrm, 'sqlstate', sqlstate));
    end;
  end loop;
  execute 'reset role';

  -- 5) Cómo queda la atribución (la que leen Facturación y Metas).
  select jsonb_agg(jsonb_build_object('numero', c.numero_contrato,
           'analista_atribuido', (select p.nombre_completo from public.perfiles p
                                   where p.id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)))
           order by c.numero_contrato)
    into v_despues from public.contratos c where c.id = any (v_ids);

  raise exception 'ENSAYO (no se escribió nada) · veredicto: % · pasos ok: % de 3 · destino: % · después: % · detalle: % · perfiles con AVANCE: %',
    case when v_ok = 3 then 'LISTO PARA 2-REAL' else 'REVISAR' end,
    v_ok, v_destino_ficha, v_despues, v_pasos, v_candidatos;
end
$ensayo$;

rollback;
```

### reasignar-avance-2-REAL.sql (v2, ESCRIBIÓ en producción el 09/10 10:55)

```sql
-- reasignar-avance-2-REAL.sql (v2, 09/10/2026) — ESCRIBE EN PRODUCCIÓN. Solo después de un ENSAYO «LISTO PARA 2-REAL»
-- (reasignar-avance-1-ENSAYO.sql v2). Decisión de Miguel: las 3 ventas REALES que estaban a nombre del perfil de pruebas
-- «MIGUEL BRICEÑO» (d731f284) pasan a AVANCECORP (d0468985, avancecorp@miavance.com, «Inversiones internas»: el responsable
-- de las ventas propias de la empresa), por la puerta de «Reasignar venta» (public.reasignar_analista_contrato), firmando
-- como la Gerencia ADMINISTRADOR AVANCE CORP (bf1c562e). 2026-01-001391, 001463 y 001549.
-- TODO O NADA, con postflight en la misma transacción. Reversa: la misma puerta hacia el analista anterior (deja su propia
-- fila). El resultado viaja como la ÚLTIMA fila.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $real$
declare
  c_perfil_pruebas constant uuid := 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2';
  c_firma_prefijo constant text := 'bf1c562e';     -- ADMINISTRADOR AVANCE CORP (firma)
  c_destino_nombre constant text := 'AVANCECORP';
  c_destino_prefijo constant text := 'd0468985';   -- AVANCECORP (destino)
  c_numeros constant text[] := array['2026-01-001391', '2026-01-001463', '2026-01-001549'];
  c_motivo constant text := 'Venta de la empresa (AVANCECORP), no de un analista: estaba a nombre del perfil de pruebas. Decision de Miguel del 09/10/2026.';
  v_n int;
  v_firma uuid;
  v_destino uuid;
  v_destino_nombre text;
  v_ids uuid[] := '{}';
  v_id uuid;
  v_num text;
  v_total jsonb;
begin
  -- 1) El destino: UN solo perfil AVANCECORP con ese prefijo.
  select count(*) into v_n from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;
  if v_n <> 1 then
    raise exception 'ABORTA: AVANCECORP (%) no es UN perfil (hay %)', c_destino_prefijo, v_n;
  end if;
  select p.id, p.nombre_completo into v_destino, v_destino_nombre from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;

  -- 2) Los 3: existen, no son de prueba y hoy están a nombre del perfil de pruebas.
  foreach v_num in array c_numeros loop
    select c.id into v_id from public.contratos c
     where c.numero_contrato = v_num and not c.es_demo and c.analista_cierre_id = c_perfil_pruebas;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe, es de prueba o ya no está a nombre del perfil de pruebas', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- 3) La firma.
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta que firma (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id into v_firma from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';

  -- 4) La puerta como esa Gerencia. Cualquier error aborta TODO.
  perform set_config('request.jwt.claims', json_build_object('sub', v_firma, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_firma::text, true);
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_ids, 1) loop
    perform public.reasignar_analista_contrato(v_ids[i], v_destino, c_motivo);
  end loop;
  execute 'reset role';

  -- 5) Postflight en la MISMA transacción: los 3 atribuidos a AVANCECORP y 3 filas de reasignación firmadas.
  select count(*) into v_n from public.contratos c
   where c.id = any (v_ids) and c.analista_cierre_id = v_destino
     and coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = v_destino;
  if v_n <> 3 then
    raise exception 'ABORTA: solo % de 3 quedaron a nombre de AVANCECORP', v_n;
  end if;
  select count(*) into v_n from crm.reasignaciones_analista r
   where r.contrato_id = any (v_ids) and r.analista_de = c_perfil_pruebas and r.analista_a = v_destino
     and r.reasignado_por = v_firma and r.motivo = c_motivo and r.reasignado_en >= now();
  if v_n <> 3 then
    raise exception 'ABORTA: hay % filas de reasignación (se esperaban 3)', v_n;
  end if;
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}'::jsonb) into v_total
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any (v_ids) group by c.moneda) t;

  perform set_config('reasignar.real', jsonb_build_object(
    'resultado', 'OK: 3 ventas a nombre de ' || v_destino_nombre,
    'destino_id8', left(v_destino::text, 8), 'firma_id8', left(v_firma::text, 8),
    'contratos', c_numeros, 'capital', v_total)::text, false);
end
$real$;

commit;
select current_setting('reasignar.real', true)::jsonb as resultado;
```

### reasignar-mayjul-1-ENSAYO.sql / reasignar-mayjul-2-REAL.sql (los 6 de mayo–julio; el REAL ESCRIBIÓ el 09/10 10:58)

Mismos guiones que los de sep–oct (arriba) con otra lista de contratos y conteos de 6. El REAL:

```sql
-- 09/10/2026 — MAYO A JULIO. Miguel: «pásalos todos a AVANCECORP». Los 6 contratos reales de mayo–julio que estaban a
-- nombre del perfil de pruebas «MIGUEL BRICEÑO»: 000625 (21/05, US$ 2.200), 000644 (26/05, US$ 6.667), 000713 (01/06,
-- S/ 33.334, upgrade), 000761 (09/06, S/ 20.000), 000827 (22/06, S/ 100.000) y 001037 (20/07, US$ 20.000). Mayo–julio no
-- están sellados. Mismo guion que el de las 3 de sep–oct (ya aplicado), solo cambia la lista.
-- reasignar-avance-2-REAL.sql (v2, 09/10/2026) — ESCRIBE EN PRODUCCIÓN. Solo después de un ENSAYO «LISTO PARA 2-REAL»
-- (reasignar-avance-1-ENSAYO.sql v2). Decisión de Miguel: las 3 ventas REALES que estaban a nombre del perfil de pruebas
-- «MIGUEL BRICEÑO» (d731f284) pasan a AVANCECORP (d0468985, avancecorp@miavance.com, «Inversiones internas»: el responsable
-- de las ventas propias de la empresa), por la puerta de «Reasignar venta» (public.reasignar_analista_contrato), firmando
-- como la Gerencia ADMINISTRADOR AVANCE CORP (bf1c562e). 2026-01-001391, 001463 y 001549.
-- TODO O NADA, con postflight en la misma transacción. Reversa: la misma puerta hacia el analista anterior (deja su propia
-- fila). El resultado viaja como la ÚLTIMA fila.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $real$
declare
  c_perfil_pruebas constant uuid := 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2';
  c_firma_prefijo constant text := 'bf1c562e';     -- ADMINISTRADOR AVANCE CORP (firma)
  c_destino_nombre constant text := 'AVANCECORP';
  c_destino_prefijo constant text := 'd0468985';   -- AVANCECORP (destino)
  c_numeros constant text[] := array['2026-01-000625', '2026-01-000644', '2026-01-000713', '2026-01-000761', '2026-01-000827', '2026-01-001037'];
  c_motivo constant text := 'Venta de la empresa (AVANCECORP), no de un analista: estaba a nombre del perfil de pruebas. Decision de Miguel del 09/10/2026.';
  v_n int;
  v_firma uuid;
  v_destino uuid;
  v_destino_nombre text;
  v_ids uuid[] := '{}';
  v_id uuid;
  v_num text;
  v_total jsonb;
begin
  -- 1) El destino: UN solo perfil AVANCECORP con ese prefijo.
  select count(*) into v_n from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;
  if v_n <> 1 then
    raise exception 'ABORTA: AVANCECORP (%) no es UN perfil (hay %)', c_destino_prefijo, v_n;
  end if;
  select p.id, p.nombre_completo into v_destino, v_destino_nombre from public.perfiles p
   where upper(regexp_replace(p.nombre_completo, '[^A-Za-z]', '', 'g')) = c_destino_nombre
     and left(p.id::text, length(c_destino_prefijo)) = c_destino_prefijo;

  -- 2) Los 6: existen, no son de prueba y hoy están a nombre del perfil de pruebas.
  foreach v_num in array c_numeros loop
    select c.id into v_id from public.contratos c
     where c.numero_contrato = v_num and not c.es_demo and c.analista_cierre_id = c_perfil_pruebas;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe, es de prueba o ya no está a nombre del perfil de pruebas', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- 3) La firma.
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta que firma (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id into v_firma from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';

  -- 4) La puerta como esa Gerencia. Cualquier error aborta TODO.
  perform set_config('request.jwt.claims', json_build_object('sub', v_firma, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_firma::text, true);
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_ids, 1) loop
    perform public.reasignar_analista_contrato(v_ids[i], v_destino, c_motivo);
  end loop;
  execute 'reset role';

  -- 5) Postflight en la MISMA transacción: los 6 atribuidos a AVANCECORP y 6 filas de reasignación firmadas.
  select count(*) into v_n from public.contratos c
   where c.id = any (v_ids) and c.analista_cierre_id = v_destino
     and coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = v_destino;
  if v_n <> 6 then
    raise exception 'ABORTA: solo % de 6 quedaron a nombre de AVANCECORP', v_n;
  end if;
  select count(*) into v_n from crm.reasignaciones_analista r
   where r.contrato_id = any (v_ids) and r.analista_de = c_perfil_pruebas and r.analista_a = v_destino
     and r.reasignado_por = v_firma and r.motivo = c_motivo and r.reasignado_en >= now();
  if v_n <> 6 then
    raise exception 'ABORTA: hay % filas de reasignación (se esperaban 6)', v_n;
  end if;
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}'::jsonb) into v_total
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any (v_ids) group by c.moneda) t;

  perform set_config('reasignar.real', jsonb_build_object(
    'resultado', 'OK: 6 ventas de mayo a julio a nombre de ' || v_destino_nombre,
    'destino_id8', left(v_destino::text, 8), 'firma_id8', left(v_firma::text, 8),
    'contratos', c_numeros, 'capital', v_total)::text, false);
end
$real$;

commit;
select current_setting('reasignar.real', true)::jsonb as resultado;
```

### eliminar-111111-1-ENSAYO.sql (no escribe)

```sql
-- eliminar-111111-1-ENSAYO.sql (09/10/2026) — Miguel quiere eliminar 2026-01-111111 (upgrade de prueba de Vladimir Jurado,
-- S/ 1.000, septiembre) y la pantalla le responde que es «parte de un upgrade o una renovación». Medido hoy: es el contrato
-- NUEVO de una operación upgrade SIN contrato de origen, no está en crm.inversiones, nadie lo renueva y septiembre sigue
-- abierto. Este ensayo llama a la MISMA función que usa «Eliminar contrato» (portal y CRM, vía la Edge crm-contrato-pdf-v2,
-- action delete-audited): crm.contrato_eliminar_auditado(contrato, actor), con el actor ADMINISTRADOR AVANCE CORP
-- (superadmin del portal). El trigger trg_contratos_05_restaurar_operacion borra su operación de upgrade.
-- NO ESCRIBE NADA: termina SIEMPRE en `raise exception`. Si sale bien, dice «LISTO PARA 2-REAL»; si no, da el error EXACTO.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $ensayo$
declare
  c_numero constant text := '2026-01-111111';
  c_actor_prefijo constant text := 'bf1c562e';   -- ADMINISTRADOR AVANCE CORP (superadmin del portal)
  v_id uuid;
  v_actor uuid;
  v_n int;
  v_res jsonb;
  v_estado text := 'ok';
  v_error text;
begin
  select c.id into v_id from public.contratos c
   where c.numero_contrato = c_numero and not c.es_demo
     and exists (select 1 from crm.operaciones_cartera o
                  where o.contrato_nuevo_id = c.id and o.contrato_origen_id is null and o.tipo = 'upgrade');
  if v_id is null then
    raise exception 'ABORTA: % ya no está como se midió (contrato activo, upgrade sin origen)', c_numero;
  end if;
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_actor_prefijo)) = c_actor_prefijo and p.rol = 'superadmin' and p.activo;
  if v_n <> 1 then
    raise exception 'ABORTA: el actor (%) no es UN superadmin activo (hay %)', c_actor_prefijo, v_n;
  end if;
  select p.id into v_actor from public.perfiles p
   where left(p.id::text, length(c_actor_prefijo)) = c_actor_prefijo and p.rol = 'superadmin' and p.activo;

  begin
    v_res := crm.contrato_eliminar_auditado(v_id, v_actor);
  exception when others then
    v_estado := sqlstate;
    v_error := sqlerrm;
  end;

  raise exception 'ENSAYO (no se escribió nada) · veredicto: % · respuesta: % · error: % · después quedarían: contrato %, operación %, copia de auditoría %',
    case when v_estado = 'ok' then 'LISTO PARA 2-REAL' else 'REVISAR' end,
    v_res, coalesce(v_estado || ' — ' || v_error, 'ninguno'),
    (select count(*) from public.contratos c where c.id = v_id),
    (select count(*) from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id),
    (select count(*) from crm.contratos_eliminados_auditoria a where a.contrato_id = v_id);
end
$ensayo$;

rollback;
```

### eliminar-111111-2-REAL.sql (ESCRIBIÓ en producción el 09/10 11:57)

```sql
-- eliminar-111111-2-REAL.sql (09/10/2026) — ESCRIBE EN PRODUCCIÓN. Solo después de un ENSAYO «LISTO PARA 2-REAL».
-- Elimina 2026-01-111111 (upgrade de prueba, S/ 1.000, septiembre) con la MISMA función que «Eliminar contrato» del portal
-- y del CRM: crm.contrato_eliminar_auditado (copia de auditoría; los PDF quedan como evidencia; borra su operación de
-- upgrade). Actor: ADMINISTRADOR AVANCE CORP. TODO O NADA, con postflight; el resultado es la ÚLTIMA fila.
-- Antes del sello de septiembre (11/10 09:20): después el sistema ya no deja eliminarlo.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $real$
declare
  c_numero constant text := '2026-01-111111';
  c_actor_prefijo constant text := 'bf1c562e';
  v_id uuid;
  v_actor uuid;
  v_n int;
  v_res jsonb;
begin
  select c.id into v_id from public.contratos c
   where c.numero_contrato = c_numero and not c.es_demo
     and exists (select 1 from crm.operaciones_cartera o
                  where o.contrato_nuevo_id = c.id and o.contrato_origen_id is null and o.tipo = 'upgrade');
  if v_id is null then
    raise exception 'ABORTA: % ya no está como se midió (contrato activo, upgrade sin origen)', c_numero;
  end if;
  select count(*) into v_n from public.perfiles p
   where left(p.id::text, length(c_actor_prefijo)) = c_actor_prefijo and p.rol = 'superadmin' and p.activo;
  if v_n <> 1 then
    raise exception 'ABORTA: el actor (%) no es UN superadmin activo (hay %)', c_actor_prefijo, v_n;
  end if;
  select p.id into v_actor from public.perfiles p
   where left(p.id::text, length(c_actor_prefijo)) = c_actor_prefijo and p.rol = 'superadmin' and p.activo;

  v_res := crm.contrato_eliminar_auditado(v_id, v_actor);

  -- Postflight en la MISMA transacción.
  if exists (select 1 from public.contratos c where c.id = v_id) then
    raise exception 'ABORTA: el contrato sigue existiendo';
  end if;
  if exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id) then
    raise exception 'ABORTA: su operación de upgrade sigue existiendo';
  end if;
  if not exists (select 1 from crm.contratos_eliminados_auditoria a where a.contrato_id = v_id) then
    raise exception 'ABORTA: no quedó la copia de auditoría';
  end if;

  perform set_config('eliminar.real', jsonb_build_object(
    'resultado', 'OK: 2026-01-111111 eliminado con copia de auditoría (y su operación de upgrade)',
    'respuesta', v_res, 'actor_id8', left(v_actor::text, 8))::text, false);
end
$real$;

commit;
select current_setting('eliminar.real', true)::jsonb as resultado;
```

-- ============================================================================
-- Migración E — un cierre por conversión no puede quedarse SIN FECHA, y un lead
--                no puede convertirse DOS VECES: las dos filas malas dejan de
--                ser representables en el ALMACENAMIENTO
-- ============================================================================
-- Solo endurece `crm.lead_asignaciones`: un CHECK nuevo y un índice único
-- parcial. No redefine funciones, no cambia firmas, no mueve grants, no toca
-- `public`, no añade columnas ni tablas.
--
-- ORDEN DE APLICACIÓN — leer antes de crear el branch
-- ---------------------------------------------------------------------------
-- E no depende funcionalmente de ninguna otra migración del ciclo: no lee ni
-- redefine nada suyo. Se aplica después de la A
-- (`20260811154434_crm_conversion_mensual_ponderada.sql`) porque A crea sobre
-- esta misma tabla los dos índices del numerador y conviene no intercalar DDL
-- entre su creación y su comprobación; con la D vigente
-- (`20260811190324_crm_origen_inmutable.sql`) el orden es indiferente en los dos
-- sentidos. Por nombre de fichero la secuencia queda A → E → D, y así vale.
-- ⚠️ `20260811164017_crm_origen_inmutable_correccion_gerencia.sql` está
-- DESCARTADA (lo dice la cabecera de 190324) y HAY QUE BORRARLA DEL ÁRBOL antes
-- del branch. Ninguna cita de este fichero apunta ya a ella.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LOS DOS AGUJEROS: DÓNDE ESTÁN DE VERDAD Y QUÉ QUEDA VIVO HOY
-- ─────────────────────────────────────────────────────────────────────────────
-- Corrección sobre el borrador de esta misma migración, y conviene leerla antes
-- que nada porque cambia el encuadre entero: el borrador decía que la migración
-- A fecha el numerador con `resultado_en` a secas y lo cuenta con `count(*)`, y
-- de ahí sacaba un 0 % y un 200 % «medidos». **Eso no es lo que A hace.** A ya
-- se defendió de los dos agujeros EN LA CONSULTA, y lo documenta en su propia
-- cabecera, en la sección «Cinturón y tirantes», con los rótulos «AGUJERO 1» y
-- «AGUJERO 2»:
--
--   · su CTE `cierres` fecha con `coalesce(la.resultado_en, la.finalizado_en)`,
--     no con `resultado_en`; la sonda `cierres_sin_episodio` usa el mismo
--     coalesce;
--   · su CTE `agg_cie` cuenta `count(distinct c.lead_id) filter (...)`, no
--     `count(*)`.
--
-- (Las referencias a A van por NOMBRE DE CTE y no por número de línea: ese
-- fichero sigue vivo en este mismo ciclo y sus líneas se mueven. El borrador
-- citaba `:526-537` y `:565-570` y ninguna de las dos apuntaba al numerador.)
--
-- Así que hoy, con A desplegada, el 0 % y el 200 % de aquel borrador NO están en
-- pantalla. Lo que E aporta es otra cosa, y es mayor: A esquiva los dos estados
-- imposibles en la LECTURA; E los hace irrepresentables en la ESCRITURA. Un
-- esquive vale para la consulta que lo lleva escrito; un constraint vale para
-- todas las consultas que existan y las que se escriban mañana.
--
-- Y hay DOS boquetes que las defensas de A dejan vivos hoy mismo. No son
-- retóricos: son los que justifican esta migración por sí solos.
--
-- ── BOQUETE VIVO 1 · la conversión que no dice que lo es ────────────────────
-- `lead_asignaciones_cierre_consistente` (creado en 20260717212639:89-148 y
-- releído byte a byte con `pg_get_constraintdef` contra producción el
-- 2026-08-11) exige, en la rama de `motivo_cierre = 'convertido'`:
--
--     motivo_cierre = 'convertido' AND ... AND resultado = 'convertido'
--       AND resultado_en = finalizado_en AND motivo_descarte_cierre IS NULL
--
-- Si `resultado` llega NULL, `resultado = 'convertido'` **no es FALSE: es
-- NULL**; el AND da NULL, el OR de las cinco ramas da NULL, y un CHECK **solo
-- rechaza cuando el predicado es FALSE**. La fila ENTRA: un episodio cuyo
-- `motivo_cierre` dice «convertido» y cuya columna `resultado` está vacía.
-- La CTE `cierres` de A empieza por `where la.resultado = 'convertido'`, o sea
-- que ESE cierre no lo ve: divisor 1, numerador 0, **0 % donde la verdad es
-- 100 %**. A lo reconoce como «RESIDUO CONOCIDO» en su cabecera y confía en que
-- lo delate la sonda `cierres_sin_episodio` — pero esa sonda solo canta si
-- `crm.leads` dice `etapa='convertido'` con `convertido_en` dentro del mes, y el
-- mismo backfill con triggers apagados que escribe el episodio torcido puede
-- perfectamente no tocar la ficha. El residuo puede ser MUDO. Con el CHECK de
-- §1 la fila no existe y el residuo desaparece.
-- (La otra variante —`resultado` correcto y `resultado_en` NULL— entra por el
-- mismo motivo, y esa sí la esquiva A con su `coalesce`. E la cierra igual: el
-- ledger no debe poder afirmar un resultado sin fecharlo.)
--
-- ── BOQUETE VIVO 2 · el lead que se convierte para dos ──────────────────────
-- El EXCLUDE `lead_asignaciones_sin_solape` compara
-- `tstzrange(asignado_en, coalesce(finalizado_en,'infinity'), '[)')`. Ese rango
-- es **vacío** cuando `finalizado_en = asignado_en`, y un rango vacío no se
-- solapa con nada; `lead_asignaciones_intervalo_valido` permite ese `>=`. Y la
-- duración cero **ni siquiera hace falta**: dos episodios `convertido`
-- ADYACENTES y no vacíos —[10:00,11:00) y [11:00,12:00)— pasan el EXCLUDE
-- igual, porque `'[)'` excluye el extremo derecho. Verificado con INSERT reales.
--
-- El `count(distinct c.lead_id)` de A cubre esto **dentro de un analista**: si
-- los dos cierres son del mismo, el lead pesa 1 y su fila da 100 %. Pero su CTE
-- `agg_cie` hace `group by c.analista_id`, así que dos cierres del mismo lead
-- atribuidos a analistas DISTINTOS son dos filas de 1, y el total del equipo los
-- suma tal cual (CTE `resumen`: `coalesce(sum(f.cierres_no_referidos), 0)`). El
-- caso concreto: el lead nace en julio con Beto y en agosto se reasigna a Ana;
-- los DOS episodios quedan cerrados como 'convertido'. En el informe de agosto
-- el divisor recoge solo a Ana (la CTE `recibidos` filtra por `asignado_en`) y
-- los cierres recogen a los dos → divisor 1, cierres 2, **200 % de equipo por un
-- solo lead**. El `distinct` de A no puede cubrirlo: para verlo tendría que
-- de-duplicar ANTES de repartir por analista, y entonces no podría atribuir. Un
-- índice único por lead sí puede, porque actúa antes de que la fila exista.
--
-- ── LOS DOS NÚMEROS, MEDIDOS CONTRA LA ARITMÉTICA REAL DE A ─────────────────
-- No son un razonamiento. Se sembraron los dos estados en la réplica PG 17.10 y
-- se les pasó la aritmética LITERAL de A tal como está hoy en disco —CTE
-- `recibidos` con `group by (analista, lead)`, CTE `cierres` con
-- `coalesce(resultado_en, finalizado_en)`, CTE `agg_cie` con
-- `count(distinct lead_id)` agrupado por analista, CTE `resumen` sumando por
-- equipo—:
--   · boquete 1 (motivo_cierre='convertido', `resultado` NULL, un lead no
--     referido recibido y cerrado en el mes) → divisor 1, cierres 0, **0,0 %**;
--   · boquete 2 (un lead con dos episodios 'convertido', el de julio de Beto y
--     el de agosto de Ana) → divisor 1, cierres 2, **200,0 % de equipo**.
-- Con las dos filas ya imposibles, las mismas consultas devuelven 100 % y 100 %.
--
-- ── DESPUÉS DE ESTA MIGRACIÓN ───────────────────────────────────────────────
--   · Las filas del boquete 1 se rechazan con 23514 sobre
--     `lead_asignaciones_cierre_no_trivaluado`.
--   · La segunda fila del boquete 2 se rechaza con 23505 sobre
--     `lead_asignaciones_una_conversion_por_lead_idx`.
--   · El caso legítimo —un lead, una conversión bien formada— sigue entrando.
--   · El `coalesce` y el `count(distinct)` de A quedan como cinturón sobre un
--     tirante ya puesto. No se tocan: cuestan cero y son la defensa correcta
--     para los meses YA escritos antes de que exista este constraint.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- POR QUÉ HACE FALTA UN CONSTRAINT SI YA HAY TRIGGERS QUE LO IMPIDEN
-- ─────────────────────────────────────────────────────────────────────────────
-- Hoy «un lead se convierte una sola vez» lo sostienen tres piezas de CÓDIGO, y
-- las tres se verificaron vivas contra producción (no contra el fichero):
--   · `crm.convertir_lead` rechaza un lead ya cerrado (20260807123000:195-303);
--   · `private.leads_before_update` exige la válvula `crm.op_privilegiada` para
--     poner `etapa='convertido'`;
--   · `private.trg_leads_guard_tenencia` lanza «Un lead convertido no se puede
--     reabrir» (20260803164348:562) y —esto es lo bueno— **no tiene válvula**:
--     `position('op_privilegiada' in prosrc) = 0`, así que ni una RPC
--     privilegiada lo esquiva. Su trigger está `tgenabled = 'O'`.
-- Y el propio ledger tiene su guardia: `private.trg_lead_asignaciones_inmutables`
-- exige `crm.ledger_writer = 'on'` **y** `pg_trigger_depth() >= 2`, o sea que un
-- INSERT a pelo contra `crm.lead_asignaciones` hoy rebota antes de llegar a
-- ningún CHECK.
--
-- Los tres caminos de retroceso del CRM se recorrieron uno a uno y **ninguno
-- sale de `convertido`**: `private.retroceso_por_anular_reunion` filtra
-- `etapa = 'reunion_agendada'` (20260726151751:340-407); el re-encolado de
-- `private.trg_leads_sync_tareas` exige lo mismo (20260809024942:141-235); y
-- `crm.deshacer_descarte` exige `etapa = 'descartado'` (20260723120000:507-568).
-- La única salida de un estado terminal es descartado → nuevo, y esa incrementa
-- `ciclo_actual`. Una renovación tampoco vuelve al mismo lead:
-- `uq_leads_dni_vivo` y `uq_leads_telefono_vivo` excluyen convertido/descartado
-- y `crm.verificar_disponibilidad_lead` devuelve `ya_es_cliente`.
--
-- **Todo eso es código, y el código se apaga.** `alter table ... disable
-- trigger` es un patrón YA USADO sobre esta misma tabla en este repositorio
-- (20260807203757:747-748, backfill del snapshot SLA); un backfill privilegiado
-- escribe donde quiere; y `crm.ledger_writer` es un GUC que cualquiera con
-- conexión de servicio puede poner en 'on'. Un CHECK y un índice único no se
-- apagan con un `set`: viven en el ALMACENAMIENTO y los evalúa el ejecutor
-- aunque no quede un solo trigger en pie. Por eso esta migración no añade un
-- trigger más: añade dos invariantes.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LAS TRES DECISIONES DE DISEÑO, Y LO QUE SE DESCARTÓ
-- ─────────────────────────────────────────────────────────────────────────────
-- (1) CHECK **complementario**, no reescritura del original.
--       a) `lead_asignaciones_cierre_consistente` es un predicado de ~40 líneas
--          con cinco ramas. Reescribirlo obliga a transcribirlo entero, y un
--          error de transcripción **ensancha lo permitido en silencio** — el
--          mismo tipo de fallo que causó el agujero que venimos a cerrar. No
--          tocarlo es cero riesgo, y sus otras cuatro ramas quedan conservadas
--          byte a byte por construcción, no por copia cuidadosa.
--       b) El complemento cabe en cuatro términos y **cada término es
--          demostrablemente bivaluado**: `x is null` y `a is not distinct from b`
--          nunca devuelven NULL, y una igualdad entre dos booleanos no nulos
--          tampoco. El arreglo no puede repetir el bug que arregla.
--       c) Diagnóstico: una violación nombra
--          `lead_asignaciones_cierre_no_trivaluado`, que apunta a la regla rota,
--          en vez del constraint-monolito que solo dice «algo del cierre».
--       d) El original conserva su estado `validated` intacto.
--     Se añade con `not valid` + `validate constraint` (el patrón del proyecto):
--     el `add` toma el lock un instante y el escaneo va aparte.
--
-- (2) ÍNDICE ÚNICO PARCIAL por lead, con el predicado sobre **las dos
--     columnas**: `where motivo_cierre = 'convertido' or resultado =
--     'convertido'`. Cada mitad es la red de la otra:
--       · con el CHECK de §1 vivo, `motivo_cierre='convertido'` y
--         `resultado='convertido'` son equivalentes, así que la mitad
--         `resultado` es la que sigue en pie si alguien retira §1;
--       · con el CHECK ORIGINAL vivo, una fila con `resultado='convertido'` y
--         `motivo_cierre` distinto es irrepresentable, así que la mitad
--         `motivo_cierre` es la que sigue en pie si alguien retira el original.
--     Las dos mitades se prueban POR SEPARADO en §3 (casos R11 y R12, sobre una
--     réplica sin los dos CHECK): no es una redundancia declarada de palabra,
--     está asertada.
--     El índice es por `lead_id` **a secas**, no por `(lead_id, ciclo_n)`: un
--     lead descartado en el ciclo 1 y convertido en el ciclo 2 sigue siendo UNA
--     conversión en toda su vida. Y es sobre la CONVERSIÓN, no sobre `resultado`
--     a secas: los descartes repetidos del mismo lead (descartar → deshacer →
--     descartar) son un flujo vivo y deben seguir entrando (caso A3).
--     Sin `concurrently`: la tabla tiene 1 fila en producción (verificado) y la
--     migración va en transacción, donde `concurrently` no está permitido.
--
-- (3) NO se toca `lead_asignaciones_intervalo_valido` ni
--     `lead_asignaciones_sin_solape`. Se consideró endurecer el `>=` a `>` y se
--     descartó, porque hay flujos legítimos de duración cero:
--       · `statement_timestamp()` es CONSTANTE dentro de una función plpgsql. El
--         ledger sella con ese reloj tanto la apertura (`new.creado_en`, forzado
--         en 20260717212639:367) como el cierre (`v_evento_en :=
--         statement_timestamp()`, :636). Cualquier comando que mueva DOS veces
--         la tenencia del mismo lead abre y cierra en el MISMO instante. El `>=`
--         de :87 no es un descuido: es el reloj del propio ledger.
--       · Un episodio de duración cero con `motivo_cierre` en
--         transferido/parqueado/desactivado es papeleo VERDADERO: el lead pasó
--         por ese analista, aunque fuera un instante. Con `>` estricto ese
--         reparto correcto abortaría con 23514 en la cara del usuario. El caso
--         A1 de §3 lo deja asertado, y va ANTES que los casos de duración cero
--         ilegítima para que, si alguien endurece el intervalo, el diagnóstico
--         salga por su nombre y no disfrazado de fallo del índice.
--       · Y sobre todo: `>` estricto **no cierra el boquete 2**, porque las dos
--         conversiones adyacentes NO vacías pasan igual el EXCLUDE (caso R5).
--     Cambiar `'[)'` por `'[]'` es peor: haría chocar dos episodios legítimos
--     consecutivos en su instante de relevo. El rango vacío no es el problema de
--     fondo; el problema de fondo es que nada decía «un lead se convierte una
--     sola vez». Eso es lo que se escribe ahora.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LO QUE ESTA MIGRACIÓN **NO** HACE
-- ─────────────────────────────────────────────────────────────────────────────
-- · **No cambia la métrica.** No hay ninguna decisión pendiente sobre el
--   `count(distinct)`: A YA lo lleva en su CTE `agg_cie`. Redefinir
--   `private.conversion_mensual_por_vendedor` para «reforzarlo» sería reproducir
--   entera una función de 200 líneas recién desplegada, que es exactamente el
--   riesgo de transcripción que la decisión (1) evita.
-- · **No impide elegir mal el origen en el alta** (eso es la migración D), ni
--   toca nada de `public`, ni añade columnas (por tanto no hay grants por
--   columna que dar: `crm.lead_asignaciones` no tiene ni un grant fuera del
--   owner), ni crea tablas permanentes (por tanto no hay RLS nueva que
--   declarar), ni añade ninguna policy DELETE.
--
-- Verificado contra producción (dctqcbznekcyxhjujuci, solo SELECT, 2026-08-11):
-- `crm.lead_asignaciones` = 1 fila, 1 abierta, 0 con `resultado`, 0 con
-- `motivo_cierre` terminal mal formado, 0 de duración cero, 0 leads con dos
-- conversiones. Los dos endurecimientos entran con CERO filas en conflicto. El
-- preflight de §0 lo vuelve a comprobar en el momento de aplicar, porque «lo
-- verifiqué hace un rato» no es una garantía transaccional.
--
-- Toda la evidencia SQL de este fichero se reprodujo en un PostgreSQL **17.10**
-- efímero sobre una réplica de `crm.lead_asignaciones` construida con los
-- `pg_get_constraintdef` sacados de producción, con el rol dueño creado
-- `nosuperuser` igual que el `postgres` de este proyecto. Producción corre
-- **17.6**: misma rama mayor, mismo comportamiento de CHECK trivaluados,
-- `constraint_name` en `get stacked diagnostics` y `LIKE ... INCLUDING ALL`.
-- La comprobación en la versión exacta la da el ciclo obligatorio del proyecto:
-- branch de Supabase → aplicar → `test-rls.mjs` → advisors → merge.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Preflight — ¿hay alguna fila que lo que voy a exigir dejaría fuera?
-- ---------------------------------------------------------------------------
-- No es decoración: `validate constraint` y `create unique index` fallan igual
-- con datos sucios, pero fallan con un mensaje que no dice CUÁNTAS filas ni
-- CUÁLES. Aquí se aborta con el recuento y con la consulta exacta para
-- listarlas.
--
-- ⚠️ TODAS las comparaciones de este bloque son BIVALUADAS. El borrador de este
-- preflight comparaba `(resultado = 'convertido') is distinct from
-- (motivo_cierre = 'convertido')`, y eso comete EL MISMO error que la migración
-- viene a arreglar, pero en la otra dirección: para un episodio `transferido`
-- —`resultado` NULL, que el CHECK original EXIGE— el primer paréntesis da NULL,
-- el segundo da FALSE, y `NULL IS DISTINCT FROM FALSE` es TRUE. O sea que
-- marcaba como ilegal el reparto de un lead, que es el movimiento más común del
-- CRM, y abortaba la migración exigiendo «arreglar» filas sanas. Hoy no explota
-- solo porque producción tiene un único episodio ABIERTO; en cuanto se
-- transfiera, parquee o desactive un lead —o en cualquier branch sembrado con
-- el fixture— la migración sería inaplicable. Reproducido en PG 17.10 y
-- corregido: `is not distinct from` en los dos lados de la equivalencia.
do $preflight$
declare
  v_res_sin_fecha     bigint;
  v_fecha_sin_res     bigint;
  v_conv_desalineado  bigint;
  v_desc_desalineado  bigint;
  v_sello_desalineado bigint;
  v_leads_2conv       bigint;
  v_msj               text := '';
begin
  select
    -- (a) resultado y resultado_en tienen que ir juntos, en los dos sentidos.
    count(*) filter (where resultado is not null and resultado_en is null),
    count(*) filter (where resultado_en is not null and resultado is null),
    -- (b) y (c) la EQUIVALENCIA motivo_cierre <=> resultado, en los dos
    -- sentidos y sin trivaluación: un episodio transferido/parqueado/
    -- desactivado tiene los dos lados en FALSE y NO se marca.
    count(*) filter (
      where (motivo_cierre is not distinct from 'convertido')
         <> (resultado is not distinct from 'convertido')),
    count(*) filter (
      where (motivo_cierre is not distinct from 'descartado')
         <> (resultado is not distinct from 'descartado')),
    -- (d) el sello: si hay resultado, se fecha en el instante del cierre.
    count(*) filter (where resultado is not null
                       and (resultado_en is null
                            or finalizado_en is null
                            or resultado_en <> finalizado_en))
  into v_res_sin_fecha, v_fecha_sin_res, v_conv_desalineado,
       v_desc_desalineado, v_sello_desalineado
  from crm.lead_asignaciones;

  select count(*)
  into v_leads_2conv
  from (
    select lead_id
    from crm.lead_asignaciones
    where motivo_cierre = 'convertido' or resultado = 'convertido'
    group by lead_id
    having count(*) > 1
  ) t;

  if v_res_sin_fecha > 0 then
    v_msj := v_msj || format(
      E'\n  · %s fila(s) con `resultado` y SIN `resultado_en` (boquete 1).',
      v_res_sin_fecha);
  end if;
  if v_fecha_sin_res > 0 then
    v_msj := v_msj || format(
      E'\n  · %s fila(s) con `resultado_en` y SIN `resultado`.', v_fecha_sin_res);
  end if;
  if v_conv_desalineado > 0 then
    v_msj := v_msj || format(
      E'\n  · %s fila(s) donde motivo_cierre=''convertido'' y resultado=''convertido'' no van de la mano (en cualquiera de los dos sentidos).',
      v_conv_desalineado);
  end if;
  if v_desc_desalineado > 0 then
    v_msj := v_msj || format(
      E'\n  · %s fila(s) donde motivo_cierre=''descartado'' y resultado=''descartado'' no van de la mano (en cualquiera de los dos sentidos).',
      v_desc_desalineado);
  end if;
  if v_sello_desalineado > 0 then
    v_msj := v_msj || format(
      E'\n  · %s fila(s) con `resultado` cuyo `resultado_en` no coincide con `finalizado_en`.',
      v_sello_desalineado);
  end if;
  if v_leads_2conv > 0 then
    v_msj := v_msj || format(
      E'\n  · %s lead(s) con MÁS DE UN cierre por conversión (boquete 2).',
      v_leads_2conv);
  end if;

  if v_msj <> '' then
    raise exception E'PREFLIGHT: crm.lead_asignaciones ya tiene filas que los endurecimientos de esta migración prohíben.%\n\nListarlas:\n  select id, lead_id, ciclo_n, episodio_n, analista_id, asignado_en, finalizado_en,\n         motivo_cierre, resultado, resultado_en\n  from crm.lead_asignaciones\n  where (resultado is null) <> (resultado_en is null)\n     or (motivo_cierre is not distinct from ''convertido'')\n        <> (resultado is not distinct from ''convertido'')\n     or (motivo_cierre is not distinct from ''descartado'')\n        <> (resultado is not distinct from ''descartado'')\n     or (resultado is not null and resultado_en is distinct from finalizado_en)\n     or lead_id in (select lead_id from crm.lead_asignaciones\n                    where motivo_cierre = ''convertido'' or resultado = ''convertido''\n                    group by lead_id having count(*) > 1)\n  order by lead_id, ciclo_n, episodio_n;\n\nNO se corrigen desde aquí: un episodio cerrado es inmutable y decidir qué dato es el bueno es de negocio, no de una migración.',
      v_msj
      using errcode = 'P0400';
  end if;

  -- Preflight de identidad, no de datos: si alguien renombró o retiró
  -- `lead_asignaciones_cierre_consistente`, esta migración estaría añadiendo su
  -- complemento a un original que ya no existe y el resultado sería más débil de
  -- lo que su cabecera promete.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'crm.lead_asignaciones'::regclass
      and conname = 'lead_asignaciones_cierre_consistente'
      and contype = 'c'
  ) then
    raise exception 'PREFLIGHT: no existe el CHECK lead_asignaciones_cierre_consistente; esta migración lo COMPLEMENTA y no lo sustituye. Revisar antes de seguir.'
      using errcode = 'P0400';
  end if;

  raise notice 'PREFLIGHT OK: % fila(s) en el ledger, ninguna en conflicto.',
    (select count(*) from crm.lead_asignaciones);
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. BOQUETE 1 — el cierre mal sellado deja de ser representable
-- ---------------------------------------------------------------------------
-- Cuatro términos, ninguno capaz de devolver NULL:
--
--   (a) `(resultado is null) = (resultado_en is null)`
--       `is null` devuelve boolean NUNCA nulo; comparar dos booleanos no nulos
--       tampoco. «Van juntos o no van», en los dos sentidos. (Aislado en el caso
--       R8 de §3, sobre una réplica sin el CHECK original.)
--
--   (b) y (c) `(motivo_cierre is not distinct from 'x') = (resultado is not
--       distinct from 'x')`
--       `is not distinct from` es la igualdad que trata NULL como un valor:
--       tampoco devuelve NULL jamás. Convierte la relación entre `motivo_cierre`
--       y `resultado` en una EQUIVALENCIA en los dos sentidos, y mata la
--       variante (motivo_cierre='convertido', resultado NULL) — el boquete vivo
--       que el numerador de A no ve. (Aisladas en R2, R3 y R10.)
--
--   (d) `resultado is null or (resultado_en is not null and finalizado_en is
--       not null and resultado_en = finalizado_en)`
--       La igualdad SOLO se evalúa detrás de dos `is not null`, así que el
--       término entero es bivaluado. Sella el reloj: el resultado se fecha en el
--       instante del cierre, no en otro. (Aislado en R9.)
--
-- Deliberadamente NO se usa `=` sobre columnas nullables en ningún sitio: esa
-- forma es la que abrió el agujero.
alter table crm.lead_asignaciones
  add constraint lead_asignaciones_cierre_no_trivaluado check (
    (resultado is null) = (resultado_en is null)
    and (motivo_cierre is not distinct from 'convertido')
        = (resultado is not distinct from 'convertido')
    and (motivo_cierre is not distinct from 'descartado')
        = (resultado is not distinct from 'descartado')
    and (
      resultado is null
      or (
        resultado_en is not null
        and finalizado_en is not null
        and resultado_en = finalizado_en
      )
    )
  ) not valid;

alter table crm.lead_asignaciones
  validate constraint lead_asignaciones_cierre_no_trivaluado;

comment on constraint lead_asignaciones_cierre_no_trivaluado
  on crm.lead_asignaciones is
  'Complemento BIVALUADO de lead_asignaciones_cierre_consistente, que se escribio con `=` sobre columnas nullables: alli `resultado = ''convertido''` con resultado NULL da NULL, el CHECK entero da NULL y PASA (un CHECK solo rechaza en FALSE). Aqui todo termino usa `is null` o `is not distinct from`, que nunca devuelven NULL. Efecto: resultado y resultado_en van juntos siempre, motivo_cierre=convertido <=> resultado=convertido (idem descartado) y el resultado se fecha en el instante del cierre. Sin esto puede existir un episodio con motivo_cierre=convertido y resultado NULL, que el numerador de la conversion mensual (where resultado = ''convertido'') NO ve: 0 % donde la verdad es 100 %.';

-- ---------------------------------------------------------------------------
-- 2. BOQUETE 2 — un lead se convierte UNA sola vez, y ahora lo dice el disco
-- ---------------------------------------------------------------------------
-- Predicado con las DOS columnas a propósito (decisión (2) de la cabecera; las
-- dos mitades quedan asertadas por separado en R11 y R12). Un lead cuyo único
-- cierre por conversión existe entra una vez en el índice; el segundo choca con
-- 23505 aunque venga de otro ciclo, de otro analista, sea adyacente en el tiempo
-- o tenga duración cero — los tres casos que el EXCLUDE deja pasar.
create unique index lead_asignaciones_una_conversion_por_lead_idx
  on crm.lead_asignaciones (lead_id)
  where motivo_cierre = 'convertido' or resultado = 'convertido';

comment on index crm.lead_asignaciones_una_conversion_por_lead_idx is
  'Un lead se convierte UNA sola vez en toda su vida. Hasta ahora eso solo lo sostenia CODIGO (private.trg_leads_guard_tenencia y la guardia del ledger), y el codigo se apaga: `disable trigger` es un patron ya usado en esta tabla en 20260807203757, y crm.ledger_writer es un simple GUC. lead_asignaciones_sin_solape NO cubre esto: dos episodios convertidos adyacentes [10,11) y [11,12) no se solapan, y los de duracion cero dan rango vacio. El count(distinct lead_id) de la migracion A tampoco: agrupa POR ANALISTA, asi que dos cierres del mismo lead atribuidos a analistas distintos suman 1+1 en el total de equipo (200 % con divisor 1). NO se pone sobre `resultado` a secas: los descartes repetidos del mismo lead son un flujo vivo.';

-- ---------------------------------------------------------------------------
-- 3. Postflight — que los constraints RECHACEN de verdad, no que el catálogo
--    diga que existen
-- ---------------------------------------------------------------------------
-- QUÉ PRUEBA ESTE BLOQUE, Y QUÉ NO. Se insertan filas de verdad y se comprueba
-- que el motor las rechaza con el SQLSTATE **y** el nombre del objeto
-- esperados. Las filas NO van a `crm.lead_asignaciones`: van a réplicas
-- TEMPORALES creadas con `create temp table ... (like crm.lead_asignaciones
-- including all) on commit drop`.
--
-- El borrador de esta migración hacía los INSERT contra la tabla real, y para
-- que los triggers del ledger no se comieran el intento ponía
-- `set local session_replication_role = replica`. **Eso no se puede aplicar**:
-- es un GUC de contexto `superuser`, el rol que aplica las migraciones de este
-- proyecto es `postgres` con `rolsuper = false`, `pg_parameter_acl` está vacía
-- y la pertenencia a roles no confiere superusuario para
-- `pg_parameter_aclcheck`. Comprobado contra producción con
-- `has_parameter_privilege('postgres','session_replication_role','SET')` =
-- false, y reproducido en PG 17.10 con un rol dueño `nosuperuser`:
-- `ERROR: permission denied to set parameter "session_replication_role"`, que
-- aborta la transacción entera y se lleva por delante el CHECK y el índice que
-- ya habían corrido. La migración era inaplicable tal cual.
--
-- La réplica temporal no necesita privilegio ninguno (`TEMP` sobre la base, que
-- `postgres` tiene), no depende de que existan leads, analistas o políticas SLA
-- (no copia las FK), no arrastra triggers y no puede ensuciar nada: `on commit
-- drop`. Y no es un maniquí: `LIKE ... INCLUDING ALL` copia los NOT NULL, TODOS
-- los CHECK **conservando su nombre**, los índices únicos parciales y el EXCLUDE
-- (verificado en PG 17.10). Antes de usarla, §3.0 exige que los tres objetos que
-- importan estén en la copia con la definición IDÉNTICA a la de la tabla real,
-- leída del catálogo — si no, aborta. Dos tablas con el mismo conjunto de
-- columnas y las mismas definiciones de CHECK y de índice dan el mismo veredicto
-- fila a fila: eso no es una analogía, es lo que un CHECK es.
--
-- Lo que este bloque NO prueba, y conviene decirlo: que la tabla REAL acepte los
-- casos legítimos end-to-end (ahí mandan además los triggers y las FK, que las
-- réplicas no llevan). Eso lo cubre el ciclo obligatorio del proyecto: branch →
-- `test-rls.mjs` → advisors. Lo que sí queda probado sobre la tabla real es que
-- lleva EXACTAMENTE esas definiciones y que están VALIDADAS (§4), y que las 1
-- fila(s) que ya tiene las cumplen (`validate constraint` de §1).
--
-- Tres réplicas, para que cada término responda por sí mismo:
--   · `pf_completo`    — fiel al almacenamiento real (los dos CHECK del cierre,
--                        el índice nuevo, el EXCLUDE, `intervalo_valido` y
--                        `un_abierto_por_lead`).
--   · `pf_sin_original`— sin `lead_asignaciones_cierre_consistente`: aísla el
--                        CHECK nuevo, que es el que tiene que sostener el
--                        invariante SOLO el día que alguien retire el viejo.
--   · `pf_sin_checks`  — sin los dos CHECK del cierre: aísla las DOS mitades del
--                        predicado del índice, que con cualquiera de los CHECK
--                        vivo son indistinguibles entre sí.
--
-- Cada aserción exige SQLSTATE **y** nombre de objeto. Solo con el SQLSTATE, un
-- fallo por otra causa (un NOT NULL sin rellenar) se leería como «rechazada:
-- correcto» y el postflight bendeciría un agujero abierto.
do $postflight$
declare
  -- Todo sintético. Sin FK en las réplicas, no apunta a nada; y `on commit drop`
  -- se lo lleva pase lo que pase.
  k_l1  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000001';
  k_l2  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000002';
  k_l3  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000003';
  k_l4  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000004';
  k_l5  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000005';
  k_l6  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000006';
  k_l7  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000007';
  k_l8  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000008';
  k_l9  constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000009';
  k_l10 constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000010';
  k_l11 constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000011';
  k_l12 constant uuid := 'ffffffff-ffff-4fff-8fff-f00000000012';
  k_ana constant uuid := 'ffffffff-ffff-4fff-8fff-a00000000001';
  k_an2 constant uuid := 'ffffffff-ffff-4fff-8fff-a00000000002';
  k_pol constant uuid := 'ffffffff-ffff-4fff-8fff-b00000000001';
  k_t0  constant timestamptz := '2020-01-01 10:00:00+00';
  k_t1  constant timestamptz := '2020-01-01 11:00:00+00';
  k_t2  constant timestamptz := '2020-01-01 12:00:00+00';
  k_t3  constant timestamptz := '2020-01-01 13:00:00+00';

  c_check_nuevo constant text := 'lead_asignaciones_cierre_no_trivaluado';
  c_check_viejo constant text := 'lead_asignaciones_cierre_consistente';

  v_def_real   text;
  v_def_copia  text;
  v_idx_real   text;
  v_idx_copia  text;
  v_idx_nombre text;   -- nombre del índice clonado en pf_completo
  v_idx_nom_sc text;   -- ídem en pf_sin_checks
  v_filas_ini  bigint;
  v_rechazos   int := 0;
  v_aceptados  int := 0;
  v_r          text[];
begin
  select count(*) into v_filas_ini from crm.lead_asignaciones;

  -- ═════════════════ 3.0 · las réplicas, y la prueba de que lo son ══════════
  create temp table pf_completo    (like crm.lead_asignaciones including all) on commit drop;
  create temp table pf_sin_original(like crm.lead_asignaciones including all) on commit drop;
  create temp table pf_sin_checks  (like crm.lead_asignaciones including all) on commit drop;

  -- ¿Llegó el CHECK NUEVO a la copia, con la misma definición?
  select pg_get_constraintdef(oid) into v_def_real
  from pg_constraint
  where conrelid = 'crm.lead_asignaciones'::regclass and conname = c_check_nuevo;
  select pg_get_constraintdef(oid) into v_def_copia
  from pg_constraint
  where conrelid = 'pg_temp.pf_completo'::regclass and conname = c_check_nuevo;
  if v_def_copia is distinct from v_def_real then
    raise exception 'POSTFLIGHT 3.0: la replica no lleva % con la definicion de la tabla real (real=% / copia=%). Sin eso el bloque estaria probando un maniqui.',
      c_check_nuevo, coalesce(v_def_real,'<ausente>'), coalesce(v_def_copia,'<ausente>');
  end if;

  -- ¿Y el CHECK VIEJO?
  select pg_get_constraintdef(oid) into v_def_real
  from pg_constraint
  where conrelid = 'crm.lead_asignaciones'::regclass and conname = c_check_viejo;
  select pg_get_constraintdef(oid) into v_def_copia
  from pg_constraint
  where conrelid = 'pg_temp.pf_completo'::regclass and conname = c_check_viejo;
  if v_def_copia is distinct from v_def_real then
    raise exception 'POSTFLIGHT 3.0: la replica no lleva % con la definicion de la tabla real.', c_check_viejo;
  end if;

  -- ¿Y el EXCLUDE? No lo necesita ningún caso, pero si faltara, los casos R5/R6
  -- dejarían de demostrar lo que dicen demostrar (que es el ÍNDICE quien los
  -- rechaza, y no la ausencia del EXCLUDE).
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'pg_temp.pf_completo'::regclass and contype = 'x'
  ) then
    raise exception 'POSTFLIGHT 3.0: la replica no lleva el EXCLUDE; R5/R6 no probarian que rechaza el indice.';
  end if;

  -- El índice clonado cambia de nombre (LIKE genera uno nuevo). Se localiza por
  -- su PREDICADO y se comprueba que su definición, quitado el prefijo
  -- «CREATE UNIQUE INDEX <nombre> ON <esquema>.<tabla>», es la misma.
  v_idx_real := substring(
    pg_get_indexdef('crm.lead_asignaciones_una_conversion_por_lead_idx'::regclass)
    from ' USING .*$');

  select c.relname,
         substring(pg_get_indexdef(i.indexrelid) from ' USING .*$')
  into v_idx_nombre, v_idx_copia
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
  where i.indrelid = 'pg_temp.pf_completo'::regclass
    and i.indisunique
    and pg_get_expr(i.indpred, i.indrelid) like '%convertido%';
  if v_idx_nombre is null or v_idx_copia is distinct from v_idx_real then
    raise exception 'POSTFLIGHT 3.0: la replica no lleva el indice unico parcial de la conversion (real=% / copia=%).',
      coalesce(v_idx_real,'<ausente>'), coalesce(v_idx_copia,'<ausente>');
  end if;

  select c.relname into v_idx_nom_sc
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
  where i.indrelid = 'pg_temp.pf_sin_checks'::regclass
    and i.indisunique
    and pg_get_expr(i.indpred, i.indrelid) like '%convertido%';
  if v_idx_nom_sc is null then
    raise exception 'POSTFLIGHT 3.0: pf_sin_checks no lleva el indice unico parcial de la conversion.';
  end if;

  -- Las dos réplicas mutiladas. Que el DROP funcione es en sí una comprobación
  -- de que el CHECK estaba ahí con ese nombre exacto.
  execute format('alter table pf_sin_original drop constraint %I', c_check_viejo);
  execute format('alter table pf_sin_checks   drop constraint %I', c_check_viejo);
  execute format('alter table pf_sin_checks   drop constraint %I', c_check_nuevo);

  -- ═════════════════ 3.1 · el andamiaje, una sola vez ═══════════════════════
  -- `pg_temp.pf_fila` compone el INSERT (todo literal, `%L` escribe NULL sin
  -- comillas cuando el argumento es NULL) y `pg_temp.pf_intentar` lo ejecuta en
  -- una SUBTRANSACCIÓN que se deshace SIEMPRE: al final levanta el marcador
  -- 'PT000', así que ni las filas de los casos que deben ENTRAR sobreviven.
  -- Devuelve [estado, sqlstate, constraint, mensaje]; los cuatro se recalculan
  -- en cada llamada, así que ningún caso puede heredar el diagnóstico del
  -- anterior (el borrador sí lo hacía: sus variables no se reiniciaban y un caso
  -- que entrara indebidamente imprimía el SQLSTATE del caso previo como suyo).
  create function pg_temp.pf_fila(
    p_tabla text, p_lead uuid, p_ciclo int, p_ep int, p_analista uuid,
    p_apertura text, p_asignado timestamptz, p_finalizado timestamptz,
    p_motivo text, p_resultado text, p_resultado_en timestamptz,
    p_descarte text, p_destino uuid, p_pol uuid
  ) returns text language sql immutable as $fila$
    select format(
      'insert into %I (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,'
      || ' asignado_en, moneda, origen, finalizado_en, motivo_cierre, resultado,'
      || ' resultado_en, motivo_descarte_cierre, analista_destino_id,'
      || ' sla_global_iniciado_en, sla_politica_asignacion_id,'
      || ' primera_gestion_limite_en, primer_contacto_limite_en)'
      || ' values (%L,%s,%s,%L,%L,%L,''PEN'',''postflight'',%L,%L,%L,%L,%L,%L,%L,%L,%L,%L)',
      p_tabla, p_lead, p_ciclo, p_ep, p_analista, p_apertura, p_asignado,
      p_finalizado, p_motivo, p_resultado, p_resultado_en, p_descarte,
      p_destino, p_asignado, p_pol, p_asignado, p_asignado);
  $fila$;

  create function pg_temp.pf_intentar(p_stmts text[]) returns text[]
  language plpgsql as $int$
  declare
    s text;
    v_c text;
  begin
    begin
      foreach s in array p_stmts loop
        execute s;
      end loop;
      raise exception using errcode = 'PT000', message = 'deshacer';
    exception
      when sqlstate 'PT000' then
        return array['ENTRO', null, null, null];
      when others then
        get stacked diagnostics v_c = constraint_name;
        return array['RECHAZADA', sqlstate, v_c, sqlerrm];
    end;
  end;
  $int$;

  create function pg_temp.pf_rechazo(
    p_caso text, p_res text[], p_sqlstate text, p_objetos text[], p_pista text
  ) returns void language plpgsql as $rec$
  begin
    if p_res[1] <> 'RECHAZADA'
       or p_res[2] <> p_sqlstate
       or not (p_res[3] = any (p_objetos)) then
      raise exception 'POSTFLIGHT % : esperaba % sobre {%} y obtuve estado=% sqlstate=% objeto=% (%). %',
        p_caso, p_sqlstate, array_to_string(p_objetos, ' | '),
        p_res[1], coalesce(p_res[2],'-'), coalesce(p_res[3],'-'),
        coalesce(p_res[4],'-'), p_pista;
    end if;
  end;
  $rec$;

  create function pg_temp.pf_acepta(p_caso text, p_res text[], p_pista text)
  returns void language plpgsql as $acp$
  begin
    if p_res[1] <> 'ENTRO' then
      raise exception 'POSTFLIGHT % : la base rechazo un flujo LEGITIMO con sqlstate=% objeto=% (%). %',
        p_caso, coalesce(p_res[2],'-'), coalesce(p_res[3],'-'),
        coalesce(p_res[4],'-'), p_pista;
    end if;
  end;
  $acp$;

  -- ═════════ 3.2 · sobre pf_completo (el almacenamiento tal cual queda) ═════

  -- R1 · boquete 1, variante «resultado sin fecha»: motivo y resultado dicen
  -- «convertido» y `resultado_en` viene NULL. Hoy entra.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l1, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'convertido', 'convertido', null, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R1 (conversion con resultado_en NULL)', v_r,
    '23514', array[c_check_nuevo], 'EL BOQUETE 1 SIGUE ABIERTO.');
  v_rechazos := v_rechazos + 1;

  -- R2 · boquete 1, variante «motivo sin resultado». ESTA es la que la
  -- migración A no ve (su numerador empieza por `where resultado='convertido'`)
  -- y la que su sonda puede no cantar. Es el caso que más justifica §1.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l2, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'convertido', null, null, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R2 (motivo_cierre=convertido con resultado NULL)', v_r,
    '23514', array[c_check_nuevo], 'EL BOQUETE 1 SIGUE ABIERTO.');
  v_rechazos := v_rechazos + 1;

  -- R3 · el análogo exacto de R2 en la rama del DESCARTE: `motivo_cierre` dice
  -- descartado y `resultado` está vacío. Lo mata el término (c) y solo él — el
  -- CHECK original lo deja pasar, porque su rama exige `resultado='descartado'`
  -- y con NULL eso da NULL. (El borrador creía cubrir (c) con una fila que en
  -- realidad matan (a) y (d); esta es la que hace falta.)
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l3, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'descartado', null, null, 'no interesado', null, k_pol) ]);
  perform pg_temp.pf_rechazo('R3 (motivo_cierre=descartado con resultado NULL)', v_r,
    '23514', array[c_check_nuevo],
    'El termino (c) del CHECK nuevo no esta cerrando la rama del descarte.');
  v_rechazos := v_rechazos + 1;

  -- R4 · descarte con resultado bien puesto pero sin fecha: lo matan (a) y (d).
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l4, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'descartado', 'descartado', null, 'no interesado', null, k_pol) ]);
  perform pg_temp.pf_rechazo('R4 (descarte con resultado_en NULL)', v_r,
    '23514', array[c_check_nuevo], '');
  v_rechazos := v_rechazos + 1;

  -- A1 · LO QUE NO SE PROHIBIÓ, y va antes que R5/R6 a propósito: un episodio
  -- TRANSFERIDO de DURACIÓN CERO (el reparto en un gesto, sellado por
  -- statement_timestamp()) seguido del episodio abierto del destinatario. Si
  -- alguien endurece `lead_asignaciones_intervalo_valido` a `>`, el fallo sale
  -- POR AQUÍ y con su nombre, en vez de disfrazarse de fallo del índice único en
  -- R6 (que es lo que hacía el borrador, con este caso puesto después).
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_completo', k_l5, 1, 1, k_ana, 'ingreso', k_t0, k_t0,
      'transferido', null, null, null, k_an2, k_pol),
    pg_temp.pf_fila('pf_completo', k_l5, 1, 2, k_an2, 'reasignado', k_t0, null,
      null, null, null, null, null, k_pol) ]);
  perform pg_temp.pf_acepta('A1 (transferencia de duracion cero + episodio abierto)', v_r,
    'Si el objeto es lead_asignaciones_intervalo_valido, alguien endurecio el >= a > y rompio el reparto.');
  v_aceptados := v_aceptados + 1;

  -- R5 · boquete 2 en la forma que el EXCLUDE NO ve: dos conversiones
  -- ADYACENTES y NO vacías, [10,11) y [11,12). Este caso es la demostración de
  -- que endurecer el intervalo a `>` no habría servido de nada.
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_completo', k_l6, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
      'convertido', 'convertido', k_t1, null, null, k_pol),
    pg_temp.pf_fila('pf_completo', k_l6, 1, 2, k_an2, 'reasignado', k_t1, k_t2,
      'convertido', 'convertido', k_t2, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R5 (dos conversiones ADYACENTES del mismo lead)', v_r,
    '23505', array[v_idx_nombre], 'EL BOQUETE 2 SIGUE ABIERTO.');
  v_rechazos := v_rechazos + 1;

  -- R6 · boquete 2 en la forma de DURACIÓN CERO (rango vacío, lo que el EXCLUDE
  -- literalmente no puede ver), y además en CICLOS distintos, para probar que el
  -- índice no se escapa por ahí.
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_completo', k_l7, 1, 1, k_ana, 'ingreso', k_t1, k_t1,
      'convertido', 'convertido', k_t1, null, null, k_pol),
    pg_temp.pf_fila('pf_completo', k_l7, 2, 1, k_ana, 'reabierto', k_t1, k_t1,
      'convertido', 'convertido', k_t1, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R6 (dos conversiones de DURACION CERO del mismo lead)', v_r,
    '23505', array[v_idx_nombre], 'EL BOQUETE 2 SIGUE ABIERTO.');
  v_rechazos := v_rechazos + 1;

  -- A2 · la conversión legítima. Sin este caso el bloque solo probaría que la
  -- base sabe decir que no. (Lección de CLAUDE.md: una suite sin caso POSITIVO
  -- de la acción principal no prueba que la acción funcione.)
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l8, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'convertido', 'convertido', k_t1, null, null, k_pol) ]);
  perform pg_temp.pf_acepta('A2 (conversion BIEN formada)', v_r,
    'El endurecimiento se paso de frenada.');
  v_aceptados := v_aceptados + 1;

  -- A3 · el flujo vivo descartar → deshacer_descarte → descartar → convertir:
  -- DOS descartes del mismo lead en ciclos distintos y una conversión después.
  -- Es lo que se habría roto si el índice fuera sobre `resultado` a secas. (No
  -- prueba nada sobre la variante `(lead_id, ciclo_n)` del índice: esa la
  -- descarta R6, que mete dos conversiones en ciclos distintos.)
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_completo', k_l9, 1, 1, k_ana, 'ingreso',
      k_t0, k_t0 + interval '10 min', 'descartado', 'descartado',
      k_t0 + interval '10 min', 'no contesta', null, k_pol),
    pg_temp.pf_fila('pf_completo', k_l9, 2, 1, k_ana, 'reabierto',
      k_t0 + interval '20 min', k_t0 + interval '30 min', 'descartado',
      'descartado', k_t0 + interval '30 min', 'no interesado', null, k_pol),
    pg_temp.pf_fila('pf_completo', k_l9, 3, 1, k_an2, 'reabierto',
      k_t0 + interval '40 min', k_t0 + interval '50 min', 'convertido',
      'convertido', k_t0 + interval '50 min', null, null, k_pol) ]);
  perform pg_temp.pf_acepta('A3 (dos descartes + una conversion del mismo lead)', v_r,
    'El indice esta mal acotado: los descartes repetidos son un flujo vivo.');
  v_aceptados := v_aceptados + 1;

  -- R7 · REGRESIÓN DEL CONSTRAINT VIEJO, no cobertura de esta migración:
  -- `resultado_en` sellado con `resultado` vacío. Aquí responde el ORIGINAL
  -- (los CHECK se evalúan en orden de NOMBRE y `..._cierre_consistente` va antes
  -- que `..._cierre_no_trivaluado`), así que se admiten los dos nombres. Lo que
  -- este caso vigila es que el original siga haciendo SU trabajo; el del CHECK
  -- nuevo sobre esta misma forma se prueba aparte y sin ambigüedad en R8.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_completo', k_l10, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'parqueado', null, k_t1, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R7 (resultado_en sellado con resultado NULL)', v_r,
    '23514', array[c_check_viejo, c_check_nuevo], '');
  v_rechazos := v_rechazos + 1;

  -- ═════ 3.3 · sobre pf_sin_original — el CHECK nuevo, solo ante el peligro ══
  -- Estos tres casos son los que el borrador declaraba «no cubiertos» y dejaba
  -- a fe. Aquí el original no está, así que el único que puede responder es el
  -- nuevo y la aserción es exacta.

  -- R8 · aísla el término (a): `resultado_en` sellado sin `resultado`.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_sin_original', k_l10, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'parqueado', null, k_t1, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R8 (termino (a) aislado: resultado_en sin resultado)', v_r,
    '23514', array[c_check_nuevo],
    'Sin el CHECK viejo, el nuevo tiene que sostener esto SOLO y no lo hace.');
  v_rechazos := v_rechazos + 1;

  -- R9 · aísla el término (d): el sello desalineado. `resultado_en` existe pero
  -- no es el instante del cierre. Es la forma que cuenta `v_sello_desalineado`
  -- en el preflight y que ningún caso del borrador sembraba.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_sin_original', k_l11, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'convertido', 'convertido', k_t2, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R9 (termino (d) aislado: resultado_en <> finalizado_en)', v_r,
    '23514', array[c_check_nuevo],
    'El sello del reloj se perderia el dia que se retire el CHECK viejo.');
  v_rechazos := v_rechazos + 1;

  -- R10 · aísla el término (c) sin ayuda de nadie.
  v_r := pg_temp.pf_intentar(array[ pg_temp.pf_fila(
    'pf_sin_original', k_l3, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
    'descartado', null, null, 'no interesado', null, k_pol) ]);
  perform pg_temp.pf_rechazo('R10 (termino (c) aislado: descartado sin resultado)', v_r,
    '23514', array[c_check_nuevo], '');
  v_rechazos := v_rechazos + 1;

  -- ═════ 3.4 · sobre pf_sin_checks — las DOS mitades del predicado del índice ═
  -- Con cualquiera de los dos CHECK vivo, `motivo_cierre='convertido'` y
  -- `resultado='convertido'` son indistinguibles y el `or` del predicado es
  -- infalsificable: el borrador lo justificaba de palabra y sus dos mitades eran
  -- borrables sin que ninguna aserción se enterara. Sin los CHECK, cada mitad
  -- responde por su cuenta.

  -- R11 · la mitad `motivo_cierre`: segunda fila con motivo convertido y
  -- `resultado` NULL. Un índice sobre `resultado` a secas la dejaría fuera del
  -- índice y las dos filas convivirían.
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_sin_checks', k_l12, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
      'convertido', 'convertido', k_t1, null, null, k_pol),
    pg_temp.pf_fila('pf_sin_checks', k_l12, 1, 2, k_an2, 'reasignado', k_t2, k_t3,
      'convertido', null, null, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R11 (mitad motivo_cierre del predicado del indice)', v_r,
    '23505', array[v_idx_nom_sc],
    'El predicado del indice no esta mirando motivo_cierre.');
  v_rechazos := v_rechazos + 1;

  -- R12 · la mitad `resultado`: segunda fila con `resultado='convertido'` y
  -- `motivo_cierre` distinto. Un índice sobre `motivo_cierre` a secas la dejaría
  -- fuera. (Esta forma es irrepresentable con el CHECK original vivo — por eso
  -- hace falta la réplica sin CHECKs para poder asertarla.)
  v_r := pg_temp.pf_intentar(array[
    pg_temp.pf_fila('pf_sin_checks', k_l11, 1, 1, k_ana, 'ingreso', k_t0, k_t1,
      'convertido', 'convertido', k_t1, null, null, k_pol),
    pg_temp.pf_fila('pf_sin_checks', k_l11, 1, 2, k_an2, 'reasignado', k_t2, k_t3,
      'desactivado', 'convertido', k_t3, null, null, k_pol) ]);
  perform pg_temp.pf_rechazo('R12 (mitad resultado del predicado del indice)', v_r,
    '23505', array[v_idx_nom_sc],
    'El predicado del indice no esta mirando resultado.');
  v_rechazos := v_rechazos + 1;

  -- ═════════════════════════ 3.5 · cierre del bloque ════════════════════════
  -- GUARDA DE EDICIÓN, no cobertura: los contadores son literales sobre un
  -- camino recto y solo pueden fallar si alguien comenta un caso. Se dejan por
  -- eso mismo, dicho en voz alta para que nadie los cuente como verificación.
  if v_rechazos <> 12 or v_aceptados <> 3 then
    raise exception 'POSTFLIGHT: se esperaban 12 rechazos (R1..R12) y 3 aceptaciones (A1..A3); hubo % y %.',
      v_rechazos, v_aceptados;
  end if;

  -- Esta sí es falsificable, y es la que importa: el postflight escribe en
  -- réplicas temporales, así que la tabla real tiene que estar EXACTAMENTE igual
  -- que antes del bloque. Si alguien reapunta un caso a `crm.lead_asignaciones`,
  -- salta aquí.
  if (select count(*) from crm.lead_asignaciones) <> v_filas_ini then
    raise exception 'POSTFLIGHT: crm.lead_asignaciones cambio de % a % filas durante el postflight. NO COMMITEAR.',
      v_filas_ini, (select count(*) from crm.lead_asignaciones);
  end if;

  -- Las réplicas caen solas en el COMMIT (`on commit drop`); las funciones no,
  -- porque `pg_temp` vive lo que viva la SESIÓN. Se retiran a mano.
  drop function pg_temp.pf_fila(text, uuid, int, int, uuid, text, timestamptz,
    timestamptz, text, text, timestamptz, text, uuid, uuid);
  drop function pg_temp.pf_intentar(text[]);
  drop function pg_temp.pf_rechazo(text, text[], text, text[], text);
  drop function pg_temp.pf_acepta(text, text[], text);

  raise notice 'POSTFLIGHT OK: % filas ilegales rechazadas con el SQLSTATE y el objeto esperados, % flujos legitimos aceptados, crm.lead_asignaciones intacta (% fila(s)).',
    v_rechazos, v_aceptados, v_filas_ini;
end;
$postflight$;

-- ---------------------------------------------------------------------------
-- 4. Cierre — el catálogo de la tabla REAL, que es lo que el postflight no toca
-- ---------------------------------------------------------------------------
-- Aquí está el otro extremo del puente: §3 probó que ESAS definiciones rechazan
-- las filas malas; esto prueba que la tabla real las lleva, validadas, y que el
-- original sigue en pie.
do $cierre$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'crm.lead_asignaciones'::regclass
      and conname = 'lead_asignaciones_cierre_no_trivaluado'
      and contype = 'c'
      and convalidated
  ) then
    raise exception 'lead_asignaciones_cierre_no_trivaluado no quedo creado y VALIDADO sobre crm.lead_asignaciones.';
  end if;

  if not exists (
    select 1
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
    join pg_namespace n on n.oid = c.relnamespace
    where i.indrelid = 'crm.lead_asignaciones'::regclass
      and n.nspname = 'crm'
      and c.relname = 'lead_asignaciones_una_conversion_por_lead_idx'
      and i.indisunique
      and i.indisvalid
      and i.indpred is not null
  ) then
    raise exception 'lead_asignaciones_una_conversion_por_lead_idx no quedo creado como indice UNICO PARCIAL y valido.';
  end if;

  -- Esta migración COMPLEMENTA al original; si desapareciera, media cabecera
  -- dejaría de ser cierta. Guarda barata, no cobertura.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'crm.lead_asignaciones'::regclass
      and conname = 'lead_asignaciones_cierre_consistente'
      and contype = 'c'
      and convalidated
  ) then
    raise exception 'lead_asignaciones_cierre_consistente desaparecio o quedo sin validar; esta migracion no debia tocarlo.';
  end if;
end;
$cierre$;

commit;

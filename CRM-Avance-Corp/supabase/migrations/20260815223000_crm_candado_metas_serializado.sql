-- ---------------------------------------------------------------------------
-- El candado de metas se SERIALIZA con el cierre del mismo mes
-- ---------------------------------------------------------------------------
-- HALLAZGO BLOQUEANTE de la revisión adversaria (Codex, 2026-08-15), previo al
-- release de la Fase 2. Publicar metas y cerrar un mes usaban candados con
-- CLAVES DISTINTAS:
--
--   · crm.publicar_metas_vendedores  → (hashtext('crm.meta_periodos'),     mes)
--   · crm.cerrar_periodo             → (hashtext('crm.periodos_cerrados'), mes)
--
-- Dos claves = cero serialización. El entrelazado que rompe la invariante:
-- el cierre lee la revisión R1 y deja su sello SIN commit; en paralelo,
-- Publicar toma SU candado (otro recurso), su trigger consulta
-- crm.periodos_cerrados bajo READ COMMITTED —no ve filas sin commit—, acepta
-- R2, y AMBAS transacciones confirman. Resultado: el mes queda sellado contra
-- R1 mientras el editor sirve R2 como vigente. DOS verdades para un mes que
-- por decisión de Miguel «no se reescribe nunca»:
--   · crm.cumplimiento_metas_fn sirve la foto con v_cierre.meta_revision (R1)
--   · crm.configuracion_metas_fn sirve la revisión máxima (R2)
--
-- EL ARREGLO ES ESTRUCTURAL, no una re-consulta: el trigger del candado
-- (private.trg_metas_no_bajo_mes_sellado, BEFORE INSERT OR UPDATE OF periodo
-- en crm.meta_periodos; la rama UPDATE esta muerta de facto porque
-- trg_meta_periodos_inmutables veta todo UPDATE — si algun dia se relajara esa
-- inmutabilidad, ojo: esta regla solo mira new.periodo) toma EXACTAMENTE el
-- candado del cierre —misma clave, misma aritmética de fecha— antes de mirar
-- el último mes sellado. El razonamiento vale para READ COMMITTED (lo que usa
-- PostgREST y toda la Data API): bajo REPEATABLE READ el SELECT post-espera NO
-- refrescaria snapshot — solo alcanzable desde una sesion directa de DBA.
-- Con eso:
--   · publicar espera a que el cierre del MISMO mes confirme → su SELECT
--     (sentencia nueva en READ COMMITTED = snapshot nuevo) ve el sello y
--     rechaza con el 22023 de siempre;
--   · y al revés: el cierre espera a que la publicación confirme y sella la
--     revisión NUEVA. Una sola verdad en los dos órdenes.
--
-- ORDEN DE CANDADOS (auditado, sin interbloqueo): publicar toma
-- (meta_periodos, mes) y LUEGO —via este trigger— (periodos_cerrados, mes).
-- cerrar_periodo toma (periodos_cerrados, mes) y NUNCA toma el de
-- meta_periodos. Sin ciclo de espera posible.
--
-- RESIDUO CONOCIDO E INERTE (dicho a propósito): publicar un mes P mientras se
-- sella OTRO mes M > P no queda serializado (candados por-mes distintos). Si
-- esa carrera se diera, las metas de P nacen por debajo del suelo del último
-- sello y `private.cierre_mes_pendiente` las IGNORA para siempre (la regla
-- «nunca por debajo del último mes sellado», 20260815102000): metas muertas,
-- ninguna verdad doble, ningún pendiente fabricado. Cerrarlo del todo exigiría
-- un candado global que frenara TODA publicación durante el ciclo — más caro
-- que el daño que evita.
--
-- ✅ LA CARRERA SE REPRODUJO Y SE VERIFICÓ con DOS SESIONES psql reales en el
-- banco local (2026-08-15), en los dos órdenes:
--   · ANTES del arreglo: con el sello en vuelo sin confirmar, la publicación
--     entró EN 0 SEGUNDOS y confirmó (las dos verdades, tal cual el hallazgo).
--   · DESPUÉS: sello en vuelo → la publicación ESPERÓ el candado (~2 s) y
--     murió con el 22023 de negocio al confirmar el sello; y al revés,
--     publicación en vuelo → el cierre ESPERÓ (~3 s) y selló la revisión
--     NUEVA (meta_revision = 2). Una sola verdad en ambos órdenes.
-- El oráculo de una sesión no puede repetir esto: el postflight verifica la
-- ESTRUCTURA (misma clave y misma aritmética en las dos funciones), que es lo
-- que mantiene cerrada la carrera en adelante.
-- ---------------------------------------------------------------------------

begin;
set local lock_timeout = '10s';

do $preflight$
declare
  v_huella text;
begin
  -- La función que se reemplaza, anclada a su fuente EXACTA de producción
  -- (2026-08-15). Si no coincide, alguien la cambió después de escribir esto:
  -- NO aplicar a ciegas — releer y reescribir esta migración.
  select md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure;
  if v_huella is distinct from 'ae30e1d229232d2c05bfa7cca7e5d33f' then
    raise exception 'private.trg_metas_no_bajo_mes_sellado no es la fuente esperada (md5 %). Revisar antes de aplicar.', v_huella;
  end if;

  -- El candado del cierre al que hay que igualarse sigue donde se le espera.
  select md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  if v_huella is distinct from '67a1fc6911d0b82835be5cf05abb80e9' then
    raise exception 'crm.cerrar_periodo no es la fuente esperada (md5 %). Revisar antes de aplicar.', v_huella;
  end if;
end
$preflight$;

create or replace function private.trg_metas_no_bajo_mes_sellado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ultimo date;
begin
  -- EL MISMO candado que crm.cerrar_periodo (misma clave, misma aritmética):
  -- publicar y cerrar el MISMO mes quedan serializados. Sin esto, el sello sin
  -- commit era invisible para el SELECT de abajo (READ COMMITTED) y una
  -- publicación concurrente fabricaba una segunda verdad sobre un mes cerrado.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (new.periodo - date '2000-01-01')::integer
  );

  select max(pc.periodo) into v_ultimo from crm.periodos_cerrados pc;

  if v_ultimo is not null and new.periodo <= v_ultimo then
    raise exception using
      errcode = '22023',
      message = format('No se publican metas de %s: %s ya esta cerrado',
                       to_char(new.periodo, 'YYYY-MM'), to_char(v_ultimo, 'YYYY-MM')),
      hint    = 'Un mes cerrado no se reescribe, y uno anterior ya no se puede sellar. Lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  return new;
end;
$function$;

comment on function private.trg_metas_no_bajo_mes_sellado() is
  'Impide publicar metas de un mes igual o anterior al ultimo sellado, SERIALIZADO con crm.cerrar_periodo: toma su mismo advisory lock (periodos_cerrados, mes) antes de mirar, asi el sello en vuelo de ese mes se espera y se ve — sin esto, una publicacion concurrente al cierre fabricaba dos verdades para un mes inmutable. Publicar metas es lo que convierte a un mes en «mes que debe un cierre».';

revoke all on function private.trg_metas_no_bajo_mes_sellado() from public, anon, authenticated;

do $postflight$
declare
  v_trg text;
  v_cerrar text;
begin
  select p.prosrc into v_trg
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'trg_metas_no_bajo_mes_sellado';
  select p.prosrc into v_cerrar
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'cerrar_periodo';

  -- La estructura que cierra la carrera, verificada pieza a pieza (strpos, no
  -- LIKE: el guion bajo es comodin). 1) el trigger toma un advisory lock…
  if strpos(v_trg, 'pg_advisory_xact_lock') = 0 then
    raise exception 'El trigger quedo sin advisory lock: la carrera publicar↔cerrar sigue abierta.';
  end if;
  -- 2) …con LA MISMA clave que el cierre…
  if strpos(v_trg, $$hashtext('crm.periodos_cerrados')$$) = 0 then
    raise exception 'El trigger no usa la clave del candado del cierre.';
  end if;
  if strpos(v_cerrar, $$hashtext('crm.periodos_cerrados')$$) = 0 then
    raise exception 'crm.cerrar_periodo ya no usa la clave esperada: revisar la pareja de candados.';
  end if;
  -- 3) …y la misma aritmetica de fecha (mismo entero = mismo recurso).
  if strpos(v_trg, $$date '2000-01-01')::integer$$) = 0
     or strpos(v_cerrar, $$date '2000-01-01')::integer$$) = 0 then
    raise exception 'La aritmetica del candado difiere entre trigger y cierre: NO contienden por el mismo recurso.';
  end if;
  -- 3bis) Y EN ORDEN: el candado ANTES de la lectura. Mover el lock despues
  -- del SELECT reabre la carrera entera dejando las 4 subcadenas intactas —
  -- es el mutante barato que neutraliza el arreglo sin tocar ningun strpos.
  if strpos(v_trg, 'pg_advisory_xact_lock') > strpos(v_trg, 'select max(pc.periodo)') then
    raise exception 'El candado quedo DESPUES de la lectura: la carrera sigue abierta.';
  end if;
  -- 4) El candado de negocio sigue en pie (el lock se añadio, no sustituyo).
  if strpos(v_trg, 'ya esta cerrado') = 0 then
    raise exception 'El trigger perdio su rechazo de negocio.';
  end if;
  -- 5) Y sigue colgado de la tabla.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'meta_periodos'
      and t.tgfoid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure
  ) then
    raise exception 'El trigger ya no esta enganchado a crm.meta_periodos.';
  end if;
end
$postflight$;

-- Vuelta atrás (manual, nunca automática): reinstalar la versión de
-- 20260815150000 (sin el advisory lock). La carrera volvería a quedar abierta:
-- hacerlo solo si el candado provoca un problema mayor que el que cierra.

commit;

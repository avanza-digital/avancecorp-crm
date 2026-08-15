-- ---------------------------------------------------------------------------
-- No se publican metas por debajo de un mes ya sellado
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. La defensa en profundidad del hallazgo que la auditoria del
-- 15/08 marco como BLOQUEANTE sobre `20260815102000_crm_cierre_mes_candado`.
--
-- Alli se cerro el DAÑO, en las dos puertas del cierre: el ciclo ya no considera
-- candidato a un mes por debajo del ultimo sellado, y `crm.cerrar_periodo` lo
-- rechaza explicitamente. Pero el ORIGEN seguia abierto: `crm.meta_periodos`
-- acepta una fila de cualquier mes, y publicar metas es lo que convierte a un mes
-- en «mes que debe un cierre». Con el origen abierto, gerencia puede seguir
-- fabricando meses pendientes que el sistema no va a sellar nunca — y que se
-- quedarian ahi, mudos, pareciendo un olvido.
--
-- POR QUE UN TRIGGER Y NO UN `if` DENTRO DE `crm.publicar_metas_vendedores`
-- (que es lo que sugirio la auditoria). Tres razones, y la primera basta:
--   1. El trigger cubre CUALQUIER escritor de `crm.meta_periodos`, no solo esa
--      RPC. Una migracion futura, un arreglo por SQL o una segunda pantalla
--      quedan cubiertos sin acordarse de nada.
--   2. La regla es de la TABLA («un mes sellado ya no admite metas nuevas»), no
--      del formulario que la escribe.
--   3. `publicar_metas_vendedores` son 7,5 KB de logica ajena a esto; sustituirla
--      entera para colar dos lineas obliga a anclar su md5 y a arrastrar una
--      segunda copia del cuerpo en el repo, con todo lo que eso invita a que se
--      desincronice.
--
-- ⚠️ LA VENTANA DE AJUSTE SIGUE ABIERTA. La regla es «<= el ultimo sellado», no
-- «< el mes en curso»: del 1 al 10, el mes que acaba de terminar TODAVIA no esta
-- sellado, asi que sus metas se pueden seguir corrigiendo. Es justo lo que la
-- ventana de ajuste significa, y por eso el candado se mide contra el sello y no
-- contra el calendario.
--
-- NO TOCA NADA DE `public`. No cambia ninguna policy ni ningun grant.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('crm.periodos_cerrados') is null then
    raise exception 'Falta crm.periodos_cerrados: aplicar antes 20260815002914.';
  end if;
  if to_regclass('crm.meta_periodos') is null then
    raise exception 'Falta crm.meta_periodos.';
  end if;
  -- Si ya hubiera filas que incumplen la regla, el trigger no las tocaria (solo
  -- mira lo que entra) y quedaria una mentira silenciosa: la tabla diria que
  -- cumple algo que no cumple. Mejor saberlo al aplicar.
  if exists (
    select 1 from crm.meta_periodos mp
    where mp.periodo <= (select max(pc.periodo) from crm.periodos_cerrados pc)
  ) then
    raise exception 'Ya hay metas publicadas por debajo de un mes sellado: revisarlas antes de poner el candado.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El candado
-- ---------------------------------------------------------------------------
create or replace function private.trg_metas_no_bajo_mes_sellado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ultimo date;
begin
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
  'Impide publicar metas de un mes igual o anterior al ultimo sellado. Publicar metas es lo que convierte a un mes en «mes que debe un cierre»: sin esto se pueden fabricar pendientes que el sistema nunca va a cerrar. Del 1 al 10 el mes anterior aun no esta sellado, asi que la ventana de ajuste sigue abierta.';

revoke all on function private.trg_metas_no_bajo_mes_sellado() from public, anon, authenticated;

-- `of periodo` en el UPDATE: mover una fila de mes es la misma jugada por otro
-- camino. Los demas UPDATE (revision, publicada_en) no tienen por que pagar el
-- coste de la consulta.
create trigger trg_meta_periodos_00_no_bajo_sellado
before insert or update of periodo on crm.meta_periodos
for each row execute function private.trg_metas_no_bajo_mes_sellado();

-- ---------------------------------------------------------------------------
-- 2. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_n integer;
begin
  select count(*) into v_n
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm' and c.relname = 'meta_periodos'
    and t.tgname = 'trg_meta_periodos_00_no_bajo_sellado'
    and not t.tgisinternal;
  if v_n <> 1 then
    raise exception 'El candado de metas no quedo puesto sobre crm.meta_periodos (n=%).', v_n;
  end if;

  if has_function_privilege('authenticated', 'private.trg_metas_no_bajo_mes_sellado()', 'EXECUTE')
     or has_function_privilege('anon', 'private.trg_metas_no_bajo_mes_sellado()', 'EXECUTE') then
    raise exception 'La funcion del trigger quedo ejecutable desde la Data API.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- begin;
--   drop trigger if exists trg_meta_periodos_00_no_bajo_sellado on crm.meta_periodos;
--   drop function if exists private.trg_metas_no_bajo_mes_sellado();
-- commit;

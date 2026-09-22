-- La razon del candado de perfiles vuelve a decir la verdad (Miguel, 22/09/2026).
--
-- EL ESTADO DE PARTIDA. `private.assert_analista_vigencia()` lleva en ROJO desde
-- el 05/09, y cada manana el vigia de las 06:39 deja un parte. Hoy son 16, y
-- bloquean el stop-the-line de la demolicion de la Fase 7, que exige cero
-- alertas abiertas DE CUALQUIER FASE.
--
-- EL ROJO ES UNO SOLO, y es legitimo:
--   «Puertas exentas cuyo cuerpo CAMBIO desde que se declararon (la razon ya no
--    se puede dar por buena): funcion public.proteger_campos_inmutables()»
--
-- ⚠️ UN FALSO HALLAZGO QUE CASI SE CONVIERTE EN DANO, anotado para que no se
-- repita. Al diagnosticar esto se comparo `md5(prosrc)` CRUDO contra la huella
-- declarada y «aparecieron» CUATRO puertas con el cuerpo cambiado. Es falso: el
-- censo sella el cuerpo SIN COMENTARIOS
-- (`regexp_replace(regexp_replace(prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')`,
-- 20260830090000:255,287). Las otras tres —`puede_gestionar_cuentas_cliente`,
-- `actualizar_contrato`, `directorio_ranking_analistas`— y tambien
-- `bandeja_actividad` tienen el cuerpo INTACTO desde el 30/08: las dos huellas
-- eran el mismo texto medido de dos maneras. Re-declararlas habria sellado tres
-- huellas con la normalizacion equivocada y ROTO EL TRINQUETE. El assert decia
-- la verdad desde el principio; el ruido lo anadio el diagnostico.
--
-- QUE CAMBIO DE VERDAD, y por que es legitimo. Lo hizo F4 (`20260908211349`,
-- publicada el 08/09 con OK de Miguel). Abrio una excepcion de UNA sola columna:
--   antes:  NEW.asesor_perfil_id := OLD.asesor_perfil_id;          (incondicional)
--   ahora:  IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;
-- Todo lo demas del candado quedo byte a byte: `activo`, `rol`, `asesor_id`,
-- `cargo`, `debe_cambiar_password`, la rama de `contratos`, y —lo que importa—
-- la llamada a `public.es_analista()` en su posicion PROHIBITIVA.
--
-- Y esta bien hecho: la migracion de F4 lleva su propio preflight que aborta si
-- el cuerpo previo no era el esperado; el cuerpo nuevo no se reteclea, se genera
-- por anclas sobre el cuerpo vivo capturado; y NO cambio ni un permiso (la ACL
-- ya era la de por defecto antes de F4, porque es una funcion de TRIGGER y a las
-- de trigger no se las llama directamente).
--
-- POR QUE NO BASTA CON RE-SELLAR. La razon declarada dice que el candado
-- «impide a un analista togglear activo o blanquear el asesor de su cliente».
-- Desde F4 esa congelacion es CONDICIONAL, asi que el texto ya no describe lo
-- que la funcion hace. La PROPIEDAD de seguridad se sostiene —medido: el asesor
-- nuevo tiene que coincidir con `responsable_esperado_id` Y con
-- `responsable_relacion_id`, y la revision que lo autoriza tiene que ser de la
-- MISMA transaccion (`r.transaccion = pg_current_xact_id()`), asi que
-- «blanquear» o apuntar a un tercero siguen siendo imposibles— pero una razon
-- que miente es deuda: la proxima persona la leera y creera otra cosa. Aqui se
-- re-sella Y se reescribe.
--
-- EL CABO SUELTO QUE SE MIRO, y por que no cambia el veredicto. Uno de los tres
-- candados que contienen la excepcion, `private.inversiones_escritura_bajo_candado()`,
-- se reescribio el 13/09 (F8 piloto) y gano una segunda via: ademas de la
-- bandera, ahora tambien pasa si el piloto F8 esta activo. Medido hoy: el
-- piloto esta APAGADO. Y aunque se encendiera, ese candado solo decide SI SE
-- PUEDE ESCRIBIR inversiones; lo que impide mover el asesor a cualquiera es la
-- otra condicion, que no cambio. La puerta lateral del pasillo se abrio; la
-- cerradura del cuarto sigue puesta.
--
-- QUE TOCA ESTA MIGRACION: una fila de `private.analista_vigencia_exenciones`,
-- esquema privado del CRM, que solo `postgres` puede leer (medido: `anon` no,
-- `authenticated` no, ninguna funcion de `public` la lee, ninguna vista, y
-- `private` no esta expuesto a la API). **NO se toca el portal**: ni la funcion,
-- ni sus permisos, ni sus triggers.
--
-- COMO SE REVIERTE. Reponiendo los dos valores anteriores, que el preflight
-- comprueba y el postflight devuelve:
--   update private.analista_vigencia_exenciones
--      set huella = '4727fcb810c3ec082d47b02a3bee7126',
--          razon  = '<la razon anterior, en 20260830090000:385-386>'
--    where objeto = 'public.proteger_campos_inmutables()';
-- Las 16 alertas que se cierren NO se reabren solas; el postflight devuelve su
-- sello para poder deshacerlo.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
lock table private.analista_vigencia_exenciones in share row exclusive mode;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: el mundo que esta migracion da por cierto.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_mal integer; v_err text; v_declarada text;
begin
  -- 1. EXACTAMENTE UNA puerta con la huella caduca, y es la que se nombra.
  --    Se mide con la normalizacion DEL CENSO, no con md5(prosrc) a secas: esa
  --    confusion es la que fabrico tres hallazgos falsos.
  select count(*) into v_mal
    from private.analista_vigencia_exenciones e
    join pg_proc p on p.oid = to_regprocedure(e.objeto)
   where e.huella is distinct from
         md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'));
  if v_mal <> 1 then
    raise exception 'PREFLIGHT: se esperaba EXACTAMENTE 1 puerta con la huella caduca y hay %. Releer antes de tocar nada.', v_mal;
  end if;
  if not exists (
    select 1 from private.analista_vigencia_exenciones e
      join pg_proc p on p.oid = to_regprocedure(e.objeto)
     where e.objeto = 'public.proteger_campos_inmutables()'
       and e.huella is distinct from
           md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))) then
    raise exception 'PREFLIGHT: la puerta caduca no es proteger_campos_inmutables; el mundo cambio';
  end if;

  -- 2. Es la huella que F4 dejo, no otra cosa.
  select huella into v_declarada from private.analista_vigencia_exenciones
   where objeto = 'public.proteger_campos_inmutables()';
  if v_declarada is distinct from '4727fcb810c3ec082d47b02a3bee7126' then
    raise exception 'PREFLIGHT: la huella declarada es % y se esperaba la del 30/08; alguien ya la toco', v_declarada;
  end if;

  -- 3. El candado sigue PROHIBIENDO por donde prometia: la pregunta del Portal
  --    en su posicion, y las cinco congelaciones intactas. Si esto no esta, el
  --    cambio NO fue el de F4 y aqui no se re-sella nada.
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'public.proteger_campos_inmutables()'::regprocedure
       and p.prosrc ~ 'NOT public\.es_admin\(\)'
       and p.prosrc ~ 'NEW\.id = auth\.uid\(\) OR public\.es_analista\(\)'
       and p.prosrc ~ 'NEW\.activo\s*:=\s*OLD\.activo'
       and p.prosrc ~ 'NEW\.rol\s*:=\s*OLD\.rol'
       and p.prosrc ~ 'NEW\.asesor_id\s*:=\s*OLD\.asesor_id'
       and p.prosrc ~ 'NEW\.cargo\s*:=\s*OLD\.cargo'
       and p.prosrc ~ 'NEW\.debe_cambiar_password\s*:=\s*OLD\.debe_cambiar_password') then
    raise exception 'PREFLIGHT: el candado perdio alguna de sus congelaciones o la pregunta del Portal; NO se re-sella';
  end if;

  -- 4. Y la excepcion nueva es la de F4, con su contencion puesta.
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'public.proteger_campos_inmutables()'::regprocedure
       and p.prosrc ~ 'IF NOT v_f4_alinea THEN NEW\.asesor_perfil_id := OLD\.asesor_perfil_id'
       and p.prosrc ~ 'private\.f4_alineacion_perfil_permitida') then
    raise exception 'PREFLIGHT: la excepcion del asesor no es la de F4; no se re-sella a ciegas';
  end if;
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'private.f4_alineacion_perfil_permitida(uuid,uuid)'::regprocedure
       and p.prosrc ~ 'r\.transaccion\s*=\s*pg_current_xact_id\(\)'
       and p.prosrc ~ 'responsable_esperado_id\s*=\s*p_responsable'
       and p.prosrc ~ 'responsable_relacion_id\s*=\s*p_responsable') then
    raise exception 'PREFLIGHT: la contencion de la excepcion F4 ya no exige transaccion propia y responsable esperado; ESO SI hay que investigarlo';
  end if;

  -- 5. Ni un permiso nuevo sobre la funcion del portal: sigue siendo trigger e
  --    INVOKER. (Una funcion de trigger no se puede llamar directamente, por eso
  --    su ACL abierta es el reparto por defecto y no significa nada; lo que NO
  --    puede pasar es que se haya vuelto definer.)
  if exists (select 1 from pg_proc p
              where p.oid = 'public.proteger_campos_inmutables()'::regprocedure
                and (p.prosecdef or pg_get_function_result(p.oid) <> 'trigger')) then
    raise exception 'PREFLIGHT: el candado dejo de ser un trigger invoker; eso cambia todo el razonamiento';
  end if;

  -- 6. El gate tiene que estar en ROJO, y por ESTA causa.
  begin
    perform private.assert_analista_vigencia();
    raise exception 'PREFLIGHT: el gate de vigencia ya esta verde; esta migracion no hace falta';
  exception when others then
    if sqlerrm like 'PREFLIGHT:%' then raise; end if;
    if sqlerrm not like '%proteger_campos_inmutables%' then
      raise exception 'PREFLIGHT: el gate esta rojo por OTRA causa: %', sqlerrm;
    end if;
  end;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- (b) La huella, CALCULADA POR LA BASE con la normalizacion del censo, y la
--     razon reescrita para que describa lo que la funcion hace HOY.
-- ---------------------------------------------------------------------------
update private.analista_vigencia_exenciones e
   set huella = md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
       razon  =
         'Aqui la pregunta del Portal se usa para PROHIBIR, no para permitir: es el candado que impide a un '
      || 'analista togglear activo, rol, asesor_id, cargo o debe_cambiar_password de su cliente. Anadirle la '
      || 'vigencia RELAJARIA el candado. '
      || 'F4 (mig 20260908211349, 08/09/2026) abrio UNA excepcion, solo sobre asesor_perfil_id: la congelacion '
      || 'pasa a ser condicional (IF NOT v_f4_alinea). No relaja el candado para un analista, y se comprobo: '
      || 'v_f4_alinea solo puede ser cierto si private.f4_alineacion_perfil_permitida() encuentra una revision '
      || 'de solicitud escrita en la MISMA transaccion (r.transaccion = pg_current_xact_id()), hecha por el '
      || 'propio auth.uid(), sobre una solicitud en estado preparada, y —lo decisivo— cuyo responsable nuevo '
      || 'coincide a la vez con s.responsable_esperado_id y con i.responsable_relacion_id. Es decir: solo puede '
      || 'ALINEAR al asesor que ya correspondia. Blanquearlo o apuntarlo a un tercero siguen siendo imposibles. '
      || 'Las demas congelaciones y la rama de contratos quedaron byte a byte. Re-sellada el 22/09/2026 tras '
      || 'leer el cuerpo vivo y su contencion; ningun permiso cambio (es una funcion de trigger, invoker).'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'public.proteger_campos_inmutables()';

-- ---------------------------------------------------------------------------
-- (c) POSTFLIGHT: no se da por bueno, se comprueba -- y se deja que el vigia
--     cierre sus propias alertas, que es justo lo que se instalo esta manana.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok text; v_f5a_antes integer; v_f5a_despues integer;
  v_f6a integer; v_f7 integer; v_f6a2 integer; v_f7b integer;
begin
  -- 1. El gate, verde.
  v_ok := private.assert_analista_vigencia();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el gate de vigencia no quedo verde: %', v_ok;
  end if;

  -- 2. Y verde para TODAS: ninguna otra huella se toco.
  if exists (select 1 from private.analista_vigencia_exenciones e
               join pg_proc p on p.oid = to_regprocedure(e.objeto)
              where e.huella is distinct from
                    md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))) then
    raise exception 'POSTFLIGHT: quedo alguna puerta con la huella caduca';
  end if;
  if (select count(*) from private.analista_vigencia_exenciones) <> 5 then
    raise exception 'POSTFLIGHT: el numero de puertas declaradas cambio; esta migracion solo re-sella una';
  end if;

  -- 3. La razon nueva esta puesta y nombra la contencion.
  if not exists (select 1 from private.analista_vigencia_exenciones
                  where objeto = 'public.proteger_campos_inmutables()'
                    and razon ~ 'pg_current_xact_id'
                    and razon ~ 'responsable_relacion_id') then
    raise exception 'POSTFLIGHT: la razon nueva no describe la contencion de la excepcion F4';
  end if;

  -- 4. El vigia cierra sus 16 EL SOLO, corriendo la misma funcion que el cron.
  select count(*) filter (where fase='f5a_analista_vigencia'),
         count(*) filter (where fase='f6a_analitica_leads_citas'),
         count(*) filter (where fase='f7_piezas_cerradas')
    into v_f5a_antes, v_f6a, v_f7
    from private.vigia_alertas where resuelta_en is null;

  perform private.vigia_analista_vigencia();

  select count(*) filter (where fase='f5a_analista_vigencia'),
         count(*) filter (where fase='f6a_analitica_leads_citas'),
         count(*) filter (where fase='f7_piezas_cerradas')
    into v_f5a_despues, v_f6a2, v_f7b
    from private.vigia_alertas where resuelta_en is null;

  if v_f5a_despues <> 0 then
    raise exception 'POSTFLIGHT: el gate quedo verde pero el vigia dejo % alertas f5a abiertas (eran %)',
      v_f5a_despues, v_f5a_antes;
  end if;
  if v_f6a2 <> v_f6a or v_f7b <> v_f7 then
    raise exception 'POSTFLIGHT: el vigia de vigencia toco alertas AJENAS (f6a % -> %, f7 % -> %)',
      v_f6a, v_f6a2, v_f7, v_f7b;
  end if;
end;
$postflight$;

-- El veredicto viaja por una FILA: el canal `supabase db query` no transporta
-- los `raise notice`, y hace falta VER el sello para poder deshacerlo.
select 'vigencia-redeclarar-candado-perfiles'                                  as migracion,
       private.assert_analista_vigencia()                                      as gate_vigencia,
       (select count(*) from private.vigia_alertas where resuelta_en is null)   as alertas_abiertas,
       (select max(resuelta_en) from private.vigia_alertas)                     as sello_de_cierre,
       (select coalesce(string_agg(fase || ' (' || n || ')', ', '), '(ninguna)')
          from (select fase, count(*) n from private.vigia_alertas
                 where resuelta_en is null group by fase) z)                    as lo_que_queda;

commit;

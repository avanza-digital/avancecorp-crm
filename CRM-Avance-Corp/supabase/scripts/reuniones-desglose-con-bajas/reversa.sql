-- REVERSA de 20261022170900_crm_reuniones_desglose_con_bajas.sql (bloque 2.12: D-43, D-46, D-47 y D-48).
--
-- FALLA CERRADA. Antes de revertir exige que las dos puertas (`crm.metricas_reuniones_fn(date,date)` y
-- `crm.metricas_agenda_fn(date,date)`) tengan EXACTAMENTE la definición que dejó la migración (md5 de `prosrc` y de
-- `pg_get_functiondef`), su dueño, su ACL efectiva (EXECUTE para `authenticated` y el dueño) y el comentario que les puso; que
-- las dos piezas (`private.filtrar_desglose_sujetos_con_bajas_crm` y `private.desglose_responsables_reuniones_crm`) tengan la
-- definición, el dueño, la ACL (solo el dueño) y el comentario que dejó la migración; y que NINGUNA otra función las nombre
-- (PL/pgSQL no registra esa dependencia: borrarlas rompería en silencio a quien las llame). Se niega si la migración no está
-- aplicada o si alguien cambió algo después (p. ej. `ALTER FUNCTION … SET lock_timeout`): en esos casos NO se revierte nada y
-- se revisa a mano. (Ensayado con `armar-ensayo.mjs --reversa-con-set`.)
--
-- QUÉ RESTAURA: los cuerpos anteriores de las dos puertas, byte a byte (`md5(prosrc)` vuelve a ca480bc7… y 104d863b…; la
-- definición, a de328143… y 1a5f2938…), su ausencia de comentario, y borra las dos piezas. El postflight exige esas huellas, la
-- ficha de las puertas idéntica a la previa (dueño, ACL, atributos), las piezas ausentes, las dependencias intactas y la FOTO de
-- los `private.assert_*()` sin argumentos y sin los `*_mutantes` idéntica a la de antes de revertir (estado, o SQLSTATE y texto
-- íntegro del primer error). Garantiza eso y solo eso: no acredita PASS de los gates que ya caían.
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `STABLE`, `search_path` vacío y ACL de las puertas (`create or replace` no
-- los toca). No toca las implementaciones ni su registro analítico (la migración tampoco).
--
-- NO DESHACE DATOS: la migración no escribía datos; el desglose se calcula al leer. Tras revertir, el analista de baja o
-- suspendido vuelve a desaparecer del desglose de reuniones y de la agenda, y lo que queda fuera vuelve a verse como «Fuera del
-- desglose actual»: es el defecto que la migración cerraba. Con la app nueva publicada es seguro (las marcas son opcionales).
begin;
set local search_path = '';
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_reuniones constant text := 'crm.metricas_reuniones_fn(date,date)';
  v_agenda constant text := 'crm.metricas_agenda_fn(date,date)';
  v_filtro constant text := 'private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])';
  v_pieza constant text := 'private.desglose_responsables_reuniones_crm(jsonb)';
  v_usuarios text;
  v_foto text := '';
  v_gates integer := 0;
  v text;
  r record;
begin
  if to_regprocedure(v_reuniones) is null or to_regprocedure(v_agenda) is null then
    raise exception 'REVERSA reuniones_desglose_con_bajas: falta una puerta; nada que revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_reuniones::regprocedure) is distinct from 'e448db0cf1d929441da2347a0f48d85d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = v_agenda::regprocedure) is distinct from 'c41eb0d85abd976bca03092e9a932d00' then
    raise exception 'REVERSA reuniones_desglose_con_bajas: el cuerpo de una puerta no es el que dejó la migración (no está aplicada o cambió después): revisar antes de revertir';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_reuniones::regprocedure) is distinct from '8399e43326dfca3da80ef78e4e8a62c3'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_agenda::regprocedure) is distinct from '671b7fcd544e504b1ef6a1ff496261c3' then
    raise exception 'REVERSA reuniones_desglose_con_bajas: una puerta no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET lock_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if exists (select 1 from unnest(array[v_reuniones, v_agenda]) f
              where (select p.proowner::regrole::text || '|' || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                                                         order by a.grantee::regrole::text, a.privilege_type)
                                                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                       from pg_proc p where p.oid = f::regprocedure)
                    is distinct from 'postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false')
     or obj_description(v_reuniones::regprocedure, 'pg_proc') is distinct from
       'Puerta de las métricas de citas para Gerencia o un lector global (los demás reciben 42501). Hoy la consume el Resumen de Gerencia, que solo lee resumen y conversion; el panel que pinta el desglose por responsable (ReunionesGerenciaPanel, de HoyGerencia) no se monta en ninguna ruta, y la pantalla viva de citas de Gerencia y Supervisión usa crm.citas_gerencia_consulta_fn (la marca llega allí con el bloque 2.14, D-53). El desglose por responsable pasa por private.desglose_responsables_reuniones_crm y queda como coherencia de la API: el analista o supervisor dado de baja (ficha de crm.equipo inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con sus citas y "de_baja": true o "suspendido": true en su elemento, y lo que queda fuera (citas sin responsable, de otros roles) va a una fila «Otros» al final con "otros": true: el desglose suma siempre el total (bloque 2.12: D-43, D-46 y D-47, 09/10/2026). Sin bajas, suspendidos ni «Otros» en la ventana, la respuesta es idéntica a la anterior.'
     or obj_description(v_agenda::regprocedure, 'pg_proc') is distinct from
       'Puerta del panel «Agenda del equipo» (analista, supervisor, Gerencia o lector global; los demás reciben 42501); el ámbito lo decide private.metricas_agenda_implementacion. El listado pasa por private.filtrar_desglose_sujetos_con_bajas_crm: el analista o supervisor dado de baja (ficha inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con "de_baja": true o "suspendido": true SOLO si tiene actividad en el período (las nueve claves de tieneActividad de la app); sin ella, fuera como antes (bloque 2.12: D-48, y D-54 para «suspendido», que también ven el supervisor, solo de su subárbol, y Directorio; 09/10/2026). Sin bajas ni suspendidos con actividad, la respuesta es idéntica a la anterior. La app valida esta respuesta con un objeto estricto: se publica ANTES la app que acepta las marcas.' then
    raise exception 'REVERSA reuniones_desglose_con_bajas: el dueño, la ACL efectiva o el comentario de una puerta no son los que dejó la migración: revisar antes de revertir';
  end if;
  if to_regprocedure(v_filtro) is null or to_regprocedure(v_pieza) is null
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
           from pg_proc p where p.oid = to_regprocedure(v_filtro))
       is distinct from '4980e12d69eccd74daee5e27967abcd6|e1ea83ff4c82452cfa9d74c5b70f8e0d|postgres|postgres:EXECUTE:false'
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
           from pg_proc p where p.oid = to_regprocedure(v_pieza))
       is distinct from '041b9ca65e6948b32d2a50a8d4479711|671a0b3db8d5e5ea4056c13c786c6b32|postgres|postgres:EXECUTE:false'
     or obj_description(to_regprocedure(v_filtro), 'pg_proc') is distinct from
       'Listado por sujeto de una métrica CON los dados de baja y los suspendidos (bloque 2.12: D-43, D-46, D-48 y D-54, 09/10/2026). Deja, sin tocar su elemento, exactamente a quien deja private.filtrar_desglose_sujetos_crm (private.rol_crm dentro de p_roles) y además conserva a quien tiene una ficha de crm.equipo de uno de p_roles y hoy está dado de baja (ficha inactiva, la regla de private.analista_dado_de_baja: "de_baja": true) o suspendido en el Portal (ficha activa y perfil activo is not true: "suspendido": true), si p_claves_actividad es nulo o alguna de esas claves de su elemento es distinta de cero; si su nombre está vacío o en blanco, sale como «(sin nombre)». Sin ficha, sin identidad o con ficha y perfil activos pero sin rol efectivo, no entra. No concede autoridad: solo nombra. Sin bajas ni suspendidos, la salida es idéntica a la del filtro común. La usan crm.metricas_agenda_fn y private.desglose_responsables_reuniones_crm.'
     or obj_description(to_regprocedure(v_pieza), 'pg_proc') is distinct from
       'Desglose por responsable de crm.metricas_reuniones_fn (bloque 2.12: D-43, D-46 y D-47, 09/10/2026): private.filtrar_desglose_sujetos_con_bajas_crm con analistas y supervisores (sin condición de actividad: todo elemento tiene citas) y, si queda alguien fuera (citas sin responsable, de Gerencia o Coordinación, de un ex Gerencia de baja, de un perfil sin rol efectivo), una fila «Otros» al final con las mismas columnas: responsable_id nulo, nombre «Otros», supervisor «—» y "otros": true; cada cifra es la de todos los elementos de la implementación menos la de los que quedaron en el desglose, y pct_realizacion se recalcula como en la implementación. Así el desglose suma siempre el total. Sin nadie fuera, no añade nada.' then
    raise exception 'REVERSA reuniones_desglose_con_bajas: una pieza nueva no es la que dejó la migración (falta, o cambió su cuerpo, su definición, su dueño, su ACL o su comentario): revisar antes de revertir';
  end if;
  -- Quién nombra a las piezas: solo la agenda y la pieza de reuniones a la genérica; solo la puerta de reuniones a la de reuniones.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_usuarios
    from pg_proc p
   where (p.prosrc like '%filtrar_desglose_sujetos_con_bajas_crm%'
          and p.oid not in (v_agenda::regprocedure, to_regprocedure(v_pieza), to_regprocedure(v_filtro)))
      or (p.prosrc like '%desglose_responsables_reuniones_crm%'
          and p.oid not in (v_reuniones::regprocedure, to_regprocedure(v_pieza)));
  if v_usuarios is not null then
    raise exception 'REVERSA reuniones_desglose_con_bajas: otra función nombra una pieza nueva (%): borrarla la rompería; revisar antes de revertir', v_usuarios;
  end if;
  perform set_config('crm.bajas_reversa_ficha_previa',
    (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
        || '|' || (select l.lanname from pg_language l where l.oid = p.prolang)::text, E'\n' order by p.oid::regprocedure::text)
       from pg_proc p where p.oid in (v_reuniones::regprocedure, v_agenda::regprocedure)), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    v_gates := v_gates + 1;
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('crm.bajas_reversa_trinquetes', v_foto, true);
end
$preflight$;

create or replace function crm.metricas_reuniones_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_reuniones_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'responsables','responsable_id',array['vendedor','supervisor']
  );
end;
$function$;

create or replace function crm.metricas_agenda_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor) in ('vendedor','supervisor','gerencia')
    or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_agenda_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'vendedores','vendedor_id',array['vendedor','supervisor']
  );
end;
$function$;

comment on function crm.metricas_reuniones_fn(date,date) is null;
comment on function crm.metricas_agenda_fn(date,date) is null;

drop function private.desglose_responsables_reuniones_crm(jsonb);
drop function private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[]);

do $postflight$
declare
  v_reuniones constant text := 'crm.metricas_reuniones_fn(date,date)';
  v_agenda constant text := 'crm.metricas_agenda_fn(date,date)';
  v_distintas text;
  v_foto text := '';
  v_gates integer := 0;
  v text;
  r record;
begin
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_reuniones::regprocedure)
       is distinct from 'ca480bc76d7624fbd3f6e6b2016d5fc3|de328143bd9221fb19bfa6af46695290'
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_agenda::regprocedure)
       is distinct from '104d863b5702506d18b7adca1ecbcb92|1a5f2938a6c42f44b511e53f48edf963' then
    raise exception 'REVERSA reuniones_desglose_con_bajas: una puerta no quedó como estaba antes de la migración';
  end if;
  if (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
        || '|' || (select l.lanname from pg_language l where l.oid = p.prolang)::text, E'\n' order by p.oid::regprocedure::text)
        from pg_proc p where p.oid in (v_reuniones::regprocedure, v_agenda::regprocedure))
     is distinct from current_setting('crm.bajas_reversa_ficha_previa', true)
     or obj_description(v_reuniones::regprocedure, 'pg_proc') is not null
     or obj_description(v_agenda::regprocedure, 'pg_proc') is not null then
    raise exception 'REVERSA reuniones_desglose_con_bajas: cambió el dueño, la ACL o un atributo de una puerta, o quedó su comentario';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace
                                       and p.proname in ('filtrar_desglose_sujetos_con_bajas_crm', 'desglose_responsables_reuniones_crm')) then
    raise exception 'REVERSA reuniones_desglose_con_bajas: una pieza nueva sigue existiendo';
  end if;
  select string_agg(e.objeto, ', ' order by e.objeto) into v_distintas
    from (values
      ('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])',
       '1cce2929af369715a2c7e161d63fc7ce|2652303501f4e7ca1d55d37ede3fd24a|postgres|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'd2878a210be96ac85973d51dfcfb27a5|99827f3fe2fbc3cfae5668c30015c758|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.es_lector_global()',
       'c7c5828be6d74121a1a0ef0de374f712|c8be602f84348a0125617995802db618|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.metricas_reuniones_implementacion(date,date)',
       'ca6fe61e76bcb8bf2d213acb1b7fc030|ce852e3740f60a57938e2baf2c0b736d|postgres|postgres:EXECUTE:false'),
      ('private.metricas_agenda_implementacion(date,date)',
       '0fc09f917a816013e1af16ef183012de|5cb341dc430b7441ff8abdd3c8110c60|postgres|postgres:EXECUTE:false'),
      ('private.vendedor_ids_visibles(uuid)',
       '33ece9bae4828f7ffdb837c6128ca9d6|85544c70a0920f3a7a1b5da06935f236|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false')
    ) e(objeto, ficha)
   where e.ficha is distinct from (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                                     from pg_proc p where p.oid = to_regprocedure(e.objeto));
  if v_distintas is not null then
    raise exception 'REVERSA reuniones_desglose_con_bajas: cambió algo que la reversa no debía tocar: %', v_distintas;
  end if;
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    v_gates := v_gates + 1;
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('crm.bajas_reversa_trinquetes', true) then
    raise exception E'REVERSA reuniones_desglose_con_bajas: algún private.assert_*() da otro resultado que antes de revertir.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.bajas_reversa_trinquetes', true), v_foto;
  end if;
  raise notice 'REVERSA reuniones_desglose_con_bajas: puertas de nuevo en ca480bc7… y 104d863b… · piezas retiradas · % trinquetes con estado y texto íntegro del primer error idénticos',
    v_gates;
end
$postflight$;

commit;

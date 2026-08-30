-- MARCHA ATRAS de la Fase 5.a (una sola pregunta: es analista vigente).
--
-- DOS BLOQUES, a proposito. El primero es el que se usa si el arreglo rompe algo
-- del portal en vivo. El segundo NO se ejecuta salvo que se quiera volver al
-- estado historico exacto, porque revierte tambien la reparacion de un bug
-- AJENO a esta fase.
--
-- Las 4 politicas se devuelven a su definicion VIVA del 2026-08-30, anclada por
-- huella (md5) antes y despues. Las 3 funciones se devuelven por REEMPLAZO
-- INVERSO anclado: no se re-teclea el cuerpo, se sustituye la pregunta nueva por
-- la vieja sobre el cuerpo VIVO, para no perder nada que otra sesion haya metido.

-- =====================================================================
-- BLOQUE 1 - REVERTIR LAS SIETE PUERTAS (el rollback operativo)
-- =====================================================================
begin;

set local lock_timeout = '5s';

alter policy contratos_analista_select on public.contratos
  using (
    public.es_analista()
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = contratos.cliente_id
        and cli.rol = 'cliente'
        and (
          cli.asesor_perfil_id = (select auth.uid())
          or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid()))
        )
    )
  );

alter policy cronograma_analista_select on public.cronograma_pagos
  using (
    public.es_analista()
    and exists (
      select 1
      from public.contratos c
      join public.perfiles cli on cli.id = c.cliente_id
      where c.id = cronograma_pagos.contrato_id
        and cli.rol = 'cliente'
        and (
          cli.asesor_perfil_id = (select auth.uid())
          or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid()))
        )
    )
  );

alter policy perfiles_analista_select on public.perfiles
  using (
    public.es_analista()
    and rol = 'cliente'
    and (
      asesor_perfil_id = (select auth.uid())
      or (asesor_perfil_id is null and creado_por = (select auth.uid()))
    )
  );

alter policy perfiles_analista_update on public.perfiles
  using (
    public.es_analista()
    and rol = 'cliente'
    and creado_en > (now() - '05:00:00'::interval)
    and (
      creado_por = (select auth.uid())
      or asesor_perfil_id = (select auth.uid())
    )
  )
  with check (
    public.es_analista()
    and rol = 'cliente'
    and (
      creado_por = (select auth.uid())
      or asesor_perfil_id = (select auth.uid())
    )
  );

-- Las tres funciones, por reemplazo INVERSO anclado.
do $$
declare
  v_def text; v_ancla text; v_veces integer;
  v_obj text;
begin
  foreach v_obj in array array['crm.cliente_detalle_fn', 'public.puede_ver_contrato', 'public.productos_inversion_seleccion_fn'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = split_part(v_obj, '.', 1) and p.proname = split_part(v_obj, '.', 2);

    v_ancla := 'private.es_analista_vigente()';
    v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_veces = 0 then
      raise exception 'rollback F5.a: % ya no pregunta por la vigencia (nada que revertir o cuerpo cambiado)', v_obj;
    end if;
    execute replace(v_def, v_ancla, 'public.es_analista()');
  end loop;
end $$;

-- El trinquete y el candado del borrado se retiran con la fase.
--
-- ⚠️ LAS DOS TABLAS NO SE BORRAN a proposito. Si se borrasen, entre una marcha
--    atras y una re-aplicacion se perderian las RAZONES declaradas y la
--    propiedad "el tope solo baja" se reiniciaria con el conteo del momento
--    -que es justo lo que un trinquete no puede permitirse-. Sin sus funciones
--    son dos tablas inertes; al re-aplicar, el `least(...)` conserva el tope mas
--    bajo que se haya alcanzado.
drop trigger if exists trg_equipo_no_borrar on crm.equipo;
-- La puerta declarada se va con el candado. `private.membresias_purgadas` NO se
-- borra: son lapidas, es decir, evidencia de bajas hechas purgando.
drop function if exists crm.purgar_membresia_crm(uuid, text);
drop function if exists private.trg_equipo_no_borrar();
do $$
begin
  if exists (select 1 from cron.job where jobname = 'crm-vigencia-analista-vigia') then
    perform cron.unschedule('crm-vigencia-analista-vigia');
  end if;
end $$;
drop function if exists private.vigia_analista_vigencia();
drop function if exists private.assert_analista_vigencia();
drop function if exists private.puertas_analista_sin_vigencia();
drop trigger if exists trg_analista_vigencia_tope_solo_baja on private.analista_vigencia_tope;
drop trigger if exists trg_analista_vigencia_tope_no_truncar on private.analista_vigencia_tope;
drop function if exists private.trg_analista_vigencia_tope_solo_baja();
drop function if exists private.trg_analista_vigencia_tope_no_truncar();
drop function if exists private.es_analista_vigente();

-- POSTFLIGHT: la preimagen, por huella. No basta con que no aparezca la palabra:
-- si faltara una politica entera, la comprobacion de ausencia quedaria verde.
do $$
declare
  v_esperado constant text[][] := array[
    array['public', 'contratos',        'contratos_analista_select',  '5a24688ac0b5e25e73aaf3d27d0c49d9', ''],
    array['public', 'cronograma_pagos', 'cronograma_analista_select', 'e843b1a209c10f3610e6d797f188a1f8', ''],
    array['public', 'perfiles',         'perfiles_analista_select',   'cb4ffa816804f998b8a3c57626d3e54a', ''],
    array['public', 'perfiles',         'perfiles_analista_update',   'ecf097f78023a74f2ff66303c7c8cfdb', '2911ed25bfadabb95c50dcd51fadb73a']
  ];
  v_fila text[]; v_using text; v_check text;
begin
  foreach v_fila slice 1 in array v_esperado loop
    select md5(pg_get_expr(pol.polqual, pol.polrelid)),
           coalesce(md5(pg_get_expr(pol.polwithcheck, pol.polrelid)), '')
      into v_using, v_check
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = v_fila[1] and c.relname = v_fila[2] and pol.polname = v_fila[3];
    if not found then
      raise exception 'rollback F5.a: falta la politica %.%', v_fila[2], v_fila[3];
    end if;
    if v_using is distinct from v_fila[4] or v_check is distinct from v_fila[5] then
      raise exception 'rollback F5.a: %.% no volvio a su preimagen (using %, check %)', v_fila[2], v_fila[3], v_using, v_check;
    end if;
  end loop;

  if (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='crm' and p.proname='cliente_detalle_fn') is distinct from 'f1541e556beb8a1de4a4d464fa8f10cd' then
    raise exception 'rollback F5.a: crm.cliente_detalle_fn no volvio a su huella original';
  end if;
  if (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='puede_ver_contrato') is distinct from 'c746e2e7184132e99923a463a4dcf694' then
    raise exception 'rollback F5.a: public.puede_ver_contrato no volvio a su huella original';
  end if;
  if (select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='productos_inversion_seleccion_fn') is distinct from 'f984bd0a4d9ba86cefff2d74542c483b' then
    raise exception 'rollback F5.a: public.productos_inversion_seleccion_fn no volvio a su huella original';
  end if;
end $$;

commit;

-- =====================================================================
-- BLOQUE 2 - SOLO PARA VOLVER AL ESTADO HISTORICO EXACTO. NO EJECUTAR
-- SALVO QUE SE QUIERA ESO A PROPOSITO.
-- =====================================================================
-- Quitar este EXECUTE REABRE un fallo que NO es de la Fase 5.a: la politica
-- `reasignaciones_lee_autoridad` de la Fase 3 vuelve a reventar con 42501, de
-- modo que NADIE -ni gerencia- puede leer el historial de reasignaciones por
-- acceso directo. Si la marcha atras es por un problema del portal, deja este
-- permiso puesto.
--
-- begin;
--   revoke execute on function private.membresia_crm_revocada() from authenticated;
--   do $$
--   begin
--     if exists (
--       select 1 from pg_proc p
--       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
--        where p.oid = 'private.membresia_crm_revocada()'::regprocedure
--          and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::regrole::oid
--     ) then
--       raise exception 'rollback F5.a bloque 2: el permiso sigue concedido';
--     end if;
--   end $$;
-- commit;

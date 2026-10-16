-- Referidos propios de supervisores. Decisión de Miguel, 16/10/2026.
-- Solo cambia la autorización del alta; conserva firma, ACL, candados,
-- idempotencia, validaciones, origen inmutable y revalidación de rol vigente.
begin;
set local lock_timeout = '5s';
do $cambio$
declare
  v_oid oid := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
  v_def text;
begin
  if (select md5(prosrc) from pg_catalog.pg_proc where oid=v_oid)
      is distinct from 'b6ec8dddaa8ab81b9248a79f4de3a51f' then
    raise exception 'PREFLIGHT: cambió el alta de leads revisada';
  end if;
  v_def := pg_get_functiondef(v_oid);
  v_def := replace(v_def, $antes$  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;
$antes$, $despues$  -- Referidos propios (Miguel, 16/10/2026): también Supervisión.
  -- El bloque de destino exige que el responsable sea el actor.
  if p_origen = 'referido' and v_rol not in ('vendedor', 'supervisor') then
    raise exception using
      errcode = '42501',
      message = 'Solo analistas y supervisores pueden registrar sus propios referidos';
  end if;
$despues$);
  v_def := replace(v_def, $antes$  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then$antes$, $despues$  -- Todo referido se autoasigna: un destino omitido también significa el actor.
  -- Los demás orígenes conservan el reparto de Supervisión y Gerencia.
  if v_rol = 'vendedor' or (v_rol = 'supervisor' and p_origen = 'referido') then$despues$);
  execute v_def;
  if (select md5(prosrc) from pg_catalog.pg_proc where oid=v_oid)
      is distinct from '145b30a30e69807a1838c1b960a0675d' then
    raise exception 'POSTFLIGHT: el alta no coincide con la definición ensayada';
  end if;
end $cambio$;
commit;


#!/usr/bin/env python3
"""Genera reversa.sql y reabrir-puerta.sql de la migración 20261002005004 (asignar cuenta de pago).

  python3 supabase/scripts/cuentas-pago-asignar/generar-derivados.py              # los escribe
  python3 supabase/scripts/cuentas-pago-asignar/generar-derivados.py --verificar  # falla si están viejos

Los dos guiones comparten UNA definición de «las piezas están enteras como las dejó la migración»
(cuerpos por huella, DEFINER/INVOKER, search_path, dueño, permisos, RLS, candados, bitácora, reglas
de la tabla y las piezas de F3 de las que depende). Las huellas salen del archivo de la migración:
si la migración cambia, se regeneran y no hay literales que mantener a mano.
"""
import hashlib, io, os, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
MIG = "20261002005004_crm_asignar_cuenta_pago.sql"
VERSION = "20261002005004"
mig = io.open(os.path.join(AQUI, "..", "..", "migrations", MIG), encoding="utf-8").read()


def md5(texto):
    return hashlib.md5(texto.encode("utf-8")).hexdigest()


def cuerpo(nombre):
    ini = mig.index("create function " + nombre + "(")
    a = mig.index("$function$", ini) + len("$function$")
    return mig[a:mig.index("$function$", a)]


H_INMUTABLE = md5(cuerpo("private.trg_contrato_cuenta_pago_asignaciones_inmutable"))
H_NUCLEO = md5(cuerpo("private.asignar_cuenta_pago_contrato_autorizado"))
H_PUERTA = md5(cuerpo("crm.asignar_cuenta_pago_contrato"))
for h in (H_INMUTABLE, H_NUCLEO, H_PUERTA):
    assert h in mig, "la migración no lleva la huella de uno de sus cuerpos en el postflight"

# Las piezas de F3 de las que depende, con las huellas que la propia migración exige al aplicarse.
DEP_COMPUERTA = "810dce30e37d1da9d913ef48ab6a4aa1"   # private.admin_banca_vigente(uuid)
DEP_COHERENTE = "7e946a5af78a827c18ee5b218896f24c"   # private.trg_contrato_cuenta_pago_coherente()
DEP_NO_BORRAR = "e95919db53c44ff1fe6632c346f27a06"   # private.trg_registro_cuenta_pago_no_borrar()
for h in (DEP_COMPUERTA, DEP_COHERENTE, DEP_NO_BORRAR):
    assert h in mig, "la migración ya no ancla una de las piezas de F3 con la huella esperada"

F_INMUTABLE = "private.trg_contrato_cuenta_pago_asignaciones_inmutable()"
F_NUCLEO = "private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)"
F_PUERTA = "crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)"
TABLA = "crm.contrato_cuenta_pago_asignaciones"

# ¿Alguien que no sea el dueño puede ejecutar la puerta o el núcleo? (cerrada = nadie)
ALGUIEN_EJECUTA = f"""exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (pg_catalog.to_regprocedure('{F_PUERTA}'), pg_catalog.to_regprocedure('{F_NUCLEO}'))
        and (p.proacl is null
             or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                        where a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner)))"""

# «Las piezas están enteras como las dejó la migración». Tolera que algo falte (da false, no error).
# No mira si authenticated tiene o no EXECUTE en puerta y núcleo: eso es lo que abre o cierra.
INTACTAS = f"""coalesce((
    -- las tres funciones: cuerpo, DEFINER/INVOKER, search_path exacto y dueño
    (select pg_catalog.count(*)
     from (values
       ('{F_INMUTABLE}', true, '{H_INMUTABLE}'),
       ('{F_NUCLEO}', true, '{H_NUCLEO}'),
       ('{F_PUERTA}', false, '{H_PUERTA}')
     ) as f(firma, definer, huella)
     join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
     where pg_catalog.md5(p.prosrc) = f.huella
       and p.prosecdef = f.definer
       and p.proconfig = array['search_path=""']
       and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) = 3
    -- nadie de más las ejecuta: authenticated, solo en la puerta y el núcleo
    and not exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (pg_catalog.to_regprocedure('{F_PUERTA}'), pg_catalog.to_regprocedure('{F_NUCLEO}'),
                      pg_catalog.to_regprocedure('{F_INMUTABLE}'))
        and (p.proacl is null
             or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                        where a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
                          and (a.grantee <> 'authenticated'::regrole::oid
                               or p.oid = pg_catalog.to_regprocedure('{F_INMUTABLE}')))))
    -- las piezas de F3 de las que depende: la compuerta de administración y los candados del vínculo
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.admin_banca_vigente(uuid)')) = '{DEP_COMPUERTA}'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()')) = '{DEP_COHERENTE}'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()')) = '{DEP_NO_BORRAR}'
    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and t.tgenabled = 'O'
           and (t.tgname, t.tgfoid) in (
             ('trg_contrato_cuenta_pago_coherente', pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()')::oid),
             ('trg_audit_contrato_cuentas_pago', pg_catalog.to_regprocedure('private.log_audit_crm()')::oid),
             ('trg_contrato_cuenta_pago_00_inmutable', pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()')::oid))) = 3
    -- la constancia: RLS, sin acceso de la API, sus tres candados con su forma, bitácora y reglas
    and coalesce((select t.relrowsecurity from pg_catalog.pg_class t
                  where t.oid = pg_catalog.to_regclass('{TABLA}')), false)
    and not exists (
      select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
      where pg_catalog.has_table_privilege(r.rol, pg_catalog.to_regclass('{TABLA}')::oid,
              'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = pg_catalog.to_regclass('{TABLA}')
           and t.tgenabled = 'O' and t.tgqual is null and t.tgattr::text = ''
           -- tgtype: fila 1 · antes 2 · borrar 8 · modificar 16 · vaciar 32
           and (t.tgname, t.tgfoid, t.tgtype::integer) in (
             ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
              pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()')::oid, 11),
             ('trg_contrato_cuenta_pago_asignaciones_00_inmutable',
              pg_catalog.to_regprocedure('{F_INMUTABLE}')::oid, 19),
             ('trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
              pg_catalog.to_regprocedure('{F_INMUTABLE}')::oid, 34))) = 3
    and exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('{TABLA}')
        and t.tgname = 'trg_audit_contrato_cuenta_pago_asignaciones'
        and t.tgfoid = pg_catalog.to_regprocedure('private.log_audit_crm()')::oid
        and t.tgenabled = 'O' and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 28) = 28
        and t.tgqual is null and t.tgattr::text = '')
    and exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('{TABLA}') and c.contype = 'u'
        and c.conname = 'contrato_cuenta_pago_asignaciones_solicitud_uq' and not c.condeferrable)
    and exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('{TABLA}') and c.contype = 'c'
        and c.conname = 'contrato_cuenta_pago_asignaciones_motivo_valido' and c.convalidated)
    -- lo que el núcleo da por hecho del vínculo: UNO por contrato, con el nombre por el que lo reconoce
    and exists (
      select 1
      from pg_catalog.pg_constraint c
      join pg_catalog.pg_index i on i.indexrelid = c.conindid
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and c.contype = 'u'
        and c.conname = 'contrato_cuentas_pago_contrato_id_key' and not c.condeferrable
        and i.indisunique and i.indpred is null and i.indisvalid and i.indimmediate and i.indnatts = 1
        and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                           where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago')
                             and a.attname = 'contrato_id'))
    -- la puerta y el núcleo escriben: las dos VOLATILE
    and (select pg_catalog.count(*) from pg_catalog.pg_proc p
         where p.oid in (pg_catalog.to_regprocedure('{F_PUERTA}'), pg_catalog.to_regprocedure('{F_NUCLEO}'))
           and p.provolatile = 'v') = 2
    -- la constancia sigue sin claves foráneas, sin permisos por columna y sin disparadores de más
    and not exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('{TABLA}') and c.contype = 'f')
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = pg_catalog.to_regclass('{TABLA}') and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null)
    and not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('{TABLA}') and not t.tgisinternal
        and t.tgname not in ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
                             'trg_contrato_cuenta_pago_asignaciones_00_inmutable',
                             'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
                             'trg_audit_contrato_cuenta_pago_asignaciones'))
  ), false)"""

REVERSA = f"""-- REVERSA de {MIG}. GENERADA por generar-derivados.py (no se edita a mano).
--   · Si NO hay ninguna asignación registrada y las piezas están ENTERAS como las dejó la migración:
--     deja todo como antes (quita la puerta, el núcleo, el candado y la tabla de constancias, que
--     está vacía) y borra su fila de supabase_migrations.schema_migrations.
--   · En cualquier otro caso NO borra nada: solo CIERRA la puerta. Retira el permiso de ejecutar
--     de la puerta y del núcleo a TODO el que lo tenga (no solo a los roles conocidos) y comprueba
--     que no quede nadie salvo el dueño. Las constancias y los vínculos que crearon son
--     instrucciones de pago en uso, y la versión sigue registrada. Cerrar es siempre seguro: se
--     hace aunque falte una pieza o alguna haya cambiado. Para reabrir: reabrir-puerta.sql.
-- No toca ningún vínculo en ningún caso.
-- Límite conocido: una asignación que ya había empezado cuando se lanza la reversa espera a que
-- esta termine y luego se completa (el permiso se comprueba al entrar). Si el veredicto dice
-- PUERTA_CERRADA, vuelve a contar las asignaciones un minuto después.
-- El veredicto final se lee del ESTADO real de la base, no de esta sesión.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reversa$
declare
  v_asignaciones bigint;
  v_intactas boolean;
  v_f record;
begin
  -- Se cuenta DESPUÉS de tomar el candado de la tabla: eso solo vale en READ COMMITTED (con una
  -- fotografía anterior al candado se podría borrar una tabla que ya tiene una asignación).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if pg_catalog.to_regclass('{TABLA}') is null
     and pg_catalog.to_regprocedure('{F_PUERTA}') is null
     and pg_catalog.to_regprocedure('{F_NUCLEO}') is null
     and pg_catalog.to_regprocedure('{F_INMUTABLE}') is null then
    raise exception 'REVERSA ASIGNAR: la migración {VERSION} no está aplicada; no hay nada que revertir';
  end if;

  -- Nadie asigna mientras se decide: la asignación escribe en esta tabla.
  if pg_catalog.to_regclass('{TABLA}') is not null then
    execute 'lock table {TABLA} in access exclusive mode';
    execute 'select pg_catalog.count(*) from {TABLA}' into v_asignaciones;
  end if;

  v_intactas := {INTACTAS};

  if v_asignaciones = 0 and v_intactas then
    execute 'drop function {F_PUERTA}';
    execute 'drop function {F_NUCLEO}';
    execute 'drop table {TABLA}';
    execute 'drop function {F_INMUTABLE}';
    if pg_catalog.to_regclass('{TABLA}') is not null
       or pg_catalog.to_regprocedure('{F_PUERTA}') is not null
       or pg_catalog.to_regprocedure('{F_NUCLEO}') is not null
       or pg_catalog.to_regprocedure('{F_INMUTABLE}') is not null then
      raise exception 'REVERSA ASIGNAR: quedó alguna pieza de la migración';
    end if;
    -- Ya no está aplicada: que el registro de versiones tampoco lo diga.
    if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
      execute 'delete from supabase_migrations.schema_migrations where version = '
        || pg_catalog.quote_literal('{VERSION}');
    end if;
  else
    -- Cerrar: a TODO el que tenga EXECUTE (salvo el dueño), en la puerta y en el núcleo que existan.
    for v_f in
      select p.oid::regprocedure::text as firma,
             case when a.grantee = 0 then 'public' else pg_catalog.quote_ident(r.rolname) end as quien
      from pg_catalog.pg_proc p
      cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
      left join pg_catalog.pg_roles r on r.oid = a.grantee
      where p.oid in (pg_catalog.to_regprocedure('{F_PUERTA}'), pg_catalog.to_regprocedure('{F_NUCLEO}'))
        and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    loop
      -- cascade: si alguien recibió el permiso con opción de concederlo y lo volvió a conceder,
      -- esos permisos de segunda mano se van con el suyo (sin cascade, el revoke fallaría).
      execute pg_catalog.format('revoke all on function %s from %s cascade', v_f.firma, v_f.quien);
    end loop;
    if {ALGUIEN_EJECUTA} then
      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';
    end if;
  end if;
end;
$reversa$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila y sale del ESTADO real: dice lo que HAY, no lo que hizo esta corrida
-- (si arriba hay un ERROR, esta corrida no cambió nada y la fila describe lo que ya había).
select case
         when pg_catalog.to_regclass('{TABLA}') is null
          and pg_catalog.to_regprocedure('{F_PUERTA}') is null
          and pg_catalog.to_regprocedure('{F_NUCLEO}') is null
          and pg_catalog.to_regprocedure('{F_INMUTABLE}') is null
           then 'RETIRADA: no queda la puerta, el núcleo ni la tabla de constancias'
         when pg_catalog.to_regprocedure('{F_PUERTA}') is null
          and pg_catalog.to_regprocedure('{F_NUCLEO}') is null
           then 'RESTOS: no quedan la puerta ni el núcleo, pero sí otras piezas de la migración; hay que retirarlas a mano antes de volver a aplicarla'
         when not {ALGUIEN_EJECUTA}
           then 'PUERTA_CERRADA: nadie puede asignar; no se borró nada (las constancias y los vínculos siguen)'
         else 'SIN_CAMBIOS: la puerta sigue abierta'
       end as resultado;
"""

REABRIR = f"""-- REABRIR la puerta de «Asignar cuenta de pago» después de haberla cerrado con reversa.sql.
-- GENERADO por generar-derivados.py (no se edita a mano).
-- Solo devuelve el permiso de ejecutar a authenticated en la puerta y en su núcleo (la compuerta
-- de administración sigue dentro del núcleo). Se niega si las piezas no están ENTERAS como las
-- dejó la migración {VERSION}: cuerpos, DEFINER/INVOKER, search_path, dueño, permisos, RLS,
-- candados, bitácora, reglas de la tabla y las piezas de F3 de las que depende (la compuerta de
-- administración y los candados del vínculo). No se reabre una puerta que alguien cambió sin revisarla.
-- El veredicto final se lee del ESTADO real de la base, no de esta sesión.
-- Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';

do $reabrir$
begin
  if not {INTACTAS} then
    raise exception 'REABRIR ASIGNAR: las piezas no están enteras como las dejó la migración {VERSION} (cuerpos, forma, permisos, candados, bitácora, reglas o las piezas de F3 de las que depende); no se reabre';
  end if;
  execute 'grant execute on function {F_NUCLEO} to authenticated';
  execute 'grant execute on function {F_PUERTA} to authenticated';
  if not {INTACTAS} then
    raise exception 'REABRIR ASIGNAR: tras abrir, las piezas no quedaron como las de la migración';
  end if;
end;
$reabrir$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila y sale del ESTADO real.
select case
         when pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('{F_PUERTA}'), 'EXECUTE')
          and pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('{F_NUCLEO}'), 'EXECUTE')
          and {INTACTAS}
           then 'PUERTA_REABIERTA'
         else 'PUERTA_CERRADA: no se reabrió'
       end as resultado;
"""

DERIVADOS = {"reversa.sql": REVERSA, "reabrir-puerta.sql": REABRIR}

if "--verificar" in sys.argv:
    viejos = []
    for nombre, texto in DERIVADOS.items():
        ruta = os.path.join(AQUI, nombre)
        actual = io.open(ruta, encoding="utf-8").read() if os.path.exists(ruta) else None
        if actual != texto:
            viejos.append(nombre)
    if viejos:
        print("DESFASADOS respecto de la migración (regenéralos): " + ", ".join(viejos), file=sys.stderr)
        sys.exit(1)
    print(f"derivados al día (migración md5 {md5(mig)})")
else:
    for nombre, texto in DERIVADOS.items():
        io.open(os.path.join(AQUI, nombre), "w", encoding="utf-8").write(texto)
    print(f"derivados escritos (migración md5 {md5(mig)}): " + ", ".join(DERIVADOS))
    print(f"  huellas: candado {H_INMUTABLE} · núcleo {H_NUCLEO} · puerta {H_PUERTA}")

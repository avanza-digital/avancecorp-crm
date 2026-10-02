#!/usr/bin/env python3
"""Genera los archivos DERIVADOS de la migración 20261001233019 a partir de los textos fuente.

  python3 supabase/scripts/cuentas-pago-rezago/generar-derivados.py              # los escribe
  python3 supabase/scripts/cuentas-pago-rezago/generar-derivados.py --verificar  # falla si alguno está viejo

Ninguno se escribe a mano, para que no haya dos copias que puedan separarse:
  · reversa.sql y reversa-solo-codigo.sql  — el bloqueo anterior sale byte a byte de 20260925194026.
  · vincular-rezago.sql                    — la carga de la migración, sola, para relanzarla.
  · ensayo-prod-sin-escribir.sql           — la migración entera dentro de una transacción que
                                             termina SIEMPRE en error a propósito.
Si la migración cambia, se regeneran (el ciclo del banco corre --verificar).
"""
import hashlib, io, os, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
MIGS = os.path.join(AQUI, "..", "..", "migrations")
MIG = "20261001233019_crm_cuentas_pago_motivo_y_rezago.sql"
S3 = "20260925194026_p0xx_pagos_solo_cuenta_contractual.sql"
MARCA = "migracion:rezago-vinculos:20261001"
HUELLA_S3 = "5efb8619e4342763ae77df2ee0bb1f61"
GENERICO = "Sin cuenta de pago — requiere conciliación"


def leer(nombre):
    return io.open(os.path.join(MIGS, nombre), encoding="utf-8").read()


def md5(texto):
    return hashlib.md5(texto.encode("utf-8")).hexdigest()


def cuerpo(texto, nombre):
    ini = texto.index("create or replace function " + nombre + "(")
    a = texto.index("$function$", ini) + len("$function$")
    return texto[a:texto.index("$function$", a)]


mig = leer(MIG)
s3 = leer(S3)
for tag in ("$ensayo_antes$", "$ensayo_fin$", "$mig$"):
    assert tag not in mig, f"la migración contiene el delimitador {tag}"

H = {
    "bloqueo": md5(cuerpo(mig, "private.exigir_cuenta_pago_cronograma")),
    "diagnostico": md5(cuerpo(mig, "private.cuenta_pago_diagnostico")),
    "autorizado": md5(cuerpo(mig, "private.cuentas_pago_motivos_autorizado")),
    "puerta": md5(cuerpo(mig, "crm.cuentas_pago_motivos_fn")),
}
for h in H.values():
    assert mig.count(h) == 2, "la migración no lleva sus propias huellas en preflight y postflight"

# El bloqueo anterior, byte a byte.
i = s3.index("create or replace function private.exigir_cuenta_pago_cronograma()")
j = s3.index("$function$;", s3.index("$function$", i) + 10) + len("$function$;")
BLOQUEO_ANTERIOR = s3[i:j]
assert md5(BLOQUEO_ANTERIOR.split("$function$")[1]) == HUELLA_S3

TRES_FUNCIONES = f"""(values
      ('private.cuenta_pago_diagnostico(uuid[])', '{H["diagnostico"]}'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '{H["autorizado"]}'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '{H["puerta"]}')
    ) as f(firma, huella)"""

# ───────────────────────────── reversas ─────────────────────────────
PRECONDICION_REVERSA = f"""do $precondicion$
declare
  v_huella text;
begin
  -- Se decide con lo que se lee DESPUÉS de tomar los candados: solo vale en READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- El de la migración, o el anterior si el código ya se revirtió.
  if v_huella is null or v_huella not in ('{H["bloqueo"]}', '{HUELLA_S3}') then
    raise exception 'REVERSA: el bloqueo vivo (%) no es el de la migración 20261001233019 ni el anterior; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  if exists (
    select 1
    from {TRES_FUNCIONES}
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REVERSA: alguna función de la migración cambió después; no se toca';
  end if;
end;
$precondicion$;
"""

CODIGO_REVERSA = f"""-- El bloqueo de antes, byte a byte: texto fuente de 20260925194026 (el postflight lo comprueba por md5).
{BLOQUEO_ANTERIOR}
comment on function private.exigir_cuenta_pago_cronograma() is null;

-- Las tres funciones nuevas (la puerta primero). El portal tolera que la puerta no exista: vuelve
-- al texto genérico.
drop function if exists crm.cuentas_pago_motivos_fn(uuid[]);
drop function if exists private.cuentas_pago_motivos_autorizado(uuid[]);
drop function if exists private.cuenta_pago_diagnostico(uuid[]);

do $postflight$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from '{HUELLA_S3}' then
    raise exception 'REVERSA POSTFLIGHT: el bloqueo no volvió al cuerpo anterior';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                  and a.grantee <> p.proowner)
     or (select p.proacl is null from pg_catalog.pg_proc p
         where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure) then
    raise exception 'REVERSA POSTFLIGHT: DEFINER, search_path o EXECUTE del bloqueo no quedaron como antes';
  end if;
  if pg_catalog.to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null then
    raise exception 'REVERSA POSTFLIGHT: quedó alguna función de la migración';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
"""

REVERSA = f"""-- REVERSA COMPLETA de {MIG}: datos y código. GENERADA por generar-derivados.py.
--   · Borra SOLO los vínculos que creó la carga de la migración (marca '{MARCA}'
--     en private.backfill_cuentas_p0xx) y les pone revertida_en. La bitácora (public.audit_log)
--     guarda el borrado. Los vínculos de cargas posteriores (vincular-rezago.sql, otra marca) no se tocan.
--   · Repone el bloqueo anterior y quita las tres funciones nuevas (si el código ya se revirtió
--     con reversa-solo-codigo.sql, esta parte no cambia nada).
-- Se NIEGA, sin cambiar nada, si algún contrato vinculado por la carga ya registró un pago
-- (crm.cuotas_cuenta_pagada), un cambio de cuenta (crm.contrato_cuenta_pago_cambios) o un PDF de
-- contrato (su fotografía lleva la cuenta): desde ese momento el vínculo es una instrucción usada
-- y no se borra. Para volver solo al mensaje anterior sin tocar vínculos: reversa-solo-codigo.sql.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

{PRECONDICION_REVERSA}
do $datos$
declare
  c_marca constant text := '{MARCA}';
  v_usado text;
  v_esperados integer;
  v_borrados integer;
begin
  if pg_catalog.to_regclass('crm.cuotas_cuenta_pagada') is null
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or pg_catalog.to_regclass('private.contrato_pdf_jobs') is null
     or pg_catalog.to_regclass('private.contrato_pdfs') is null then
    raise exception 'REVERSA: faltan las tablas con las que se sabe si un vínculo ya se usó; no se borra nada';
  end if;
  -- El criterio «ya registró un pago» depende de que cada pago selle su cuenta: los dos triggers
  -- del sello, habilitados y colgados de su función. (Que estén así AHORA no prueba que lo
  -- estuvieran siempre: si alguna vez se apagaron, esta reversa no se usa sin revisar los pagos.)
  if pg_catalog.to_regprocedure('private.sellar_cuenta_cuota_pagada()') is null
     or (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = 'public.cronograma_pagos'::regclass
           and t.tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert',
                            'trg_cronograma_pagos_20_sellar_cuenta_update')
           and t.tgfoid = pg_catalog.to_regprocedure('private.sellar_cuenta_cuota_pagada()')
           and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA: los triggers que sellan la cuenta de cada pago no están habilitados; no se puede saber si un vínculo ya se usó';
  end if;

  -- Candados en el orden de un pago: el contrato primero (FOR UPDATE, por id). Un pago en curso
  -- termina antes; uno nuevo espera y, al seguir, ya no encuentra el vínculo y se rechaza.
  perform 1
  from public.contratos ct
  where ct.id in (select b.contrato_id from private.backfill_cuentas_p0xx b
                  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null)
  order by ct.id
  for update;

  select ct.numero_contrato into v_usado
  from private.backfill_cuentas_p0xx b
  join public.contratos ct on ct.id = b.contrato_id
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and (exists (select 1 from crm.cuotas_cuenta_pagada q where q.contrato_id = b.contrato_id)
         or exists (select 1 from crm.contrato_cuenta_pago_cambios c where c.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdf_jobs j where j.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdfs p where p.contrato_id = b.contrato_id))
  order by ct.numero_contrato
  limit 1;
  if v_usado is not null then
    raise exception 'REVERSA: el contrato % ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada. Para volver solo al mensaje anterior usa reversa-solo-codigo.sql', v_usado;
  end if;

  -- Se esperan tantos borrados como vínculos de la carga cuyo contrato sigue existiendo (un
  -- contrato eliminado ya se llevó su vínculo en cascada).
  select pg_catalog.count(*) into v_esperados
  from private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and exists (select 1 from public.contratos ct where ct.id = b.contrato_id);

  delete from crm.contrato_cuentas_pago l
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and l.id = b.fila_id and l.contrato_id = b.contrato_id;
  get diagnostics v_borrados = row_count;
  if v_borrados <> v_esperados then
    raise exception 'REVERSA: se esperaban % vínculos de la carga y se encontraron %; no se borra nada',
      v_esperados, v_borrados;
  end if;

  update private.backfill_cuentas_p0xx
     set revertida_en = pg_catalog.now()
   where tipo = 'vinculo' and marca_actor = c_marca and revertida_en is null;

  raise notice 'REVERSA: % vínculos de la carga borrados', v_borrados;
end;
$datos$;

{CODIGO_REVERSA}"""

REVERSA_CODIGO = f"""-- REVERSA SOLO DEL CÓDIGO de {MIG}. GENERADA por generar-derivados.py.
-- Repone el bloqueo anterior (mensaje único) y quita las tres funciones nuevas. NO toca ningún
-- vínculo: los que creó la carga siguen siendo la cuenta de pago de sus contratos. Es la reversa
-- que sirve cuando ya se registraron pagos con esos vínculos (la completa se niega).
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

{PRECONDICION_REVERSA}
{CODIGO_REVERSA}"""

# ───────────────────────────── carga relanzable ─────────────────────────────
lineas = mig.split("\n")
i_carga = next(i for i, l in enumerate(lineas) if l.startswith("-- ── 4. Carga del rezago"))
i_fin = next(i for i, l in enumerate(lineas) if l.strip() == "$rezago$;")
bloque_carga = "\n".join(lineas[i_carga:i_fin + 1])
LINEA_MARCA = f"  c_marca constant text := '{MARCA}';"
assert bloque_carga.count(LINEA_MARCA) == 1, "no encuentro la línea de la marca en la carga"
bloque_carga = bloque_carga.replace(
    LINEA_MARCA,
    "  -- Cada relanzamiento deja su propia marca (día de Lima): no se confunde con la carga de la migración.\n"
    "  c_marca constant text := 'carga:rezago-vinculos:'\n"
    "    || pg_catalog.to_char(pg_catalog.now() at time zone 'America/Lima', 'YYYYMMDD');")

CARGA = f"""-- VINCULAR EL REZAGO, otra vez. GENERADO por generar-derivados.py: es la carga de
-- {MIG}, sola y sin tocar ninguna función.
--
-- Cuándo: cuando Operaciones registre la cuenta que le faltaba a un contrato del rezago (o retire
-- la que sobraba) y ese contrato pase a tener UNA sola cuenta activa en su moneda. Vincula
-- exactamente esos contratos; a los demás no los toca. Lanzarlo sin nada que vincular no cambia nada.
-- Se niega si el bloqueo o el diagnóstico vivos no son los de la migración: la regla que aplica
-- tiene que ser la que se ensayó.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/vincular-rezago.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  -- La carga decide con lo que lee DESPUÉS de tomar sus candados: solo vale en READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'VINCULAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if (select pg_catalog.count(*)
      from (values
        ('private.exigir_cuenta_pago_cronograma()', '{H["bloqueo"]}'),
        ('private.cuenta_pago_diagnostico(uuid[])', '{H["diagnostico"]}'),
        ('private.cuentas_pago_motivos_autorizado(uuid[])', '{H["autorizado"]}'),
        ('crm.cuentas_pago_motivos_fn(uuid[])', '{H["puerta"]}')
      ) as f(firma, huella)
      join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
      where pg_catalog.md5(p.prosrc) = f.huella) <> 4 then
    raise exception 'VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración 20261001233019; no se toca nada';
  end if;
  if pg_catalog.to_regclass('private.backfill_cuentas_p0xx') is null
     or pg_catalog.to_regclass('private.conciliacion_cuentas_p0xx') is null then
    raise exception 'VINCULAR: faltan las tablas de rastro o de conciliación';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and t.tgname in ('trg_contrato_cuenta_pago_coherente', 'trg_audit_contrato_cuentas_pago')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'VINCULAR: faltan los triggers de coherencia o de bitácora del vínculo';
  end if;
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'VINCULAR: quien lo lanza debe poder leer contratos, vínculos y cuentas sin RLS';
  end if;
end;
$precondicion$;

{bloque_carga}

commit;

-- Constancia del conteo por caso antes y después de ESTA corrida (queda en la salida).
select pg_catalog.current_setting('crm.rezago_vinculos_resultado', true)::jsonb as rezago_vinculos;
"""

# ───────────────────────────── ensayo de producción ─────────────────────────────
i_begin = next(i for i, l in enumerate(lineas) if l.strip() == "begin;")
i_commit = max(i for i, l in enumerate(lineas) if l.strip() == "commit;")
assert sum(1 for l in lineas if l.strip() == "begin;") == 1, "la migración tiene más de un begin; de nivel superior"
assert sum(1 for l in lineas if l.strip() == "commit;") == 1, "la migración tiene más de un commit; de nivel superior"
cuerpo_mig = "\n".join(lineas[i_begin + 1:i_commit])  # sin begin/commit ni la constancia final

# La misma clasificación que private.cuenta_pago_diagnostico, escrita aparte y sin funciones: es
# la segunda opinión del «antes» (si no coincide con la de la carga, el ensayo lo dice).
CENSO_SIN_FUNCIONES = """select case
           when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when cp.id is not null then 'cuenta_no_corresponde'
           when q.en_moneda = 1 then 'una_cuenta'
           when q.en_moneda > 1 then 'varias_cuentas'
           when q.otra_moneda > 0 then 'otra_moneda'
           else 'sin_cuenta'
         end as caso
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  cross join lateral (
    select count(*) filter (where a.moneda = ct.moneda) as en_moneda,
           count(*) filter (where a.moneda <> ct.moneda) as otra_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id and a.activa
  ) q"""

MARCAR_PAGADA = """update public.cronograma_pagos
             set estado = 'pagado',
                 fecha_pago_real = (now() at time zone 'America/Lima')::date,
                 monto_pagado = monto_programado
           where id = v_cuota;"""

ENSAYO = f"""-- ENSAYO EN PRODUCCIÓN, SIN ESCRIBIR, de {MIG}.
-- GENERADO por generar-derivados.py con el archivo real de la migración (md5 {md5(mig)}).
--
-- Corre la migración entera dentro de una transacción que TERMINA SIEMPRE en un error a propósito
-- («ENSAYO_DESHECHO»): no queda nada escrito, tampoco si algo falla antes. El resultado se lee en
-- el texto de ese error:
--   antes_sin_funciones / carga / despues : conteo por caso (el «antes» se cuenta dos veces: con
--                                           la regla nueva y con una consulta aparte)
--   pagos      : una cuota REAL marcada como pagada, por conexión directa, en un contrato de cada
--                caso bloqueado, en cada contrato que la carga vinculó y en uno que ya estaba bien
--   identidad  : sobre un contrato bloqueado, qué texto recibe un gestor de cartera (el detalle)
--                y qué texto recibe un analista (el genérico)
--   veredicto  : PASA (todo se probó y salió como dicta la regla), FALLA (algo salió distinto;
--                ver «fallos») o INCOMPLETO (nada falló, pero algo no se pudo probar; ver
--                «sin_probar»). todo_como_se_esperaba = true solo con PASA.
--   conexion   : con qué usuario de la base corrió (sirve para saber qué es «conexión directa»)
-- Si la propia migración se niega (preflight, un candidato en conciliación, el tope, un candado
-- ocupado), el error que verás es el SUYO y no ENSAYO_DESHECHO; tampoco queda nada escrito.
-- «Nada escrito» son los DATOS: mientras corre toma los mismos candados que la migración (unos
-- segundos), y puede consumir números de secuencia y dejar rastro en los registros del servidor.
-- Después, para convertir el argumento en un hecho: censo-sin-funciones.sql debe dar lo mismo que antes.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $ensayo_antes$
declare
  v jsonb;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{{}}'::jsonb) into v
  from (select c.caso, count(*) as n from (
  {CENSO_SIN_FUNCIONES}
  ) c group by c.caso) s;
  perform set_config('crm.ensayo_rezago_antes', v::text, true);
end;
$ensayo_antes$;

-- ───────────── la migración, tal cual (sin su begin/commit) ─────────────
{cuerpo_mig}
-- ───────────── fin de la migración ─────────────

do $ensayo_fin$
declare
  c_generico constant text := '{GENERICO}';
  v_antes jsonb := current_setting('crm.ensayo_rezago_antes', true)::jsonb;
  v_carga jsonb := current_setting('crm.rezago_vinculos_resultado', true)::jsonb;
  v_despues jsonb;
  v_pagos jsonb := '[]'::jsonb;
  v_identidad jsonb := '[]'::jsonb;
  v_fallos text[] := array[]::text[];
  v_sin_probar text[] := array[]::text[];
  r record;
  v_caso record;
  v_bloqueado record;
  v_quien record;
  v_cuota uuid;
  v_resultado text;
  v_codigo text;
  v_mensaje text;
  v_bien boolean;
  v_probados integer := 0;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{{}}'::jsonb) into v_despues
  from (select d.caso, count(*) as n from private.cuenta_pago_diagnostico() d group by d.caso) s;

  if v_antes is distinct from (v_carga -> 'antes') then
    v_fallos := v_fallos || 'el conteo previo hecho sin funciones no coincide con el de la regla nueva'::text;
  end if;

  -- 1) Pagos por conexión directa (sin usuario de la API: se espera el detalle).
  for r in
    (select distinct on (d.caso) d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'bloqueado'::text as que
     from private.cuenta_pago_diagnostico() d
     where d.caso <> 'ok'
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.caso, d.es_demo, d.numero_contrato)
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'vinculado por la carga'
     from private.backfill_cuentas_p0xx b
     join private.cuenta_pago_diagnostico() d on d.contrato_id = b.contrato_id
     where b.tipo = 'vinculo' and b.marca_actor = '{MARCA}' and b.insertada_en = now())
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'ya estaba bien'
     from private.cuenta_pago_diagnostico() d
     where d.caso = 'ok' and d.estado = 'activo'
       and not exists (select 1 from private.backfill_cuentas_p0xx b
                       where b.tipo = 'vinculo' and b.contrato_id = d.contrato_id and b.insertada_en = now())
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.es_demo desc, d.numero_contrato
     limit 1)
  loop
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = r.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    v_codigo := null;
    v_mensaje := null;
    if v_cuota is null then
      v_resultado := 'sin cuota pendiente que probar';
      v_bien := null;
      v_sin_probar := v_sin_probar
        || format('contrato %s (%s): no tiene ninguna cuota pendiente que probar', r.numero_contrato, r.que);
    else
      begin
        {MARCAR_PAGADA}
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := case when r.caso = 'ok' then v_resultado = 'pagada'
                     else v_resultado = 'bloqueada' and v_codigo = '23514' and v_mensaje = r.mensaje end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('contrato %s (%s, caso %s): %s %s', r.numero_contrato, r.que, r.caso, v_resultado, coalesce(v_mensaje, ''));
      end if;
    end if;
    v_pagos := v_pagos || jsonb_build_object(
      'contrato', r.numero_contrato, 'caso', r.caso, 'que', r.que,
      'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
  end loop;

  -- Cobertura: un ensayo que no pudo probar algo NO es un ensayo que pasó. Cada caso bloqueado
  -- que exista tiene que haberse probado, y también un contrato que ya estaba bien.
  for v_caso in
    select c.caso, c.n
    from (select key as caso, value::text::integer as n from jsonb_each(v_despues)) c
    where c.caso <> 'ok' and c.n > 0
  loop
    if not exists (select 1 from jsonb_array_elements(v_pagos) x
                   where x ->> 'caso' = v_caso.caso and x ->> 'que' = 'bloqueado') then
      v_sin_probar := v_sin_probar
        || format('caso %s: hay %s contratos y ninguno con una cuota pendiente que probar', v_caso.caso, v_caso.n);
    end if;
  end loop;
  if not exists (select 1 from jsonb_array_elements(v_pagos) x where x ->> 'que' = 'ya estaba bien') then
    v_sin_probar := v_sin_probar || 'ningún contrato que ya estaba bien tiene una cuota pendiente que probar'::text;
  end if;

  -- 2) A quién se le dice el detalle. Va AL FINAL: la identidad simulada queda puesta hasta el
  --    error que deshace todo. No cambia de rol: solo los datos de sesión que lee el bloqueo.
  select d.contrato_id, d.numero_contrato, d.caso, d.mensaje into v_bloqueado
  from private.cuenta_pago_diagnostico() d
  where d.caso <> 'ok'
    and exists (select 1 from public.cronograma_pagos cp
                where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
  order by d.es_demo, d.numero_contrato
  limit 1;
  if not found then
    v_sin_probar := v_sin_probar || 'identidad: no hay ningún contrato bloqueado con una cuota pendiente'::text;
  else
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = v_bloqueado.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    for v_quien in
      (select 'gestor de cartera'::text as papel, p.id, true as detalle
       from public.perfiles p
       where p.rol in ('admin', 'superadmin', 'operaciones') and p.activo
         and not exists (select 1 from crm.equipo e where e.perfil_id = p.id and e.activo is false)
       order by p.id limit 1)
      union all
      (select 'analista (no gestor)', p.id, false
       from public.perfiles p
       where p.rol = 'analista' and p.activo
       order by p.id limit 1)
    loop
      v_probados := v_probados + 1;
      perform set_config('request.jwt.claim.sub', v_quien.id::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims',
        jsonb_build_object('sub', v_quien.id, 'role', 'authenticated')::text, true);
      v_codigo := null;
      v_mensaje := null;
      begin
        {MARCAR_PAGADA}
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := v_resultado = 'bloqueada' and v_codigo = '23514'
                and v_mensaje = case when v_quien.detalle then v_bloqueado.mensaje else c_generico end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('identidad %s: %s %s', v_quien.papel, v_resultado, coalesce(v_mensaje, ''));
      end if;
      v_identidad := v_identidad || jsonb_build_object(
        'quien', v_quien.papel, 'contrato', v_bloqueado.numero_contrato, 'caso', v_bloqueado.caso,
        'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
    end loop;
    if v_probados < 2 then
      v_sin_probar := v_sin_probar
        || 'identidad: falta un gestor de cartera vigente o un analista activo con quien probar'::text;
    end if;
  end if;

  raise exception 'ENSAYO_DESHECHO >> %', jsonb_build_object(
    'veredicto', case when cardinality(v_fallos) > 0 then 'FALLA'
                      when cardinality(v_sin_probar) > 0 then 'INCOMPLETO'
                      else 'PASA' end,
    'fallos', to_jsonb(v_fallos), 'sin_probar', to_jsonb(v_sin_probar),
    'conexion', jsonb_build_object('session_user', session_user::text, 'current_user', current_user::text),
    'antes_sin_funciones', v_antes, 'carga', v_carga, 'despues', v_despues,
    'pagos', v_pagos, 'identidad', v_identidad,
    'todo_como_se_esperaba', cardinality(v_fallos) = 0 and cardinality(v_sin_probar) = 0);
end;
$ensayo_fin$;
"""

DERIVADOS = {
    "reversa.sql": REVERSA,
    "reversa-solo-codigo.sql": REVERSA_CODIGO,
    "vincular-rezago.sql": CARGA,
    "ensayo-prod-sin-escribir.sql": ENSAYO,
}

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
    for k, h in H.items():
        print(f"  huella {k}: {h}")

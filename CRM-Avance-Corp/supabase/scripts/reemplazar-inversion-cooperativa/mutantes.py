#!/usr/bin/env python3
"""Mutantes de 20261018053228 (Reemplazar inversión, cooperativas): por cada defensa de la MIGRACIÓN, una versión del texto
que la neutraliza; la batería (probar.sh con MUTANTE_MIGRACION) tiene que tumbarla. Veredicto: MUERTO (probar.sh sale 1),
SOBREVIVE (sale 0: la defensa NO está probada) o ENSAYO (sale 3, o el ancla no aparece exactamente una vez: cuenta como vivo).
Los mutantes de los dos ayudantes del bucket van con su huella del postflight apagada: si no, la huella los mataría sola.

  python3 -I mutantes.py [filtro]
"""
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
MIGRACION = os.path.join(AQUI, '..', '..', 'migrations', '20261018053228_crm_reemplazar_inversion_cooperativa.sql')
PROBAR = os.path.join(AQUI, 'probar.sh')

HUELLA_BUCKET_OFF = ("raise exception 'POSTFLIGHT reemplazar_cooperativa: un ayudante del bucket no quedó como se ensayó';", 'null;')


def off(msg):
    return (f"raise exception '{msg}';", 'null;')


# (nombre, [(antes, después), ...]) — cada «antes» debe aparecer EXACTAMENTE una vez en la migración.
MUTANTES = [
    # ── Puerta ──
    # La puerta, el núcleo y la copia exigen rol (uno es la red del otro): el mutante honesto apaga los tres; un vendedor pasaría.
    ('puerta, núcleo y copia: sin exigir rol',
     [("""  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then""",
       """  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then"""),
      ("""  if v_portal is null and not v_gerencia then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if not v_gerencia then
    raise exception 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead' using errcode = '42501';
  end if;""", ""),
      ("     or p_rol is null or p_rol not in ('gerencia', 'admin', 'superadmin') then", "     then")]),
    # Solo Gerencia: puerta, núcleo y regla del bucket (el admin del portal sin CRM pasaría).
    ('puerta, núcleo y regla del bucket: sin exigir Gerencia',
     [("""  if not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then""",
       """  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then"""),
      ("""  if not v_gerencia then
    raise exception 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead' using errcode = '42501';
  end if;
  if p_cierre is not null""", "  if p_cierre is not null"),
      ("  if not coalesce((v_roles ->> 'gerencia')::boolean, false) or private.membresia_crm_revocada() then\n    return false;", "  if private.membresia_crm_revocada() then\n    return false;")]),
    # (sin mutante de «membresía revocada»: con «solo Gerencia», una membresía revocada ya no es Gerencia y la rechaza el chequeo
    #  anterior; la comprobación queda como red redundante, no como defensa propia)
    ('puerta: sin el mínimo del motivo', [("  if coalesce(length(v_motivo), 0) < 5 then", "  if false then")]),
    ('puerta: sin el máximo del motivo', [("  if length(v_motivo) > 300 then\n    raise exception 'El motivo admite como máximo 300 caracteres' using errcode = '22023';\n  end if;\n  begin\n    return private.reemplazar_inversion_cooperativa",
                                          "  begin\n    return private.reemplazar_inversion_cooperativa")]),
    ('vista previa: sin exigir rol ni Gerencia',
     [("""  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo gerencia puede reemplazar una inversión de cooperativa: es la venta de un lead' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  select * into v_ce from crm.cierres_externos ce where ce.id = p_fuente_id;""",
       """  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  select * into v_ce from crm.cierres_externos ce where ce.id = p_fuente_id;""")]),
    ('vista previa: sin «no reemplazable» por aporte adicional',
     [("                            when not v_ce.es_cierre_inicial then 'Solo se reemplaza la inversión inicial de la cooperativa; un aporte adicional se corrige o se elimina'\n", "")]),
    ('vista previa: sin «plazo vencido»', [("    'plazo_vencido', v_acr.id is not null and v_acr.estado = 'acreditada'\n                     and pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(v_mes),",
                                             "    'plazo_vencido', false,")]),
    # ── Núcleo: lo que no se reemplaza ──
    ('núcleo: admite un p_cierre que no es objeto', [("  if p_cierre is not null and jsonb_typeof(p_cierre) <> 'object' then", "  if false then")]),
    ('núcleo: sin «origen de capital confirmado»', [("  if exists (select 1 from crm.origenes_capital_confirmados o where o.cierre_externo_id = p_fuente and o.activo) then", "  if false then")]),
    ('núcleo: sin «ya respalda otra inversión»', [("    if exists (select 1 from crm.cierres_externos ce2 where ce2.comprobante_objeto_id = v_obj.id) then", "    if false then")]),
    ('núcleo: admite claves ajenas en p_cierre', [("  if exists (select 1 from jsonb_object_keys(p_cierre) k where k not in ('cooperativa', 'fecha_comercial', 'comprobante_ruta')) then", "  if false then")]),
    ('núcleo: sin «solo cooperativas» (0A000)', [("  if v_ctx ->> 'tipo' is distinct from 'cierre_externo' then\n    raise exception 'Esta puerta reemplaza", "  if false then\n    raise exception 'Esta puerta reemplaza")]),
    ('núcleo y copia: sin «movimientos» (motivo no eliminable)', [("  v_no := private.inversion_motivo_no_eliminable('cierre_externo', p_fuente, (v_ctx ->> 'inversion_id')::uuid);\n  if v_no is not null then\n    raise exception '%', v_no using errcode = 'P0409';\n  end if;\n  select * into v_ce",
                                                          "  select * into v_ce"),
      ("  v_no := private.inversion_motivo_no_eliminable('cierre_externo', v_cierre, v_inv);\n  if v_no is not null then raise exception '%', v_no using errcode = 'P0409'; end if;", "")]),
    ('núcleo y copia: sin «venta anulada»', [("  if v_ce.anulado_en is not null or coalesce((v_ctx ->> 'conversion_anulada')::boolean, false) then", "  if false then"),
      ("  if v_ce.anulado_en is not null or (v_es_conversion and coalesce((p_ctx ->> 'conversion_anulada')::boolean, false)) then\n    raise exception 'Una venta anulada no se reemplaza' using errcode = 'P0409';", "  if false then\n    raise exception 'Una venta anulada no se reemplaza' using errcode = 'P0409';")]),
    ('núcleo: sin «solo la inicial»', [("  if not v_ce.es_cierre_inicial then\n    raise exception 'Solo se reemplaza", "  if false then\n    raise exception 'Solo se reemplaza")]),
    ('núcleo: sin «acreditada a otra inversión»', [("    if v_acr.id is not null and (v_acr.fuente_tipo, v_acr.fuente_id) is distinct from ('cierre_externo'::text, p_fuente) then", "    if false then")]),
    ('núcleo: sin validar la cooperativa', [("  if v_e.id is null then\n    raise exception 'La cooperativa indicada no existe", "  if false then\n    raise exception 'La cooperativa indicada no existe")]),
    ('núcleo: sin la moneda admitida', [("  if not (v_ce.moneda = any (coalesce(v_e.monedas, '{}'::text[]))) then", "  if false then")]),
    ('núcleo: sin «fecha futura»', [("  if v_fecha > v_hoy then", "  if false then")]),
    ('núcleo: sin la carpeta de esta inversión en el comprobante (un objeto válido en otra carpeta entra)',
     [("    if (v_ruta ~ ('^' || v_persona::text || '/reemplazo-' || p_fuente::text || '/[A-Za-z0-9_-]+\\.(pdf|jpg|jpeg|png)$')) is not true then", "    if false then")]),
    ('núcleo: la carpeta sin exigir ESTA inversión (otra carpeta de reemplazo de la misma persona entra)',
     [("    if (v_ruta ~ ('^' || v_persona::text || '/reemplazo-' || p_fuente::text || '/[A-Za-z0-9_-]+\\.(pdf|jpg|jpeg|png)$')) is not true then",
       "    if (v_ruta ~ ('^' || v_persona::text || '/reemplazo-[a-f0-9-]{36}/[A-Za-z0-9_-]+\\.(pdf|jpg|jpeg|png)$')) is not true then")]),
    ('núcleo: la carpeta se compara con la identidad sin canonizar',
     [("    if (v_ruta ~ ('^' || v_persona::text || '/reemplazo-' || p_fuente::text || '/[A-Za-z0-9_-]+\\.(pdf|jpg|jpeg|png)$')) is not true then",
       "    if (v_ruta ~ ('^' || v_ce.inversionista_id::text || '/reemplazo-' || p_fuente::text || '/[A-Za-z0-9_-]+\\.(pdf|jpg|jpeg|png)$')) is not true then")]),
    ('núcleo: sin validar el objeto del comprobante (existencia, tamaño y mimetype)',
     [("""    if v_obj.id is null or coalesce((v_obj.metadata ->> 'size')::bigint, 0) not between 1 and 10485760
       or coalesce(v_obj.metadata ->> 'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then""", "    if false then")]),
    ('núcleo: el objeto del comprobante sin el mimetype',
     [("       or coalesce(v_obj.metadata ->> 'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then", "       then")]),
    ('núcleo: sin «nada que reemplazar»', [("  if v_coop = v_ce.cooperativa and v_fecha is not distinct from v_ce.fecha_comercial and v_obj_id is not distinct from v_ce.comprobante_objeto_id then", "  if false then")]),
    ('núcleo: sin recalcular el vencimiento', [("    v_vence := private.coopac_validar_condiciones_base(v_fecha, v_ce.plazo_meses, v_ce.tasa_anual, v_ce.base_plazo);", "    v_vence := v_ce.vence_en;")]),
    ('núcleo: sin los sellos', [("  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])\n     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= v_periodos[1]) then", "  if false then")]),
    ('núcleo: sin los sellos ni el detector del mes sellado de la venta (uno es la red del otro)',
     [("  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])\n     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= v_periodos[1]) then", "  if false then"),
      ("    if v_venta.p_desconocido or v_venta.p_sellado then", "    if false then")]),
    ('núcleo: sin el plazo de carga', [("  if v_mueve_venta and v_acr.estado = 'acreditada'\n     and pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(pg_catalog.date_trunc('month', v_fecha::timestamp)::date) then", "  if false then")]),
    ('núcleo: la copia apunta a OTRO id (no al de la nueva)', [("  v_aud := private.registrar_inversion_reemplazada_cooperativa(v_ctx, p_actor, v_rol, p_motivo, v_nuevo,", "  v_aud := private.registrar_inversion_reemplazada_cooperativa(v_ctx, p_actor, v_rol, p_motivo, gen_random_uuid(),")]),
    ('núcleo: sin el depósito reclamado', [("    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)\n    values (upper(btrim(v_ce.numero_transaccion)), v_nuevo, p_actor);\n", "")]),
    ('núcleo: la inversión nueva sin la marca de primera conversión', [("  v_inv := private.inversion_vincular_fuente(v_persona, null, v_nuevo, p_actor, coalesce(v_primera, false));", "  v_inv := private.inversion_vincular_fuente(v_persona, null, v_nuevo, p_actor, false);")]),
    ('núcleo: sin los cotitulares', [("  for v_t in select (x ->> 'inversionista_id')::uuid as inversionista_id, x ->> 'rol' as rol from jsonb_array_elements(v_titulares) x loop", "  for v_t in select (x ->> 'inversionista_id')::uuid as inversionista_id, x ->> 'rol' as rol from jsonb_array_elements('[]'::jsonb) x loop")]),
    ('núcleo: sin el evento «registro»', [("  insert into crm.inversion_eventos (inversion_id, tipo, motivo, creado_por)\n  values (v_inv, 'registro', left('Reemplazo de inversión: ' || p_motivo, 300), p_actor);\n", "")]),
    ('núcleo: sin el invariante de la venta', [("    if v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'cierre_externo'", "    if false and (v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'cierre_externo'"),
                                              ("       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha::timestamp)::date then\n      raise exception using errcode = 'P0409',\n        message = case when v_acr2.estado = 'fuera_de_plazo'",
                                               "       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha::timestamp)::date) then\n      raise exception using errcode = 'P0409',\n        message = case when v_acr2.estado = 'fuera_de_plazo'")]),
    ('núcleo: idempotencia sin comparar los datos', [("      if v_previo.snapshot #>> '{reemplazo,huella_pedido}' is distinct from v_huella_pedido then", "      if false then")]),
    ('núcleo: la fecha nueva no llega a la fila', [("      v_ce.inversionista_id, true, v_fecha, v_fecha, v_obj_id, v_ce.plazo_meses, v_ce.tasa_anual, v_ce.base_plazo);", "      v_ce.inversionista_id, true, v_ce.fecha_comercial, v_ce.fecha_comercial, v_obj_id, v_ce.plazo_meses, v_ce.tasa_anual, v_ce.base_plazo);")]),
    # ── La copia y el borrado ──
    ('copia: conversion_anulada verdadero', [("    v_es_conversion, false, null, p_motivo, p_actor, p_rol,", "    v_es_conversion, v_es_conversion, null, p_motivo, p_actor, p_rol,")]),
    # (sin mutante del rol de la copia: con «solo Gerencia» el rol registrado es siempre 'gerencia')
    # ── El bucket (huella apagada) ──
    ('bucket: sin la rama de reemplazo en la política de subida',
     [("  if p_ruta ~ ''^[a-f0-9-]{36}/reemplazo-'' then return private.f4_comprobante_reemplazo_autorizado(p_ruta); end if;\n", ""), HUELLA_BUCKET_OFF]),
    ('bucket: la regla de reemplazo sin exigir Gerencia ni membresía',
     [("  if not coalesce((v_roles ->> 'gerencia')::boolean, false) or private.membresia_crm_revocada() then\n    return false;", "  if false then\n    return false;")]),
    ('bucket: sin la rama de las copias en la visibilidad (huella apagada)',
     [("    where p_ruta ~ '^[a-f0-9-]{36}/reemplazo-' and e.fuente_tipo = 'cierre_externo' and e.reemplazada_por is not null\n", "    where false and e.fuente_tipo = 'cierre_externo' and e.reemplazada_por is not null\n"), HUELLA_BUCKET_OFF]),
    ('bucket: la regla de reemplazo sin la persona ni la vigencia',
     [("                 where ce.id = v_cierre and ce.anulado_en is null and ce.es_cierre_inicial\n                   and private.inversionista_canonica(ce.inversionista_id) = v_persona);", "                 where ce.id = v_cierre);")]),
    ('bucket: sin la rama de reemplazo en la visibilidad',
     [("    where p_ruta ~ '^[a-f0-9-]{36}/reemplazo-' and o.bucket_id = 'f4-comprobantes' and o.name = p_ruta and (", "    where false and ("), HUELLA_BUCKET_OFF]),
    ('bucket: la visibilidad del reemplazo sin la regla del responsable',
     [("""      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
    )
  ) or exists (
    -- 18/10/2026: el comprobante de una inversión ya reemplazada""", """      true
    )
  ) or exists (
    -- 18/10/2026: el comprobante de una inversión ya reemplazada"""), HUELLA_BUCKET_OFF]),
]


def main():
    texto = open(MIGRACION, encoding='utf-8').read()
    filtro = sys.argv[1] if len(sys.argv) > 1 else None
    seleccion = [m for m in MUTANTES if not filtro or filtro in m[0]]
    vivos = 0
    for nombre, cambios in seleccion:
        mutado = texto
        ancla_mal = None
        for antes, despues in cambios:
            if mutado.count(antes) != 1:
                ancla_mal = antes
                break
            mutado = mutado.replace(antes, despues)
        if ancla_mal is not None:
            print(f'  ENSAYO     {nombre}: el ancla no aparece exactamente una vez → {ancla_mal[:80]!r}')
            vivos += 1
            continue
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8') as f:
            f.write(mutado)
            ruta = f.name
        try:
            r = subprocess.run(['bash', PROBAR], env={**os.environ, 'MUTANTE_MIGRACION': ruta}, capture_output=True, text=True)
        finally:
            os.unlink(ruta)
        salida = (r.stdout + r.stderr).strip().splitlines()
        causa = salida[-1] if salida else ''
        if r.returncode == 1:
            print(f'  MUERTO     {nombre}\n             ← {causa}')
        elif r.returncode == 0:
            print(f'  SOBREVIVE  {nombre}')
            vivos += 1
        else:
            print(f'  ENSAYO     {nombre} (probar.sh {r.returncode}) → {causa}')
            vivos += 1
    print(f'{len(seleccion) - vivos}/{len(seleccion)} mutantes muertos')
    sys.exit(1 if vivos else 0)


if __name__ == '__main__':
    main()

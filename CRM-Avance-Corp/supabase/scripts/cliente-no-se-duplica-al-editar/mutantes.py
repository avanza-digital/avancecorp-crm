#!/usr/bin/env python3
"""Catálogo de MUTANTES del ensayo del bloque 2.8 (lo usa mutantes.sh; no toca la base).

Cada mutante rompe UNA defensa de la migración DESPUÉS de instalarla y declara qué casos del oráculo (`pruebas.sql`) tienen que
nombrar su fallo («FALLO <caso>»). Los de CUERPO cambian un fragmento del cuerpo vivo (pg_get_functiondef) de la pieza, el núcleo o
el disparador; cada fragmento tiene que aparecer EXACTAMENTE las veces declaradas o el mutante se niega («MUTANTE NO APLICABLE»): si
la migración cambia, no muta otra cosa sin que nadie se entere. Los de CATÁLOGO son SQL libre (ficha, permisos, disparador de tabla).

Uso:  python3 -I mutantes.py lista                  → una línea por mutante: id|descripción|caso1;caso2;…
      python3 -I mutantes.py sql <id> <archivo.sql>  → escribe el SQL que instala ese mutante
"""
import sys

P = 'private.juicio_cliente_convertido(text,text,text,uuid)'
N = 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'
D = 'private.trg_leads_disponibilidad_atomica()'

# ── Fragmentos vigentes (los de la migración, tal como los devuelve pg_get_functiondef) ─────────────────────────────────
WHERE_TEL = "    and (l.telefono = v_tel or l.telefono_alternativo = v_tel or l.telefono = v_alt or l.telefono_alternativo = v_alt)\n"
GRADO = "  order by case when l.telefono = v_tel then 1 when l.telefono_alternativo = v_tel then 2 when l.telefono = v_alt then 3 else 4 end,\n"
ORDEN_TEL = "           (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id\n  limit 1;\n  -- 2."
ORDEN_DNI = "    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id\n    limit 1;\n  end if;\n"
DNI_BLOQUE = """  -- 2. Si ningún teléfono casa, el DNI (D-27), con la misma prioridad.
  if not found and v_dni is not null then
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_c
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.id is distinct from p_excluir_lead_id
      and l.dni = v_dni
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
  end if;
"""
EXCLUIR = "and l.id is distinct from p_excluir_lead_id\n"
ETAPA = "where l.etapa = 'convertido'\n"
CON_PERSONA = "  if v_c.inversionista_id is not null then\n"
RESPALDO = ("    return coalesce(v_juicio, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', "
            "'via', 'identidad'));\n")
SIN_PERSONA = "  return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_c.tenedor, 'sin asesor asignado'));\n"

LLAMADA_N = "    v_convertido := private.juicio_cliente_convertido(p_telefono, v_tecleado ->> 'telefono_alternativo', p_dni, null);\n"
GUARDA_N = "  if not v_reintento then\n    v_convertido := private.juicio_cliente_convertido("
REGLA_N = """  if not v_reintento then
    v_convertido := private.juicio_cliente_convertido(p_telefono, v_tecleado ->> 'telefono_alternativo', p_dni, null);
    if v_convertido is not null then
      return v_convertido;
    end if;
  end if;

  <<rama>>
"""

D_UPDATE = """    v_cliente := private.juicio_cliente_convertido(
      case when new.telefono is distinct from old.telefono then new.telefono end,
      case when new.telefono_alternativo is distinct from old.telefono_alternativo then new.telefono_alternativo end,
      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
  end if;
"""
D_CAMBIOS = """      case when new.telefono is distinct from old.telefono then new.telefono end,
      case when new.telefono_alternativo is distinct from old.telefono_alternativo then new.telefono_alternativo end,
      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
"""
D_ARG_ALT = "      case when new.telefono_alternativo is distinct from old.telefono_alternativo then new.telefono_alternativo end,\n"
D_ARG_DNI = "      case when not v_priv and new.dni is distinct from old.dni then new.dni end,\n"
D_RAISE_ID = """    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
  end if;
"""
D_ALT = """      if v_actor is not null
         and new.telefono_alternativo is distinct from old.telefono_alternativo then
        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
          if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
            raise exception using errcode = '42501', message = 'Acceso CRM revocado';
          end if;
          raise exception using
            errcode = 'P0481',
            message = 'Contacto no disponible',
            detail = v_cliente::text;
        end if;
      end if;
      return new;
    end if;
"""
D_ALT_COND = """      if v_actor is not null
         and new.telefono_alternativo is distinct from old.telefono_alternativo then
        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
"""
D_ALT_LLAMADA = "        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);\n"
D_ALT_ROL = """          v_rol := private.rol_crm(v_actor);
          if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
            raise exception using errcode = '42501', message = 'Acceso CRM revocado';
          end if;
          raise exception using
            errcode = 'P0481',
"""
# Ronda 3: el alternativo SIN VALIDAR (la cruda) y la salida de la corrección de documento.
D_CRUDA_UPDATE = """    if v_actor is not null and new.telefono_alternativo_crudo is not null
       and new.telefono_alternativo_crudo is distinct from old.telefono_alternativo_crudo then
      raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
    end if;
"""
D_CRUDA_INSERT = """  if new.telefono_alternativo_crudo is not null then
    raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
  end if;
"""
D_F2B = """       and new.telefono_alternativo is not distinct from old.telefono_alternativo
       and new.telefono_alternativo_crudo is not distinct from old.telefono_alternativo_crudo then
      return new;
"""
D_INSERT = """  if not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
    v_cliente := private.juicio_cliente_convertido(new.telefono, new.telefono_alternativo, new.dni, null);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
  end if;
"""
D_INSERT_EXCL = "  if not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then\n    v_cliente :="
D_INSERT_SIN_SESION = "  if v_actor is null then\n    return new;\n  end if;\n"
D_ROL_UPDATE = """    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD"""
D_DETALLE = """        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
  end if;
"""
D_CODIGO = """      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
"""
COMPROBACION_UPDATE = D_UPDATE[: D_UPDATE.index("    return new;\n")]
# Ronda 4 (auditor P3-4): los candados del alternativo, con la misma clave que el teléfono principal.
D_CANDADO_UPDATE = "      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],\n      array[old.dni, new.dni]\n"
D_CANDADO_INSERT = "  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);\n"
# Ronda 4 (Codex r2): E8l estricto con la migración (la pieza recorta el alternativo tecleado).
P_ALT_BTRIM = "  v_alt text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');\n"
# Ronda 4 (Codex R2-F2): un enlace a OTRA persona que la comprobación de la ronda 3 (cualquier inversionista_id no nulo) dejaba
# pasar. Un disparador de ensayo que, cuando la persona enlazada tiene un PASAPORTE, enlaza el lead a otra persona (nueva, sin leads:
# así nada más se queja y solo la correspondencia lead ↔ persona ↔ identificador de E8g2 lo puede ver).
ME5_SQL = """create function private.ensayo_mutante_me5() returns trigger language plpgsql as $m$
begin
  if new.inversionista_id is not null and new.inversionista_id is distinct from old.inversionista_id
     and exists (select 1 from crm.inversionista_identificadores d
                  where d.inversionista_id = new.inversionista_id and d.tipo_documento = 'PASAPORTE') then
    new.inversionista_id := private.inversionista_resolver('DNI', '70289998', true, 'ensayo-mutante-ME5');
  end if;
  return new;
end
$m$;
create trigger zzzzz_ensayo_mutante_me5 before update on crm.leads for each row execute function private.ensayo_mutante_me5();"""

# id → (descripción, [ (firma, vigente, mutado, veces), … ] | 'SQL libre', [casos que deben nombrar su fallo])
MUTANTES = [
  # ── La pieza: el alternativo en cada dirección ──
  ('MP1', 'pieza: el alternativo TECLEADO no cuenta',
   [(P, WHERE_TEL, "    and (l.telefono = v_tel or l.telefono_alternativo = v_tel)\n", 1)], ['E3a-', 'E3b-', 'E5-', 'A1-', 'A3-', 'I2-']),
  ('MP2', 'pieza: el alternativo DEL CLIENTE no cuenta',
   [(P, WHERE_TEL, "    and (l.telefono = v_tel or l.telefono = v_alt)\n", 1)], ['E4-', 'E5-', 'A2-', 'A3-', 'I3-']),
  ('MP3', 'pieza: sin la dirección «lo tecleado como principal contra el alternativo del cliente»',
   [(P, WHERE_TEL, "    and (l.telefono = v_tel or l.telefono = v_alt or l.telefono_alternativo = v_alt)\n", 1)], ['E4-', 'A2-', 'I3-']),
  ('MP4', 'pieza: sin la dirección «el alternativo tecleado contra el principal del cliente»',
   [(P, WHERE_TEL, "    and (l.telefono = v_tel or l.telefono_alternativo = v_tel or l.telefono_alternativo = v_alt)\n", 1)], ['E3a-', 'E3b-', 'A1-', 'I2-']),
  ('MP5', 'pieza: sin «alternativo contra alternativo»',
   [(P, WHERE_TEL, "    and (l.telefono = v_tel or l.telefono_alternativo = v_tel or l.telefono = v_alt)\n", 1)], ['E5-', 'A3-']),
  # ── La pieza: el orden entre teléfonos (grados) ──
  ('MP6', 'pieza: el alternativo del cliente antes que su principal (grados 1↔2)',
   [(P, GRADO, "  order by case when l.telefono_alternativo = v_tel then 1 when l.telefono = v_tel then 2 when l.telefono = v_alt then 3 else 4 end,\n", 1)], ['E7a-']),
  ('MP7', 'pieza: el alternativo tecleado antes que lo tecleado como principal (grados 2↔3)',
   [(P, GRADO, "  order by case when l.telefono = v_tel then 1 when l.telefono = v_alt then 2 when l.telefono_alternativo = v_tel then 3 else 4 end,\n", 1)], ['E7b-']),
  ('MP8', 'pieza: el alternativo tecleado, contra el alternativo antes que contra el principal (grados 3↔4)',
   [(P, GRADO, "  order by case when l.telefono = v_tel then 1 when l.telefono_alternativo = v_tel then 2 when l.telefono_alternativo = v_alt then 3 else 4 end,\n", 1)], ['E7c-']),
  ('MP9', 'pieza: prioridad plana entre teléfonos (sin grados)',
   [(P, GRADO, "  order by\n", 1)], ['E7a-', 'E7b-', 'E7c-']),
  # ── La pieza: la prioridad entre varios convertidos ──
  ('MP10', 'pieza, teléfono: el enlazado a persona deja de ir primero',
   [(P, ORDEN_TEL, ORDEN_TEL.replace('(l.inversionista_id is not null) desc', '(l.inversionista_id is not null) asc'), 1)], ['E7d-']),
  ('MP11', 'pieza, teléfono: el retirado antes que el activo',
   [(P, ORDEN_TEL, ORDEN_TEL.replace('l.activo desc', 'l.activo asc'), 1)], ['E7e-']),
  ('MP12', 'pieza, teléfono: el convertido más antiguo primero',
   [(P, ORDEN_TEL, ORDEN_TEL.replace('l.convertido_en desc nulls last', 'l.convertido_en asc nulls last'), 1)], ['E7f-']),
  ('MP13', 'pieza, teléfono: los convertidos sin fecha primero (nulls first)',
   [(P, ORDEN_TEL, ORDEN_TEL.replace('l.convertido_en desc nulls last', 'l.convertido_en desc nulls first'), 1)], ['E7g-']),
  ('MP14', 'pieza, teléfono: sin el criterio de la fecha (desempata el id)',
   [(P, ORDEN_TEL, ORDEN_TEL.replace(' l.convertido_en desc nulls last,', ''), 1)], ['E7f-', 'E7g-']),
  ('MP15', 'pieza, DNI: el enlazado a persona deja de ir primero',
   [(P, ORDEN_DNI, ORDEN_DNI.replace('(l.inversionista_id is not null) desc', '(l.inversionista_id is not null) asc'), 1)], ['E7j-']),
  ('MP16', 'pieza, DNI: el retirado antes que el activo',
   [(P, ORDEN_DNI, ORDEN_DNI.replace('l.activo desc', 'l.activo asc'), 1)], ['E7h-']),
  ('MP17', 'pieza, DNI: el convertido más antiguo primero',
   [(P, ORDEN_DNI, ORDEN_DNI.replace('l.convertido_en desc nulls last', 'l.convertido_en asc nulls last'), 1)], ['E7i-']),
  ('MP18', 'pieza, DNI: los convertidos sin fecha primero (nulls first)',
   [(P, ORDEN_DNI, ORDEN_DNI.replace('l.convertido_en desc nulls last', 'l.convertido_en desc nulls first'), 1)], ['E7k-']),
  ('MP19', 'pieza, DNI: sin el criterio de la fecha (desempata el id)',
   [(P, ORDEN_DNI, ORDEN_DNI.replace(' l.convertido_en desc nulls last,', ''), 1)], ['E7i-', 'E7k-']),
  # ── La pieza: precedencia, DNI, exclusión, formato, juicio ──
  ('MP20', 'pieza: el teléfono deja de mandar cuando también hay DNI',
   [(P, WHERE_TEL, WHERE_TEL + "    and v_dni is null\n", 1)], ['E7l-', 'A6-']),
  ('MP21', 'pieza: la regla del DNI quitada',
   [(P, DNI_BLOQUE, "", 1)], ['E2b-', 'E2c-', 'E2d-', 'I4-']),
  ('MP22', 'pieza: no excluye al lead que se edita',
   [(P, EXCLUIR, "", 2)], ['E6f2-']),
  ('MP23', 'pieza: el «sin persona» responde con via (otro formato)',
   [(P, SIN_PERSONA, SIN_PERSONA.replace("'sin asesor asignado'))", "'sin asesor asignado'), 'via', 'identidad')"), 1)], ['E1c-']),
  ('MP24', 'pieza: el «sin persona» no nombra al dueño de la ficha',
   [(P, SIN_PERSONA, "  return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado');\n", 1)], ['E1c-']),
  ('MP25', 'pieza: sin el respaldo de D-21 cuando el juicio no dice nada',
   [(P, RESPALDO, "    return v_juicio;\n", 1)], ['E1h-']),
  ('MP26', 'pieza: no juzga a la persona (todo convertido como «sin persona»)',
   [(P, CON_PERSONA, "  if false then\n", 1)], ['E1g-', 'E1a-']),
  ('MP27', 'pieza: solo mira convertidos ACTIVOS',
   [(P, ETAPA, "where l.etapa = 'convertido' and l.activo\n", 2)], ['E1b-', 'E1d-', 'E2d-']),
  ('MP28', 'pieza: solo mira convertidos RETIRADOS',
   [(P, ETAPA, "where l.etapa = 'convertido' and not l.activo\n", 2)], ['E1a-', 'E1c-']),
  # ── El núcleo del alta ──
  ('MN1', 'núcleo: no le pasa el alternativo tecleado a la pieza',
   [(N, LLAMADA_N, LLAMADA_N.replace("v_tecleado ->> 'telefono_alternativo'", 'null'), 1)], ['A1-', 'A3-']),
  ('MN2', 'núcleo: la regla 1b quitada (el alta deja que el INSERT llegue al disparador)',
   [(N, REGLA_N, "  <<rama>>\n", 1)], ['A5-', 'A1-']),
  ('MN3', 'núcleo: la regla se aplica también al reintento del 2.4',
   [(N, GUARDA_N, GUARDA_N.replace('if not v_reintento then', 'if true then'), 1)], ['R1-']),
  # ── El disparador ──
  ('MD1', 'disparador: sin la regla del UPDATE que cambia teléfono o DNI',
   [(D, D_UPDATE, "    return new;\n  end if;\n", 1)], ['E1a-', 'E2c-', 'E4-', 'E7a-']),
  ('MD2', 'disparador: sin la regla del UPDATE que solo cambia el alternativo',
   [(D, D_ALT, "      return new;\n    end if;\n", 1)], ['E3a-', 'E3b-', 'E5-']),
  ('MD3', 'disparador de tabla: telefono_alternativo fuera de su lista de columnas',
   'create or replace trigger trg_leads_00_disponibilidad_update before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte, '
   'telefono_alternativo_crudo on crm.leads for each row execute function private.trg_leads_disponibilidad_atomica();', ['E3a-', 'E3b-', 'E5-', 'E3c-']),
  ('MD4', 'disparador: sin la regla del INSERT con sesión',
   [(D, D_INSERT, "", 1)], ['I1-', 'I2-', 'I3-', 'I4-']),
  ('MD5', 'disparador: la regla del INSERT juzga también el contacto dormido de la carga de bases',
   [(D, D_INSERT_EXCL, "  if true then\n    v_cliente :=", 1)], ['B1-']),
  ('MD6a', 'disparador: la regla del alternativo juzga también sin sesión',
   [(D, D_ALT_COND, D_ALT_COND.replace('      if v_actor is not null\n', '      if true\n'), 1)], ['S3-']),
  ('MD6b', 'disparador: el INSERT sin sesión también se juzga',
   [(D, D_INSERT_SIN_SESION, """  if v_actor is null then
    if private.juicio_cliente_convertido(new.telefono, new.telefono_alternativo, new.dni, null) is not null then
      raise exception using errcode = 'P0481', message = 'Contacto no disponible';
    end if;
    return new;
  end if;
""", 1)], ['S1-']),
  ('MD7', 'disparador: juzga la combinación entera del lead, no solo lo que la edición pone',
   [(D, D_CAMBIOS, "      new.telefono, new.telefono_alternativo, new.dni,\n      old.id);\n", 1)], ['E6b3-']),
  ('MD8', 'disparador: juzga cualquier edición que pase por él (también las que no cambian teléfono, alternativo ni DNI)',
   [(D, D_ALT_COND, """      if v_actor is not null then
        v_cliente := private.juicio_cliente_convertido(new.telefono, new.telefono_alternativo, new.dni, old.id);
""", 1)], ['E6b2-']),
  ('MD9', 'disparador: la regla va antes de los vetos y del verificador (se adelanta a los veredictos de hoy)',
   [(D, D_UPDATE, "    return new;\n  end if;\n", 1),
    (D, D_ROL_UPDATE, D_ROL_UPDATE.replace("    end if;\n\n    -- Excluir OLD", "    end if;\n" + COMPROBACION_UPDATE + "\n    -- Excluir OLD"), 1)],
   ['E6e-', 'E6d2-']),
  ('MD10', 'disparador: el alternativo sin comprobar el rol (quien no puede ve el veredicto)',
   [(D, D_ALT_ROL, "          raise exception using\n            errcode = 'P0481',\n", 1)], ['E3c-', 'E3d-']),
  ('MD12', 'disparador: no excluye al lead que se edita',
   [(D, D_CAMBIOS, D_CAMBIOS.replace('      old.id);\n', '      null);\n'), 1)], ['E6f2-']),
  ('MD13', 'disparador: el veredicto no viaja en el detalle',
   [(D, D_DETALLE, D_DETALLE.replace("        message = 'Contacto no disponible',\n        detail = v_cliente::text;\n",
                                       "        message = 'Contacto no disponible';\n"), 1)], ['E1a-']),
  ('MD14', 'disparador: otro código de error (no el P0481 de hoy)',
   [(D, D_CODIGO, D_CODIGO.replace("errcode = 'P0481'", "errcode = 'P0409'"), 1)], ['E1a-']),
  # ── Ronda 3 · la cruda (auditor F1, Codex F1): lógica y lista de columnas por separado ──
  ('MF1', 'disparador: sin la comprobación de la cruda en el UPDATE (lógica)',
   [(D, D_CRUDA_UPDATE, "", 1)], ['F1-', 'F1b-', 'F2-', 'F8-', 'F7u1-']),
  ('MF2', 'disparador de tabla: telefono_alternativo_crudo fuera de su lista de columnas (la lógica intacta)',
   'create or replace trigger trg_leads_00_disponibilidad_update before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte, '
   'telefono_alternativo on crm.leads for each row execute function private.trg_leads_disponibilidad_atomica();', ['F1-', 'F2-', 'F7u1-']),
  ('MF3', 'disparador: sin la comprobación de la cruda en el INSERT',
   [(D, D_CRUDA_INSERT, "", 1)], ['F5-', 'F7i1-']),
  ('MF4', 'disparador: la comprobación de la cruda en el UPDATE también sin sesión (rompe la importación y lo que corre sin usuario)',
   [(D, D_CRUDA_UPDATE, D_CRUDA_UPDATE.replace('    if v_actor is not null and new.telefono_alternativo_crudo is not null\n',
                                               '    if new.telefono_alternativo_crudo is not null\n'), 1)], ['F6a-']),
  ('MF4b', 'disparador: la comprobación de la cruda en el INSERT también sin sesión (el importador no podría escribirla)',
   [(D, D_CRUDA_INSERT, "", 1), (D, D_INSERT_SIN_SESION, D_CRUDA_INSERT + D_INSERT_SIN_SESION, 1)], ['F6b-']),
  ('MF5', 'disparador: con sesión, la cruda tampoco se puede BORRAR',
   [(D, D_CRUDA_UPDATE, D_CRUDA_UPDATE.replace('if v_actor is not null and new.telefono_alternativo_crudo is not null\n       and ',
                                               'if v_actor is not null\n       and '), 1)], ['F4-', 'F4b-']),
  ('MF6', 'disparador: con sesión, la cruda heredada tampoco se puede CONSERVAR',
   [(D, D_CRUDA_UPDATE, D_CRUDA_UPDATE.replace('\n       and new.telefono_alternativo_crudo is distinct from old.telefono_alternativo_crudo then\n',
                                               ' then\n'), 1)], ['F3a-', 'F3b-']),
  # ── Ronda 3 · la válvula (auditor F3, Codex F3) ──
  ('MV1', 'disparador: reintroduce la exclusión COMPLETA bajo la válvula privilegiada (las dos ramas)',
   [(D, D_ALT_COND, D_ALT_COND.replace('      if v_actor is not null\n', '      if v_actor is not null and not v_priv\n'), 1),
    (D, D_RAISE_ID, D_RAISE_ID.replace('    if v_cliente is not null then\n', '    if v_cliente is not null and not v_priv then\n'), 1)],
   ['V1-', 'V2-', 'V5-', 'V6-']),
  ('MV1a', 'disparador: bajo la válvula privilegiada no se juzga la rama con cambio de teléfono o DNI',
   [(D, D_RAISE_ID, D_RAISE_ID.replace('    if v_cliente is not null then\n', '    if v_cliente is not null and not v_priv then\n'), 1)],
   ['V1-', 'V5-', 'V6-']),
  ('MV1b', 'disparador: bajo la válvula privilegiada no se juzga la rama que solo cambia el alternativo',
   [(D, D_ALT_COND, D_ALT_COND.replace('      if v_actor is not null\n', '      if v_actor is not null and not v_priv\n'), 1)], ['V2-']),
  ('MV2', 'disparador: bajo la válvula privilegiada también se juzga el DNI (D-38 aún no decidida)',
   [(D, D_ARG_DNI, "      case when new.dni is distinct from old.dni then new.dni end,\n", 1)], ['P1-']),
  ('MV3', 'disparador: la salida de la corrección de documento sin exigir alternativo y cruda intactos (la de la ronda 2)',
   [(D, D_F2B, "       then\n      return new;\n", 1)], ['V5-']),
  # ── Ronda 3 · huecos de la edición ──
  ('ME1', 'disparador: la rama con cambio de teléfono o DNI no le pasa el alternativo a la pieza',
   [(D, D_ARG_ALT, "      null,\n", 1)], ['E8a-']),
  ('ME2', 'pieza, teléfono: el desempate final por id al revés',
   [(P, ORDEN_TEL, ORDEN_TEL.replace('l.id\n  limit 1;', 'l.id desc\n  limit 1;'), 1)], ['E8b-']),
  ('ME3', 'pieza, DNI: el desempate final por id al revés',
   [(P, ORDEN_DNI, ORDEN_DNI.replace('l.id\n    limit 1;', 'l.id desc\n    limit 1;'), 1)], ['E8c-']),
  ('ME4', 'disparador: la rama del alternativo no excluye al lead que se edita',
   [(D, D_ALT_LLAMADA, D_ALT_LLAMADA.replace('null, old.id);', 'null, null);'), 1)], ['E8d-']),
  # ── Ronda 4 · los candados del alternativo (auditor P3-4) ──
  ('MK1', 'disparador: sin el alternativo en el candado del UPDATE (la carrera del alternativo vuelve)',
   [(D, D_CANDADO_UPDATE, "      array[old.telefono, new.telefono],\n      array[old.dni, new.dni]\n", 1)],
   ['K1-', 'K2-', 'K3-', 'K4-', 'K5-', 'K7-']),
  ('MK2', 'disparador: el alternativo con OTRA clave (en la lista del DNI: ya no espera a quien pone ese número como teléfono)',
   [(D, D_CANDADO_UPDATE, "      array[old.telefono, new.telefono],\n      array[old.dni, new.dni, old.telefono_alternativo, new.telefono_alternativo]\n", 1),
    (D, D_CANDADO_INSERT, "  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni, new.telefono_alternativo]);\n", 1)],
   ['K1-', 'K2-', 'K6-', 'K7-']),
  ('MK3', 'disparador: sin el alternativo en el candado del INSERT',
   [(D, D_CANDADO_INSERT, "  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);\n", 1)], ['K6-']),
  ('MK4', 'disparador: en el candado del UPDATE solo el alternativo NUEVO (no el viejo)',
   [(D, D_CANDADO_UPDATE, "      array[old.telefono, new.telefono, new.telefono_alternativo],\n      array[old.dni, new.dni]\n", 1)],
   ['K2-', 'K4-', 'K5-']),
  # ── Ronda 4 · huecos de prueba de Codex r2 ──
  ('ME5', 'el documento enlaza el lead a OTRA persona, no a la del pasaporte (disparador de ensayo)', ME5_SQL, ['E8g2-']),
  ('MP29', 'pieza: no recorta el alternativo tecleado (con la migración, el alternativo con espacios deja de ser P0481)',
   [(P, P_ALT_BTRIM, "  v_alt text := nullif(p_telefono_alternativo, '');\n", 1)], ['E8l-']),
  # ── Catálogo ──
  ('MC1', 'la pieza pasa a SECURITY DEFINER', 'alter function %s security definer;' % P, ['C1:']),
  ('MC2', 'authenticated recibe EXECUTE sobre la pieza', 'grant execute on function %s to authenticated;' % P, ['C1:']),
  ('MC3', 'la pieza pierde el search_path vacío', 'alter function %s set search_path = public;' % P, ['C1:']),
  ('MC4', 'el disparador pasa a SECURITY INVOKER', 'alter function %s security invoker;' % D, ['C3:']),
  ('MC5', 'authenticated recibe EXECUTE sobre el disparador', 'grant execute on function %s to authenticated;' % D, ['C3:']),
  ('MC6', 'el núcleo pasa a SECURITY INVOKER', 'alter function %s security invoker;' % N, ['C2:']),
  ('MC7', 'el verificador modificado',
   "do $m$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure), "
   "'Un solo lead TOTAL por persona', 'Un solo lead TOTAL por persona.'); end $m$;", ['C5:']),
  ('MC8', 'la ficha (crm.editar_lead_fn) modificada',
   "do $m$ begin execute replace(pg_get_functiondef('crm.editar_lead_fn(uuid,jsonb)'::regprocedure), "
   "'nunca un «ok» sin escribir', 'nunca un «ok» sin escribir.'); end $m$;", ['C6:']),
]


def sql_de(frags):
    partes = []
    for firma, vigente, mutado, veces in frags:
        for t in ('$vigente$', '$mutado$', '$mutar$'):
            assert t not in vigente and t not in mutado, 'la etiqueta %s aparece en un fragmento' % t
        assert vigente != mutado, 'un fragmento no cambia nada'
        partes.append("""do $mutar$
declare
  v_def text;
  v_veces integer;
begin
  v_def := pg_get_functiondef('%s'::regprocedure);
  v_veces := (length(v_def) - length(replace(v_def, $vigente$%s$vigente$, ''))) / length($vigente$%s$vigente$);
  if v_veces <> %s then
    raise exception 'MUTANTE NO APLICABLE: el fragmento aparece %% veces en %s (debían ser %s)', v_veces;
  end if;
  execute replace(v_def, $vigente$%s$vigente$, $mutado$%s$mutado$);
end;
$mutar$;
""" % (firma, vigente, vigente, veces, firma, veces, vigente, mutado))
    return '\n'.join(partes)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == 'lista':
        ids = [m[0] for m in MUTANTES]
        assert len(ids) == len(set(ids)), 'ids repetidos'
        for id_, desc, _, casos in MUTANTES:
            assert casos, 'el mutante %s no declara por qué fallo tiene que morir' % id_
            print('%s|%s|%s' % (id_, desc, ';'.join(casos)))
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'sql':
        m = [x for x in MUTANTES if x[0] == sys.argv[2]]
        if len(m) != 1:
            sys.exit('mutante desconocido: %s' % sys.argv[2])
        _, _, cuerpo, _ = m[0]
        sql = cuerpo + '\n' if isinstance(cuerpo, str) else sql_de(cuerpo)
        open(sys.argv[3], 'w', encoding='utf-8').write(sql)
        return
    sys.exit(__doc__)


if __name__ == '__main__':
    main()

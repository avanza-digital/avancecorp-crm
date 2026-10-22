#!/usr/bin/env python3
"""Catálogo de MUTANTES del ensayo del bloque 2.11 (lo usa mutantes.sh; no toca la base).

Cada mutante rompe UNA defensa DESPUÉS de instalar la migración real y declara qué casos del oráculo (`pruebas.sql`) tienen que
nombrar su fallo («FALLO <caso>»). Los de CUERPO cambian un fragmento del cuerpo vivo (pg_get_functiondef) de la pieza nueva o de uno
de los dos núcleos; cada fragmento tiene que aparecer EXACTAMENTE las veces declaradas o el mutante se niega («MUTANTE NO APLICABLE»):
si la migración cambia, no muta otra cosa sin que nadie se entere. Los de CATÁLOGO son SQL libre.

Los del encargo (ENCARGO 2-2.11, punto 3): sin el alternativo conservado (M1) · sin los retirados (M2) · sin excluir la propia ficha
(M3). Y los de las otras defensas: sin el teléfono conservado (M4) · sin el DNI conservado (M5) · cualquier lead, no solo clientes
(M6) · normalizando el alternativo conservado (M7) · la regla del alta ANTES de lo de hoy (M8) · la regla solo en altas nuevas, sin el
reintento (M9: lo que D-61 descartó) · sin la regla en el núcleo del alta (M10) o en el de la base
(M11) · la regla de la base antes del ámbito (M12), del No contactar (M13) o del replay (M14) · sin el candado (M15) · el veredicto
como DATO en vez del P0481 (M16) · el rechazo del ámbito con el veredicto en el detalle (M18; ronda 3, Codex r1) · y el catálogo
(MC1–MC4). Aparte, los de CONCURRENCIA (`MUTANTES_ESPERA`, no salen en `lista`: los corre `espera.sh` con dos sesiones): M17, la pieza
JUZGA ANTES de tomar los candados (ronda 3, Codex r1 P3): el oráculo y K1 no lo distinguen; lo mata la prueba de orden de `espera.sh`.

Uso:  python3 -I mutantes.py lista                  → una línea por mutante: id|descripción|caso1;caso2;…
      python3 -I mutantes.py sql <id> <archivo.sql>  → escribe el SQL que instala ese mutante (también los de concurrencia)
      python3 -I mutantes.py comprobar <pieza.def> <nucleo.def> <nbase.def>
                                                     → comprueba en LOCAL que cada fragmento aparece las veces declaradas
"""
import sys

P = 'private.juicio_cliente_conservado(uuid)'
N = 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'
B = 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'

# ── Fragmentos vigentes (los que deja la migración, tal como los devuelve pg_get_functiondef) ────────────────────────────
CANDADO = "  perform private.bloquear_contactos_lead(array[v_l.telefono, v_l.telefono_alternativo], array[v_l.dni]);\n"
JUICIO = "  return private.juicio_cliente_convertido(v_l.telefono, v_l.telefono_alternativo, v_l.dni, v_l.id);\n"
LLAMADA_ALTA = ("    v_fresco := private.juicio_cliente_conservado(v_lead.id);\n"
                "    if v_fresco is not null then\n"
                "      return v_fresco;\n"
                "    end if;\n")
# La variante A, que D-61 descartó: la misma llamada solo en altas nuevas (el reintento, como en la regla 1b, sin ella).
LLAMADA_ALTA_A = ("    if not v_reintento then\n"
                  "      v_fresco := private.juicio_cliente_conservado(v_lead.id);\n"
                  "      if v_fresco is not null then\n"
                  "        return v_fresco;\n"
                  "      end if;\n"
                  "    end if;\n")
CONSERVADO_3B = "    v_conservado := private.alta_reactivar_bloqueo_conservado(v_cand.id);\n"
LLAMADA_BASE = ("  v_cliente := private.juicio_cliente_conservado(v_lead.id);\n"
                "  if v_cliente is not null then\n"
                "    raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;\n"
                "  end if;\n")
AMBITO = "  if v_lead.id is null or not v_lead.activo\n"
NO_CONTACTAR = "  if v_lead.no_contactar then\n"
REPLAY = "  -- Idempotencia DESPUES del candado del lead: dos clics concurrentes → el segundo espera y recibe el replay.\n"
AMBITO_RAISE = ("  if v_lead.id is null or not v_lead.activo\n"
                "     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then\n"
                "    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';\n"
                "  end if;\n")
DECLARE_PIEZA = "declare\n  v_l crm.leads%rowtype;\nbegin\n"

LOS_DEL_ALTA = ['A1-', 'A2-', 'A3-', 'A4-', 'A5-', 'A6-', 'A9-', 'A14-']
LOS_DE_LA_BASE = ['B1-', 'B2-', 'B3-', 'B4-', 'B5-', 'B6-', 'B7-', 'B8-', 'B9-']

MUTANTES = [
  # ── Los del encargo ──
  ('M1', 'la pieza no mira el ALTERNATIVO conservado',
   [(P, JUICIO, JUICIO.replace('v_l.telefono_alternativo', 'null'), 1)],
   ['A1-', 'A2-', 'A3-', 'A9-', 'A14-', 'B7-', 'B8-']),
  ('M2', 'la pieza solo reconoce a los clientes ACTIVOS (los retirados vuelven a reactivarse)',
   [(P, JUICIO, "  return case when exists (select 1 from crm.leads c where c.etapa = 'convertido' and c.activo and c.id is distinct from v_l.id\n"
                "                             and (c.telefono in (v_l.telefono, v_l.telefono_alternativo)\n"
                "                                  or c.telefono_alternativo in (v_l.telefono, v_l.telefono_alternativo) or c.dni = v_l.dni))\n"
                "              then private.juicio_cliente_convertido(v_l.telefono, v_l.telefono_alternativo, v_l.dni, v_l.id) end;\n", 1)],
   ['A2-', 'A4-', 'A5-', 'A6-', 'B3-', 'B4-', 'B6-']),
  ('M3', 'la pieza no excluye al propio lead (se juzga contra sí mismo)',
   [(P, JUICIO, JUICIO.replace('v_l.dni, v_l.id)', 'v_l.dni, null)'), 1)], ['U1-']),
  # ── Las otras defensas de la pieza ──
  ('M4', 'la pieza no mira el TELÉFONO conservado',
   [(P, JUICIO, JUICIO.replace('(v_l.telefono, ', '(null, '), 1)],
   ['A4-', 'A5-', 'B1-', 'B2-', 'B3-', 'B4-', 'B5-', 'B9-']),
  ('M5', 'la pieza no mira el DNI conservado',
   [(P, JUICIO, JUICIO.replace('v_l.dni, v_l.id)', 'null, v_l.id)'), 1)], ['A6-', 'B6-']),
  ('M6', 'la pieza bloquea por CUALQUIER lead con esos teléfonos, no solo por clientes (contra D-25/D-37)',
   [(P, JUICIO, "  return coalesce(private.juicio_cliente_convertido(v_l.telefono, v_l.telefono_alternativo, v_l.dni, v_l.id),\n"
                "    (select pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'cualquier lead') from crm.leads c\n"
                "      where c.id <> v_l.id and (c.telefono in (v_l.telefono, v_l.telefono_alternativo)\n"
                "                                or c.telefono_alternativo in (v_l.telefono, v_l.telefono_alternativo)) limit 1));\n", 1)],
   ['A11-', 'B11-']),
  ('M7', 'la pieza normaliza el alternativo conservado (ya canónico): el internacional de 9 dígitos pasa por el móvil peruano',
   [(P, JUICIO, JUICIO.replace('v_l.telefono, v_l.telefono_alternativo, v_l.dni',
                               'v_l.telefono, private.normalizar_telefono(v_l.telefono_alternativo), v_l.dni'), 1)], ['A12-']),
  ('M15', 'la pieza no toma los candados de contacto antes de juzgar',
   [(P, CANDADO, '', 1)], ['K1-']),
  # ── El núcleo del alta ──
  ('M8', 'alta: la regla ANTES de lo de hoy (antes de lo conservado contra leads activos, 3b): el «tomado» de hoy deja de mandar',
   [(N, LLAMADA_ALTA, '', 1),
    (N, CONSERVADO_3B, LLAMADA_ALTA.replace('v_lead.id', 'v_cand.id') + CONSERVADO_3B, 1)], ['A13-']),
  ('M9', 'alta: la regla solo en altas NUEVAS (el reintento vuelve a reactivar la ficha de un cliente: lo que D-61 descartó)',
   [(N, LLAMADA_ALTA, LLAMADA_ALTA_A, 1)], ['A9-']),
  ('M10', 'alta: sin la regla en el núcleo (la ficha que conserva el contacto de un cliente vuelve a reactivarse)',
   [(N, LLAMADA_ALTA, '', 1)], LOS_DEL_ALTA + ['C2:']),
  # ── El núcleo de la base ──
  ('M11', 'base: sin la regla en el núcleo (el lead que conserva el contacto de un cliente vuelve a la cartera)',
   [(B, LLAMADA_BASE, '', 1)], LOS_DE_LA_BASE + ['C2:']),
  ('M12', 'base: la regla ANTES del ámbito (quien no ve el lead recibe el veredicto con el asesor)',
   [(B, LLAMADA_BASE, '', 1), (B, AMBITO, LLAMADA_BASE + AMBITO, 1)], ['B12-']),
  ('M13', 'base: la regla ANTES del No contactar (el veto deja de mandar)',
   [(B, LLAMADA_BASE, '', 1), (B, NO_CONTACTAR, LLAMADA_BASE + NO_CONTACTAR, 1)], ['B13-']),
  ('M14', 'base: la regla ANTES del replay (una operación ya hecha deja de devolver lo de entonces)',
   [(B, LLAMADA_BASE, '', 1), (B, REPLAY, LLAMADA_BASE + REPLAY, 1)], ['B14-']),
  ('M16', 'base: el veredicto como DATO (return) en vez del P0481 (la puerta responde algo que la pantalla toma por éxito)',
   [(B, "    raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;\n",
     "    return v_cliente;\n", 1)], LOS_DE_LA_BASE),
  ('M18', 'base: el rechazo del ámbito conserva su código (P0002) pero lleva el veredicto en el detalle (filtra el asesor a quien no ve el lead)',
   [(B, AMBITO_RAISE, AMBITO_RAISE.replace("using errcode = 'P0002';",
                                           "using errcode = 'P0002', detail = coalesce(private.juicio_cliente_conservado(v_lead.id)::text, '');"), 1)],
   ['B12-']),
  # ── Catálogo ──
  ('MC1', 'la pieza pasa a SECURITY DEFINER', 'alter function %s security definer;' % P, ['C1:']),
  ('MC2', 'authenticated recibe EXECUTE sobre la pieza', 'grant execute on function %s to authenticated;' % P, ['C1:']),
  ('MC3', 'la pieza pierde el search_path vacío', 'alter function %s set search_path = public;' % P, ['C1:']),
  ('MC4', 'otra función usa la pieza',
   "create function private.ensayo_2_11_otro_llamador() returns jsonb language sql volatile set search_path = '' as "
   "$m$ select private.juicio_cliente_conservado(null::uuid) $m$;", ['C3:']),
]


# Los de CONCURRENCIA: no los juzga el oráculo (sobreviven a propósito a K1 y a la espera con A); los corre `espera.sh`.
MUTANTES_ESPERA = [
  ('M17', 'la pieza JUZGA ANTES de tomar los candados (guarda el veredicto, toma los candados después y devuelve lo guardado)',
   [(P, DECLARE_PIEZA, "declare\n  v_l crm.leads%rowtype;\n  v_j jsonb;\nbegin\n", 1),
    (P, CANDADO, '', 1),
    (P, JUICIO, "  v_j := private.juicio_cliente_convertido(v_l.telefono, v_l.telefono_alternativo, v_l.dni, v_l.id);\n" + CANDADO + "  return v_j;\n", 1)],
   ['espera.sh modo «orden»: «perfiles tomada por quien esperaba: sí»']),
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
        m = [x for x in MUTANTES + MUTANTES_ESPERA if x[0] == sys.argv[2]]
        if len(m) != 1:
            sys.exit('mutante desconocido: %s' % sys.argv[2])
        _, _, cuerpo, _ = m[0]
        sql = cuerpo + '\n' if isinstance(cuerpo, str) else sql_de(cuerpo)
        open(sys.argv[3], 'w', encoding='utf-8').write(sql)
        return
    if len(sys.argv) == 5 and sys.argv[1] == 'comprobar':
        textos = {P: open(sys.argv[2], encoding='utf-8').read(), N: open(sys.argv[3], encoding='utf-8').read(),
                  B: open(sys.argv[4], encoding='utf-8').read()}
        malos = 0
        for id_, _, cuerpo, _ in MUTANTES + MUTANTES_ESPERA:
            if isinstance(cuerpo, str):
                continue
            texto = dict(textos)
            for firma, vigente, mutado, veces in cuerpo:
                n = texto[firma].count(vigente)
                if n != veces:
                    print('✗ %s: el fragmento aparece %d veces en %s (debían ser %d): %r' % (id_, n, firma, veces, vigente[:70]))
                    malos += 1
                texto[firma] = texto[firma].replace(vigente, mutado)
            print('✓ %s aplicable' % id_)
        sys.exit(1 if malos else 0)
    sys.exit(__doc__)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Catálogo de MUTANTES del ensayo del bloque 2.13, ronda 2 (lo usa mutantes.sh; no toca la base).

Cada mutante rompe UNA defensa de la migración DESPUÉS de instalarla y declara qué casos del oráculo (`pruebas.sql`) tienen que
nombrar su fallo («FALLO <caso>»). Los de CUERPO cambian un fragmento del cuerpo vivo (pg_get_functiondef) de la pieza o del
disparador; cada fragmento tiene que aparecer EXACTAMENTE las veces declaradas o el mutante se niega («MUTANTE NO APLICABLE»): si la
migración cambia, no muta otra cosa sin que nadie se entere. Los de CATÁLOGO son SQL libre (ficha y permisos).

Uso:  python3 -I mutantes.py lista                  → una línea por mutante: id|descripción|caso1;caso2;…
      python3 -I mutantes.py sql <id> <archivo.sql>  → escribe el SQL que instala ese mutante
"""
import sys

P = 'private.juicio_lead_vivo_por_numero(text,uuid)'
D = 'private.trg_leads_disponibilidad_atomica()'

# ── Fragmentos vigentes (los de la migración, tal como los devuelve pg_get_functiondef) ─────────────────────────────────
P_CANON = "  v_num text := (select c.e164 from private.canonizar_contacto(p_numero) c);\n"
P_EXCLUIR = "  where l.id is distinct from p_excluir_lead_id\n    and l.activo = true\n"
P_ACTIVO = "    and l.activo = true\n    and l.etapa not in ('convertido', 'descartado')\n"
P_ETAPA = "    and l.etapa not in ('convertido', 'descartado')\n"
P_NUMERO = "    and (l.telefono = v_num or l.telefono_alternativo = v_num)\n"
P_ORDEN = "  order by case when l.telefono = v_num then 1 else 2 end, l.id\n"
P_VEREDICTO = "  v_juicio := private.verificar_disponibilidad_lead_impl(v_telefono, null, p_excluir_lead_id);\n"
P_CANONICO = "    and private.normalizar_telefono(l.telefono) = l.telefono\n"

D_A = ("        if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv) then\n"
       "          v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);\n"
       "        end if;\n")
D_A_COND = "        if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv) then\n"
D_A_LLAMADA = "          v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);\n"
D_B = ("    if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv)\n"
       "       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n"
       "      v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);\n"
       "    end if;\n")
D_B_COND = ("    if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv)\n"
            "       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n")
D_B_LLAMADA = ("       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n"
               "      v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);\n")
D_SESION = ("      if v_actor is not null\n"
            "         and new.telefono_alternativo is distinct from old.telefono_alternativo then\n")

MUTANTES = [
    # ── La pieza ──
    ('MP1', 'pieza: sin excluir la propia ficha (la tapa a otro lead vivo con el mismo número)', [(P, P_EXCLUIR, "  where l.activo = true\n", 1)], ['T15-']),
    ('MP2', 'pieza: sin mirar el alternativo del otro lead (solo su teléfono)', [(P, P_NUMERO, "    and l.telefono = v_num\n", 1)],
     ['T2-', 'T9-']),
    ('MP3', 'pieza: compara el número tal cual llega, sin forma canónica', [(P, P_CANON, "  v_num text := p_numero;\n", 1)],
     ['T5a-', 'T5b-']),
    ('MP4', 'pieza: solo recorta espacios (sin forma canónica)',
     [(P, P_CANON, "  v_num text := nullif(pg_catalog.btrim(p_numero), '');\n", 1)], ['T5a-']),
    ('MP5', 'pieza: la forma del candado (normalizar_telefono) en vez de la canónica: junta un internacional de 9 dígitos con el móvil peruano',
     [(P, P_CANON, "  v_num text := private.normalizar_telefono(p_numero);\n", 1)], ['N11-']),
    ('MP6', 'pieza: también los leads RETIRADOS (un retirado tapa a un vivo con el mismo número)', [(P, P_ACTIVO, P_ETAPA, 1)], ['T16-']),
    ('MP7', 'pieza: también los leads DESCARTADOS', [(P, P_ETAPA, "    and l.etapa <> 'convertido'\n", 1)], ['N4a-']),
    ('MP8', 'pieza: sin la precedencia del teléfono sobre el alternativo (solo por id)', [(P, P_ORDEN, "  order by l.id\n", 1)], ['T8-']),
    ('MP9', 'pieza: el desempate final al revés (id mayor)',
     [(P, P_ORDEN, "  order by case when l.telefono = v_num then 1 else 2 end, l.id desc\n", 1)], ['T9-']),
    ('MP10', 'pieza: un veredicto propio en vez del de la disponibilidad (el verificador)',
     [(P, P_VEREDICTO, "  v_juicio := pg_catalog.jsonb_build_object('estado', 'tomado');\n", 1)], ['T1a-', 'T3-', 'T13-', 'T14-']),
    ('MP11', 'pieza: el veredicto del número tecleado, no el del teléfono del lead que lo tiene',
     [(P, P_VEREDICTO, "  v_juicio := private.verificar_disponibilidad_lead_impl(v_num, null, p_excluir_lead_id);\n", 1)], ['T2-', 'T9-']),
    ('MP12', 'pieza: sin el filtro del principal visible (nombra a OTRO lead por el número normalizado, o da un P0481 «libre»)',
     [(P, P_CANONICO, "", 1)], ['N12-', 'N12b-']),
    # ── El disparador ──
    ('MD1', 'disparador: sin la condición «es cliente» en la rama del alternativo',
     [(D, D_A_COND, "        if v_cliente is null then\n", 1)], ['N2a-', 'N2b-']),
    ('MD2', 'disparador: sin la condición «es cliente» en la rama del teléfono',
     [(D, D_B_COND, "    if v_cliente is null\n       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n", 1)],
     ['N2c-']),
    # ── Ronda 2 · la calificación de la conversión (auditor P3-1) ──
    ('MD12', 'disparador: rama del alternativo sin la calificación (new.etapa = convertido a secas: una conversión ilegal recibe el veredicto)',
     [(D, D_A_COND, "        if v_cliente is null and new.etapa = 'convertido' then\n", 1)], ['N14a-']),
    ('MD13', 'disparador: rama del teléfono sin la calificación (new.etapa = convertido a secas)',
     [(D, D_B_COND, "    if v_cliente is null and new.etapa = 'convertido'\n"
       "       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n", 1)], ['N14b-']),
    ('MD14', 'disparador: rama del alternativo sin «or v_priv» (la conversión real con el número de un lead vivo pasa)',
     [(D, D_A_COND, "        if v_cliente is null and new.etapa = 'convertido' and old.etapa = 'convertido' then\n", 1)], ['T15-']),
    ('MD15', 'disparador: rama del teléfono sin «or v_priv»',
     [(D, D_B_COND, "    if v_cliente is null and new.etapa = 'convertido' and old.etapa = 'convertido'\n"
       "       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n", 1)], ['T15b-']),
    ('MD16', 'disparador: rama del alternativo solo bajo válvula (sin old.etapa = convertido: el cliente que ya lo es no se juzga)',
     [(D, D_A_COND, "        if v_cliente is null and new.etapa = 'convertido' and v_priv then\n", 1)], ['T1a-', 'T2-', 'T3-']),
    ('MD17', 'disparador: rama del teléfono solo bajo válvula',
     [(D, D_B_COND, "    if v_cliente is null and new.etapa = 'convertido' and v_priv\n"
       "       and new.telefono_alternativo is distinct from old.telefono_alternativo then\n", 1)], ['T4-']),
    ('MD3', 'disparador: sin la regla en la rama del alternativo', [(D, D_A, "", 1)], ['T1a-', 'T2-', 'T3-', 'T6a-', 'T7-']),
    ('MD4', 'disparador: sin la regla en la rama del teléfono', [(D, D_B, "", 1)], ['T4-']),
    ('MD5', 'disparador: en la rama del teléfono también cuando el alternativo NO cambia (lo que la edición no toca)',
     [(D, D_B_COND, "    if v_cliente is null and new.etapa = 'convertido' then\n", 1)], ['N5c-']),
    ('MD6', 'disparador: la regla antes que la del 2.8 (el lead vivo manda sobre el otro cliente)',
     [(D, D_A_COND + D_A_LLAMADA, "        if new.etapa = 'convertido' then\n"
       "          v_cliente := coalesce(private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id), v_cliente);\n", 1)], ['T11-']),
    ('MD7', 'disparador: el veredicto antes que el rol (Coordinación y el usuario sin rol lo verían)',
     [(D, D_A, D_A_COND + D_A_LLAMADA + "          if v_cliente is not null then\n"
       "            raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;\n"
       "          end if;\n        end if;\n", 1)], ['T6a-', 'T6b-']),
    ('MD8', 'disparador: la regla también SIN sesión',
     [(D, D_SESION, "      if v_actor is null and new.etapa = 'convertido'\n"
       "         and new.telefono_alternativo is distinct from old.telefono_alternativo then\n"
       "        v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);\n"
       "        if v_cliente is not null then\n"
       "          raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;\n"
       "        end if;\n      end if;\n" + D_SESION, 1)], ['N6-']),
    ('MD9', 'disparador: la rama del alternativo no excluye la propia ficha',
     [(D, D_A_LLAMADA, D_A_LLAMADA.replace('old.id);', 'null);'), 1)], ['N7b-']),
    ('MD10', 'disparador: la rama del teléfono no excluye la propia ficha',
     [(D, D_B_LLAMADA, D_B_LLAMADA.replace('old.id);', 'null);'), 1)], ['N7c-']),
    ('MD11', 'disparador: juzga el alternativo VIEJO en vez del nuevo',
     [(D, D_A_LLAMADA, D_A_LLAMADA.replace('(new.telefono_alternativo,', '(old.telefono_alternativo,'), 1)], ['T1a-', 'T2-']),
    # ── Catálogo ──
    ('MC1', 'la pieza pasa a SECURITY DEFINER', 'alter function %s security definer;' % P, ['C1:']),
    ('MC2', 'authenticated recibe EXECUTE sobre la pieza', 'grant execute on function %s to authenticated;' % P, ['C1:']),
    ('MC3', 'la pieza pierde el search_path vacío', 'alter function %s set search_path = public;' % P, ['C1:']),
    ('MC4', 'la pieza pasa a VOLATILE', 'alter function %s volatile;' % P, ['C1:']),
    ('MC5', 'el disparador pasa a SECURITY INVOKER', 'alter function %s security invoker;' % D, ['C2:']),
    ('MC6', 'authenticated recibe EXECUTE sobre el disparador', 'grant execute on function %s to authenticated;' % D, ['C2:']),
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

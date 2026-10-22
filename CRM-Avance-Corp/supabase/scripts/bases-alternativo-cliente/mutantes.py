#!/usr/bin/env python3
"""Catálogo de MUTANTES del ensayo del bloque 2.9 (lo usa mutantes.sh; no toca la base).

Cada mutante rompe UNA defensa DESPUÉS de instalar la migración real y declara qué casos del oráculo (`pruebas.sql`) tienen que
nombrar su fallo («FALLO <caso>»). Los de CUERPO cambian un fragmento del cuerpo vivo (pg_get_functiondef) del envoltorio, del núcleo
de la carga o de su regla del ámbito; cada fragmento tiene que aparecer EXACTAMENTE las veces declaradas o el mutante se niega
(«MUTANTE NO APLICABLE»): si la migración cambia, no muta otra cosa sin que nadie se entere. Los de CATÁLOGO son SQL libre.

Los del encargo (ENCARGO 2-2.9, punto 3): sin la comparación nueva (M1) · con cualquier lead en vez de solo convertidos (M2) · con el
alternativo «al revés» (M3: la comparación nueva mira el teléfono PRINCIPAL del cliente en vez de su alternativo; M3b: el filtro al
revés, los que NO son clientes) · sin normalizar (M4a: la fila sin normalizar antes de comparar; M4b: normalizando el alternativo
guardado, que ya es canónico: confunde el internacional de 9 dígitos con el móvil peruano). Y los de las otras defensas: la regla del
ámbito (M5), los retirados (M6), el orden de relevancia (M7), la categoría (M8) y el catálogo (MC1–MC4). RONDA 2 (Codex r1, auditor r1):
MD sin la coincidencia por DNI (D2) · MA1 el ámbito con `bool_and` y MA2 el ámbito que solo mira al GANADOR (F3/F3b: cualquier
coincidencia de otro equipo tiene que ocultar, aunque haya otra propia) · M9 el desempate por fecha al revés (E1) · MC5/MC6 otro
consumidor de la regla del ámbito / del núcleo (C3) · MC7 el disparador sin el candado del alternativo del 2.8 r4 (C5).

Límite (Codex r1): M1 y M3 son equivalentes en el conjunto que buscan (el principal ya estaba en el WHERE); los mutantes no son
defensas independientes una a una.

Uso:  python3 -I mutantes.py lista                  → una línea por mutante: id|descripción|caso1;caso2;…
      python3 -I mutantes.py sql <id> <archivo.sql>  → escribe el SQL que instala ese mutante
"""
import sys

E = 'private.bases_carga_contacto_existente(text,text)'
N = 'private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)'
A = 'private.bases_carga_fuera_de_ambito(uuid,text,text,text)'

# ── Fragmentos vigentes (los de la migración y los de B8, tal como los devuelve pg_get_functiondef) ─────────────────────
BRAZO = "      or (l.etapa = 'convertido' and l.telefono_alternativo = p_telefono)\n"
ORDEN = "         pg_catalog.row_number() over (order by case when l.activo and l.etapa not in ('convertido', 'descartado') then 0\n"
CATEGORIA = "         case when not l.activo then 'retirado'\n"
NORMALIZA = "    v_tel := private.normalizar_telefono(nullif(pg_catalog.btrim(e.valor ->> 'telefono'), ''));\n"
AMBITO = "    from private.bases_carga_contacto_existente(p_telefono, p_dni) x\n"
# Ronda 2
D = 'private.trg_leads_disponibilidad_atomica()'
WHERE_DNI = "   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)\n"
AMBITO_OR = ("  select coalesce(pg_catalog.bool_or(not private.base_gestion_lead_visible(p_actor, p_rol, x.vendedor_id, "
             "x.asignado_supervisor_id)), false)\n")
FECHA = "                                               l.creado_en desc, l.id)\n"
CANDADO_U = "      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],\n"

LOS_DEL_ALTERNATIVO = ['A1-', 'A2-', 'A3-', 'A4-', 'A5-', 'F1-', 'F2-', 'R1-', 'Z1-', 'Z2-', 'Z3-', 'Z4-', 'D1-', 'L1-']

MUTANTES = [
  # ── Los del encargo ──
  ('M1', 'envoltorio: sin la comparación nueva (el alternativo de un cliente vuelve a cargarse)',
   [(E, BRAZO, "", 1)], LOS_DEL_ALTERNATIVO),
  ('M2', 'envoltorio: el alternativo de CUALQUIER lead, no solo de los convertidos (contra D-37)',
   [(E, BRAZO, "      or (l.telefono_alternativo = p_telefono)\n", 1)], ['N1-', 'N2-', 'N3-', 'L1-']),
  ('M3', 'envoltorio, al revés: la comparación nueva mira el teléfono PRINCIPAL del cliente en vez de su alternativo',
   [(E, BRAZO, "      or (l.etapa = 'convertido' and l.telefono = p_telefono)\n", 1)], LOS_DEL_ALTERNATIVO),
  ('M3b', 'envoltorio, al revés: el filtro mira a los que NO son clientes',
   [(E, BRAZO, "      or (l.etapa <> 'convertido' and l.telefono_alternativo = p_telefono)\n", 1)],
   LOS_DEL_ALTERNATIVO + ['N1-', 'N2-', 'N3-']),
  ('M4a', 'núcleo de la carga: sin normalizar el teléfono de la fila antes de comparar (y de validar)',
   [(N, NORMALIZA, "    v_tel := nullif(pg_catalog.btrim(e.valor ->> 'telefono'), '');\n", 1)], ['Z1-', 'Z2-', 'Z3-', 'Z4-']),
  ('M4b', 'envoltorio: normaliza el alternativo guardado (ya canónico): el internacional de 9 dígitos pasa por el móvil peruano',
   [(E, BRAZO, "      or (l.etapa = 'convertido' and private.normalizar_telefono(l.telefono_alternativo) = p_telefono)\n", 1)], ['N5-']),
  # ── Las otras defensas ──
  ('M5', 'regla del ámbito: no ve el alternativo (el motivo del cliente de otro equipo se filtra a quien carga)',
   [(A, AMBITO, "    from (select l.vendedor_id, l.asignado_supervisor_id from crm.leads l where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)) x\n", 1)],
   ['F1-']),
  ('M6', 'envoltorio: solo los clientes ACTIVOS (el alternativo de un cliente retirado vuelve a cargarse)',
   [(E, BRAZO, "      or (l.etapa = 'convertido' and l.activo and l.telefono_alternativo = p_telefono)\n", 1)], ['A2-', 'A4-']),
  ('M7', 'envoltorio: otro orden de relevancia (lo que casa solo por el alternativo, al final)',
   [(E, ORDEN, "         pg_catalog.row_number() over (order by (l.telefono is distinct from p_telefono and (p_dni is null or l.dni is distinct from p_dni)), case when l.activo and l.etapa not in ('convertido', 'descartado') then 0\n", 1)],
   ['R1-']),
  ('M8', 'envoltorio: categoría propia para el alternativo (siempre «convertido», también si el cliente está retirado)',
   [(E, CATEGORIA, "         case when l.etapa = 'convertido' and l.telefono_alternativo = p_telefono and l.telefono is distinct from p_telefono then 'convertido'\n              when not l.activo then 'retirado'\n", 1)],
   ['A2-', 'A4-']),
  # ── Ronda 2 ──
  ('MD', 'envoltorio: sin la coincidencia por DNI (el DNI de un cliente sin persona deja de detectarse)',
   [(E, WHERE_DNI, "   where l.telefono = p_telefono\n", 1)], ['D2-']),
  ('MA1', 'regla del ámbito: bool_and en vez de bool_or (solo oculta si TODAS las coincidencias son de otro equipo)',
   [(A, AMBITO_OR, AMBITO_OR.replace('bool_or', 'bool_and'), 1)], ['F3-', 'F3b-']),
  ('MA2', 'regla del ámbito: solo examina la coincidencia GANADORA (la más relevante)',
   [(A, AMBITO, "    from (select y.* from private.bases_carga_contacto_existente(p_telefono, p_dni) y order by y.orden limit 1) x\n", 1)],
   ['F3-', 'F3b-']),
  ('M9', 'envoltorio: el desempate por fecha al revés (a igual categoría, gana la más ANTIGUA)',
   [(E, FECHA, FECHA.replace('l.creado_en desc', 'l.creado_en asc'), 1)], ['E1-']),
  # ── Catálogo ──
  ('MC1', 'el envoltorio pasa a SECURITY DEFINER', 'alter function %s security definer;' % E, ['C1:']),
  ('MC2', 'authenticated recibe EXECUTE sobre el envoltorio', 'grant execute on function %s to authenticated;' % E, ['C1:']),
  ('MC3', 'el envoltorio pierde el search_path vacío', 'alter function %s set search_path = public;' % E, ['C1:']),
  ('MC4', 'otra función usa el envoltorio (el cambio la alcanzaría)',
   "create function private.ensayo_2_9_otro_llamador() returns bigint language sql stable set search_path = '' as "
   "$m$ select count(*) from private.bases_carga_contacto_existente('+51900000000', null) $m$;", ['C3:']),
  ('MC5', 'otra función consume la regla del ámbito (el cambio la alcanzaría)',
   "create function private.ensayo_2_9_consume_ambito() returns boolean language sql stable set search_path = '' as "
   "$m$ select private.bases_carga_fuera_de_ambito(null::uuid, null::text, '+51900000000', null::text) $m$;", ['C3:']),
  ('MC6', 'otra función consume el núcleo de la carga (el cambio la alcanzaría)',
   "create function private.ensayo_2_9_consume_nucleo() returns jsonb language plpgsql volatile set search_path = '' as "
   "$m$ begin if false then return private.bases_carga_cargar_lote_core(null, null, null, null); end if; return null; end $m$;", ['C3:']),
  ('MC7', 'el disparador de disponibilidad sin el alternativo en su candado de la UPDATE (el de antes del 2.8 r4)',
   [(D, CANDADO_U, "      array[old.telefono, new.telefono],\n", 1)], ['C5:']),
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

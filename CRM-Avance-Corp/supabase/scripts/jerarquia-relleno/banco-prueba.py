#!/usr/bin/env python3
"""Prueba la migración del relleno en el banco Docker con datos (stack fact0c), sin dejar rastro.

Monta en el banco la MISMA situación que producción con dos analistas del banco (evento anterior → deriva sin evento →
fila de auditoría), cambia SOLO el bloque de constantes y corre cada caso en su propia transacción, que se deshace.
Casos: el bueno (aplica y la repetición dice «ya aplicado»), el ensayo, una base sin estas personas, seis negativas\nla reversa (borra, se repite sin efecto y se niega ante un evento alterado, también si solo cambia un supervisor) y la
concurrencia (con los candados de la migración, un cambio de jerarquía y un evento simultáneos esperan; sin ellos, no).
Uso: banco-prueba.py [contenedor]   (por defecto supabase_db_avancecorp-fact0c-20261009; hace falta supabase_admin)
"""
import subprocess
import sys
import time
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
MIGRACION = CARPETA.parents[1] / 'migrations' / '20261010150451_crm_jerarquia_relleno_carmen_jorge.sql'
CONTENEDOR = sys.argv[1] if len(sys.argv) > 1 else 'supabase_db_avancecorp-fact0c-20261009'

V, V2 = '857a97da-9fc8-4e9d-b319-aeb7f2dc2ca6', '8778a96a-60c2-4b66-a530-9d50681c7d2c'
S1, S2, S3 = ('866e171f-0f7f-4511-a6a8-a4f44afccc59', 'a0c29740-e1f0-45e9-80c7-0433bf32d0df',
              '5b3ce2a4-8a96-4cf0-86eb-fe8be62bb3d9')
A1, A2 = '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'
I1, I2 = 'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000002'
TS = "('2026-03-20 12:00'::timestamp at time zone 'America/Lima')"

CONSTANTES = f"""-- INICIO CONSTANTES
  create temporary table relleno_eventos (
    perfil_id uuid primary key, audit_id uuid not null unique, idempotencia uuid not null unique
  ) on commit drop;
  insert into pg_temp.relleno_eventos values ('{V}', '{A1}', '{I1}'), ('{V2}', '{A2}', '{I2}');
  v_antes := '{S1}';
  v_despues := '{S2}';
  v_ts := {TS};
  v_corte := '2026-10-05';
  create temporary table relleno_aprobado (
    analista_id uuid, mes date, moneda text, operaciones bigint not null, capital numeric not null,
    primary key (analista_id, mes, moneda)
  ) on commit drop;
  insert into pg_temp.relleno_aprobado values ('{V}', '2026-10-01', 'PEN', 27, 27000);
-- FIN CONSTANTES
"""

MONTAJE = f"""begin isolation level repeatable read;
set local session_replication_role = replica;
update crm.usuario_eventos set creado_en = ('2026-03-05 12:00'::timestamp at time zone 'America/Lima')
 where accion = 'jerarquia_actualizada' and objetivo_id in ('{V}', '{V2}');
update crm.equipo set supervisor_id = '{S2}' where perfil_id in ('{V}', '{V2}');
insert into public.audit_log(id, tabla, operacion, fila_id, usuario_id, ts, data_antes, data_despues) values
  ('{A1}', 'crm.equipo', 'UPDATE', '{V}', null, {TS}, '{{"supervisor_id": "{S1}"}}', '{{"supervisor_id": "{S2}"}}'),
  ('{A2}', 'crm.equipo', 'UPDATE', '{V2}', null, {TS}, '{{"supervisor_id": "{S1}"}}', '{{"supervisor_id": "{S2}"}}');
set local session_replication_role = origin;
"""


def bloque_do(texto):
    ini, fin = texto.index('do $migracion$'), texto.index('$migracion$;') + len('$migracion$;')
    return texto[ini:fin] + '\n'


def con_constantes(do, constantes):
    a, b = '-- INICIO CONSTANTES\n', '-- FIN CONSTANTES\n'
    assert do.count(a) == do.count(b) == 1
    return do[:do.index(a)] + constantes + do[do.index(b) + len(b):]


def reversa_banco():
    """La reversa con las personas, idempotencias y hora del banco, sin su begin/commit."""
    t = (CARPETA / 'reversa.sql').read_text()
    t = t[t.index('do $reversa$'):t.index('$reversa$;') + len('$reversa$;')] + '\n'
    for viejo, nuevo in (('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', V), ('cc8b660a-49e9-49b2-a939-c12b5078911b', V2),
                         ('df2577aa-0315-43ad-8d28-cc1fce382b61', I1), ('8ea032ed-da1e-48f1-b75c-52f6afaaf3e5', I2),
                         ('ebb19751-5976-4446-91ec-03382247d8b8', S1), ('bf1c562e-ed08-4cc3-92a8-34f1fa3e9127', S2),
                         ("'2026-08-29 17:56:38.8714+00'", TS)):
        assert viejo in t
        t = t.replace(viejo, nuevo)
    return t


def mutar(texto, viejo, nuevo):
    assert texto.count(viejo) == 1, f'mutación ambigua: {viejo!r}'
    return texto.replace(viejo, nuevo)


def correr(sql):
    r = subprocess.run(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-U', 'supabase_admin', '-d', 'postgres',
                        '-At', '-v', 'ON_ERROR_STOP=0'], input=sql, capture_output=True, text=True)
    return r.stdout + r.stderr


def concurrencia(texto, con_candados=True):
    """Sesión A: los candados de la migración (extraídos de su texto) y 4 s de espera. Sesión B, 1 s después: un
    cambio en crm.equipo y un evento nuevo, con lock_timeout de 1 s y deshechos. Con candados, B debe esperar y caer."""
    candados = [l for l in texto.splitlines() if l.startswith('lock table ')]
    assert len(candados) == 2, candados
    a_sql = ('begin isolation level repeatable read;\n' + ('\n'.join(candados) + '\n' if con_candados else '')
             + 'select pg_sleep(4);\nrollback;\n')
    a = subprocess.Popen(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At'],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    a.stdin.write(a_sql)
    a.stdin.close()
    time.sleep(1)
    b = correr(f"""set lock_timeout = '1s';
begin; update crm.equipo set supervisor_id = supervisor_id where perfil_id = '{V}'; rollback;
begin; insert into crm.usuario_eventos(actor_id, objetivo_id, accion, detalle, idempotencia)
  values ('f6d2941b-2e93-4c81-9a27-0c5e786b104d', '{V}', 'perfil_actualizado', '{{}}', gen_random_uuid()); rollback;
""")
    a.wait()
    return b


def main():
    texto = MIGRACION.read_text()
    do = con_constantes(bloque_do(texto), CONSTANTES)
    verificar = (f"select 'EVENTOS=' || count(*) from crm.usuario_eventos where idempotencia in ('{I1}', '{I2}')"
                 f" and detalle ->> 'via' = 'relleno';\n")
    casos = [
        ('bueno: aplica y la repetición no hace nada',
         # Entre las dos pasadas se sueltan las tablas temporales: la repetición real es otra transacción.
         MONTAJE + do + verificar + 'drop table pg_temp.relleno_eventos, pg_temp.relleno_aprobado, '
         'pg_temp.relleno_antes, pg_temp.relleno_despues, pg_temp.relleno_par;\n' + do + 'rollback;\n',
         ['Relleno de jerarquía aplicado: 36 operaciones', 'nuevas desde el 2026-10-05: 9', 'EVENTOS=2',
          'ya aplicado']),
        ('ensayo: acaba en error y lo deshace',
         MONTAJE + "set local crm.relleno_jerarquia_ensayo = 'on';\n" + do + verificar + 'rollback;\n',
         ['ENSAYO RELLENO PASS', 'SE DESHACE TODO']),
        ('base sin estas personas: la migración de producción no hace nada',
         texto, ['esta base no tiene a estas personas']),
        ('negativa: importe aprobado distinto',
         MONTAJE + mutar(do, "'PEN', 27, 27000)", "'PEN', 27, 27001)") + 'rollback;\n',
         ['ORÁCULO: el cambio no es el aprobado']),
        ('negativa: el evento no cambia el supervisor (mutante del insert)',
         MONTAJE + mutar(do, "'supervisor_nuevo', v_despues, 'via', 'relleno',",
                         "'supervisor_nuevo', v_antes, 'via', 'relleno',") + 'rollback;\n',
         ['ORÁCULO: 36 operaciones de los dos desde el cambio no quedan con ADMINISTRADOR']),
        ('negativa: el evento lleva a otro supervisor (mutante del insert)',
         MONTAJE + mutar(do, "'supervisor_nuevo', v_despues, 'via', 'relleno',",
                         f"'supervisor_nuevo', '{S3}'::uuid, 'via', 'relleno',") + 'rollback;\n',
         ['ORÁCULO: 36 operaciones cambian de supervisor fuera de lo aprobado']),
        ('negativa: la hora no es la de la auditoría',
         MONTAJE + mutar(do, f'v_ts := {TS};', f"v_ts := {TS} + interval '1 second';") + 'rollback;\n',
         ['PREFLIGHT: el rastro de auditoría no es el medido (0 de 2']),
        ('negativa: relleno a medias',
         MONTAJE + f"insert into crm.usuario_eventos(actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)"
         f" values ('f6d2941b-2e93-4c81-9a27-0c5e786b104d', '{V}', 'jerarquia_actualizada', '{{\"via\": \"relleno\"}}',"
         f" '{I1}', {TS});\n" + do + 'rollback;\n',
         ['PREFLIGHT: relleno a medias o distinto (1 eventos']),
        ('negativa: hubo otro cambio después (la jerarquía ya no es la medida)',
         MONTAJE + f"update crm.equipo set supervisor_id = '{S3}' where perfil_id = '{V}';\n"
         f"update crm.equipo set supervisor_id = '{S2}' where perfil_id = '{V}';\n" + do + 'rollback;\n',
         ['PREFLIGHT: la jerarquía de hoy ya no es la medida (1 de 2']),
        ('reversa: borra los dos eventos y la repetición no hace nada',
         MONTAJE + do + reversa_banco() + verificar + reversa_banco() + 'rollback;\n',
         ['Reversa del relleno hecha: 2 eventos borrados', 'EVENTOS=0', 'no hay eventos que borrar']),
        ('negativa de la reversa: un evento alterado',
         MONTAJE + do + f"update crm.usuario_eventos set creado_en = creado_en + interval '1 second'"
         f" where idempotencia = '{I1}';\n" + reversa_banco() + 'rollback;\n',
         ['REVERSA: 2 eventos con la idempotencia del relleno, 1 exactos']),
        ('negativa de la reversa: solo cambia el supervisor nuevo de un evento (Codex r1)',
         MONTAJE + do + f"update crm.usuario_eventos set detalle = jsonb_set(detalle, '{{supervisor_nuevo}}', '\"{S3}\"')"
         f" where idempotencia = '{I1}';\n" + reversa_banco() + 'rollback;\n',
         ['REVERSA: 2 eventos con la idempotencia del relleno, 1 exactos']),
    ]
    fallos = 0
    b = concurrencia(texto)
    ok = b.count('canceling statement due to lock timeout') == 2
    b_mutante = concurrencia(texto, con_candados=False)
    ok_mutante = 'lock timeout' not in b_mutante
    for nombre, bien, salida in (('concurrencia: con los candados, cambio de jerarquía y evento simultáneos esperan', ok, b),
                                 ('concurrencia (mutante sin candados): pasan, la prueba muerde', ok_mutante, b_mutante)):
        fallos += not bien
        print(('PASS ' if bien else 'FAIL ') + nombre)
        if not bien:
            print('  salida:', salida[:1500])
    for nombre, sql, esperado in casos:
        salida = correr(sql)
        ok = all(e in salida for e in esperado)
        if 'ERROR' in salida and not any(e.startswith(('ORÁCULO', 'PREFLIGHT', 'ENSAYO', 'REVERSA')) for e in esperado):
            ok = False
        fallos += not ok
        print(('PASS ' if ok else 'FAIL ') + nombre)
        if not ok:
            print('  esperado:', esperado)
            print('  salida:', '\n    '.join(l for l in salida.splitlines() if l.strip())[:3000])
    print(f'{len(casos) + 2 - fallos}/{len(casos) + 2} casos PASS')
    sys.exit(1 if fallos else 0)


if __name__ == '__main__':
    main()

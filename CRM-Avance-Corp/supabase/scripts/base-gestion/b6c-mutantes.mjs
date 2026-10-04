// B6c · mutantes de la suite b6c-nota-veto.sql: cada uno neutraliza UNA defensa de la migración 20261004123611 (el sello de
// la nota del veto o el nuevo orden de levantar_no_contactar) y la suite tiene que FALLAR en el caso que la prueba. Si un
// mutante sobrevive, esa defensa NO está probada. Todo corre en la transacción de la suite, que termina en ROLLBACK: el banco
// no cambia. Solo apunta a un banco LOCAL (127.0.0.1) con B6c aplicada y los actores de seed:demo; no acepta URL ni
// credenciales (la contraseña es la del Postgres local de Docker, PGPASSWORD; por defecto «postgres»).
// Uso: node supabase/scripts/base-gestion/b6c-mutantes.mjs --puerto 58122 [--solo-suite]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b6c-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is not null
  and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta'))::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B6c aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b6c-nota-veto.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004123611_crm_base_gestion_reservar_nota_veto.sql', AQUI), 'utf8');
const b2 = readFileSync(new URL('../../migrations/20261002061500_crm_base_gestion_no_contactar_supervisor.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (texto, inicio) => {
  const i = texto.indexOf(inicio);
  if (i < 0 || texto.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = texto.indexOf('$function$;', texto.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return texto.slice(i, j).replace(/^create (or replace )?function/, 'create or replace function');
};
const FUENTES = {
  sello: bloque(migracion, 'create function private.trg_actividades_no_contactar_solo_puerta()'),
  levantar: bloque(migracion, 'create or replace function crm.levantar_no_contactar('),
};
const LEVANTAR_B2 = bloque(b2, 'create or replace function crm.levantar_no_contactar(');
const TRIGGER = (eventos) => 'drop trigger trg_00_actividades_no_contactar_solo_puerta on crm.actividades;\n'
  + `create trigger trg_00_actividades_no_contactar_solo_puerta before ${eventos} on crm.actividades for each row execute function private.trg_actividades_no_contactar_solo_puerta();`;
const NUEVA = "      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \\t\\r\\n')) = 'no_contactar';\n";
const VIEJA = "      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \\t\\r\\n')) = 'no_contactar';\n";
const SIN_USUARIO = "  if (select auth.uid()) is null then\n";

const MUTANTES = [
  { nombre: 'sin el sello (drop trigger): vuelve el riesgo P2b de B6b', ddl: 'drop trigger trg_00_actividades_no_contactar_solo_puerta on crm.actividades;', cae: /^A1 / },
  { nombre: 'levantar apaga la válvula ANTES de su nota (el texto de B2)', ddl: LEVANTAR_B2, cae: /^L1 / },
  { nombre: 'el sello deja pasar accion = levantar', objeto: 'sello', buscar: NUEVA,
    poner: NUEVA.replace("= 'no_contactar';", "= 'no_contactar' and coalesce(new.metadata->>'accion', '') <> 'levantar';"), cae: /^A2 / },
  { nombre: 'el sello solo mira accion = marcar (evento sin acción pasa)', objeto: 'sello', buscar: NUEVA,
    poner: NUEVA.replace("= 'no_contactar';", "= 'no_contactar' and new.metadata->>'accion' = 'marcar';"), cae: /^A3 / },
  { nombre: 'el sello no exime la válvula de las puertas (rompe marcar/levantar/postventa)', objeto: 'sello',
    buscar: "  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then\n    v_exento := true;  -- la válvula de las puertas del veto\n", poner: '', cae: /^F1 / },
  { nombre: 'el sello no exime las sesiones sin usuario (rompe migraciones y backfills)', objeto: 'sello',
    buscar: SIN_USUARIO, poner: '  if false then  -- mutante: la sesión sin usuario ya no está exenta (la válvula sí)\n', cae: /^S1 / },
  { nombre: 'el sello exime por el rol del JWT (service_role con usuario pasa)', objeto: 'sello', buscar: SIN_USUARIO,
    poner: "  if (select auth.uid()) is null or coalesce(nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb->>'role', '') = 'service_role' then\n", cae: /^S3 / },
  { nombre: 'el sello solo en INSERT (un UPDATE de la metadata pasa)', ddl: TRIGGER('insert'), cae: /^U2 / },
  { nombre: 'el sello no mira la fila vieja (quitar el evento pasa)', objeto: 'sello',
    buscar: "    if tg_op <> 'INSERT' and not v_veto then\n" + VIEJA + '    end if;\n', poner: '', cae: /^U4 / },
  { nombre: 'levantar ya no apaga la válvula (queda encendida para el resto de la transacción)', objeto: 'levantar',
    buscar: "          v_uid);\n  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);\n\n  return", poner: "          v_uid);\n\n  return", cae: /^L3 / },
  { nombre: 'la reserva depende de la bandera resolver_en_puertas', objeto: 'sello', buscar: SIN_USUARIO,
    poner: "  if not coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false) then\n    return new;\n  end if;\n" + SIN_USUARIO, cae: /^O2 / },
  // r1 (auditor-rls r1, P3): inmutable y variantes.
  { nombre: 'el sello solo vigila la metadata en un UPDATE (otra columna pasa: r0)', ddl: TRIGGER('insert or update of metadata or delete'), cae: /^U8 / },
  { nombre: 'el sello no cubre DELETE (borrar la nota pasa)', ddl: TRIGGER('insert or update'), cae: /^U11 / },
  { nombre: 'el sello compara la forma EXACTA (sin minúsculas ni recorte): la variante No_Contactar pasa', objeto: 'sello', buscar: NUEVA,
    poner: "      v_veto := coalesce(new.metadata->>'evento', '') = 'no_contactar';\n", cae: /^A9 / },
  { nombre: 'el sello no recorta espacios (la variante « no_contactar » pasa)', objeto: 'sello', buscar: NUEVA,
    poner: "      v_veto := pg_catalog.lower(coalesce(new.metadata->>'evento', '')) = 'no_contactar';\n", cae: /^A10 / },
  { nombre: 'el sello compara la fila vieja en forma exacta (cambiar una nota del veto con variante pasa)', objeto: 'sello', buscar: VIEJA,
    poner: "      v_veto := coalesce(old.metadata->>'evento', '') = 'no_contactar';\n", cae: /^U13 / },
];

const correr = (ddl) => {
  const r = psql(suite.replace('-- @@MUTANTE@@', ddl));
  const lineas = (r.stdout || '').split('\n');
  return { status: r.status, fallos: lineas.filter((l) => l.startsWith('FAIL ')), total: lineas.find((l) => l.startsWith('TOTAL:')) ?? '(sin total)', err: (r.stderr || '').trim().split('\n').slice(-2).join(' | ') };
};

const base = correr('-- sin mutante');
console.log(`suite sin mutante: ${base.total} (salida ${base.status})`);
if (base.status !== 0 || base.fallos.length) {
  for (const f of base.fallos) console.log(`  ${f}`);
  console.error(`ABORTADO: la suite sin mutante no pasa (${base.err})`);
  process.exit(1);
}
if (args.includes('--solo-suite')) process.exit(0);

let vivos = 0;
for (const m of MUTANTES) {
  let ddl = m.ddl;
  if (m.objeto) {
    const fuente = FUENTES[m.objeto];
    if (fuente.split(m.buscar).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez en ${m.objeto}`);
    ddl = fuente.replace(m.buscar, m.poner);
  }
  const r = correr(ddl);
  const casos = r.fallos.map((l) => l.slice(5).split(' · esperado ')[0]);
  const cayoDonde = casos.some((c) => m.cae.test(c));
  if (r.status !== 0 && cayoDonde) console.log(`CAE  ${m.nombre} — ${r.total}; entre ellos el esperado (${casos.filter((c) => m.cae.test(c)).join(' / ')})`);
  else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; casos en FAIL: ${casos.join(' / ') || 'ninguno'} ${r.err}`); }
}
console.log(vivos === 0 ? `MUTANTES: ${MUTANTES.length}/${MUTANTES.length} caen` : `MUTANTES: ${vivos} de ${MUTANTES.length} SOBREVIVEN`);
process.exit(vivos === 0 ? 0 : 1);

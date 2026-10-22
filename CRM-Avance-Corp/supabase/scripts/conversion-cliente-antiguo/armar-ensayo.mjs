#!/usr/bin/env node
// Arma el ENSAYO de «Convertir a un cliente antiguo sin ficha de persona usa su misma ficha» (plan AVANCE-BACKEND-0810-F2, fase 2,
// bloque 2.10; D-38) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega, en el ORDEN DE INSTALACIÓN que fijó el Director (2.8 → 2.9 → 2.11 → 2.16 → 2.10), las migraciones del 2.11 y del 2.16 (el
// laboratorio no las tiene), la migración REAL de este bloque (menos sus `begin;`/`commit;`) y el oráculo dentro de UNA transacción que
// termina en `rollback`: se prueba el cuerpo que se va a publicar —preflight, postflight y comentarios incluidos—, no una copia. La base
// de partida es el laboratorio igual a producción CON los siete bloques de la fase 2 aplicados (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8
// ronda 4); el 2.9, el 2.11 y el 2.16 NO están aplicados. Esta migración no depende de ninguno: `--sin-211` y `--sin-216` lo prueban.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node …/armar-ensayo.mjs                                   → 2.11 + 2.16 + migración + oráculo (VERDE)
//   node …/armar-ensayo.mjs --sin-migracion                   → 2.11 + 2.16 + solo el oráculo (ROJO: mide el defecto)
//   node …/armar-ensayo.mjs --sin-211 --sin-216               → sin las dos de delante (la migración no depende de ellas)
//   node …/armar-ensayo.mjs --mutante m.sql                   → … + migración + mutante + oráculo (ROJO, nombrando su fallo)
//   node …/armar-ensayo.mjs --oraculo 24|27|28|29|211|216|conv [--sin-migracion] [--mutante m.sql]
//                                                             → … (+ migración) [+ mutante] + el oráculo del 2.4 (modo 2.7 «con», SIN
//                                                               el fixture B7), del 2.7, del 2.8, del 2.9 (con SU migración delante de
//                                                               todo), del 2.11, del 2.16 o el de la conversión unificada (`conv`:
//                                                               supabase/scripts/conversion-inversion/test-conversion.sql, con un
//                                                               lead más sembrado por el alta real: el laboratorio tiene 5 y pide 6)
//   node …/armar-ensayo.mjs --reversa                         → … + migración + reversa + huellas de antes (VERDE)
//   node …/armar-ensayo.mjs --reversa-lifo                    → 2.11 + 2.16 + migración + reversa + reversa del 2.16 + reversa del
//                                                               2.11: todo vuelve al punto de partida del laboratorio (VERDE)
//   node …/armar-ensayo.mjs --reversa-ajena 211|216           → 2.11 (+ 2.16) + migración + la reversa del 2.11 (sin el 2.16) o del
//                                                               2.16: tiene que ENTRAR (esta migración no toca lo que ellas fijan)
//   node …/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                             → … + migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                               (sin --espera, con un archivo vacío: control, la reversa entra)
//   node …/armar-ensayo.mjs --deriva d.sql --espera "<texto>" → deriva ANTES de la migración (y después del 2.11 y el 2.16): su
//                                                               preflight tiene que negarse sin rastro
//   node …/armar-ensayo.mjs --deriva vacio.sql                → control: sin deriva, la migración entra
//   node …/armar-ensayo.mjs --trinquetes [--sin-migracion]    → … (+ migración) + foto de los private.assert_* y del censo
//   node …/armar-ensayo.mjs --espera-a | --espera-b [--mutante m.sql]
//                                                             → las dos sesiones de `espera.sh` (A retiene el candado del documento
//                                                               de un DNI; B, con la migración, convierte con ese DNI y espera)
//   … --migracion <ruta> · --pruebas <ruta> · --reversa-archivo <ruta>   (modificadores: otra migración, otro oráculo, otra reversa)
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes y --oraculo conv, que terminan en rollback): eso es el veredicto.
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const dirMigraciones = resolve(aqui, '../../migrations')
const args = process.argv.slice(2)
function valorDe(bandera, que) {
  const i = args.indexOf(bandera)
  if (i < 0) return null
  if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`${bandera} necesita ${que}`)
  return args[i + 1]
}
const pruebas = resolve(valorDe('--pruebas', 'la ruta del oráculo') ?? resolve(aqui, 'pruebas.sql'))
const reversa = resolve(valorDe('--reversa-archivo', 'la ruta de la reversa') ?? resolve(aqui, 'reversa.sql'))
const reversa211 = resolve(aqui, '../reactivar-reconoce-cliente/reversa.sql')
const reversa216 = resolve(aqui, '../puertas-reconocen-cliente/reversa.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')
const AJENOS = {
  24: resolve(aqui, '../reactivar-lead-retirado/pruebas.sql'),
  27: resolve(aqui, '../cliente-por-telefono/pruebas.sql'),
  28: resolve(aqui, '../cliente-no-se-duplica-al-editar/pruebas.sql'),
  29: resolve(aqui, '../bases-alternativo-cliente/pruebas.sql'),
  211: resolve(aqui, '../reactivar-reconoce-cliente/pruebas.sql'),
  216: resolve(aqui, '../puertas-reconocen-cliente/pruebas.sql'),
  conv: resolve(aqui, '../conversion-inversion/test-conversion.sql'),
}

// Una migración se localiza por su nombre (el sello de tiempo lo fija quien integra): exactamente UNA.
function rutaDelRepo(patron, nombre) {
  const m = readdirSync(dirMigraciones).filter((f) => patron.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración ${nombre} y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}
const rutaMigracionDelRepo = () => rutaDelRepo(/^\d{14}_crm_conversion_cliente_antiguo_misma_ficha\.sql$/, '*_crm_conversion_cliente_antiguo_misma_ficha.sql')
const rutaMigracion211 = () => rutaDelRepo(/^\d{14}_crm_reactivar_reconoce_cliente\.sql$/, '*_crm_reactivar_reconoce_cliente.sql (bloque 2.11)')
const rutaMigracion216 = () => rutaDelRepo(/^\d{14}_crm_puertas_reconocen_cliente\.sql$/, '*_crm_puertas_reconocen_cliente.sql (bloque 2.16)')
const rutaMigracion29 = () => rutaDelRepo(/^\d{14}_crm_bases_alternativo_cliente\.sql$/, '*_crm_bases_alternativo_cliente.sql (bloque 2.9)')

// Huellas ANTES de la migración (las del laboratorio = producción + siete bloques; ni el 2.11 ni el 2.16 tocan estas tres; medidas con
// q.py el 10/10/2026 y verificadas byte a byte) y las que deja la migración (las que sella su postflight y exige la reversa).
const ANTES = {
  // RESELLE C2 (22/10/2026): la puerta re-asentada contra producción del 22/10 (antes d1c9358d…/b40dded8…; 20261019001700 «recorrido»).
  puerta: { prosrc: '4eebf912d4abc0b101e3c39688dc0c54', def: 'df451bd3cc831e2b47a26eb867c9e65e', com: 'd41d8cd98f00b204e9800998ecf8427e' },
  escritura: { prosrc: 'b67d8181139ab76ff9232523a67dfa11', def: 'dcc540a48b7f252c783f814f6a184144', com: '5e0226384bc1c2db4fa72bb8dad54fff' },
  lectura: { prosrc: 'b1106c6c67be483f8fb655a276e3def4', def: '477d0e80266faa6add30929337f00701', com: '84620ea87a16f7610aa05d3a636b3623' },
}
const FIRMAS = {
  puerta: "'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure",
  escritura: "'private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure",
  lectura: "'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure",
}
const ABSORBER = "to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)')"
const HISTORIA = "to_regprocedure('private.lead_historia_de_persona(uuid,uuid)')"

const sinMigracion = args.includes('--sin-migracion')
const sin211 = args.includes('--sin-211')
const sin216 = args.includes('--sin-216')
const conReversa = args.includes('--reversa')
const conReversaLifo = args.includes('--reversa-lifo')
const reversaAjena = valorDe('--reversa-ajena', '«211» o «216»')
if (reversaAjena != null && !['211', '216'].includes(reversaAjena)) throw new Error('--reversa-ajena necesita «211» o «216»')
const conTrinquetes = args.includes('--trinquetes')
const esperaA = args.includes('--espera-a')
const esperaB = args.includes('--espera-b')
const oraculo = valorDe('--oraculo', '«24», «27», «28», «29», «211», «216» o «conv»')
if (oraculo != null && !Object.keys(AJENOS).includes(oraculo)) throw new Error('--oraculo necesita «24», «27», «28», «29», «211», «216» o «conv»')
const mutante = valorDe('--mutante', 'la ruta del archivo SQL del mutante')
const deriva = valorDe('--deriva', 'la ruta del archivo SQL de la deriva')
const reversaDeriva = valorDe('--reversa-deriva', 'la ruta del archivo SQL de la deriva')
const espera = valorDe('--espera', 'el texto que debe abortar')
if (espera != null && deriva == null && reversaDeriva == null) throw new Error('--espera acompaña a --deriva o a --reversa-deriva')
const modos = [conReversa, conReversaLifo, reversaAjena != null, mutante != null && oraculo == null && !esperaB, deriva != null, reversaDeriva != null,
  conTrinquetes, oraculo != null, esperaA, esperaB].filter(Boolean).length
if (modos > 1) throw new Error('--reversa, --reversa-lifo, --reversa-ajena, --mutante, --deriva, --reversa-deriva, --trinquetes, --oraculo y --espera-a/-b no se combinan (salvo --oraculo o --espera-b con --mutante)')
if (sinMigracion && (conReversa || conReversaLifo || reversaAjena != null || (mutante != null && oraculo == null) || deriva != null || reversaDeriva != null || esperaA || esperaB)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo')
}
if ((sin211 && !sin216) && (conReversaLifo || reversaAjena === '216')) throw new Error('el 2.16 exige el 2.11 delante: --sin-211 obliga a --sin-216')
const rutaMigracion = valorDe('--migracion', 'la ruta del archivo SQL')
const migracion = rutaMigracion ? resolve(rutaMigracion) : (sinMigracion || esperaA ? null : rutaMigracionDelRepo())

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.10) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción lo pone este guion: si se colara el `commit;` de una migración (o de una reversa), el ensayo dejaría
// la puerta REEMPLAZADA en la base —exactamente lo que este archivo existe para evitar (incidente H-27 del 2.4)—.
function exigirSinCommit(ruta, sql) {
  if (/^\s*commit\s*;/im.test(sql)) throw new Error(`Queda un commit suelto en ${ruta}: el ensayo escribiría en la base`)
}
function sinTransaccion(ruta) {
  const lineas = readFileSync(ruta, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|commit)\s*;\s*$/i.test(l))
  if (cuerpo.length === lineas.length) throw new Error(`${ruta} no trae begin;/commit;: revisar antes de ensayar`)
  exigirSinCommit(ruta, cuerpo.join('\n'))
  return cuerpo.join('\n')
}
function leerSinCommit(ruta) {
  const sql = readFileSync(ruta, 'utf8')
  exigirSinCommit(ruta, sql)
  return sql
}
function exigirSinEtiquetas(sql, etiquetas, donde) {
  for (const etiqueta of etiquetas) {
    if (sql.includes(etiqueta)) throw new Error(`La etiqueta ${etiqueta} aparece en ${donde}: el envoltorio se rompería`)
  }
}
// Un oráculo de otro bloque se pega tal cual, sin su begin/rollback si los trajera (los nuestros los pone este guion).
function oraculoAjeno(ruta) {
  const sql = readFileSync(ruta, 'utf8').split('\n').filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(ruta, sql)
  return sql
}
// Las de delante, en el orden de instalación: 2.11 y después 2.16 (que exige el 2.11). `--sin-211`/`--sin-216` las quitan.
// C3 ronda 2 (22/10/2026): el 2.16 quedó fuera de la tanda y puede no estar en migrations/. Si falta, el modo por defecto no lo pega (como
// --sin-216) y lo avisa; lo que lo exige (--reversa-lifo, --reversa-ajena 216, --oraculo 216) sigue fallando sin él.
const hay216 = readdirSync(dirMigraciones).some((f) => /^\d{14}_crm_puertas_reconocen_cliente\.sql$/.test(f))
if (!hay216 && !sin216) process.stderr.write('AVISO (2.10): no hay *_crm_puertas_reconocen_cliente.sql (2.16) en migrations/: se arma sin el 2.16, como con --sin-216\n')
function previos({ con211 = !sin211, con216 = !sin216 && hay216 } = {}) {
  const partes = []
  if (con211) partes.push(sinTransaccion(rutaMigracion211()))
  if (con216) partes.push(sinTransaccion(rutaMigracion216()))
  return partes
}

// FOTO de todo lo que la migración (o la reversa) puede mover y de lo que no debe mover: la puerta, los dos núcleos y las dos piezas
// (definición, dueño, ACL, comentario), más lo que las rodea (el envoltorio del contexto, la pieza del 2.8, la puerta de enlace de
// Gerencia, el resolver, el puente) y las piezas del 2.11 y del 2.16 (para el orden LIFO). Para saber si una deriva o una reversa que se
// niega dejaron la base EXACTAMENTE como estaba.
const FICHA = (firma) => `coalesce((select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
            || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${firma}), 'AUSENTE')`
const FOTO = `md5(concat_ws(' ## ',
    ${FICHA(FIRMAS.puerta)},
    ${FICHA(FIRMAS.escritura)},
    ${FICHA(FIRMAS.lectura)},
    ${FICHA(ABSORBER)},
    ${FICHA(HISTORIA)},
    ${FICHA("to_regprocedure('private.inversion_persona_contexto(uuid,uuid)')")},
    ${FICHA("to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)')")},
    ${FICHA("to_regprocedure('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)')")},
    ${FICHA("to_regprocedure('private.inversionista_resolver(text,text,boolean,text)')")},
    ${FICHA("to_regprocedure('private.trg_leads_zz_puente_identidad()')")},
    ${FICHA("to_regprocedure('private.leads_de_personas(uuid[])')")},
    ${FICHA("to_regprocedure('private.juicio_cliente_conservado(uuid)')")},
    ${FICHA("to_regprocedure('crm.reabrir_lead_fn(uuid)')")},
    ${FICHA("to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)')")}))`
const HUELLA = (clave) => `(select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = ${FIRMAS[clave]})`
const HUELLA_ANTES = (clave) => `'${ANTES[clave].prosrc}/${ANTES[clave].def}/${ANTES[clave].com}'`
const TODAS_ANTES = Object.keys(ANTES).map((k) => `${HUELLA(k)} = ${HUELLA_ANTES(k)}`).join('\n              and ')

// DERIVA PREVIA. Una deriva se instala ANTES de la migración (y después del 2.11 y el 2.16) y prueba su PREFLIGHT: si el catálogo ya no
// es el auditado, la migración tiene que negarse y dejarlo todo como estaba. La migración corre dentro de un bloque que captura su
// aborto, para mirar la foto después y dar un veredicto de máquina: VERDE solo si abortó con el mensaje esperado (`--espera`) y la foto
// es idéntica. Sin `--espera` es el control: sin deriva, la migración entra y deja la puerta y los núcleos con su cuerpo nuevo y las dos
// piezas creadas. El archivo de la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración («ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes
              and v_puerta <> '${ANTES.puerta.prosrc}' and v_escritura <> '${ANTES.escritura.prosrc}' and v_lectura <> '${ANTES.lectura.prosrc}'
              and ${ABSORBER} is not null and ${HISTORIA} is not null then 'VERDE' else 'ROJO' end`
  const sqlDeriva = leerSinCommit(resolve(deriva)).replace('-- @@MIGRACION@@', () => sqlMigracion)
  return [
    ...CABECERA,
    ...previos(),
    sqlDeriva,
    '\\echo DERIVA_INSTALADA',
    `do $deriva$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
  v_puerta text; v_escritura text; v_lectura text;
begin
  v_foto_antes := ${FOTO};
  begin
    execute $migracion$
${sqlMigracion}
$migracion$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  select md5(p.prosrc) into v_puerta from pg_proc p where p.oid = ${FIRMAS.puerta};
  select md5(p.prosrc) into v_escritura from pg_proc p where p.oid = ${FIRMAS.escritura};
  select md5(p.prosrc) into v_lectura from pg_proc p where p.oid = ${FIRMAS.lectura};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\npuerta después: % (antes ${ANTES.puerta.prosrc}) · escritura: % (antes ${ANTES.escritura.prosrc}) · lectura: % (antes ${ANTES.lectura.prosrc}) · piezas: %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_puerta, v_escritura, v_lectura,
    case when ${ABSORBER} is not null and ${HISTORIA} is not null then 'presentes' when ${ABSORBER} is null and ${HISTORIA} is null then 'ausentes' else 'A MEDIAS' end,
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de la migración' else 'DISTINTA de la de antes de la migración' end;
end;
$deriva$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDeTrinquetes() {
  const lineas = readFileSync(trinquetes, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(trinquetes, cuerpo)
  const partes = [...CABECERA, ...previos()]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  partes.push(cuerpo, 'rollback;', '')
  return partes.join('\n')
}

// LOS ORÁCULOS AJENOS ENCIMA (sin tocarlos). El del 2.4 se arma como en una base que YA tiene el 2.7 (modo «con») y SIN el fixture B7.
// El del 2.8 corre sobre un laboratorio que YA tiene el 2.8 (su caso C6 fija la huella de hoy de la puerta: con esta migración cambia).
// El del 2.9 lleva DELANTE de todo la migración del 2.9. Los del 2.11 y del 2.16 corren con sus migraciones delante (siempre). El de la
// conversión unificada (`conv`) pide seis leads activos sin DNI ni persona y el laboratorio tiene cinco: se siembra UNO más por el alta
// real (VEND1, número del bloque de este ensayo) antes de pegarlo; termina en rollback y su veredicto son sus dos `PASS:`.
function ensayoDeOraculoAjeno() {
  const partes = [...CABECERA]
  if (oraculo === '29') partes.push(sinTransaccion(rutaMigracion29()))
  partes.push(...previos())
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  if (oraculo === '24') {
    partes.push(`do $b7$
begin
  if (select a.attnotnull from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado' and not a.attisdropped)
     or to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null then
    raise exception 'ENSAYO ABORTADO: el laboratorio no tiene el esquema B7 (bases cargadas): el oráculo del 2.4 necesitaría su fixture';
  end if;
end
$b7$;`)
    partes.push(`select set_config('ensayo.modo_2_7', 'con', true);`)
  }
  if (oraculo === 'conv') {
    partes.push(`do $conv$
declare v_vend1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND1'); v_r jsonb;
begin
  if v_vend1 is null then raise exception 'ENSAYO ABORTADO: falta PASO08 VEND1'; end if;
  if exists (select 1 from crm.leads l where l.telefono = '+51924099990') then raise exception 'ENSAYO ABORTADO: el número +51 924 099990 no está libre'; end if;
  perform set_config('request.jwt.claim.sub', v_vend1::text, true),
          set_config('request.jwt.claims', json_build_object('sub', v_vend1, 'role', 'authenticated')::text, true);
  v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'ENS210 SEXTO LEAD DEL ORACULO DE CONVERSION', p_telefono => '924099990',
                                      p_origen => 'formulario', p_monto_estimado => 5000, p_moneda => 'PEN');
  perform set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
  if v_r ->> 'estado' is distinct from 'creado' then raise exception 'ENSAYO ABORTADO: no se pudo sembrar el sexto lead (%)', v_r; end if;
end
$conv$;`)
  }
  partes.push(oraculoAjeno(AJENOS[oraculo]))
  partes.push('rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA. previos → aplicar → una deriva posterior → intentar la reversa: tiene que ABORTAR en su preflight con el mensaje
// esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla. Sin `--espera` (archivo vacío) es el control: la reversa
// tiene que entrar y devolver la puerta y los núcleos de antes y borrar las piezas.
function ensayoDeReversaDeriva() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcd$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(espera ?? '', ['$reversa_sql$', '$rcd$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and ${TODAS_ANTES} and ${ABSORBER} is null and ${HISTORIA} is null then 'VERDE' else 'ROJO' end`
  return [
    ...CABECERA,
    ...previos(),
    sinTransaccion(migracion),
    leerSinCommit(resolve(reversaDeriva)),
    '\\echo DERIVA_INSTALADA',
    `do $rcd$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
begin
  v_foto_antes := ${FOTO};
  begin
    execute $reversa_sql$
${sqlReversa}
$reversa_sql$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  raise exception E'REVERSA CON DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: revirtió'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa' else 'DISTINTA de la de antes de intentar la reversa' end;
end;
$rcd$;`,
    'rollback;',
    '',
  ].join('\n')
}

// LA REVERSA DE OTRO BLOQUE CON EL 2.10 ENCIMA: tiene que ENTRAR (esta migración no toca nada de lo que fijan el 2.11 ni el 2.16) y
// dejar intactas la puerta, los núcleos y las piezas de este bloque.
function ensayoReversaAjena() {
  const con216 = reversaAjena === '216'
  const sqlAjena = sinTransaccion(con216 ? reversa216 : reversa211)
  exigirSinEtiquetas(sqlAjena, ['$raj$', '$revaj$'], 'la reversa ajena')
  return [
    ...CABECERA,
    ...previos({ con211: true, con216 }),
    sinTransaccion(migracion),
    `do $revaj$
declare
  v_aborto text;
  v_mias_antes text;
  v_mias_despues text;
  v_foto_antes text;
  v_foto_despues text;
begin
  v_mias_antes := ${HUELLA('puerta')} || ' ' || ${HUELLA('escritura')} || ' ' || ${HUELLA('lectura')} || ' ' || ${FICHA(ABSORBER)} || ' ' || ${FICHA(HISTORIA)};
  v_foto_antes := ${FOTO};
  begin
    execute $raj$
${sqlAjena}
$raj$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_mias_despues := ${HUELLA('puerta')} || ' ' || ${HUELLA('escritura')} || ' ' || ${HUELLA('lectura')} || ' ' || ${FICHA(ABSORBER)} || ' ' || ${FICHA(HISTORIA)};
  v_foto_despues := ${FOTO};
  raise exception E'REVERSA DEL ${con216 ? '2.16' : '2.11'} CON EL 2.10 ENCIMA %:\\n%\\nlo del 2.10 %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_aborto is null and v_mias_despues = v_mias_antes and v_foto_despues <> v_foto_antes then 'VERDE (entró; el 2.10 no la bloquea ni cambia)' else 'ROJO' end,
    coalesce('la reversa ajena ABORTÓ: ' || v_aborto, 'la reversa ajena NO abortó: revirtió lo suyo'),
    case when v_mias_despues = v_mias_antes then 'INTACTO (puerta, núcleos y piezas con sus huellas)' else 'CAMBIÓ' end,
    case when v_foto_despues = v_foto_antes then 'IGUAL (la reversa ajena no cambió nada: sospechoso)' else 'DISTINTA (la reversa ajena hizo lo suyo)' end;
end;
$revaj$;`,
    'rollback;',
    '',
  ].join('\n')
}

// ESPERA ENTRE DOS SESIONES (`espera.sh`). Sesión A: toma el candado del DOCUMENTO de un DNI fijo (la misma clave que toma la puerta de
// conversión y el resolver: `inv_resolver:DNI:<dni>`; lo que tomaría otra conversión con ese DNI o la puerta del DNI de la ficha) y lo
// retiene unos segundos, mirando en pg_locks si alguien espera por él. Sesión B: con la migración (o con un mutante), una conversión con
// ese DNI de un lead nuevo, con un cliente antiguo sin ficha (retirado) sembrado con ese DNI ⇒ B tiene que ESPERAR a A antes de juzgar y
// absorber, y absorber bien al soltarse. Las dos terminan en rollback. El DNI es fijo para que A y B lo compartan sin hablar entre ellas.
const DNI_ESPERA = '75299901'
function ensayoEsperaA() {
  return [
    ...CABECERA,
    `do $a$
declare
  v_t0 timestamptz := clock_timestamp(); v_vio boolean := false; v_pid integer; v_n integer := 0; i integer;
  v_clave bigint := hashtext('inv_resolver:DNI:${DNI_ESPERA}');
begin
  perform pg_advisory_xact_lock(v_clave);
  raise notice 'A: candado del documento DNI ${DNI_ESPERA} tomado';
  -- Retiene el candado hasta 45 s (B pega antes las migraciones del 2.11, del 2.16 y la de este bloque: sus postflights barren los
  -- trinquetes y tardan). En cuanto ve a alguien esperando por él, lo retiene 2,5 s más y lo suelta (B nunca llega al lock_timeout de
  -- 5 s de la puerta).
  for i in 1..450 loop
    perform pg_sleep(0.1);
    select l.pid into v_pid from pg_locks l where l.locktype = 'advisory' and not l.granted and l.objid = (v_clave & 4294967295)::oid and l.classid = ((v_clave >> 32) & 4294967295)::oid limit 1;
    if v_pid is null then
      select l.pid into v_pid from pg_locks l where l.locktype = 'advisory' and not l.granted and l.objid = (v_clave & 4294967295)::oid limit 1;
    end if;
    if v_pid is not null then
      v_vio := true;
      v_n := v_n + 1;
      exit when v_n >= 25;
    end if;
  end loop;
  raise exception 'ESPERA A: retuvo el candado % ms · espera vista: %',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000), case when v_vio then 'sí' else 'no' end;
end
$a$;`,
    'rollback;',
    '',
  ].join('\n')
}
function ensayoEsperaB() {
  const partes = [...CABECERA, ...previos(), sinTransaccion(migracion)]
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  partes.push(readFileSync(resolve(aqui, 'espera-b.sql'), 'utf8').replaceAll('@@DNI@@', DNI_ESPERA))
  partes.push('rollback;', '')
  return partes.join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversaLifo) {
    // La foto del PUNTO DE PARTIDA del laboratorio (antes del 2.11 y el 2.16): tras 2.11 → 2.16 → 2.10 → reversa 2.10 → reversa 2.16 →
    // reversa 2.11 tiene que volver.
    partes.push(`do $antes0$
begin
  perform set_config('ensayo.foto_laboratorio', ${FOTO}, true);
end;
$antes0$;`)
  }
  partes.push(...previos(conReversaLifo ? { con211: true, con216: true } : {}))
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('ensayo.foto_previa', ${FOTO}, true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa || conReversaLifo) {
    // Aplicar → revertir → todo vuelve: la puerta y los dos núcleos (cuerpo, definición, comentario), las piezas borradas y la FOTO
    // entera idéntica a la de antes de aplicar (con --reversa-lifo, además las reversas del 2.16 y del 2.11 y la foto del punto de
    // partida del laboratorio).
    partes.push(sinTransaccion(reversa))
    if (conReversaLifo) partes.push(sinTransaccion(reversa216), sinTransaccion(reversa211))
    const fotoRef = conReversaLifo ? 'ensayo.foto_laboratorio' : 'ensayo.foto_previa'
    partes.push(`do $huella$
declare
  v_p text; v_e text; v_l text;
begin
  v_p := ${HUELLA('puerta')}; v_e := ${HUELLA('escritura')}; v_l := ${HUELLA('lectura')};
  raise exception E'REVERSA${conReversaLifo ? ' LIFO (2.10, después 2.16 y después 2.11)' : ''} %:\\npuerta % (antes ${ANTES.puerta.prosrc}/${ANTES.puerta.def}/${ANTES.puerta.com})\\nescritura % (antes ${ANTES.escritura.prosrc}/${ANTES.escritura.def}/${ANTES.escritura.com})\\nlectura % (antes ${ANTES.lectura.prosrc}/${ANTES.lectura.def}/${ANTES.lectura.com})\\npiezas del 2.10: %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = ${HUELLA_ANTES('puerta')} and v_e = ${HUELLA_ANTES('escritura')} and v_l = ${HUELLA_ANTES('lectura')}
              and ${ABSORBER} is null and ${HISTORIA} is null
              and ${FOTO} = current_setting('${fotoRef}', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_e, v_l,
    case when ${ABSORBER} is null and ${HISTORIA} is null then 'borradas' else 'SIGUEN' end,
    case when ${FOTO} = current_setting('${fotoRef}', true)
         then 'IDÉNTICA a la de ${conReversaLifo ? 'ANTES del 2.11 (el punto de partida del laboratorio)' : 'antes de aplicar'} (la puerta, los núcleos, las piezas y lo que las rodea: definición, dueño, ACL y comentario)'
         else 'DISTINTA de la de ${conReversaLifo ? 'antes del 2.11' : 'antes de aplicar'}' end;
end;
$huella$;`)
  } else {
    if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
    partes.push(leerSinCommit(pruebas))
  }
  partes.push('rollback;', '')
  return partes.join('\n')
}

process.stdout.write(
  deriva != null ? ensayoDeDeriva()
    : reversaDeriva != null ? ensayoDeReversaDeriva()
    : reversaAjena != null ? ensayoReversaAjena()
    : conTrinquetes ? ensayoDeTrinquetes()
    : oraculo != null ? ensayoDeOraculoAjeno()
    : esperaA ? ensayoEsperaA()
    : esperaB ? ensayoEsperaB()
    : ensayoDelOraculo(),
)

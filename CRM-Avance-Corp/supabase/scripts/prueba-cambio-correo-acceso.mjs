// ¿PUEDE EL CLIENTE ENTRAR CON EL CORREO NUEVO? — la prueba que lo demuestra.
//
// Miguel preguntó exactamente eso el 08/09/2026, y la respuesta honesta era «no
// lo sé»: en producción hay 4 cuentas a las que YA se les cambió el correo con
// este mismo mecanismo y las tres piezas les quedaron alineadas, pero NINGUNA ha
// vuelto a iniciar sesión desde entonces, y `auth.audit_log_entries` está vacío.
// O sea: había evidencia de que el dato se mueve bien, y CERO evidencia de que
// la puerta se abra después. Esto último es lo único que importa, y esto lo mide.
//
// QUÉ HACE, sobre una cuenta DESECHABLE que crea y borra él mismo:
//   1. crea un usuario de Auth con una clave conocida (NO crea perfil: `auth.users`
//      no tiene ningún trigger, comprobado el 08/09 ⇒ no entra en ningún conteo
//      del negocio, ni clientes, ni cierre de mes);
//   2. inicia sesión con el correo VIEJO           → debe PASAR (línea base);
//   3. le cambia el correo igual que la edge `corregir-correo-cliente`:
//      `auth.admin.updateUserById({ email, email_confirm: true })`;
//   4. comprueba que las DOS piezas de Auth se movieron —`auth.users.email` y la
//      identidad de correo, que es donde GoTrue busca de verdad al usuario—;
//   5. inicia sesión con el correo NUEVO           → 🔑 LA PRUEBA;
//   6. inicia sesión con el correo VIEJO           → debe FALLAR (si siguiera
//      abriendo, el cambio no habría cerrado nada);
//   7. borra la cuenta, pase lo que pase.
//
// NO toca ningún cliente real, ningún contrato y ningún dato del negocio. Se
// puede correr durante el congelamiento: no aplica migraciones ni cambia esquema.
//
// Uso:
//   node supabase/scripts/prueba-cambio-correo-acceso.mjs --preflight
//   node supabase/scripts/prueba-cambio-correo-acceso.mjs --probar
//
// Variables:
//   Ninguna, si la CLI de Supabase está autenticada: el guion pide las llaves a
//   `supabase projects api-keys --reveal`, igual que `cambiar-dominio-correo-crm.mjs`.
//   El número de proyecto va por defecto y no es un secreto. Se puede forzar con
//   SUPABASE_PROJECT_REF, o saltarse la CLI exportando las llaves al entorno.

import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const HELP = `
¿Puede el cliente entrar con el correo nuevo? — prueba de punta a punta

  node supabase/scripts/prueba-cambio-correo-acceso.mjs --preflight   valida entorno, sin conectar
  node supabase/scripts/prueba-cambio-correo-acceso.mjs --probar      crea, prueba y borra

No requiere exportar secretos ni instalar nada: usa la CLI de Supabase
(o npx supabase si no está instalada). Si nunca te autenticaste:

  npx --yes supabase@latest login

Opcional: SUPABASE_PROJECT_REF para apuntar a otro proyecto.
`;

const args = new Set(process.argv.slice(2));
if (args.has('--help') || args.has('-h') || args.size === 0) {
  console.log(HELP.trim());
  process.exit(args.size === 0 ? 2 : 0);
}
const modos = ['--preflight', '--probar'].filter((m) => args.has(m));
if (modos.length !== 1) {
  console.error('Selecciona exactamente un modo: --preflight o --probar.');
  process.exit(2);
}

// El proyecto del CRM/portal. No es un secreto: aparece en la URL pública.
const PROYECTO_POR_DEFECTO = 'dctqcbznekcyxhjujuci';
const projectRef = process.env.SUPABASE_PROJECT_REF?.trim() || PROYECTO_POR_DEFECTO;
const url = process.env.SUPABASE_URL?.trim() || `https://${projectRef}.supabase.co`;
const supabaseCli = process.env.SUPABASE_CLI_BIN?.trim() || 'supabase';

function fallar(mensaje) {
  console.error(`✗ ${mensaje}`);
  process.exit(1);
}

try {
  const u = new URL(url);
  if (u.protocol !== 'https:') fallar('SUPABASE_URL debe usar HTTPS.');
  if (u.username || u.password || u.search || u.hash) {
    fallar('SUPABASE_URL no debe contener credenciales ni parámetros.');
  }
} catch {
  fallar('SUPABASE_URL no es una URL válida.');
}

/** Las llaves salen de la CLI ya autenticada, para no obligar a nadie a
 *  exportar secretos a mano (mismo mecanismo que cambiar-dominio-correo-crm.mjs).
 *  Si están en el entorno, mandan esas. */
function llavesDelProyecto() {
  const entornoAdmin = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  const entornoPublica = process.env.SUPABASE_ANON_KEY?.trim();
  if (entornoAdmin && entornoPublica) {
    return { admin: entornoAdmin, publica: entornoPublica };
  }

  // La CLI puede no estar instalada: se intenta el binario y, si no está, `npx`.
  // Así nadie tiene que instalar nada ni —sobre todo— pegar una llave de
  // servicio en un chat o en un comando, donde quedaría escrita para siempre.
  const argumentos = [
    'projects', 'api-keys', '--project-ref', projectRef, '--reveal', '--output', 'json',
  ];
  const opciones = { encoding: 'utf8', timeout: 180_000, maxBuffer: 2 * 1024 * 1024 };
  const intentos = [
    { cmd: supabaseCli, args: argumentos },
    { cmd: 'npx', args: ['--yes', 'supabase@latest', ...argumentos] },
  ];

  let r = null;
  for (const intento of intentos) {
    r = spawnSync(intento.cmd, intento.args, opciones);
    if (!r.error && r.status === 0) break;
  }
  if (!r || r.error || r.status !== 0) {
    const salida = `${r?.stderr ?? ''}${r?.stdout ?? ''}`.trim();
    const noAutenticada = /login|token|logged|acceso|unauthor/i.test(salida);
    fallar(noAutenticada || !salida
      ? 'La CLI de Supabase no está autenticada en esta máquina.\n'
        + '  Ejecuta UNA vez:  npx --yes supabase@latest login\n'
        + '  y vuelve a correr esto. NO pegues llaves en el chat ni en el comando:\n'
        + '  el guion las lee solo, y así no quedan escritas en ningún historial.'
      : `La CLI falló al pedir las llaves: ${salida.slice(0, 300)}`);
  }
  let payload;
  try {
    payload = JSON.parse(r.stdout);
  } catch {
    fallar('La CLI no devolvió un JSON reconocible para las API keys.');
  }
  const filas = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.keys) ? payload.keys : [];
  const valor = (f) => f?.api_key ?? f?.['key'] ?? f?.value;
  const admin = valor(filas.find((f) => f?.name === 'service_role'
    || f?.type === 'secret' || String(valor(f) ?? '').startsWith('sb_secret_')));
  const publica = valor(filas.find((f) => f?.name === 'anon'
    || f?.type === 'publishable' || String(valor(f) ?? '').startsWith('sb_publishable_')));
  if (typeof admin !== 'string' || admin.length < 20) {
    fallar('La CLI no devolvió una llave administrativa utilizable.');
  }
  if (typeof publica !== 'string' || publica.length < 20) {
    fallar('La CLI no devolvió la llave pública, necesaria para probar el inicio de sesión.');
  }
  return { admin: entornoAdmin || admin, publica: entornoPublica || publica };
}

if (args.has('--preflight')) {
  const llaves = llavesDelProyecto();
  console.log('✓ Entorno completo. Listo para --probar.');
  console.log(`  Proyecto: ${url}`);
  console.log(`  Llaves obtenidas: administrativa ${llaves.admin.slice(0, 7)}…`
    + ` · pública ${llaves.publica.slice(0, 7)}…`);
  process.exit(0);
}

const llaves = llavesDelProyecto();
const serviceKey = llaves.admin;
const anonKey = llaves.publica;

// Marca única e inconfundible: este guion NUNCA toca una cuenta que no haya
// creado él mismo, y el sufijo lo hace imposible de confundir con una real.
const marca = randomUUID().slice(0, 8);
const CORREO_VIEJO = `prueba-correo-${marca}@ejemplo-avancecorp.test`;
const CORREO_NUEVO = `prueba-correo-${marca}-nuevo@ejemplo-avancecorp.test`;
const CLAVE = `Pr#${randomUUID()}`;

const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

let resultados = [];
function paso(ok, texto, detalle = '') {
  resultados.push(ok);
  console.log(`${ok ? '✓' : '✗'} ${texto}${detalle ? ` — ${detalle}` : ''}`);
}

/** Un cliente ANÓNIMO nuevo por intento: así el login se prueba de verdad,
 *  desde cero, sin arrastrar la sesión de un intento anterior. */
async function intentarEntrar(email) {
  const anon = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data, error } = await anon.auth.signInWithPassword({ email, password: CLAVE });
  return { ok: !error && !!data?.session, error };
}

let userId = null;
try {
  // 1) La cuenta desechable.
  const { data: creado, error: crearErr } = await admin.auth.admin.createUser({
    email: CORREO_VIEJO,
    password: CLAVE,
    email_confirm: true,
  });
  if (crearErr || !creado?.user) fallar(`No se pudo crear la cuenta de prueba: ${crearErr?.message}`);
  userId = creado.user.id;
  console.log(`\nCuenta de prueba creada: ${CORREO_VIEJO}\n`);

  // 2) Línea base: con el correo viejo se entra.
  const base = await intentarEntrar(CORREO_VIEJO);
  paso(base.ok, 'LÍNEA BASE: entra con el correo original', base.error?.message ?? 'sesión abierta');

  // 3) El cambio, EXACTAMENTE como lo hace la edge.
  const { error: cambioErr } = await admin.auth.admin.updateUserById(userId, {
    email: CORREO_NUEVO,
    email_confirm: true,
  });
  paso(!cambioErr, 'El cambio de correo se aplica', cambioErr?.message ?? 'sin error');

  // 4) Las DOS piezas de Auth, no solo una. La identidad es la que usa GoTrue
  //    para encontrar al usuario al iniciar sesión: si `users` se moviera y la
  //    identidad no, el correo nuevo no abriría nada.
  const { data: leido } = await admin.auth.admin.getUserById(userId);
  const emailUsuario = leido?.user?.email ?? '';
  const identidad = (leido?.user?.identities ?? [])
    .find((i) => i.provider === 'email');
  const emailIdentidad = identidad?.identity_data?.email ?? '';
  paso(emailUsuario === CORREO_NUEVO, 'auth.users quedó con el correo nuevo', emailUsuario);
  paso(emailIdentidad === CORREO_NUEVO, 'la IDENTIDAD de acceso quedó con el correo nuevo', emailIdentidad || 'sin identidad de correo');
  paso(!!leido?.user?.email_confirmed_at, 'el correo nuevo queda CONFIRMADO (no pide verificación)');

  // 5) 🔑 LA PRUEBA: la puerta se abre con el correo nuevo.
  const nuevo = await intentarEntrar(CORREO_NUEVO);
  paso(nuevo.ok, '🔑 ENTRA CON EL CORREO NUEVO', nuevo.error?.message ?? 'sesión abierta');

  // 6) Y el viejo ya no abre nada.
  const viejo = await intentarEntrar(CORREO_VIEJO);
  paso(!viejo.ok, 'el correo ANTERIOR ya no abre la puerta', viejo.error?.message ?? 'ABRIÓ — el cambio no cerró nada');
} finally {
  // 7) Limpieza incondicional.
  if (userId) {
    const { error } = await admin.auth.admin.deleteUser(userId);
    console.log(error
      ? `\n⚠️  NO se pudo borrar la cuenta de prueba ${userId}: ${error.message} — bórrala a mano`
      : `\nCuenta de prueba borrada (${userId}).`);
  }
}

const fallos = resultados.filter((r) => !r).length;
if (fallos === 0) {
  console.log(`\n✅ PRUEBA_CORREO_OK: ${resultados.length}/${resultados.length}.`);
  console.log('   El cliente SÍ entra con el correo nuevo, y el anterior deja de servir.');
  process.exit(0);
}
console.error(`\n❌ PRUEBA_CORREO_FALLA: ${fallos} de ${resultados.length} comprobaciones en rojo.`);
console.error('   NO desplegar la corrección de correo hasta entender por qué.');
process.exit(1);

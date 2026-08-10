// Gate de REALIDAD: contrasta los supuestos con los que se construye y prueba
// el CRM contra lo que de verdad hay en la base.
//
// Por qué existe
// --------------
// Tres veces en dos días un cambio pasó el gate entero (1.500+ tests, e2e, RLS)
// y no hizo NADA en producción, siempre por la misma razón: los tests montan el
// mundo del FIXTURE —metas publicadas, cartera poblada, gate de leads abierto—
// y producción es otro mundo. El bug no estaba en el código: estaba en el
// mundo que el código daba por hecho.
//
//   · el ranking del supervisor se colgó de una vista que su rol no puede abrir;
//   · la campana se pintaba con una regla y se abría con otra;
//   · la columna de dólares del asesor se mostraba por «no se sabe», y resultó
//     que «no se sabe» es el estado de TODOS los días mientras nadie publique
//     metas.
//
// Este gate no prueba código: audita la DISTANCIA entre lo que el producto
// asume y lo que existe. Cada divergencia dice qué pantallas están hoy
// probándose contra un mundo que no está ahí fuera.
//
// Es de SOLO LECTURA y por eso —a diferencia del seed y de test-rls, que
// bloquean producción a propósito— aquí apuntar a producción es justamente el
// punto. No escribe una sola fila.
//
// Uso:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node supabase/scripts/gate-realidad.mjs
//   ... --json     salida legible por máquina (para CI)
//   ... --estricto  sale con código 1 si hay divergencias (por defecto: 0, es un aviso)

import { createClient } from '@supabase/supabase-js';

const ARGS = process.argv.slice(2);
const JSON_OUT = ARGS.includes('--json');
const ESTRICTO = ARGS.includes('--estricto');

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

function fatal(mensaje) {
  process.stderr.write(`✗ ${mensaje}\n`);
  process.exit(2);
}

if (!SUPABASE_URL) fatal('Falta SUPABASE_URL.');
if (!SERVICE_KEY) fatal('Falta SUPABASE_SERVICE_ROLE_KEY (lectura de conteos).');

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  db: { schema: 'crm' },
});

/**
 * Un SUPUESTO es algo que el front o los tests dan por cierto sin decirlo.
 * `medir` devuelve el número real; `esperado` describe lo que el producto
 * asume; `divergeSi` decide si eso es una divergencia digna de aviso.
 *
 * `afecta` es la parte importante: sin ella un conteo es trivia. Con ella, el
 * aviso dice qué pantalla está hoy probándose contra un mundo que no existe.
 */
const SUPUESTOS = [
  {
    clave: 'metas_publicadas',
    titulo: 'Hay una revisión de metas publicada',
    asume: 'Los fixtures (METAS_DEMO) dan metas a todos los vendedores, en PEN y en USD.',
    afecta: [
      'Hoy · asesor → «Tu cumplimiento del mes» (las 3 columnas de meta)',
      'Hoy · supervisor y gerencia → metas de equipo y empresa',
      'Ranking de vendedores (capital y conversión): sin meta no hay % de avance',
    ],
    consecuencia:
      'Sin metas, el store degrada a objetivosCero y el cumplimiento llega NULO. '
      + 'Toda lógica que distinga «no tiene meta» de «no pude leer la meta» está '
      + 'hoy en el primer caso, y ningún test que use el fixture lo ejerce.',
    async medir() {
      const { count, error } = await admin.from('meta_periodos')
        .select('id', { count: 'exact', head: true });
      if (error) throw error;
      return count ?? 0;
    },
    divergeSi: (n) => n === 0,
    esperado: '≥ 1 periodo con revisión publicada',
  },
  {
    clave: 'leads_en_cartera',
    titulo: 'La cartera tiene leads que trabajar',
    asume: 'Los fixtures siembran 7 leads y la demo ~20; las pantallas se prueban con lista llena.',
    afecta: [
      'Cartera → paginación keyset y «Cargar más» (con 1 lead nunca aparece)',
      'Pipeline → columnas del kanban',
      'Hoy · asesor → cola de acción y agenda',
    ],
    consecuencia:
      'Con la cartera casi vacía, «Nada pendiente» es el estado permanente: una '
      + 'pantalla rota y una pantalla vacía se ven IGUAL en producción.',
    async medir() {
      const { count, error } = await admin.from('leads')
        .select('id', { count: 'exact', head: true }).eq('activo', true);
      if (error) throw error;
      return count ?? 0;
    },
    divergeSi: (n) => n < 5,
    esperado: '≥ 5 leads activos',
  },
  {
    clave: 'actividades',
    titulo: 'Los leads tienen historial de contacto',
    asume: 'La cola de acción, el semáforo del kanban y `ultimo_contacto_en` se prueban con timeline.',
    afecta: [
      'Cartera → semáforo de último contacto (todo saldrá «sin contactar»)',
      'Hoy · asesor → buckets de la cola (sin_responder, insistir, seguimiento)',
    ],
    consecuencia:
      'Sin actividades, `ultimo_contacto_en` es NULL en todas las filas y los '
      + 'buckets que dependen de «cuándo se le habló» colapsan a uno solo.',
    async medir() {
      const { count, error } = await admin.from('actividades')
        .select('id', { count: 'exact', head: true });
      if (error) throw error;
      return count ?? 0;
    },
    divergeSi: (n) => n === 0,
    esperado: '≥ 1 actividad',
  },
  {
    clave: 'tareas_pendientes',
    titulo: 'Hay agenda viva (tareas pendientes)',
    asume: 'La agenda héroe y el «plan vigente» de la cola se prueban con tareas sembradas.',
    afecta: [
      'Hoy · asesor → agenda del día y el modo «viernes de higiene»',
      'Cola de acción → el escudo de «tiene plan vigente»',
    ],
    consecuencia:
      'Sin tareas, todo lead abierto cae en «sin próxima acción» y la agenda '
      + 'está vacía siempre: dos caminos del código que nadie recorre en vivo.',
    async medir() {
      const { count, error } = await admin.from('tareas')
        .select('id', { count: 'exact', head: true })
        .eq('estado', 'pendiente').eq('activo', true);
      if (error) throw error;
      return count ?? 0;
    },
    divergeSi: (n) => n === 0,
    esperado: '≥ 1 tarea pendiente',
  },
  {
    clave: 'equipo_operativo',
    titulo: 'Hay fuerza de ventas activa en el CRM',
    asume: 'El roster de los fixtures tiene 10 miembros activos con jerarquía de 2 niveles.',
    afecta: [
      'Gestión de equipo y rankings (sin vendedores, tabla vacía)',
      'Reparto de la cola global (sin supervisores no hay destino)',
    ],
    consecuencia:
      'Un roster mínimo hace que los agregados por vendedor y las comparativas '
      + 'de equipo no tengan nada que comparar.',
    async medir() {
      const { count, error } = await admin.from('equipo')
        .select('perfil_id', { count: 'exact', head: true })
        .eq('activo', true).in('rol_crm', ['vendedor', 'supervisor']);
      if (error) throw error;
      return count ?? 0;
    },
    divergeSi: (n) => n < 2,
    esperado: '≥ 2 entre vendedores y supervisores activos',
  },
];

function pintar(resultados) {
  const divergentes = resultados.filter((r) => r.diverge);
  process.stdout.write('\n— Gate de realidad: lo que el producto ASUME vs lo que HAY —\n\n');
  for (const r of resultados) {
    if (r.error) {
      process.stdout.write(`  ⚠️  ${r.titulo}\n      no se pudo medir: ${r.error}\n\n`);
      continue;
    }
    const marca = r.diverge ? '⚠️ ' : '✓ ';
    process.stdout.write(`  ${marca} ${r.titulo}: ${r.valor}  (se asume ${r.esperado})\n`);
    if (!r.diverge) continue;
    process.stdout.write(`      ${r.asume}\n`);
    process.stdout.write(`      Consecuencia: ${r.consecuencia}\n`);
    process.stdout.write('      Pantallas que hoy se prueban contra un mundo que no existe:\n');
    for (const p of r.afecta) process.stdout.write(`        · ${p}\n`);
    process.stdout.write('\n');
  }

  if (divergentes.length === 0) {
    process.stdout.write('\n✅ Sin divergencias: los fixtures y la base cuentan la misma película.\n');
    return;
  }
  process.stdout.write(
    `\n⚠️  ${divergentes.length} de ${resultados.length} supuestos NO se cumplen en esta base.\n`
    + '   Esto no es un bug: es la lista de sitios donde un cambio puede pasar\n'
    + '   el gate entero y no hacer nada en producción. Antes de dar por bueno\n'
    + '   un arreglo que toque una de esas pantallas, escribe el test EN ESE\n'
    + '   estado (el vacío), no solo con el fixture lleno.\n',
  );
}

async function principal() {
  const resultados = [];
  for (const supuesto of SUPUESTOS) {
    try {
      const valor = await supuesto.medir();
      resultados.push({ ...supuesto, valor, diverge: supuesto.divergeSi(valor), error: null });
    } catch (error) {
      resultados.push({
        ...supuesto, valor: null, diverge: false,
        error: error?.message ?? String(error),
      });
    }
  }

  if (JSON_OUT) {
    process.stdout.write(`${JSON.stringify(
      resultados.map(({ clave, titulo, valor, esperado, diverge, error, afecta }) => ({
        clave, titulo, valor, esperado, diverge, error, afecta,
      })),
      null, 2,
    )}\n`);
  } else {
    pintar(resultados);
  }

  const hayFallosDeMedicion = resultados.some((r) => r.error);
  if (hayFallosDeMedicion) process.exit(2);
  if (ESTRICTO && resultados.some((r) => r.diverge)) process.exit(1);
}

principal().catch((error) => fatal(error?.message ?? String(error)));

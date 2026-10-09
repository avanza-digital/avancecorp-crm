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
    clave: 'roster_metas_completo',
    titulo: 'Todo vendedor activo tiene supervisor activo',
    asume: 'Los fixtures cuelgan a TODOS los vendedores de un supervisor; nadie queda huérfano.',
    afecta: [
      'Configuración · Metas → publicar la revisión del mes',
      'Hoy · asesor → sin revisión publicada no hay meta que enseñar',
      'Rankings y metas de equipo (la atribución sale del supervisor)',
    ],
    consecuencia:
      'Un vendedor sin supervisor no cabe en crm.metas_vendedor (supervisor_id es '
      + 'NOT NULL). Ese hueco de datos DEJÓ SIN METAS AL CRM ENTERO durante días: '
      + 'el editor ofrecía las metas del roster y el servidor las exigía de todos, '
      + 'así que la publicación fallaba siempre y nadie tenía objetivo del mes.',
    async medir() {
      // Sin acceso a private.* desde PostgREST se replica el predicado de
      // private.rol_crm, que exige activo en LOS DOS lados: la membresía del
      // equipo y el perfil del portal. Comprobar solo uno da un conteo bonito
      // y falso, que es justo lo que este gate existe para no hacer.
      const { data, error } = await admin.from('equipo')
        .select('perfil_id, rol_crm, supervisor_id').eq('activo', true);
      if (error) throw error;
      const miembros = data ?? [];
      if (miembros.length === 0) return 0;
      const { data: perfiles, error: errorPerfiles } = await admin.schema('public')
        .from('perfiles').select('id, activo, rol').in('id', miembros.map((f) => f.perfil_id));
      if (errorPerfiles) throw errorPerfiles;
      const portal = new Map((perfiles ?? []).map((p) => [p.id, p]));
      // Misma excepción que private.rol_crm: al superadmin del portal solo le
      // suma autoridad una membresía de Gerencia; con cualquier otro rol queda
      // fuera del CRM y no debe contarse como vendedor huérfano.
      const rolVigente = new Map(miembros
        .filter((f) => portal.get(f.perfil_id)?.activo
          && (portal.get(f.perfil_id)?.rol !== 'superadmin' || f.rol_crm === 'gerencia'))
        .map((f) => [f.perfil_id, f.rol_crm]));
      return miembros.filter((fila) => rolVigente.get(fila.perfil_id) === 'vendedor'
        && rolVigente.get(fila.supervisor_id ?? '') !== 'supervisor').length;
    },
    divergeSi: (n) => n > 0,
    esperado: '0 vendedores sin supervisor activo',
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
  {
    clave: 'facturacion_ventas_de_analistas_de_baja',
    titulo: 'Hay ventas de analistas dados de baja (cuentan al heredero)',
    asume: 'Los fixtures de Facturación (facturacion.test.tsx, e2e facturacion-realidad) solo traen ventas '
      + 'de analistas activos: el analista de cada fila es siempre quien la registró.',
    afecta: [
      'Facturación → malla y totales por analista y por equipo',
      'Metas, cumplimiento y el sello del mes (capital_real)',
      'Cartera → ficha del inversionista («Analista de la operación»)',
      'Altas de contratos nuevos por analista',
    ],
    consecuencia:
      'Desde 20261009200000 (09/10/2026) la venta de un analista de baja se cuenta al responsable '
      + 'actual ACTIVO de su cliente; si no hay ninguno, se queda con la persona de baja. Ese camino '
      + 'vive solo en la base: ningún fixture de pantalla lo ejerce. Su oráculo es '
      + 'supabase/scripts/baja-analista-heredero/ensayo-sintetico.sql (banco Docker).',
    async medir() {
      const { data: bajas, error: errorBajas } = await admin.from('equipo')
        .select('perfil_id').eq('activo', false);
      if (errorBajas) throw errorBajas;
      const ids = (bajas ?? []).map((fila) => fila.perfil_id);
      if (ids.length === 0) return 0;
      const { count, error } = await admin.schema('public').from('contratos')
        .select('id', { count: 'exact', head: true })
        .eq('es_demo', false)
        .in('analista_cierre_id', ids);
      if (error) throw error;
      return count ?? 0;
    },
    // Diverge mientras exista UNA: entonces Facturación se está mostrando con una regla que
    // los tests de pantalla no ven. No es un error que arreglar, es un mundo que vigilar.
    divergeSi: (n) => n > 0,
    esperado: '0 (con ventas de bajas, la cifra la decide la regla del heredero, no el fixture)',
  },
  {
    clave: 'clientes_con_domicilio_legal',
    titulo: 'Los clientes tienen domicilio legal',
    asume: 'Los fixtures dan por hecho que un cliente se puede contratar sin más.',
    afecta: [
      'Mi cartera · «+ Contrato» → el alta se REVIERTE entera sin domicilio',
      'Convertir lead → contrato (el domicilio se captura ahí y por eso ese camino sí funciona)',
      'Ver / descargar el PDF de un contrato viejo que aún no lo tenga sellado',
    ],
    consecuencia:
      'El PDF se reserva en la MISMA transacción del alta y '
      + 'private.contrato_pdf_snapshot_v2_base exige el domicilio: sin él, el raise '
      + '23514 revierte el contrato ENTERO. El 2026-08-19 se midieron 332 de 339 '
      + 'clientes activos sin domicilio (98%) y CERO contratos creados en todo el día. '
      + 'Ningún fixture reproduce ese mundo: todos nacen con domicilio.',
    async medir() {
      const { count, error } = await admin.schema('public').from('perfiles')
        .select('id', { count: 'exact', head: true })
        .eq('rol', 'cliente')
        .eq('activo', true)
        .is('domicilio', null);
      if (error) throw error;
      return count ?? 0;
    },
    // Diverge mientras QUEDE alguno: este número bajando es la única prueba de
    // que el arreglo está llegando a la gente, no de que se desplegó.
    divergeSi: (n) => n > 0,
    esperado: '0 clientes activos sin domicilio legal',
  },
  {
    clave: 'metas_bajo_el_sello',
    titulo: 'Ninguna revisión de metas vive por debajo del último mes sellado',
    asume: 'El candado del cierre (20260815150000 + 20260815223000) rechaza publicar '
      + 'metas de un mes ≤ al último sellado, serializado con el sellado del MISMO mes.',
    afecta: [
      'Cierre de mes: un mes con metas bajo el suelo jamás se sellará (metas muertas)',
      'Configuración · Metas: el editor las mostraría como si contaran',
    ],
    consecuencia:
      'Es el CANARIO del residuo documentado en 20260815223000: publicar un mes P '
      + 'mientras se sella OTRO mes M > P no queda serializado. Si esta cuenta deja '
      + 'de ser 0, esa carrera ocurrió de verdad: las filas son inertes (el suelo '
      + 'las ignora), pero hay que saberlo y decidir si se limpian.',
    async medir() {
      // Las metas del propio mes sellado son legítimas (se selló CON ellas).
      // Lo anómalo: una revisión MAYOR que la fotografiada por su sello, o un
      // mes bajo el suelo que ni siquiera tiene sello propio.
      const { data: sellos, error: errorSellos } = await admin.from('periodos_cerrados')
        .select('periodo, meta_revision');
      if (errorSellos) throw errorSellos;
      if (!sellos || sellos.length === 0) return 0;
      const porPeriodo = new Map(sellos.map((s) => [s.periodo, s.meta_revision]));
      const ultimo = sellos.map((s) => s.periodo).sort().at(-1);
      const { data: metas, error } = await admin.from('meta_periodos')
        .select('periodo, revision').lte('periodo', ultimo);
      if (error) throw error;
      return (metas ?? []).filter((m) => {
        const sellada = porPeriodo.get(m.periodo);
        return sellada === undefined || m.revision > sellada;
      }).length;
    },
    divergeSi: (n) => n > 0,
    esperado: '0 revisiones bajo el sello sin fotografiar (residuo de 20260815223000)',
  },
  {
    clave: 'conversion_un_solo_nucleo',
    titulo: 'La conversión del mes es UNA por los cuatro caminos',
    asume: 'Resumen, Conversiones y Distribución recalculan por su cuenta y se da por hecho que '
      + 'coinciden con Ranking, Metas y HOY (la lectura mensual). Hasta el 21/09/2026 lo único '
      + 'que se comprobaba era una sonda que compara el núcleo consigo mismo.',
    afecta: [
      'Hoy · gerencia → Resumen (número grande del rango)',
      'Conversiones → héroe «Índice comercial»',
      'Distribución → índice del núcleo',
      'Ranking, Metas y HOY → lectura mensual (la cifra oficial)',
    ],
    consecuencia:
      'Si los caminos discrepan, dos pantallas enseñan dos porcentajes distintos del mismo '
      + 'mes y ninguna dice cuál manda. Pasa en cuanto haya un mes sellado o una deuda por '
      + 'anulación que viaje de mes; hoy coinciden por casualidad, no por construcción.',
    async medir() {
      // crm.alarma_conversion_fn solo la puede ejecutar service_role: compara divisor,
      // numerador y % por los cuatro caminos y devuelve solo agregados.
      const { data, error } = await admin.rpc('alarma_conversion_fn');
      if (error) throw error;
      if (data?.cuadra == null) return `sin veredicto (${data?.motivo ?? 'sin datos'})`;
      const d = data.detalle ?? {};
      const resumen = Object.entries(d).map(([k, v]) => `${k} ${v.pct ?? '—'} %`).join(' · ');
      return data.cuadra
        ? `cuadra · ${data.caminos_leidos} caminos · ${d.nucleo_directo?.pct ?? '—'} % (${data.mes} → ${data.hasta})`
        : `NO CUADRA · ${resumen}`;
    },
    divergeSi: (v) => typeof v !== 'string' || !v.startsWith('cuadra'),
    esperado: 'los cuatro caminos con el mismo divisor, numerador y %',
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

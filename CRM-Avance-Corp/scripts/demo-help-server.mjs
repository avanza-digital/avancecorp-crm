import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HOST = '127.0.0.1';
const PORT = 55431;
const MAX_BODY_BYTES = 4_096;
const ALLOWED_ORIGINS = new Set([
  'http://127.0.0.1:5173',
  'http://localhost:5173',
]);

const VALID_VIEWS = new Set([
  'hoy',
  'alertas',
  'conversiones',
  'ranking-vendedores',
  'reuniones',
  'metas',
  'rendimiento',
  'capital-cierres',
  'pipeline',
  'cartera',
  'agenda',
  'mi-cartera',
  'repartir',
  'equipo',
  'config',
  'config-usuarios',
  'config-productos',
  'config-metas',
  'config-sla',
]);

const CLARIFICATION_RULES = Object.freeze([
  {
    any: ['eliminar', 'borrar', 'quitar', 'sacar', 'anular', 'cancelar'],
    none: [
      'accion', 'tarea', 'pendiente', 'llamada', 'whatsapp', 'recordatorio', 'reunion',
      'cita', 'actividad', 'gestion', 'historial', 'lead', 'prospecto', 'contacto',
      'cliente', 'contrato', 'pdf', 'datos', 'celular', 'dni', 'correo', 'etapa',
    ],
    clarification: {
      titulo: '¿Qué quieres quitar?',
      detalle: 'En el CRM no es lo mismo anular una acción pendiente, corregir una gestión registrada o descartar un lead.',
      opciones: [
        { etiqueta: 'Una acción que todavía está pendiente', detalle: 'Una llamada, WhatsApp, tarea o reunión que ya no realizarás.', consulta: 'como elimino una accion' },
        { etiqueta: 'Una gestión ya registrada', detalle: 'Una actividad que quedó guardada por error en el historial.', consulta: 'como elimino una actividad' },
        { etiqueta: 'Un lead que no continuará', detalle: 'Un prospecto que debe salir del proceso comercial.', consulta: 'como descarto un lead que ya no continuará' },
      ],
    },
  },
  {
    any: ['cambiar', 'corregir', 'mover', 'actualizar', 'editar'],
    none: [
      'datos', 'celular', 'numero', 'nombre', 'correo', 'dni', 'capital', 'reunion', 'cita',
      'fecha', 'etapa', 'estado', 'contactado', 'interesado', 'propuesta', 'actividad',
      'gestion', 'historial', 'contrato', 'pdf',
    ],
    clarification: {
      titulo: '¿Qué necesitas cambiar?',
      detalle: 'Indica qué elemento cambió para mostrarte los pasos correctos.',
      opciones: [
        { etiqueta: 'Los datos de un lead', detalle: 'Nombre, celular, DNI, correo o capital.', consulta: 'como corrijo los datos de un lead' },
        { etiqueta: 'La fecha de una reunión', detalle: 'El cliente pidió otro día u otra hora.', consulta: 'como cambio la fecha de una cita' },
        { etiqueta: 'La etapa del lead', detalle: 'El prospecto avanzó realmente en el proceso.', consulta: 'como cambio un lead de etapa en el proceso' },
      ],
    },
  },
  {
    any: ['hice', 'termine', 'complete', 'cerrar', 'marcar'],
    none: [
      'accion', 'tarea', 'pendiente', 'llamada', 'whatsapp', 'reunion', 'cita',
      'actividad', 'gestion', 'contacto', 'cliente', 'lead', 'contrato', 'pdf',
    ],
    clarification: {
      titulo: '¿Qué fue lo que realizaste?',
      detalle: 'Necesito distinguir si vas a cerrar una acción agendada o registrar el resultado de un contacto.',
      opciones: [
        { etiqueta: 'Una acción de mi Agenda', detalle: 'Una llamada, tarea o reunión que estaba pendiente.', consulta: 'ya hice la accion' },
        { etiqueta: 'Un contacto con el lead', detalle: 'Llamaste o escribiste y quieres dejar el resultado.', consulta: 'como marco que ya llame' },
      ],
    },
  },
]);

// ── Mesa demo de Coordinacion ────────────────────────────────────────────────
// Solo replica las RPC que consume /repartir. No expone telefono, correo ni DNI:
// Rosa enruta y descarta, no contacta. Las fechas relativas mantienen la cola
// viva para cualquier presentacion.
const haceDias = (dias) => new Date(Date.now() - dias * 86_400_000).toISOString();

let demoCola = [
  {
    id: 'demo-reparto-1', nombre_completo: 'MARIANA SALAZAR VEGA',
    distrito: 'San Isidro', origen: 'landing', categoria_interes: 'nuevo',
    monto_estimado: 55_000, moneda: 'PEN', creado_en: haceDias(0.15),
    clasificacion_auto: null,
    comentario: 'Busca invertir a doce meses y desea conocer las alternativas disponibles.',
  },
  {
    id: 'demo-reparto-2', nombre_completo: 'DIEGO RAMOS HUAMAN',
    distrito: 'Santiago de Surco', origen: 'formulario', categoria_interes: 'renovacion',
    monto_estimado: 20_000, moneda: 'USD', creado_en: haceDias(0.6),
    clasificacion_auto: null,
    comentario: 'Ya tuvo una inversion y quiere evaluar una renovacion en dolares.',
  },
  {
    id: 'demo-reparto-3', nombre_completo: 'PAOLA VILCHEZ TORRES',
    distrito: 'Miraflores', origen: 'landing', categoria_interes: 'nuevo',
    monto_estimado: 18_000, moneda: 'PEN', creado_en: haceDias(1.2),
    clasificacion_auto: 'posible_credito',
    comentario: 'Consulta si puede obtener financiamiento antes de realizar la inversion.',
  },
  {
    id: 'demo-reparto-4', nombre_completo: 'JORGE CASTILLO RUIZ',
    distrito: 'La Molina', origen: 'referido', categoria_interes: 'upgrade',
    monto_estimado: 80_000, moneda: 'PEN', creado_en: haceDias(2.4),
    clasificacion_auto: null,
    comentario: 'Referido por un cliente. Quiere aumentar el capital de su inversion actual.',
  },
  {
    id: 'demo-reparto-5', nombre_completo: 'LUCIA MENDOZA PAREDES',
    distrito: null, origen: 'oficina', categoria_interes: null,
    monto_estimado: 9_500, moneda: 'USD', creado_en: haceDias(3.1),
    clasificacion_auto: null, comentario: null,
  },
  {
    id: 'demo-reparto-6', nombre_completo: 'RENATO FLORES DIAZ',
    distrito: 'San Miguel', origen: 'formulario', categoria_interes: 'nuevo',
    monto_estimado: 32_000, moneda: 'PEN', creado_en: haceDias(4.8),
    clasificacion_auto: null,
    comentario: 'Desea una reunion presencial para revisar plazo y rentabilidad.',
  },
  {
    id: 'demo-reparto-7', nombre_completo: 'CLAUDIA QUISPE LOPEZ',
    distrito: 'Jesus Maria', origen: 'landing', categoria_interes: 'renovacion',
    monto_estimado: 26_000, moneda: 'PEN', creado_en: haceDias(7.2),
    clasificacion_auto: null,
    comentario: 'Su inversion vence pronto y quiere revisar opciones para renovar.',
  },
  {
    id: 'demo-reparto-8', nombre_completo: 'ALONSO PENA ROJAS',
    distrito: 'Magdalena del Mar', origen: 'otro', categoria_interes: 'upgrade',
    monto_estimado: 42_000, moneda: 'USD', creado_en: haceDias(9.4),
    clasificacion_auto: null,
    comentario: 'Contacto de una feria. Evalua incrementar su posicion en dolares.',
  },
];

const demoSupervisores = [
  { perfil_id: 'd-sup1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 2 },
  { perfil_id: 'd-sup2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 1 },
];

let demoDescartados = [];

function fechaLimaIso(fecha = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
}

function resumenIngresosDemo(pMes) {
  if (!/^\d{4}-(0[1-9]|1[0-2])-01$/.test(pMes ?? '')) return null;
  const hoy = fechaLimaIso();
  const mesActual = `${hoy.slice(0, 7)}-01`;
  if (pMes > mesActual) return null;

  const [anio, mes] = pMes.slice(0, 7).split('-').map(Number);
  const ultimoDia = new Date(Date.UTC(anio, mes, 0)).getUTCDate();
  const hastaDia = pMes === mesActual ? Number(hoy.slice(8, 10)) : ultimoDia;
  const base = pMes === mesActual ? [5, 9, 7, 6, 4, 2] : [8, 11, 9, 10, 6, 3];
  const semanas = [];
  let dia = 1;
  while (dia <= hastaDia) {
    const desde = `${pMes.slice(0, 8)}${String(dia).padStart(2, '0')}`;
    const dow = new Date(`${desde}T12:00:00Z`).getUTCDay();
    const hastaNumero = Math.min(dia + ((7 - dow) % 7), hastaDia);
    const hasta = `${pMes.slice(0, 8)}${String(hastaNumero).padStart(2, '0')}`;
    semanas.push({
      numero: semanas.length + 1,
      desde,
      hasta,
      total: base[semanas.length] ?? 0,
    });
    dia = hastaNumero + 1;
  }
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    mes: pMes,
    total: semanas.reduce((total, semana) => total + semana.total, 0),
    semanas,
  };
}

function resumenColaDemo() {
  const capital = demoCola.reduce((total, lead) => {
    total[lead.moneda === 'USD' ? 'usd' : 'pen'] += lead.monto_estimado;
    return total;
  }, { pen: 0, usd: 0 });
  const ahora = Date.now();
  const espera = demoCola.reduce((maximo, lead) => Math.max(
    maximo,
    Math.max(0, Math.floor((ahora - Date.parse(lead.creado_en)) / 86_400_000)),
  ), 0);
  const porOrigen = new Map();
  for (const lead of demoCola) porOrigen.set(lead.origen, (porOrigen.get(lead.origen) ?? 0) + 1);
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    cola: {
      total: demoCola.length,
      capital,
      espera_max_dias: espera,
      posible_credito: demoCola.filter((lead) => lead.clasificacion_auto === 'posible_credito').length,
      por_origen: [...porOrigen.entries()].map(([origen, n]) => ({ origen, n })),
    },
  };
}

function normalizeText(value) {
  return value
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLocaleLowerCase('es')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function hasTerm(normalized, term) {
  return ` ${normalized} `.includes(` ${normalizeText(term)} `);
}

async function loadCatalog() {
  const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const migrationPath = resolve(
    repositoryRoot,
    'supabase/migrations/20260818034822_crm_ayuda_vendedor_servidor.sql',
  );
  const migration = await readFile(migrationPath, 'utf8');
  const match = migration.match(/\$catalogo\$\s*(\[[\s\S]*?\])\s*\$catalogo\$::jsonb/);
  if (!match) throw new Error('No se encontró el catálogo aprobado del Centro de ayuda.');

  const catalog = JSON.parse(match[1]);
  if (!Array.isArray(catalog) || catalog.length !== 17) {
    throw new Error(`El catálogo aprobado debe contener 17 guías; contiene ${catalog.length}.`);
  }
  return catalog;
}

function buildIndex(catalog) {
  const exact = new Map();
  for (const article of catalog) {
    for (const expression of article.expresiones) {
      exact.set(normalizeText(expression.texto), article);
    }
  }
  return exact;
}

function frequentQuestions(catalog, view) {
  return [...catalog]
    .sort((a, b) => {
      const relatedA = a.vistas.includes(view) ? 1 : 0;
      const relatedB = b.vistas.includes(view) ? 1 : 0;
      return relatedB - relatedA || a.prioridad - b.prioridad || a.clave.localeCompare(b.clave);
    })
    .slice(0, 6)
    .map((article) => article.pregunta);
}

function resolveQuery(exact, query) {
  const clean = query.trim();
  const normalized = normalizeText(clean);

  for (const rule of CLARIFICATION_RULES) {
    if (rule.any.some((term) => hasTerm(normalized, term))
      && !rule.none.some((term) => hasTerm(normalized, term))) {
      return { version: 1, tipo: 'aclaracion', aclaracion: rule.clarification };
    }
  }

  const article = exact.get(normalized);
  if (article) return { version: 1, tipo: 'respuesta', respuesta: article.contenido };
  return { version: 1, tipo: 'sin_resultado', consulta: clean };
}

async function readJsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error('BODY_TOO_LARGE');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function writeJson(response, status, payload, origin) {
  response.writeHead(status, {
    'Access-Control-Allow-Headers': 'apikey, authorization, content-profile, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'http://127.0.0.1:5173',
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
    Vary: 'Origin',
  });
  response.end(JSON.stringify(payload));
}

const catalog = await loadCatalog();
const exact = buildIndex(catalog);

if (process.argv.includes('--self-test')) {
  const exactResult = resolveQuery(exact, 'como elimino una accion');
  const ambiguousResult = resolveQuery(exact, 'quiero eliminar algo');
  const unknownResult = resolveQuery(exact, 'como preparo un cafe');
  const mesDemo = `${fechaLimaIso().slice(0, 7)}-01`;
  const ingresosDemo = resumenIngresosDemo(mesDemo);
  if (exactResult.tipo !== 'respuesta'
    || ambiguousResult.tipo !== 'aclaracion'
    || unknownResult.tipo !== 'sin_resultado'
    || ingresosDemo == null
    || ingresosDemo.semanas.reduce((total, semana) => total + semana.total, 0)
      !== ingresosDemo.total
    || demoCola.length < 6) {
    throw new Error('Falló el contrato del servidor demo de ayuda.');
  }
  console.log(`Servidor demo validado: ${catalog.length} guías y mesa de Rosa aprobadas.`);
  process.exit(0);
}

const server = createServer(async (request, response) => {
  const origin = request.headers.origin ?? '';
  if (request.method === 'OPTIONS') {
    writeJson(response, 204, null, origin);
    return;
  }

  // Una sesión real o antigua nunca se acepta en el servidor de presentación.
  // Responder 401 corta el refresco de Auth sin conectarse a ningún proyecto.
  if (request.url?.startsWith('/auth/v1/')) {
    writeJson(response, 401, { code: 'not_authenticated', message: 'Usa el modo demo local.' }, origin);
    return;
  }

  if (request.method !== 'POST' || (origin && !ALLOWED_ORIGINS.has(origin))) {
    writeJson(response, 404, { message: 'Ruta no disponible.' }, origin);
    return;
  }

  try {
    const payload = await readJsonBody(request);
    const ruta = request.url?.split('?')[0];

    if (ruta === '/rest/v1/rpc/leads_por_repartir') {
      writeJson(response, 200, demoCola, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/supervisores_para_reparto') {
      writeJson(response, 200, demoSupervisores, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/resumen_reparto_fn') {
      writeJson(response, 200, resumenColaDemo(), origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/ingresos_reparto_mes_fn') {
      const resumen = resumenIngresosDemo(payload?.p_mes);
      if (!resumen) {
        writeJson(response, 400, { code: '22023', message: 'Mes no valido.' }, origin);
        return;
      }
      writeJson(response, 200, resumen, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/repartir_lead') {
      const indice = demoCola.findIndex((lead) => lead.id === payload?.p_lead);
      const supervisor = demoSupervisores.find((item) => item.perfil_id === payload?.p_supervisor);
      if (indice < 0 || !supervisor) {
        writeJson(response, 404, { code: 'P0002', message: 'El lead ya no esta en la cola.' }, origin);
        return;
      }
      const [lead] = demoCola.splice(indice, 1);
      supervisor.bandeja_pendiente += 1;
      writeJson(response, 200, {
        lead_id: lead.id,
        asignado_supervisor_id: supervisor.perfil_id,
      }, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/descartar_lead') {
      const indice = demoCola.findIndex((lead) => lead.id === payload?.p_lead);
      if (indice < 0) {
        writeJson(response, 404, { code: 'P0002', message: 'El lead ya no esta en la cola.' }, origin);
        return;
      }
      const [lead] = demoCola.splice(indice, 1);
      demoDescartados.unshift({
        ...lead,
        motivo_descarte: payload?.p_motivo ?? 'otro',
        nota_descarte: payload?.p_nota ?? null,
        descartado_en: new Date().toISOString(),
        descartado_por_nombre: 'COORDINADOR (DEMO)',
        es_mio: true,
        puede_deshacer: true,
      });
      writeJson(response, 200, { lead_id: lead.id, ya_estaba: false }, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/leads_descartados') {
      writeJson(response, 200, demoDescartados, origin);
      return;
    }
    if (ruta === '/rest/v1/rpc/deshacer_descarte') {
      const indice = demoDescartados.findIndex((lead) => lead.id === payload?.p_lead);
      if (indice < 0) {
        writeJson(response, 404, { code: 'P0002', message: 'El descarte ya no se puede deshacer.' }, origin);
        return;
      }
      const [descartado] = demoDescartados.splice(indice, 1);
      const {
        motivo_descarte: _motivo,
        nota_descarte: _nota,
        descartado_en: _fecha,
        descartado_por_nombre: _autor,
        es_mio: _esMio,
        puede_deshacer: _puede,
        ...lead
      } = descartado;
      demoCola.unshift(lead);
      writeJson(response, 200, { lead_id: lead.id }, origin);
      return;
    }

    const view = payload?.p_vista;
    if (!VALID_VIEWS.has(view)) {
      writeJson(response, 400, { code: '22023', message: 'Vista de ayuda no válida.' }, origin);
      return;
    }

    if (ruta === '/rest/v1/rpc/ayuda_vendedor_inicio') {
      writeJson(response, 200, { version: 1, preguntas: frequentQuestions(catalog, view) }, origin);
      return;
    }

    if (ruta === '/rest/v1/rpc/consultar_ayuda_vendedor') {
      const query = typeof payload?.p_consulta === 'string' ? payload.p_consulta.trim() : '';
      if (query.length < 2 || query.length > 240) {
        writeJson(response, 400, { code: '22023', message: 'Consulta de ayuda no válida.' }, origin);
        return;
      }
      writeJson(response, 200, resolveQuery(exact, query), origin);
      return;
    }

    writeJson(response, 404, { message: 'Ruta no disponible.' }, origin);
  } catch (error) {
    const status = error?.message === 'BODY_TOO_LARGE' ? 413 : 400;
    writeJson(response, status, { message: 'Solicitud no válida.' }, origin);
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Centro de ayuda demo: http://${HOST}:${PORT}`);
  console.log(`Catálogo aprobado cargado: ${catalog.length} guías.`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}

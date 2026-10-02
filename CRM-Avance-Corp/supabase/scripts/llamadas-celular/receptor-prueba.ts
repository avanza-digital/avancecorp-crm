// Receptor de PRUEBA para las pruebas de MacroDroid en C1 (F3.3: las 6 de F3-PLAN-CORTO.md).
//
// Corre en este PC el MISMO handler de la Edge crm-llamadas-ingesta (handler.ts) con una base falsa
// en memoria que imita las puertas de servicio de F3-a: clave del celular (42501 → 401), límite de
// 30 por minuto de reloj y 600 por día de Lima (P0429 → 429 con Retry-After), id de origen
// idempotente (mismo contenido = repetida; otro contenido = P0409 → 409) y entrantes ignoradas.
// Datos inventados: nada va a Supabase ni a producción. Imita el contrato, no la base: la regla
// exacta (identificación del lead, elegibilidad) se prueba en el banco (npm run test:llamadas:local).
// Nunca registra la clave ni el número completo (solo sus 3 últimos dígitos).
//
// Uso, desde CRM-Avance-Corp con Deno en el PATH (export PATH="$HOME/.local/deno:$PATH"):
//   npm run receptor:llamadas-prueba                        → crea una clave y la muestra una vez
//   npm run receptor:llamadas-prueba -- --clave <64 hex>    → reutiliza la que ya tiene el celular
//   opcionales: --puerto 8787 · --crm https://crm.miavance.com (raíz de la URL «abrir»)
// En MacroDroid: POST http://<IP de este PC>:8787/functions/v1/crm-llamadas-ingesta (la misma ruta
// que en Supabase: al desplegar la Edge solo cambia el servidor).
// Control, solo desde este PC (prueba 4: 429 y 5xx):
//   curl "http://127.0.0.1:8787/_control?modo=503&veces=3"   (modos: 503, 429, 401, normal)
//   curl http://127.0.0.1:8787/_estado
// Pruebas: deno test supabase/scripts/llamadas-celular/receptor-prueba.test.ts

import { crearHandler } from '../../functions/crm-llamadas-ingesta/handler.ts';

type Json = Record<string, unknown>;
export type Modo = 'normal' | '503' | '429' | '401';
type Remoto = { hostname: string };

export const RUTA = '/functions/v1/crm-llamadas-ingesta';
const LIMITE_MINUTO = 30;
const LIMITE_DIA = 600;
const LIMA_MS = -5 * 3_600_000; // Lima no cambia de hora en el año
const DESDE = Date.parse('2026-01-01T00:00:00Z');
const HASTA = Date.parse('2100-01-01T00:00:00Z');
const LOCALES = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

const fallo = (code: string, extra: { message?: string; details?: string } = {}) =>
  Object.assign(new Error(extra.message ?? code), { code, ...extra });

/** Solo los 3 últimos dígitos: el número es un dato personal. */
export function enmascarar(numero: unknown): string {
  if (typeof numero !== 'string' || numero.trim() === '') return 'sin número';
  const digitos = numero.replace(/\D/g, '');
  return digitos.length > 3 ? `…${digitos.slice(-3)}` : '…';
}

export function crearReceptor(o: {
  clave: string;
  urlCrm?: string;
  ahora?: () => number;
  anotar?: (linea: string) => void;
}) {
  const ahora = o.ahora ?? Date.now;
  const anotar = o.anotar ?? console.log;
  const eventos = new Map<string, string>(); // id de origen → contenido canónico
  const cuenta = { guardadas: 0, repetidas: 0, ignoradas: 0, latidos: 0, en_minuto: 0, en_dia: 0 };
  let minuto = -1, dia = -1;
  let modo: Modo = 'normal', veces = 0;

  // ctx es de cada envío: dos envíos a la vez (doble disparo) no se pisan la línea del registro.
  type Ctx = { desenlace: string };

  // Una falla forzada desde /_control, como si la base respondiera eso.
  function simular(ctx: Ctx) {
    if (modo === 'normal') return;
    const m = modo;
    if (--veces <= 0) modo = 'normal';
    ctx.desenlace = `falla simulada ${m}`;
    if (m === '503') throw new Error('falla simulada');
    if (m === '429') throw fallo('P0429', { details: 'reintentar_en_seg=30' });
    throw fallo('42501');
  }

  // Ventanas fijas como celular_consumir_envio: minuto de reloj y día de Lima. Devuelve con qué
  // confirmar el envío: si la operación falla después, no cuenta (en la base se deshace con ella).
  function consumir(ctx: Ctx): () => void {
    const t = ahora();
    const m = Math.floor(t / 60_000), d = Math.floor((t + LIMA_MS) / 86_400_000);
    if (m !== minuto) { minuto = m; cuenta.en_minuto = 0; }
    if (d !== dia) { dia = d; cuenta.en_dia = 0; }
    if (cuenta.en_dia >= LIMITE_DIA) {
      const espera = Math.ceil(((d + 1) * 86_400_000 - LIMA_MS - t) / 1000);
      ctx.desenlace = 'límite del día';
      throw fallo('P0429', { details: `reintentar_en_seg=${Math.max(1, espera)}` });
    }
    if (cuenta.en_minuto >= LIMITE_MINUTO) {
      ctx.desenlace = 'límite del minuto';
      throw fallo('P0429', { details: `reintentar_en_seg=${Math.max(1, Math.ceil(((m + 1) * 60_000 - t) / 1000))}` });
    }
    return () => { cuenta.en_minuto++; cuenta.en_dia++; };
  }

  function clave(ctx: Ctx, credencial: string) {
    if (credencial !== o.clave) { ctx.desenlace = 'clave desconocida'; throw fallo('42501'); }
  }

  const dependencias = (ctx: Ctx) => ({
    urlCrm: o.urlCrm ?? 'https://crm.miavance.com',
    ingerir: async (credencial: string, e: Json) => {
      simular(ctx);
      clave(ctx, credencial);
      const confirmar = consumir(ctx);
      const t = typeof e.ocurrio_en === 'string' ? Date.parse(e.ocurrio_en) : null;
      if (t !== null && (t < DESDE || t >= HASTA)) {
        ctx.desenlace = 'ocurrio_en fuera de rango';
        throw fallo('22023', { message: 'ocurrio_en fuera de rango' });
      }
      const numero = typeof e.numero === 'string' && e.numero.trim() !== '' ? e.numero.trim() : null;
      // Contenido canónico: la hora en UTC (el mismo instante en otra zona es el mismo contenido).
      const canon = JSON.stringify([numero, e.direccion ?? null, e.estado_tecnico ?? null,
        e.duracion_seg ?? null, t === null ? null : new Date(t).toISOString()]);
      const id = e.evento_origen_id as string;
      const previo = eventos.get(id);
      if (previo !== undefined && previo !== canon) {
        ctx.desenlace = 'mismo id con otro contenido';
        throw fallo('P0409');
      }
      confirmar();
      if (previo !== undefined) { cuenta.repetidas++; ctx.desenlace = 'repetida (ya estaba)'; return { repetido: true, ignorado: false }; }
      // Decisión 2 de F2: con las entrantes apagadas, una entrante no se guarda.
      if (e.direccion === 'entrante') { cuenta.ignoradas++; ctx.desenlace = 'ignorada (entrante)'; return { repetido: false, ignorado: true }; }
      eventos.set(id, canon);
      cuenta.guardadas++;
      ctx.desenlace = 'guardada';
      return { evento_id: crypto.randomUUID(), repetido: false, ignorado: false, motivo: null };
    },
    registrarSalud: async (credencial: string) => {
      simular(ctx);
      clave(ctx, credencial);
      consumir(ctx)();
      cuenta.latidos++;
      ctx.desenlace = 'latido registrado';
      return { registrado: true };
    },
  });

  const json = (estado: number, cuerpo: unknown) =>
    new Response(JSON.stringify(cuerpo), { status: estado, headers: { 'Content-Type': 'application/json' } });

  // Lo que se ve en la consola de un envío: sin la clave ni el número completo.
  function resumen(texto: string): string {
    try {
      const c = JSON.parse(texto);
      if (c?.accion === 'llamada' && c.evento && typeof c.evento === 'object') {
        const e = c.evento;
        return `llamada id=${String(e.evento_origen_id).slice(0, 60)} ${enmascarar(e.numero)} ${e.direccion ?? '-'} ` +
          `${e.estado_tecnico ?? '-'} ${e.duracion_seg ?? '-'}s ocurrio_en=${String(e.ocurrio_en ?? '-').slice(0, 40)}`;
      }
      if (c?.accion === 'latido' && c.latido && typeof c.latido === 'object') {
        return `latido macro=${String(c.latido.version_macro).slice(0, 40)} en_cola=${c.latido.en_cola}`;
      }
      return `cuerpo con otra forma (claves: ${Object.keys(c ?? {}).slice(0, 5).join(', ')})`;
    } catch {
      return 'cuerpo que no es JSON';
    }
  }

  return async (req: Request, remoto: Remoto): Promise<Response> => {
    const url = new URL(req.url);
    if (url.pathname === '/_control' || url.pathname === '/_estado') {
      if (!LOCALES.has(remoto.hostname)) return json(404, { error: 'No encontrado' });
      if (url.pathname === '/_estado') return json(200, { modo, veces, ...cuenta, ids: eventos.size });
      const m = url.searchParams.get('modo') ?? '';
      if (!['normal', '503', '429', '401'].includes(m)) return json(400, { error: 'modo: normal, 503, 429 o 401' });
      modo = m as Modo;
      veces = modo === 'normal' ? 0 : Math.min(50, Math.max(1, Number(url.searchParams.get('veces')) || 1));
      anotar(`${horaLima(ahora())}  control: modo=${modo}${veces ? ` durante ${veces} envío(s)` : ''}`);
      return json(200, { modo, veces });
    }
    if (url.pathname !== RUTA) return json(404, { error: 'No encontrado' });

    const credencial = req.headers.get('x-celular-credencial');
    const estadoClave = credencial === null ? 'ausente' : credencial === o.clave ? 'correcta' : 'incorrecta';
    const copia = req.method === 'POST' ? await req.clone().text().catch(() => '') : '';
    const ctx: Ctx = { desenlace: '' };
    const r = await crearHandler(dependencias(ctx))(req);
    anotar(`${horaLima(ahora())}  ${req.method} → ${r.status}${ctx.desenlace ? ` (${ctx.desenlace})` : ''} · clave ${estadoClave}` +
      `${copia ? ` · ${resumen(copia)}` : ''}`);
    return r;
  };
}

export function horaLima(t: number): string {
  return new Date(t + LIMA_MS).toISOString().slice(11, 19);
}

if (import.meta.main) {
  const arg = (nombre: string) => {
    const i = Deno.args.indexOf(`--${nombre}`);
    return i >= 0 ? Deno.args[i + 1] : undefined;
  };
  const generada = arg('clave') === undefined;
  const clave = arg('clave') ??
    Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, '0')).join('');
  if (!/^[0-9a-f]{64}$/.test(clave)) {
    console.error('--clave lleva 64 caracteres hexadecimales en minúscula');
    Deno.exit(1);
  }
  const puerto = Number(arg('puerto') ?? 8787);
  const receptor = crearReceptor({ clave, urlCrm: arg('crm') });
  const ips = Deno.networkInterfaces().filter((n) => n.family === 'IPv4' && !n.address.startsWith('127.')).map((n) => n.address);

  console.log('Receptor de PRUEBA de llamadas (datos inventados; nada va a Supabase ni a producción)');
  for (const ip of ips) console.log(`  URL para MacroDroid: http://${ip}:${puerto}${RUTA}`);
  console.log('  Cabeceras: Content-Type: application/json · x-celular-credencial: <la clave>');
  if (generada) {
    console.log(`  Clave de prueba (se muestra solo ahora): ${clave}`);
    console.log('  Para reutilizarla tras reiniciar: npm run receptor:llamadas-prueba -- --clave <la clave>');
  }
  console.log(`  Control: curl "http://127.0.0.1:${puerto}/_control?modo=503&veces=3" · curl http://127.0.0.1:${puerto}/_estado`);
  Deno.serve({ hostname: '0.0.0.0', port: puerto, onListen: () => console.log(`  Escuchando en el puerto ${puerto}\n`) },
    (req, info) => receptor(req, info.remoteAddr as Deno.NetAddr));
}

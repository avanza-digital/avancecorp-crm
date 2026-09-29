import type { SolicitudTasa } from '@/data/crm-api'

export function recibeRespuestasTasa(rol: string | null | undefined): boolean {
  return rol === 'vendedor' || rol === 'supervisor'
}

export function esRespuestaPropia(s: SolicitudTasa, cuentaId: string): boolean {
  return s.es_mia && s.solicitada_por === cuentaId && !!s.resuelta_por
    && !!s.resuelta_en && Number.isFinite(Date.parse(s.resuelta_en))
}

export const CONSULTA_RESPUESTAS_ACTIVA_MS = 15_000
export const CONSULTA_RESPUESTAS_REPOSO_MS = 120_000

// Solo una solicitud PROPIA que sigue pendiente de Gerencia justifica preguntar cada 15 s
// (`estado_efectivo`: una pendiente ya vencida no espera respuesta). El resto del tiempo,
// 2 min: medido el 29/09/2026, este sondeo era el 45 % de todas las llamadas del CRM al
// servidor. Con la última consulta fallida se vuelve a 15 s: la caída se anuncia y se
// recupera tan rápido como antes (Codex, 29/09). Una solicitud creada en OTRA pestaña del
// mismo navegador llega por la señal de abajo; desde otro dispositivo, en la siguiente
// consulta de reposo (≤ 2 min) y a partir de ahí cada 15 s.
export function intervaloConsultaRespuestas(solicitudes: readonly SolicitudTasa[] | undefined, cuentaId: string, fallo = false): number {
  if (fallo) return CONSULTA_RESPUESTAS_ACTIVA_MS
  const pendiente = (solicitudes ?? []).some(s => s.es_mia && s.solicitada_por === cuentaId && s.estado_efectivo === 'pendiente')
  return pendiente ? CONSULTA_RESPUESTAS_ACTIVA_MS : CONSULTA_RESPUESTAS_REPOSO_MS
}

// Señal entre pestañas del mismo navegador: al crear una solicitud se escribe una marca (solo
// la hora, ningún dato) y las demás pestañas vuelven a consultar al instante en vez de esperar
// su ritmo de reposo. El evento `storage` no llega a la pestaña que escribe: esa ya invalida.
export const CLAVE_SENAL_SOLICITUD_TASA = 'ac-crm-solicitud-tasa-creada-v1'

export function senalarSolicitudTasaCreada(): void {
  try { localStorage.setItem(CLAVE_SENAL_SOLICITUD_TASA, String(Date.now())) } catch { /* sin almacenamiento: las otras pestañas siguen su ritmo */ }
}

// La decisión de Gerencia se conserva aunque después se consuma o venza la tasa.
export function tituloRespuestaTasa(s: SolicitudTasa): string {
  if (s.tasa_maxima_autorizada == null) return 'Tu solicitud de tasa fue rechazada'
  return s.tasa_maxima_autorizada === s.tasa_solicitada
    ? 'Tu solicitud de tasa fue aprobada' : 'Gerencia aprobó una tasa con tope'
}

export function claveRespuestaTasa(s: SolicitudTasa): string {
  return `${s.id}|${s.resuelta_en}`
}

export interface RegistroRespuestasTasa {
  iniciado: boolean
  configurado: boolean
  sonido: boolean
  escritorio: boolean
  // Solo identificadores y marcas de lectura; nunca nombres, importes o motivos.
  respuestas: Record<string, boolean>
}

const prefijo = 'ac-crm-respuestas-tasa-v1:'
const memoria = new Map<string, RegistroRespuestasTasa>()
const sinGuardar = new Set<string>()
const vacio = (): RegistroRespuestasTasa => ({ iniciado: false, configurado: false, sonido: false, escritorio: false, respuestas: {} })

export function claveRegistroRespuestas(cuentaId: string): string { return `${prefijo}${cuentaId}` }

export function leerRegistroRespuestas(cuentaId: string): RegistroRespuestasTasa {
  if (sinGuardar.has(cuentaId)) return memoria.get(cuentaId) ?? vacio()
  try {
    const texto = localStorage.getItem(claveRegistroRespuestas(cuentaId))
    if (!texto) return vacio()
    let r: unknown
    try { r = JSON.parse(texto) } catch { return vacio() }
    if (!r || typeof r !== 'object') return vacio()
    const dato = r as Record<string, unknown>
    if (typeof dato.iniciado !== 'boolean' || typeof dato.configurado !== 'boolean'
      || typeof dato.sonido !== 'boolean' || typeof dato.escritorio !== 'boolean'
      || !dato.respuestas || typeof dato.respuestas !== 'object' || Array.isArray(dato.respuestas)) return vacio()
    const respuestas = Object.fromEntries(Object.entries(dato.respuestas).filter(([clave, valor]) =>
      clave.length < 140 && /^[\w-]+\|[\dT:.Z+-]+$/.test(clave) && typeof valor === 'boolean').slice(-1000))
    return { iniciado: dato.iniciado, configurado: dato.configurado, sonido: dato.sonido, escritorio: dato.escritorio, respuestas }
  } catch { return memoria.get(cuentaId) ?? vacio() }
}

export function guardarRegistroRespuestas(cuentaId: string, registro: RegistroRespuestasTasa): boolean {
  const acotado = { ...registro, respuestas: Object.fromEntries(Object.entries(registro.respuestas).slice(-1000)) }
  memoria.set(cuentaId, acotado)
  try {
    localStorage.setItem(claveRegistroRespuestas(cuentaId), JSON.stringify(acotado))
    sinGuardar.delete(cuentaId)
    return true
  } catch { sinGuardar.add(cuentaId); return false }
}

export function incorporarRespuestas(registro: RegistroRespuestasTasa, solicitudes: SolicitudTasa[], cuentaId: string) {
  const respuestas = { ...registro.respuestas }
  const nuevas: SolicitudTasa[] = []
  for (const solicitud of solicitudes) {
    if (!esRespuestaPropia(solicitud, cuentaId)) continue
    const clave = claveRespuestaTasa(solicitud)
    if (Object.hasOwn(respuestas, clave)) continue
    // Primera visita: no anunciar decisiones históricas como si acabaran de llegar.
    respuestas[clave] = !registro.iniciado
    if (registro.iniciado) nuevas.push(solicitud)
  }
  return { registro: { ...registro, iniciado: true, respuestas }, nuevas }
}

/** Serializa lectura + escritura entre pestañas de la misma PC. */
export async function conBloqueoRespuestas<T>(cuentaId: string, operacion: () => T): Promise<T> {
  if (navigator.locks) return navigator.locks.request(claveRegistroRespuestas(cuentaId), operacion)
  return operacion()
}

/** Contexto por sesión: se activa por un clic y se destruye al salir. */
export function crearSonidoRespuesta() {
  let contexto: AudioContext | null = null
  return {
    disponible(): boolean { return contexto?.state === 'running' },
    async activar(): Promise<boolean> {
      try {
        contexto ??= new AudioContext()
        await contexto.resume()
        return contexto.state === 'running'
      } catch { return false }
    },
    sonar(): boolean {
      if (!contexto || contexto.state !== 'running') return false
      const inicio = contexto.currentTime
      for (const [desfase, frecuencia] of [[0, 740], [0.13, 988]] as const) {
        const tono = contexto.createOscillator()
        const volumen = contexto.createGain()
        tono.type = 'sine'
        tono.frequency.value = frecuencia
        volumen.gain.setValueAtTime(0, inicio + desfase)
        volumen.gain.linearRampToValueAtTime(0.09, inicio + desfase + 0.015)
        volumen.gain.exponentialRampToValueAtTime(0.001, inicio + desfase + 0.18)
        tono.connect(volumen); volumen.connect(contexto.destination)
        tono.start(inicio + desfase); tono.stop(inicio + desfase + 0.2)
        tono.onended = () => { tono.disconnect(); volumen.disconnect() }
      }
      return true
    },
    cerrar() { const anterior = contexto; contexto = null; if (anterior) void anterior.close().catch(() => {}) },
  }
}

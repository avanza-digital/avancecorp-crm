import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listarSolicitudesTasa, type SolicitudTasa } from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'
import { useAuth } from '@/lib/auth-context'
import { AUTH_CLEARED_EVENT } from '@/lib/seguridad'
import { escribirHash, leerHash } from '@/lib/router'
import {
  claveRegistroRespuestas, claveRespuestaTasa, conBloqueoRespuestas, crearSonidoRespuesta,
  esRespuestaPropia, guardarRegistroRespuestas, incorporarRespuestas, leerRegistroRespuestas,
  recibeRespuestasTasa, tituloRespuestaTasa, type RegistroRespuestasTasa,
} from '@/lib/respuestas-tasa'
import { RespuestasTasaContext } from '@/lib/respuestas-tasa-context'
import { DialogoRespuestasTasa } from './respuestas-tasa'

export function RespuestasTasaProvider({ children }: { children: ReactNode }) {
  const { yo } = useAuth()
  if (!yo || yo.demo || !recibeRespuestasTasa(yo.rol)) return children
  return <RespuestasDeCuenta key={`${yo.id}:${yo.rol}`} cuentaId={yo.id}>{children}</RespuestasDeCuenta>
}

function RespuestasDeCuenta({ cuentaId, children }: { cuentaId: string; children: ReactNode }) {
  const [registro, setRegistro] = useState(() => leerRegistroRespuestas(cuentaId))
  const [ocupado, setOcupado] = useState(false)
  const [mensaje, setMensaje] = useState('')
  const [sinPersistencia, setSinPersistencia] = useState(false)
  const [apagado, setApagado] = useState(false)
  const [bandeja, setBandeja] = useState(false)
  const [abierta, setAbierta] = useState(() => leerHash().solicitudTasaId ?? null)
  const vigente = useRef(true)
  const sonido = useRef<ReturnType<typeof crearSonidoRespuesta> | null>(null)
  sonido.current ??= crearSonidoRespuesta()
  const notificaciones = useRef<Notification[]>([])
  const avisos = useRef<(string | number)[]>([])
  const consulta = useQuery({
    queryKey: [...crmQueryKeys.rentabilidad(), 'respuestas-analista', cuentaId],
    queryFn: ({ signal }) => listarSolicitudesTasa(null, signal, { soloMias: true, limite: 500 }),
    enabled: !apagado,
    staleTime: 0,
    refetchInterval: 15_000,
    refetchIntervalInBackground: true,
  })
  const solicitudes = useMemo(() => (consulta.data ?? [])
    .filter(s => esRespuestaPropia(s, cuentaId))
    .sort((a, b) => (b.resuelta_en ?? '').localeCompare(a.resuelta_en ?? '')), [consulta.data, cuentaId])

  const actualizar = useCallback(async (cambiar: (r: RegistroRespuestasTasa) => RegistroRespuestasTasa) => {
    await conBloqueoRespuestas(cuentaId, () => {
      if (!vigente.current) return
      const siguiente = cambiar(leerRegistroRespuestas(cuentaId))
      setSinPersistencia(!guardarRegistroRespuestas(cuentaId, siguiente))
      setRegistro(siguiente)
    })
  }, [cuentaId])

  const abrirSolicitud = useCallback((id: string) => {
    if (!vigente.current) return
    escribirHash('hoy', null, false, undefined, id)
    setAbierta(id)
    setBandeja(false)
  }, [])

  useEffect(() => {
    vigente.current = true
    const limpiar = () => {
      vigente.current = false
      sonido.current?.cerrar()
      notificaciones.current.forEach(n => n.close())
      notificaciones.current = []
      avisos.current.forEach(id => toast.dismiss(id))
      avisos.current = []
    }
    const alSalir = () => { limpiar(); setApagado(true); setBandeja(false); setAbierta(null) }
    const alHash = () => setAbierta(leerHash().solicitudTasaId ?? null)
    const alStorage = (e: StorageEvent) => {
      if (vigente.current && (e.key === null || e.key === claveRegistroRespuestas(cuentaId))) setRegistro(leerRegistroRespuestas(cuentaId))
    }
    // Cada documento nuevo necesita un gesto; se respeta la preferencia guardada.
    const alGesto = () => {
      if (vigente.current && leerRegistroRespuestas(cuentaId).sonido) void sonido.current?.activar()
    }
    window.addEventListener(AUTH_CLEARED_EVENT, alSalir)
    window.addEventListener('hashchange', alHash)
    window.addEventListener('storage', alStorage)
    window.addEventListener('pointerdown', alGesto)
    window.addEventListener('keydown', alGesto)
    return () => {
      limpiar()
      window.removeEventListener(AUTH_CLEARED_EVENT, alSalir)
      window.removeEventListener('hashchange', alHash)
      window.removeEventListener('storage', alStorage)
      window.removeEventListener('pointerdown', alGesto)
      window.removeEventListener('keydown', alGesto)
    }
  }, [cuentaId])

  useEffect(() => {
    if (!consulta.isSuccess || !consulta.isFetchedAfterMount || !consulta.data || apagado) return
    let cancelado = false
    void conBloqueoRespuestas(cuentaId, () => {
      if (cancelado || !vigente.current) return
      const anterior = leerRegistroRespuestas(cuentaId)
      const enfocada = document.hasFocus()
      const escritorioDisponible = anterior.escritorio && 'Notification' in window && Notification.permission === 'granted'
      // Una pestaña sin audio activado no debe consumir la alerta que otra sí
      // puede entregar. Si ninguna puede, se incorpora al volver al CRM.
      if (anterior.iniciado && !enfocada && (!navigator.locks
        || (!escritorioDisponible && !(anterior.sonido && sonido.current?.disponible())))) return
      const resultado = incorporarRespuestas(anterior, consulta.data!, cuentaId)
      const persistido = guardarRegistroRespuestas(cuentaId, resultado.registro)
      setSinPersistencia(!persistido)
      if (!persistido && !enfocada && resultado.nuevas.length > 0) {
        guardarRegistroRespuestas(cuentaId, anterior)
        setRegistro(anterior)
        return
      }
      setRegistro(resultado.registro)
      if (!resultado.nuevas.length) return
      // Sin coordinación/persistencia, solo la pestaña enfocada puede sonar.
      if ((!navigator.locks || !persistido) && !enfocada) return
      const primera = resultado.nuevas[0]!
      const varias = resultado.nuevas.length > 1
      const titulo = varias ? `${resultado.nuevas.length} respuestas de Gerencia` : tituloRespuestaTasa(primera)
      const abrir = () => { if (vigente.current) { if (varias) setBandeja(true); else abrirSolicitud(primera.id) } }
      const aviso = toast(titulo, {
        description: varias ? 'Revisa las respuestas a tus solicitudes de tasa.' : `${primera.cliente_nombre}. Revisa la respuesta de Gerencia.`,
        duration: 12_000,
        action: { label: varias ? 'Ver respuestas' : 'Ver solicitud', onClick: abrir },
      })
      avisos.current.push(aviso)
      const sono = resultado.registro.sonido && (sonido.current?.sonar() ?? false)
      if (resultado.registro.escritorio && 'Notification' in window && Notification.permission === 'granted'
        && (document.visibilityState === 'hidden' || !document.hasFocus())) {
        try {
          const notificacion = new Notification(titulo, {
            body: 'Abre el CRM para revisar la respuesta de Gerencia.',
            icon: '/brand/avance-icon-192.png', tag: `respuesta-tasa-${primera.id}`,
            silent: sono || !resultado.registro.sonido,
          })
          notificacion.onclick = () => { notificacion.close(); if (vigente.current) { window.focus(); abrir() } }
          notificaciones.current.push(notificacion)
        } catch { /* La respuesta permanece en la bandeja si la PC bloquea el aviso. */ }
      }
    })
    return () => { cancelado = true }
  }, [consulta.data, consulta.dataUpdatedAt, consulta.isSuccess, consulta.isFetchedAfterMount, apagado, cuentaId, abrirSolicitud])

  const seleccionada = !apagado && !consulta.isError ? solicitudes.find(s => s.id === abierta) ?? null : null
  const claveSeleccionada = seleccionada ? claveRespuestaTasa(seleccionada) : null
  useEffect(() => {
    if (claveSeleccionada && registro.respuestas[claveSeleccionada] === false) {
      void actualizar(r => ({ ...r, respuestas: { ...r.respuestas, [claveSeleccionada]: true } }))
    }
  }, [claveSeleccionada, registro.respuestas, actualizar])

  const pedirPermiso = () => {
    if (!('Notification' in window)) return Promise.resolve(false)
    if (Notification.permission !== 'default') return Promise.resolve(Notification.permission === 'granted')
    return Notification.requestPermission().then(p => p === 'granted').catch(() => false)
  }
  const configurar = async (soloEscritorio = false) => {
    setOcupado(true); setMensaje('')
    // Ambos comienzan dentro del clic, antes de ceder la activación del usuario.
    const audio = soloEscritorio ? Promise.resolve(registro.sonido) : sonido.current!.activar()
    const permiso = pedirPermiso()
    const [conSonido, escritorio] = await Promise.all([audio, permiso])
    if (!vigente.current) return
    await actualizar(r => ({ ...r, configurado: true, sonido: conSonido, escritorio }))
    if (!vigente.current) return
    setMensaje(escritorio
      ? 'Alertas activadas en esta PC.'
      : 'Los avisos dentro del CRM están activos. Para verlos sobre otras ventanas, permite las notificaciones del CRM en el navegador.')
    if (!soloEscritorio && conSonido) sonido.current?.sonar()
    setOcupado(false)
  }
  const cambiarSonido = async () => {
    setOcupado(true)
    const activado = registro.sonido ? false : await sonido.current!.activar()
    if (!vigente.current) return
    await actualizar(r => ({ ...r, configurado: true, sonido: activado }))
    if (!vigente.current) return
    if (activado) sonido.current?.sonar()
    setMensaje(activado ? 'Sonido activado.' : registro.sonido ? 'Sonido silenciado.' : 'El navegador no permitió activar el sonido. Vuelve a intentarlo desde esta PC.')
    setOcupado(false)
  }
  const marcarLeidas = () => actualizar(r => ({ ...r, respuestas: {
    ...r.respuestas, ...Object.fromEntries(solicitudes.map(s => [claveRespuestaTasa(s), true])),
  } }))
  const cerrar = () => {
    setBandeja(false); setAbierta(null)
    if (leerHash().solicitudTasaId) escribirHash('hoy', null, true)
  }
  const error = consulta.isError ? 'No pudimos consultar las respuestas. Reintentaremos al recuperar la conexión.'
    : sinPersistencia ? 'Esta PC no permite guardar la lectura. Se conservará durante esta sesión.'
    : (consulta.data?.length ?? 0) >= 500 ? 'Hay más solicitudes de las que esta bandeja puede mostrar. Revisa también las fichas.' : ''
  const esLeida = (s: SolicitudTasa) => registro.respuestas[claveRespuestaTasa(s)] !== false

  return <RespuestasTasaContext.Provider value={{
    habilitado: !apagado, configurado: registro.configurado, sonido: registro.sonido,
    escritorio: registro.escritorio && 'Notification' in window && Notification.permission === 'granted',
    ocupado, mensaje, error, cargando: consulta.isPending, solicitudes: apagado ? [] : solicitudes,
    sinLeer: apagado ? 0 : solicitudes.filter(s => !esLeida(s)).length, esLeida,
    activar: () => configurar(), cambiarSonido,
    cambiarEscritorio: () => registro.escritorio && 'Notification' in window && Notification.permission === 'granted'
      ? actualizar(r => ({ ...r, escritorio: false })) : configurar(true),
    probar: () => {
      if (registro.sonido) void sonido.current!.activar().then(ok => { if (ok && vigente.current) sonido.current?.sonar() })
      avisos.current.push(toast('Así recibirás las respuestas de Gerencia', { description: 'Esta es una prueba de la alerta en tu CRM.' }))
    },
    abrirBandeja: () => setBandeja(true), abrirSolicitud, marcarLeidas,
    reintentar: () => { void consulta.refetch() },
  }}>
    {children}
    {!apagado && <DialogoRespuestasTasa abierto={bandeja || !!abierta} solicitudId={abierta} seleccionada={seleccionada} cerrar={cerrar} />}
  </RespuestasTasaContext.Provider>
}

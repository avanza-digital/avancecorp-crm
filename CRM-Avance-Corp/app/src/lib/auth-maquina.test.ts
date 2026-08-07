// Tests de la máquina de acceso — el foco es la CARRERA que motivó el rewrite:
// una verificación en vuelo jamás debe aplicar su resultado después de un
// logout o un cambio de cuenta (hallazgo Alta de la auditoría 2026-07-10).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createActor } from 'xstate'
import {
  authMaquina,
  faseDe,
  ERROR_SESION,
  ERROR_TIMEOUT,
  ESPERAS_REVALIDACION_MS,
  LIMITE_VERIFICACION_MS,
  type EstadoAuth,
  type ResultadoVerificacion,
  type Verificar,
} from './auth-maquina'

/** Promesa controlable desde el test (resolver/rechazar a voluntad). */
function diferida<T>() {
  let resolver!: (v: T) => void
  let rechazar!: (e: unknown) => void
  const promesa = new Promise<T>((res, rej) => {
    resolver = res
    rechazar = rej
  })
  return { promesa, resolver, rechazar }
}

const ACCESO_ANA: ResultadoVerificacion = { tipo: 'acceso', userId: 'u-ana', rol: 'vendedor', rolPortal: 'analista', nombre: 'ANA', puedeContratar: true }
const ACCESO_BETO: ResultadoVerificacion = { tipo: 'acceso', userId: 'u-beto', rol: 'supervisor', rolPortal: 'comercial', nombre: 'BETO', puedeContratar: true }

function montar(verificar: Verificar, alLimpiar = vi.fn()) {
  const actor = createActor(authMaquina, { input: { verificar, alLimpiar } })
  actor.start()
  return { actor, alLimpiar }
}

/** Deja que las microtareas (then de promesas ya resueltas) se procesen. */
const drenar = () => new Promise<void>((res) => { setTimeout(res, 0); vi.advanceTimersByTime(0) })

beforeEach(() => {
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
})

describe('auth-maquina — carreras (el bug que motivó el rewrite)', () => {
  it('una verificación en vuelo NO recoloca la identidad después de SALIR', async () => {
    const lenta = diferida<ResultadoVerificacion>()
    const { actor, alLimpiar } = montar(() => lenta.promesa)

    expect(actor.getSnapshot().value).toBe('verificando')

    // Logout mientras la verificación sigue en vuelo.
    actor.send({ type: 'SALIR' })
    expect(actor.getSnapshot().value).toBe('anon')
    expect(alLimpiar).toHaveBeenCalled()

    // La respuesta vieja llega DESPUÉS del logout…
    lenta.resolver(ACCESO_ANA)
    await drenar()

    // …y NO puede aplicar: seguimos anónimos y sin identidad.
    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('cambio de cuenta a mitad de verificación: el resultado del usuario anterior se descarta', async () => {
    const deAna = diferida<ResultadoVerificacion>()
    const deBeto = diferida<ResultadoVerificacion>()
    let llamada = 0
    const { actor } = montar(() => (++llamada === 1 ? deAna.promesa : deBeto.promesa))

    // Mientras se verifica a ANA, el listener anuncia a BETO.
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-beto' })
    expect(actor.getSnapshot().value).toBe('verificando')

    // La respuesta VIEJA (Ana) llega primero — debe descartarse (reenter canceló su actor).
    deAna.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().context.yo).toBeNull()

    // La respuesta vigente (Beto) sí aplica.
    deBeto.resolver(ACCESO_BETO)
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-beto', rol: 'supervisor' })
  })

  it('logout durante una REVALIDACIÓN silenciosa también descarta la respuesta', async () => {
    const primera = diferida<ResultadoVerificacion>()
    const segunda = diferida<ResultadoVerificacion>()
    let llamada = 0
    const { actor } = montar(() => (++llamada === 1 ? primera.promesa : segunda.promesa))

    primera.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')

    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando')
    // La fase pública NO parpadea durante la revalidación silenciosa.
    expect(faseDe('revalidando', actor.getSnapshot().context)).toBe('listo')

    actor.send({ type: 'SALIR' })
    segunda.resolver(ACCESO_ANA)
    await drenar()

    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('el eco del listener (mismo usuario ya confirmado) NO dispara otra verificación', async () => {
    const verificar = vi.fn<Verificar>().mockResolvedValue(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(verificar).toHaveBeenCalledTimes(1)

    // onAuthStateChange re-anuncia al MISMO usuario (eco típico de Supabase).
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-ana' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(verificar).toHaveBeenCalledTimes(1)
  })
})

// El asesor volvía a la pestaña, un parpadeo de red hacía fallar la
// revalidación silenciosa y la máquina lo trataba como "no hay sesión":
// Workspace desmontado, Login en pantalla y la conversión a medio llenar
// perdida. Y para rematar, volver a entrar con la MISMA cuenta no hacía nada.
describe('auth-maquina — un parpadeo de red NO expulsa al asesor', () => {
  it('revalidación que falla por RED conserva la sesión y reintenta sola', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockRejectedValueOnce(new Error(ERROR_SESION)) // "no pude preguntar"
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor, alLimpiar } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    alLimpiar.mockClear()

    actor.send({ type: 'REVALIDAR' })
    await drenar()

    // Ni Login ni identidad borrada: la sesión sigue viva esperando el reintento.
    expect(actor.getSnapshot().value).toBe('revalidacion_diferida')
    expect(faseDe('revalidacion_diferida', actor.getSnapshot().context)).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
    expect(actor.getSnapshot().context.error).toBeNull()
    expect(alLimpiar).not.toHaveBeenCalled() // la caché de datos NO se tira

    // Vencida la espera vuelve a preguntar y el servidor ya responde.
    vi.advanceTimersByTime(ESPERAS_REVALIDACION_MS[0] + 1)
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
    expect(verificar).toHaveBeenCalledTimes(3)
  })

  it('una revalidación COLGADA tampoco cierra la sesión (timeout ≠ sin sesión)', async () => {
    const primera = diferida<ResultadoVerificacion>()
    const colgada = diferida<ResultadoVerificacion>()
    let llamada = 0
    const { actor } = montar(() => (++llamada === 1 ? primera.promesa : colgada.promesa))

    primera.resolver(ACCESO_ANA)
    await drenar()
    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando')

    vi.advanceTimersByTime(LIMITE_VERIFICACION_MS + 1)
    await drenar()
    expect(actor.getSnapshot().value).toBe('revalidacion_diferida')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
  })

  it('agotado el backoff sigue en listo (jamás en Login) y el foco reintenta ya', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockRejectedValue(new Error(ERROR_SESION)) // la red no vuelve
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    await drenar()

    for (const espera of ESPERAS_REVALIDACION_MS) {
      expect(actor.getSnapshot().value).toBe('revalidacion_diferida')
      vi.advanceTimersByTime(espera + 1)
      await drenar()
    }

    // Sin presupuesto de reintentos: la sesión SIGUE en pie, no en 'error'.
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
    expect(actor.getSnapshot().context.reintentosRevalidacion).toBe(0)
  })

  it('pero si el SERVIDOR dice que no hay sesión, se cierra igual (fail-closed)', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockResolvedValueOnce({ tipo: 'sin_sesion' })
    const { actor, alLimpiar } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    await drenar()

    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
    expect(alLimpiar).toHaveBeenCalled()
  })

  it('SALIR durante la espera del reintento cierra al instante', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockRejectedValue(new Error(ERROR_SESION))
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('revalidacion_diferida')

    actor.send({ type: 'SALIR' })
    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('en error, volver a entrar con la MISMA cuenta re-verifica (botón «Entrar» vivo)', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    // Fallo de la verificación INICIAL de una recarga (el estado 'error' real).
    actor.send({ type: 'SESION_CAMBIO', userId: null })
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-ana' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('error')

    // Login con la MISMA cuenta: el listener anuncia el mismo userId de siempre.
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-ana' })
    expect(actor.getSnapshot().value).toBe('verificando')
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
  })

  it('REINTENTAR durante la verificación reinicia la pregunta (salida del splash atascado)', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockImplementationOnce(() => colgada.promesa)
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)
    expect(actor.getSnapshot().value).toBe('verificando')

    actor.send({ type: 'REINTENTAR' })
    await drenar()

    expect(verificar).toHaveBeenCalledTimes(2)
    expect(actor.getSnapshot().value).toBe('listo')

    // La respuesta de la verificación abandonada ya no puede aplicar.
    colgada.resolver(ACCESO_BETO)
    await drenar()
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
  })

  it('en error, volver a la pestaña (REVALIDAR) también reintenta', async () => {
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('error')

    actor.send({ type: 'REVALIDAR' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.error).toBeNull()
  })
})

// Con la app en `error` la pantalla montada es el LOGIN. Mandar ese REVALIDAR a
// `verificando` ponía la fase pública en 'resolviendo' → App pintaba el splash
// → el formulario se desmontaba y volver a la pestaña borraba el correo y la
// clave a medio teclear (regresión 2026-07-25). El reintento automático se
// conserva entero: lo único que cambia es que ya no se ve.
describe('auth-maquina — el reintento desde error es SILENCIOSO (no desmonta el Login)', () => {
  it('REVALIDAR re-pregunta sin sacar la fase pública de error', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockImplementationOnce(() => colgada.promesa)
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('error')

    actor.send({ type: 'REVALIDAR' })

    // Sí está preguntando de nuevo…
    expect(actor.getSnapshot().value).toBe('revalidando_error')
    expect(verificar).toHaveBeenCalledTimes(2)
    // …pero la fase pública NO se mueve: el Login (y lo tecleado) sigue montado.
    const snapshot = actor.getSnapshot()
    expect(faseDe(snapshot.value as EstadoAuth, snapshot.context)).toBe('error')
    // Y el aviso tampoco parpadea mientras tanto.
    expect(snapshot.context.error).toBe(ERROR_SESION)

    // Sigue habiendo salida del error: si el servidor volvió, entra solo.
    colgada.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.error).toBeNull()
  })

  it('si la re-verificación silenciosa vuelve a fallar, se queda en error', async () => {
    const verificar = vi.fn<Verificar>().mockRejectedValue(new Error(ERROR_SESION))
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    await drenar()

    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.error).toBe(ERROR_SESION)

    // Y el siguiente foco lo vuelve a intentar (no se gasta a una sola vez).
    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando_error')
  })

  it('una re-verificación silenciosa COLGADA cae de vuelta a error con mensaje', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockImplementationOnce(() => colgada.promesa)
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando_error')

    vi.advanceTimersByTime(LIMITE_VERIFICACION_MS + 1)
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.error).toBe(ERROR_TIMEOUT)

    // El resolve tardío del intento abandonado ya no puede aplicar.
    colgada.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('el botón «Entrar» con la MISMA cuenta manda aunque el reintento silencioso esté en vuelo', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockImplementationOnce(() => colgada.promesa)
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    // Estado `error` con `ultimoUser` = 'u-ana': el caso en el que un
    // SESION_CAMBIO de la misma cuenta llegaba como "eco" y se descartaba.
    actor.send({ type: 'SESION_CAMBIO', userId: null })
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-ana' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.ultimoUser).toBe('u-ana')

    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando_error')

    // Login con la misma cuenta: el gesto explícito gana y sí muestra spinner.
    actor.send({ type: 'SESION_CAMBIO', userId: 'u-ana' })
    expect(actor.getSnapshot().value).toBe('verificando')
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toMatchObject({ id: 'u-ana' })
  })

  it('«Reintentar verificación» (gesto explícito) sí vuelve al spinner', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockImplementationOnce(() => colgada.promesa)
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    expect(actor.getSnapshot().value).toBe('revalidando_error')

    actor.send({ type: 'REINTENTAR' })
    expect(actor.getSnapshot().value).toBe('verificando')
    const snapshot = actor.getSnapshot()
    expect(faseDe(snapshot.value as EstadoAuth, snapshot.context)).toBe('resolviendo')
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
  })

  it('sigue siendo fail-closed: si el servidor dice que no hay sesión, cierra', async () => {
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockResolvedValueOnce({ tipo: 'sin_sesion' })
    const { actor, alLimpiar } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    await drenar()

    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
    expect(actor.getSnapshot().context.ultimoUser).toBeNull()
    expect(alLimpiar).toHaveBeenCalled()
  })

  it('SALIR durante el reintento silencioso cancela la verificación en vuelo', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockImplementationOnce(() => colgada.promesa)
    const { actor } = montar(verificar)

    await drenar()
    actor.send({ type: 'REVALIDAR' })
    actor.send({ type: 'SALIR' })
    expect(actor.getSnapshot().value).toBe('anon')

    colgada.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })
})

describe('auth-maquina — flujo de fases', () => {
  it('acceso válido: init → listo con identidad', async () => {
    const { actor } = montar(vi.fn<Verificar>().mockResolvedValue(ACCESO_ANA))
    expect(faseDe('verificando', actor.getSnapshot().context)).toBe('init')

    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
    expect(actor.getSnapshot().context.yo).toEqual({
      id: 'u-ana',
      nombre_completo: 'ANA',
      rol: 'vendedor',
      rol_portal: 'analista',
      demo: false,
      puede_contratar: true,
    })
  })

  it('sin sesión en el servidor → anon', async () => {
    const { actor } = montar(vi.fn<Verificar>().mockResolvedValue({ tipo: 'sin_sesion' }))
    await drenar()
    expect(actor.getSnapshot().value).toBe('anon')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('usuario sin rol CRM → no_enrolado (privilegio mínimo)', async () => {
    const { actor } = montar(vi.fn<Verificar>().mockResolvedValue({ tipo: 'no_enrolado', userId: 'u-x' }))
    await drenar()
    expect(actor.getSnapshot().value).toBe('no_enrolado')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('fallo del servidor → error con mensaje seguro, y REINTENTAR re-verifica', async () => {
    const verificar = vi.fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION))
      .mockResolvedValueOnce(ACCESO_ANA)
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.error).toBe(ERROR_SESION)

    actor.send({ type: 'REINTENTAR' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')
  })

  it('timeout: pasado el límite cae a error y el resolve tardío no aplica', async () => {
    const lenta = diferida<ResultadoVerificacion>()
    const { actor } = montar(() => lenta.promesa)

    vi.advanceTimersByTime(LIMITE_VERIFICACION_MS + 1)
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.error).toBe(ERROR_TIMEOUT)

    lenta.resolver(ACCESO_ANA)
    await drenar()
    expect(actor.getSnapshot().value).toBe('error')
    expect(actor.getSnapshot().context.yo).toBeNull()
  })

  it('revalidación que descubre acceso revocado → no_enrolado y limpia identidad', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockResolvedValueOnce({ tipo: 'no_enrolado', userId: 'u-ana' })
    const { actor, alLimpiar } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().value).toBe('listo')

    actor.send({ type: 'REVALIDAR' })
    await drenar()
    expect(actor.getSnapshot().value).toBe('no_enrolado')
    expect(actor.getSnapshot().context.yo).toBeNull()
    expect(alLimpiar).toHaveBeenCalled()
  })

  it('cambio de cuenta confirmado limpia la caché ANTES de exponer la identidad nueva', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockResolvedValueOnce(ACCESO_BETO)
    const { actor, alLimpiar } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().context.yo?.id).toBe('u-ana')
    alLimpiar.mockClear()

    actor.send({ type: 'SESION_CAMBIO', userId: 'u-beto' })
    await drenar()
    expect(actor.getSnapshot().context.yo?.id).toBe('u-beto')
    expect(alLimpiar).toHaveBeenCalled()
  })

  // Si a alguien le quitan el rol de portal que da de alta clientes (analista →
  // directorio), su rol_crm y su nombre NO cambian: la revalidación traía todo
  // "igual" y la identidad vieja se conservaba entera, dejando el permiso
  // obsoleto en la sesión abierta. Debe reflejar el permiso NUEVO.
  it('revalidación con el permiso de contratar REVOCADO refresca la identidad', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA) // puedeContratar: true
      .mockResolvedValueOnce({ ...ACCESO_ANA, puedeContratar: false })
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().context.yo?.puede_contratar).toBe(true)

    actor.send({ type: 'REVALIDAR' })
    await drenar()
    expect(actor.getSnapshot().context.yo?.puede_contratar).toBe(false)
  })

  it('revalidación que cambia el rol del Portal refresca la identidad', async () => {
    const verificar = vi.fn<Verificar>()
      .mockResolvedValueOnce(ACCESO_ANA)
      .mockResolvedValueOnce({ ...ACCESO_ANA, rolPortal: 'superadmin' })
    const { actor } = montar(verificar)

    await drenar()
    expect(actor.getSnapshot().context.yo?.rol_portal).toBe('analista')

    actor.send({ type: 'REVALIDAR' })
    await drenar()
    expect(actor.getSnapshot().context.yo?.rol_portal).toBe('superadmin')
  })

  it('faseDe mapea estados internos al contrato público', () => {
    expect(faseDe('verificando', { arrancando: true })).toBe('init')
    expect(faseDe('verificando', { arrancando: false })).toBe('resolviendo')
    expect(faseDe('revalidando', { arrancando: false })).toBe('listo')
    expect(faseDe('revalidacion_diferida', { arrancando: false })).toBe('listo')
    expect(faseDe('revalidando_error', { arrancando: false })).toBe('error')
    expect(faseDe('anon', { arrancando: false })).toBe('anon')
    expect(faseDe('listo', { arrancando: false })).toBe('listo')
    expect(faseDe('no_enrolado', { arrancando: false })).toBe('no_enrolado')
    expect(faseDe('error', { arrancando: false })).toBe('error')
  })
})

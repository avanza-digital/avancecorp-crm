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
  LIMITE_VERIFICACION_MS,
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

const ACCESO_ANA: ResultadoVerificacion = { tipo: 'acceso', userId: 'u-ana', rol: 'vendedor', nombre: 'ANA', puedeContratar: true }
const ACCESO_BETO: ResultadoVerificacion = { tipo: 'acceso', userId: 'u-beto', rol: 'supervisor', nombre: 'BETO', puedeContratar: true }

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

  it('faseDe mapea estados internos al contrato público', () => {
    expect(faseDe('verificando', { arrancando: true })).toBe('init')
    expect(faseDe('verificando', { arrancando: false })).toBe('resolviendo')
    expect(faseDe('revalidando', { arrancando: false })).toBe('listo')
    expect(faseDe('anon', { arrancando: false })).toBe('anon')
    expect(faseDe('listo', { arrancando: false })).toBe('listo')
    expect(faseDe('no_enrolado', { arrancando: false })).toBe('no_enrolado')
    expect(faseDe('error', { arrancando: false })).toBe('error')
  })
})

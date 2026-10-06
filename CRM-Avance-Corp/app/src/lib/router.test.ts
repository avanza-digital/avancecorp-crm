import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  escribirHash,
  esVistaGerencia,
  esVistaConfiguracion,
  esVistaInterna,
  esVistaLeads,
  hashDe,
  leerHash,
  VISTAS,
  VISTAS_GERENCIA,
} from './router'

describe('router por hash', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/')
  })

  it('construye rutas canónicas y codifica el identificador del lead', () => {
    expect(hashDe('hoy')).toBe('#/hoy')
    expect(hashDe('pipeline', null)).toBe('#/pipeline')
    expect(hashDe('cartera', 'lead/á 1')).toBe('#/cartera/lead/lead%2F%C3%A1%201')
  })

  it('conserva día y equipo de Citas al abrir/cerrar la ficha y rechaza contextos inválidos', () => {
    const consulta = { dia: '2026-10-05', equipo: '10000000-0000-4000-8000-000000000001' }
    escribirHash('reuniones', 'lead/1', true, undefined, undefined, undefined, undefined, consulta)
    expect(leerHash()).toEqual({ vista: 'reuniones', leadId: 'lead/1', consultaCitas: consulta })
    escribirHash('reuniones', null, true, undefined, undefined, undefined, undefined, leerHash().consultaCitas)
    expect(leerHash().consultaCitas).toEqual(consulta)
    for (const hash of ['#/reuniones/dia/2026-02-30', '#/reuniones/dia/2026-13-01', '#/reuniones/dia/2026-10-05/equipo/../../../x', '#/hoy/dia/2026-10-05']) {
      window.history.replaceState(null, '', hash)
      expect(leerHash().consultaCitas).toBeUndefined()
    }
    expect(hashDe('hoy', null, undefined, undefined, undefined, undefined, consulta)).toBe('#/hoy')
  })

  it('conserva mes, semana y equipo al salir del filtro diario y abrir una ficha', () => {
    const consulta = { mes: '2026-10', semana: '2', equipo: 'd-sup1' }
    escribirHash('reuniones', 'lead/1', true, undefined, undefined, undefined, undefined, consulta)
    expect(window.location.hash).toBe('#/reuniones/mes/2026-10/semana/2/equipo/d-sup1/lead/lead%2F1')
    expect(leerHash()).toEqual({ vista: 'reuniones', leadId: 'lead/1', consultaCitas: consulta })
    for (const hash of ['#/reuniones/mes/2026-13', '#/reuniones/mes/2026-10/semana/5', '#/reuniones/dia/2026-10-05/equipo']) {
      window.history.replaceState(null, '', hash)
      expect(leerHash().consultaCitas).toBeUndefined()
    }
  })

  it('conserva equipo/analista al abrir y cerrar la ficha desde Gestión Diaria', () => {
    const id = '10000000-0000-4000-8000-000000000001'
    for (const tipo of ['equipo', 'analista'] as const) {
      const detalleGestion = { tipo, id }
      escribirHash('gestion-diaria', 'lead/1', true, undefined, undefined, detalleGestion)
      expect(leerHash()).toEqual({ vista: 'gestion-diaria', leadId: 'lead/1', detalleGestion })
      escribirHash('gestion-diaria', null, true, undefined, undefined, leerHash().detalleGestion)
      expect(window.location.hash).toBe(`#/gestion-diaria/${tipo}/${id}`)
    }
  })

  it('mantiene la cola completa al abrir/cerrar una ficha y conserva el acceso antiguo', () => {
    const detalleGestion = { tipo: 'cola' as const }
    escribirHash('gestion-diaria', 'lead/á 1', true, undefined, undefined, detalleGestion)
    expect(window.location.hash).toBe('#/gestion-diaria/cola/lead/lead%2F%C3%A1%201')
    expect(leerHash()).toEqual({ vista: 'gestion-diaria', leadId: 'lead/á 1', detalleGestion })
    escribirHash('gestion-diaria', null, true, undefined, undefined, leerHash().detalleGestion)
    expect(window.location.hash).toBe('#/gestion-diaria/cola')
    expect(hashDe('seguimiento', 'l1', undefined, undefined, detalleGestion)).toBe('#/seguimiento/lead/l1')
    window.history.replaceState(null, '', '#/seguimiento/lead/l1')
    expect(leerHash()).toEqual({ vista: 'seguimiento', leadId: 'l1' })
    window.history.replaceState(null, '', '#/gestion-diaria/cola/lead/%')
    expect(leerHash()).toEqual({ vista: 'gestion-diaria', leadId: null, detalleGestion })
  })

  it('acepta el organigrama del modo demo (d-sup1, d-v1…) y sólo con esa forma', () => {
    for (const detalleGestion of [{ tipo: 'equipo', id: 'd-sup1' }, { tipo: 'analista', id: 'd-v1' }] as const) {
      escribirHash('gestion-diaria', null, true, undefined, undefined, detalleGestion)
      expect(leerHash().detalleGestion).toEqual(detalleGestion)
    }
    for (const hash of ['#/gestion-diaria/equipo/d-', '#/gestion-diaria/analista/d-V1', '#/gestion-diaria/analista/x-v1', '#/gestion-diaria/equipo/d-sup1%2F..']) {
      window.location.hash = hash
      expect(leerHash().detalleGestion).toBeUndefined()
    }
  })

  // F1.2.1 (plan «Llamadas desde el celular al CRM»): el enlace que arma el
  // celular al colgar trae el número en su propio segmento.
  it('la ruta por número existe solo en Hoy y Gestión Diaria, codifica su segmento y conserva el +', () => {
    expect(hashDe('gestion-diaria', null, undefined, undefined, undefined, '+51999888777')).toBe('#/gestion-diaria/llamada/%2B51999888777')
    expect(hashDe('hoy', null, undefined, undefined, undefined, '+51 999-888 777')).toBe('#/hoy/llamada/%2B51%20999-888%20777')
    expect(hashDe('hoy', null, undefined, undefined, undefined, '999888777')).toBe('#/hoy/llamada/999888777')
    // Con la ficha abierta el número ya cumplió; en otras vistas no existe.
    expect(hashDe('hoy', 'l1', undefined, undefined, undefined, '+51999888777')).toBe('#/hoy/lead/l1')
    expect(hashDe('cartera', null, undefined, undefined, undefined, '+51999888777')).toBe('#/cartera')
    // Lo que no es un número de marcador no viaja en el hash (un código de
    // servicio como *123# tampoco: no es un lead).
    for (const raro of ['abc', '', '+', '+ ', '999888777x', '<script>', '*123#', '9'.repeat(41)]) {
      expect(hashDe('hoy', null, undefined, undefined, undefined, raro)).toBe('#/hoy')
    }
    expect(hashDe('hoy', null, undefined, undefined, undefined, '(01) 445-7890')).toBe('#/hoy/llamada/(01)%20445-7890')
  })

  it('lee el número tal cual llegó, codificado o crudo, y descarta lo que no es un número', () => {
    for (const hash of ['#/gestion-diaria/llamada/%2B51999888777', '#/gestion-diaria/llamada/+51999888777']) {
      window.location.hash = hash
      expect(leerHash()).toEqual({ vista: 'gestion-diaria', leadId: null, llamadaNumero: '+51999888777' })
    }
    window.location.hash = '#/hoy/llamada/999888777'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null, llamadaNumero: '999888777' })
    window.location.hash = '#/hoy/llamada/%2B51%20999-888%20777'
    expect(leerHash().llamadaNumero).toBe('+51 999-888 777')
    for (const hash of ['#/hoy/llamada/', '#/hoy/llamada/abc', '#/hoy/llamada/%2B', '#/hoy/llamada/*123%23', '#/hoy/llamada/%E0%A4%A',
      '#/cartera/llamada/999888777', '#/gestion-diaria/cola/llamada/999888777', `#/hoy/llamada/${'9'.repeat(41)}`]) {
      window.location.hash = hash
      expect(leerHash().llamadaNumero).toBeUndefined()
    }
    // Detrás de «llamada» no viaja una ficha.
    window.location.hash = '#/hoy/llamada/999888777/lead/l1'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null, llamadaNumero: '999888777' })
  })

  // F4-b: detrás del número puede venir el id de la llamada (`C1-<segundos>`), con la forma que exige la base.
  it('lee el id de la llamada detrás del número; sin la forma de la base se ignora y el enlace sigue como F1', () => {
    window.location.hash = '#/gestion-diaria/llamada/%2B51999888777/C1-1790980958'
    expect(leerHash()).toEqual({ vista: 'gestion-diaria', leadId: null, llamadaNumero: '+51999888777', llamadaOrigenId: 'C1-1790980958' })
    window.location.hash = '#/hoy/llamada/999888777/C12-1790980958'
    expect(leerHash().llamadaOrigenId).toBe('C12-1790980958')
    for (const raro of ['c1-1790980958', 'C0-1790980958', 'C1-179098095', 'C1-1790980958x', 'C1%2D1790980958', 'lead', '%E0%A4%A']) {
      window.location.hash = `#/gestion-diaria/llamada/999888777/${raro}`
      expect(leerHash(), raro).toEqual({ vista: 'gestion-diaria', leadId: null, llamadaNumero: '999888777' })
    }
    // Sin número válido, el id no viaja solo.
    window.location.hash = '#/hoy/llamada/abc/C1-1790980958'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null })
  })

  it('hashDe lleva el id solo detrás de un número válido y solo con la forma de la base', () => {
    expect(hashDe('gestion-diaria', null, undefined, undefined, undefined, '+51999888777', undefined, 'C1-1790980958'))
      .toBe('#/gestion-diaria/llamada/%2B51999888777/C1-1790980958')
    expect(hashDe('gestion-diaria', null, undefined, undefined, undefined, '+51999888777', undefined, 'C1-17909809')).toBe('#/gestion-diaria/llamada/%2B51999888777')
    expect(hashDe('gestion-diaria', null, undefined, undefined, undefined, 'abc', undefined, 'C1-1790980958')).toBe('#/gestion-diaria')
    expect(hashDe('gestion-diaria', 'l1', undefined, undefined, undefined, '+51999888777', undefined, 'C1-1790980958')).toBe('#/gestion-diaria/lead/l1')
  })

  it('escribirHash conserva el número sin ficha y lo suelta al abrir una', () => {
    escribirHash('gestion-diaria', null, true, undefined, undefined, undefined, '+51999888777')
    expect(window.location.hash).toBe('#/gestion-diaria/llamada/%2B51999888777')
    expect(leerHash().llamadaNumero).toBe('+51999888777')
    escribirHash('gestion-diaria', 'l1', true, undefined, undefined, undefined, '+51999888777')
    expect(window.location.hash).toBe('#/gestion-diaria/lead/l1')
    expect(leerHash().llamadaNumero).toBeUndefined()
  })

  it('permite la fila fuera de equipos y descarta detalles inválidos o de otra vista', () => {
    escribirHash('gestion-diaria', null, true, undefined, undefined, { tipo: 'equipo', id: 'fuera' })
    expect(leerHash().detalleGestion).toEqual({ tipo: 'equipo', id: 'fuera' })
    for (const hash of ['#/gestion-diaria/analista/fuera', '#/gestion-diaria/equipo/../../x', '#/hoy/equipo/fuera']) {
      window.location.hash = hash
      expect(leerHash().detalleGestion).toBeUndefined()
    }
    expect(hashDe('hoy', null, undefined, undefined, { tipo: 'equipo', id: 'fuera' })).toBe('#/hoy')
  })

  it.each([
    ['#/hoy', 'hoy'],
    ['#/alertas', 'alertas'],
    ['#/seguimiento', 'seguimiento'],
    ['#pipeline', 'pipeline'],
    ['#/agenda/', 'agenda'],
    ['#/equipo///', 'equipo'],
    ['#/config-usuarios', 'config-usuarios'],
    ['#/config-productos', 'config-productos'],
    ['#/config-metas', 'config-metas'],
    ['#/config-sla', 'config-sla'],
    ['#/config-rentabilidad', 'config-rentabilidad'],
  ] as const)('acepta variantes compatibles de %s', (hash, vista) => {
    window.location.hash = hash
    expect(leerHash()).toEqual({ vista, leadId: null })
  })

  it('decodifica un lead y descarta rutas o escapes desconocidos', () => {
    window.location.hash = '#/cartera/lead/lead%2F%C3%A1%201'
    expect(leerHash()).toEqual({ vista: 'cartera', leadId: 'lead/á 1' })

    window.location.hash = '#/desconocida/lead/l1'
    expect(leerHash()).toEqual({ vista: null, leadId: null })

    window.location.hash = '#/hoy/lead/%E0%A4%A'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null })
  })

  it('resuelve las rutas HEREDADAS (clientes/contratos → mi-cartera) sin reintroducirlas', () => {
    // Bookmarks viejos de las pantallas retiradas en Fase 6 caen en la cartera
    // unificada, no en la vista base 'hoy'.
    window.location.hash = '#/clientes'
    expect(leerHash()).toEqual({ vista: 'mi-cartera', leadId: null })

    window.location.hash = '#/contratos'
    expect(leerHash()).toEqual({ vista: 'mi-cartera', leadId: null })

    // N1 (F3 de «Conversión única»): «Capital» dejó de ser vista — nació
    // muerta por autorización y todo lo suyo vive en el Resumen de Hoy. Su
    // bookmark viejo cae ahí, por URL directa o refresh profundo.
    window.location.hash = '#/capital-cierres'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null })

    // Una ruta realmente desconocida sigue degradando a null (no todo es alias).
    window.location.hash = '#/inexistente'
    expect(leerHash()).toEqual({ vista: null, leadId: null })

    // Claves del prototipo del Record NO deben resolver a un miembro heredado
    // (Object/toString/prototype): degradan a null como cualquier ruta desconocida.
    for (const clave of ['constructor', 'toString', '__proto__', 'hasOwnProperty']) {
      window.location.hash = `#/${clave}`
      expect(leerHash()).toEqual({ vista: null, leadId: null })
    }
  })

  it('reconoce #/repartir y la deja FUERA del mundo leads (C1)', () => {
    // 'repartir' debe ser navegable por URL para el coordinador; si entrara en
    // VISTAS_LEADS, el gate de leads (cerrado para su rol) la ocultaría justo a
    // quien es la única pantalla que puede usar.
    window.location.hash = '#/repartir'
    expect(leerHash()).toEqual({ vista: 'repartir', leadId: null })
    expect(VISTAS).toContain('repartir')
    expect(esVistaLeads('repartir')).toBe(false)
    expect(hashDe('repartir')).toBe('#/repartir')
  })

  it('registra Derivaciones como módulo independiente y fuera del gate de leads', () => {
    window.location.hash = '#/derivaciones'

    expect(leerHash()).toEqual({ vista: 'derivaciones', leadId: null })
    expect(VISTAS).toContain('derivaciones')
    expect(esVistaLeads('derivaciones')).toBe(false)
    expect(hashDe('derivaciones')).toBe('#/derivaciones')
  })

  it('registra la carpeta de rescate como ruta interna del mundo leads', () => {
    window.location.hash = '#/rescate-carpeta'
    expect(leerHash()).toEqual({ vista: 'rescate-carpeta', leadId: null })
    expect(esVistaInterna('rescate-carpeta')).toBe(true)
    expect(esVistaLeads('rescate-carpeta')).toBe(true)
    expect(hashDe('rescate-carpeta')).toBe('#/rescate-carpeta')
  })

  it('registra los cuatro módulos como rutas internas de Configuración', () => {
    for (const vista of [
      'config-usuarios',
      'config-productos',
      'config-metas',
      'config-sla',
      'config-rentabilidad',
    ] as const) {
      expect(VISTAS).toContain(vista)
      expect(esVistaConfiguracion(vista)).toBe(true)
      expect(esVistaLeads(vista)).toBe(false)
      expect(esVistaGerencia(vista)).toBe(false)
      expect(hashDe(vista)).toBe(`#/${vista}`)
    }
    expect(esVistaConfiguracion('config')).toBe(false)
  })

  it('registra Alertas justo después de Hoy como bandeja transversal', () => {
    expect(VISTAS.slice(0, 3)).toEqual(['hoy', 'alertas', 'seguimiento'])
    expect(VISTAS_GERENCIA[0]).toBe('conversiones')
    expect(VISTAS_GERENCIA).not.toContain('alertas')
    expect(esVistaGerencia('alertas')).toBe(false)
    expect(esVistaLeads('alertas')).toBe(false)
    expect(hashDe('alertas')).toBe('#/alertas')
  })

  it('separa Seguimiento de los informes de Gerencia y conserva ficha y gate de leads', () => {
    expect(esVistaGerencia('seguimiento')).toBe(false)
    expect(esVistaLeads('seguimiento')).toBe(true)
    expect(esVistaInterna('seguimiento')).toBe(false)
    expect(hashDe('seguimiento', 'l-1')).toBe('#/seguimiento/lead/l-1')
    window.location.hash = '#/seguimiento/lead/l-1'
    expect(leerHash()).toEqual({ vista: 'seguimiento', leadId: 'l-1' })
  })

  it('navega con historial normal y evita escrituras redundantes', () => {
    escribirHash('pipeline', 'l1')
    expect(window.location.hash).toBe('#/pipeline/lead/l1')

    const replaceState = vi.spyOn(window.history, 'replaceState')
    escribirHash('pipeline', 'l1')
    expect(replaceState).not.toHaveBeenCalled()
  })

  it('reemplaza rutas de corrección sin agregar navegación', () => {
    const replaceState = vi.spyOn(window.history, 'replaceState')

    escribirHash('hoy', null, true)

    expect(replaceState).toHaveBeenCalledOnce()
    expect(replaceState).toHaveBeenCalledWith(null, '', '#/hoy')
  })
})

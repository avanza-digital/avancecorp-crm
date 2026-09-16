import type {CarteraInversionistas, FichaInversionista, InversionFuente} from '@/lib/inversionistas'
export const ACTOR_F5 = '11111111-1111-4111-8111-111111111111'
export const PERSONA_F5 = '22222222-2222-4222-8222-222222222222'
export const FUENTE_F5 = '33333333-3333-4333-8333-333333333333'
export const PERFIL_F5 = '44444444-4444-4444-8444-444444444444'
export const personaF5 = {inversionista_id: PERSONA_F5, nombre: 'ANA SINTÉTICA F5', documento_tipo: 'DNI',
  documento: '93334444', documento_verificado: true, telefono: '999888777', correo: 'ana.f5@pruebas.example',
  estado: 'activo', no_contactar: false, responsable_id: ACTOR_F5, responsable_nombre: 'ANALISTA F5', creado_en: '2026-09-08T12:00:00Z'}
export const inversionF5: InversionFuente = {fuente_id: FUENTE_F5, inversionista_id: PERSONA_F5, inversion_id: null,
  empresa: 'qorilazo', perfil_id: null, lead_id: null, numero: 'QORILAZO SINTÉTICO', capital: 1200, moneda: 'PEN',
  estado: 'vigente', fecha_comercial: '2026-09-01', fecha_imputacion: '2026-09-01', vence_en: '2027-09-01',
  analista_origen_id: ACTOR_F5, analista_origen_nombre: 'ANALISTA F5', es_inicial: true, es_demo: false,
  creado_en: '2026-09-01T12:00:00Z', contrato: null, pdf: null, documentos: [], cotitulares: [], proxima_cuota: null, numero_transaccion: 'DEPÓSITO SINTÉTICO'}
export const totalesF5 = [{empresa: 'qorilazo' as const, moneda: 'PEN' as const, cantidad: 1, capital_registrado: 1200, capital_activo: null}]
export const fichaF5: FichaInversionista = {version: 1, persona: {...personaF5, perfil_id: null}, identidad_fusionada: false,
  capacidades: {nueva_inversion: true, motivo_no_operable: null, contactar: true, cuentas_perfil_ids: [], documentos: true},
  inversiones: [inversionF5], inversiones_total: 1, pagina_inversiones: 1, totales: totalesF5,
  historial: [], historial_total: 0, pagina_historial: 1, tareas: [], tareas_total: 0}
export const carteraF5: CarteraInversionistas = {version: 2, pagina: 1, tamano: 25, total: 1,
  filas: [{...personaF5, empresas: ['qorilazo'], ultima_fecha_comercial:'2026-09-01', resumen:totalesF5}], totales: totalesF5,
  sin_inversiones_total:0, solo_avance:false, opciones_meses:['2026-09','2026-08'], opciones_responsables:[{id:ACTOR_F5,nombre:'ANALISTA F5'}]}

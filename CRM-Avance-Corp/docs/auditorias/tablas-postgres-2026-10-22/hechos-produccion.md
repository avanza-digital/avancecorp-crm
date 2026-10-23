# Hechos medidos en PRODUCCIÓN (solo lectura) — 2026-10-22, entre 20:34 y 21:03 Lima (hora real por `date`)

Proyecto Supabase `dctqcbznekcyxhjujuci`, esquemas `crm` (118 tablas) y `private` (33 tablas). No existe esquema `audit`
(la bitácora es `crm.audit_log`-style via `private.log_audit_crm()` / `private.log_audit_sin_secretos()`).

## Filas vivas por tabla (pg_stat_user_tables.n_live_tup)

crm: actividad_ciclo_contexto 2057 · actividades 33984 · actividades_cliente 7 · agenda_ics 0 · ajustes_mes_cerrado 0 ·
alertas_reconocimientos 6 · backfill_multiempresa_mapa 0 · base_carga_leads 0 · base_carga_operaciones 0 · bases_carga 0 ·
busquedas_cliente_existente 38 · cambio_cuenta_avisos 4 · capital_cortes_valorados 65 · capital_mes_sellos 0 ·
capital_valoracion_politica 1 · capital_valoraciones 183 · cartera_lecturas 16353 · celulares_asignaciones 0 ·
cierre_mes_vendedor 42 · cierres_avance_anulados 4 · cierres_externos 108 · configuracion_reparto 0 ·
contrato_cuenta_pago_asignaciones 7 · contrato_cuenta_pago_cambios 7 · contrato_cuentas_pago 862 ·
contratos_eliminados_auditoria 10 · control_citas_aplicaciones 0 · control_citas_versiones 0 · conversion_acreditaciones 306 ·
conversion_pesos 0 · conversion_politica 0 · conversion_reservas 0 · conversion_ventas_recuperadas 5 ·
correcciones_categoria_contrato 24 · correcciones_correo_acceso 5 · cuentas_bancarias 66 · cuentas_bancarias_retiros 8 ·
cuotas_cuenta_pagada 1408 · depositos_reclamados 108 · dispositivos_push_tasa 4 · empresas 0 · enfriamiento_politica 0 ·
envios_push_tasa 0 · equipo 0(*) · gestion_diaria_control_avisos 0 · gestion_diaria_entregas 39 ·
inversion_ajustes_mes_cerrado 1 · inversion_backfill_lotes 0 · inversion_cotitular_origenes 1 · inversion_eventos 355 ·
inversion_solicitud_correcciones 190 · inversion_solicitud_origenes 1 · inversion_solicitud_revisiones 0 ·
inversion_solicitudes 422 · inversion_titulares 389 · inversiones 388 · inversiones_eliminadas 11 ·
inversionista_datos_contacto 0 · inversionista_fusiones 0 · inversionista_gestiones 502 · inversionista_identificadores 760 ·
inversionista_leads 339 · inversionista_operaciones 1 · inversionista_responsables 789 · inversionistas 755 ·
lead_asignacion_sla_hitos 5142 · lead_asignaciones 5142 · lead_potencial 524 · lead_potencial_eventos 799 ·
lead_sla_ciclos 4617 · lead_sla_etapa_ajustes 14 · lead_sla_etapas 9356 · leads 4539 · leads_eliminados 5 ·
ledger_rentabilidad 1004 · llamadas_celular_enlaces 8 · llamadas_celular_eventos 9 · llamadas_celular_politica 0 ·
meta_periodos 2 · metas_vendedor 54 · metas_vendedor_detalle 2790 · multiempresa_flags 0 · multiempresa_idempotencia 317 ·
objetivos_legacy_archivo 0 · objetivos_vendedores_legacy_archivo 0 · operaciones_cartera 27 · origenes_capital_confirmados 0 ·
periodos_cerrados 1 · piloto_f8_control 0 · piloto_f8_miembros 0 · plazos_carga_mes 2 · politica_abandono 0 ·
politica_gestion_diaria 0 · politica_rentabilidad 0 · postventa_escrituras 0 · postventa_operaciones 162 · postventa_retiros 0 ·
producto_condiciones 1085 · producto_versiones 1085 · productos_inversion 0 · reaperturas_mes 0 · reasignaciones_analista 4 ·
recordatorios_disponibilidad 1 · recorrido_control 1 · rentabilidad_hitos 0 · sla_operacion_control 0 ·
sla_operacion_recibos 15218 · sla_politica_etapas 0 · sla_politica_etapas_operacion 0 · sla_politicas 0 ·
solicitudes_desechadas_corridas 0 · solicitudes_tasa 0 · tarea_sla_contexto 11965 · tareas 13780 · tipo_cambio_diario 11 ·
tipo_cambio_trabajos 12 · usuario_eventos 0 · verificaciones_lead 1621

private: agenda_reparto_cambios 16 · agenda_reparto_destinos 0 · agenda_reparto_diaria 16 · analista_vigencia_exenciones 0 ·
analista_vigencia_tope 0 · analitica_lc_sello 0 · analitica_leads_citas_exenciones 3 · analitica_leads_citas_tope 0 ·
auditoria_alertas 8 · auditoria_condicionada 0 · auditoria_exenciones 0 · auditoria_sello 0 · ayuda_consultas 1 ·
ayuda_expresiones 0 · ayuda_intenciones 0 · ayuda_reglas_aclaracion 0 · backfill_cuentas_p0xx 0 · celulares_estado 0 ·
conciliacion_cuentas_p0xx 0 · contrato_altas_idempotentes 385 · contrato_eliminaciones 0 · contrato_pdf_anexo_emisiones 167 ·
contrato_pdf_jobs 468 · contrato_pdfs 394 · f7_piezas_en_observacion 0 · llamadas_celular_intenciones 0 ·
llamadas_celular_recepciones 9 · membresias_purgadas 0 · pares_autoridad 0 · respaldo_cierre_agosto_2026 0 ·
respaldo_cierre_septiembre_2026 169 · usuarios_retirados 0 · vigia_alertas 24

(*) n_live_tup es estimado; un 0 en tablas de configuración (equipo, sla_politicas, enfriamiento_politica…) puede ser
estadística desactualizada, NO prueba de que estén vacías. Si un hallazgo depende de que una tabla esté vacía, pedir
`select count(*)`.

## Constraints NOT VALID (sin validar): ninguna.

## Tablas sin RLS: solo `private.respaldo_cierre_agosto_2026`.

## Tablas sin PRIMARY KEY (según el volcado): `private.pares_autoridad`, `private.respaldo_cierre_agosto_2026`,
`private.respaldo_cierre_septiembre_2026`.

## Columnas float/money: ninguna. Columnas `timestamp` sin zona: ninguna.

## Tablas con columna numeric de monto/importe/capital/precio/saldo y SIN columna `*moneda*`:
crm.ajustes_mes_cerrado · crm.objetivos_legacy_archivo · crm.objetivos_vendedores_legacy_archivo

## Llaves foráneas SIN índice que las cubra (tabla, constraint, columnas, filas)
crm.lead_sla_etapas lead_sla_etapas_politica_id_fkey politica_id 9356
crm.lead_sla_ciclos lead_sla_ciclos_politica_id_fkey politica_id 4617
crm.ledger_rentabilidad ledger_rentabilidad_politica_id_fkey politica_id 1004
crm.ledger_rentabilidad ledger_rentabilidad_solicitud_id_fkey solicitud_id 1004
crm.inversionista_responsables inversionista_responsables_por_fkey por 789
crm.inversionista_identificadores inversionista_identificadores_creado_por_fkey creado_por 760
crm.inversionistas inversionistas_no_contactar_por_fkey no_contactar_por 755
crm.inversionistas inversionistas_creado_por_fkey creado_por 755
crm.inversion_titulares inversion_titulares_creado_por_fkey creado_por 389
crm.inversiones inversiones_creado_por_fkey creado_por 388
crm.inversionista_leads inversionista_leads_creado_por_fkey creado_por 339
crm.multiempresa_idempotencia multiempresa_idempotencia_creado_por_fkey creado_por 317
crm.postventa_operaciones postventa_operaciones_inversionista_id_fkey inversionista_id 162
crm.cierre_mes_vendedor cierre_mes_vendedor_supervisor_id_fkey supervisor_id 42
crm.operaciones_cartera operaciones_cartera_creado_por_fkey creado_por 27
crm.operaciones_cartera operaciones_cartera_vendedor_id_fkey vendedor_id 27
private.agenda_reparto_cambios cambiado_por / supervisor_anterior_id / supervisor_nuevo_id 16
private.agenda_reparto_diaria supervisor_id / creado_por / actualizado_por 16
crm.inversiones_eliminadas inversiones_eliminadas_contrato_auditoria_id_fkey contrato_auditoria_id 11
crm.reasignaciones_analista reasignado_por / analista_a / analista_de 4
crm.cierres_avance_anulados cierres_avance_anulados_acreditado_a_fkey acreditado_a 4
crm.plazos_carga_mes plazos_carga_mes_reapertura_fkey reapertura_id,periodo 2
crm.recorrido_control actualizado_por 1 · crm.periodos_cerrados cerrado_por 1 · crm.inversion_solicitud_origenes fuente_id, creado_por 1
Con 0 filas: objetivos_vendedores_legacy_archivo (vendedor_id, actualizado_por, supervisor_id), empresas creado_por,
inversionista_fusiones por, multiempresa_flags actualizado_por, backfill_multiempresa_mapa revisor,
politica_rentabilidad (version_anterior_id, publicada_por), solicitudes_tasa politica_id, ajustes_mes_cerrado creado_por,
politica_abandono actualizado_por, sla_operacion_control (politica_adopcion_id, cambiado_por),
politica_gestion_diaria (version_anterior_id, creado_por), piloto_f8_control actualizado_por, piloto_f8_miembros actualizado_por,
inversionista_datos_contacto actualizado_por, configuracion_reparto actualizado_por, postventa_retiros (creado_por, revisado_por)

## Columnas `*_id` SIN llave foránea (y que no son PK)
crm.actividad_ciclo_contexto.gesto_oficina_id uuid
crm.alertas_reconocimientos.alerta_id text · .solicitud_corte_id uuid
crm.backfill_multiempresa_mapa.fila_id uuid
crm.base_carga_operaciones.operacion_id uuid · crm.bases_carga.operacion_id uuid
crm.cambio_cuenta_avisos.solicitud_id uuid
crm.capital_valoraciones.fuente_id uuid
crm.contrato_cuenta_pago_asignaciones: cliente_id, contrato_id, cuenta_bancaria_id, solicitud_id, vinculo_id (uuid)
crm.contrato_cuenta_pago_cambios: cliente_id, contrato_id, cuenta_anterior_id, cuenta_nueva_id, solicitud_id (uuid)
crm.contratos_eliminados_auditoria.contrato_id uuid
crm.conversion_acreditaciones: analista_id, fuente_id (uuid)
crm.conversion_reservas.claim_id uuid
crm.conversion_ventas_recuperadas: acreditacion_id, contrato_vigente_id, fuente_borrada_id, lead_id (uuid)
crm.correcciones_categoria_contrato: actor_id, contrato_id (uuid)
crm.correcciones_correo_acceso.cliente_id uuid
crm.cuentas_bancarias_retiros: cliente_id, cuenta_id, solicitud_id (uuid)
crm.cuotas_cuenta_pagada: contrato_id, cuenta_bancaria_id, cuota_id (uuid)   ← 1408 filas
crm.dispositivos_push_tasa.sesion_id uuid
crm.gestion_diaria_entregas: alerta_id text, solicitud_id uuid
crm.inversion_solicitudes.auth_claim_id uuid
crm.inversiones_eliminadas: fuente_id, inversion_id, inversionista_id, lead_id (uuid)
crm.leads_eliminados.lead_id uuid
crm.ledger_rentabilidad: actor_id, cliente_id, contrato_id, contrato_origen_id (uuid)   ← 1004 filas
crm.llamadas_celular_eventos.evento_origen_id text
crm.origenes_capital_confirmados: cierre_externo_id, contrato_id (uuid)
crm.postventa_escrituras.tarea_id uuid
crm.producto_condiciones.legacy_contrato_id uuid
crm.sla_operacion_recibos: operacion_id, sujeto_id (uuid)   ← 15218 filas
crm.solicitudes_tasa: contrato_id, contrato_origen_id, producto_condicion_id (uuid)
crm.tareas.cancelada_por_id uuid   ← 13780 filas
crm.usuario_eventos: actor_id, objetivo_id (uuid)
private.ayuda_consultas.usuario_id · private.backfill_cuentas_p0xx (cliente_id, contrato_id, fila_id) ·
private.conciliacion_cuentas_p0xx (cliente_id, contrato_id) · private.contrato_altas_idempotentes.actor_id ·
private.contrato_pdf_anexo_emisiones (actor_id, contrato_id, pdf_id) · private.llamadas_celular_intenciones.evento_origen_id text ·
private.llamadas_celular_recepciones.evento_origen_id text · private.membresias_purgadas.perfil_id

## Llaves foráneas hacia `public` (portal) y su ON DELETE (n=set null, c=cascade, r=restrict, a=no action)
Hay ~130. Las que apuntan a `public.contratos`: leads.contrato_id n · contrato_cuentas_pago c ·
private.contrato_altas_idempotentes n · private.contrato_pdf_jobs r · private.contrato_pdfs r · private.contrato_eliminaciones r ·
reasignaciones_analista r · operaciones_cartera (contrato_origen_id r, contrato_nuevo_id r) · inversiones r.
A `public.contrato_titulares`: inversion_cotitular_origenes r. El resto apunta a `public.perfiles` (actor/creado_por/cliente):
cascade en equipo.perfil_id, tareas.perfil_id, cuentas_bancarias.cliente_id, actividades_cliente.cliente_id;
set null en leads.perfil_id, leads.creado_por, actividades.creado_por, cuentas_bancarias.creado_por…; restrict/no action en el resto.

## Tablas SIN columna `actualizado_en`/`updated_at` (113 de 151) — muchas son ledgers/eventos inmutables por diseño
(lista completa en el JSON de origen; destacan tablas mutables: crm.cuentas_bancarias, crm.contrato_cuentas_pago,
crm.metas_vendedor, crm.metas_vendedor_detalle, crm.meta_periodos, crm.sla_politicas, crm.tipo_cambio_diario,
crm.politica_rentabilidad, crm.recordatorios_disponibilidad, crm.verificaciones_lead, crm.depositos_reclamados).

## Tablas SIN columna `creado_en`/`created_at`/`registrado_en` (61 de 151)
private.analista_vigencia_exenciones, private.analista_vigencia_tope, private.f7_piezas_en_observacion, private.membresias_purgadas,
crm.enfriamiento_politica, crm.meta_periodos, crm.sla_politicas, crm.sla_politica_etapas, crm.multiempresa_flags,
crm.tipo_cambio_diario, crm.sla_politica_etapas_operacion, crm.reasignaciones_analista, crm.sla_operacion_control,
crm.capital_valoracion_politica, private.respaldo_cierre_septiembre_2026, private.auditoria_alertas, private.auditoria_exenciones,
private.pares_autoridad, private.usuarios_retirados, crm.politica_rentabilidad, private.backfill_cuentas_p0xx,
private.conciliacion_cuentas_p0xx, private.auditoria_sello, private.analitica_leads_citas_exenciones,
private.analitica_leads_citas_tope, private.analitica_lc_sello, crm.depositos_reclamados, crm.cierres_avance_anulados,
crm.solicitudes_tasa, crm.conversion_reservas, crm.contrato_cuenta_pago_asignaciones, crm.cierre_mes_vendedor,
crm.periodos_cerrados, private.auditoria_condicionada, crm.inversion_solicitud_revisiones, crm.politica_abandono,
private.ayuda_expresiones, private.ayuda_reglas_aclaracion, private.contrato_pdfs, private.agenda_reparto_cambios,
crm.inversiones_eliminadas, crm.configuracion_reparto, crm.postventa_escrituras, crm.inversion_cotitular_origenes,
crm.inversion_solicitud_correcciones, crm.contrato_cuenta_pago_cambios, crm.cuotas_cuenta_pagada, crm.cuentas_bancarias_retiros,
crm.conversion_politica, crm.piloto_f8_control, crm.piloto_f8_miembros, crm.control_citas_versiones,
crm.control_citas_aplicaciones, crm.inversionista_datos_contacto, crm.contratos_eliminados_auditoria,
private.respaldo_cierre_agosto_2026, crm.recorrido_control, crm.leads_eliminados, crm.reaperturas_mes, crm.plazos_carga_mes
(OJO: muchas usan otro nombre para la fecha de alta: `cerrado_en`, `decidido_en`, `aplicado_en`, `generado_en`, `fecha`…
Comprobar en el JSON antes de declararlo hallazgo.)

## Medido aparte sobre crm.leads (misma sesión)
Candados `uq_leads_telefono_vivo` y `uq_leads_dni_vivo` funcionan: 0 leads vivos con el mismo teléfono, 0 con el mismo DNI.
Hueco conocido: teléfono de un lead vivo = `telefono_alternativo` de otro vivo en 15 pares (el índice no cruza columnas).
Ya reportado a Miguel; NO repetirlo como hallazgo.

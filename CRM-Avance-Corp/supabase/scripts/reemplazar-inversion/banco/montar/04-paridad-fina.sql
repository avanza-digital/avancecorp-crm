-- Banco reemplazo-inv (copiado de foto-sla-f2) · paridad fina tras la carga (ejecutar como supabase_admin). Diferencias de TEXTO que un
-- volcado no puede reproducir, sin efecto en permisos ni en reglas, pero que las huellas sí ven:
\set ON_ERROR_STOP 1
begin;

-- 1. 103 tablas/secuencias de crm y private que en producción tienen el permiso «solo del dueño» ESCRITO
--    ({postgres=arwdDxtm/postgres} o {postgres=rwU/postgres}); el volcado las deja con permiso nulo (mismo
--    efecto). REVOKE ... FROM PUBLIC lo materializa igual. Lista generada en producción el 15/10/2026 (solo lectura).
revoke all on table crm.ajustes_mes_cerrado from public;
revoke all on table crm.backfill_multiempresa_mapa from public;
revoke all on table crm.base_carga_leads from public;
revoke all on table crm.base_carga_operaciones from public;
revoke all on table crm.bases_carga from public;
revoke all on table crm.busquedas_cliente_existente from public;
revoke all on table crm.cambio_cuenta_avisos from public;
revoke all on table crm.cartera_lecturas from public;
revoke all on table crm.celulares_asignaciones from public;
revoke all on table crm.cierre_mes_vendedor from public;
revoke all on table crm.cierres_avance_anulados from public;
revoke all on table crm.cierres_externos from public;
revoke all on table crm.configuracion_reparto from public;
revoke all on table crm.contrato_cuenta_pago_asignaciones from public;
revoke all on table crm.contrato_cuenta_pago_cambios from public;
revoke all on table crm.contratos_eliminados_auditoria from public;
revoke all on table crm.control_citas_aplicaciones from public;
revoke all on table crm.control_citas_versiones from public;
revoke all on table crm.conversion_acreditaciones from public;
revoke all on table crm.conversion_pesos from public;
revoke all on table crm.conversion_politica from public;
revoke all on table crm.conversion_reservas from public;
revoke all on table crm.correcciones_categoria_contrato from public;
revoke all on table crm.cuentas_bancarias_retiros from public;
revoke all on table crm.cuotas_cuenta_pagada from public;
revoke all on table crm.depositos_reclamados from public;
revoke all on table crm.dispositivos_push_tasa from public;
revoke all on table crm.empresas from public;
revoke all on table crm.envios_push_tasa from public;
revoke all on table crm.inversion_ajustes_mes_cerrado from public;
revoke all on table crm.inversion_backfill_lotes from public;
revoke all on table crm.inversion_cotitular_origenes from public;
revoke all on table crm.inversion_eventos from public;
revoke all on table crm.inversion_solicitud_correcciones from public;
revoke all on table crm.inversion_solicitud_origenes from public;
revoke all on table crm.inversion_solicitud_revisiones from public;
revoke all on table crm.inversion_solicitudes from public;
revoke all on table crm.inversion_titulares from public;
revoke all on table crm.inversiones from public;
revoke all on table crm.inversiones_eliminadas from public;
revoke all on table crm.inversionista_datos_contacto from public;
revoke all on table crm.inversionista_fusiones from public;
revoke all on table crm.inversionista_gestiones from public;
revoke all on table crm.inversionista_identificadores from public;
revoke all on table crm.inversionista_leads from public;
revoke all on table crm.inversionista_operaciones from public;
revoke all on table crm.inversionista_responsables from public;
revoke all on table crm.inversionistas from public;
revoke all on table crm.lead_asignaciones from public;
revoke all on table crm.lead_potencial from public;
revoke all on table crm.lead_potencial_eventos from public;
revoke all on sequence crm.lead_potencial_eventos_orden_seq from public;
revoke all on table crm.lead_sla_etapa_ajustes from public;
revoke all on table crm.leads_eliminados from public;
revoke all on table crm.llamadas_celular_enlaces from public;
revoke all on table crm.llamadas_celular_eventos from public;
revoke all on table crm.llamadas_celular_politica from public;
revoke all on table crm.multiempresa_flags from public;
revoke all on table crm.multiempresa_idempotencia from public;
revoke all on table crm.origenes_capital_confirmados from public;
revoke all on table crm.periodos_cerrados from public;
revoke all on table crm.piloto_f8_control from public;
revoke all on table crm.piloto_f8_miembros from public;
revoke all on table crm.plazos_carga_mes from public;
revoke all on table crm.politica_gestion_diaria from public;
revoke all on table crm.postventa_escrituras from public;
revoke all on table crm.postventa_operaciones from public;
revoke all on table crm.postventa_retiros from public;
revoke all on table crm.reaperturas_mes from public;
revoke all on table crm.sla_operacion_control from public;
revoke all on table crm.sla_operacion_recibos from public;
revoke all on table crm.sla_politica_etapas_operacion from public;
revoke all on table crm.tarea_sla_contexto from public;
revoke all on table crm.usuario_eventos from public;
revoke all on sequence crm.usuario_eventos_id_seq from public;
revoke all on table private.agenda_reparto_cambios from public;
revoke all on table private.agenda_reparto_destinos from public;
revoke all on table private.agenda_reparto_diaria from public;
revoke all on table private.auditoria_alertas from public;
revoke all on table private.auditoria_condicionada from public;
revoke all on table private.auditoria_exenciones from public;
revoke all on table private.auditoria_sello from public;
revoke all on table private.ayuda_consultas from public;
revoke all on sequence private.ayuda_consultas_id_seq from public;
revoke all on table private.ayuda_expresiones from public;
revoke all on sequence private.ayuda_expresiones_id_seq from public;
revoke all on table private.ayuda_intenciones from public;
revoke all on sequence private.ayuda_intenciones_id_seq from public;
revoke all on table private.ayuda_reglas_aclaracion from public;
revoke all on sequence private.ayuda_reglas_aclaracion_id_seq from public;
revoke all on table private.backfill_cuentas_p0xx from public;
revoke all on table private.celulares_estado from public;
revoke all on table private.conciliacion_cuentas_p0xx from public;
revoke all on table private.contrato_altas_idempotentes from public;
revoke all on table private.contrato_eliminaciones from public;
revoke all on table private.contrato_pdf_anexo_emisiones from public;
revoke all on table private.contrato_pdf_jobs from public;
revoke all on table private.contrato_pdfs from public;
revoke all on table private.llamadas_celular_intenciones from public;
revoke all on table private.llamadas_celular_recepciones from public;
revoke all on table private.respaldo_cierre_agosto_2026 from public;
revoke all on table private.respaldo_cierre_septiembre_2026 from public;
revoke all on table private.usuarios_retirados from public;

-- 2. Tres CHECK que en producción se crearon con BETWEEN (queda un AND anidado). Al recargar el texto del
--    volcado, Postgres aplana los AND y la definición impresa cambia de paréntesis (mismo significado).
--    Se recrean con su forma original; las tablas están vacías.
alter table crm.alertas_reconocimientos drop constraint alertas_reconocimientos_miembros_check,
  add constraint alertas_reconocimientos_miembros_check
  check (cardinality(miembros) between 1 and 2000 and array_ndims(miembros) = 1);
alter table crm.empresas drop constraint empresas_monedas_check,
  add constraint empresas_monedas_check
  check (cardinality(monedas) between 1 and 5 and monedas <@ array['PEN'::text, 'USD'::text] and array_ndims(monedas) = 1);
alter table crm.producto_condiciones drop constraint producto_condiciones_capital_check,
  add constraint producto_condiciones_capital_check
  check (capital_minimo between 100 and 100000000 and capital_maximo between capital_minimo and 100000000);

-- Comprobación: md5 de las tres definiciones = las de producción; si no, se deshace todo.
do $$
declare v_mal int;
begin
  select count(*) into v_mal
  from (values ('alertas_reconocimientos_miembros_check', '207faa60b92c3809bbfa4cca0537687d'),
               ('empresas_monedas_check', 'cb84935d1e61d40b1a3f89c622ba444a'),
               ('producto_condiciones_capital_check', '1c56caef8b9982b1abca3eedd7c062fc')) e(nombre, md5_prod)
  left join pg_catalog.pg_constraint co on co.conname = e.nombre and co.connamespace = 'crm'::regnamespace
  where co.oid is null or pg_catalog.md5(pg_catalog.pg_get_constraintdef(co.oid)) <> e.md5_prod;
  if v_mal > 0 then raise exception 'paridad fina: % restricciones no quedaron iguales a produccion', v_mal; end if;
end $$;

commit;

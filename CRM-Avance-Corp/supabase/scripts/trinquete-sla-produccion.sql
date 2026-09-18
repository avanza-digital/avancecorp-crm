-- Requiere prerrequisito de gobernanza + N1 + N2 + N3 + cierre de reconstrucción.
-- Sólo lectura; no publica política, no cambia modo ni reconstruye filas.
begin read only;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $gate$
begin
  perform private.assert_analista_vigencia();
  perform private.assert_analitica_leads_citas();
  perform private.assert_auditoria();
  perform private.assert_f7_piezas_cerradas();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  -- Se llaman SOLO si existen: este guion corre también contra instalaciones
  -- anteriores a cada pieza, y un `to_regprocedure` nulo no debe tumbar el
  -- corredor entero.
  if to_regprocedure('private.assert_sla_avisos()') is not null then
    perform private.assert_sla_avisos();
  end if;
  if to_regprocedure('private.assert_entrevista_al_asistir()') is not null then
    perform private.assert_entrevista_al_asistir();
  end if;
  if to_regprocedure('private.sla_reconstruir_contextos_lote(uuid[])') is not null
    or to_regprocedure('private.sla_cadena_tarea_reconstruible(uuid,uuid,timestamptz)') is not null then
    raise exception 'La puerta transitoria de reconstruccion debe estar cerrada';
  end if;
end;
$gate$;
select 'OK: SLA completo, gobernanza y contratos N1/N2/N3 verificados; reconstruccion cerrada' as veredicto;
commit;

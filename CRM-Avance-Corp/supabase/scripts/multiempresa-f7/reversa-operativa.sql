-- Desactiva solo la nueva lectura F7. No borra informes firmados ni inversiones.
update crm.multiempresa_flags set activo=false,actualizado_en=now(),actualizado_por=auth.uid()
where nombre='metricas_multiempresa_sombra';

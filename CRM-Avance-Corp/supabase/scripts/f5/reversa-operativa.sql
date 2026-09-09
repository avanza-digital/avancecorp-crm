-- Reversa de operación F5: mostrar la cartera Avance publicada. No borrar datos.
-- Revisar/aprobar el destino antes de ejecutar fuera del banco sintético.
begin;
select nombre from crm.multiempresa_flags where nombre='ficha_360_neutral' for update;
update crm.multiempresa_flags set activo=false where nombre='ficha_360_neutral';
commit;
-- Escritores F4 tienen su propia reversa con candado vigente. Esta reversa no
-- cambia inversiones confirmadas, fuentes, solicitudes, archivos ni permisos.

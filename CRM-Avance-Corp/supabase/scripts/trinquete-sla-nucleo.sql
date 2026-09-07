-- Lectura del gate instalado. No aplica la migracion ni enciende el modulo.
select private.assert_sla_nucleo() as veredicto;

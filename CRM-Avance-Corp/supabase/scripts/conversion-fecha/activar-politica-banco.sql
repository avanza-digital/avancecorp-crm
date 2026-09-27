-- SOLO PRUEBAS DE UNIDAD/INTEGRACIÓN: habilita la rama nueva sin adjudicar
-- crédito a los legados de la plantilla. La instalación y conciliación real
-- se ensayan por separado en prueba-activacion.sql, sin este atajo de fixture.
update crm.conversion_politica set activada_en='2026-09-26 22:00-05',
  manifiesto_huella='solo-banco-sintetico',resultado='{}'::jsonb where unica;

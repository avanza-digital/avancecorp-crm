# Citas por fecha comercial — plan y aceptación
Estado: implementación, revisión y ensayos locales terminados; candidata preparada para el flujo de publicación autorizado. Publicación no ejecutada.
Base inicial: avancecorp/main f1e6f602. Copia aislada autorizada por Miguel: /private/tmp/crm-citas-fecha-comercial-20261017.

## Objetivo
Cada venta de Citas pertenece al mes de su fecha comercial; conservar convertido_en como fecha de registro/auditoría. Conciliar servidor, testigo, tabla, detalle, porcentajes, recuperación, proyección y CSV. Mantener ámbito de Gerencia/Supervisión, identidad canónica, anulaciones y capital.

## Decisión de negocio vigente
Miguel confirmó expresamente la fecha comercial para ventas. Sustituye el uso de convertido_en para atribuir el mes de depósitos. Las entrevistas conservan su fecha propia. La fecha de carga no prueba una venta posterior a una entrevista.

## Fases y aceptación
1. Medición: censo completo septiembre/octubre y casos 001379 (05/09), 001428 (14/09), 001481 (21/09). Identificar diferencias por persona/analista sin exportar PII a git.
2. Servidor: consumir fecha_numerador del núcleo conversion_cierres; separar fecha_comercial y convertido_en; regla idéntica en testigo independiente. No modificar contratos, acreditaciones ni sellos. Extender aditivamente la lectura: campos comerciales y testigo comercial nuevos; semántica anterior conservada para clientes publicados.
3. Pantalla: mes de ventas siempre comercial; importes del núcleo existente; auditoría intacta. Vinculación por fecha de entrevista frente a fecha comercial. Cerrar explícitamente la precisión día/hora y la configuración heredada mes_resultado.
4. Aviso: global, junto al total; diferencias concretas campo/pantalla/servidor; no colocar aviso global en analista. No presentar cifras discrepantes como verificadas.
5. Validación: pruebas unitarias, SQL aislado y permisos, contrato HTTP, E2E Docker, gate del proyecto, revisión independiente; comparar todos los analistas y total de ambos meses. Probar regreso al estado anterior.
6. Entrega: migración nueva + ledger, fuentes y evidencia saneada, instrucciones de publicación/reversa. Sin deploy: requiere flujo humano autorizado.

## Evidencia inicial (17/10 UTC; consulta de solo lectura)
Datos actuales, antes de modificar:
- Septiembre: testigo por registro 99 clientes, pantalla 99; 74 entrevistas, 62 personas, 9 vinculados, 14,52%.
- Octubre: testigo por registro 60, pantalla 57; 84 entrevistas, 79 personas, 17 vinculados, 21,52%.
- Hay 17 cierres registrados en octubre cuya fecha comercial es septiembre. Tres faltan además de la población de pantalla; los otros 14 sí están presentes por otras actividades/asignaciones.
- Exploración por fecha comercial: septiembre 116 clientes; octubre 43. Propuesta por día local para asociar entrevista: 10/62 (16,13%) y 15/79 (18,99%). Son expectativas exploratorias, NO verificación del candidato; comprobar precisión y todos los ámbitos.
- Lecturas actuales: private.citas_gerencia_consulta md5(prosrc)=3dc1c5481ca9dc1a6c45dfab969a6a0b; private.citas_testigo_mes=9df82d2d322795b7875d627da84d69d3.
- Gate de realidad original: NOT RUN por falta de SUPABASE_URL en entorno. Se complementará en SQL/API con la misma fuente y se documentará sin llamar PASS al gate no ejecutado.

## Concurrencia y límites
La carpeta original tiene trabajo ajeno de valoración monetaria y PWA. No modificarla. Otra tarea tiene en preparación citas_gerencia_consulta_v2_fn y private.citas_gerencia_consulta_corte: comprobar Main y producción antes de fijar migración/publicación. No usar sus bancos como destino de escritura.

## Requisitos para completar
- [x] Regla comercial aplicada y fecha de registro intacta.
- [x] Tres contratos y todos los cierres Sep/Oct conciliados, por analista y total.
- [x] Pruebas de carga tardía, mismo día, entrevista posterior, sin fecha verificable, anulaciones, identidades y múltiples contratos.
- [x] Gerencia/Supervisión aisladas; testigo global no visible a supervisor.
- [x] Lectores previos compatibles durante despliegue; capital y meses sellados preservados.
- [x] Tabla, detalle, recuperación, proyección, CSV y ayuda coherentes.
- [x] Aviso concreto y en ámbito correcto.
- [x] Gates y revisión independiente evaluados; límites y NOT RUN de publicación explícitos.
- [x] Reversa y publicación preparadas, sin publicar.


## Resultado vigente
Ver [[RESULTADO]] (`RESULTADO.md`) y los JSON de conciliación. Main incorporado: e4ded65d.

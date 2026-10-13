# Límite sobre el total de cierres referidos

Estado: **PREPARADO Y PROBADO EN LOCAL; SIN ACTIVAR EN PRODUCCIÓN**.
Decisión de Miguel (12/10/2026): el 15 % es un límite del aporte conjunto,
calculado sobre el total de cierres referidos válidos por analista y mes.
No se calcula sobre cierres de Landing/Formulario ni se redondea hacia arriba.

Con 100 llegadas automáticas, 10 cierres automáticos y 4 referidos válidos:
límite referido = 4 × 15 % = 0,60; numerador 10,60; conversión **10,60 %**.
Sin cierres automáticos también existe el límite referido. Si el divisor es
cero, el porcentaje sigue siendo NULL (no calculable).

## Implementación

- Migración nueva: `../../migrations/20261012220959_crm_conversion_limite_total_referidos.sql`.
- `private.conversion_episodios`: límite mensual exacto `total_referidos × tope / 100`.
  Conserva el orden de admisión vigente (fecha comercial, acreditación, UUID).
  Ocho referidos admiten 1,20: aportes 1; 0,20; 0; 0; 0; 0; 0; 0. El último
  admitido puede aportar una fracción. No se aplica 0,15 % a cada cierre.
- El mes completo determina el límite antes de filtrar fechas. Un rango
  parcial puede contener el cierre que aporta 1 y no los demás referidos del mes.
  El navegador muestra el aporte recibido y no recalcula el límite del rango.
- Columna privada `crm.conversion_acreditaciones.ajuste_anulacion_en_sello`: conserva
  el descuento correspondiente a la foto sellada. Miguel confirmó que anular
  cualquiera de cuatro referidos descuenta 0,15 (el límite baja de 0,60 a 0,45),
  con independencia de su posición. Todos los referidos válidos sostienen el
  límite, incluso los que muestran aporte individual cero. Falta del dato sellado
  desde octubre provoca error en lugar de estimar una deuda incorrecta.
- Reglas vigentes desde octubre 2026 aún abierto. Agosto y septiembre conservan
  pesos y fotos. Divisor, ámbitos, operaciones y capital conservan su definición.
  Renovaciones continúan en cero; upgrade elegible conserva su aporte.
- Firmas RPC y permisos sin cambios. La columna nueva no admite acceso directo
  de roles API. Funciones privadas SECURITY DEFINER con search_path vacío.
- Textos alineados en Coordinación, Ranking, Gerencia, Conversión y Hoy del analista.
  Tipos regenerados desde el banco; se conserva metadata PostgREST 14.5.

## Verificación local

Banco exclusivo `avancecorp-conversion-sin-renovaciones-20261012`, PostgreSQL 17,
puerto 55482. Esquema de producción sin datos personales; fixtures sintéticos
con rollback. La reversa fue aplicada y se comprobó la restauración exacta de
los tres cuerpos anteriores; después se reaplicó la candidata.

- `prueba.sql`: 36 aserciones sobre límites, fracciones, ámbito, rango,
  divisor, anulaciones sucesivas y repetidas, cambio de porcentaje posterior,
  septiembre, sello, deuda, cruce de mes y privilegios.
- `lecturas.sql`: 7 aserciones de paridad Conversión/Coordinación/Metas,
  pesos e histórico; incluye SET ROLE authenticated y ámbito individual.
  Esto no sustituye sesiones Auth/HTTP en la rama remota.
- Recuperación: ocho escenarios PASS; reversa rechazada tras sellar o cambiar
  nota, migración rechazada tras sellar, cambiar porcentaje o añadir versión,
  doble aplicación rechazada y espera del candado global de sellado (2,03 s).
- E2E Docker: 3 PASS en detalle de cierres y Conversión de Coordinación,
  con aporte fraccionario, teclado, permisos y filtros.
- Gate integral frontend: PASS, 6.640 tests, lint, typecheck, cobertura,
  build, bundle y duplicación (0,44 %).
- Revisión independiente final: PASS. El primer dictamen detectó la diferencia
  entre deuda posicional y marginal; Miguel confirmó la marginal y se corrigió.
  La segunda revisión validó matemática, mes comercial y concurrencia.
- SELECT/INSERT/UPDATE denegados para anon, authenticated y service_role
  en la nueva columna (nueve combinaciones); postflight comprueba las nueve.
- Evidencia estructurada: `verificacion.json`.
- Rama Supabase, matriz RLS Auth/HTTP, advisors, merge y publicación frontend:
  **NOT RUN / pendientes de activación autorizada**.

## Recuperación y activación

`reversa.sql` restaura las funciones anteriores y retira solo la columna
creada, mientras no existan aportes ni periodos afectados sellados. Rechaza
funciones o configuración distintas de las ensayadas. Conserva renovación 0.
Se tramita por el mismo circuito de rama/merge; no modifica el historial de
migraciones por sí sola. No ejecutar el banco de pruebas en producción.

Antes de activar: volver a comprobar octubre abierto y huellas, crear la rama
Supabase autorizada, aplicar, ejecutar la matriz RLS pertinente y advisors,
fusionar la PR y la rama de base. El frontend se publica por `$release-crm`.
No declarar activa la regla ni cambiar el estado del Figma hasta verificarla.

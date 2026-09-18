# Evaluación del PRIMARY — 18/09/2026

Dos consultas por el wrapper del repositorio, sin herramientas ni escrituras del
reviewer. Ambos dictámenes fueron `CHANGES_REQUESTED`; no se presentan como PASS.
El segundo no encontró P0/P1 y pidió principalmente pruebas adicionales.

## Aceptado y comprobado

- Herencia histórica sobre el tope: UI y SQL permiten la base del origen válido,
  hasta 50 %. Conteo productivo: dos contratos activos/vencidos >28 %. Ensayo
  de base 30 % con política 28 % PASS.
- Enlace de aprobaciones compatibles durante observación para utilizarlas al
  reactivar: conversión por la puerta real y consumo posterior PASS.
- Identidad ajena, documento desactualizado y huella conflictiva: escenarios
  aislados, sin excepción ni cambios en la fila; fila compatible sí se enlaza.
  La identidad ajena en enforcement sigue produciendo P0409. PASS SQL.
- Campo fijo fuera de rango al reactivar: conserva lo escrito, marca el error
  y ofrece confirmar la tasa vigente. Dos pruebas unitarias (alta/corrección)
  comprueban el botón y el resultado; E2E comprueba bloqueo y recuperación.
- Carga inicial de solicitudes antes de inicializar la intención del lead.
  Prueba de respuesta tardía con capital/plazo/modalidad anteriores PASS.
- Preflight de definición completa y mensaje SQL sin formato ambiguo.
  Reversa exacta y conservación de ACL/configuración comprobadas en PostgreSQL.

## Decisiones y observaciones descartadas

- Observación no consume una aprobación que no necesita. Un contrato registrado
  bajo ese modo no está respaldado por esa autorización. La aprobación anterior
  puede utilizarse una vez tras reactivar, mientras siga vigente y corresponda
  a la identidad/intención. El ensayo fija esta secuencia y rechaza un segundo
  consumo en enforcement. Esto conserva el contrato de apagar toda exigencia
  sin cambiar artificialmente el historial de Gerencia.
- El portal sí reinicia `bloqueaGuardado` al consultar y se recupera de un fallo.
  Se conserva la espera breve durante refresco: evita guardar mientras cambia
  la regla. No se introduce una consulta nueva por pulsación.
- Recuperar una bandeja que falló no debe remontar el formulario y borrar lo
  que ya escribió el analista. Se preserva esa edición; el servidor revalida.
  La carrera normal de primera carga quedó cubierta con espera inicial.
- La supuesta base heredada sin regla no se produce en `private.resolver_tasa`:
  para renovación/upgrade exige origen, pertenencia y estado, y asigna
  `heredada_renovacion`/`heredada_upgrade`. El reviewer no recibió ese fragmento
  en la segunda consulta; no se cambia el contrato por esa hipótesis.
- Una republicación de base cambia `contexto` (incluye `base`/`minimo`) y conserva
  la inicialización previa. La hipótesis de que `primera` siempre queda falsa
  en ese caso no corresponde al código.

## Límites declarados

El ensayo es local, con catálogo capturado y datos sintéticos; no sustituye la
matriz RLS/HTTP de una rama remota. Las pruebas nuevas de identidad usan el rol
administrativo solo para preparar fixtures; las comprobaciones financieras
validan actores por JWT y las altas principales se ejercitan con authenticated.
Advisors de candidata, matriz remota y publicación siguen NOT RUN.

El tope heredado permite altas de renovación/upgrade; la corrección conserva
la tasa persistida exacta y la UI restringe negociar una distinta al tope actual.
El trigger conserva su resolución original para correcciones, comportamiento
previo que puede ser más permisivo que el formulario en contratos heredados.
No se amplía esa ruta documental en esta corrección.

El backend decide con la política efectiva por sentencia. La prueba publica
el modo en sentencias separadas y afirma cuál está vigente; cambiarlo dentro
de un solo DO no representa un cambio efectivo para su `statement_timestamp`.

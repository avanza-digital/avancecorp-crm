# Corrección: primera inversión por empresa

Estado: implementación, gate frontend, navegador y revisión de Claude
verificados, incluido el ajuste final del mensaje. Lista para integrar por PR;
todavía no publicada.

## Regla confirmada

El 07/10/2026 Miguel confirmó: cliente con Qorilazo vigente, sin inversiones
previas en Avance/Prodelco → Nueva inversión solo en Avance/Prodelco; Upgrade
solo desde su origen vigente en Qorilazo. Reinversión sigue separada. Esta
decisión sustituye el bloqueo global de #206.

## Cambio

`empresasSinHistorial` usa las cantidades por empresa/moneda del resumen completo
de `inversionista_ficha_fn`, independientemente de la página visible y el saldo
activo. Devuelve estado desconocido si la suma no coincide con el total.

La ficha habilita Nueva inversión cuando queda alguna empresa sin historial y
el actor puede operar. Muestra las empresas disponibles junto al botón. El
formulario solo permite escoger esas empresas y refresca el historial antes de
persistir/preparar una solicitud nueva. No aplica este filtro a una solicitud
ya enviada: mantiene la recuperación idempotente y el tipo de continuidad.

Upgrade conserva sus requisitos de origen activo/vigente. No cambia SQL,
atribución, dinero, contratos, reinversión ni permisos del servidor.

## Alcance y límites

- Cartera propia multiempresa y su formulario. La ficha antigua de Avance no
  produce estos datos ni utiliza el helper.
- Conversión de lead y venta cruzada conservan su comportamiento: sus contextos
  aún no incluyen historial por empresa. No se presenta este cambio como
  enforcement global ni como bloqueo atómico de altas simultáneas.
- `cantidad` proviene de `cartera_f5_fuentes_reales()`: excluye fuentes demo y
  conserva fuentes anuladas/vencidas. Las sesiones demo siguen en la pantalla
  antigua; un lector no puede operar.
- Upgrade en cabecera sigue usando los orígenes de la página visible, como
  antes. La elegibilidad de nueva inversión sí incluye todas las páginas.

## Verificación

- Reproducción del caso exacto: FAIL sobre el bloqueo anterior; PASS corregido.
- `npm run check` final: **PASS**, 393 archivos / **6.305 pruebas**, lint, tipos,
  cobertura, configuración de release, service worker, build, bundle y
  duplicación (0,44 %).
- Regresiones incluidas: ninguna/una/dos/tres empresas, varias monedas y
  páginas, saldo activo cero, totales inconsistentes, permisos revocados y
  fallo de lectura antes de preparar, confirmación con respuesta perdida,
  recuperación de upgrade y reinversión sin reclasificación.
- E2E Docker: **PASS, 32/32**, F5/F6 y ficha anterior/multiempresa,
  un worker, cero reintentos (3,3 minutos). Capturas de escritorio y móvil
  inspeccionadas: Nueva inversión habilitada, selector Avance/Prodelco,
  Upgrade y Reinversión separados.
- Tras limpiar el mensaje al elegir otra empresa: **2/2 E2E PASS** adicionales
  en móvil/escritorio, sin reintentos, y el gate integral repetido en verde.
- `gate:realidad`: **NOT RUN**, falta `SUPABASE_URL` en la copia aislada. La
  regresión reproduce el estado mostrado por Miguel en producción: una sola
  inversión Qorilazo vigente y posibilidad operativa.

## Revisión independiente

Codex PRIMARY, Claude SECONDARY_REVIEWER de solo lectura, mediante
`scripts/claude-review`. Primera revisión de diseño: CHANGES_REQUESTED sobre
recuperación y origen de datos; cambios y evidencia incorporados. Segunda
revisión de implementación: **PASS**, sin cambios obligatorios en el alcance.
Codex incorporó el P3 de limpiar el error al elegir otra empresa y añadió el
caso de refresco antes de preparar Avance.

Evaluación de las otras observaciones:

- No se añade un efecto que borre la empresa seleccionada: la derivación
  detiene el envío si aparece historial. La pérdida del formulario que ya no
  corresponde es deliberada; no se modifica una solicitud enviada.
- Un bloqueo transitorio del servidor conserva el mensaje de actualización en
  curso. El usuario puede reintentar; no se ignora una capacidad denegada.
- La constante anterior sigue usada en `MiCarteraAvance` y `ClienteFicha`.
- `cartera_f5_fuentes_reales()` (migración `20260914025926`, líneas 51–62)
  excluye demos. La versión vigente de `cartera_f5_fuentes()` (migración
  `20260930172255`, líneas 71–142) no filtra empresas por actor y conserva
  anulaciones. Se descarta la hipótesis de ocultación parcial para operadores.
- El registro de lectura limita a un evento por actor/persona/categoría cada
  60 segundos (`20260908230249`, líneas 39–51); el refresco adicional no crea
  un evento por cada envío.

Dos consultas realizadas, sin delegación recursiva.

Evidencia local saneada:
`/private/tmp/crm-inversion-por-empresa-20261007/` (`check-final.log`, `e2e.log`, `e2e-final.log`,
`revision-plan-claude.txt`, `revision-implementacion-claude.txt`).

## Publicación

La fuente inicial es `avancecorp/main` en `3bdfded2c813`. Rama de trabajo:
`fix/inversion-por-empresa`, en la copia aislada
`/private/tmp/crm-continuidad-release-20261006`.

Publicar únicamente después de integrar el PR por las reglas de protección de
Main, verificar igualdad con `avancecorp/main`, generar el artefacto desde ese
commit limpio y pasar el preflight de Hostinger. El despliegue anterior de
Upgrade ya está aplicado; esta corrección no necesita otra migración.

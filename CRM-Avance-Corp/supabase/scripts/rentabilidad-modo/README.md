# Interruptor integral de rentabilidad — 18/09/2026

Estado: implementación y ensayo local terminados; **sin aplicar ni publicar**.

Miguel pidió que el mismo botón controle toda la exigencia de aprobación.
Producción confirmó `modo=observacion` (v14), base 15 % y tope 28 %;
formulario, conversión y bloqueo por solicitudes aún exigían aprobación.

## Comportamiento preparado

- Observación permite pactar la tasa sin solicitar ni consumir aprobación.
  Las solicitudes pendientes o con tope no impiden convertir o contratar.
- Enforcement conserva las autorizaciones y el bloqueo de pendientes.
- Se conservan tasas positivas, dos decimales, tope técnico, identidad,
  permisos, origen contractual y protección de PDF. Una renovación/upgrade
  puede heredar una tasa histórica superior al tope actual (máximo absoluto
  50 %). Producción tiene dos contratos activos/vencidos superiores al 28 %.
- Las solicitudes anteriores conservan su estado. Al convertir en observación
  se enlazan las que corresponden a la misma identidad y no tienen conflictos;
  las incompatibles permanecen en el lead y no bloquean. Una aprobación
  compatible sigue sirviendo si se reactiva antes de crear el contrato.
- CRM y portal consultan el modo al recuperar foco y cada 30 segundos mientras
  está abierto el formulario operativo. El servidor vuelve a validarlo al guardar.
- Un servidor anterior sin `observacion_sin_aprobacion=true` conserva los controles
  anteriores. Esto permite instalar el frontend antes del SQL sin abrir un hueco.

## SQL y recuperación

Migración: `../../migrations/20260918210543_crm_modo_rentabilidad_integral.sql`.
Reversa preparada: `reversa.sql`. Ninguna se ejecuta automáticamente en producción.
Ambas comprueban la huella de la definición completa de cada función antes de
reemplazarla, incluidos atributos. No cambian firmas, grants, RLS, propietario,
datos de negocio ni el modo elegido por Gerencia.

Antes de aplicar: confirmar el SQL exacto; rama Supabase autorizada, matriz RLS
y advisors; integrar por el flujo de migraciones del proyecto. La publicación del
CRM requiere invocación humana de `$release-crm` o `/release-crm`. Publicar desde
el mismo commit verificado en main local y `avancecorp/main`.

La reversa devuelve las ocho definiciones anteriores, pero no borra contratos
registrados legítimamente mientras estuvo habilitada la observación. Si se
revierte, recuperar también los recursos frontend del artefacto anterior.

## Verificación

Desde la raíz del repositorio, con Docker local disponible:

```sh
python3 CRM-Avance-Corp/supabase/scripts/rentabilidad-modo/verificar-local.py
```

El runner crea y elimina su propia base en `supabase_db_avancecorp-f4-bank`,
partiendo de la plantilla sintética `crm_push_tasa_release_20260910`. No conecta
a destinos remotos. `base-funciones.json` contiene las ocho definiciones leídas
del catálogo vigente; `base-puertas.json` contiene las dos puertas actuales de
alta necesarias para transportar el origen de upgrade que faltaba en la
plantilla antigua. Son código, sin filas de clientes ni credenciales.

PASS:

- Ocho funciones reemplazadas conservando propietario, ACL, configuración,
  seguridad y volatilidad; reversa exacta comprobada.
- Regresiones SQL de tasas inferiores, pendientes y solicitudes en leads.
- Cambio mediante la RPC real de publicación de política; altas desde 0,01 hasta
  28, pendiente que deja de bloquear, rechazo de nuevas solicitudes y excesos.
- Conversión en observación y alta después de reactivar utilizando la misma
  aprobación anterior; se verifica el modo efectivo en sentencias separadas.
- Herencia de 30 % con tope 28, corrección sin PDF dentro del rango, rechazo
  sobre el tope y protección de un contrato congelado por PDF.
- `npm run check`: 248 archivos, 3.697 pruebas, tipos, lint, cobertura, build,
  tests de configuración/SW, bundle y duplicación. Cuatro avisos de a11y
  preexistentes en `coverflow-carousel.tsx`.
- Ocho Playwright focalizados: observación escritorio/móvil, refresco sin cerrar
  sesión, solicitudes en enforcement y tasas inferiores anteriores.
- Portal: sintaxis de los cuatro JS y tres pruebas del rango nuevo. Banco
  completo: 86/88; los mismos dos fallos previos del baseline (83/85).
- Preflights offline de seed y RLS (13 sesiones); no equivalen a la matriz remota.

FAIL preexistente: portal `asiento-operaciones.test.mjs` (función de rol) y
`contrato-pdf-servidor.test.mjs` (versiones literales antiguas). Se reprodujeron
también sin este cambio; no se modificaron sus expectativas para ocultarlos.

NOT RUN: rama remota, matriz RLS autenticada remota, advisors de la candidata,
publicación y recorrido productivo. `gate:realidad` general no arrancó por falta
de variables de servidor en el shell; el estado relevante de política y las
ocho definiciones se comprobaron mediante SELECT en producción.

## Revisión y límites

Review independiente por `scripts/claude-review`, incluida revisión de permisos.
Se corrigieron herencia histórica, enlace de aprobaciones, campo fijo inválido
al reactivar, carga inicial del lead y preflight de atributos. Las decisiones y
dictámenes se conservan en `revision-inicial.md` y `revision-final.md`.

Las dos consultas de modo pueden actualizarse en instantes distintos, hasta
30 segundos. Un cambio concurrente al guardar puede exigir volver a revisar
la tasa; el servidor no confía en el modo enviado por el navegador. La bandeja
de solicitudes conserva su historial y las solicitudes anteriores pueden volver
a bloquear al reactivar. Correcciones documentales del portal siguen haciéndose
desde el CRM, que mantiene el procedimiento de PDF.

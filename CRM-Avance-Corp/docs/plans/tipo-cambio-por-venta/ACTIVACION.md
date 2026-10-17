# Activación y reversa — pendiente de flujo autorizado

La publicación/activación fue autorizada con «ok publiquemos». La organización
y el coste de la rama temporal se confirmaron expresamente. Estado real de la
ejecución en PUBLICACION-20261017.md; este runbook no acredita pasos aún pendientes.
El envío de avisos sigue sin autorización. El objetivo no incluye modificar el
estado de `crm-cierre-mes-diario`.

## Condiciones previas

1. Revisar ESTADO.md y la revisión independiente final. Cerrar fallos pendientes
   y ejecutar los gates del proyecto. La lista dinámica de candidatas está en
   `supabase/scripts/tipo-cambio-por-venta/migraciones-locales.mjs`; la fundación
   `20261016190725` se aplica primero. Hoy son once candidatas, incluidas la de
   índices `20261017025829`, cierre acotado `20261017033241` y censo `20261017040525`. No volver a aplicar las guardas a una rama ya
   modificada: ensayar el replay desde la base original.
2. Preparar un commit revisado sin incorporar cambios ajenos del worktree.
   Main local y `avancecorp/main` deben apuntar al mismo commit verificado antes
   de construir/publicar. No utilizar `origin/main`, tronco ni una rama de
   release alternativa. No publicar el build de este worktree sucio.
3. Nuevo inventario de solo lectura (`inventario.sql`) y simulación BCRP con sus
   respuestas originales. El último ensayo de 116 operaciones / S/ 4 650 700,67
   es evidencia de su captura, **no un censo congelado para activar**. Comparar ids,
   firma monetaria y mes de imputación; comprobar fechas y deudas monetarias.
4. Octubre debe seguir abierto o tener un sello compatible, con cobertura
   completa. Acreditar el corte de cualquier operación preoctubre imputada en
   octubre. Metas comerciales en PEN; no convertir metas USD con una tasa viva.
   El preflight candidato rechaza datos sin correspondencia, fechas incoherentes
   y metas USD que no tienen equivalente fijo.

## Orden autorizado de aplicación

1. Crear la rama/instancia de Supabase autorizada y verificar las guardas contra
   el esquema vivo. Aplicar por CLI las nuevas migraciones documentadas. No
   cambiar objetos de public ni migraciones ya registradas. La política nace
   apagada, así que los lectores anteriores conservan su contrato.
2. Publicar Edge `crm-capital-valorar` con `verify_jwt=true`; el handler exige
   además `Authorization: Bearer <service_role exacta>`. La clave permanece en
   el entorno de Edge y en el almacén secreto del servicio invocador. Nunca en
   el bundle, SQL versionado, parámetros de URL, capturas ni logs.
   Configurar `CRM_CAPITAL_VALORAR_SERVICE_KEY` con la service_role JWT vigente
   del proyecto: algunas ramas asignan una clave moderna sb_secret a la
   variable reservada, que no es válida para el gateway JWT. Se conserva tanto
   verify_jwt como la comparación exacta del handler; no se rotan claves ni
   se cambia la autenticación de las otras Edge.
3. Preparar una invocación de servidor POST con cuerpo `{}` y esa autorización.
   El worker descubre fechas, reserva trabajos, consulta las dos series BCRP y
   reconcilia por lotes de hasta 500. Para cada lote consume hasta tres fechas;
   no acepta tasas ni operaciones proporcionadas por el cliente.
4. Completar el relleno real con el proceso idempotente: ejecutar el worker y
   repetir hasta cobertura completa, incluyendo altas concurrentes. Cotización
   sin consolidar significa pendiente; no sustituirla manualmente ni reutilizar
   la actual. Conservar respuestas, pares, huella y revisiones.
5. Construir el bundle compatible desde el commit verificado y realizar el
   flujo humano de publicación del proyecto. El preflight obligatorio es
   `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>`
   desde la raíz Git. Validar release, manifiesto y versión visible; comprobar
   con las sesiones de aceptación que se usan las RPC v2/v3. Los clientes
   abiertos deben actualizarse antes de evaluar las cifras nuevas.
6. Desde un servidor autorizado, consultar
   `crm.preflight_capital_valorado_fn()`. Conservar su respuesta y tomar su
   `huella` inmediatamente antes de llamar a
   `crm.activar_capital_valorado_fn(p_bundle,p_huella)`. `p_bundle` identifica
   el artefacto compatible realmente publicado. Si cambia el censo o cualquier
   guarda falla, reconciliar/investigar y repetir preflight, sin eludirlo.
7. Programar únicamente el nuevo worker con el mecanismo autorizado de Cron o
   servidor. Antes, comprobar sus secretos y URL exacta de proyecto; no registrar
   la clave en texto en `cron.job.command`. Usar un almacén secreto restringido
   y una invocación que lea la clave al ejecutar. Elegir periodicidad operativa
   según rezago/carga medidos; el backoff de publicación ya es persistente.

No pausar/reactivar el job 3 como efecto colateral. Su última lectura fue activo;
volver a leerlo. La reevaluación anticipada es una RPC distinta, posterior al
commit de reconciliación; solo solicita el ciclo nativo si encuentra cron único,
activo y compatible. El ciclo decide los periodos/plazos existentes, incluidos
los meses previos; no es una orden de sellar septiembre ni octubre. Si Gerencia
necesita mantener un periodo abierto, resolver esa gobernanza existente antes
de autorizar la operación del worker.

## Verificación y seguimiento

- Releer el mismo corte de Ranking, Metas, Facturación y detalle; contrastar por
  operación y analista con la simulación. Cambiar la cotización de consulta no
  cambia el equivalente aceptado. En Citas conservar su medida sin anulados.
- Revisar cobertura por rol y señales `pendientes`, `por_incorporar`, `sin_corte`
  y `atascado`. Antes del primer corte no hay posición ni total convertido
  parcial. Después se conserva la publicación completa anterior.
- Vigilar `tipo_cambio_trabajos`: intentos, próxima ejecución, reserva vencida,
  motivo y completado; y los tiempos del último corte. El plazo excedido en 24 h
  muestra atascado y mantiene el mes abierto. Un HTTP 200 del BCRP no demuestra
  publicación completa; el worker exige los pares y la confirmación temporal.
- La respuesta Edge distingue fallos del proveedor de una solicitud de cierre
  pendiente. Fallar esa solicitud no revierte la valoración ya confirmada; el
  ciclo normal conserva su siguiente oportunidad y la pausa se respeta.
- Ensayar en la rama la caída prolongada de proveedor, recuperación, cierre
  simulado, lectura posterior y reversa. Repetir censo/preflight al pasar a vivo.
- Registrar estado de Cron, hash de fuente, migraciones, bundle, censo,
  simulación, respuesta de activación y verificación de solo lectura. El gate de
  realidad pendiente de ESTADO.md no debe presentarse como PASS.

## Reversa

Desde servicio autorizado, `crm.suspender_capital_valorado_fn()` suspende la
presentación nueva de meses abiertos. Deshabilitar solo la programación del
worker nuevo si corresponde. Mantener el cron de cierre existente como lo
disponga su operador; no alterarlo automáticamente.

**Con sellos nuevos, conservar un bundle que entienda sus RPC y versión.** La
lectura v2 sigue fijando los meses sellados aunque la presentación esté
suspendida. No volver a un cliente que recalcule esos sellos con TC mensual.
Conservar tasas, evidencia, valoraciones, auditoría y cortes: no borrar datos,
truncar tablas, deshacer la historia ni reemplazar una tasa consolidada.

**Suspender no pausa el cierre existente.** Si un mes desde octubre se cierra
con la política suspendida, se conserva su régimen anterior y la reactivación
automática queda bloqueada por sello incompatible. Antes de una suspensión que
alcance un cierre mensual, acordar la gobernanza del periodo con su operador.
No modificar cron de forma automática ni reconstruir ese sello después: una
eventual recuperación exige una decisión y migración explícitas que preserven
la historia. La reversa no promete reactivación tras un sello incompatible.

## Aviso preparado (no enviado)

Desde octubre de 2026, cada venta conserva su tipo de cambio de la fecha
comercial. Una venta de USD 20 000 a 3,40 aporta S/ 68 000 aunque después cambie
la cotización. El ranking muestra el último corte completo y avisa si hay
ventas pendientes de valorar. Actualiza el CRM para consultar esta medida.
Las cifras de meses anteriores conservan su regla vigente.

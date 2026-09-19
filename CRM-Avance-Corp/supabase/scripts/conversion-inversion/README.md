# Conversión mediante Nueva inversión

Estado al 19/09/2026: implementado y probado en una carpeta independiente;
**sin instalar la candidata ni publicar frontend/Edge en producción**.
Base integrada: Main `4d33785eddd629483ca26aefc606534a823be5ee`.

## Resultado

`InversionDesdeLead` reconoce la identidad y abre el mismo `InversionNueva`
que usa Cartera. Desaparece el formulario real de conversión anterior.
Avance usa `ContratoNuevo`; Qorilazo/Prodelco usan `InversionCooperativa`.
Campos, cuentas, comprobantes, validaciones, correcciones y confirmación
pertenecen al proceso compartido.

El lead permanece abierto mientras se prepara o revisa la solicitud. La
confirmación escribe inversión, fuente, conversión y actividad en la misma
transacción. Conserva el analista de la relación y los indicadores iniciales
que usan Cartera y las métricas, con PEN y USD separados. Los lectores de
capital no se sustituyen.

Cerrar permite continuar después. Cancelar la solicitud es una acción
explícita adicional, común a ambos accesos: conserva antecedentes y libera
la elección de empresa/moneda. No cancela una inversión confirmada. Si hay
un acceso Avance en curso, exige recuperarlo antes de cancelar; el acceso
ya terminado se conserva y reutiliza. Reconocer una identidad y preparar
el acceso no se presentan como una conversión confirmada.

El origen del lead es inmutable. Un índice parcial impide dos solicitudes
vigentes del mismo lead, incluso con claves diferentes. La recuperación
puede usar el servidor sin depender del almacenamiento del navegador.
La ficha del lead convertido ofrece **Ver inversión y bienvenida**.

## SQL y transición

La candidata es
[`20260919161807_crm_conversion_inversion_unificada.sql`](../../migrations/20260919161807_crm_conversion_inversion_unificada.sql).
`generar.mjs` la reproduce desde las definiciones saneadas y los bloques
`contexto.sql`, `cancelar.sql` y `bienvenida.sql`. Las 18 anclas de funciones
impiden instalar sobre definiciones distintas a las verificadas.

Añade dos columnas a `crm.inversion_solicitudes`, un índice único, una
restricción de origen y tres triggers de CRM; crea 11 funciones y sustituye
10. No altera tablas, funciones, triggers ni policies del esquema `public`.
Los escritores contractuales/alta de acceso existentes siguen siendo los
que producen los hechos del portal.

La instalación se niega si hay una conversión antigua abierta con reserva
activa o efectos iniciados. Bloquea nuevas reservas del formulario viejo
antes de Auth, y evita que una pestaña vieja cierre un lead sin su inversión
confirmada. Los resultados históricos idempotentes se conservan.

La consulta periódica conserva los controles de ámbito y usa variantes de
lectura sin los locks de fila/documento del escritor. Un fallo temporal
conserva el formulario pero suspende acciones hasta revalidar. Una revocación
retira los datos. El escritor siempre vuelve a validar bajo sus candados.

Main incorporó el modo integral de rentabilidad y la entrevista automática
durante la pausa. `actualizar-base.mjs` aplica sus migraciones completas sólo
en las copias sintéticas propias. Conserva 14 anclas y actualiza las dos
dependencias de tasas. El modo elegido por Gerencia continúa mandando;
esta candidata no vuelve a instalar los validadores de tasas anteriores.

## Bienvenida

La Edge `crm-inversion-bienvenida` se invoca después de confirmar una primera
inversión Avance con acceso nuevo. Autentica al usuario y comprueba su ámbito
antes de reclamar el envío mediante una RPC exclusiva de servicio. Destinatario
y plantilla quedan fijados; un reintento no vuelve a confirmar la inversión.
Los tests sustituyen sólo el proveedor externo: no se envió correo real.

Un cierre de pestaña se recupera desde el lead convertido. Si la respuesta
del proveedor se perdió, se reutiliza la misma clave de idempotencia. Después
de 23 horas la entrega incierta pasa a `verificar_entrega` y se suspende el
reenvío automático. Gerencia/soporte debe verificar esa entrega en el proveedor;
no hay una cola automática ni una acción que permita fingir una entrega desde
el navegador. La inversión sigue confirmada.

La plantilla conserva la política de contraseña temporal del portal existente.
Cambiar esa política por enlaces de establecimiento de contraseña es un trabajo
de autenticación distinto, no una condición añadida para registrar inversiones.

## Verificación

PASS en la copia aislada:

- `npm run check` en `app`: 248 archivos, 3.694 pruebas, lint, tipos, cobertura,
  configuración de release, SW, build, bundle y duplicación. Persisten los
  cuatro avisos anteriores de accesibilidad de `coverflow-carousel`.
- 15 pruebas HTTP con Auth, PostgREST y Storage reales: ámbito, tres combinaciones
  cooperativa/moneda, Avance DNI/CE/pasaporte, cancelación y cambio de moneda,
  doble clave simultánea, confirmaciones repetidas, reasignación, fusión antes
  y después de confirmar, pérdida de respuesta de Auth y entrega idempotente.
- Oráculo SQL con rollback: contrato/cuenta/cronograma, fallo tardío que revierte
  todo el cierre, aprobación pendiente/tope no aceptado/vencida/cambio de capital,
  aprobación válida consumida una vez y atribución comercial.
- Replay completo desde copia sin candidata y reversa exacta: 11 funciones
  nuevas, 33 verificaciones de permisos, propietario y `search_path`; definición
  de `public` idéntica antes/después. Las 16 definiciones base se restauran.
- Navegador con backend real, escritorio y móvil: conversión, cerrar/retomar,
  recuperación desde el lead convertido, comprobante con respuesta perdida,
  inversión adicional de Cartera, dos inversiones y una sola conversión inicial.
- Preflights de scripts y Edge; cuatro tests de frontera de la bienvenida y
  `deno check` de su entrada. Seed y RLS offline con valores ficticios, sin conexión.

La regresión general terminó con 201 PASS, 26 SKIP preexistentes y una expectativa
obsoleta: exigía bloquear la entrada completa por una tasa Avance. Se actualizó
para entrar al formulario común, conservar el 20 %, verificar el bloqueo en
enforcement y habilitar la revisión al cambiar a observación. El archivo afectado
se repitió completo: 3 PASS. Son 202 casos distintos aprobados y 26 omitidos entre
ambas ejecuciones; no se presenta como una sola ejecución completa sin fallos.
Detalles en `evidencia-final.json`. Las capturas y trazas están en el directorio
temporal del ensayo; no contienen clientes reales.

NOT RUN: rama remota/advisors de esta candidata, matriz autenticada remota,
instalación productiva, envío real de bienvenida y publicación. La matriz HTTP
local prueba los roles nuevos; el preflight offline no sustituye la matriz remota.

## Reproducir

Los scripts sólo admiten bases locales con nombres fijos de este ensayo.
Necesitan Docker y la plantilla sintética existente `prodelco_usd_20260917`.
No borran ni reinician una copia ya existente.

```sh
node supabase/scripts/conversion-inversion/actualizar-base.mjs
# Sólo si aún no existe el banco principal:
node supabase/scripts/conversion-inversion/banco.mjs crear
node supabase/scripts/conversion-inversion/generar.mjs
node supabase/scripts/conversion-inversion/banco.mjs aplicar
node supabase/scripts/conversion-inversion/banco.mjs test
node supabase/scripts/conversion-inversion/replay.mjs
node supabase/scripts/conversion-inversion/fixture-http.mjs catalogo
node supabase/scripts/conversion-inversion/http-banco.mjs iniciar
node supabase/scripts/conversion-inversion/http-banco.mjs servidor
# En otra terminal, con el servidor propio activo:
node supabase/scripts/conversion-inversion/fixture-http.mjs
node --test supabase/scripts/conversion-inversion/http.test.mjs
cd app
npm run test:e2e -- --config=playwright.conversion.config.ts
```

`tipos.mjs` obtiene los tipos con postgres-meta e integra sólo los seis nodos
tocados. Conserva los tipos curados y la advertencia de Main sobre la regeneración
completa, que tiene una incompatibilidad previa con argumentos opcionales `null`.

## Instalación pendiente y recuperación

1. Revisar el SQL exacto y `huellas.json`; obtener la autorización exigida por
   `supabase/migrations/LEEME.md` y el vault. Verificar de nuevo anclas y reservas.
2. Validar en una rama Supabase autorizada, ejecutar su matriz RLS y advisors;
   integrar por el flujo de migraciones. No aplicar directamente a producción.
3. Instalar la Edge de bienvenida con sus secretos de servidor y la validación
   manual de sesión. Publicar después el frontend mediante invocación humana
   de `$release-crm` o `/release-crm`, desde el commit verificado en Main y
   `avancecorp/main`. No reutilizar el build de ensayo como artefacto productivo.
4. Comprobar las tres empresas, tasas en ambos modos y métricas sin duplicar
   operaciones reales. Un correo pendiente no debe provocar una nueva inversión.

`reversa.sql` conserva hechos y columnas aditivas. Se niega si quedan solicitudes
de conversión preparadas; primero hay que finalizarlas o cancelarlas mediante
el proceso nuevo. Revierte escritores y guards anteriores sin borrar inversiones,
auditoría ni entregas. Su ejecución requiere autorización propia y comprobación
de que ninguna publicación posterior cambió esas funciones.

## Revisión y aislamiento

`revision-independiente.md` conserva el dictamen **CHANGES_REQUESTED** de Claude
antes de las correcciones; `decision-review.md` explica lo aceptado y lo descartado
con evidencia. No se atribuye al reviewer una aprobación posterior inexistente.

Miguel autorizó trasladar únicamente esta tarea. Los 33 archivos iniciales se
movieron con comparación SHA; los cambios de la otra sesión permanecieron en su
carpeta. Trabajo actual: `/private/tmp/avancecorp-conversion-wt`, rama
`codex/conversion-inversion-20260919`. El respaldo original y el stash previo
a integrar Main se conservan fuera del directorio de producto.

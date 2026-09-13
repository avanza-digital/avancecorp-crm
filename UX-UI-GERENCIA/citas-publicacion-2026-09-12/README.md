# Citas Gerencia — preparación verificada el 13 de septiembre de 2026

La reparación del lector y de su actualización en pantalla está verificada en
una copia aislada del frontend y en la rama Supabase `citas-validacion-20260912`
(`xhgsjtzpmwlqfkninphl`). **No se instaló ni publicó esta entrega en producción.**
La matriz RLS general conserva fallos anteriores; esta evidencia no equivale a
un PASS global del CRM.

## Alcance

- La consulta obtiene los estados y cierres de los núcleos existentes. Conserva
  el contrato V2, la cohorte mensual y su historial entre meses; incorpora el
  estado comercial canónico sin cambiar la regla de conversión a cliente.
- Cambios de citas, conversiones, anulaciones y recargas invalidan el detalle
  correcto. Una respuesta antigua en vuelo no reemplaza una actualización.
  La vista activa consulta cada 60 segundos y respeta actor, mes y filtros.
- El control analítico mantiene sus 34 candidatos inventariados: comprueba
  definición, propietario y permisos de cuatro auxiliares y aplica el techo
  30 a los otros 30. No cambia el contenido de las funciones financieras.
- Se elimina del artefacto un enlace `config-citas` que había llegado a HEAD
  sin sus rutas/tipos. El borrador de Superadmin permanece en el workspace.
  Se fija la fecha del fixture de Rentabilidad que vencía el 13/09; no cambia
  su lógica productiva.

**Fuera de esta entrega:** configuración de nuevas metas, objetivo 1,25 citas
por lead, tasas del 70%, proyección mensual y ticket por analista. Continúan
como borradores con decisiones pendientes; esta reparación no los activa.
Los cambios de Leads recibidos por día pertenecen a otra entrega.

## Resultado de verificación

| Puerta | Resultado y alcance |
| --- | --- |
| Frontend aislado `npm run check` | PASS: 3.413 pruebas en 235 archivos, TypeScript, lint, build y controles del paquete. |
| Playwright aislado | PASS: 173 pruebas; 26 omitidas por sus condiciones existentes. Las omitidas no se presentan como ejecutadas. |
| Scripts / preflight Edge | `npm run check:scripts`, `npm run test:edge-preflight`: PASS. |
| Esquema base remoto | PASS: 623 funciones y sus permisos, 275 migraciones y las superficies de esquema contrastadas con el padre; sin copiar clientes reales. Ver `paridad-base.json`. |
| Auth / PostgREST de Citas | PASS: 32 comprobaciones con sesiones reales. Ver `citas-http.log`. |
| Contratos de núcleos y lector | PASS: 52 comparaciones completas, mismo actor y corte temporal; sólo se retira el campo aditivo al comparar el JSON antiguo. Ver `paridad-nucleos-remota.log`. |
| Límite de historial | PASS: 10.000 filas íntegras, sin duplicados; 10.001 produce 54000. Consulta de la muestra: 586 ms y 7.350.226 bytes. |
| Cohorte heterogénea | PASS: 2.500 leads, 10.000 citas y 100 cierres. JSON anterior/nuevo idéntico salvo el campo aditivo. Anterior 7.201 ms; nuevo 556 ms. |
| Preflight y atomicidad SQL | PASS en ambas candidatas: deriva detectada antes de aplicar; fallo inducido antes del COMMIT revierte funciones, gobernanza y datos. Ver `ensayo-migraciones.json`. |
| Mutantes de gobernanza | PASS: diez mutantes clásicos y la batería ampliada de auxiliares rechazados; pruebas revierten sus cambios. |
| Revisión independiente | PASS de implementación; alcance y evidencia en `review-implementacion.md`. El wrapper de Claude no produjo dictamen en esta preparación; no se contó como aprobación. |
| Matriz RLS completa A/B | **FAIL global; PASS de ausencia de regresiones.** Antes y después: 1.778 PASS y los mismos 49 FAIL, sobre 1.827 comprobaciones. |
| Advisors | Sin avisos nuevos de esquema/funciones ni de rendimiento. Se observó después una advertencia Auth de contraseñas filtradas, confirmada también en el padre; se conserva explícitamente en el comparativo. |

Los tiempos son mediciones únicas del banco sintético, no un SLA ni una
predicción de producción. La primera ejecución de Playwright falló al usar
`node_modules` mediante symlink fuera del árbol permitido por Vite; el resultado
final procede de dependencias copiadas dentro del checkout aislado.

### Qué cubre el recorrido real

Gerencia autorizada; otros doce usuarios y anónimo denegados; rechazo de mes
parcial; perfil o membresía de Gerencia inactivos. Alta de lead por
`crear_lead_si_disponible`, cita presencial con ubicación, inasistencia del mes
anterior, siguiente cita, reprogramación, asistencia con actividad real,
cancelación humana y cancelación por conversión. La conversión a cliente se
cuenta una vez por lead; la ausencia recuperada y la entrevista tienen cierre
posterior; una cita fechada después del cierre no lo recibe. Anular retira el
cierre y conserva el historial. Un cierre externo usa el núcleo operativo,
pero no inventa un perfil cliente ni infla conversiones a cliente.

### Preparación y límites del banco

Sólo contiene identidades y operaciones ficticias. Los usuarios Auth se
crearon confirmados por la API administrativa sin enviar correo. Las pruebas
no invocan Edge Functions ni generan contratos o movimientos reales.

La comparación RLS utiliza la misma semilla restaurada antes de instalar las
candidatas. Normaliza únicamente UUID ficticios al comparar el multiconjunto
de fallos. No se descartan fallos por nombre ni se asumen inofensivos. Los 49
casos están íntegros en `rls-antes.json` y `rls-despues.json`.

Después del A/B se completó el singleton de control SLA que faltaba en la
semilla. Sin él, `sla_conceder_prorroga` producía P0002 al cerrar una cita.
`semilla-control-sla.sql` reproduce la configuración del padre sustituyendo
el actor por Gerencia ficticia; inicializa y reactiva la guarda en una sola
transacción. No modifica el código de negocio. No se repitió la matriz general
con esta semilla ampliada: sus cifras corresponden exclusivamente al A/B.

Las muestras masivas se crean por el writer interno con todas las restricciones
y triggers activos. Esto conserva `creado_en = now()` en el ensayo transaccional;
los inserts humanos usan `clock_timestamp()` después del lock y se verifican
en las peticiones HTTP sucesivas. Las 100 trayectorias de la cohorte usan las
RPC de asistencia y cierre con el actor analista. Ambos ensayos de volumen
terminan en ROLLBACK; se verificaron cero residuos y cero triggers CRM apagados.

## SQL preparado

| Migración | SHA256 del archivo probado |
| --- | --- |
| `20260912151320_crm_citas_consulta_nucleos.sql` | `2ce0fc80f3610c9df2cbac22fc96283922b6c6076b90202de8c82b35aba22a02` |
| `20260912181045_crm_analitica_auxiliares_verificados.sql` | `f131be0636b9564f63d78810ca7b1429d437d3a1a22be21d01c117f60599d1d9` |

Se aplicaron secuencialmente en la rama y se registraron después mediante
`supabase migration repair --status applied`, que sólo regulariza el historial
de SQL ya ejecutado. El banco terminó con 277 versiones y el gate:

> 34 candidatos declarados; 30 sujetos al techo 30; 4 auxiliares verificados; 0 sin declarar.

Ver `banco-final-verificado.json`. Los helpers nuevos sólo permiten ejecución a
postgres; se conservan la puerta de Gerencia y los permisos RPC. No hay cambios
de tablas ni firmas expuestas que requieran regenerar tipos. No se aplicó la
migración del borrador de Superadmin. El padre seguía con las 275 versiones
anteriores en la captura `produccion-previa-2026-09-13.json`.

## Repetición y entrega

Los scripts `supabase/scripts/test-citas-nucleos-*.sql` y
`test-citas-nucleos-remoto.mjs` requieren un banco desechable con el esquema y la
semilla completos. `preparar-test-citas-nucleos-remoto.py paridad|cohorte` genera
los oráculos desde las fuentes originales versionadas y emite un lote con
ROLLBACK. Usar una misma sesión SQL y `ON_ERROR_STOP`; comprobar antes el
proyecto de destino. El ejecutor privado usado para esta entrega rechaza
cualquier destino diferente de la rama propia. Credenciales, dump del esquema
y logs privados de preparación no se versionan.

El artefacto debe construirse desde un checkout limpio del commit que coincida
con `main` y `avancecorp/main`, con la configuración pública de producción.
Su manifiesto registra el commit, migraciones y hashes; verificarlo con
`npm run release:crm:verify`. Crear el ZIP no instala SQL ni publica la web.

**Pendiente para una publicación:** revisar/aceptar expresamente la deuda de la
matriz general, autorizar la instalación de estas dos migraciones y completar
los gates del despliegue real. No se ha ejecutado instalación SQL productiva,
publicación HTTP ni smoke productivo de esta entrega: **NOT RUN**.

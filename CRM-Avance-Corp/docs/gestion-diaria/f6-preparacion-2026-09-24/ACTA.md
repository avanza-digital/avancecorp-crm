# F6 — Cola completa preparada en Gestión Diaria

24/09/2026. **Preparación aditiva verificada; sin publicar ni retirar Seguimiento.**
F5 fue integrada por `miguejbs98` en Main `8da4bcf3` mediante el
[PR #94](https://github.com/avanza-digital/avancecorp-crm/pull/94), con controles
PASS y sin revisión aprobada registrada. Esa condición sigue pendiente de
resolución. El acceso a Hostinger ya está recuperado. No se publicó F5 ni
esta preparación F6. La semana estable continúa sin iniciar.

## Comportamiento preparado

Gestión Diaria incorpora «Resumen del día» y «Seguimiento completo» para
vendedor, supervisor y gerencia. La segunda sección reutiliza la cola y la
frontera SLA existentes: mismas consultas, conteos del servidor, señales,
filtros y páginas por cursor de 10, 25 y 50. El texto aclara que son pendientes
actuales, independientes de la fecha consultada en el resumen.

La ruta `#/gestion-diaria/cola` admite `/lead/<id>`. Abrir y cerrar la ficha
conserva filtros y página, incluso fuera del lote inicial. Atrás/adelante y los
enlaces directos mantienen la sección. Recargar o salir de ella reinicia sus
filtros y posición. Pulsar el módulo lateral activo conserva la sección;
«Resumen del día» vuelve explícitamente al resumen.

La pantalla y los enlaces `#/seguimiento[/lead/<id>]` permanecen operativos.
No se retiran entradas, datos, RPC, permisos ni confirmaciones de guardados
pendientes. No se cambia la política de vistas ni se concede acceso a directorio
o coordinación. El resumen no permanece montado consultando datos en segundo
plano mientras se usa la cola.

## Verificaciones

| Control | Resultado |
| --- | --- |
| Typecheck y lint iniciales | PASS |
| Unitarias focalizadas | PASS: 80 pruebas / 5 archivos |
| Gate integral `npm run check` | PASS: 4.393 pruebas / 297 archivos, build y controles incluidos |
| Docker cola, equipo y cortes tras corrección | PASS: 19/19, incluidos tres fallos iniciales |
| Docker Chromium focalizado final | PASS: 9 pruebas, 0 fallos, un worker, sin reintentos |
| Docker Chromium completo | PASS: 265 aprobadas / 0 fallos / 26 omisiones previstas; 19,8 min |
| Docker WebKit F5 y F6 | PASS: 14 aprobadas / 0 fallos; 1,8 min, un worker, sin reintentos |
| Revisión independiente | Dos PASS; hipótesis P2 descartada con CSS real y P3 evaluados |
| Publicación de esta preparación | NOT RUN |
| Siete días reales estables y retirada final | NOT RUN; T0 de F5 pendiente |

Los nueve recorridos nuevos cubren 105 oportunidades, llegada a la página que
contiene las oportunidades 101–105, lectura por id de una ficha fuera del lote,
filtros de supervisión, cursor vencido, revocación con ocultación de filas,
recuperación y vacío real, móvil/teclado, perfiles denegados, SLA apagado y demo.
Incluyen normalización de detalles gerenciales para otros roles y clic lateral
conservando página. El primer intento completo falló en tres controles por
68 px de desbordamiento; se corrigió alojando el acceso en la cabecera existente
del supervisor, sin rebajar tests. Se conservaron los fallos.
El backend está interceptado: es evidencia de la UI, no un ensayo nuevo de RLS.

Comandos desde `CRM-Avance-Corp/app`:

```sh
npm run check
CRM_E2E_VOLUME=gestion-diaria-f5-e2e-modules CRM_E2E_CONTAINER=gestion-diaria-f6-e2e CRM_E2E_TASK=gestion-diaria-f6 npm run test:e2e:docker -- e2e/gestion-diaria-cola.spec.ts --workers=1 --retries=0 --reporter=list
CRM_E2E_VOLUME=gestion-diaria-f5-e2e-modules CRM_E2E_CONTAINER=gestion-diaria-f6-e2e CRM_E2E_TASK=gestion-diaria-f6 npm run test:e2e:docker -- --workers=1 --retries=0 --reporter=list
CRM_E2E_VOLUME=gestion-diaria-f5-e2e-modules CRM_E2E_CONTAINER=gestion-diaria-f6-webkit CRM_E2E_TASK=gestion-diaria-f6 npm run test:e2e:docker -- --config=playwright.gestion-diaria.webkit.config.ts --workers=1 --retries=0 --reporter=list
```

Se usa un worker por la presión de memoria acreditada en los ensayos anteriores.
Los bancos ajenos no se detienen ni se modifican. La preparación partió de F5
`9bde971f` y, tras comprobar igualdad de árboles, actualizó su base a Main
`8da4bcf3` sin cambiar los archivos probados, en la rama separada `codex/gestion-diaria-f6-preparacion-20260924`
de la copia de trabajo ya autorizada.

## Condiciones pendientes

1. F5: resolver la condición de revisión GitHub, promover SQL autorizado por
   rama nativa y publicar mediante `$release-crm`. Hostinger ya está operativo.
2. Registrar T0 de publicación verificada y al menos siete días reales estables
   en el [registro](../OBSERVACION-F3-F5.md). No sustituirlos por pruebas.
3. Solo después, preparar y verificar los alias antiguos, retirar la entrada y
   pantalla duplicadas, publicar esa retirada y cerrar su evidencia.

La autorización de Miguel para SQL F5 y `$release-crm` está registrada y no se
solicita de nuevo. No equivale a aprobación del PR por GitHub ni adelanta la
retirada. Esta preparación se mantiene fuera del PR #94.

Referencias: [inventario F6](../PREPARACION-F6-2026-09-24.md),
[review](../REVISION-F6-PREPARACION-2026-09-24.md) y
[plan](../EJECUCION-F4-1-F6-2026-09-24.md).

Capturas inspeccionadas: [escritorio](f6-cola-105-escritorio.png) y
[móvil](f6-cola-analista-movil.png). [Evidencia estructurada](evidencia.json) y
[actualización del mismo Figma](figma-actualizacion.json); todos los pasos de
observación y retirada permanecen pendientes.

La ampliación de la configuración WebKit está versionada; después de ella
se repitieron lint y typecheck con PASS. No cambió el código de producto tras
el gate integral y la regresión Chromium. Las huellas de fuente coinciden.

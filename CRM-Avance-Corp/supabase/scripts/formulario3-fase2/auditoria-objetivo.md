# Auditoría del objetivo de la fase 2 · 2026-10-14

Resultado: los seis resultados del encargo están cubiertos para la entrega local.
Se contrastó el archivo del objetivo con el código y la evidencia ya conservada.
Las 31 huellas de fuentes coincidían antes de esta auditoría; el único cambio
posterior amplía la primera prueba E2E con la navegación al Pipeline. No cambia
el producto, la migración ni las reglas del importador.

| Resultado solicitado | Evidencia contrastada | Resultado |
| --- | --- | --- |
| Etiqueta en cartera, ficha y Pipeline; canal FORMULARIO conservado | `campania-chip.tsx`, `cartera.tsx`, `lead-drawer.tsx`, `pipeline.tsx`; primer E2E de campaña. La nueva aserción carga la segunda página del Pipeline, comprueba la etiqueta y abre la ficha con Enter. | PASS |
| Filtro Campaña combinado con origen, etapa, analista, fechas y procedencia | Argumentos de `cartera.tsx` y `crm-api.ts`; pruebas HTTP de cartera; matriz `cartera.sql` con funciones reales. | PASS |
| Toda la cartera autorizada, páginas y cifras coherentes; persistencia al volver o recargar | 43 comprobaciones SQL: páginas 50 + 20, total de 70 leads, capital PEN/USD y embudo. E2E: 55 leads de campaña situados fuera de la primera página inicial; ficha, recarga y limpiar filtros. `use-filtro-campania.test.ts` cubre separación por cuenta/modo y almacenamiento bloqueado. | PASS |
| Historial conservado y reingresos sin reclasificar el contacto original | E2E de cartera histórica: una nota que menciona Formulario 3 no crea la etiqueta. Contrato de fase 1: campaña del reingreso en actividad, origen previo conservado e idempotencia. Fuentes de fase 1 comprobadas sin cambios, salvo los tipos generados ampliados por fase 2. | PASS |
| Alcance por rol y campaña sin edición humana | Matriz SQL con RLS real: analista, supervisor, gerencia, Directorio, coordinación, inactivo y sesión vacía; campaña no editable, nota sí editable. E2E: ficha sin campo de edición de campaña. | PASS |
| Pruebas y revisión con Claude | Gate integral de 6.700 pruebas, 43 comprobaciones SQL, 9 E2E en Docker y revisión independiente anterior con mejoras justificadas aplicadas. Decisiones y límites en `revision-resolucion.md`. | PASS |

## Comprobación adicional

Comando ejecutado en `app/`:

```sh
npm run test:e2e:docker -- e2e/formulario3-campania.spec.ts e2e/cartera-keyset.spec.ts --workers=2
```

Resultado: **9 PASS, sin reintentos, 28,5 segundos**. Salida completa en
[e2e-auditoria-final.log](e2e-auditoria-final.log). La captura
[Pipeline](capturas/pipeline-formulario3.png) se inspeccionó visualmente:
«Formulario 3» es legible junto al canal «FORMULARIO» en la tarjeta 060,
cargada después de las primeras 50. El test también confirma que una tarjeta
histórica no recibe la etiqueta y que la ficha conserva ambos datos.
Oxlint del archivo ampliado: PASS.

El gate integral de aplicación y la matriz SQL no se repitieron: no cambió
ninguna fuente de producto ni SQL desde sus pasadas válidas. Se conserva la
revisión de Claude existente; esta ampliación de aserciones no introduce una
nueva decisión de arquitectura ni un cambio de producto que requiera otra.

## Estado observado y límites

La lectura de producción durante esta auditoría volvió a confirmar:
`campania_publicada=false` y huella de cartera
`23a63cc3965472b9db85aa81cadffbeb`. La lectura de n8n confirmó el flujo
`BjI5m1PKVWhO0NDb` inactivo, sin versión activa, con `Importar en CRM`
deshabilitado y `enviar_crm=false`.

Los E2E usan HTTP simulado; la matriz SQL comprueba RLS real por separado.
Auth/HTTP integrado y el ensayo remoto final siguen pendientes de fase 3.
El gate general de producción continúa NOT RUN por credenciales ausentes.
No se publicó, importó, activó n8n ni creó otra rama remota en esta auditoría.

El [plan en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34)
ya refleja este mismo alcance: fase 2 validada localmente y fase 3 pendiente.

# Correcciones del contrato v10 / anexo v2 — 10/10/2026

Preparación local. Ningún SQL ni despliegue de esta entrega se ha aplicado en
producción. La publicación requiere autorización de Miguel sobre el SQL exacto
mostrado y el proyecto de destino. Este documento conserva también los gates que
solo podrán ejecutarse con ese entorno autorizado.

## Resultado

- Contrato `contrato-aep-17-v10`: correo de 8.1 y 14.2 corregido a
  `atencionalcliente@groupmascapital.com` y firma transparente original del Word.
- Anexo `anexo-cronograma-v2`: fila «Número de cuenta destino», entre modalidad y
  analista, obtenida de `snapshot.cuentaPago.numeroCuenta` del contrato sellado.
  Se trata como texto; `0019100000000000` conserva ambos ceros iniciales.
- Firma: PNG original `word/media/image1.png`, 321×240, 42.323 bytes;
  SHA-256 `c3dcb1242301df96cb926930a82a019d4258d6a6e5d8ac3d01033b2e4cf90a6a`.
  El archivo incrustado coincide byte por byte, tiene 65.360 píxeles transparentes
  y cero blancos opacos. `fit: [93,65]` conserva toda la imagen y su proporción.
- Los archivos sellados v1–v9 se descargan desde Storage; no se regeneran ni se
  sobrescriben. El lector reconoce explícitamente las versiones históricas.
  El anexo se genera aparte, a demanda; su auditoría existente admite v2.
- No se cambian cronogramas, capital, tasas, fechas, cuentas vigentes, permisos,
  tablas públicas, reglas financieras ni la interfaz de producto del CRM.

Se conserva la lectura de v3/v4 como parte del requisito de compatibilidad con
versiones anteriores: ambas son versiones registradas por las migraciones y
admitidas por los CHECK del ledger. No se encontró una prohibición documental;
la lista del handler las omitía. Esta ampliación no altera la autorización,
la propiedad del contrato, la validación de ruta ni la comprobación SHA previa
a firmar la descarga. El catálogo antes de publicar permite contar cada versión.
Los nombres internos `anexo-v1.ts` y `renderizarAnexoPdfV1` identifican el módulo;
la versión efectiva de salida la fija `ANEXO_TEMPLATE_VERSION` (ahora v2).

## Archivos y muestras

SQL completo de ida:
[`20261010154908_crm_contrato_pdf_plantilla_v10_correcciones.sql`](../../migrations/20261010154908_crm_contrato_pdf_plantilla_v10_correcciones.sql).
SQL completo de reversa: [`reversa.sql`](reversa.sql).
Catálogo y huellas antes/después: [`verificar-catalogo.sql`](verificar-catalogo.sql).

Las 14 muestras están en `output/pdf/correcciones-20261010/` desde la raíz del CRM:
contrato y anexo para individual PEN, individual USD, mancomunado PEN (1 cotitular),
mancomunado USD (5 cotitulares), compuesto USD a 2 años, mensual PEN a 5 años
(60 cuotas), y trimestral PEN a 2 años. Son datos ficticios. Los siete snapshots
JSON y `manifest.json` permiten reproducir los archivos y comprobar sus SHA.
Se revisaron sus 75 páginas rasterizadas: márgenes, firma sin parche blanco,
cuenta completa, filas y cabeceras de tablas, numeración y bloques de cotitulares.

## Verificación local

| Comprobación | Resultado |
| --- | --- |
| Generador, handler y Storage en Docker Deno 2.9.4 | PASS: 94 pruebas |
| Generación real en Docker y comparación con las muestras locales | PASS: mismos bytes y SHA |
| Chromium en Docker: anexo v2, descarga v9/v10, error sin sellado | PASS: 4 pruebas |
| Pruebas de frontend relacionadas con PDF | PASS: 32 pruebas |
| PostgreSQL 17 aislado: migración, reversa, guardas y fallos atómicos | PASS: 39 comprobaciones |
| Banco SQL existente del núcleo PDF (incluye RLS/concurrencia/anexo) | PASS: `CONTRATO_PDF_V2_RUNNER_OK` y limpieza verificada |
| Reversa Edge: renderer antiguo y lectura v10 | PASS: 91 pruebas y typecheck, también en Docker |
| Texto completo antes/después, mismos snapshots | PASS: 14 comparaciones |
| Deno check con el `deno.json` propio de la función | PASS |
| Lint y typecheck del CRM | PASS; lint conserva avisos preexistentes ajenos al cambio |
| Preflights generales seed/RLS | NOT RUN: faltan variables del banco (`SUPABASE_URL`); no ejecutaron aserciones |
| Rama Supabase remota, advisors y smoke en producción | NOT RUN: pendientes del entorno y publicación autorizados |

Límites del banco: la suite v10 usa las formas versionadas de las tablas y dos
cuerpos privados suplentes. Verifica reemplazo del literal, atributos y reversa;
no sustituye un ensayo sobre el catálogo vigente del proyecto destino. El banco
SQL general verifica los cuerpos reales versionados en su etapa histórica.
Las pruebas de navegador usan autenticación/RPC/Storage simulados y PDF reales
producidos por la Edge; no son una prueba HTTP contra producción. No hay cambios
de esquema público ni firmas de RPC que requieran regenerar `database.types.ts`.

Revisión independiente con `scripts/claude-review`: CHANGES_REQUESTED inicial,
hallazgos resueltos y dictamen final **PASS**, confianza alta. Los dos dictámenes
y la evaluación del PRIMARY están en
`output/contrato-correcciones-20261010/evidencia/`. También se atendió el P3
opcional final: guarda explícita de la versión del anexo al preparar la reversa.

## Reproducir

Desde la raíz del CRM:

```bash
python3 supabase/scripts/banco-pdf-v10/generar-muestras.py
python3 supabase/scripts/banco-pdf-v10/banco-local.py
bash supabase/scripts/run-test-contrato-pdf-v2-local.sh --run
```

El primer comando crea las 14 muestras y compara su texto con el renderer v9
conservado en el commit `426499c338ad6359462fcd2c5b9d035ff04f147b`. Únicamente permite
las dos sustituciones de correo y la fila exacta de cuenta; conserva todos los
números y palabras del cuerpo. El banco v10 inicia su propio contenedor
PostgreSQL 17 sin red/puertos/volúmenes y lo retira por su ID al finalizar.

Desde `supabase/functions/crm-contrato-pdf-v2/`:

```bash
deno check --config deno.json index.ts handler.test.ts renderer.test.ts storage.test.ts
deno test --config deno.json --allow-read handler.test.ts renderer.test.ts storage.test.ts
```

Para generar los fixtures dentro de Docker (desde la raíz del CRM):

```bash
docker run --rm --network none \
  -v "$PWD":/workspace:ro \
  -v "$PWD/app/e2e/fixtures/contrato-correcciones":/workspace/app/e2e/fixtures/contrato-correcciones \
  -w /workspace denoland/deno:2.9.4 run --allow-read \
  --allow-write=/workspace/app/e2e/fixtures/contrato-correcciones \
  supabase/scripts/banco-pdf-v10/generar-fixtures.ts
```

Desde `app/`:

```bash
npm run test:e2e:docker -- e2e/contrato-anexo.spec.ts --workers=2 --reporter=list
npx vitest run src/lib/contrato-pdf-archivo.test.ts src/components/app/contrato-detalle-pdf.test.tsx
npm run lint
npm run typecheck
```

## Publicación — ejecutar solo tras autorización

1. Confirmar el proyecto, el SQL exacto y la ventana de cambio. Integrar únicamente
   los archivos de esta tarea, preservar cambios ajenos y los cambios remotos.
   Main local debe seguir `avancecorp/main`; ambos deben apuntar al mismo commit.
   El paquete local contiene huellas para revisión, **no sustituye** ese requisito:
   reconstruir/verificar el artefacto de publicación desde el commit acordado.
2. En la rama Supabase autorizada, contrastar catálogo actual, ejecutar la candidata,
   la reversa y la reaplicación, probar reserva/corrección/sellado/descarga/anexo,
   ejecutar la matriz RLS pertinente y advisors. Detenerse ante nuevas diferencias.
   Conservar OID/owner/ACL/search_path de las dos funciones privadas, cuerpos con
   solo el cambio de literal y todas las filas selladas sin cambios.
3. Preparar **antes del cambio** la Edge de reversa con `preparar-reversa.py` y sus
   pruebas. Confirmar que la base del renderer v9 coincide con la versión que se
   pretende recuperar; no usar sin verificar una copia antigua arbitraria.
4. Coordinar una pausa efectiva de altas/correcciones/emisiones y de workers que
   puedan reclamar trabajos. No basta con observar cero jobs un instante. No hay
   un interruptor nuevo de mantenimiento en este cambio. Con la Edge anterior,
   resolver los trabajos `procesando`, `subido_verificado` y reintentos con bytes,
   incluidos los leases vencidos. No borrar sus archivos ni forzar su versión.
5. Guardar la salida de `verificar-catalogo.sql`. Debe haber solo reservas v9
   vacías, jobs sellados o bloqueados para revisión. El preflight transaccional
   de la migración repite esta guarda tomando primero los candados de tablas.
6. Desplegar **solo** `crm-contrato-pdf-v2`, manteniendo `verify_jwt = true` y sus
   secretos actuales. No usar `--prune`, no desactivar JWT y no desplegar todas
   las funciones. Con `PROYECTO_AUTORIZADO` previamente definido, desde el checkout
   del commit verificado:

   ```bash
   supabase functions deploy crm-contrato-pdf-v2 --project-ref "$PROYECTO_AUTORIZADO"
   ```

7. Aplicar la candidata por el carril autorizado del proyecto y registrar su
   versión una sola vez. El archivo tiene `begin/commit`; cualquier error revierte
   defaults, CHECKs, funciones y trigger. No es idempotente. No ejecutar un push
   general de las migraciones pendientes de otras tareas. Si el SQL falla,
   mantener la pausa y desplegar la Edge de reversa; no dejar SQL v9/renderer v10.
8. Repetir `verificar-catalogo.sql`: default v10; ambas funciones estampan v10 y
   ninguna v9; atributos iguales; trigger `O`; CHECKs admiten v10 y las antiguas;
   huellas/cantidades de PDF anteriores exactamente iguales mientras la pausa
   sigue vigente. Descargar un PDF anterior y comparar SHA y bytes con su
   referencia previa. El frontend existente admite las nuevas versiones.
9. Con un caso de prueba expresamente autorizado en el destino, generar un
   contrato y anexo: versiones v10/v2, correos correctos, firma completa y cuenta
   del snapshot. Cambiar la cuenta vigente del caso de prueba y comprobar que el
   anexo conserva la cuenta sellada, sin modificar contratos reales. Comprobar
   acceso permitido y denegado según cartera y que emitir el anexo no crea una
   revisión del contrato. Conservar hashes/asiento de emisión y cerrar la prueba.
10. Reabrir las emisiones, observar errores y completar ledger/acta con commit,
    proyecto, artefacto, fecha, pruebas y huellas efectivamente publicadas.

## Reversión que conserva los documentos

La v9 antigua no reconoce v10. **No desplegar directamente el binario anterior.**
Preparar una carpeta nueva:

```bash
python3 supabase/scripts/banco-pdf-v10/preparar-reversa.py /private/tmp/edge-reversa-contrato-v10
```

La salida restaura renderer/template/imagen de v9 y anexo v1, conservando el
handler actual con lectura explícita v10. Sus pruebas incluyen esa descarga y
los golden originales v9/v1. Desde la carpeta generada:

```bash
deno check --config deno.json index.ts handler.test.ts renderer.test.ts storage.test.ts
deno test --config deno.json --allow-read handler.test.ts renderer.test.ts storage.test.ts
```

Para desplegarla, colocar esos archivos como
`supabase/functions/crm-contrato-pdf-v2/` en el artefacto de reversa verificado y
conservar la configuración `enabled=true`, `verify_jwt=true`, entrypoint
`./functions/crm-contrato-pdf-v2/index.ts`. El paquete incluye esa estructura.

Con autorización: pausar y resolver trabajos v10 en vuelo/con bytes **todavía
con la Edge v10**; capturar catálogo/huellas; desplegar la Edge compatible de
reversa; aplicar `reversa.sql`; comprobar default/funciones v9 y trigger activo,
CHECKs todavía compatibles con v10, hashes de todos los PDF anteriores intactos,
descarga de v9 y v10 y generación de v9/anexo v1. Reabrir solo después del PASS.
La reversa no borra migraciones ni documentos y no cambia los snapshots sellados.
Si falla, la transacción queda íntegra: mantener la pausa, volver a la Edge v10
si SQL sigue en v10 y diagnosticar la condición que impidió revertir.

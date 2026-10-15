# Formulario 3 · fase 2

Implementación preparada, sin publicar. El trabajo añade lectura y filtro de
`campania_origen`; el canal sigue siendo `formulario`. No modifica el importador,
los datos de contactos existentes, reparto, conversión ni n8n.

## Contrato

- Etiqueta informativa en cartera, ficha, vista previa y tarjetas del Pipeline.
  Los registros sin campaña conservan su presentación; no se infiere desde notas.
- Filtro «Campaña»: Todas / Formulario 3. Se combina con los demás filtros y
  recorta antes de paginar, contar, sumar capital y calcular el embudo.
- El servidor devuelve el eco de campaña y el cliente comprueba eco y filas.
  Si la ruta anterior recibe campaña, usa la consulta integrada, nunca la omite.
- Caché separada por campaña. Selección conservada en esta pestaña por cuenta
  y por modo real/demo; cambiar de cuenta no reutiliza la selección de otra.
- Sin edición humana de campaña. Las lecturas mantienen RLS y admisión vigentes.
- La migración requiere fase 1, comprueba las definiciones vivas por huella,
  reemplaza las firmas exactas sin CASCADE y restaura los mismos grants en la
  transacción. `resumen_cartera_fn` conserva su contrato y las cifras sin filtro.

## Ensayo local

Banco Docker `avancecorp-coordinacion-pg-actual`, base exclusiva
`formulario3_fase2_20261014_review`, clon nuevo de la fase 1 ya validada tras
incorporar la revisión. El primer ensayo quedó en `formulario3_fase2_20261014`.
La cartera viva de
producción y la base del clon tenían huella `23a63cc3965472b9db85aa81cadffbeb`.
Producción no tiene aún la columna de campaña; está cubierto el estado de
cartera histórica sin campañas y el filtro vacío.

```sh
npm run test:rls -- --formulario3-fase2
```

43 comprobaciones SQL con las funciones reales y `SET LOCAL ROLE authenticated`:
135 filas propias, 70 de campaña, 9 de otro equipo; páginas de 50 + 20, cursor
con empates, totales y capital PEN/USD, embudo, ficha, lector anterior, resumen
general, filtros combinados, campañas inválidas, escritura denegada, analista,
supervisor, gerencia, Directorio, coordinación, miembro inactivo y sesión vacía.
Cada ensayo revierte sus datos y configuraciones con ROLLBACK.
La comparación del envoltorio abarca su respuesta completa; también se comprueba
la edición permitida de un lead con campaña y la documentación conservada.

`cartera-anterior.sql` es la definición viva previa, ejecutada únicamente en
`pg_temp` para comparar todas las filas, su orden y el resumen sin filtro.
Los tipos de las dos funciones se generaron desde este banco con Supabase CLI
2.117.0; se integraron solo esos bloques, conservando los cambios de fase 1 y
los tipos ajenos presentes en el árbol.

Advisors ejecutados antes/después en los bancos locales: sin alertas nuevas de
seguridad, WARN o ERROR. Diferencias INFO de `unused_index` corresponden a
contadores de uso distintos entre clones; no se crearon ni eliminaron índices.
No se retiran índices de producción a partir de un banco vacío.

## Gates y límites

- PASS: `app/npm run check`, 420 archivos / 6.700 pruebas, tipos, lint, build,
  bundle y duplicación. Se conservan 11 warnings previos ajenos a esta fase.
- PASS: `npm run check:scripts` fuera del sandbox; su prueba HTTP local necesita
  abrir un puerto en 127.0.0.1. El primer intento fue bloqueado por EPERM.
- PASS: matriz SQL final de 43 comprobaciones y advisors locales del clon final.
- PASS: 9 E2E en Docker, sin reintentos en la pasada final ampliada con
  Pipeline, segunda página y ficha por teclado (28,5 s).
- PASS tras review: 262 pruebas enfocadas de cartera, alta, edición y documento,
  más typecheck y sintaxis del ejecutor SQL. No cambió el código de producto
  frontend después del gate integral; se ampliaron sus aserciones de prueba.
- Claude: una revisión válida, `CHANGES_REQUESTED` por huecos de evidencia y
  conservación de metadatos. Codex resolvió los puntos con lecturas, corrección
  y pruebas; no se volvió a consultar para obtener un PASS. Ver
  [decisiones de revisión](revision-resolucion.md).
- `npm run gate:realidad` general: NOT RUN (faltan variables de credencial del
  gate). Se comprobó por lectura SQL el estado pertinente en producción:
  columna ausente y función de cartera sin cambios; la UI histórica se prueba.
- Auth/HTTP integrado contra la base y ensayo remoto: pendientes de fase 3.
  Los E2E usan HTTP simulado; la matriz SQL usa RLS real. No se confunden esas
  dos evidencias con una prueba integrada de autenticación real.
- No se creó una rama remota nueva, no hay coste adicional de Supabase.

## Evidencia final

`verificacion.json` contiene estados y huellas. Logs: `check-app-final.log`,
`check-scripts-final.log`, `e2e-auditoria-final.log`, `cartera-final.log`,
`migracion-final.log` y `revision-pruebas-app.log`. La salida inicial de 40 SQL
se conserva en `cartera-local.log`. `contraste.json` acredita ratios 4,60–5,17.
Las capturas están en `capturas/` y el
[plan en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34)
indica fase 2 validada localmente y fase 3 pendiente.
La [auditoría del objetivo](auditoria-objetivo.md) relaciona los seis resultados
solicitados con sus pruebas, incluye la captura del Pipeline y precisa los
límites de la validación. `e2e-final.log` conserva la pasada anterior (23,5 s).

## Publicación posterior

Orden: fase 1 SQL → fase 2 SQL → verificar capacidad y tipos → Edge de fase 1
→ frontend de fase 2. El frontend nuevo requiere la columna al leer la ficha.
Una pestaña con el frontend anterior sigue funcionando con la base nueva:
los argumentos añadidos son opcionales y los validadores anteriores toleran
el dato adicional. Reversión operativa: frontend anterior, conservar esquema.
La publicación corresponde a fase 4, por el procedimiento humano de release.
n8n se mantiene apagado hasta las pruebas de carga autorizadas posteriores.

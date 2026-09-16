# Evaluación del PRIMARY de la revisión independiente

Codex es PRIMARY. Claude emitió `CHANGES_REQUESTED`, confianza media, sobre el
primer candidato: [revisión íntegra](revision-claude.md). No modificó archivos.

## Correcciones aceptadas y comprobadas

- **Ámbito Directorio**: ausencia de inversiones siempre dentro del ámbito
  autorizado. Consultar COOPAC ocultas para decidir esa ausencia filtraría su
  existencia. El núcleo devuelve `solo_avance`; etiquetas, contador, ayuda y
  selector indican Avance. La prueba SQL usa una persona sintética con perfil
  autorizado y una COOPAC, sin Avance: Directorio ve «sin inversiones Avance»;
  Gerencia ve su COOPAC. Nunca se amplían permisos.
- **DTO explícito**: `personas` proyecta únicamente las doce columnas públicas;
  v1 selecciona sus seis claves superiores explícitamente. Prueba de claves
  exactas y unicidad para Gerencia, Supervisor, Analista y Directorio.
- **Accesibilidad**: `aria-describedby` de cada fila aporta documento, capital,
  fecha, responsable y «No contactar», manteniendo el nombre «Abrir ficha…».
  La ayuda de filtros incompatibles se muestra también en móvil.
- **Por vencer**: al desactivar restaura mes/estado anteriores si no cambiaron
  durante esa consulta. Seleccionar otro estado desactiva el filtro de
  vencimiento; evita pedir inversiones vencidas y vigentes simultáneamente.
- **Revocación persistente**: la invalidación de una lista rechazada se procesa
  una vez por selección hasta una lectura correcta; evita un bucle de lecturas.
  Prueba comprueba máximo dos intentos automáticos, retirada de datos y
  recuperación manual. La cancelación de solicitudes y borrado de ficha siguen.
- **Restablecer**: el botón se llama «Ver toda la cartera», pues limpia el mes
  intencionalmente. Al entrar se mantiene el mes actual. Cabecera «todas sus
  empresas» distingue esos distintivos del capital recortado por filtros.
- **Reversa real**: `preparar.mjs` compara siete respuestas completas después
  de instalar, revertir y reinstalar; comprueba owner y ACL en los tres pasos y
  ausencia de las funciones nuevas tras revertir. El ensayo detectó y corrigió
  un punto y coma ausente en el artefacto de reversión generado.
- **Sin fecha**: prueba el vacío y excluye a clientes sin inversiones. En el
  esquema vigente Avance tiene fecha comercial NOT NULL y COOPAC usa el fallback
  canónico a `creado_en` NOT NULL. No se perforan esas restricciones para crear
  una fuente nula imposible actualmente. El filtro se conserva defensivamente.

## Hipótesis contrastadas con evidencia

Inventario **solo lectura de producción** (2026-09-15, noche de Lima):

```json
{"schema":"crm","proname":"cartera_inversionistas_fn",
 "argumentos":"p_pagina integer, p_tamano integer, p_texto text, p_empresa text, p_responsable uuid, p_sin_responsable boolean",
 "propietario":"postgres","prosecdef":true,
 "acl":"{postgres=X/postgres,authenticated=X/postgres}"}
```

No existen `private.cartera_f5_listar` ni la nueva RPC en producción. Por tanto:

- El owner de v1 **ya es postgres**, y `service_role` **no tiene EXECUTE**.
  Los `ALTER OWNER` y grants no elevan ni reducen privilegios existentes.
  El fallo previo local era del helper recién creado por `supabase_admin`,
  inaccesible desde la RPC v1 propiedad de postgres; no demuestra otro owner v1.
- No existe una sobrecarga antigua del helper nuevo. No se borran funciones por
  una hipótesis. La reversa elimina solo las dos firmas creadas en este cambio.
- `private.cartera_f5_personas_visibles(uuid)` selecciona una identidad canónica
  por PK; agregaciones por identidad y laterales `LIMIT 1` impiden multiplicarla.
  La prueba real de cuatro roles lo confirma; no se usa DISTINCT para tapar un
  error de integridad. Responsable procede de un único perfil por PK.
- `private.cartera_f5_fuentes_reales()` excluye `es_demo is true` desde la
  migración `20260914025926`. Se conserva la semántica previa de valores NULL
  en sumas; no se cambia el contrato financiero por una hipótesis del review.
- `private.cartera_f5_registrar` deduplica por actor/persona/tipo durante 60 s
  (`20260908230249`, función `cartera_f5_registrar`). Polling de 15 s no equivale
  a cuatro escrituras de auditoría por minuto. El polling ya existía y se
  conserva para revalidar acceso. Rendimiento remoto de esta versión: NOT RUN.
- `fmtFecha` usa `fechaLocalValida`/`parseDateLocal` para fechas civiles;
  `etiquetaDeMes` usa substrings y nombres de meses. No hay conversión UTC de
  fecha civil. Ambos helpers y sus tests existentes se conservan.
- Un DTO inválido produce `RESPUESTA_INCOMPLETA`, no total cero. Las pruebas de
  la API cubren versión antigua, metadatos faltantes y respuesta parcial.

## Gate y límites

Gate integral frontend ejecutado por sus pasos, cobertura con cuatro workers;
la primera corrida sin límite tuvo timeouts ajenos y contaminación posterior.
La repetición acotada pasó sin cambiar esos tests. No se declara PASS para
aquella primera corrida. SQL y HTTP se prueban contra Postgres/PostgREST reales
locales; E2E usa respuestas de API simuladas. No equivalen a un login real ni a
una publicación. El orden obligatorio sigue siendo SQL probado y aprobado,
después frontend del commit verificado. Evidencia: `verificacion.json`,
`compatibilidad.json`, `http.json`, `pruebas-sql.txt` y capturas.

Dictamen del PRIMARY: hallazgos accionables corregidos; las hipótesis de
permisos/owner/sobrecargas se rechazan con el inventario observado. Producción
permanece sin esta migración. No se alteró ningún registro financiero real.

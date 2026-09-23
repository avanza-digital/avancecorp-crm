# Gestión Diaria — compatibilidad con el detalle opcional generado

Incidencia reportada por Miguel después del release F4: otra sesión regenera
`database.types.ts` completo y encuentra `string | null` en el llamador de
`registrar_actividad_v2`, incompatible con el argumento generado `p_detalle?: string`.
Miguel confirmó que esa otra sesión conserva la regeneración completa. Este
commit modifica únicamente el llamador, compatibilidad de recibos y sus pruebas.
**Es una corrección preparada después del release; no está publicada en Hostinger.**

## Contrato comprobado

Una consulta productiva de solo lectura a `pg_proc`, `pg_namespace`,
`pg_get_function_arguments` y `pg_get_functiondef`, filtrando por el nombre,
devuelve una sola función, en `crm`:

```sql
registrar_actividad_v2(
  p_operacion_id uuid, p_lead_id uuid, p_tipo text,
  p_detalle text DEFAULT NULL::text,
  p_siguiente jsonb DEFAULT NULL::jsonb
)
```

Su cuerpo construye el detalle como `nullif(btrim(p_detalle),'')` antes de
llamar al núcleo SLA. La base no pasó a exigir texto no nulo: la incompatibilidad
es con los tipos generados. Omitir el argumento conserva el NULL predeterminado
y la semántica del servidor. No hace falta SQL nuevo.

## Corrección y recibos existentes

El store omite realmente `p_detalle` cuando no hay contenido; no lo incluye
como `undefined`, porque `exactOptionalPropertyTypes` también lo rechaza.
El detalle con texto sigue enviándose sin cambiarlo.

Solo para `registrar_actividad_v2`, el cálculo de la firma interna normaliza la
ausencia de detalle a NULL. Así coincide con los recibos guardados por la versión
anterior, cuyo único llamador enviaba siempre texto o NULL. El historial de esa
línea conserva su incorporación desde `839aa7c8`. Al recuperar una intención
anterior se reenvían su mismo UUID y argumentos exactos; no se fabrican recibos
nuevos ni se elimina información pendiente.

## Verificación

- PASS: `npm run check`, **4.174 tests / 279 archivos**, lint, typecheck,
  cobertura, configuración, build, bundle y duplicación.
- PASS: typecheck adicional sustituyendo temporalmente solo esa firma por
  `p_detalle?: string`. Se restauró el archivo original; `database.types.ts`
  no forma parte del diff. La comprobación inicial con `undefined` explícito
  falló y motivó la omisión real de la propiedad.
- PASS: **32 E2E Docker** de acciones reales, SLA y resultado de llamada.
  Contenedor `gestion-diaria-f4-tipos-e2e`, volumen propio. El primer intento
  restringido no accedía a Docker; la ejecución autorizada terminó sin fallos.
- Revisión acotada de esta nueva incidencia: Claude **PASS**, recuperado por
  `scripts/claude-review`; el primer intento sin dictamen no cuenta. Los P3
  reforzaron la prueba de omisión estricta, recuperación de un recibo nuevo sin
  detalle y rechazo de cambiar el texto mientras queda otro guardado pendiente.
  La consulta de catálogo ya mostraba una única firma, sin sobrecargas.
- Después de esos refuerzos solo en tests, se repiten las dos suites afectadas
  y los checks estáticos del commit. Las pruebas de la publicación anterior
  conservan sus resultados y su commit de origen; no se les atribuye este parche.

Evidencia local: `/private/tmp/gd-f4-tipos-check-20260923.log`,
`gd-f4-tipos-e2e-20260923.log` y `gd-f4-tipos-review.out` en la misma carpeta.
La cantidad de líneas del archivo regenerado y su integración completa quedan
a cargo de la otra sesión; no se declara resuelta esa tarea por este parche.

Para integrar: incorporar el commit de esta corrección junto a los tipos
regenerados y ejecutar el typecheck/gate sobre esa combinación. No editar los
tipos generados para volver a añadir NULL ni modificar producción para satisfacer
el compilador. [Estado de F4 y primera jornada](GESTION-DIARIA.md).

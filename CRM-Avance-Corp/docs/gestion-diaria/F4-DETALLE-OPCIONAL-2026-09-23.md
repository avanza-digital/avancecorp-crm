# Gestión Diaria — compatibilidad con el detalle opcional generado

Incidencia reportada por Miguel después del release F4: otra sesión regenera
`database.types.ts` completo y encuentra `string | null` en el llamador de
`registrar_actividad_v2`, incompatible con el argumento generado `p_detalle?: string`.
Miguel confirmó que esa otra sesión conserva la regeneración completa. Este
commit modifica únicamente el llamador, compatibilidad de recibos y sus pruebas.
**PUBLICADO Y VERIFICADO el 23/09, 12:40 Lima.** PR #77 fusionado en
`8e6f4357`; artefacto construido desde ese Main limpio e igual al remoto.
La regeneración completa de tipos aún no estaba en Main al publicar y sigue
a cargo de la otra sesión; esta corrección es compatible con la firma generada.

## Publicación efectiva

- URL: **https://crm.miavance.com**.
- Fuente: `8e6f4357feb18e2c9caed9e8ed135c3bad2931f0`.
- Build: `build-20260923T173450335Z`; JS principal `assets/index-Ux3DSPAy.js`.
- ZIP: `releases/crm-20260923T173451Z-8e6f4357feb1.zip`, 2.258.913 bytes.
- SHA-256: `a27c055d974064f9a14042c3b4a184a72c55cb3d5b4dd9b7065cafd8f2ccafc0`.
- `release:crm`, `release:crm:verify`, preflight y publicación por MCP Hostinger
  PASS. Main/remoto reconfirmados antes de subir; `app/` idéntico a `4e51e5fb`,
  que pasó todos los controles de GitHub. Los E2E focalizados corresponden al
  mismo código de producto; después solo se reforzaron pruebas y actas.
- **113 archivos PASS:** 112 por HTTPS, con bytes/SHA y versión estable,
  más `.htaccess` completo por MCP, 2.977 bytes. Manifiesto y evidencias
  `.https-verificado.json`, `.htaccess-verificado.json` y
  `.publicacion-verificada.json` junto al ZIP, con el mismo basename.
- Smoke real Chrome/gerencia PASS: configuración de Gestión Diaria y registro
  operativo. V1 OFF hoy, una v2 programada para el 24/09 y tasa baja OFF hasta
  F5. No se creó actividad ficticia para probar el guardado productivo.
- Recuperación: ZIP publicado anterior
  `crm-20260923T163254Z-6bf0e84a6ea1.zip`, SHA-256
  `0800772132124f9451c3ca1b9452a979e15957695f60b020014ee6a815d37945`,
  conservado con su manifiesto y cotejo de 113 archivos. No se modificaron SQL
  ni la programación de cortes en esta entrega.

La primera jornada real del 24/09 sigue NOT RUN. Las actas posteriores no cambian
el commit de este despliegue ni requieren volver a publicar el mismo código.

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
- Después de esos refuerzos solo en tests: **107 pruebas focalizadas PASS**,
  lint/typecheck del commit PASS y suite completa del pre-push **4.175/279 PASS**.
  Los cuatro controles de GitHub terminaron SUCCESS antes de fusionar PR #77.
  Las pruebas de la publicación anterior
  conservan sus resultados y su commit de origen; no se les atribuye este parche.

Evidencia local: `/private/tmp/gd-f4-tipos-check-20260923.log`,
`gd-f4-tipos-e2e-20260923.log` y `gd-f4-tipos-review.out` en la misma carpeta.
La cantidad de líneas del archivo regenerado y su integración completa quedan
a cargo de la otra sesión; no se declara resuelta esa tarea por este parche.

Para la otra sesión: el commit `4e51e5fb` ya está integrado en Main mediante
PR #77 y publicado. Regenerar tipos sobre ese Main y ejecutar el typecheck/gate
sobre la combinación, sin volver a aplicar el parche. No editar los
tipos generados para volver a añadir NULL ni modificar producción para satisfacer
el compilador. [Estado de F4 y primera jornada](GESTION-DIARIA.md).

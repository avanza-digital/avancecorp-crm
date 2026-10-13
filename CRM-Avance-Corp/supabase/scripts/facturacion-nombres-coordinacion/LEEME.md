# Nombres en el reporte de Facturación de Coordinación

Miguel autorizó el 13/10/2026 mostrar nombres para los reportes de Rosa, manteniendo
solo lectura. Se aplica al rol Coordinación activo en CRM y Portal. No habilita
fichas, identificadores de clientes/contratos/leads/cierres, números de contrato,
documentos, contactos ni escrituras. Ranking y Repartir conservan sus permisos.

## Contrato y compatibilidad

La RPC nueva `crm.listar_operaciones_facturacion_v2_fn` devuelve `version:2`.
Coordinación recibe `visible:false`, `nombre_visible:true` y `cliente_nombre`.
El panel distingue permiso de nombre y permiso de ficha; un nombre nulo se muestra
como «Cliente sin nombre». El parser rechaza campos extra y el consumidor exige v2.

La RPC v1 y su helper quedan intactos: las pestañas del frontend anterior continúan
funcionando con su máscara. Otros roles delegan exactamente en v1, sin cambiar
visibilidad, filtros o cifras. El nuevo helper INVOKER pertenece a postgres y no
tiene EXECUTE para authenticated, anon o service_role. Solo el wrapper DEFINER,
STABLE con search_path vacío, tiene EXECUTE authenticated.

**Mantenimiento obligatorio:** Coordinación usa una copia acotada del cuerpo v1
porque su salida enmascarada no contiene una identidad con la que unir nombres.
Toda modificación futura de `private.facturacion_lista` debe revisar esta copia
y ejecutar la matriz de paridad de este kit y el bloque v2 de `test-rls.mjs`.
La huella protege la instalación; no sincroniza cambios futuros automáticamente.

## Evidencia y límites

- `vivo/catalogo.json`: dos definiciones capturadas por lectura del proyecto destino
  `dctqcbznekcyxhjujuci`, sin datos de clientes. Guarda de definiciones antes/después.
- `generar.py`: genera dos funciones nuevas, permisos sellados y `reversa.sql`.
- `ensayar.py` / `prueba.sql`: siembra sintética, matriz real y rollback. Exigen la
  base local exclusiva y vacía `coordinacion_nombres_20261013`, con comentario de
  identificación, postgres y triggers encendidos. No apuntan a producción.
- Matriz SQL y reversa/reaplicación: PASS. 15 comparaciones exactas de otros roles,
  tres meses, 220 filas (214 contratos, seis cooperativas), tres páginas por mes,
  nombres iguales a Gerencia, cifras y v1 intactas, sin IDs privados/contactos,
  RLS de fichas conservada, metas denegadas y Repartir permitido.
- Bajas CRM y Portal con el mismo JWT: PASS. Se fabrican flags de fixture
  suspendiendo BEFORE guards solo durante la siembra; se restauran antes de leer.
  Esto mide el estado revocado, no el comando de offboarding.
- Frontend integrado con la versión viva: `npm run check` PASS, 416 archivos /
  6.671 tests. E2E local Docker: 54 PASS, cero fallos (Facturación, realidad,
  Coordinación, Repartir, llamadas y Conversión). El frontend probado en
  `97c2d2e0` es idéntico al publicado en `4e31dbbf`; después solo cambiaron pruebas.
- Revisión independiente `scripts/claude-review`, auditor RLS: PASS. El primer
  intento fue rechazado por formato; la repetición entregó dictamen válido.
  Recomendaciones aceptadas: contrato v2 exigido, nombres nulos y regresión HTTP
  de paridad con v1. Aviso de mantenimiento documentado aquí sin modificar v1.
- `gate:realidad`: NOT RUN en producción por falta de credenciales configuradas;
  no equivale a las pruebas sintéticas. La identidad de Rosa se verificó por lectura.
- Auth remoto real: matriz general 3.932/3.932 PASS sobre el baseline previo;
  bloque Facturación 392/392 PASS tras reflejar las 470 migraciones del padre
  vigente. Incluye nombres exactos, claves mínimas, nueve roles, anonimato y los
  12 oráculos de atribución. El oráculo exige supervisores de ramas independientes
  y ambos GUC de identidad. El alcance reducido crea y retira sus dos ventas
  sintéticas del mes actual; no depende de fixtures de otros recorridos.
- Advisors finales en producción: seguridad 5→5 y rendimiento 6→6; cero avisos
  nuevos. Catálogo de las cuatro funciones idéntico al banco validado.
- **PUBLICADO Y VERIFICADO el 13/10/2026:** build `build-20261013T182849030Z`,
  fuente limpia `4e31dbbf13efc8b462c7ceb217d18eb408c58203`. Portada, versión y
  JS/CSS: 123 archivos HTTP 200 con bytes/huellas iguales al manifiesto.
  Lectura de producción con identidad Rosa: 71 filas con nombres, estructura y
  totales intactos, sin campos privados. Rama temporal y credenciales retiradas.
  Detalles y límites: [`publicacion.json`](publicacion.json).

Desde la raíz CRM, con la candidata instalada en el banco local:

```sh
python3 supabase/scripts/facturacion-nombres-coordinacion/ensayar.py
```

En rama/staging con las variables y la semilla de `LEEME-seed.md`:

```sh
node supabase/scripts/test-rls.mjs --facturacion-nombres
```

Este alcance no sustituye la matriz general. La corrida general conserva una
advertencia de banco sin meses sellados para el check de metas históricas; la
denegación de escrituras de Coordinación se comprueba en el ensayo SQL específico.

## Instalación y reversa

Backend primero: rama Supabase autorizada → candidata → matriz RLS/Auth real
(`test-rls.mjs`, incluye v2 con nombres exactos y claves mínimas) → advisors → merge.
La rama sin datos requiere reconstruir el esquema publicado porque el replay
histórico se detiene en `20260811210049`; esa preparación no es otra migración de
producto. Se preservan las migraciones y restricciones del historial del padre.
El primer `apply_migration` falló al registrar el historial por ausencia del índice
único de idempotencia en esa réplica. Se comprobó el estado, se revirtió la candidata,
se repuso exclusivamente esa restricción del padre y se reaplicó: PASS.

Una publicación paralela añadió el límite de referidos. El rebase volvió a
fallar por el replay histórico. Solo en nuestra rama vacía se reflejaron el
schema, los cuerpos actuales y la configuración técnica del padre, sin datos
personales. Reaplicar la migración antigua después de «Realización» rechazó su
guarda y revirtió la transacción; la réplica se hizo con los cuerpos vigentes,
respetando la combinación ya publicada. Historial final: padre 470, rama 471,
único extra `20261013171002 crm_facturacion_nombres_coordinacion`. La matriz
focalizada y los advisors pasaron antes del merge; no se ejecutó DDL directo en
producción para esta corrección.

Confirmar que PostgREST ve v2 y permite una lectura autenticada de Gerencia antes
de publicar frontend. Construir y publicar desde Main limpio y verificado conforme
al flujo de release del proyecto. Para revertir: frontend compatible primero;
después `reversa.sql`, que exige cuerpos y v1 intactos y elimina solo las dos
funciones nuevas, sin CASCADE ni cambios de datos.

El preflight de Main `f81d726e` rechazó la falta del commit vivo `33a701156385`.
Se creó el rescate en una copia aparte desde ese commit. Durante la verificación
se publicó `767e04447c94`, que se integró y volvió a probar: conserva Realización,
referidos y las pantallas F4-e publicadas. El preflight de `4e31dbbf13ef` pasó
contra `767e04447c94` antes del despliegue. El rescate vuelve a Main mediante
el PR #267 con merge que preserva su historia, tras la fusión previa del PR #264;
el acta no cambia la fuente del ZIP.

# Coordinación: consulta y corrección de categoría

Estado: **backend aplicado y verificado en producción; frontend pendiente de publicar por `$release-crm`**.
Validación remota y promoción: [VERIFICACION-CLOUD.md](VERIFICACION-CLOUD.md).
Pedido de Miguel del 15/10/2026: Coordinadora ve Leads y la cartera completa de clientes;
Admin/Superadmin, Gerencia y Coordinadora corrigen Nuevo / Renovación / Upgrade porque
el analista pudo registrarlo mal. Confirmación explícita: también corrige conversión y ranking.

La clasificación pertenece a cada contrato Avance. No crea una operación financiera ni
cambia capital, tasa, fechas, cuenta, documentos u operador original. La corrección requiere
motivo y deja historial inmutable. Los meses sellados siguen protegidos. La categoría explícita
corregida prevalece sobre la derivación de Renovación con adicional como Upgrade en conversión;
los contratos sin corrección conservan la regla vigente de octubre.

## Cambios

- `20261015211217`: helper y policies SELECT de Coordinación activa; cartera completa,
  equipo para filtros, búsqueda, ficha del lead, actividades, tareas, potencial y estados.
  No amplía `es_lector_global` ni `vendedor_ids_visibles`. Cartera F5 ofrece consulta sin
  gestión, banca, archivos ni postventa. Repartir conserva sus permisos específicos.
- `20261015212939`: reutiliza la puerta `crm.corregir_categoria_contrato_fn` con la firma
  vigente. Autoriza con perfil/membresía actuales bloqueados; deniega Directorio, vendedor,
  supervisor e inactivos. Núcleo sin EXECUTE para roles API. El permiso de excepción del
  trigger exige auditoría del mismo contrato, actor, transacción y categorías anterior/nueva.
- `20261015224848`: consolida las policies SELECT con su OR exacto, conserva los filtros
  restrictivos y elimina los tres avisos nuevos por policies permisivas duplicadas.
- Proyección comercial interna para contar cada fuente una vez; conserva el registro financiero.
  Nuevo corregido a cartera deja de ser captación nueva. La inversa respeta los relojes,
  plazos e identidad única de acreditación. Los snapshots de producto y las restricciones
  económicas permanecen; el producto archivado admite corregir su clasificación comercial.
- Modal accesible en Cartera → ficha → inversión → Corregir categoría; guardado por RPC,
  recarga de cartera, conversión y ranking; error conserva el motivo escrito.

## Verificación local

Banco PostgreSQL 17 Docker `avancecorp-coordinacion-pg-actual`, base
`permisos_coordinacion_20261015`, copia de esquema sin datos de `origen_f3_final_20261015`.
El esquema contiene la variante Formulario 3; no se afirma equivalencia completa con producción.

- PASS: `prueba.sql`, 93 comprobaciones, fixtures sintéticos y ROLLBACK. Roles permitidos y
  denegados, seis direcciones, RLS de consulta, baja sin renovar JWT, dinero y relojes intactos,
  ranking, conteo sin duplicados, categoría histórica NULL, plazos vencidos, primer mes Upgrade,
  producto archivado y prohibición de alterar tasa, idempotencia, auditoría y mes sellado.
- PASS: `replay.sql`, reversa + reaplicación, todas las definiciones idénticas, 93 checks después en la variante F3; 87 en la variante anterior.
- PASS: `concurrencia.py`, dos sesiones: revocación CRM y sello concurrentes. La corrección
  espera el candado, rechaza y no escribe categoría ni auditoría parcial. Usa otro clon vacío
  `permisos_coordinacion_variante_20261015`; conserva únicamente datos sintéticos.
- PASS: tipos generados desde el banco. Solo se incorpora la tabla nueva al archivo versionado
  para no arrastrar diferencias ajenas del esquema local.
- PASS: comparación de las 29 funciones vivas, solo lectura: todas sus huellas están admitidas
  por los preflights de estas migraciones, incluida la variante Formulario 3 publicada en paralelo.
- PASS frontend: 6.928 tests y build; E2E Docker: 422 aprobados, 26 omitidos, cero fallos.
  Gate completo y límites: [VERIFICACION.md](VERIFICACION.md). Revisión: [REVISION.md](REVISION.md).

Para repetir en un banco propio con las migraciones aplicadas:

```sh
psql "$PERMISOS_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/scripts/permisos-coordinacion/prueba.sql
psql "$PERMISOS_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/scripts/permisos-coordinacion/replay.sql
python3 supabase/scripts/permisos-coordinacion/concurrencia.py <contenedor> <permisos_coordinacion_clon_vacio>
```

`prueba.sql` exige nombre de banco de pruebas y cero contratos/equipo. Nunca usar estas
semillas en producción. La matriz HTTP/Auth general `test-rls.mjs` requiere una instancia
Supabase de ensayo con Auth y PostgREST; este banco SQL no los tiene.

- PASS: `sello.py`, cierre mensual real después de seis transiciones, sin pérdida de eventos comerciales.
- PASS: `rendimiento.sql`, 3.000 operaciones adicionales: ranking 110,425 ms y conversión 7,265 ms.
- PASS: advisors locales antes/después, 7 avisos preexistentes y ninguno nuevo tras consolidar policies.

## Aplicación y reversa

Aplicar en orden consulta → categoría → consolidación de policies (`20261015224848`), mediante el ciclo de rama/instancia autorizada,
matriz RLS y advisors del repositorio. Las tres migraciones son transaccionales, con candado
común, límite de espera y huellas que rechazan divergencias. No cambian firmas ni payloads
públicos existentes. Revisar otra vez las huellas si producción cambia.

Reversa, solo antes de la primera corrección: `reversa-politicas.sql` → `reversa-categoria.sql` →
`reversa-consulta.sql`. Si ya hay auditoría, la reversa se niega: preparar una migración
compensatoria y conservar el historial. No borrar la tabla ni reconstruir hechos financieros.

La publicación del frontend requiere invocación humana de `$release-crm` o `/release-crm`
según `CRM-Avance-Corp/CLAUDE.md`; Miguel ya invocó la habilidad para esta publicación.

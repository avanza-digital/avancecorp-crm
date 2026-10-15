# Coordinación: consulta y corrección de categoría

Estado: **implementado en copia aislada, validación final en curso; NO publicado ni aplicado a producción**.
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

- PASS: `prueba.sql`, 74 comprobaciones, fixtures sintéticos y ROLLBACK. Roles permitidos y
  denegados, seis direcciones, RLS de consulta, baja sin renovar JWT, dinero y relojes intactos,
  ranking, conteo sin duplicados, categoría histórica NULL, plazos vencidos, primer mes Upgrade,
  producto archivado y prohibición de alterar tasa, idempotencia, auditoría y mes sellado.
- PASS: `replay.sql`, reversa + reaplicación, todas las definiciones idénticas, 74 checks después.
- PASS: `concurrencia.py`, dos sesiones: revocación CRM y sello concurrentes. La corrección
  espera el candado, rechaza y no escribe categoría ni auditoría parcial. Usa otro clon vacío
  `permisos_coordinacion_carreras_20261015`; conserva únicamente datos sintéticos.
- PASS: tipos generados desde el banco. Solo se incorpora la tabla nueva al archivo versionado
  para no arrastrar diferencias ajenas del esquema local.
- PASS: comparación de las 29 funciones vivas, solo lectura: todas sus huellas están admitidas
  por los preflights de estas migraciones, incluida la variante Formulario 3 publicada en paralelo.
- Frontend, revisión independiente y advisors: ver `VERIFICACION.md` al cerrar el gate.

Para repetir en un banco propio con las migraciones aplicadas:

```sh
psql "$PERMISOS_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/scripts/permisos-coordinacion/prueba.sql
psql "$PERMISOS_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/scripts/permisos-coordinacion/replay.sql
python3 supabase/scripts/permisos-coordinacion/concurrencia.py <contenedor> <permisos_coordinacion_clon_vacio>
```

`prueba.sql` exige nombre de banco de pruebas y cero contratos/equipo. Nunca usar estas
semillas en producción. La matriz HTTP/Auth general `test-rls.mjs` requiere una instancia
Supabase de ensayo con Auth y PostgREST; este banco SQL no los tiene.

## Aplicación y reversa

Aplicar en orden consulta → categoría, mediante el ciclo de rama/instancia autorizada,
matriz RLS y advisors del repositorio. Ambas migraciones son transaccionales, con candado
común, límite de espera y huellas que rechazan divergencias. No cambian firmas ni payloads
públicos existentes. Revisar otra vez las huellas si producción cambia.

Reversa, solo antes de la primera corrección: `reversa-categoria.sql` →
`reversa-consulta.sql`. Si ya hay auditoría, la reversa se niega: preparar una migración
compensatoria y conservar el historial. No borrar la tabla ni reconstruir hechos financieros.

La publicación del frontend requiere invocación humana de `$release-crm` o `/release-crm`
según `CRM-Avance-Corp/CLAUDE.md`; este trabajo no ejecuta esa publicación.

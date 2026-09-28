# Ensayo de Ranking por origen

## Origen acreditado — preparación del 28/09/2026

`20260928163532_crm_ranking_origen_acreditado.sql` recupera el canal confirmado
cuando el lead llegó por una carga posterior al cierre. Conserva la precedencia
de vínculos directos, clientes anteriores (incluida ambigüedad) y cartera legada.
No modifica el contrato JSON público ni funciones monetarias/conversión.

Banco local de componentes, sobre una **base vacía dedicada** en el contenedor
de PostgreSQL ya disponible (no sirve para una base con datos):

```bash
node supabase/scripts/ranking-origen/probar-acreditaciones.mjs > /tmp/ranking-acreditaciones.sql
docker exec -i supabase_db_crm-avance-corp-local psql -U postgres -d ranking_origen_acreditado_20260928 -v ON_ERROR_STOP=1 < /tmp/ranking-acreditaciones.sql
```

La prueba compila el lector anterior real y el bloque exacto que lo transforma,
con dependencias sintéticas. Verifica 13 casos, importes/atribución/multiplicidad,
ACL del helper y política inactiva; termina con ROLLBACK. **No** ejecuta el
preflight/postflight del inventario analítico ni sustituye el ensayo completo
en una rama Supabase autorizada, matriz RLS, advisors o publicación.

La pantalla obtiene Renovación/Upgrade del cumplimiento canónico existente y
solo muestra ese reparto si concilia exactamente en céntimos con Cartera, por
moneda. La cartera legada que conserva categoría financiera `nuevo` no se
reclasifica de oficio: mantiene el total y declara el desglose no disponible.

## Ensayo de la entrega original

Solo sobre una **rama vacía y autorizada**, nunca en producción.

1. Comprobar paridad estructural y del historial con producción.
2. Aplicar el SQL aprobado `20260925190000_crm_ranking_origen_vendedor.sql`.
3. Ejecutar `semilla-rama.sql` mediante psql con `ON_ERROR_STOP=1`. Crea
   únicamente actores y operaciones ficticios; rechaza un banco con perfiles.
   La carga histórica usa `session_replication_role=replica` y después valida
   todas las FKs de crm/public antes de confirmar. No prueba las puertas de alta.
4. Exportar las credenciales **de esa rama**, sin imprimirlas: `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `POSTGRES_URL` (pooler),
   `CRM_RANKING_TEST_REF` (confirmación explícita del ref). `PSQL_BIN` es opcional.
5. Desde `CRM-Avance-Corp`: `node supabase/scripts/test-rls.mjs --ranking-origen`.

La matriz focalizada inicia sesiones Auth reales con contraseñas temporales de
los actores sintéticos. Prueba PostgREST positivo/negativo y ejecuta
`prueba-rama.sql` con los permisos `authenticated`, triggers activos y ROLLBACK.
Incluye paridad monetaria, varios leads por contrato, cooperativa, peso ausente,
descuadre, ámbito ajeno/inactivo, deuda real, cierre de 34 vendedores, foto
sellada y rechazo de UPDATE. No es la suite completa de conversiones.

La semilla conserva 2.048 leads y 32 contratos sintéticos en dos meses. El
cierre real medido el 26/09/2026 tardó 1,8–2,0 segundos; no es una garantía de
latencia para otros volúmenes. La rama debe eliminarse después del merge y del
postflight. Nunca copiar sus fixtures o contraseñas a producción.

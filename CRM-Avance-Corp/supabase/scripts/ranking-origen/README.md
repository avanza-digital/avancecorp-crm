# Ensayo de Ranking por origen

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

# Entrega A — ensayo remoto de Cartera
Fecha: 26/09/2026 Lima (27/09/2026 UTC).
Estado: pruebas funcionales PASS. NO aplicada en producción. No es autorización de publicación.

## Autorización y aislamiento
Miguel confirmó el ensayo, la organización AVANCECORP- CRM-PORTAL y US$ 0,01344/h.
Rama propia: ranking-cartera-20260927, ref qinpzjnslblwqjrhaqqf,
id 8a0d013e-f329-4a9f-bab9-cacc9eed1ffc; padre dctqcbznekcyxhjujuci.
Creada sin datos productivos. Usuarios/contratos/leads son sintéticos.
42 usuarios Auth, 2048 leads y 35 contratos; Cron: cero trabajos activos.
No se tocaron las otras ramas ni se copiaron archivos bancarios de clientes.
No hubo merge, commit, push ni despliegue productivo en este ensayo.

## SQL exacto y trazabilidad
Archivo aprobado: 20260927003433_crm_ranking_cartera_legada.sql.
SHA256: e2bc5cbea16b2efb4f4d9336a7f2cf0af1046f6e1595906951bed94388e30451.
Registro nativo en la rama: 20260927015203_crm_ranking_cartera_legada.
El registro contiene una sentencia con el SQL completo; MD5 del SQL registrado
y del archivo aprobado: eb06323a315aeadaf2f6cec388ecf562.
El nombre local y la versión remota difieren porque apply_migration asigna la versión;
antes de integrar, conciliar el nombre versionado sin duplicar la aplicación.

Único cuerpo de producto modificado: private.ranking_capital_origen_filas.
MD5 antes: 52ecf49a1c698e135a531b38ab75e291.
MD5 después: bfeaa3140c4fcdedb12566dcdf5ae9a6.
Núcleos monetarios intactos:
- capital_episodios: 214c6bada3dc63f553d7f9b62fd7963c.
- produccion_mes_por_vendedor: ecfdf7e030497af2f299ba327102a5ea.
Owner postgres, EXECUTE solo postgres, search_path vacío: intactos.

## Resultados
- PASS comparación inmediata antes/después de instalar: exactamente tres canales
  sin_origen → cartera, PEN 150000; mismas filas y resto de columnas.
- PASS huellas de contratos, leads, ledger, inversiones, cierres y auditoría;
  producción/conversión/vendedor/categoría financiera sin cambios.
- PASS matriz existente antes y después: seis grupos HTTP/Auth y once SQL.
  Gerencia/supervisor propio autorizados; ajeno/inactivo/cliente/anónimo denegados.
  Ambigüedad sin duplicados, COOPAC, centavos, peso ausente, descuadre fail-closed.
  Cierre real de 34 vendedores/2048 leads; foto sellada neta S/11900 con
  ajuste real S/100; snapshot inmutable y fotos antiguas no reconstruidas.
- PASS tres comprobaciones HTTP adicionales: Cartera PEN150000 con conversión
  nula y sumas por moneda conciliadas para gerencia y supervisor; vendedor ajeno
  rechazado con HTTP403/42501.
- PASS reversión exacta y reinstalación en transacción terminada con ROLLBACK:
  Cartera150000 → sin_origen150000 → Cartera150000.
- PASS preflights seed y RLS, offline y sin sembrar el banco general.
  Resuelve los fallos de configuración registrados en la fase local.
- PASS mismos grupos HTTP/SQL y tres HTTP adicionales tras sincronizar
  la migración productiva concurrente de cuentas bancarias.
  Cierre medido: 1108,411 ms baseline; 1113,921 ms candidato;
  1385,839 ms tras sincronización (mediciones únicas, no benchmark estadístico).
- PASS comparación Advisors inmediatamente antes/después del candidato:
  cero hallazgos añadidos o retirados, tanto seguridad como rendimiento.
- Claude: se conserva el PASS del SQL exacto en REVISION-CLAUDE.md.
  No se repitió la consulta porque el SQL no cambió.

Los fixtures remotos heredados de ranking preparan historia sintética con
session_replication_role=replica y restauran origin antes de probar.
Esto NO describe el runner local de 25 aserciones, que no deshabilita triggers.
No se debilitó ningún guard del producto.

## Reconstrucción y actualización concurrente
El replay nativo inicial se detuvo en la migración histórica 86, cuyo postflight
requiere datos de vendedores. Se reconstruyó solamente la rama vacía con la
estructura productiva actual y el historial exacto de 370 registros.
Se recuperaron comentarios que el dump eliminó de dos funciones; no cambió lógica.
El primer apply del candidato se revirtió por faltar el índice único de idempotencia
del historial. Se restauró ese índice de metadata y el segundo apply fue correcto.

Durante el ensayo entró en producción 20260927012948_crm_retirar_cuenta_cliente.
No afecta al lector ni a los dos núcleos monetarios. Se sincronizó en la rama
su SQL y registro exactos, además de la configuración de su bucket privado vacío.
No se copiaron documentos ni se ejerció la operación de retirar cuentas.
El rebase nativo devolvió success sin haber alineado aún ese registro; por eso se
verificó el catálogo real y se hizo la sincronización explícita en transacción.

Paridad final: 371 registros base, 816 funciones ajenas al candidato,
1274 columnas, 318 triggers, 106 policies, RLS de 127 tablas, 465 índices y
3 vistas coinciden en sus respectivas huellas.
Hay tres CHECK con serialización distinta únicamente de paréntesis AND
(empresas_monedas_check, producto_condiciones_capital_check,
alertas_reconocimientos_miembros_check); sus condiciones y semántica son iguales.
No se presenta como paridad literal de todos los CHECK.
La rama conserva 372 migraciones: las 371 productivas más solo el candidato.

## Advisors heredados
No se corrigen avisos ajenos automáticamente.
Después de sincronizar cuentas aparecen solamente dos INFO de su nueva tabla:
[RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
e [índice aún no usado](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
No fueron introducidos por el candidato del ranking.
Persisten sin cambios los WARN previos:
[EXECUTE anónimo](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable),
[EXECUTE authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[protección de contraseñas filtradas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection),
[initplan RLS](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan) y
[policies permisivas múltiples](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies).
Un aviso no equivale por sí solo a vulnerabilidad validada.

## Límites y pendiente
- NOT RUN matriz general de conversión/offboarding: se ejecutó la matriz focal
  pertinente de ranking, no se sembró el banco general encima.
- NOT RUN E2E integral/build frontend en este ensayo exclusivamente SQL.
  Los 66 tests frontend de compatibilidad y 25 aserciones SQL locales anteriores
  constan en VERIFICACION.md. No equivalen a un E2E del candidato remoto.
- Tipos no regenerados: no cambia schema público, firma ni JSON.
- NOT RUN merge/publicación. Falta autorización expresa y los gates de release:
  Main con avancecorp/main vigente, integración sin sobrescribir y artefacto del
  commit verificado cuando corresponda publicar frontend.
- El estado final de automatización de la rama se registra en CIERRE-RAMA.md;
  success de una solicitud de rebase no basta para declarar que terminó.
- Entrega B (nueva inversión por empresa, upgrade/renovación en UI): no iniciada.

Se usaron las skills Supabase, Supabase Postgres Best Practices y Context7
para aislamiento, documentación vigente, privilegios mínimos y verificación.
Evidencia saneada en remoto/. Credenciales y dumps privados quedan únicamente
en /private/tmp/ranking-cartera-remoto.p5DWEW, nunca se incluyen en la entrega.

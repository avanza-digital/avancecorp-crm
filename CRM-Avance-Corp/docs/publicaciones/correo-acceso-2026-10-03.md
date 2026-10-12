# Correo de acceso desde Convertir cliente — 03/10/2026

**ACTIVO Y VERIFICADO EN PRODUCCIÓN, 03/10/2026 11:16 Lima.**
Aplicación mediante `merge_branch`; estado final `FUNCTIONS_DEPLOYED`.

Miguel autorizó activar el arreglo general con «ok vamos con eso entonces».
El analista corrige «Correo de acceso Avance» dentro de Convertir cliente,
revisa y continúa la misma solicitud. Antes de crear Auth, la ficha y la reserva
se sincronizan. Si Auth ya existe, se conservan sus credenciales y se puede
retomar el alta; el cambio de correo se hace por un administrador del portal
en Clientes → Editar → Correo electrónico, con motivo y la misma contraseña.
«Gestión de acceso» describe esa operación; no es el nombre de un menú.

## Alcance verificado

- SQL original: `20260925170437_crm_correo_acceso_sincronizado.sql` y
  `20260925201350_crm_correo_acceso_indice_unico.sql`.
- Ambos archivos coinciden con `avancecorp/main` en
  `536454e3bc895fa62711508bfcdd4fa5f8c0ae21` y con los dos únicos registros
  adicionales de la branch hospedada.
- Branch: `correo-acceso-20260925`, proyecto `ultbhxxwaobtjlbuydvi`;
  destino: `dctqcbznekcyxhjujuci`. Se rebasó sobre producción antes del gate.
- Funciones CRM/private: 860 productivas frente a 866 candidatas. Solamente
  cambian tres cuerpos; se añaden seis helpers. Las seis dependencias del
  preflight coinciden con producción inmediatamente antes de solicitar el merge.
- Políticas, vistas, tablas, columnas, índices y triggers: 1.097 objetos
  productivos frente a 1.100 candidatos; únicamente se añaden los tres triggers
  previstos. Cero objetos anteriores diferentes o ausentes. Misma comparación
  tras completar el gate RLS.
- Las 22 Edge Functions coinciden en SHA-256 y `verify_jwt`. Los cinco archivos
  desplegados de `crm-inversion-portal` coinciden con el handler y dependencias
  utilizados en las pruebas. No hay nueva publicación frontend: el build vivo
  `build-20261002T005154879Z` ya contiene el flujo compatible.

## Verificación del 03/10

| Comprobación | Resultado |
|---|---|
| `check:scripts`, `test:edge-preflight` | PASS |
| `seed:preflight`, `test:rls:preflight`, seed hospedado | PASS con credenciales del destino de ensayo |
| SQL local, banco Docker propio | PASS, 22 aserciones |
| GoTrue/PostgREST local y handler Edge actual | PASS, 21 pruebas, incluidas carreras y roles |
| E2E Docker `acceso-avance-ux.spec.ts --workers=2` | PASS, 5 pruebas |
| `test-rls.mjs` completo en branch hospedada | PASS, 2.547 aserciones, salida 0 |
| GoTrue/PostgREST hospedados y handler Edge actual | PASS, tres escenarios, salida 0 |
| Advisors seguridad | Sin alertas nuevas frente a producción |
| Advisors rendimiento | Solo diferencias de uso de índices; sin nuevas clases de alertas |
| Review adicional mediante `scripts/claude-review` | NOT RUN: dos intentos sin dictamen válido; no se cuenta como PASS |

Escenarios hospedados: una reserva corregida crea una sola cuenta con el correo
nuevo y tolera reintentos; una petición tardía con el correo anterior se rechaza
sin dejar un usuario huérfano; una cuenta Auth ya creada impide cambiar sus
credenciales por esta puerta y permite completar el perfil pendiente.
Usuarios y correos sintéticos, confirmación administrativa sin envío de correo.

La primera corrida RLS se interrumpió por fixtures del 25/09: cuentas bancarias
duplicadas e identidades ligadas a documentos fijos. Antes de reconstruir solo
datos sintéticos se guardó un dump completo de 7.074.352 bytes, validado con
`pg_restore --list`. Esquema, restricciones, policies y aserciones se conservaron.
La segunda corrida comenzó con siete leads activos y cero identidades. El smoke
inicial intentó INSERT directo de lead (correctamente rechazado); se ajustó el
fixture a la RPC vigente `crear_lead_si_disponible`, sin cambiar permisos.

Advisors preexistentes no modificados. La diferencia de rendimiento corresponde
al [uso de índices](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)
en un ensayo sintético frente a tráfico real. No se propone retirar índices por
esa diferencia. La advertencia productiva de
[`pg_net` en public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public)
no aparece en la branch; no forma parte de este cambio.

Los dos reviews de implementación del 25/09, sus hallazgos y respuestas siguen
en `supabase/scripts/correo-acceso/REVISION.md`. El intento adicional del 03/10
no produjo VERDICT válido ni dentro ni fuera del sandbox. Se completaron los
checks reales indicados arriba; no se presenta la ausencia de review como aprobación.

## Evidencia local y reversión

Postflight productivo: 420 migraciones, con las dos versiones originales añadidas
y las 418 anteriores presentes. Las 866 funciones CRM/private y los 1.100 objetos
estructurales comparados coinciden exactamente con la branch ensayada. Los tres
triggers están habilitados. Los seis helpers no conceden EXECUTE a anon,
authenticated ni service_role. El índice original de reserva está listo y válido;
el duplicado no existe. Las 22 Edge Functions siguen activas, con el mismo código
y `verify_jwt`; el build frontend conserva su identificador previo. Advisors de
producción después del merge: cero alertas nuevas de seguridad o rendimiento.
No se crearon cuentas ni contratos reales como prueba.

Al cerrar la sesión, Miguel solicitó eliminar lo que ya no era necesario. Se
retiraron 20 temporales de `/private/tmp/` (7.931.859 bytes): credenciales y contraseña
del banco, runners, prompts, logs, copias SQL y dumps sintéticos. Los resultados
verificados quedan documentados en esta acta; esos archivos temporales ya no existen.

Se eliminaron la branch remota `correo-acceso-20260925`, los contenedores locales
`correo_acceso_20260925_auth` y `correo_acceso_20260925_rest`, y su base exclusiva
`correo_acceso_20260925`. Antes de retirarla se comprobó su nombre, las etiquetas
de ambos contenedores y cero perfiles no sintéticos. Verificación posterior:
branch ausente, cero contenedores propios y cero bases con ese nombre.
El stack Docker compartido y los recursos de otras tareas se conservaron.

Salida final conservada del gate: `RLS OK — 2547 aserciones; gate aprobado`.
Smoke: tres PASS (correo atrasado sin huérfano; correo corregido con una sola
cuenta; cuenta previa con recuperación de alta). Código, migraciones, pruebas,
reversa y registro de la recuperación puntual se conservan como evidencia útil.

Reversión operativa: `supabase/scripts/correo-acceso/revertir-comportamiento.sql`.
Conserva el guard contra altas tardías; no borra cuentas, contratos ni correcciones
auditadas. El ensayo de reversión consta como PASS en el runbook del 25/09.

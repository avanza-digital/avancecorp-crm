# Tasas inferiores — publicado

**Publicado y verificado el 14/09/2026.** SQL instalado en producción como
`20260914174353`, conservando intacto el archivo fuente `20260914042114`.
El banco temporal autorizado fue eliminado; coste estimado US$0,059 de US$1.
La publicación posterior de Citas conserva este cambio. Estado vigente, builds,
pruebas y límites: [acta de publicación](PUBLICACION-2026-09-14.md).
La pausa y la preparación de [verificacion.md](verificacion.md) son historial.

## Comportamiento

- Inversión `nuevo`: de 0,01 % hasta la base vigente (15 % en la lectura del
  14/09), con hasta dos decimales. Arranca en 15 y admite coma o punto.
- Superar la base mantiene la aprobación de Gerencia para la misma intención.
  Una solicitud pendiente bloquea incluso si se escribe una tasa inferior.
- La tasa elegida se conserva desde lead hasta contrato. Si deja de estar dentro
  del rango vigente, se bloquea para revisarla sin sustituirla automáticamente.
- Renovaciones/upgrades conservan el mínimo heredado. La regla no concede permiso
  para rebajar contratos emitidos ni alterar su PDF.
- El ledger registra base, tasa y actor, con `tasa_inferior_sin_excepcion=true`,
  sin crear solicitudes artificiales.

## Archivos y ensayo

- [SQL candidato](../../migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql).
- `preflight-produccion.sql`: lectura de cuatro huellas, propietarios y política.
- `base-viva-funciones.json`, `alta-viva-funcion.json`: cuerpos anteriores
  capturados mediante SELECT, sin datos de clientes ni credenciales.
- `rutas-vivas-y-rls.json`: inventario de INSERT, RLS, borradores de reservas y cron.
- `verificar-local.py`, `test-tasa-baja.sql`, `test-reversa-conversion.sql`,
  `test-concurrencia-reversa-local.py`, `evidencias-local.json`: ensayo y evidencia.
- `revertir-antes-del-primer-uso.sql`: restauración exacta con guardas de uso/huella.
- `revision-claude.md` y `revision-claude-segunda.md`: dictámenes originales;
  `verificacion.md`: evaluación final del PRIMARY.

Desde la raíz del repositorio:

```bash
python3 CRM-Avance-Corp/supabase/scripts/tasa-baja/verificar-local.py
```

Requiere Docker y el template sintético `crm_push_tasa_release_20260910` del
contenedor `supabase_db_avancecorp-f4-bank`. Crea y elimina su propia base aleatoria,
sin modificar el template. No recibe URLs ni destinos remotos. No es un replay
desde cero ni una copia de datos de producción.

El setup F3 repone el par estándar analista/vendedor del catálogo F5.b vacío en
el template, como administrador sin impersonación. Las operaciones posteriores
usan `SET ROLE authenticated` y JWT del analista, con lectura RLS propia. No se
deshabilitan triggers. Las aserciones sobre reservas cerradas a la API se hacen
con el propietario del banco después de ejecutar la operación autenticada.

Las dos carreras observan la espera real en `pg_stat_activity` antes de liberar
la primera transacción. La limpieza de su reserva sintética ocurre después de
las aserciones y exclusivamente en la copia desechable.

## Secuencia histórica de publicación

La siguiente receta ya se completó en el alcance descrito en el acta. No volver
a instalar esta migración. La inspección manual autenticada del paso 7 sigue
marcada NOT RUN; las verificaciones productivas efectuadas fueron de lectura.

1. Recibir la nueva instrucción de Miguel y completar el ciclo autorizado de banco
   Supabase: seed previo, candidata, oráculos, matriz RLS pertinente y advisors.
   El resultado y los límites del ciclo remoto constan en el acta publicada.
2. Integrar Main con `avancecorp/main` preservando las demás tareas. No usar
   `origin/main`, `tronco`, ramas de release ni force push. Main local y remoto
   deben coincidir antes de publicar. Si avanzan, verificar y reconstruir.
3. Repetir el preflight: cuatro cuerpos esperados, propietario común y helper
   ausente. Lectura previa: política v13, base 15, tope 28, vigencia 1 día,
   enforcement. Si hay deriva, revisar sin eliminar las guardas.
4. Instalar únicamente esta migración por el ciclo autorizado y merge del banco.
   No hacer `db push` general ni `apply_migration` directo a producción:
   existen candidatas ajenas de Citas. Actualiza tres funciones privadas y
   `public.crear_contrato`, sin cambiar firma, owner, ACL o search_path.
5. Comprobar ambas RPC de resolución, mínimos nuevos/heredados, helper privado,
   atributos de las cuatro funciones y advisors. No usar clientes reales de prueba.
6. Publicar el ZIP construido desde el commit de Main sincronizado y cotejar
   manifiesto. Servidor antes que frontend: su señal de capacidad habilita el campo.
   Sin esa señal el frontend conserva el mínimo anterior.
7. Verificar con una sesión autorizada la vista, tasa inicial, borrador inferior y
   bloqueo de pendientes, sin enviar solicitudes ni emitir contratos de prueba.
   Guardar evidencia y actualizar el vault a publicado.

El paquete local se conserva fuera del web root en
`CRM-Avance-Corp/releases/tasas-inferiores-20260914/` del workspace principal.
El manifiesto vincula ZIP, commit y hashes; no sustituye los controles remotos.

## Recuperación

La reversa restaura exactamente los cuatro cuerpos y sus permisos. Rechaza
contratos a tasa inferior y conversiones comprometidas: reservas activas, selladas
o leads convertidos. Después de ese punto se corrige hacia delante. No borrar
registros para permitir la reversa.

Durante esa operación manual toma `ACCESS EXCLUSIVE` en contratos, leads,
reservas y ledger para drenar también las lecturas previas a la validación.
Puede pausar brevemente sus lecturas; si no obtiene los candados en 5 segundos,
aborta sin restaurar ninguna función. No cambia banderas ni apaga enforcement.

Puede restaurarse el frontend anterior conservando el servidor compatible;
el anterior no ofrece tasas inferiores nuevas. Guardar los artefactos previos
fuera del web root.

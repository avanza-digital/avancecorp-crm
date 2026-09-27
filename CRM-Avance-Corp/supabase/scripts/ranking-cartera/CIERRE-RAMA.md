# Cierre del ensayo remoto

26/09/2026 Lima — rama ranking-cartera-20260927 (qinpzjnslblwqjrhaqqf).

**PASS: Supabase terminó en FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY.**
El segundo rebase, después de alinear la base, terminó correctamente.
Se resolvió el estado MIGRATIONS_FAILED del replay histórico inicial.
No hay merge productivo: último conteo de producción, 371 migraciones y cero
registros crm_ranking_cartera_legada. Rama: 372, incluida solo nuestra candidata.

La rama queda conservada para la siguiente etapa autorizada; continúa el coste
aprobado US$0,01344/h (aproximadamente US$0,32 por día). No se borraron datos
ni ramas ajenas. Eliminar o pausar la rama al terminar la publicación o si se
decide aplazarla; no dejarla como entorno permanente por defecto.

Falta autorización productiva, integración segura con Main vigente y las
comprobaciones de publicación aplicables. No aplicar el SQL directamente
a producción: utilizar el merge nativo después de verificar exactamente el
delta de migraciones y Edge Functions, que también entran en ese merge.

El patch entrega-a.patch conserva la evidencia LOCAL anterior y su SHA256.
No se alteró el SQL aprobado. El estado remoto posterior está en
ENSAYO-REMOTO.md, remoto/evidencia.json y los logs de las tres pasadas.
Al integrar, actualizar el ledger y conciliar la versión local 20260927003433
con la nativa 20260927015203 sin duplicar migraciones.

Los scripts de remoto/ documentan el ensayo ejecutado. Son adaptadores de una
rama específica, no un bootstrap genérico: dependen de los fixtures publicados
y de credenciales privadas fuera del repositorio. Nunca apuntarlos a producción.

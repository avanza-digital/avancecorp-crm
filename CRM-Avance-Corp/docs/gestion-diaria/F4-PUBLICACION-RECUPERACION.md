# F4 etapa 3 — preparación de publicación y recuperación

Estado al 21/09/2026: preparación técnica local verificada; **no autorizado ni
ejecutado en producción**. Gobernado por [GESTION-DIARIA.md](GESTION-DIARIA.md).
No incluye etapa 4, activación de cortes ni TypeSafe.

## Artefacto exacto y alcance

SQL candidato: `20260921214018_crm_gestion_diaria_cortes.sql`.
SHA-256: `8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`.
Se instala una sola política histórica v1, `cortes_activos=false`.
No ejecutar `db push` general ni migraciones pendientes de otros módulos.

Antes del release, conciliar la entrega con `avancecorp/main` sin sobrescribir
trabajo concurrente. El taller ya contiene el Main remoto `59dd1480` mediante
`9a101dcd`; comprobar otra vez el remoto al publicar. `43557bc9` corresponde a
trabajo local adicional de otra tarea, no al Main remoto confirmado. No resetear
esa rama ni incorporar/eliminar esos cambios por cuenta de esta entrega.
Main local y `avancecorp/main` deben terminar en el mismo commit aprobado.
Construir sólo desde ese commit limpio, nunca reutilizar el build de este ensayo.

Requiere aprobación del SQL exacto y la invocación humana de `$release-crm`.
Ni este documento ni la autorización del banco local permiten desplegar.

## Preparar el resguardo del destino antes de instalar

El responsable del release debe confirmar proyecto, identidad y entorno real,
sin usar las credenciales del banco. Registrar el commit de la aplicación vigente
y su artefacto recuperable, y comprobar el respaldo de base establecido por la
operación. No habilitar un recurso de pago ni asumir que hay PITR contratado.

Capturar en un archivo privado del release, antes del SQL, la definición completa,
owner, ACL, comentario y hash de estas seis funciones existentes:

- `private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)`.
- `private.gestion_diaria_equipo_core(date,uuid)`.
- `private.gestion_diaria_umbrales()`.
- `private.assert_gestion_diaria_analista()`.
- `private.assert_gestion_diaria_equipo()`.
- `private.assert_gestion_diaria()`.

Capturar además el comentario de `crm.gestion_diaria_equipo_fn(date,uuid)` y el
catálogo/grants/RLS de los objetos afectados. Ejecutar `private.assert_gestion_diaria()`
y los cuatro gates SLA (`assert_sla_nucleo`, `assert_sla_operacion`,
`assert_sla_comandos`, `assert_sla_avisos`). La tabla candidata debe estar ausente.
Si cambia algún sello o aparece otra instalación, detener y revisar; no adaptar
a ciegas los resguardos locales a producción.

## Secuencia de publicación autorizada

1. Verificar el resguardo del destino y repetir los gates sobre el commit final.
2. Ejecutar únicamente el SQL candidato aprobado por el mecanismo del proyecto,
   con parada al primer error. La migración es transaccional: si falla antes del
   commit, no continuar con el cliente ni repetir comandos sueltos.
3. Comprobar gates, recarga de esquema PostgREST y exactamente una política v1 OFF.
   Guardar la fila completa de esa política y los metadatos posteriores de las
   seis funciones en el resguardo privado de **ese destino**.
4. Smoke de lectura con identidades autorizadas existentes: equipo propio, detalle
   y analista; ajeno denegado; sin nuevos avisos. No sembrar fixtures productivos.
5. Publicar el cliente compatible desde el artefacto verificado, con el flujo
   de release, y repetir el smoke. La pantalla sigue siendo la de las etapas 1–2.

## Recuperación según lo que falló

Si el SQL no confirmó, comprobar la ausencia de objetos nuevos y los hashes
previos; la atomicidad se ensayó localmente con una excepción antes del commit.
No borrar objetos manualmente para “completar” un rollback ya efectuado.

Si falla sólo el cliente y el servidor pasa sus gates, recuperar el artefacto
anterior conservando SQL OFF. El contrato anterior admite los campos aditivos;
se verificaron los parsers reales anterior/nuevo contra ambos servidores.

Si debe retirarse SQL ya confirmado, preparar una reversión **específica del
destino a partir de su resguardo** y obtener aprobación antes de ejecutarla.
No ejecutar `http/reversa-candidato-solo-local.sql` ni quitarle su guarda de banco.
El procedimiento probado localmente es:

1. Exigir seis definiciones/owner/ACL/comentarios posteriores intactos, todos los
   gates y exactamente la fila v1 OFF capturada. Ninguna nueva versión, cambio
   administrativo o dependencia posterior es compatible con esta reversa.
2. En una transacción con timeout de bloqueo, bloquear la política y repetir las
   precondiciones. Restaurar las seis definiciones exactas previas, sin reconstruir
   su lógica mediante sustituciones aproximadas.
3. Retirar exclusivamente `assert_gestion_diaria_cortes`, `gestion_diaria_cortes`,
   la sobrecarga `gestion_diaria_umbrales(timestamptz)`, el resolutor de política,
   la tabla nueva y su función de trigger, sin `CASCADE`. Restaurar el comentario
   público. No borrar ni reescribir actividades, asignaciones o auditoría.
4. Ejecutar gates antes de confirmar y recargar el esquema. Comprobar después
   definiciones/ACL/owner/comentarios previos, las respuestas de las RPC y el
   inventario de datos de negocio. Si una dependencia o guarda falla, rollback.
5. Con el cliente nuevo aún presente, probar navegación y lectura contra el
   servidor anterior: esa combinación también se ensayó en navegador real.

Con cualquier política posterior a v1, **no borrar historia**. Mantener apagada
la presentación de avisos y preparar una corrección compatible aparte. La etapa
3 no aporta todavía el editor ni el control de emergencia de avisos de etapas
posteriores. No usar cambios retroactivos para arreglar resultados históricos.

La recuperación productiva no se ha ejecutado ni queda autorizada por esta guía.
Sus resguardos concretos, aprobación y smoke del destino pertenecen al release.
La evidencia local está resumida en [F4-CORTES-JORNADA.md](F4-CORTES-JORNADA.md).

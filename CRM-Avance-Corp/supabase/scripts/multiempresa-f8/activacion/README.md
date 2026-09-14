# F8 — primera activación del equipo nominal

Estado: **equipo seleccionado y verificado; SQL preparado y probado, todavía sin
configurar ni activar en producción**. La selección privada tiene cuatro
perfiles distintos: Gerencia, supervisor y dos analistas. Uno de los analistas
pertenece a otro supervisor. El piloto conserva las asignaciones vigentes y el
alcance de cada rol; no convierte al supervisor piloto en supervisor de todos.

## Qué ejecuta el SQL

[crear-sql.mjs](crear-sql.mjs) solo produce el texto SQL a partir de cuatro UUID,
roles y supervisores verificados, más un `responsable_id` y una referencia
explícitos. Rechaza UUID inválidos, duplicados, equipo incompleto, composición
incorrecta y referencias que no cumplan el formato cerrado. Los nombres y UUID productivos se guardan
fuera de Git. La [plantilla](activar.sql) no es ejecutable sin sustituir el JSON.

El SQL exacto inserta cuatro membresías y enciende el control en una transacción.
La vigencia propuesta es de **siete días desde la ejecución**. El acceso caduca
al vencer la ventana; esto no declara por sí solo cerrado G7 ni promete cambiar
el booleano persistente `activo`. Puede apagarse antes mediante la
[reversa nominal](revertir.sql), que exige su propio responsable y referencia
y conserva la historia. La [reversa operativa de emergencia](../reversa-operativa.sql)
existente sigue disponible si el responsable dejó de estar activo.

Se exige estado inicial OFF, revisión cero y sin participantes; cuentas/perfiles
activos, correo confirmado, identidad email y cuenta no suspendida/eliminada.
Se comprueban roles y supervisores exactos, F3 ON, F4–F7 globales OFF y cobertura
real sin brechas. Toma primero el candado compartido F3 y luego el exclusivo
F8. Lee cuentas, perfiles, equipo y banderas sin bloquear sus filas: algunos
writers ya toman primero esas filas y luego F8. La cobertura se comprueba antes
del candado F8 y otra vez en el trigger instalado bajo ese candado. Los triggers
siguen revalidando equipo, ventana y exclusión global; las capacidades vuelven
a comprobar el estado vigente del perfil/rol. Auth continúa controlando el login.

Una repetición se rechaza y requiere revisar el estado; no usa UPSERT para
reescribir miembros o alargar ventanas. Al terminar exige exactamente cuatro
personas con capacidad y ningún miembro ajeno habilitado.

`actualizado_por` recibe el UUID **explícito** del responsable operativo de
Gerencia propuesto en el paquete; el generador no lo infiere de la lista.
`motivo` guarda la referencia de la autorización y el ejecutor administrativo
Codex. `propuesta-activacion.json`, privado, liga esa referencia al SQL por SHA256
y permanece PENDIENTE hasta que el solicitante apruebe el encendido. El operador SQL conserva
`auth.uid()` NULL; la auditoría no finge una sesión ni una firma de ese usuario.
La aprobación humana corresponde al solicitante de esta conversación, queda
registrada antes de ejecutar y es distinta de la responsabilidad operativa.

No hay migración de schema, nuevos grants, cambios de Auth, reasignaciones ni
altas económicas en este paquete. En vigencia, el motor F8 instalado acompaña
las altas legadas con su espejo relacional para mantener cobertura; las nuevas
pantallas/acciones se habilitan solo al equipo nominal.

## Pruebas

Desde `CRM-Avance-Corp`:

```sh
npm run check:multiempresa:f8
npm run test:multiempresa:f8:activacion
```

PASS: 24 pruebas en el banco sintético local (23 subcasos y contenedor),
incluidos rechazo de perfiles/roles/supervisores cambiados, Auth suspendida,
eliminada, sin confirmación o sin identidad email, F3 OFF, rollout global,
revisión previa y sesión ajena. El SQL completo rechaza un supervisor obsoleto.
Las carreras contra las cuatro banderas globales y la reversa terminan sin
deadlock, comprobando la espera efectiva del competidor. Dos activaciones
simultáneas y un encendido global competidor permiten confirmar solo la
primera activación. También se prueba el rechazo previo por brecha real. Se verifican ámbito,
repetición, responsable/referencia explícitos y reversa idempotente. Las cuentas, hechos económicos y jerarquía mantuvieron
sus huellas; cinco eventos de auditoría con actor de sesión NULL. Siete días
exactos y capacidades F5/F6 de los cuatro, con usuario ajeno excluido.

La primera comprobación de ámbito omitió el UID de sesión y el núcleo devolvió
vacío como corresponde. Se corrigió el contexto del test; no se cambió el
núcleo. El segundo intento fue bloqueado por el aislamiento del socket Docker;
la ejecución autorizada posterior pasó todos los casos.

PASS: sintaxis y los 43 verificadores offline del gate F8. NOT RUN: ejecución
productiva, sesiones Auth/HTTP de los participantes reales y suite general RLS
en esta preparación. El ensayo combinado anterior conserva su evidencia propia.
No hay cambios de frontend/schema que requieran build o regenerar tipos.

La primera revisión independiente pidió cambios. Se incorporaron responsable
y referencia explícitos, reversa nominal, pruebas del SQL completo y menor
tiempo bajo candado. El PRIMARY reprodujo además un deadlock de la primera
versión, causado por `F8 → FOR SHARE banderas` frente a `fila bandera → F8`.
Se retiraron esos bloqueos de fila y la regresión concurrente pasó. Véase
[decisión del PRIMARY](evidencia-2026-09-14/decision-primary.md).
La [segunda revisión de Claude](evidencia-2026-09-14/revision-claude-2.txt) dio
**PASS**, con recomendaciones P3. Se completaron los casos de las cuatro
banderas, espera efectiva, COMMIT competidor y cobertura; se aclararon las FK
implícitas. La conexión MCP se comprobó como postgres, sin UID y READ COMMITTED,
en una transacción de solo lectura. Falta la aprobación humana de encendido.

## Punto de ejecución

1. Presentar el SQL nominal exacto y su vigencia; obtener aprobación de encendido.
2. Actualizar el preflight de solo lectura de las cuatro cuentas, jerarquía,
   control OFF, banderas y cobertura. Cualquier deriva detiene el paso.
3. Ejecutar una vez el SQL aprobado en una sola conexión. Con psql usar
   `-X -v ON_ERROR_STOP=1 -f activar-equipo.sql`, **sin `-1`**, porque el archivo
   ya abre/cierra la transacción. Ante cualquier error, detenerse y cerrar o
   revertir la transacción; no continuar copiando sentencias individuales. Con
   MCP enviar todo el archivo en una única consulta administrativa. Comprobar
   control, cuatro miembros, ventana,
   RLS/ACL, capacidades por actor, ámbito, auditoría y estado del resto del CRM.
4. Guardar el corte inicial del piloto y seguir [ACTA-G7.md](../ACTA-G7.md).

Archivos nominales privados en
`/private/tmp/avancecorp-f8-participantes-20260914/`: selección completa y SQL
exacto `activar-equipo.sql`, `revertir-equipo.sql` y la propuesta con referencia
`F8-20260914-01`. Los SHA256 nominales se guardan en la propuesta privada.
Los archivos versionados de esta carpeta son la plantilla sin identidades, pruebas sintéticas y evidencia saneada.

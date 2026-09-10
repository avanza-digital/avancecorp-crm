# F6 — implementación de postventa

Estado: **publicada e instalada, apagada, el 10/09/2026**.
Acta vigente: [[F6 - publicada y apagada (2026-09-10)]]. La evidencia local
original de esta nota se complementa con el ensayo y la publicación posteriores.
Última evidencia y correctivas: [[F6 - conflicto HTTP y ensayo remoto (2026-09-10)]].
Depende de [[F5 - instalada y apagada (2026-09-10)]] y del [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## Alcance y decisiones

- Una agenda física: `crm.tareas` admite un tercer sujeto, la persona inversionista.
  Se conserva el sujeto original y se resuelve la identidad canónica para ámbito e historial.
  Las tareas antiguas permanecen intactas. Con F6 activa, una gestión nueva desde un
  perfil enlazado se dirige a la persona; no se fabrican perfiles ni leads.
- F6 tiene su propia bandera `postventa_neutral`, inicialmente apagada. Requiere F3 y
  F5 disponibles. La instalación no activa inversión, postventa ni el piloto.
- Vendedor y supervisor trabajan en su ámbito vigente; Gerencia ve la cola sin
  responsable y asigna mediante la RPC F3 existente. Directorio conserva su lectura
  Avance y no obtiene las gestiones neutrales mixtas.
- Responsable Gerencia es válido para una tarea neutral. Si se pierde un responsable,
  la tarea queda visible en la cola de Gerencia; no se cancela por una mera reasignación.
- Orden de bloqueo: modo → jerarquía → documentos → persona → tarea. Una ruta que
  sostiene una tarea nunca espera por una persona. Los cruces heredados fallan con
  `40001`, sin completar parcialmente. Solo aislamiento READ COMMITTED.
- Las escrituras neutrales van por comandos con recibo idempotente. Un contexto
  interno de escritura, inaccesible a roles API, impide aprovechar una RPC antigua
  para escribir una tarea neutral. Una GUC del llamador no concede ese permiso.
- Veto global usa `private.leads_de_persona_veto`, incluye perfiles equivalentes y
  cancela pendientes aun cuando el booleano ya estaba activo. Levantarlo no revive
  tareas. Registrar/revisar un retiro solicitado por el cliente es gestión interna.
- Historial de gestiones conserva persona original, autor, fecha y empresa. La ficha
  une captación, cliente y postventa con orden estable y total/filas del mismo snapshot.
- Reinversión cooperativa añade un enlace inmutable solicitud → inversión anterior.
  Persona y empresa deben coincidir. La clave F4 y el origen se comparan bajo bloqueo;
  una solicitud ordinaria no adquiere un origen retroactivo. El wrapper primero toma
  persona, después clave y fuente; no bloquea la fuente antes de autorizar la persona.
  Se revalida al confirmar. Capital y depósito son nuevos; no se transfiere dinero del
  origen ni se calculan comisiones.
- Retiro: solicitud, revisión y resolución administrativa trazadas. Una solicitud
  activa por fuente mediante índice único. No liquida, paga ni anula la inversión.
- Vencimientos son una proyección de fuentes por empresa/moneda, no dinero almacenado
  en tareas. Se conservan renovación/upgrade Avance y nueva inversión de F4/F5.

## Revisión independiente y evaluación de Codex

Claude fue SECONDARY_REVIEWER mediante `scripts/claude-review`, sin herramientas ni
escritura. Dictamen de arquitectura: CHANGES_REQUESTED, confianza media.

Aceptadas: enrutamiento de perfiles enlazados, alcance explícito de la cola,
validación de veto y re-veto, orden persona→tarea, origen en idempotencia,
historial de reasignación sin lead, tipos de tarea existentes y aislamiento.

Matiz: un wrapper no obliga a bloquear fuente antes de persona. Se conserva F4 y
el wrapper adquiere la misma autorización/lock de persona antes de la clave y de
la fuente. Se verificó con carreras y conservación de funciones financieras.
Los riesgos de fallthrough eran hipótesis sin cuerpos de trigger adjuntos; Codex
inspeccionó los cuerpos y añadió una puerta neutral explícita, probada también
contra DML directo y llamadas antiguas. La revisión no equivale a verificación.

La segunda revisión también pidió cambios. Codex corrigió el ámbito F6 de la cola
de supervisor, el error local de postventa, la contención de banderas, el seguimiento
por perfiles, la cota de agenda y la traza del veto en leads. Rechazó inferencias
no confirmadas con evidencia: los grants ya permitían las columnas, la confirmación
ya notificaba errores y el enlace virtual es opcional. Se conservan lectura fresca,
fallo cerrado y cierre+próxima acción atómicos. No se atribuye a Claude un PASS final.
[Evaluación y pruebas de cada hallazgo](../../CRM-Avance-Corp/supabase/scripts/f6/REVISION.md).

## Evidencia técnica

- 41 pruebas F6 con Auth/PostgREST/Postgres locales reales y datos ficticios;
  46 pruebas de regresión F5 sobre el mismo banco con F6 instalada.
- Replay del SQL exacto en copia descartable: 564 funciones previas con ACL/owner
  conservados, seis extensiones previstas y once tablas de negocio/identidad/Auth
  sin cambios al instalar o revertir. Bandera nueva OFF y cero referencias D-19
  sin candado. Las seis huellas base también coinciden con producción (solo lectura).
- Tipos: 18 nodos introspectados; conserva los contratos Tasa ajenos al banco.
- Gate frontend PASS: 3.180 tests, lint/typecheck/cobertura/build/bundle/duplicación.
  Cuatro advertencias anteriores de coverflow; ninguna nueva.
- Navegación completa: 159 PASS, 26 omitidas existentes. Los siete recorridos F6
  cubren agenda/ficha, móvil, pérdida de respuesta, veto/retiro, Gerencia y Directorio.
  Capturas verificadas visualmente; no equivalen a aceptación humana F6.
- Preflights backend PASS. Matriz RLS general completa con F6 y advisors remotos
  NOT RUN; los 65 fallos anteriores de línea base no se consideran resueltos.

Paquete reproducible y límites:
[F6 README](../../CRM-Avance-Corp/supabase/scripts/f6/README.md),
[aceptación](../../CRM-Avance-Corp/supabase/scripts/f6/ACEPTACION.md),
[SQL](../../CRM-Avance-Corp/supabase/migrations/20260910150039_crm_f6_postventa_persona.sql).

## Puertas siguientes

Miguel autorizó publicar F6 apagada. El ensayo remoto detectó una incompatibilidad
de `40001` y se añadieron dos correctivas verificadas; quedan el cierre de gates,
publicación compatible, merge y comprobación productiva. La aprobación «hazlo.
aprobado» del 10/09 instaló F5 y ya fue ejecutada; no se vuelve a pedir por F5.
No se alteraron las quince identidades reales pendientes ni se activó el piloto.

F7 sigue pendiente; F8 requiere piloto real y F9 un ciclo mensual completo.

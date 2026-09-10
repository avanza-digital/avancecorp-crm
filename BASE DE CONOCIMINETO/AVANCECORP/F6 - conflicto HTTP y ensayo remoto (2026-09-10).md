# F6 — conflicto HTTP y ensayo remoto

Continúa [[F6 - implementación de postventa (2026-09-10)]] y el
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
Miguel autorizó publicar F6 apagada. La publicación ya se completó; acta vigente
y límites: [[F6 - publicada y apagada (2026-09-10)]].

## Hallazgo real antes de publicar

El banco alojado reprodujo una incompatibilidad que no aparecía en la instancia
local: PostgREST 14 reintenta automáticamente SQLSTATE `40001`. Una RPC de tarea
bloqueada agotaba 30 segundos; al soltar el candado el servidor todavía podía
completar un intento. La actividad SQL mostraba transacciones sucesivas.
[Supabase documenta el problema y su corrección en PostgREST 16](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).

Se conserva intacto el SQL F6 inicial. Dos migraciones adicionales traducen el
conflicto a `PT409` en 19 fronteras concretas: doce RPC F6, sincronización de tareas,
validación del origen de reinversión, degradación de ficha y cuatro RPC F4 usadas
por reinversión. En estas cuatro, el contrato anterior se conserva si no existe
un origen F6. No se cambia globalmente el tratamiento de errores de F3/F4.

El bloque exterior revierte toda la operación antes de devolver HTTP 409. Se
conservan firmas, propietarios, configuración y ACL. Los dos fallbacks de agenda
y ficha aceptan el nuevo conflicto sin ocultar errores de permisos. El journal
libera un primer envío rechazado explícitamente; conserva su clave si antes hubo
un resultado desconocido.

## Evidencia hasta este punto

- Misma reproducción bloqueada: HTTP 409 en **223 ms**, sin efectos parciales.
- **43/43** pruebas remotas F6: postventa 13, reinversión 9, integridad 9,
  concurrencia 5 y regresiones de revisión 7.
- **19 cuerpos exactos** según las correctivas; 1.401 objetos restantes del
  catálogo F6 idénticos. Firmas/ACL/propietarios/configuración preservados.
- Replay de los tres archivos F6: 564 funciones previas, diez integraciones
  previstas, fuentes/Auth/identidades intactas, banderas OFF, reversa y D19 PASS.
- Frontend: gate integral PASS, **3.182** tests, sin nuevas advertencias;
  journal 11/11 y recorridos F6 7/7 PASS.
- Reversa remota PASS: conserva seis conjuntos de tareas/recibos/historia.
- La matriz general anterior y posterior al SQL F6 inicial obtuvo exactamente
  **1.772 PASS / 45 FAIL**, sin regresiones. La repetición con seed limpio tras
  ambas correctivas dio exactamente las mismas cantidades y los mismos 45 fallos.
  No se presentan como resueltos ni como aprobación del piloto.

Un residuo ficticio de la matriz RLS necesitaba su identidad antes de los ensayos
F6. Se enlazó únicamente en el banco; no se tocaron identidades reales. El fixture
de postventa ahora restaura responsable y tramo mediante la RPC publicada, para
que un intento interrumpido no deje inconsistentes ambas proyecciones.

Revisión independiente adicional de Codex, sólo lectura: PASS sobre las dos
correctivas, journal y pruebas. Se aceptó ampliar la protección a la consulta F4
que recupera la solicitud. Este dictamen no es una nueva revisión de Claude ni
sustituye los gates de publicación. Los dos dictámenes Claude originales siguen
documentados en la nota de implementación.

Las comisiones continúan fuera del CRM. F4/F5/F6 permanecen apagadas y la
aceptación humana F6, conciliación F7, piloto F8 y ciclo mensual F9 siguen pendientes.

---
tags: [crm, cartera, f6, postventa, publicacion]
fecha: 2026-09-10
estado: publicada-instalada-apagada
---

# F6 — publicada y apagada

Miguel autorizó publicar F6 manteniéndola apagada. El frontend y los tres SQL
están instalados y verificados. F3 sigue encendida; F4/F5/F6 apagadas.
Las comisiones se calculan fuera del sistema.

Código: `b54fe94219fa516ab3824ec1be9ae756fc3144e1`.
Release: `crm-20260910T191116Z-b54fe94219fa`.
Main local y `avancecorp/main` coincidían al construir/publicar.
Los commits posteriores de cierre documentan ese mismo artefacto.

[Acta completa y evidencia](../../CRM-Avance-Corp/supabase/scripts/f6/PUBLICACION-2026-09-10.md).
Continúa [[F6 - implementación de postventa (2026-09-10)]] y
[[F6 - conflicto HTTP y ensayo remoto (2026-09-10)]].
Gobierna el [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## Qué quedó comprobado

- 43 pruebas remotas F6, 3.182 frontend, 159 E2E PASS; 26 E2E omitidas.
- Tres SQL exactos por banco → ensayo → merge. Se conservan los 268 registros
  anteriores; total productivo 271. No hay DDL de public ni reescritura financiera.
- Fuentes comerciales previas y permisos conservados. Se identificó una tarea
  legacy creada durante la publicación; las 3.411 anteriores conservan su hash.
- F6 responde `habilitada:false` bajo permisos authenticated/Gerencia.
  Banco temporal eliminado; banco-f7 conservado.
- Publicación Hostinger: 79 recursos, versión estable y acceso sin errores.
  Doce PNG mantienen la misma transformación CDN histórica.

El ensayo remoto encontró reintentos automáticos de PostgREST 14 ante conflictos.
Dos correctivas devuelven HTTP 409 tras rollback, sin duplicación ni efectos
parciales; una operación bloqueada pasó de agotar 30 segundos a responder en 223 ms.

## Límites que siguen vigentes

La matriz RLS general conserva **45 fallos de 1.817 comprobaciones**, exactamente
los mismos antes y después de F6; no se presenta como aprobada. Auth conserva
479 usuarios, pero su huella íntegra cambió durante un refresco de sesión.
La coincidencia temporal de usuario/sesión/refresh token respalda concurrencia;
no hay snapshot por columna que pruebe todos los campos iguales. El cierre es
**PASS CON OBSERVACIÓN**, conservando el fallo original y sus evidencias.

Permanecen **15 fuentes con identidad pendiente** (13 Avance, dos Qorilazo).
No se conciliaron datos reales ni se encendió el piloto.

## Retoma

1. Completar la revisión manual F6 sobre datos sintéticos. Miguel confirmó el
   10/09 la llamada en ficha, Hoy y Agenda, una sola vez en Agenda y la misma
   ficha tras recargar. También aprobó el cierre con detalle en el historial
   y un único próximo contacto con la fecha elegida, así como el cambio de hora
   de una reunión visible en Agenda y la confirmación de la cita.
   Miguel delegó a Codex la prueba de responsable y pasó
   con UI, sesiones de ambos asesores y comprobación funcional de la cola sin
   responsable. Las dos tareas conservaron identidad y horarios; el anterior
   perdió acceso incluso con su JWT previo. Codex probó después No contactar:
   canceló los pendientes, bloqueó contactos y el levantamiento por el asesor;
   Gerencia levantó el veto y se creó un contacto nuevo sin revivir cancelados.
   Se conservaron inversiones y banderas. En el punto 5 Codex confirmó por UI
   reinversiones ficticias Qorilazo/Prodelco: una inversión nueva por solicitud,
   origen conservado y confirmación repetida sin duplicados. Aumento y renovación
   Avance abrieron con el contrato correcto y se cancelaron sin crear solicitudes.
   La preparación y carga de esos comprobantes fueron por API local; la selección
   automática de archivos fue rechazada por Chrome. Después Miguel confirmó que
   la selección manual sí funciona en el Chrome habitual. Pidió que el control
   pareciera un botón: se aplicó el estilo navy del CRM al selector nativo,
   conservando el nombre del archivo y el foco por teclado. El ajuste visual está
   verificado en local (`npm run check` PASS) y aprobado por Miguel, pendiente de
   publicación. Miguel completó Qorilazo por UI: comprobante, Revisar y Confirmar;
   la ficha muestra tres inversiones y S/ 3.250, con antecedentes visibles. Falta
   el mismo recorrido completo de Prodelco (preparado con S/ 800 ficticios) y los
   puntos 6–8. La aceptación completa permanece
   pendiente. Registro y alcance:
   [avance manual](../../CRM-Avance-Corp/supabase/scripts/f6/REVISION-MANUAL-2026-09-10.md).
2. F7/G6: conciliar métricas, Capital y atribución por empresa y moneda.
3. F8/G7: piloto económico con sus participantes, volúmenes y firmas.
4. F9/G8: activación progresiva y ciclo mensual de observación.

No se hereda a F6 el visto bueno manual de [[F5 - instalada y apagada (2026-09-10)]].
El plan completo F1–F9 todavía no está terminado. Comisiones externas:
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

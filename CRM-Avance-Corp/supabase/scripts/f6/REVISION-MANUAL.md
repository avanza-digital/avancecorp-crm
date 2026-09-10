# F6 — recorrido de aceptación manual

En curso con Miguel. El 10/09 confirmó la creación y visualización de la llamada
en ficha, Hoy y Agenda, sin duplicación en Agenda, y la misma ficha tras recargar.
La aceptación completa sigue pendiente; continúa el punto 2. El registro y sus
límites constan en [el avance de revisión](REVISION-MANUAL-2026-09-10.md).

Usar el banco sintético y usuarios de prueba;
no activar producción ni registrar dinero o personas reales para este recorrido.
F3/F4/F5/F6 deben estar encendidas únicamente en ese entorno de ensayo.

1. **Vendedor:** abrir una persona Qorilazo sin perfil Avance. Agendar una llamada.
   Debe aparecer una sola vez en Hoy, Agenda y ficha. Abrirla desde Agenda y
   recargar: debe conservarse la misma ficha.
2. **Seguimiento:** cerrar esa llamada y programar el siguiente contacto. Comprobar
   detalle en historia, una sola próxima tarea y la fecha elegida. Probar además
   reprogramar y confirmar una reunión.
3. **Responsable:** Gerencia reasigna la persona a otro asesor. El anterior pierde
   acceso; el nuevo ve la tarea. Sin responsable, la persona queda en la cola de
   Gerencia hasta asignarla.
4. **Veto:** marcar No contactar con motivo. Los pendientes se cancelan y no se
   puede programar un contacto nuevo. Gerencia puede levantar el veto; las tareas
   canceladas no reaparecen.
5. **Vencimiento e inversión:** abrir un vencimiento Qorilazo/Prodelco y elegir
   reinvertir. Revisar que empresa, persona e inversión anterior son las correctas.
   Usar capital y depósito ficticios nuevos. La confirmación añade una inversión y
   conserva la anterior. Comprobar también que renovación/upgrade Avance siguen
   disponibles donde corresponde.
6. **Retiro:** registrar una solicitud, revisarla como Gerencia y dejar la resolución.
   Cambia el trámite; capital, contrato, pagos e inversión original permanecen
   iguales. Directorio no recibe esos botones ni la agenda neutral.
7. **Móvil y teclado:** repetir agenda/ficha en 390 px, recorrer los controles con
   Tab y lector de pantalla, abrir/cerrar los diálogos y comprobar foco/lectura.
   No debe haber desplazamiento horizontal ni salto periódico de la ficha.
8. **Respuesta perdida:** con una interrupción controlada del banco, recargar tras
   enviar una gestión. Abrir el mismo formulario y pulsar “Verificar envío guardado”.
   Debe existir una sola tarea; no debe permitir sustituir el envío pendiente por
   otro contenido. Este caso ya tiene prueba automatizada, no requiere provocar
   cortes en el servicio productivo.

Registrar fecha, rol, resultado y cualquier diferencia observada. Las capturas y
los tests automatizados no sustituyen este visto bueno. Este recorrido tampoco
firma G6, G7 o G8, que pertenecen a conciliación, piloto y operación mensual.

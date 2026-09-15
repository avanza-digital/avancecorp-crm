# Ruta pendiente para abrir Multiempresa a todos los analistas

## Decisión pendiente de Miguel

La revisión real está [documentada](README.md). La consulta enviada a Miguel el
15/09 propone **aceptar las 20 inversiones existentes como muestra de volumen y
completar en un banco aislado los recorridos y casos especiales ausentes**.
Todavía no hay respuesta a esa propuesta. «Retoma este objetivo» mantiene el
trabajo en marcha; no se interpreta como aprobación de cambiar los criterios G7.

Esta opción cambia cómo se acredita parte del piloto económico. No equivale a
una firma financiera, cierre G7 o permiso de activación. La alternativa vigente
es conservar el piloto y reunir los casos reales previstos. No crear operaciones
económicas ficticias en producción para acelerar la aceptación.

## Trabajo técnico autorizado que puede continuar

1. Consolidar las pruebas aisladas de diez reintentos idempotentes, cinco carreras
   económicas, recuperación ante fallo Auth y depósito repetido. Vincular cada
   resultado al código vigente; repetir solo lo que no cubran los ensayos anteriores.
2. Completar las rutas Avance → Qorilazo, Qorilazo → Avance, Qorilazo → Prodelco,
   una segunda inversión en la misma empresa y las dos adicionales. Probar los
   permisos de vendedor, supervisor, Gerencia y Directorio; el coordinador no
   adquiere gestión de inversiones. Las simulaciones siguen etiquetadas como tales.
3. Completar casos de identidad provisional, cotitularidad, anulación, retiro,
   upgrade reasignado y sello mensual en un entorno aislado. Registrar por
   separado la evidencia real que exista. Sin responsable ya tiene lectura SQL
   comprobada en dos personas reales, sin crear inversiones.
4. Ensayar activación y reversa del modo general con el mismo código instalado.
   Hay un antecedente de [92 comparaciones Auth/API en modo general](../../ficha-rendimiento/evidencias/http-remoto.json),
   pero no representa la futura operación de las 18 cuentas productivas ni una
   aprobación de sus permisos. Conservar los ensayos de denegación y alcance ajeno.

No hace falta esperar nuevas ventas para ejecutar estos controles técnicos.
La aplicación de los resultados sintéticos a las casillas reales G7 depende de
la decisión pendiente. El banco local puede usarse sin crear un banco remoto de pago.

## Revisión humana

Presentar un corte concreto de fuentes y excepciones, el resultado de las rutas,
soporte/reversa y las limitaciones restantes. Registrar aceptación de Miguel y
las responsabilidades financiera, técnica, seguridad, operación y del proceso
externo de comisiones según el maestro. No se calculan comisiones en el CRM ni
se reabre el G6 ya firmado: la conformidad nueva corresponde a F8.

## Activación F9 una vez aprobado G7

Las olas del maestro son Gerencia, usuarios piloto, supervisores/analistas y
finalmente métricas. El acceso de los cuatro miembros nominales ya existe, pero
no se declara por ello cerrada una ola F9 anterior a la firma G7.

La apertura a **18 analistas, 3 supervisores y 2 Gerencia** corresponde a la
tercera ola. Antes de ejecutarla:

- Confirmar cuenta, rol y supervisor vigentes, cero fuentes incoherentes y el
  mismo código probado. Hay 24 cuentas activas en total; el coordinador conserva
  su alcance. Directorio conserva únicamente su lectura Avance si existe.
- Preparar SQL exacto que haga la transición **F8 OFF y F4/F5/F6 globales ON en
  una única transacción**, con guardias de versión, configuración y composición
  del equipo; F3 permanece ON y F7 sigue OFF. Probar el orden de bloqueos y el
  aborto íntegro ante conflicto. No apagar primero en una transacción separada.
- Preparar reversa que corte las capacidades nuevas conservando inversiones,
  contratos, documentos, tareas e historial. Restaurar piloto solo si equipo y
  ventana siguen siendo válidos; no prolongar la ventana silenciosamente.
- Mostrar ese SQL ya probado para aprobación, conforme a
  `public_html/CLAUDE.md` y AGENTS. No hay un SQL de activación nuevo aprobado
  en esta entrega, ni se presenta una plantilla sin completar como aprobado.
- Tras aplicar, verificar las 24 cuentas, ámbitos propios/ajenos, la primera
  ficha por rol y las lecturas de Hoy/Cartera. Revisar fuentes nuevas sin identidad
  coherente: una sola brecha suspende F5 para todos por diseño.

Continuar la conciliación por corte, el seguimiento de errores y el monitoreo de
latencia. Si aparece P0/P1, desactivar el alcance afectado con la reversa ensayada.
F7 y el ciclo mensual G8 son pasos posteriores; abrir las fichas no termina todo
el plan principal ni autoriza retirar rutas antiguas.

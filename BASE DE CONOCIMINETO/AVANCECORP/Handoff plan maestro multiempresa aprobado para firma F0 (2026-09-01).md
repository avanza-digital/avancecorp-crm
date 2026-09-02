---
tags: [crm, multiempresa, inversionistas, identidad, capital, f0, handoff]
fecha: 2026-09-01
estado: aprobado-para-firma-documental-f0
autoridad: Miguel
serial_reanudacion: AVC-MULTIEMPRESA-G0-20260901-R1
plan_html: ../../PLAN-MAESTRO-MULTIEMPRESA.html
---

# Handoff — plan maestro multiempresa aprobado para firma F0

## Serial de reanudación

`AVC-MULTIEMPRESA-G0-20260901-R1`

Frase para iniciar la próxima sesión:

> Continúa el plan multiempresa con el serial AVC-MULTIEMPRESA-G0-20260901-R1. Lee el handoff del vault y comienza desde G0; no ejecutes F1 ni SQL sin la autorización separada correspondiente.

## Estado al cerrar la sesión

Miguel emitió el veredicto final: el plan maestro de cliente multiempresa queda **aprobado para firma documental de F0**.

La aprobación documental:

- convierte el plan en la autoridad propuesta para F0;
- no significa todavía que F0 haya sido firmado materialmente;
- no autoriza F1;
- no autoriza SQL, migraciones, backfill ni cambios en producción;
- no creó ramas Git ni Supabase Branch;
- no modificó el CRM, el Portal ni la base productiva.

El documento completo y vigente es:

- [PLAN-MAESTRO-MULTIEMPRESA.html](../../PLAN-MAESTRO-MULTIEMPRESA.html)

Ese HTML es la fuente completa del plan. Esta nota es el punto de reanudación para la siguiente sesión.

## Objetivo firmado conceptualmente

Una misma persona podrá invertir varias veces en Avance Corp, COOPAC Qorilazo o COOPAC Prodelco conservando:

- una identidad canónica cuando esté verificada;
- un solo lead canónico operativo;
- todos sus leads históricos;
- una sola historia comercial;
- una sola conversión durante toda su vida;
- cada inversión y empresa legalmente separadas;
- Capital, AUM, atribución y comisión sin duplicaciones;
- titularidad, cotitularidad y acceso Portal como conceptos distintos.

## Decisiones arquitectónicas cerradas

1. `private.capital_episodios` permanece protegido y no se reescribe para este proyecto.
2. No se crea una segunda calculadora de Capital.
3. Avance sigue entrando mediante `public.contratos`.
4. Qorilazo y Prodelco siguen entrando mediante `crm.cierres_externos`.
5. `crm.inversiones` será un registro relacional, no otra fuente financiera.
6. Las puertas, ventanas y consumidores existentes se amplían sin introducir reglas independientes.
7. `crm.inversionista_leads` conservará el lead canónico y todos los leads históricos.
8. Una persona no verificada puede tener candidatos provisionales separados; no se fusiona por nombre, teléfono o correo.
9. Una inversión confirmada tendrá exactamente una empresa, una fuente económica y un titular principal.
10. La titularidad se resuelve mediante `crm.inversion_titulares`; los cotitulares no duplican Capital.
11. Ser titular o cotitular no concede automáticamente Auth, Portal ni documentos.
12. Solo la primera operación elegible durante toda la vida convierte.
13. Una anulación de la operación ganadora no promueve otra inversión.
14. Si una fusión descubre dos conversiones, gana la primera y la posterior se corrige mediante ajuste append-only si el periodo está sellado.
15. ATR-4 manda: la anulación reduce conversión, pero no Capital, producción ni AUM.
16. La retirada financiera externa queda diferida hasta que una fuente consumida por Capital pueda representarla.
17. Para cooperativas solo se registran inicialmente solicitudes o revisiones de retiro, no una retirada financiera terminada.
18. Se reutiliza `crm.depositos_reclamados`; no se crea otro ledger.
19. Una inversión externa tiene un número de depósito vigente; el ledger conserva 1..N reclamos históricos si hubo correcciones.
20. La idempotencia guarda clave, tipo, versión, hash canónico del payload y resultado.
21. Misma clave + mismo hash devuelve el resultado; misma clave + hash distinto produce conflicto auditado.
22. La creación Avance usa una saga durable para Auth, perfil, contrato, inversión, Portal y correo posterior al commit.
23. Responsable actual, registrante, atribución histórica, atribución viva, fotografía sellada y comisión son conceptos diferentes.
24. La atribución viva de una cadena de upgrade Avance puede moverse por su cabeza autorizada; meses sellados y comisiones pagadas no cambian.
25. Los puentes hacia contratos y perfiles viven en `crm`; no se alteran silenciosamente tablas `public` del Portal.
26. Las RPC canónicas expuestas pueden ser `SECURITY DEFINER` si tienen `search_path` fijo, ACL mínima, validación interna de identidad/rol/ámbito y no reciben grants generales.
27. Núcleos y helpers privados permanecen en esquema no expuesto y sin grants a la API.
28. El backfill es un solo pipeline canónico, ejecutable en múltiples lotes, ensayos y reanudaciones.
29. F4 habilita escritores y UI; no vuelve a migrar los cierres procesados en F2.
30. Las rutas legacy se bloquean con flags durante el rollout y solo se revocan definitivamente en G8.

## Regla productiva de G0

Los hashes, migraciones y definiciones incluidos en el HTML son **referencias observadas**, no la firma definitiva.

G0 deberá recapturar directamente del servidor productivo posterior a ATR-2/ATR-4:

- migraciones aplicadas;
- firma y columnas retornadas de `private.capital_episodios`;
- `pg_get_functiondef` y `prosrc`;
- checksums reproducibles;
- propietario, volatilidad y `SECURITY DEFINER`;
- `search_path` y ACL;
- dependencias, especialmente `private.analista_atribuido_cadena`;
- esquema relevante de las fuentes;
- oráculos funcionales de Capital mensual y AUM.

Cualquier diferencia bloquea G0 hasta explicar la deriva y demostrar que los contratos siguen cumpliéndose. No se actualiza silenciosamente un hash esperado para hacer pasar el gate.

La recaptura de G0 es de solo lectura. G0 firmado tampoco autoriza automáticamente F1.

## Forma de ejecución aprobada

Miguel no quiere un cronograma artificial. Cuando se autorice la implementación:

- el alcance será completar todo el tren F0→F9/G8;
- se avanzará continuamente por evidencia;
- las tareas independientes se ejecutarán en paralelo;
- un gate se revisará apenas sus entregables estén completos;
- no habrá pausas por calendario si la evidencia ya es suficiente;
- no se saltará ningún gate para ganar velocidad;
- el trabajo solo se detendrá por autorización pendiente, invariante rota, riesgo no resuelto o evidencia insuficiente.

## Reserva temporal de G8

Aunque la ejecución no está limitada por semanas ni fechas artificiales, G8 exige al menos **un ciclo operativo mensual completo**.

Debe cubrir:

- un cierre mensual y su conciliación;
- jobs diarios, periódicos y de cierre;
- vencimientos y alertas reales;
- estabilidad de Capital, AUM, conversión, atribución y comisión;
- cero P0/P1 abierto;
- cero huérfanos y sagas vencidas;
- rendimiento, RLS, Portal y operación dentro de umbrales.

Un P0/P1 o un cambio material en semántica financiera, conversión, comisión, seguridad o jobs reinicia el ciclo para el alcance afectado. Una corrección menor sin impacto en esas invariantes no lo reinicia.

## Punto exacto para la siguiente sesión

1. Leer esta nota y abrir `PLAN-MAESTRO-MULTIEMPRESA.html`.
2. Confirmar que Miguel desea iniciar G0.
3. Crear un worktree o rama separada; no cambiar de rama sobre el árbol actual con cambios existentes.
4. Preparar un Supabase Branch aislado para cualquier ensayo posterior.
5. Ejecutar G0 primero como auditoría de solo lectura contra producción.
6. Presentar el manifiesto productivo y sus diferencias.
7. Solicitar una autorización separada antes de comenzar F1 o escribir SQL.

## Documentos relacionados

- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]]
- [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]]
- [[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
- [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]]
- [[Plan maestro de ejecucion - identidad unificada de inversionistas (2026-08-31)]]

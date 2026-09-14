# Primer recorrido real de G7

Estado: primer caso identificado y verificado el 14/09/2026. Capital e identidad
conciliados por SQL; lista/ficha de supervisor/Gerencia pendientes por timeout y
revisión visual NOT RUN. El solicitante aún comunicará sus observaciones.
Resultado: [recorrido real y evidencia](recorrido-real-2026-09-14/README.md).
No registrar operaciones económicas ficticias en producción ni simular una
aceptación que todavía no ocurrió.

## Criterio de aceptación reafirmado

Datos y cifras deben venir de los núcleos canónicos. No crear lectores o
cálculos de negocio independientes para hacer coincidir una pantalla. Un
recorrido exitoso valida ese recorrido; G7 mantiene su matriz de empresas,
permisos, operaciones y conciliaciones.

## Fronteras localizadas para seguir el dato

Inspección estática en `c6e3985`, con CodeGraph primero y lectura enfocada donde
el índice no incluyó símbolos nuevos. Estas llamadas identifican la ruta que
se seguirá; no prueban por sí solas todo el backend ni una operación real.

| Entrada/lector | Frontera existente | Comprobación pendiente del caso |
|---|---|---|
| Alta manual de cliente | `crearClientePortal` → Edge `crear-cliente` (`app/src/data/crm-api.ts`) | Seguir la escritura canónica y su identidad, sin duplicados |
| Conversión desde lead | `convertirLead` → Edge `crm-convertir-lead` (mismo módulo) | Distinguir alta de persona de inversión/contrato confirmado |
| Cartera multiempresa | `listarInversionistas` → `crm.cartera_inversionistas_fn` (`app/src/data/inversionistas-api.ts`) | Identidad, responsable y empresas coherentes con los núcleos |
| Ficha | `obtenerFichaInversionista` → `crm.inversionista_ficha_fn` | Mismos importes, moneda, fechas y fuente, sin duplicados |
| Seguimiento | `postventa-api.ts` → `postventa_agenda_fn`, `postventa_ficha_fn`, `postventa_vencimientos_fn` | Solo seguimiento/obligaciones aplicables al dato registrado |
| Informe multiempresa F7 | `obtenerMetricasMultiempresa` → `crm.metricas_multiempresa_fn` (`app/src/data/metricas-multiempresa.ts`) | Su capacidad sigue OFF, comprobado por SQL para Gerencia; no afirmar que la pantalla está habilitada ni activarla fuera del alcance aprobado |

El piloto activa las capacidades F5/F6 y sus operaciones autorizadas. El informe
F7 conserva su bandera OFF; la comprobación de cifras incluirá las pantallas
vigentes y los núcleos, respetando esta separación de activación.

## Ejecución y seguimiento

El caso fue una inversión adicional Prodelco → Qorilazo sobre la misma persona,
no un alta nueva de perfil Avance: una conversión inicial anterior al encendido
y una inversión de Qorilazo confirmada durante F8. Fuentes, cartera del analista
y núcleo de capital coinciden en PEN 9,000; conversión conserva un solo cierre.
La fecha comercial de Qorilazo, 11/09, ya estaba en la solicitud.

El recorrido siguiente se conserva como guía. Identificación y conciliación
están documentadas para este caso; UI/Auth/HTTP, timeouts multirrol y restantes
casos/firma G7 mantienen sus pendientes.

1. Identificar el registro real creado por el solicitante y su hora/empresa.
   Guardar identidades y evidencia nominal solo en el registro privado.
2. Seguir el comando hasta el núcleo y sus efectos de identidad, asignación e
   inversión, según el flujo efectivamente usado. Crear un cliente por sí solo
   no demuestra una inversión o ingreso confirmado.
3. Contrastar lectores y pantallas con el mismo corte y significado de cada
   indicador. Revisar invalidaciones de caché si el núcleo está bien pero la UI
   no refleja el cambio; no duplicar cálculos para compensarlo.
4. Verificar las vistas de analista, supervisor y Gerencia con los alcances
   debidos, y documentar las diferencias de permisos como resultados esperados.
5. Adjuntar el resultado a [ACTA-G7.md](ACTA-G7.md). Conservar pendientes los
   otros casos y las conformidades que aún no tengan evidencia.

Comisiones externas, conforme al alcance ya aprobado.

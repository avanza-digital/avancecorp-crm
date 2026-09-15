# G7 — aceptación del piloto económico F8

**Estado: ABIERTO; piloto nominal ON desde el 14/09/2026 a las 13:23 Lima.** Esta acta se completa con evidencia
real; el banco sintético no firma ni reemplaza la aceptación humana.

## Preparación técnica

| Control | Estado | Evidencia |
|---|---|---|
| Control nominal y temporal instalado | PASS producción OFF | [Publicación del 14/09](PUBLICACION-2026-09-14.md), dos SQL literales y 279 entradas previas intactas |
| RLS, ACL y autorización por actor | PASS local y rama nueva | 31 pruebas SQL locales, 27 remotas y 12 grupos Auth/Data API |
| F8 y rollout global mutuamente excluyentes | PASS local y rama | Cinco carreras del control en cada entorno |
| Reversa conserva hechos económicos | PASS local y rama | Seis superficies económicas remotas sin diferencias |
| Enlaces de las fuentes reales | PASS producción | Diez enlaces aprobados ya aplicados; lectura del 14/09 a las 12:09 Lima: 600 fuentes reales y cero brechas |
| Exclusión demo de la cobertura y operación F5/F8 | PASS producción | Cinco fuentes demo conservadas y excluidas; lector operativo con 600 reales |
| Compatibilidad del paquete instalado | PASS producción/rama | Preflight vivo antes del merge y paridad posterior: únicamente las diferencias administradas revisadas |
| Equipo nominal | PASS selección y cuentas verificadas | Cuatro elegidos por Miguel; sin reasignaciones. Identidades guardadas fuera de Git |
| Configuración y encendido nominal | PASS producción, activo | [Acta de activación](ACTIVACION-2026-09-14.md); cuatro participantes y siete días, hasta el 21/09 a las 13:23 Lima |
| Advisors y tipos de rama | PASS paquete combinado | WARN sin cambios; INFO de RLS cerrado y FK en tablas pequeñas documentados; tipos F8 coincidentes |

La rama de instalación fue eliminada tras verificar producción. La suite RLS
general heredada completa no se ejecutó en el ensayo combinado; la matriz
específica F8 pasó. El encendido nominal y las capacidades SQL verificadas no sustituyen los casos
o firmas pendientes que siguen. El solicitante ya ejecutó el primer caso desde
el analista del supervisor piloto: [resultado del 14/09](recorrido-real-2026-09-14/README.md).
Identidad y PEN 9,000 conciliados con los núcleos. El timeout de lista/ficha de
supervisor y Gerencia (G7-R01) fue corregido y publicado el 15/09; la nueva
[verificación productiva de los cuatro contextos](ficha-anterior-2026-09-15/PUBLICACION.md)
pasa con límite SQL de ocho segundos por sentencia. Miguel aprobó la adaptación
visual de la ficha, ya publicada; UI/Auth/HTTP de sesiones reales siguen NOT RUN.
Datos/totales deben salir de los núcleos canónicos, sin lecturas o cálculos paralelos.

## Evidencia mínima real

| Requisito | Resultado | Evidencia / responsable |
|---|---|---|
| 15 identidades verificadas; al menos 5 por empresa | PARCIAL | Una identidad canónica comprobada por SQL en el primer caso; no completa el muestreo |
| 20 inversiones confirmadas y consecutivamente conciliadas; al menos 5 por empresa | PARCIAL | Una inversión nueva Qorilazo durante F8, conciliada con su antecedente Prodelco previo al encendido |
| 6 recorridos multiempresa obligatorios | PARCIAL | Prodelco→Qorilazo aporta un recorrido adicional representativo; revisión visual pendiente |
| Multirrol | PASS SQL / parcial real | Cartera y primera ficha de cuatro contextos vigentes PASS el 15/09 tras corregir G7-R01; rol SQL authenticated, timeout 8s y ROLLBACK. Login JWT/HTTP y recorrido humano productivo pendientes |
| Sin responsable | PENDIENTE | |
| Identidad provisional | PENDIENTE | |
| Cotitularidad | PENDIENTE | |
| Anulación | PENDIENTE | |
| Solicitud de retiro | PENDIENTE | |
| Upgrade reasignado | PENDIENTE | |
| Mes sellado sin reescritura | PENDIENTE | |
| 10 reintentos idempotentes | PENDIENTE | |
| 5 carreras económicas aisladas | PENDIENTE | No confundir con carreras del control ya probadas |
| Fallo Auth y depósito repetido | PENDIENTE | |
| Cero P0/P1 abiertos | G7-R01 resuelto técnicamente; revisión del resto pendiente | Corrección publicada y lecturas de supervisor/Gerencia verificadas el 15/09; esta comprobación no sustituye los casos G7 todavía pendientes |
| Cero diferencias financieras | PARCIAL | Sin diferencias en el caso de PEN 9,000; no equivale a conciliación completa del piloto |
| Soporte y reversa comprobados | PENDIENTE | |

Recorridos obligatorios: Avance→Qorilazo, Qorilazo→Avance,
Qorilazo→Prodelco, segunda inversión en la misma empresa y dos recorridos
multiempresa adicionales representativos.

## Firmas G7

| Responsable | Persona | Estado / fecha |
|---|---|---|
| Miguel — aceptación del piloto | Miguel | PENDIENTE |
| Financiero | Miguel | PENDIENTE para el corte F8 |
| Proceso externo de comisiones | Por designar | PENDIENTE |
| Técnico | Por designar | PENDIENTE |
| Seguridad | Por designar | PENDIENTE |
| Operativo | Por designar | PENDIENTE |

G7 solo cambia a **CERRADO** cuando todas las filas exigidas tienen evidencia y
firma. Las variaciones normales por ventas nuevas se documentan con un corte;
no invalidan una conciliación histórica ya firmada.

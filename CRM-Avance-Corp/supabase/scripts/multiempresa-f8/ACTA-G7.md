# G7 — aceptación del piloto económico F8

**Estado del expediente G7: conformidades según evidencia, sin firmas atribuidas automáticamente.**
La apertura operativa fue autorizada por Miguel y ejecutada el 15/09/2026 a las
21:08 Lima: [acta F9](../multiempresa-f9/apertura-2026-09-15/ACTA-PRODUCCION.md).
F4/F5/F6 ON para el equipo; F8 OFF, revisión 2; F7 OFF. Este expediente conserva
el historial iniciado con el piloto del 14/09 y sus pruebas. El banco sintético
no firma ni reemplaza la aceptación humana; G8 continúa en observación.

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

Revisión del **15/09, corte 15:07 Lima**: [613 fuentes reales y muestra retrospectiva](cierre-g7-2026-09-15/README.md)
comprobadas; 19 fichas con 25 inversiones y capacidades de 24 cuentas. Cero
diferencias internas entre Cartera/Capital/F7; los lectores comparten fuentes,
por lo que esto no sustituye contabilidad externa ni conformidad financiera.
La ficha rápida ya está publicada. El piloto sigue nominal y G7 abierto.

## Evidencia mínima real

| Requisito | Resultado | Evidencia / responsable |
|---|---|---|
| 15 identidades verificadas; al menos 5 por empresa | PASS técnico retrospectivo / conformidad documental pendiente | Muestra de 19 personas, 10 Avance/5 Prodelco/5 Qorilazo con una compartida; identificador vigente marcado verificado y ficha coherente. No se autenticó el documento físico |
| 20 inversiones confirmadas y consecutivamente conciliadas; al menos 5 por empresa | PASS retrospectivo conforme al método aprobado / conformidad pendiente | Miguel aceptó la muestra de veinte existentes más casos sintéticos. 25 inversiones en sus fichas; 614 fuentes coherentes en el refresco 18:32 Lima. No se presentan como veinte altas nuevas F8 |
| 6 recorridos multiempresa obligatorios | PASS sintético autorizado | Los seis recorridos completos mediante RPC HTTP; identidad/Auth conservados y operaciones únicas. [Casos complementarios](cierre-g7-2026-09-15/CASOS-COMPLEMENTARIOS.md) |
| Multirrol | PASS SQL y HTTP local / recorrido humano productivo pendiente | 24 cuentas reales comprobadas; todos los contextos del banco acumulado (56, no casos independientes), sesiones HTTP por rol, rechazo de reanudación ajena y todas las páginas de Directorio. El piloto real conserva solo cuatro participantes |
| Sin responsable | PASS lectura SQL Gerencia / gestión real pendiente | Dos personas, tres inversiones; fichas visibles y nueva inversión bloqueada hasta asignación. No se modificó su responsable |
| Identidad provisional | PASS sintético | Sin documento verificado no guarda solicitud; el fixture verificado permite continuar |
| Cotitularidad | PASS sintético | Titularidad documental/canónica única, sin duplicar persona, acceso ni capital |
| Anulación | PASS sintético | Cambia estado, registra un evento y conserva Capital/atribución/fechas |
| Solicitud de retiro | PASS sintético | Revisión solo Gerencia; reintentos únicos y ningún cambio en contratos/cierres económicos |
| Upgrade reasignado | PASS sintético / candidato real conciliado | Reasignar cabeza cambia atribución viva de su renovación y conserva autor; desglose 700+100=800. No se hizo una reasignación real. Nueve renovaciones históricas sin desglose siguen explícitas |
| Mes sellado sin reescritura | PASS sintético y estabilidad real | Sello sintético con dos fotografías conserva todo tras reasignar, invertir y reintentar; ajuste único al mes vivo. Las 16 filas reales de agosto siguen estables al refresco 18:32 |
| 10 reintentos idempotentes | PASS aislado SQL | [Ensayo local del 15/09](cierre-g7-2026-09-15/PRUEBAS-LOCALES.md): cinco reintentos Qorilazo y cinco Prodelco sin duplicar ni cambiar hechos |
| 5 carreras económicas aisladas | PASS aislado SQL | Dos sesiones coincidentes observadas por caso: confirmación, depósito cruzado, clave/importe, corrección y conversión inicial; una sola operación válida |
| Fallo Auth y depósito repetido | PASS aislado | Cuatro pérdidas de respuesta después de escrituras Auth/SQL reales locales, recuperadas sin duplicación. Depósito repetido denegado en carrera SQL |
| Cero P0/P1 abiertos | G7-R01 resuelto técnicamente; revisión del resto pendiente | Corrección publicada y lecturas de supervisor/Gerencia verificadas el 15/09; esta comprobación no sustituye los casos G7 todavía pendientes |
| Cero diferencias financieras | PARCIAL; coherencia interna PASS | 614 fuentes sin divergencias en el refresco 18:32. Conformidad financiera del corte F8 pendiente; no es validación de documentos/contabilidad externa |
| Soporte y reversa comprobados | PARCIAL | Cinco controles locales de transición/reversa PASS, dieciséis superficies conservadas; falta soporte y procedimiento productivo exacto aprobado |

Recorridos obligatorios: Avance→Qorilazo, Qorilazo→Avance,
Qorilazo→Prodelco, segunda inversión en la misma empresa y dos recorridos
multiempresa adicionales representativos.

Modo general ensayado localmente: 21 contextos, incluidas Coordinación,
inactividad y Directorio sin equipo. No hubo ampliación de acceso fuera de rol.
Las 65 funciones seleccionadas coinciden con producción; no se afirma paridad
completa del banco ni sesiones Auth de usuarios reales. [Evidencia local](cierre-g7-2026-09-15/PRUEBAS-LOCALES.md).

Miguel aprobó expresamente ese método el 15/09 («sii claro hazlo»), después de
su explicación. Los casos complementarios terminaron PASS: quince grupos HTTP,
tres financieros SQL y la matriz ampliada de permisos. El cotejo ampliado cubre
203 funciones, tres auxiliares y tres tablas seleccionadas, con recibos ligados
por hashes. No afirma paridad del esquema completo. Se conserva y evalúa la
[segunda revisión de Claude](cierre-g7-2026-09-15/EVALUACION-CASOS.md).
[Ruta de apertura y pendientes](cierre-g7-2026-09-15/APERTURA.md).
No se crearon ventas ficticias reales ni se declaran firmadas casillas por las
pruebas automáticas; soporte, SQL productivo exacto y conformidades siguen abiertos.

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

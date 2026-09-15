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

Revisión del **15/09, corte 15:07 Lima**: [613 fuentes reales y muestra retrospectiva](cierre-g7-2026-09-15/README.md)
comprobadas; 19 fichas con 25 inversiones y capacidades de 24 cuentas. Cero
diferencias internas entre Cartera/Capital/F7; los lectores comparten fuentes,
por lo que esto no sustituye contabilidad externa ni conformidad financiera.
La ficha rápida ya está publicada. El piloto sigue nominal y G7 abierto.

## Evidencia mínima real

| Requisito | Resultado | Evidencia / responsable |
|---|---|---|
| 15 identidades verificadas; al menos 5 por empresa | PASS técnico retrospectivo / conformidad documental pendiente | Muestra de 19 personas, 10 Avance/5 Prodelco/5 Qorilazo con una compartida; identificador vigente marcado verificado y ficha coherente. No se autenticó el documento físico |
| 20 inversiones confirmadas y consecutivamente conciliadas; al menos 5 por empresa | PARCIAL; lectura retrospectiva PASS | 20 fuentes seleccionadas, 25 inversiones en sus fichas, 613 fuentes internamente coherentes. Solo una solicitud F4 confirmada por un participante durante el piloto; no se acredita con la lectura el flujo operativo completo |
| 6 recorridos multiempresa obligatorios | PARCIAL | Única persona multiempresa: Prodelco→Qorilazo. Avance→Avance histórico incluye renovaciones/upgrades; no se equipara a una nueva inversión F8. Tres direcciones obligatorias no existen en los datos reales |
| Multirrol | PASS SQL / parcial real | 24 cuentas vigentes; F5/F6 habilitados solo a los cuatro nominales. SQL authenticated y ROLLBACK, sin login JWT/HTTP ni recorrido humano productivo |
| Sin responsable | PASS lectura SQL Gerencia / gestión real pendiente | Dos personas, tres inversiones; fichas visibles y nueva inversión bloqueada hasta asignación. No se modificó su responsable |
| Identidad provisional | PENDIENTE | |
| Cotitularidad | PENDIENTE | |
| Anulación | PENDIENTE | |
| Solicitud de retiro | PENDIENTE | |
| Upgrade reasignado | PARCIAL | Un candidato real, stock/atribución/autor coinciden entre fuentes; no se ejecutó ni aceptó una reasignación. Seis filas de desglose y tres renovaciones completas conciliadas internamente; nueve renovaciones históricas sin desglose explícitas |
| Mes sellado sin reescritura | PASS estabilidad entre lecturas / operación pendiente | Agosto conserva las 16 filas y ambas huellas entre 15:07 y 15:16 Lima; no sustituye una nueva prueba de escritura contra el sello |
| 10 reintentos idempotentes | PENDIENTE | |
| 5 carreras económicas aisladas | PENDIENTE | No confundir con carreras del control ya probadas |
| Fallo Auth y depósito repetido | PENDIENTE | |
| Cero P0/P1 abiertos | G7-R01 resuelto técnicamente; revisión del resto pendiente | Corrección publicada y lecturas de supervisor/Gerencia verificadas el 15/09; esta comprobación no sustituye los casos G7 todavía pendientes |
| Cero diferencias financieras | PARCIAL; coherencia interna PASS | 613 fuentes sin divergencias entre lectores compartidos. Conformidad financiera del corte F8 pendiente; no es validación de documentos/contabilidad externa |
| Soporte y reversa comprobados | PENDIENTE | |

Recorridos obligatorios: Avance→Qorilazo, Qorilazo→Avance,
Qorilazo→Prodelco, segunda inversión en la misma empresa y dos recorridos
multiempresa adicionales representativos.

Miguel tiene pendiente decidir si acepta la muestra real existente para el
volumen y completa los recorridos/casos ausentes en un banco aislado. El pedido
de retomar no se toma como aprobación de ese ajuste. [Ruta de apertura y
pendientes técnicos](cierre-g7-2026-09-15/APERTURA.md). No se exige crear ventas
ficticias reales ni se declaran firmadas casillas por las pruebas automáticas.

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

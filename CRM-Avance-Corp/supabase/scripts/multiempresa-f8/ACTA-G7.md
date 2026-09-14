# G7 — aceptación del piloto económico F8

**Estado: ABIERTO / NOT RUN en producción.** Esta acta se completa con evidencia
real; el banco sintético no firma ni reemplaza la aceptación humana.

## Preparación técnica

| Control | Estado | Evidencia |
|---|---|---|
| Control nominal y temporal instalado | PASS rama original / NOT RUN producción | Ensayo remoto aislado; rama anterior no mergeable y eliminada |
| RLS, ACL y autorización por actor | PASS local y rama original | 31 pruebas SQL locales del paquete; 11 remotas del control anterior, sin la nueva exclusión demo |
| F8 y rollout global mutuamente excluyentes | PASS local y rama | Cinco carreras del control en cada entorno |
| Reversa conserva hechos económicos | PASS local y rama | Seis superficies económicas remotas sin diferencias |
| Enlaces de las fuentes reales | PASS producción | Diez enlaces aprobados aplicados; lectura del 13/09 a las 23:08 Lima: 593 fuentes reales y cero brechas |
| Exclusión demo de la cobertura y operación F5/F8 | PASS local / NOT RUN producción | Cinco fuentes demo, cuatro con brechas; corrección preparada, SQL pendiente de aprobación |
| Compatibilidad para instalar el paquete combinado | PASS precondiciones / NOT RUN rama nueva | [14 definiciones previas coincidentes](instalacion/preflight-produccion-2026-09-13.json); no sustituye el ensayo ni el merge |
| Equipo nominal | PENDIENTE | Elegir Gerencia, un supervisor y dos vendedores |
| Advisors y tipos de rama | PASS control original / NOT RUN paquete combinado | WARN sin cambios e INFO F8 aceptados en la rama anterior; repetir en la rama con exclusión demo |

## Evidencia mínima real

| Requisito | Resultado | Evidencia / responsable |
|---|---|---|
| 15 identidades verificadas; al menos 5 por empresa | PENDIENTE | Prodelco parte con 4 |
| 20 inversiones confirmadas y consecutivamente conciliadas; al menos 5 por empresa | PENDIENTE | |
| 6 recorridos multiempresa obligatorios | PENDIENTE | |
| Multirrol | PENDIENTE | |
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
| Cero P0/P1 abiertos | PENDIENTE | |
| Cero diferencias financieras | PENDIENTE | |
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

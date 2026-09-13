# G7 — aceptación del piloto económico F8

**Estado: ABIERTO / NOT RUN en producción.** Esta acta se completa con evidencia
real; el banco sintético no firma ni reemplaza la aceptación humana.

## Preparación técnica

| Control | Estado | Evidencia |
|---|---|---|
| Control nominal y temporal instalado | NOT RUN | Candidata local, todavía sin rama Supabase |
| RLS, ACL y autorización por actor | PASS local | `npm run test:multiempresa:f8` |
| F8 y rollout global mutuamente excluyentes | PASS local | Cinco carreras del control |
| Reversa conserva hechos económicos | PASS local | Siete huellas sin diferencias |
| Cobertura completa F5 | PENDIENTE | 14 fuentes: 10 reales y 4 demo al corte de preparación |
| Equipo nominal | PENDIENTE | Elegir Gerencia, un supervisor y dos vendedores |
| Advisors y tipos de rama | NOT RUN | Requiere rama Supabase autorizada |

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

# Gestión Diaria F4 — cierre en curso

**Decisión vigente de Miguel, 22/09:** mantener la alerta de tasa muy baja apagada
hasta F5. No se compara aún con la tasa del equipo ni se permite activarla rellenando
la diferencia. El campo reservado conserva NULL; la publicación de F4 rechaza un
valor distinto. Esta decisión sustituye la opción anterior de activarla al rellenarlo.


Relacionado: [[Inicio]], [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]].

Miguel mantiene el objetivo de cerrar F4 etapas 4–6 y verificar una primera jornada
futura activa. Excluye TypeSafe y F5. Confirmó otra sesión editando el taller principal;
Codex trabaja solo en `/private/tmp/avancecorp-release.hvdub4/repo`, rama
`codex/gestion-diaria-f4-cierre`, base `e22c0cab`.

Tras confirmar que la otra sesión usa Docker, Miguel autorizó explícitamente utilizarlo
identificando el servicio como Gestión Diaria. Se reanudó solo `gestion-diaria-f4-http`,
con seis servicios, red propia sin egreso externo y puertos loopback propios. Auth
responde HTTP200. No se reinició Docker completo ni se modificaron otras instancias.

Tres SQL candidatos instalados solo en el banco propio: avisos, configuración y
grupos diarios. Gates/21 mutantes/roles/horarios/SLA PASS; frontend completo
`check` con 4.150 pruebas PASS. HTTP/Auth de seis roles y paridad de dos equipos
PASS. Tres carreras con dos solicitudes observadas esperando el mismo lock PASS:
publicación, entrega del popup y aplazamiento únicos; reconocimiento compartido.

El banco conserva historia sintética (v2 activa hoy, v3 OFF desde mañana). Producción
sigue v1 OFF y no tiene los nuevos candidatos. Navegador real, capturas móviles y
configuración legibles, persistencia entre sesiones y cotejo de tipos oficiales
PASS. Regresión nativa: 232 PASS, 26 SKIPPED de pantallas retiradas. Main agregó
E2E obligatorio en Docker: pendiente integrar y correr ese gate. Revisión final de
Claude en curso. Conciliación Main/ledger, entrega y primera jornada productiva
siguen pendientes. Claude previo CHANGES_REQUESTED sí recuperado.

Miguel pidió apoyo de Jev para avanzar más rápido. 13 pendientes clasificados en
2,2 s; una confianza baja se resolvió leyendo el requisito. No es integración F4.1
ni veredicto de pruebas. Ver [[Jev para auditar - que sabe juzgar y que no (2026-09-21)]].

Fuente operativa: [plan principal](../../CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md)
y [acta de ejecución](../../CRM-Avance-Corp/docs/gestion-diaria/F4-CIERRE-EJECUCION-2026-09-22.md).

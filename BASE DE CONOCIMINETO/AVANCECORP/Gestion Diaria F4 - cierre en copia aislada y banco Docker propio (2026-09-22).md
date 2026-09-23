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

Cuatro SQL candidatos instalados solo en el banco propio: avisos, configuración,
grupos diarios y separación de lectura/escritura (SLA fuera del lock de cortes).
Gates/25 mutantes/roles/horarios/SLA PASS; frontend completo
`check` con 4.153 pruebas PASS. HTTP/Auth de seis roles y paridad de dos equipos
PASS. Tres carreras con dos solicitudes observadas esperando el mismo lock PASS:
publicación, entrega del popup y aplazamiento únicos; reconocimiento compartido.

El banco conserva historia sintética (v2 activa hoy, v3 OFF desde mañana). Producción
sigue v1 OFF y no tiene los nuevos candidatos. Navegador real, capturas móviles y
configuración legibles, persistencia entre sesiones y cotejo de tipos oficiales
PASS. Regresión Docker: **232 PASS, 26 SKIPPED de pantallas retiradas, cero fallos**,
en `gestion-diaria-f4-e2e`, volumen propio, dos workers. Libro anterior de alertas
SLA compatible por HTTP y navegador entre sesiones PASS. Ambos dictámenes de
Claude se recuperaron CHANGES_REQUESTED; el PRIMARY resolvió con pruebas.
Main `7d65fcdb` integrado en `7c4a8d6c`; vigilante y F4 pasan juntos. Check y
Docker repetidos tras integrar Acceso Avance: 4.153 y 232 PASS, 26 SKIPPED. Respaldo y corrección del ledger
de etapa 3 preparados: 33 sentencias exactas, ensayo reversible y tres guardas
PASS; producción intacta. Ensayo remoto, entrega y primera jornada pendientes.

Miguel pidió apoyo de Jev para avanzar más rápido. 13 pendientes clasificados en
2,2 s; una confianza baja se resolvió leyendo el requisito. No es integración F4.1
ni veredicto de pruebas. Ver [[Jev para auditar - que sabe juzgar y que no (2026-09-21)]].

Fuente operativa: [plan principal](../../CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md)
y [acta de ejecución](../../CRM-Avance-Corp/docs/gestion-diaria/F4-CIERRE-EJECUCION-2026-09-22.md).

Propuesta exacta lista: cuatro SQL más conciliación administrativa, rama remota
con fixtures (US$0,01344/h; tope propuesto US$1) y publicación mediante
`$release-crm`. Pendiente autorización. Hostinger conectado; ZIP actual de Acceso
Avance `7d65fcdb` conservado y 107 archivos cotejados en origen.
[Propuesta de publicación](../../CRM-Avance-Corp/docs/gestion-diaria/F4-CIERRE-PROPUESTA-PUBLICACION-2026-09-22.md).

PR #73 abierto en borrador: https://github.com/avanza-digital/avancecorp-crm/pull/73.
Solo actas después del código ensayado `7c4a8d6c`. Organización confirmada para
cotizar; aprobación de SQL/banco y `$release-crm` solicitada, todavía pendiente.

---
tags: [crm, gestion-diaria, f5, checkpoint]
actualizado: 2026-09-24
---

# F4.1 apagada, F5 validada y F6 preparada

Continúa [[Gestion Diaria - auditoria y plan F4.1-F6 (2026-09-24)]].
La conformidad de Miguel está cerrada. No volver a pedirla. Trabajo reanudado
por su instrucción después de la pausa segura del 24/09.

F4.1 permanece apagada: 19/20 casos sintéticos, una falsa alarma y ausencia de
referencia real independiente por equipo. La muestra no demuestra utilidad
real. Coste y latencia documentados con sus límites; credencial y condiciones
de datos sin acreditar. No se transfirieron notas reales.

F5 está construida y validada en la copia separada autorizada, rama
`codex/gestion-diaria-f5-20260924`. Tablero por fecha, comparación ponderada,
equipos, analista, registro y hábitos de 7/14/30 días. Consultar/Enter confirma
el día y conserva foco/contexto. Pendientes y organigrama actuales explícitos.
Tasa muy baja continúa apagada. **SQL y frontend F5 NO publicados.**

[PR #94](https://github.com/avanza-digital/avancecorp-crm/pull/94) integrado por
`miguejbs98` el 24/09 a las 20:22:12 Lima en Main `8da4bcf3`, con árbol idéntico
al candidato `9bde971f`. Controles PASS; no hay revisión APPROVED registrada.
Codex no ejecutó ese merge ni una excepción. Debe resolverse la condición
expresa de revisión aprobada antes de publicar. Fuente inicial: `e2c73d5b`.

## Evidencia final

Main #93 integrado: `a1bbe24d` en la copia mediante `e523085e`. Se conservan
venta cruzada y la corrección de doble clic de Main #92. Código F5 sin cambios;
contratos de tipos integrados y cotejados con la generación remota.

- Gate frontend: **4.386 pruebas / 297 archivos PASS**, incluido build.
- Docker Chromium completo: **256 aprobadas / 0 fallos / 26 omisiones previstas**,
  un worker, sin reintentos. WebKit: **5/0**, un worker, sin reintentos.
- Los intentos con presión de memoria se conservan como fallidos; se detuvieron
  solo los bancos F4/F5 inactivos propios. WebKit final sin OOM. No se cambiaron
  el producto ni los tests para conseguir ese resultado.
- SQL/oráculo, paridad y guardas PASS. 365.000 llamadas en un año y 1.008 tareas
  sintéticas conciliadas. Reversa transaccional PASS, sin retirar datos/tablas.
- Baseline remoto anterior **2.226/0**. Candidata con script de Main #93:
  **2.267/0** (41 casos añadidos por Main). Catálogo original idéntico al padre
  antes de F5; doce funciones nuevas y dos cuerpos cambiados después.
- **21 solicitudes HTTP remotas / 7 actores Auth sintéticos reales PASS**,
  incluidos permisos, revocación con el mismo JWT y ámbito de supervisión.
  Once comprobaciones adicionales de cifras frente a registros originales PASS.
- Tipos y advisors PASS sin avisos nuevos; la deuda previa queda documentada.
- Revisión independiente histórica **CHANGES_REQUESTED**, seis P2/P3 resueltos
  y verificados por PRIMARY. No se pidió otra revisión para obtener un PASS.

La segunda rama `gd-f5-cierre-20260924` (`ozmxjmjopdnyhxsecmvf`) también se
eliminó; ausencia comprobada el 24/09 a las 19:31:22 Lima. Credenciales retiradas.
La rama ajena banco-f7 se conservó. Estimación acumulada de ambas ramas:
**US$0,019374**, no factura, dentro de los US$5 autorizados en la misma
organización. El aprovisionamiento automático parcial se reconstruyó sobre
semilla sintética y cotejo de catálogo; no se atribuye un replay íntegro exitoso.

Miguel autorizó el SQL F5 y `$release-crm` tras aprobación y controles pasados
en GitHub. No repetir la solicitud. Antes de promover, recrear
rama dentro del presupuesto restante, cotejar el padre vigente y ejecutar el
merge nativo con solo F5 pendiente. Nunca aplicar directamente a producción.
La preparación y el acceso del conector se documentan en
`docs/gestion-diaria/f5-2026-09-24/PREPUBLICACION-F5.md`: Hostinger ya se
recuperó con el token autorizado en el Llavero y el servidor oficial local.
Sitio exacto, lectura y herramienta de despliegue estático verificados. No se
publicó ni se modificó MCP global. La consulta 403 anterior no llevaba OAuth
y no acreditaba un fallo de la cuenta. ZIP anterior íntegro, portada/JS/CSS coincidentes; doce PNG servidos
difieren, siete solo en codificación y cinco en dimensiones.
El frontend sigue el flujo humano de release, desde Main limpio e idéntico
al remoto, servidor compatible primero. No eludir la revisión normal de GitHub.

## F4 y preparación F6

Ambos cortes reales del 24/09 están contrastados; el de las 16:00 se observó
en la sesión abierta con ocho analistas y cinco casos. El cierre de las 18:00
se auditó mediante lectura a las 18:58 Lima para las tres cuentas supervisoras:
ninguna podía presentar o posponer avisos después del cierre. Es una auditoría
posterior, no una observación manual exacta a las 18:00. El sábado 26/09 conserva
su control real pendiente.

F6 tiene inventario, transición, matriz de equivalencia y registro diario de
observación preparados. Debe conservar cola completa por cursor, filtros,
permisos, enlaces antiguos y confirmaciones de guardados. La cola F3 carga
hasta 100; no basta para retirar Seguimiento. La sonda de conciliación de solo
lectura ya pasó en el banco. Los siete días reales empiezan únicamente cuando
F5 esté publicada y verificada: **T0 todavía pendiente**. Seguimiento permanece.

## Documentos y continuidad

- Contrato: `CRM-Avance-Corp/docs/gestion-diaria/CONTRATO-F5-2026-09-24.md`.
- Evidencia: `docs/gestion-diaria/f5-2026-09-24/evidencia.json` y
  `CIERRE-ENSAYO-REMOTO.md` en esa misma carpeta.
- Review y decisiones: `docs/gestion-diaria/REVISION-F5-2026-09-24.md`.
- F6: `docs/gestion-diaria/PREPARACION-F6-2026-09-24.md` y
  `OBSERVACION-F3-F5.md`.
- Mismo tablero Figma: F4.1 OFF, F5 validada/publicación pendiente, F6 preparada.
- El PR #91 ya está MERGED. La pausa anterior queda como historia en
  `docs/gestion-diaria/f5-2026-09-24/PAUSA-2026-09-24.md`.
- Respaldo privado durable: `~/.local/share/avancecorp-checkpoints/gestion-diaria-f5-2026-09-24/`.

Véase [[Inicio]] y [[Gestion Diaria - supervisor con consulta por fecha (2026-09-24)]].

Preparación aditiva F6 verificada: [[Gestion Diaria - cola completa F6 preparada (2026-09-24)]].

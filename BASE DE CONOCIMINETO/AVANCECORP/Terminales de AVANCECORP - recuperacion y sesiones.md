---
tags: [herramientas, terminales, recuperacion]
actualizado: 2026-09-15
---

# Terminales de AVANCECORP — recuperación y sesiones

El 14/09/2026 Miguel pidió recuperar todas las terminales tras el cierre de VS Code.
Se abrieron y comprobaron visualmente ocho conversaciones originales, cada una en
su propia pestaña, además de la terminal usada para la recuperación. Cartera quedó
seleccionada. Las sesiones quedaron esperando instrucciones del usuario.

Directorio de trabajo:
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`.

| Nombre de la terminal | Comando para recuperar su conversación |
| --- | --- |
| CARTERA ANALISTA | `codex resume 01a07f3d-4a56-76f3-8658-dff84096777b` |
| CITAS - HISTORIAL CODEX | `codex resume 01a07f47-0f6a-7690-8b0c-69ef1136c950` |
| CITAS | `claude --resume ae6829db-7442-4362-a5c5-1776a7320667` |
| SOLICITUD DE TASA | `codex resume 01a08399-c213-7ea1-8620-7fc2456e94e2` |
| LEADS POR FECHA | `codex resume 01a09641-b5a3-7073-8e5d-24066c44258b` |
| MODULO DE VENTAS | `claude --resume 001395a1-9c57-45d5-8235-3936e63b14c3` |
| VENTAS - SESION ORIGINAL | `claude --resume 6a7b5261-7e95-4a6d-9296-fd970a21fda5` |
| PIPELINE - ENTREVISTA | `claude --resume 17ea1fe7-69fd-4e95-b0c7-5812743b0529` |
| COSECHA - CRM | `claude --resume 18ad9962-0a43-4e47-9847-411afaf0a131` |
| CONVERSION | `claude --resume d6df3160-701e-437d-b40b-6ac0e179546f` |
| CONTRATOS - PDF | `claude --resume 403cfe21-27c1-429c-adc7-820cb89f269b` |
| CORRECCION DE CORREOS | `codex resume 01a0a61b-e4b2-73d0-8175-7a3f137d048d` |

## Recuperación del 15/09/2026

Tras otro cierre accidental de VS Code, Miguel pidió recuperar Citas y después
todas las terminales. Se reabrieron y comprobaron visualmente las doce
conversaciones de la tabla, además de la terminal de recuperación. Se reutilizaron
las pestañas existentes de Citas, Conversiones y Cosecha. Citas quedó seleccionada.
Todas quedaron esperando instrucciones, sin enviar nuevos encargos a los agentes.

La conversación **CITAS** de Claude contiene el cambio más reciente: el ticket
cuenta todo el capital del mes, publicado y cerrado el 15/09. **CITAS - HISTORIAL
CODEX** conserva la etapa anterior del ticket unificado en soles, cerrada el 14/09.
Véase [[Citas Gerencia - ticket con todo el capital del mes 2026-09-15]].

## Cómo identificar las conversaciones

- **Cartera Analista**, también llamada **Cartera de Clientes** por Miguel, contiene
  el trabajo de identidad e inversiones multiempresa y el piloto F8.
- **Módulo de Ventas** es la conversación reciente sobre Facturación; la sesión
  original contiene su auditoría anterior de métricas.
- **Solicitud de Tasa** contiene la preparación y publicación de tasas inferiores
  a la base. **Citas de Gerencia** incluye el ticket mensual convertido a soles.
- El registro de recuperación anterior es la conversación Codex
  `01a09dfa-1ab9-7bb3-a622-65b0eef0a8a2`; Miguel confirmó allí que las terminales ya
  estaban abiertas. Sirvió para contrastar los nombres y las sesiones originales.

## Alcance de la recuperación

Reabrir una conversación recupera su historial. Los procesos de shell o comandos
interrumpidos por el cierre requieren una comprobación propia antes de continuar.
Los avisos antiguos de interrupción permanecen visibles en el historial de Codex.

Para una recuperación futura, comprobar primero qué pestañas y procesos siguen
vivos y evitar abrir dos veces la misma conversación. Ejecutar cada comando en
una terminal nueva del directorio indicado, sin añadir una instrucción que lance
trabajo automáticamente. Conservar las configuraciones y permisos existentes.

Relacionadas: [[Inicio]], [[F8 - piloto nominal activado (2026-09-14)]],
[[Citas Gerencia - decisiones finales para publicar 2026-09-14]],
[[Facturacion - modulo del dueno en produccion (2026-09-13)]],
[[Rentabilidades menores a 15 - publicacion autorizada 2026-09-14]].

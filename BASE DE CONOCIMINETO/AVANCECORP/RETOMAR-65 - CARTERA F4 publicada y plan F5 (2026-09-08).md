---
tags: [crm, cartera, multiempresa, retomar, F4, F5]
fecha: 2026-09-08
estado: F4-publicada-escritores-apagados-F5-plan-preparado
---

# CARTERA — F4 publicada; sigue implementar F5

Miguel autorizó «publica f4 y dame el plan de implementacion para f5». Se publicó
F4 y se entregó [[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]].
Las comisiones se calculan fuera del sistema. No añadir su cálculo o liquidación.

## Qué está publicado

- Web `https://crm.miavance.com`, build `build-20260908T222022754Z`.
- Fuente `264ece65332061fa6b7dcbfa8ec81e4381c6d69f`, con Main y `avancecorp/main`
  iguales antes de construir. Incluye el commit F4 `0a2e4db` y el cambio de Citas
  `264ece6`, integrado al detectar que Main avanzó durante la preparación.
- SQL canónico `20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`;
  SHA-256 `f0f28b032cfa7c4b65dc6734fb359e263f0feebaf174bf25537a215628a434ae`.
  La candidata técnica `20260907191832` quedó sustituida **sin aplicar**: no
  ejecutar ambas ni un replay global. La revisión conserva Rentabilidad R4 y
  la corrección documental exclusiva de Administración.
- `crm-contrato-pdf-v2` v14, plantilla v8 y fuentes anteriores conservadas.
  `crm-inversion-portal` v1. Ambos activos con verificación JWT obligatoria;
  14 archivos fuente descargados y comparados con el commit.
- F3 `resolver_en_puertas=true`; F4 `inversiones_escritura=false` y
  F5 `ficha_360_neutral=false`. Instalación no equivale a encendido comercial.

## Verificación y límites

48 cuerpos, propietarios y permisos exactos. Siete tablas nuevas con RLS y
sin acceso API directo. Ninguna diferencia de contratos, cuotas, cierres,
capital, PDF o documentos durante la instalación; cantidades conservadas.
539 contratos, 4.828 cuotas, 16 cierres y 14 inversiones vinculadas en la
captura; son cifras de esa comprobación, no un tablero en tiempo real.

3.090 unitarias y 49 Deno PDF conformes; 13 grupos SQL sobre otra copia sintética
con Rentabilidad enforcement vigente. Lint, tipos, build/bundle y preflights
backend conformes. Los 140 recorridos Playwright se verificaron en el commit
publicado: 136 pasaron en el checkout de compilación; cuatro fallaron por el
entorno de dependencias enlazadas/cargas y pasaron al repetirlos en el worktree
con dependencias propias. Se conservan 26 SKIP preexistentes. No se cambiaron
aserciones para esconder esos fallos. La tanda completa F4 anterior pasó 140/140.

Web: 79 recursos accesibles, login sin error y rutas internas cerradas. El
alojamiento recomprime PNG y reduce cinco logos grandes; los originales son
los mismos que la versión anterior y se comprobó su equivalencia visual.
Advisors: nueve avisos por RPC definidoras autorizadas, siete informativos por
tablas internas sin políticas de acceso directo y 21 por índices recién
instalados sin uso; todos corresponden a la arquitectura y permisos verificados.

No se crearon usuarios ni hechos económicos en producción para probar. No se
ejecutó backfill. F2 global queda retirado; los faltantes se tratarán con censo
vigente y lotes administrativos de como máximo 100 fuentes. La reversa operativa
es apagar flags y conservar datos, sin DOWN destructivo.

## Dónde quedó guardado

- Repositorio principal: `AVANCECORP-desktop`, Main siguiendo `avancecorp/main`.
- Implementación aislada: `/private/tmp/avancecorp-f4-desarrollo`, rama
  `codex/f4-cierre`; checkout limpio de publicación: `/private/tmp/avancecorp-f4-publicacion`.
- Respaldo privado permanente:
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/RESPALDOS-CARTERA/publicacion-f4-20260908-161043`.
  Incluye esquema, datos de 122 tablas (con Auth y metadatos de Storage), ZIP y
  manifiestos anteriores/nuevos, fuentes Edge, verificaciones y trabajo previo.
- Los cambios únicos anteriores del checkout principal se conservaron; siete
  copias antiguas de scripts F4 quedaron como WIP visible. No confundirlas con
  la versión confirmada y publicada ni confirmarlas mecánicamente.
- [Registro técnico](../../CRM-Avance-Corp/supabase/scripts/f4/PUBLICACION-2026-09-08.md)
  y [resultado productivo](../../CRM-Avance-Corp/supabase/scripts/f4/publicacion-2026-09-08/resultado-produccion.json).

## Siguiente trabajo

Implementar F5 por entregas y commits: contrato/lecturas autorizadas, cartera
unificada, ficha única, nueva inversión, aceptación G5 y paquete de publicación.
F5 no se implementó en este encargo. El plan define los archivos, RPC, fuentes,
permisos, pruebas y recuperación. Después siguen F6, F7/G6, F8/G7 y F9/G8.

Relacionados: [[Inicio]], [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[RETOMAR-64 - CARTERA F4 terminada y avance guardado (2026-09-08)]],
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

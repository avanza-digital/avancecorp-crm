# F8 — verificación remota en rama del 13/09/2026

## Resultado

**PASS en entorno Supabase aislado. Producción sin cambios. F8 permanece sin
instalar y apagada en producción.**

Se creó la rama temporal `multiempresa-f8-20260913` (`luftwjtpagmfcgfykrqv`)
con el coste horario autorizado por Miguel. Supabase no pudo reconstruir por sí
solo el historial: la rama quedó en `MIGRATIONS_FAILED` después de
`20260811210049`, mientras producción llega a `20260913173350`. La primera
migración pendiente contiene un postflight que exige filas de equipo y las
ramas no copian datos productivos. El mismo estado existe en las demás ramas
preview recientes del proyecto.

La rama F8 fue eliminada después de guardar la evidencia; su coste horario quedó
detenido. Las ramas antiguas de otros trabajos no se modificaron.

Por esa deuda histórica, la rama no fue apta para merge. Para completar la
validación sin copiar PII ni hechos reales, se restauró el banco sintético F7
que ya usa el paquete local: 15 perfiles de prueba, seis miembros de equipo y
92 inversiones sintéticas. Se omitieron únicamente los FK hacia
`auth.users` y `storage.objects`, cuyos datos externos no forman parte del
banco; F8 depende de `public.perfiles`, no de esos dos FK. Se instalaron en la
rama los mismos objetos, ACL y funciones F7 sobre los que pasó el banco local.

## Artefacto probado

- Commit de origen: `1aceef60cdb49625c1dc8060fd5b3ea65c98bb00`.
- Archivo: `20260913215240_crm_f8_piloto_controlado.sql`.
- SHA-256:
  `0807e59bcaccfbce8d7af02dc67fcfa8a64686305aaa976d4840af16c86c18fe`.
- Aplicación: archivo exacto, 26.011 bytes, bajo rol `postgres` en la rama.
- Estado inicial y final: F3 ON; F4, F5, F6 y F7 globales OFF; control F8 OFF.

La aplicación directa dentro de la rama fue solo un ensayo. No registró una
migración mergeable y no autoriza repetir ese mecanismo en producción.

## Matriz remota

`node --test` ejecutó la misma batería versionada de F8 contra Supabase:

- **11 pruebas PASS, cero fallos**, en 86,1 s;
- instalación OFF, RLS/ACL y reejecución rechazada;
- equipo incompleto, quinto futuro y perfil inactivo rechazados;
- cuatro actores nominales habilitados y actor ajeno excluido;
- pérdida de integridad y revocación suspenden el piloto;
- ventana máxima y ampliación activa rechazadas;
- espejo relacional global sin conceder la operación F4 a un ajeno;
- exclusión mutua entre F8 y rollout global;
- cinco carreras concurrentes dejan exactamente un modo activo;
- vencimiento automático y reversa conservan la historia.

Las huellas anteriores y posteriores fueron idénticas:

| Superficie | MD5 antes y después |
|---|---|
| Contratos | `c41dd05ba731a1946bf305627df6d282` |
| Cierres externos | `09a1efd6889b7b29b63d43a305db7f11` |
| Inversiones | `81c2e200b35cf47cb813b9c8f9f0ceda` |
| Inversionistas | `3f5256ed626ed4ba21f4f0d9acc3533d` |
| Titulares | `40c7fb241b10a69605940e95a251f5dc` |
| Periodos cerrados | `e455ab4bc9e41f9556b9d2c4df94b065` |
| Auth sintético vacío | `d41d8cd98f00b204e9800998ecf8427e` |

## Seguridad, advisors y tipos

- RLS quedó activo en las dos tablas F8.
- `anon`, `authenticated` y `service_role` no obtuvieron privilegios de tabla.
- Quedaron cuatro triggers de protección/auditoría y tres helpers privados F8.
- Los avisos `WARN` de seguridad no cambiaron.
- El advisor añadió dos `INFO` esperados por RLS sin policies: las tablas son
  deliberadamente inaccesibles por Data API.
- El advisor añadió dos `INFO` por los FK `actualizado_por`. Se aceptan porque
  el contrato limita las tablas a una fila de control y cuatro miembros; no hay
  un recorrido de volumen que justifique índices adicionales.
- Los bloques generados de `piloto_f8_control` y `piloto_f8_miembros` coinciden
  byte por byte con `app/src/lib/database.types.ts`.

## Pendientes reales

- Resolver 14 enlaces de cobertura: diez reales y cuatro demo.
- Elegir nominalmente Gerencia, un supervisor y dos vendedores.
- Resolver el historial no reconstruible de ramas o preparar un mecanismo de
  instalación compatible con el ciclo obligatorio y someterlo a autorización.
- Instalar F8 OFF en producción, cargar el equipo, autorizar el encendido y
  completar los casos y firmas de G7.

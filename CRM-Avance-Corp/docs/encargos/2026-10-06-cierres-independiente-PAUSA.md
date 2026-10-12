# Pausa segura · publicación independiente del cierre de gestiones

**Serial: CRM-CIERRES-INDEPENDIENTE-20261006-02**

Pausa solicitada por Miguel: «pausemos en un momento seguro». Se detuvo únicamente la prueba Docker propia. No continuar verificaciones, integración o publicación hasta que Miguel pida seguir. Su autorización anterior «deploy» se conserva para la reanudación.

## Estado guardado

- Código comprometido y subido en la [PR #209](https://github.com/avanza-digital/avancecorp-crm/pull/209), abierta en borrador. Última lectura: `REVIEW_REQUIRED`; GitHub exige una aprobación, sin bypass.
- Rama: `crm/publicar-cierres-sin-llamadas-20261006`.
- HEAD: `5683dbdfb650c704363b9e0e5ff3e29d77d4f99f`; incluye Main `62a375f0e23a220952489148c6f8e07357a053e8` (#208).
- Copia aislada: `/private/tmp/crm-cierre-paquete-2pwvxy9d/repo`, limpia al pausar. No cambiar ni limpiar el taller compartido: contiene trabajo ajeno.
- `LLAMADAS_CELULAR_APROBADAS = false` permite publicar Main completo con #207 mientras #190 sigue en desarrollo. Condiciona consultas, pestaña, receptor, formulario y store; conserva el registro manual v4 y Deshacer. Demo conservado. No modifica SQL, Edge ni permisos.
- SQL #207 **instalado y verificado**; no reaplicar. SQL #208 instalado por la otra entrega y comprobado. Postflight #207 tras #208: PASS `2026-10-07T01:35:34.117124Z`.
- **Frontend de este encargo todavía no publicado**. Última lectura del sitio: `build-20261006T213354829Z`, fuente `4e6ee7ee296be83cd96366e3e79685343b3b706b`.
- Rama temporal Supabase propia ya eliminada. Ningún recurso de otros agentes se detuvo.

## Verificación exacta

| Control | Resultado |
| --- | --- |
| Cuatro suites focalizadas del interruptor | PASS: 229 pruebas |
| `npm run check` sobre `789ebfff` | PASS: 6.267 pruebas / 391 archivos |
| `npm run check` sobre HEAD `5683dbdf`, con #208 | PASS: 6.279 pruebas / 392 archivos; lint, tipos, build, bundle y duplicación |
| E2E Docker del HEAD actual | **INCOMPLETO: interrumpido por pausa del usuario**, salida 143; no atribuir PASS |
| Restauración de dependencias del host | PASS: symlink `app/node_modules` repuesto y respaldo temporal retirado por el runner |
| GitHub #209 | Última lectura: preflight/cambios PASS; app-check en curso; Supabase Preview omitido. No se esperó su término durante la pausa |

Claude revisó el interruptor: **CHANGES_REQUESTED**, sin P0/P1. Codex evaluó sus observaciones con evidencia: Deshacer ya existe en producción y no cambia frente al build vivo; ambas tarjetas utilizan el hook condicionado; los consumidores de consultas están cubiertos. No atribuir PASS al reviewer. Informe y pedido saneado guardados en artifacts. No repetir la revisión original de #207.

La ejecución E2E detenida era de ocho especificaciones, un worker, 56 casos definidos. No había fallos registrados antes de la pausa, pero no terminó. Dos intentos previos fueron interrumpidos; uno registró OOM real con otras suites concurrentes (evidencia guardada). No cambiar tiempos ni aserciones para ocultarlo. El PASS histórico de 368 E2E sobre `a0c334ba` no acredita este HEAD.

Contenedor propio detenido: `avancecorp-cierre-independiente-e2e`; sesión 18961 terminada, exit 143. El runner confirmó «Dependencias del host restauradas». No quedan verificaciones propias ejecutándose.

## Reanudar desde aquí

1. Leer esta pausa y el estado JSON. Comprobar PR #209, Main remoto, build vivo y recursos Docker; integrar novedades sin sobrescribir trabajo ajeno. Mantener el interruptor cerrado hasta que el responsable de #190 verifique su backend y SLA.
2. Completar las ocho especificaciones Docker locales sobre el candidato vigente, con un worker y recursos disponibles. Runner: `/private/tmp/gestiones-clientes-independiente-e2e.py`. Conserva/restaura el symlink de dependencias. No ejecutar E2E en GitHub.
3. Registrar resultados, actualizar acta/PR y marcarla lista. Obtener la aprobación requerida por GitHub antes de integrar; no se ha solicitado una aprobación nueva durante esta pausa.
4. Integrar en `avancecorp/main`, comprobar Main local = remoto y árbol limpio. Construir **un ZIP nuevo** desde ese commit. Repetir checks solamente si el código nuevo o el gate lo requieren.
5. Ejecutar preflight Hostinger y publicar con la autorización «deploy» vigente. Wrapper oficial preparado, nunca ejecutado en modo publicación: `/private/tmp/gestiones-clientes-hostinger.mjs publicar <manifiesto absoluto>`. Verifica Main, limpieza, interruptor, dominio y hash. Preflight obligatorio separado: `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <ZIP absoluto>` desde la raíz Git original, actualizando sus objetos sin alterar el taller.
6. Verificar HTTP, versión y hashes publicados; cerrar actas y vault. La comprobación visual corresponde a Miguel. No fabricar gestiones de clientes reales para probar.

Las ocho especificaciones: `llamadas-celular`, `gestion-diaria-resultado`, `gestion-diaria-analista`, `f6-postventa`, `gestion-diaria-clientes`, `cola-v3-clientes-supervision`, `clientes` y `f5-cartera`, todas bajo `app/e2e/` con extensión `.spec.ts`.

## Artefactos y evidencia

- Estado: `app/artifacts/gestiones-clientes-independiente-estado.json`.
- Checks: `gestiones-clientes-independiente-check.log` y `gestiones-clientes-independiente-main-208-check.log`.
- E2E: `gestiones-clientes-independiente-e2e-pausa.log`, `gestiones-clientes-independiente-e2e-interrumpido.log`, `gestiones-clientes-independiente-e2e-oom.log`; recursos: `gestiones-clientes-independiente-recursos.json`.
- Review: `gestiones-clientes-independiente-review.txt` y `gestiones-clientes-independiente-review-pedido.txt`.
- SQL: [acta de despliegue](2026-10-06-cierre-gestiones-clientes-DESPLIEGUE.md) y artifacts productivos de #207; 3.075 aserciones HTTP aprobadas, cuatro suites SQL con y sin SLA, postflight y catálogo verificados. No acreditan #190.
- **No publicar** `releases/crm-20261007T000643Z-a0c334bae19c.zip`: no contiene el interruptor ni #208. Tampoco publicar el candidato antiguo `4d90e7ab`.
- Recuperación conservada: `releases/crm-20261006T213355Z-4e6ee7ee296b.zip`, SHA-256 `9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`. No revertir automáticamente SQL o historial.

Si desaparece la copia temporal, recuperar la rama desde `avancecorp` y los artefactos de esta carpeta. Las credenciales no forman parte de esta nota ni de la PR.

# Gestión Diaria F4 — correctivo HTTP verificado

Relacionado: [[Inicio]], [[Gestion Diaria F4 - pausa y conflicto HTTP pendiente (2026-09-22)]],
[[Gestion Diaria F4 - cierre en copia aislada y banco Docker propio (2026-09-22)]].

Miguel reanudó el 23/09. Trabajo en la copia aislada
`/private/tmp/avancecorp-release.hvdub4/repo`, rama `codex/gestion-diaria-f4-cierre`.
El plan principal vuelve a indicar trabajo activo y conserva los antecedentes.

El correctivo de `40001` a `PT409` pasa en PostgREST 14.5 local: dos carreras
con dos solicitudes observadas en el lock, una respuesta 200 y otra 409, sin
reintento infinito. Terminó a las 09:20 Lima. SQL, 24 mutantes, permisos y
conservación de estado PASS. Se corrigió el instrumento HTTP, se midieron sus
lecturas paralelas y se reanudó sin reinstalar el SQL local ya aplicado.

Propuesta revisable:
`CRM-Avance-Corp/docs/gestion-diaria/F4-CONFLICTO-HTTP-PROPUESTA-2026-09-23.md`.
Archivo `20260923021512_crm_gestion_diaria_conflicto_http.sql`, SHA-256
`428e6a19951afc12315b61c760ba679e37e0399ca4aa0d44dde7f938ce3ad18a`.
**Pendiente autorización remota de este quinto archivo**; las aprobaciones
anteriores de los cuatro SQL, conciliación, banco hasta US$1, organización y
`$release-crm` siguen vigentes. No se modifica ningún SQL ya aprobado.

Producción sigue v1 OFF y sin los SQL finales de F4. Ledger 341, con tres avances
ajenos desde la pausa: refrescar antes del ensayo final. La conciliación de etapa
3 ya está hecha. La rama remota anterior está eliminada (~US$0,048 estimados),
los siete contenedores Docker propios se reanudaron y quedaron aislados.
Código frontend idéntico al del PASS anterior: 4.158 tests y 234 E2E Docker.
Matriz remota de los cuatro SQL: 2.196/0; el quinto aún no tiene ensayo remoto.

Restan autorización adicional, ensayo remoto con catálogo vigente, merge de
cinco SQL con cortes OFF, frontend, política futura por gerencia y primera
jornada real. Tasa baja NULL hasta F5; F4.1/TypeSafe y F5 fuera de esta entrega.

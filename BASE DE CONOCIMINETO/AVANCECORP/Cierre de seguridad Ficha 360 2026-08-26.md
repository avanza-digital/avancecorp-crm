---
tags: [crm, ficha-360, seguridad, concurrencia, pdf, hard-delete]
actualizado: 2026-08-26
estado: preview-publicada-pendiente-aceptacion
serial: AVC-F41-360-20260825-R2
---

# Cierre de seguridad Ficha 360 — 2026-08-26

La entrega **AVC-F41-360-20260825-R2** cierra la revisión adversaria y
arquitectónica de [[Ficha comercial 360 de clientes - plan]] sin modificar
producción. El trabajo se ejecutó en la rama aislada
`feature/ficha-cliente-360-preview-20260825` y usa únicamente una base PostgreSQL
local desechable para las carreras de concurrencia.

## Decisiones de autoridad

- Leer un PDF sellado y materializarlo son capacidades diferentes. Directorio
  puede consultar lo autorizado, pero no crear, reanudar, subir ni sellar el
  documento.
- La precedencia Portal/CRM depende de la capacidad y no es una regla global:
  **CRM Directorio veta la materialización PDF**, mientras que la corrección
  administrativa histórica y el hard-delete conservan sus autoridades Portal
  expresas de Admin/Superadmin.
- Portal Directorio puede materializar solo cuando la misma identidad conserva
  una membresía CRM operativa activa de Vendedor, Supervisor o Gerencia.
- Las correcciones administrativas de contratos históricos siguen funcionando
  aunque el cliente esté inactivo o ya no tenga asesor. Los flujos de la ficha
  permanecen condicionados por cartera activa mediante sus wrappers exteriores.

## Orden de serialización

Los escritores quedan linealizados con este orden:

`jerarquía global → mutex de cobros → perfil del actor → perfil del cliente → contrato → cuenta/job/hijos`

La jerarquía usa lock compartido para operaciones comerciales y exclusivo para
rol, jerarquía, activación y alta de vendedores. Los cuatro mutadores exclusivos
reautorizan al actor después de esperar la llave y mantienen su perfil congelado
hasta `COMMIT`. Las firmas públicas conservan OID, owner y ACL; los cuerpos
canónicos clonados son privados y no tienen `EXECUTE` para roles API.

El mutex de cobros se toma compartido en los writers canónicos que parten del
padre y exclusivo en el `PATCH` operativo directo y en las fases críticas del
hard-delete. El `PATCH` autenticado queda limitado a estado, fecha y monto del
pago y a su registrador: RLS decide la cartera permitida y un trigger de sentencia
bloquea y reautoriza antes de modificar filas. Las rutas `service_role` incluidas
en el repositorio participan en el mismo orden.

## PDF y eliminación

- Edge autentica al actor antes de usar `service_role` y vuelve a comprobar su
  estado inmediatamente antes de emitir una URL firmada.
- La proyección legal del renderer no contiene cuenta bancaria.
- La preparación y la finalización del hard-delete toman jerarquía compartida,
  mutex de cobros exclusivo, perfil Portal del Admin/Superadmin y contrato. El
  `COMMIT` de la preparación es el punto de autorización para el borrado Storage
  y su finalización posterior; ambas fases también se probaron dentro de una
  misma transacción para asegurar que no haya una promoción de locks bloqueante.
- Otro Admin vigente puede adoptar el mismo token y manifiesto de un intento
  interrumpido; Storage se elimina de forma reintentable e idempotente.
- No se agregó una cancelación insegura: la base no puede saber si Edge ya borró
  parte del manifiesto externo.

## Evidencia local

- **2,347** pruebas de aplicación aprobadas en **175** archivos.
- **27** pruebas Deno de Edge/renderer aprobadas.
- **43** carreras deterministas aprobadas, además de una aserción transaccional
  preparación→finalización, pruebas de matriz híbrida,
  corrección histórica, adopción de hard-delete y dos finalizadores simultáneos.
- La migración comprueba en runtime OID, owner, ACL, defaults, `search_path`,
  orden de locks y ausencia de privilegios en clones privados.
- Los advisors `security` y `performance` de Supabase CLI 2.114.0 terminaron en
  verde contra una base local desechable. No detectaron hallazgos introducidos
  por F41; los tres avisos de seguridad y nueve informativos de rendimiento
  pertenecen al fixture previo a aplicar la migración.
- `git diff --check`, sintaxis del runner y limpieza por OID/marcador de la base
  desechable aprobados.
- Producción y datos reales no fueron consultados ni modificados.

## Preview aislada

- Commit de implementación: `6702444`.
- Proyecto: `avancecorp-crm-preview` (`prj_JtZjYFlEmmVdCBL99ctaCBZuPdUw`).
- Deployment: `dpl_GNBm6cTeWrwWKrKo2UpiDqDjaJMV`, confirmado por Vercel como
  `target: preview` y `Ready`.
- URL de aceptación:
  <https://avancecorp-crm-preview-295ehzulp-avancecorp26-1551s-projects.vercel.app>
- La URL responde `200`, publica `f41-preview-20260825`, bloquea robots por
  cabecera, meta y `robots.txt`, y limita `connect-src` a `'self'`.
- Se compararon los 71 archivos servibles: 69 fueron idénticos byte a byte y los
  dos HTML solo incorporan el script de feedback esperado de Vercel Preview. No
  apareció ningún endpoint Supabase/Sentry ni credencial en el contenido remoto.
- En navegador, Vendedor abrió Mi cartera y una ficha 360; Directorio quedó en
  solo lectura, sin cuentas bancarias ni acciones comerciales. No hubo errores
  de consola.
- No se usó `--prod`, no se promovió el deployment y producción quedó intacta.

## Riesgos residuales acotados

- El mutex global de cobros es deliberadamente conservador: elimina ciclos de
  locks conocidos a costa de poder serializar cobros independientes y reducir
  throughput bajo carga extrema. Debe observarse antes de intentar particionarlo.
- `service_role` sigue siendo una frontera de confianza. Las rutas canónicas del
  repositorio respetan el protocolo, pero SQL privilegiado arbitrario o una RPC
  privada nueva podrían omitirlo; toda ruta nueva debe adoptar el mismo orden.
- Fuera de F4.1, `crm.corregir_fecha_cierre_comercial` mantiene una ventana Low:
  comprueba Gerencia antes de esperar el contrato y no reautoriza justo antes
  del `UPDATE`. No existe una llamada runtime localizada ni modifica términos
  legales/PDF; debe corregirse si esa RPC se incorpora a un flujo activo.
- Si una revocación ocurre después de subir un objeto privado pero antes de
  registrar/finalizar el ledger, el siguiente writer lo deniega. El objeto puede
  quedar privado hasta que un worker autorizado lo recupere; nunca queda sellado
  ni se entrega una URL al actor revocado.
- Una URL ya emitida es una capability temporal y conserva su validez máxima de
  **300 segundos**. La reautorización final reduce la ventana, pero no puede
  revocar una URL que ya fue firmada.

Relacionado: [[PDF de contrato (generador) — plan]],
[[Offboarding seguro del CRM (P04)]], [[Acceso y roles del CRM]] y
[[Checkpoint F4.1 2026-08-25]].

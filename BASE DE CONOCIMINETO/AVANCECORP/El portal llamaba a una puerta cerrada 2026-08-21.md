# El portal llamaba a una puerta cerrada (2026-08-21)

**Sintoma.** Miguel, con la cuenta superadmin del portal, no podia eliminar el
contrato `2026-01-200000`. El boton estaba, lo pulsaba, y salia un mensaje rojo
generico: «No se pudo eliminar el contrato y sus archivos.»

**Causa.** La Edge Function `crm-contrato-pdf-v2` solo autorizaba el dominio
`https://crm.miavance.com`. El panel de administracion vive en
`https://miavance.com` — otro origen. El navegador veia la respuesta autorizada
para un dominio distinto y la descartaba: **la peticion nunca llegaba al
servidor**. Hueco de despliegue puro: el boton se publico en el portal, pero la
lista de origenes de la funcion solo contemplaba el CRM.

**Como se probo (sin adivinar).** Un `OPTIONS` desde cada origen. Los tres
recibian la misma cabecera:

```
Origin: https://miavance.com      -> access-control-allow-origin: https://crm.miavance.com
Origin: https://crm.miavance.com  -> access-control-allow-origin: https://crm.miavance.com
```

Y el registro de produccion lo confirmaba desde el otro lado: **cero llamadas a
esa funcion en 24 h**. Cuando el sintoma es un error generico de front, la
pregunta que lo parte en dos es «¿llego la peticion al servidor?». Si no llego,
no busques la causa en permisos ni en datos.

**Arreglo.** El secreto `CRM_ALLOWED_ORIGINS` **no existia** (comprobado con
`supabase secrets list`: 13 secretos, ninguno era ese), asi que crearlo no pisaba
nada:

```
supabase secrets set CRM_ALLOWED_ORIGINS="https://miavance.com,https://www.miavance.com" \
  --project-ref dctqcbznekcyxhjujuci
```

Tomo efecto **al instante, sin redesplegar**. Se eligio la via del secreto
justamente para no reconstruir el paquete publicado — ver
[[parche-solo-en-el-artefacto-no-existe]], que es como se rompieron las altas de
contrato el 19-ago. Verificado despues: cada origen recibe el suyo, el CRM sigue
funcionando y un dominio ajeno sigue rechazado.

⚠️ **El permiso vive en un secreto, invisible para quien lea el repo.** Conviene
llevarlo a `ORIGENES_PRODUCCION` en `handler.ts` la proxima vez que haya que
desplegar esa funcion por otro motivo — contrastando antes el paquete vivo con
el del commit.

**Lo que NO estaba roto.** Editar contratos desde el portal seguia funcionando:
el guardado va directo por RPC y solo el refresco del PDF pasa por la funcion, y
el front ya lo degradaba a **aviso** («La correccion quedo guardada, pero no se
pudo confirmar el nuevo PDF»). Solo caian los tres botones que viven DENTRO de
la funcion: eliminar contrato, ver PDF y rehacer PDF.

---

## Superadmin operativo: el asiento que faltaba

Mismo dia, segundo hallazgo. Miguel no encontraba como anular un cierre en
cooperativa. La funcion existia y estaba viva (`crm.anular_cierre_externo`, y
«Anular cierre» aparece en el JS publicado del CRM), pero es **exclusiva de
gerencia** y sus dos cuentas quedaban fuera: la superadmin solo recibe la
pantalla de Usuarios (`estado: administrador_roles`), y `miguel@cacmascapital.com`
es vendedor.

**El sistema ya contemplaba la solucion.** El validador de `crm.equipo` dice
«Superadmin Portal solo puede tener una membresia CRM activa como Gerencia», y
`acceso-crm.ts` valida esa misma figura al entrar. Faltaba solo la fila.

🔴 **La puerta de siempre estaba cerrada para esto**: `crm.asignar_rol_usuario_fn`
exige que quien recibe su PRIMER rol venga con rol de portal `comercial`
(«Solo un candidato CRM pendiente puede recibir su primer rol»). Un superadmin
nunca lo es. Se inserto la fila por servidor — el trigger validador corrio igual,
que es lo que hace legitima la via.

Verificado: identidad `miembro` + `gerencia` + `superadmin`; sin entrar al roster
de vendedores (17, sin el) ni a los supervisores de reparto. Reversible con
`activo=false`.

**Anular no es borrar.** La fila se queda con su motivo escrito y deja de contar
en cuota y conversion. Es de una sola direccion. Ver
[[conversion-una-sola-puerta]].

**Cerrado ese mismo dia:** el contrato `2026-01-200000` eliminado por el circuito
oficial (preparar -> retirar archivos -> finalizar) en una sola transaccion, con
copia en `audit_log`; y el cierre de prueba de S/ 100.000 anulado por Miguel
desde su cuenta nueva, motivo «DEMO».

Relacionado: [[Regimen documental del contrato 2026-08-20]] ·
[[PDF contractual privado e inmutable 2026-08-17]]

# PLAN MAESTRO del servidor (P-055) — de la deuda a la capa semántica

Código para retomar: **`RETOMAR-SERVIDOR`** · Escrito el 2026-08-28 · Reemplaza como plan vigente a [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]] y a [[Capa semantica del servidor - plan por nucleos (episodios)]] (ambos siguen valiendo como detalle técnico). Inventario de origen: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]].

Producido con tres arquitecturas independientes, un crítico de cobertura y **una auditoría adversarial de Codex** que refutó dos conclusiones mías antes de que llegaran al plan.

---

## 1. La problemática

El servidor funciona y el negocio opera. El problema no es que algo esté caído: es que **el sistema no tiene una sola versión de la verdad**, y eso ya empezó a costar decisiones.

**1. La misma cifra se calcula en muchos lugares distintos.**
El capital se calcula en **16 sitios**, la cantidad de leads en **21**, las citas en **6**. Cada pantalla lleva su propio cuaderno. Cuando dos no coinciden, nadie sabe cuál creer — y ya pasó dos veces este mes: el «Capital S/ 0» cuando había S/ 3,7 millones reales, y los dos contadores de leads que no cuadraban.

**2. Ninguna venta sabe quién la cerró.**
El sistema guarda quién *registró* el contrato, no quién lo *vendió*. En la mayoría coincide, pero no siempre: hay contratos cargados por administración o gerencia por encargo de un analista. Mientras eso siga así, **el ranking no puede ser exacto** y una futura comisión se calcularía sobre un dato aproximado.

**3. El mismo concepto tiene dos nombres.**
La misma persona es «analista» en el portal y «vendedor» en el CRM. No es cosmético: **en la sesión que produjo este plan, esa ambigüedad me hizo dar un diagnóstico comercial equivocado sobre datos correctos** — leí un grupo como si fueran dos.

**4. Datos con peso legal que se pueden cambiar sin dejar rastro.**
Los co-titulares de una cuenta mancomunada se pueden agregar o quitar sin que quede registro de quién ni cuándo, mientras el contrato al que pertenecen sí lo deja. Lo mismo con el borrado del historial de gestión de un cliente y con las cuotas de pago.

**5. Puertas abiertas heredadas.**
Permisos que vinieron de fábrica y nunca se recortaron, funciones viejas que ya nadie llama, dos contratos de prueba contando como producción real, y montos sin protección justo antes del primer cierre de mes.

**Por qué ahora:** el **10 de septiembre** es el primer cierre de mes real. Las tablas que hay que blindar están hoy vacías — hacerlo antes de esa fecha no cuesta nada; después, sí.

---

## 2. El objetivo

Un servidor donde:

- **Cada cifra tiene una sola calculadora.** Preguntar «cuánto cerramos este mes» tiene una única respuesta, igual en todas las pantallas, y cambiar una regla de negocio se hace en un solo lugar en vez de dieciséis.
- **Cada venta tiene dueño.** Todo contrato sabe qué analista lo cerró, ese dato no se mueve solo, y se puede reasignar dejando rastro. El ranking de agosto en adelante es exacto y sirve para pagar comisiones.
- **Nada con valor probatorio cambia sin dejar rastro.** Ante un reclamo, la historia se puede reconstruir.
- **Todo se llama igual en todas partes.** Un solo idioma entre el CRM y el portal.
- **Y no vuelve a degradarse:** una prueba automática impide que nazca una calculadora paralela o que se rompa el idioma. Es la diferencia entre una regla escrita y una regla que se aplica sola.

Todo esto es **medible**: el §9 trae el tablero con el número de hoy y la meta de cada punto.

---

## 3. Decisiones tomadas por Miguel (2026-08-28)

| # | Tema | Decisión |
|---|---|---|
| 1 | **De quién es un contrato** | **Del analista que lo cierra.** El vínculo cliente↔analista es para que el cliente vea a su analista en la app; **no es la guía del ranking**. |
| 2 | **Campo «analista que cierra»** | **Se crea y es obligatorio desde ya.** Cuando registra un administrativo o un supervisor, tiene que **seleccionar el analista**; si no corresponde a nadie, lo pone a su nombre. **Debe poder reasignarse** después. El histórico se rellena con la regla de respaldo. |
| 3 | **Qué fecha define el mes** | **La fecha de inicio del contrato**, no la de registro. |
| 4 | **Cooperativas** | **Son parte del capital**: el núcleo lee contratos **y** cierres en cooperativas (solo vigentes; los anulados descuentan). |
| 5 | **Desglose renovado/adicional** | **Se completa**: hoy está vacío en las 62 operaciones aunque 53 dicen «completo». |
| 6 | **Contratos demo en producción** | **444444 y 888282 son demos** (de Kirk) → se excluyen de métricas y ranking. **001163 es de Adelayda** y cuenta para agosto; **001325 es de Miguel Briceño**. |
| 7 | **Catálogo de productos versionados** (6 funciones dormidas) | **Eliminar.** |
| 8 | **4 funciones esperando pantalla** | **Publicar las pantallas** (Mi cartera, Ficha 360°, período comercial). Salen de la lista de retiros. |
| 9 | **Botón «eliminar cliente»** | **Avisar** qué se va a borrar antes de hacerlo. |
| 10 | **Superadmin borrando perfiles** | **Queda abierto como hoy** — excepción consciente, con su consecuencia aceptada. |
| 11 | **Nomenclatura** | **«analista» en todo el sistema**, CRM y portal. *(Ver §6: Codex recomienda acotar el alcance interno; requiere decisión final.)* |
| 12 | **Tablero por analista** | **Se abre**, verificado contra el cuadro de agosto. |
| 13 | **Conexión `crm_metricas_bridge`** | No se sabe qué la usa → **investigar antes de retirar nada** que dependa de ella. |
| 14 | **Arranque** | **Nada se ejecuta hasta aprobar este plan.** |

---

## 4. Los hallazgos que cambiaron el plan

### 4.1 La doble nomenclatura ya costó un diagnóstico

17 personas tienen a la vez `perfiles.rol='analista'` (portal) y `crm.equipo.rol_crm='vendedor'` (CRM), más 2 analista+supervisor. **No son dos grupos: son el mismo equipo.** Leerlos como grupos distintos me llevó a afirmar que «el capital lo registra el back office» y que «el CRM no captura la venta nueva». **Las dos afirmaciones eran falsas y quedan retractadas.**

### 4.2 Lo que Codex refutó de mi corrección

| Afirmación mía | Veredicto de Codex |
|---|---|
| (a) analista y vendedor son la misma persona | **Confirmada** — 17 + 2, verificado |
| (b) `creado_por` identifica a quien vendió | **Refutada como regla universal.** Reconstruyendo el asesor vigente al momento del alta desde `audit_log`: **7 contratos fueron registrados por gerencia para 3 asesores distintos**. El flujo de conversión ya separa explícitamente operador y asesor (`creado_por: callerId` vs `asesor_perfil_id: asesorId`). |
| (c) 465 de 466 registrados por el equipo comercial | **Confirmada, pero solo como distribución del registrador** — no demuestra quién vendió |
| (d) el mes se cuenta por fecha de registro | **Refutada — hallazgo principal.** El módulo vivo **ya usa `fecha_cierre_comercial`**, no la fecha de registro. Mi cuadro por «quién registró» difiere de la pantalla real en **15 de 18 personas** (S/ 6,53 M contra S/ 4,00 M). |
| (e) el núcleo debe atribuir por `creado_por` | **Refutada.** El núcleo vivo ya es **híbrido**: usa el analista explícito del lead si existe, si no el autor; exige pertenecer al **roster mensual** y suma los cierres en cooperativas. Agosto vivo = 118 − 8 (fuera del roster) + 5 (cooperativas) = **115 unidades**. |

**Conclusión de Codex, que coincide con lo que decidió Miguel:** conservar `creado_por` como *registrador* y **añadir una autoría comercial inmutable**. Ni `creado_por` ni la operación de cartera sirven solos.

**Dato relevante:** hoy **no existe módulo de comisiones** en el servidor (0 tablas, 0 funciones). El ranking no está pagando plata todavía — hay margen para hacerlo bien antes de que lo haga.

### 4.3 Cuánto se mueve el ranking según cómo se cuente

Producción de agosto de las tres primeras, según el criterio:

| Analista | Por fecha de registro | Por fecha de inicio | Definitivo (inicio + coop) |
|---|---:|---:|---:|
| Grecia Ramírez | S/ 1 170 600 | S/ 607 600 | **S/ 807 600** |
| Adelayda Gaspar | S/ 1 104 100 | S/ 366 600 | S/ 383 600 |
| Astrid Centenaro | S/ 653 100 | S/ 573 100 | **S/ 573 100** |

De 210 contratos registrados en agosto, **92 empezaron antes** (S/ 2,61 M, el 42 %). El podio cambia según el criterio: por registro, Adelayda es 2.ª; por fecha de inicio, cae al 5.º y sube Astrid.

⚠️ **Salvedad:** el ranking de arriba aún no aplica el filtro de roster mensual que el sistema vivo sí aplica (8 contratos quedan fuera). El núcleo debe decidir si ese filtro se conserva — está en las preguntas abiertas.

---

## 5. El diseño del capital

**Las tres reglas de la capa:**
1. **El núcleo no autoriza** — recibe la visibilidad resuelta, devuelve filas-hecho. En `private`, sin acceso desde la API.
2. **La ventana autoriza una vez** — un despachador por métrica.
3. **La pantalla no calcula** — solo suma, filtra y da forma.

**La regla que desbloquea todo:** las dimensiones con decisión abierta **viajan como columnas del hecho**. Así una respuesta tardía cambia números, no estructura.

**La fila-hecho de capital lleva:**
- El **analista que cerró** (campo nuevo, inmutable, reasignable con rastro)
- El registrador (`creado_por`), que se conserva y **no se pisa**
- Fecha de inicio del contrato (eje del mes) y fecha de registro (para auditar cargas tardías)
- Moneda (PEN y USD **nunca** se suman)
- Origen: contrato del portal o cierre en cooperativa
- Estado de anulación
- Marca de demo/prueba (para excluir 444444 y 888282 y los que vengan)

---

## 6. La campaña de nomenclatura — con el veredicto de Codex

**Inventario corregido por Codex:** 10 columnas, 4 tablas, 13 funciones, 17 índices con el término en el nombre; **54 funciones** con el literal; **7 políticas** que comparan el valor (no 18: las otras solo lo mencionan); **3 CHECK** (no 6); 19 filas de equipo; 3 236 apariciones en 218 archivos del CRM (228 son literales, 3 008 son identificadores y textos). **El portal desplegable tiene 0 apariciones.**

**Lo que rompería, por gravedad:**

| Nivel | Qué se rompe |
|---|---|
| **P0** | Si se migran las 19 filas primero, `crm.mi_acceso_fn` no reconoce el rol y devuelve **«revocado»**: el CRM deja de dejar entrar a todo el mundo. |
| **P0** | `vendedor_ids_visibles` cae a su rama vacía y `roster_metas_vendedores` devuelve nada: **leads, ranking y metas en blanco**. |
| **P0** | La edge de conversión rechaza al rol nuevo con **403**, y `ciclo-contratos` deja de enviar avisos a esos analistas. |
| **P0** | **Colisión de significados:** `perfiles.rol='analista'` habilita el portal; el nuevo `rol_crm='analista'` significaría fuerza de ventas. Además hay 2 vendedores del CRM cuyo rol de portal es `comercial`. |
| **P1** | Renombrar columnas, tablas o funciones **cambia las direcciones de la API**: los navegadores con la versión vieja reciben errores. |
| **P1** | La edge de usuarios llama por nombre a `registrar_vendedor_usuario_fn`, y la hoja de leads manda la clave `vendedor_correo`. |
| **P2** | Los tres gates de pruebas usan el literal: quedarían verdes probando el mundo viejo. |
| **P3** | Los 17 índices solo tienen el término en el nombre: renombrarlos no cambia nada. |

**Recomendación de Codex:** cambiar **solo lo que se lee** a «Analista» y conservar `vendedor` como contrato interno estable. Es la única variante sin indisponibilidad y sin compatibilidad eterna.

**Si el renombre interno se mantiene** (decisión de Miguel), el único orden seguro es: aditivo en la base (aceptar ambos valores) → edges que aceptan ambos → CRM que lee ambos → recién ahí migrar las 19 filas → y la limpieza final **solo** con un gate de versión que fuerce recarga y telemetría que pruebe que no queda nadie en la versión vieja.

---

## 7. El plan por fases

### FASE 0 · Decidir — **HOY o este fin de semana**, no se toca nada
Responder las **7 preguntas** de §8 —4 de capital y 3 estructurales— y aprobar el plan.

**Por qué hoy y no «esta semana»:** hoy es viernes 28 y la Fase 1 tiene que estar en producción el 5 de septiembre. Si esto se corre, la Fase 1 entra al cierre a medio hacer.
**Por qué las de capital también van aquí:** decidir no compite con ejecutar. Se pueden contestar mientras corren las fases 1 a 3; si llegan recién cuando arranca la Fase 4, la Fase 4 arranca frenada.
**Al terminar:** ninguna fase se detiene a mitad de camino esperando una respuesta.
**De ti:** una conversación.

---

### FASE 1 · Proteger lo que ya tienes — *antes del 5 de septiembre* ⏰
- Que quede registro de quién agrega o quita un co-titular de una cuenta mancomunada. Hoy no queda ninguno, y es el dato con más peso legal del sistema.
- Que quede registro de quién borra el historial de gestión de un cliente y quién borra cuotas de pago. Hoy tampoco.
- Blindar los montos para que no pueda entrar un valor inválido al cronograma de pagos ni al cierre mensual.

- **Cerrar los permisos baratos que no tocan el portal vivo:** quitarle a los visitantes sin cuenta el acceso a 5 consultas de administración y el permiso de vaciar tablas enteras — ese último la seguridad por filas no lo gobierna. *(No filtran nada hoy: son de solo lectura y la seguridad por filas las deja en cero. Se adelantan porque cuestan cinco minutos, no porque estén sangrando.)*
- **Poner guarda a la numeración de contratos.** El generador automático calcula «el último + 1» sin candado. *(Hoy es una rama muerta: los 466 contratos usan numeración manual, cero autogenerados. Se arregla ahora porque es chico, independiente, y el día que se encienda con dos altas simultáneas da un error feo al usuario.)*

**Por qué ahora:** el primer cierre de mes real es el **10 de septiembre**. Esas tablas hoy están vacías, así que blindarlas no cuesta nada. Después del 10 sí cuesta.
**Al terminar:** ningún dato con valor probatorio se puede cambiar sin dejar rastro.
**De ti:** revisión y merge a producción. **Duración:** 2 sesiones.

---

### FASE 2 · Mirar el primer cierre de mes — *8 al 12 de septiembre*
Semana de quietud: no se publica ni una sola modificación. Se observa que el cierre del día 10 corra bien y se guarda una copia de ese mes como referencia para verificar todo lo que venga después.

**Por qué:** si algo falla el 10, quiero saber que fue el cierre y no un cambio nuestro.
**Al terminar:** el primer cierre real, ejecutado y observado.
**De ti:** revisión y merge (ninguno esa semana, por diseño). **Duración:** media sesión de vigilancia.

---

### FASE 3 · Que cada venta tenga dueño — *segunda mitad de septiembre*
- Crear el campo **«analista que cierra»** en el contrato, obligatorio al registrar.
- Cuando registra un administrativo o un supervisor, tiene que **elegir el analista**; si la venta no es de nadie, va a su nombre.
- Poder **reasignar** después, dejando rastro de quién reasignó.
- Rellenar el histórico con la regla de respaldo y **marcar los dos contratos demo** para que dejen de contar.

**Al terminar:** el ranking de agosto en adelante es exacto, y ya no depende de quién tipeó.
**De ti:** confirmar los casos dudosos del histórico + revisión y merge. **Duración:** 2 sesiones.

---

### FASE 4 · Una sola calculadora de capital — *fines de septiembre a principios de octubre*
- Construir la calculadora única, que lee **contratos y cierres en cooperativas**, cuenta por fecha de inicio y descuenta lo anulado.
- Pasar las **16 pantallas** que hoy calculan capital por su cuenta a consumirla, en tres tandas, verificando que ningún número cambie ni un céntimo.
- Al final, las dos funciones que sellan el mes también leen de ahí — **antes del 3 de octubre**, porque el cierre del 10 de octubre es su prueba.

- **El candado sale con esta fase, no después:** la prueba automática que impide que nazca una calculadora paralela se activa a medida que cada pantalla migra. Sin fecha ni dueño sería solo una intención, y es la pieza que evita volver aquí en seis meses.

**Al terminar:** gerencia, el supervisor y el analista ven siempre el mismo número, y cambiar una regla se hace en un solo lugar.
**De ti:** revisión y merge de cada tanda (las respuestas ya vinieron en la Fase 0). **Duración:** 6–7 sesiones.

---

### FASE 5 · Cerrar puertas — *mitad de septiembre, después del cierre*
*(Lo barato y sin riesgo ya salió en la Fase 1. Aquí queda solo lo que toca el portal vivo y por eso no puede compartir semana con el estreno del cierre.)*
- Recortar los permisos que sí usan las pantallas del portal, dejando exactamente lo que necesitan. Va con una prueba completa del portal con cuenta real el mismo día, y con la marcha atrás escrita antes de publicar.
- Unificar las políticas de seguridad que repiten el chequeo de rol a mano en vez de usar la regla central.
- Limitar quién puede borrar un perfil, y poner el aviso en «eliminar cliente» antes de borrar.
- Arreglar el alta de usuarios con pasaporte corto, que hoy falla.

**Al terminar:** no queda ninguna puerta abierta que nadie esté usando.
**De ti:** revisión y merge. **Duración:** 2 sesiones.

---

### FASE 6 · Las otras dos calculadoras — *octubre*
Lo mismo que la fase 4, para el conteo de leads (21 lugares) y de citas (6 lugares). Y un solo criterio de «producto seleccionable», que hoy está escrito tres veces: si alguien lo ajusta en una sola copia, CRM y portal ofrecerían catálogos distintos sin que nadie se entere.

**Al terminar:** las cuatro cifras del negocio tienen una sola fuente.
**De ti:** revisión y merge. **Duración:** 7–8 sesiones.

---

### FASE 7 · Ordenar la casa — *noviembre*
Índices que faltan y los que sobran, campos obligatorios donde el dato ya está siempre, listas de valores con un solo punto de verdad, corrección de 3 documentos que hoy quedan fuera de todo cruce, y retiro de lo que nadie usa (el catálogo de productos dormido incluido), siempre apagando primero y borrando después.

**Al terminar:** el servidor no arrastra piezas muertas ni reglas duplicadas.
**De ti:** una sesión corta para los 3 documentos y el visto bueno de cada retiro. **Duración:** 5–6 sesiones.

---

### FASE 8 · Un solo idioma — *cuando lo demás esté estable*
«Analista» en todo el sistema. Va al final a propósito: hacerlo a mitad de una verificación de cifras haría imposible saber qué cambió un número. El alcance depende de tu respuesta a la pregunta 5 de §8.

⚠️ **Dos auditorías independientes recomiendan recortarla a la capa de presentación** (Codex y el auditor de Miguel, por separado): renombrar por dentro tiene radio de explosión alto —4 roturas de nivel P0, §6— y valor de negocio cero, porque nadie ve esos nombres. Sin recorte y sin fecha, esta fase queda abierta para siempre.

**Al terminar:** el mismo concepto se llama igual en todas partes, y no vuelve a pasar lo que pasó en esta sesión.
**De ti:** la decisión de alcance. **Duración:** depende del alcance.

---

## ⚠️ Lo que este plan NO promete

**El cierre del 10 de octubre todavía va a correr sobre las calculadoras viejas.** Con la Fase 4 terminando a inicios de octubre y la Fase 6 corriendo durante octubre, el segundo cierre real ocurre antes de que todas las cifras tengan una sola fuente. Es una decisión defendible —el orden alternativo sería más arriesgado— pero conviene decirla en voz alta para que nadie se sorprenda si los números de octubre todavía no cuadran entre pantallas.

**Ninguna fase dice «De ti: nada».** Todas piden tu revisión y tu merge a producción; el plan no toca producción sin eso. Planificar cero tiempo tuyo es la forma más rápida de terminar con tres días encima.

---

## 8. Preguntas abiertas — TODAS se responden en la Fase 0

**Del capital** *(estaban mal ubicadas como insumo de la Fase 4; se adelantan porque decidir no compite con ejecutar):*

1. **El filtro de roster mensual.** Hoy el sistema deja fuera del mes a quien no estaba en la foto del equipo cuando se cerró: son 8 contratos de agosto. ¿El núcleo nuevo conserva esa regla, o cuenta la venta aunque el analista ya no esté en la foto?
2. **El pipeline estimado.** ¿Convive con el capital real en la misma cifra, o son dos métricas separadas que nunca se suman?
3. **El AUM** (el total administrado): ¿entra al núcleo de capital o vive aparte?
4. **Los 12 contratos históricos** de mayo a julio registrados por gerencia: ¿se revisan uno por uno con el equipo, o se declaran atribución aproximada y se sigue?

**Estructurales:**

5. **El alcance final del renombre** a «analista», a la luz de las 4 roturas graves que encontró Codex (§6). Dos auditorías independientes recomiendan limitarlo a lo que se lee.
6. **`tipo_documento`** repetido en 3 tablas: ¿se unifica o se declara tolerable?
7. **La relación que borra en cascada la membresía del equipo** al borrar un perfil: ¿se cambia para que impida el borrado? *(Hoy contradice la regla del proyecto de que a un colaborador se le da de baja, no se le borra.)*

---

## 9. Tablero (lo que mide que esto terminó)

| Contador | Hoy | Meta |
|---|---|---|
| Capital calculado fuera del núcleo | 16 + indirectos | 0 |
| Leads contados fuera del núcleo | 21 | 0 |
| Citas contadas fuera del núcleo | 6 | 0 |
| Contratos sin analista que cierra | 466 | 0 |
| Contratos demo contando en métricas | 2 | 0 |
| Tablas sin rastro ni declaración | 8 | 0 |
| Puertas de borrado sin auditoría | 4 | 0 |
| Montos sin protección | 11+ | 0 |
| Permisos de fábrica sin recortar | 10 tablas | 0 |
| Políticas que repiten el rol a mano | 3 + 13 | 0 |
| Versiones vivas de la misma métrica | 3 | 1 |
| Cierres de mes sanos | 0 | 2 |
| Fichas de la capa semántica | 1 | 6 |

---

## 10. Definición de terminado

1. Cada cifra tiene una sola calculadora, y una prueba automática impide que nazca otra.
2. Cada contrato sabe qué analista lo cerró, y ese dato no se mueve solo.
3. Dos cierres de mes reales ejecutados sanos.
4. Ningún hallazgo de la auditoría sin destino: arreglado, retirado, o declarado a propósito y firmado.
5. Un solo idioma en todo el sistema.

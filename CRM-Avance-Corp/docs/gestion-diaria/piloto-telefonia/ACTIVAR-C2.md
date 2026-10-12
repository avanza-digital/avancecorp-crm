# Activar un celular nuevo (C2, C3…) — guía paso a paso (10/10/2026)

Para Jhosep (con el celular en la mano) y alguien con **cuenta de gerencia** en la PC. Unos **20 minutos por celular**,
en una pausa del analista: el único cambio para él es que **al colgar se le abre la encuesta**. Sale de `ACTIVAR-C1.md`
(el alta de C1 del 07/10) y de `macrodroid.md` §3c (la macro final, con el arreglo de la llamada en espera del 09/10).
Lo que C1 enseñó ya viene incorporado: no hay que repetir sus hallazgos.

Regla de siempre: **sin números de teléfono ni claves** en capturas, chats con Claude ni documentos.

## 0. Antes de empezar

- [x] **Aviso de tratamiento: resuelto** (Miguel, 12/10: Legal aprobó el asunto e hizo el trámite; no hace falta
  incorporarlo al sistema ni una pantalla). `AVISO-TRATAMIENTO.md` queda como borrador de referencia. No bloquea la
  activación.
- [ ] La **cuenta del CRM del analista** que va a usar el celular (vendedor o supervisor activo). La llamada solo se une
  si el celular es de quien registra.
- [ ] **MacroDroid encendido** todo el tiempo. Dos opciones, a decidir antes (Pro corporativo hasta S/ 57 está
  autorizado por Miguel): **Pro** (S/ 19, pago único, con cuenta corporativa) o **gratis**, que exige mirar un anuncio
  **cada 3 días** o la app se apaga sola sin avisar (`SOPORTE.md` §5). Con gratis, el analista tiene que hacerlo él.
- [ ] Un **lead de prueba propio del analista** en su cartera, con un número del equipo y su permiso (como «prueba
  leeds» en C1). Ojo: si ese número está en un lead abierto de **otro** analista, en un cliente activo o en «No
  contactar», el servidor no guarda la llamada para nadie (`SOPORTE.md` §2.2b). Los leads de prueba de C1 no sirven
  para C2.
- [ ] El celular cargado, con Wi-Fi o datos, y **una sola SIM** (el piloto no cubre doble SIM).

## 1. Gerencia, en la PC (2 min)

1. CRM → **Configuración** → tarjeta **«Celulares»** → **Abrir** → **«Asignar celular»**.
2. Etiqueta: **C2** (o C3). Analista: la cuenta del paso 0.
3. **«Asignar y ver la clave»** → **«Copiar»** → mandarla al celular por WhatsApp. La clave se ve **una sola vez**.
   A Claude no se le pasa.
4. **No cerrar la ventana** hasta pegar la clave en el celular (parte 3). Al final, **«Ya la copié al celular»**.
   La fila dirá «Nunca habló»: es lo normal hasta el primer latido.

## 2. Ajustes de Android (5 min)

1. **MacroDroid** desde Play Store (sin «Helper App» ni «ADB hack»). Anotar la versión.
2. **Permisos** de MacroDroid: **Teléfono** y **Registro de llamadas** en «Permitir». Sin el segundo, en C1 no se abrió
   la encuesta, la llamada no llegó a «Pendientes» y la tarjeta siguió «Al día», aunque el celular mandó igual una
   petición (202) (hallazgo H-PERMISO, 09/10). Hipótesis, no comprobada: sin ese permiso el número llega vacío.
3. **«Aparecer encima»** (mostrar sobre otras apps) activado.
4. **Batería** de MacroDroid: «No restringido». En Samsung, además: Ajustes → Batería → «Límites de uso en segundo
   plano» → **«Suspender aplicaciones sin uso» apagado**, y MacroDroid fuera de «suspendidas» y de «suspensión
   profunda». En otras marcas: «autoarranque» o «apps que nunca duermen».
5. **Chrome** como navegador predeterminado.
6. **CRM instalado como app** desde Chrome en `https://crm.miavance.com`, con la cuenta del analista (**PWA**: la app
   que se instala desde el navegador).
7. Ajustes → Aplicaciones → **CRM Avance Corp** → «Definir como predeterminada» → **«Abrir vínculos admitidos» ✓** →
   «Direcciones web admitidas» → **crm.miavance.com ✓**. Los dos interruptores encendidos; sin esto la encuesta se abre
   en Chrome y no en la app.
8. **Fecha y hora automáticas** ✓ (Samsung: Ajustes → Administración general → Fecha y hora).
9. **«Llamada en espera»** se deja como esté (en C1, activada): la macro ya la resuelve.

## 3. MacroDroid (≈10 min importando; ≈30 a mano)

Dos caminos. **El A ya está probado en C1 (12/10): úsalo.** El B queda por si falla la importación.

### A. Importar las macros de C1 (comprobado el 12/10)

Lo que se aprendió al exportar desde C1 (`REGISTRO.md` §5k):
- Cada macro se exporta **una por una** (mantener presionada → compartir/exportar) a un archivo **`.macro`** (JSON
  con `globalVariables`, `macro` y `macroExportVersion`). No usar la exportación del mosaico (`.mdr`, lleva todo).
- El archivo **lleva las variables globales que usa la macro con su valor**: por eso C1 se vació antes. `url_llamadas`
  llega puesta (sirve tal cual); `ultimo_latido`, `ultimo_aviso_401` y `t_saliente` llegan con el valor de C1 y hay
  que ponerlos en 0; `cola_llamadas` y `errores_llamadas` salieron vacías. Entre los tres archivos están las nueve.
- El formato trae `isSecure` por variable: la 5.67 tiene «variable segura» (no se probó en pantalla).
- Importar abriendo el archivo, y qué pasa con una cola con entradas: **sin comprobar** (se comprueba en C2).

**Los archivos ya existen** (12/10): tres `.macro` limpios —sin clave, sin números— en la PC de Jhosep (carpeta
`MACROS-C1-C2-C3`, fuera del repo), revisados con un script que solo cuenta y nunca muestra valores. **No hace falta
volver a exportar desde C1** mientras su macro no cambie. Si cambia, repetir lo del 12/10: C1 con cola 0 y colas sin
entradas, vaciar `numero_saliente` y `clave_celular`, no llamar, exportar las tres, revisar los archivos en la PC (sin
pasárselos a Claude si no es por un script que no muestre valores), y reponer la clave (la misma o una rotada) con
`ultimo_latido` = 0.

1. Pasar los tres archivos al celular nuevo (WhatsApp o cable). **En el celular nuevo**: abrir cada archivo con
   MacroDroid (o MacroDroid → menú → Exportar/Importar → **Importar**). Una macro importada llega **apagada**: no
   encenderla todavía. Anotar cómo se importó, para la guía.
2. Revisar en «Variables globales» que existan las nueve variables de la tabla de abajo (la importación crea las que
   faltan) y dejar sus valores iniciales: `ultimo_latido`, `ultimo_aviso_401` y `t_saliente` **en 0**; colas sin
   entradas; `en_saliente` Falso; `numero_saliente` y `clave_celular` vacías hasta el paso de la clave.
3. En **«Llamadas-Al colgar»** cambiar la etiqueta: la acción `id_llamada = C1-{system_time}` pasa a
   **`C2-{system_time}`** (C3 en C3). Con la etiqueta equivocada, el servidor rechaza el aviso (400).
4. Comprobar de paso en «Al colgar» que «Abrir Sitio web» llegó con la URL del CRM y con «Parámetros de codificación
   de URL» y «HTTP GET (sin navegador)» desmarcados.

### B. Armar las tres macros a mano

Seguir **`macrodroid.md` §3c**, Pasos 1 a 4, tal cual, con estas tres diferencias para un celular nuevo:
- No existe «Piloto F0»: la acción **«Abrir Sitio web»** de «Al colgar» se crea desde cero, con **«Parámetros de
  codificación de URL»** y **«HTTP GET (sin navegador)»** desmarcados. No crear «Piloto F0» (muestra el número).
- La etiqueta es **C2** (o C3) en `id_llamada`.
- El aviso y el latido se **pegan**, no se teclean (el teclado cambia las comillas y da 400).

### Variables globales (para A y B)

| Variable | Tipo | Valor en el celular nuevo |
| --- | --- | --- |
| `cola_llamadas` | Diccionario | sin entradas |
| `errores_llamadas` | Diccionario | sin entradas |
| `en_saliente` | Booleana | Falso |
| `t_saliente` | Entera | 0 |
| `numero_saliente` | Cadena | vacía (arreglo de la llamada en espera, 09/10: obligatoria) |
| `ultimo_latido` | Entera | 0 |
| `ultimo_aviso_401` | Entera | 0 |
| `url_llamadas` | Cadena | `https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta` |
| `clave_celular` | Cadena | la clave de la tarjeta (parte 1) |

### El orden importa

1. Pegar la **clave** en `clave_celular` y comprobar `url_llamadas` sin espacios.
2. `ultimo_latido` = 0 y las dos colas sin entradas (si hay algo: «Eliminar clave» en cada entrada, no «Borrar valor»).
3. **Recién ahora encender** las tres macros. Si se encienden antes de pegar la clave, «Enviar cola» manda con la clave
   vacía (401) y las llamadas hechas mientras tanto quedan en la cola y salen después.
4. Borrar el WhatsApp con la clave. En la PC, **«Ya la copié al celular»**.

## 4. Comprobar que vive (5 min)

1. En la PC, Configuración › Celulares, fila de C2: **«Al día»**, macro **`llamadas-v3`**, en cola **0**. Si a los
   10 minutos sigue «Nunca habló»: `ACTIVAR-C1.md` §4 (MacroDroid encendido, internet, URL exacta, clave bien pegada).
2. **Llamada de control:** desde el celular, llamar al lead de prueba y colgar. Tiene que abrirse la encuesta en la app
   con «Llamada del celular de las HH:MM»; al guardar, «Quedó unido…» (o «Quedará unido…» si se guardó muy rápido) y la
   llamada aparece en «Celular» → «Qué pasó hoy». El latido **no** prueba la captura: la llamada sí.
3. Si la encuesta se abre en Chrome y no en la app: repasar el paso 2.7.

## 5. Qué anotar

- `REGISTRO.md` §1: marca y modelo, Android, navegador, versión de MacroDroid, ajustes de batería, fecha de alta.
- `REGISTRO.md` §2 y §3: analista, aviso entregado y firmado, PWA instalada, permisos.
- `compatibilidad.md`: la fila del celular (PASS / FAIL / NOT RUN por columna).
- Si se usó el camino A (importar): anotar si funcionó, para los siguientes celulares.
- Desde ese día cuenta para la aceptación de F0: **diez salientes por equipo** con sus casos.

## 6. Si algo sale mal

- **No se abre la encuesta:** MacroDroid apagado (días gratis), permiso «Registro de llamadas» quitado, o «Abrir
  vínculos admitidos» sin marcar. `SOPORTE.md` §2.
- **«La clave de este celular ya no vale»:** se pegó mal; volver a pegarla, o gerencia la rota (`SOPORTE.md` §3.2).
  Al rotar: pegar la nueva **y** `ultimo_latido` = 0.
- **Aviso rechazado (400):** casi siempre la etiqueta (`C1-` en C2) o las comillas del aviso.
- Para volver atrás del todo: gerencia **cierra** el celular en la tarjeta, y como eso no apaga el celular, se hacen
  también los pasos en el celular de `SOPORTE.md` §3.5. Nunca se borran datos del CRM.

## En llano

Dar de alta un celular nuevo es: gerencia lo asigna y copia una clave; en el celular se instala MacroDroid, se le dan
los permisos y se instala el CRM como app con la cuenta del analista; se importan los tres archivos que ya salieron de
C1 el 12/10 (o se arman a mano) cambiando la etiqueta a C2; se pega la clave y, recién entonces, se encienden las
macros. Una llamada de control confirma que todo funciona. El aviso de tratamiento ya lo resolvió Legal (12/10).

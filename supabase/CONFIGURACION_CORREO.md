# Configuración del panel de Supabase para el cambio de contraseña por código

Este documento explica **qué hay que cambiar en el panel de Supabase**
(`https://supabase.com/dashboard/project/kbbbwdoommxsczjliqlu`) para que el
cambio de contraseña con código funcione, y qué **no** se puede hacer desde
la aplicación.

> **Importante:** guardar el HTML en `supabase/templates/reset_password.html`
> **no** actualiza nada en Supabase. El archivo es una copia local de la
> plantilla: hay que pegarla a mano en el panel (ver más abajo).

---

## 1. Plantilla de correo "Reset Password"

| Qué | Dónde | Valor |
|---|---|---|
| Archivo local | `supabase/templates/reset_password.html` | Plantilla completa, estilo Mercamigo (azul y blanco) |
| Dónde pegarla | Supabase → **Authentication → Email Templates → Reset Password** | El contenido de `{{ .Token }}` y el resto del HTML |
| Asunto | Supabase → Authentication → Email Templates → Reset Password → **Subject** | `Tu código para cambiar la contraseña de Mercamigo` |
| Variable obligatoria | dentro del HTML | `{{ .Token }}` (el código de 8 dígitos) |

La plantilla **no** debe llevar `{{ .ConfirmationURL }}`: este flujo es por
código, no por enlace. Si se deja el enlace, el correo contendría un
enlace que abriría la app con una sesión de recuperación y saltaría la
verificación del código.

### Cómo pegar la plantilla

1. Abre `supabase/templates/reset_password.html` y copia **todo** el
   contenido.
2. En el panel: **Authentication → Email Templates → Reset Password**.
3. Borra el cuerpo actual y pega el contenido del archivo.
4. Pon el asunto: `Tu código para cambiar la contraseña de Mercamigo`.
5. Guarda.

> No se modifica **Magic Link** ni **Confirm Signup**.

---

## 2. Longitud del código (Email OTP Length = 6)

| Qué | Dónde | Valor |
|---|---|---|
| Longitud del código | Supabase → **Authentication → Sign In / Providers → Email** → **Email OTP Length** | `8` |

La aplicación usa 8 dígitos de forma fija
(`AppConfig.recoveryOtpLength`). Si el panel tuviera otra
longitud, el código no se podría escribir completo y la verificación
fallaría.

El campo **Email OTP Length** controla la longitud de los códigos que envía
Supabase en los flujos de OTP por correo.

---

## 3. Caducidad y reenvío

| Concepto | De dónde sale | Valor |
|---|---|---|
| Caducidad del código | La fija el servidor (Supabase Auth) | **No se puede cambiar desde la app.** Por defecto, los códigos de recuperación caducan en **1 hora** |
| Reenvío | La app lo pide con `resetPasswordForEmail` | La app espera **60 s** entre envíos (es una espera visual, no el límite real) |
| Límite real de envíos | El servidor | Lo aplica Supabase: si se supera, la API responde **HTTP 429** y la app muestra el error de "demasiados códigos" |

- El **contador de 60 s** de la app es solo visual: el límite que manda es
  el del servidor.
- Si el servidor responde **429**, la app no dice "código enviado": muestra
  el error.

---

## 4. Límites del servicio de correo y SMTP actual

El proyecto usa el **servicio de correo integrado de Supabase** (no hay SMTP
propio configurado en este repositorio).

| Limitación | Detalle |
|---|---|
| Cuota | El plan de Supabase impone un límite de correos por hora. Con el SMTP integrado, el envío a un mismo destinatario se limita a unas **2–3 copias por hora** (después, el correo puede retrasarse o no enviarse) |
| Antigüedad del dominio | Los correos del SMTP integrado de Supabase se escriben desde `noreply@supabase.io` y pueden caer en spam |
| Plantillas | Las plantillas del panel **reemplazan** el correo; no se puede añadir HTML desde la app |
| Entrega a Gmail | Con el SMTP integrado, los correos a cuentas de Gmail pueden tardar o filtrarse |

**Recomendación**: para un uso real, configurar un **SMTP propio**
(Supabase → Authentication → SMTP) y usar plantillas con el remitente de la
tienda. Mientras tanto, el flujo funciona, pero el correo puede tardar.

---

## 5. Lo que la aplicación **no** hace (y por qué)

| No se hace | Motivo |
|---|---|
| Generar el código en Flutter | El código lo genera y valida el servidor (`verifyOTP`) |
| Crear tablas de códigos | El código no se guarda en ninguna tabla: Supabase Auth lo gestiona |
| Usar `signInWithOtp` | Ese mecanismo inicia sesión con un código; aquí se usa el de **recuperación** (`resetPasswordForEmail` + `verifyOTP` con tipo `recovery`) |
| Usar `OtpType.email` para verificar | `OtpType.email` es para códigos de inicio de sesión, no de recuperación |
| Usar `service_role` o funciones administrativas | La app solo usa la clave publicable |
| Enviar correos desde los tests | Los tests son simulados: no se envían correos ni se cambian contraseñas reales |

### Nota sobre la diferencia entre la app y el panel

La app **oculta** el formulario de "cambiar contraseña" detrás de la
verificación del código. Eso **no** significa que el servidor la exija: el
servidor aceptaría un `updateUser` con cualquier sesión válida. La
verificación por código es una decisión de **diseño de la app** (y una
protección real, porque el servidor solo la exige si la sesión es de
recuperación).

---

## 6. Comprobación de que el flujo está bien configurado

1. Entra en la app con una cuenta de prueba.
2. **Mi cuenta → Cambiar contraseña**.
3. Debe llegar un correo con un código de 8 dígitos.
4. Escribe el código → **Verificar código** → **Guardar contraseña**.
5. La contraseña antigua deja de servir y la nueva permite entrar.

Si el correo llega con un **enlace** en vez de un código, es que la
plantilla del panel todavía tiene `{{ .ConfirmationURL }}`: hay que
sustituirla por el archivo de `supabase/templates/reset_password.html`.

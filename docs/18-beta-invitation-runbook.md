# Invitaciones y alta controlada durante la beta

**Estado:** Procedimiento manual vigente; automatización pendiente

**Versión:** 0.1

**Fecha:** 2026-08-14

## 1. Objetivo

Definir cómo incorporar, bloquear y retirar usuarios durante la beta privada sin
habilitar registro público ni exponer la administración de Keycloak. También
deja explícito qué partes de una invitación automatizada todavía no existen.

## 2. Estado funcional actual

La opción **Crear cuenta** del cliente sólo explica que el acceso está
restringido. No crea una cuenta, no solicita un correo y no envía una invitación.

La cuenta `musicflow-beta` es un usuario técnico controlado para validar OIDC,
PKCE, restauración y cierre de sesión. No representa un sistema general de
invitaciones. Su secreto local no debe reutilizarse para otros usuarios.

Hasta implementar SMTP y el flujo automatizado, una invitación significa:

1. alta manual por un administrador en el realm `musicflow`;
2. entrega privada de usuario y contraseña temporal;
3. cambio obligatorio de contraseña en el primer acceso;
4. MFA mediante OTP cuando el administrador lo requiera;
5. revocación manual si termina la participación en la beta.

## 3. Prerrequisitos

- Docker Desktop y el perfil `identity` en estado Healthy.
- Acceso local a `http://127.0.0.1:8081/admin/master/console/`.
- Credencial administrativa disponible en
  `.secrets/keycloak-admin-password`.
- El administrador nunca se publica mediante Cloudflare Tunnel.
- Un canal privado para entregar la contraseña temporal.

## 4. Alta manual de un invitado

1. Abrir la consola administrativa local de Keycloak.
2. Autenticarse en `master` con la cuenta administrativa.
3. Cambiar al realm `musicflow` antes de crear el usuario.
4. Entrar en **Users** y seleccionar **Add user**.
5. Asignar un username único, nombre, apellido y, cuando exista, correo real.
6. Mantener **User enabled** activado.
7. Mantener **Email verified** desactivado mientras no exista verificación por
   SMTP. No se debe afirmar una verificación que no ocurrió.
8. Guardar la cuenta sin roles administrativos.
9. En **Credentials**, establecer una contraseña inicial aleatoria y marcarla
   como **Temporary**.
10. Añadir **Configure OTP** como acción requerida cuando el riesgo o el alcance
    de la prueba exijan MFA.
11. Entregar username y contraseña temporal por un canal privado. No deben
    aparecer juntos en documentación, capturas, commits o tickets.
12. El invitado abre MusicFlow, pulsa **Continuar con MusicFlow** y completa en
    el navegador el cambio de contraseña y, si corresponde, OTP.
13. Confirmar que Keycloak retorna al callback local y que la aplicación muestra
    la identidad esperada.

No se utilizará `configure-identity-beta-user.ps1` para crear varios invitados:
ese script y `.secrets/keycloak-beta-user-password` pertenecen únicamente a la
cuenta conocida `musicflow-beta`.

## 5. Revocación, bloqueo y recuperación manual

- **Suspensión temporal:** desactivar **User enabled** y cerrar sus sesiones.
- **Retiro definitivo:** cerrar sesiones, eliminar la cuenta sólo después de
  confirmar que no existen recursos que deban conservar trazabilidad.
- **Contraseña comprometida:** restablecer una contraseña temporal y cerrar las
  sesiones existentes.
- **OTP comprometido:** eliminar la credencial OTP afectada y requerir
  **Configure OTP** nuevamente.
- **Intentos fallidos:** revisar eventos y protección contra fuerza bruta antes
  de desbloquear; no desactivar globalmente el control antiabuso.

## 6. Limitaciones aceptadas

Durante este estado provisional no existen:

- correo de invitación;
- enlace de un solo uso;
- verificación automática de correo;
- recuperación de contraseña por correo;
- vencimiento automático de invitaciones;
- panel de administración propio de MusicFlow;
- auditoría de invitaciones en la base de datos de la aplicación.

Por ello, el procedimiento manual sólo es aceptable para una beta pequeña y
controlada. No es adecuado para registro público ni despliegue masivo.

## 7. Flujo automatizado pendiente

El incremento futuro deberá implementar este contrato:

1. un administrador autorizado registra el correo del invitado;
2. la API crea una invitación de un solo uso, con token hasheado, vencimiento,
   estado y auditoría;
3. Keycloak crea o prepara la identidad sin otorgar privilegios;
4. SMTP envía un enlace HTTPS al correo registrado;
5. el invitado verifica correo, define contraseña y configura MFA;
6. la invitación se consume de forma atómica y no puede reutilizarse;
7. el usuario accede desde Tauri mediante Authorization Code + PKCE;
8. revocación, reenvío y expiración quedan registrados.

La API no almacenará contraseñas ni enviará secretos administrativos al cliente.
Keycloak seguirá siendo responsable de autenticación y credenciales.

## 8. Criterios para habilitar invitaciones automáticas

- SMTP configurado con secretos fuera del repositorio.
- Verificación de correo y recuperación probadas.
- Token de invitación aleatorio, hasheado, de un solo uso y con expiración.
- Autorización administrativa y rate limiting del endpoint de invitaciones.
- Pruebas de reutilización, expiración, revocación y concurrencia.
- Logs de auditoría sin tokens, contraseñas ni información sensible.
- Términos, privacidad y canal de soporte definidos para la beta externa.

Este pendiente no bloquea la validación JWT de la API con la cuenta controlada,
pero debe cerrarse antes de ampliar la beta a usuarios externos no administrados
manualmente.

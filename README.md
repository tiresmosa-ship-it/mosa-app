# MOSA Neumáticos

Aplicación web (PWA) para la gestión de neumáticos de flotas de camiones,
usada por MOSA para reemplazar los formularios en papel que llenan los
mecánicos en terreno.

- **Stack:** React (CDN, sin build step) + Tailwind CSS (CDN) + Supabase
- **Archivo desplegable:** un solo `index.html` + `sw.js` + `manifest.json`

## Archivos

- `index.html` — app completa (login, 4 formularios de campo, panel admin)
- `sw.js` — service worker (cache del app shell, offline)
- `manifest.json` — manifest PWA
- `icon-192.png` / `icon-512.png` — íconos de la app
- `migrations.sql` — script para preparar la base de datos en Supabase

## 1. Preparar la base de datos (una sola vez)

1. Entrá a tu proyecto en [Supabase](https://supabase.com) → **SQL Editor**.
2. Pegá y ejecutá el contenido de [`migrations.sql`](migrations.sql). Esto:
   - Agrega las columnas `usuario` y `password_hash` a `mecanicos` (si no existen).
   - Crea la tabla `config_cliente` (si no existe).
   - Inserta valores por defecto de configuración para el cliente `la_portada`
     (correlativos en 1, `psi_minimo=85`, `mm_minimo=4`).
3. Verificá que **RLS (Row Level Security)** permita lectura/escritura desde
   la clave pública (`anon`) en todas las tablas usadas por la app, ya que el
   login de mecánicos es propio (no usa Supabase Auth). El script incluye
   ejemplos de políticas permisivas al final, comentadas.
4. Cargá al menos un mecánico con `usuario` y una contraseña (la contraseña
   se hashea en el frontend con SHA-256 antes de guardarse — podés crear
   mecánicos desde el panel admin de la app una vez desplegada, no hace
   falta hacerlo a mano en SQL).
5. Ajustá en **Configuración** (dentro de la app, como admin) el número de
   arranque real de cada correlativo (`numero_auditoria_inicio`,
   `numero_cambio_inicio`, `numero_flash_inicio`, `numero_hoja_inicio`) según
   lo que indique Nelson.

## 2. Desplegar en Hostinger

1. Entrá al **Administrador de archivos** de tu hosting en Hostinger (o vía
   FTP/SFTP).
2. Subí estos 5 archivos a la carpeta pública del sitio (normalmente
   `public_html/` o la subcarpeta donde quieras servir la app):
   - `index.html`
   - `sw.js`
   - `manifest.json`
   - `icon-192.png`
   - `icon-512.png`
3. Asegurate de que el sitio se sirva por **HTTPS** (necesario para que
   funcione el Service Worker / PWA). Hostinger habilita SSL gratis con
   Let's Encrypt desde el panel.
4. Entrá a la URL del sitio desde el celular o tablet del mecánico y usá
   "Agregar a pantalla de inicio" (Android/Chrome) o "Añadir a pantalla de
   inicio" (iOS/Safari) para instalar la PWA.
5. No hace falta ningún build ni `npm install`: los archivos se sirven tal
   cual, React/Tailwind/Supabase se cargan desde CDN.

## 3. Credenciales de acceso

- **Administrador:** usuario `admin`, contraseña `mosadmin2026` (fijas en el
  código — para cambiarlas hay que editar `ADMIN_USER`/`ADMIN_PASS` en
  `index.html` y volver a subir el archivo).
- **Mecánicos:** cada uno tiene su propio usuario/contraseña, gestionados
  desde el panel admin → **Mecánicos**.

## 4. Funcionamiento offline

- Si el mecánico pierde conexión, el header muestra el badge **"Sin
  conexión"** y los formularios se guardan en `localStorage`.
- Al recuperar conexión, la cola pendiente se sincroniza automáticamente en
  orden (FIFO). También podés forzar el reintento con el botón que aparece
  en la barra de "registros pendientes".
- Los maestros (equipos, mecánicos, configuración) se cachean localmente la
  primera vez que se cargan online, para que los selectores sigan
  funcionando sin conexión.

## 5. Notas de diseño / decisiones tomadas

- El **número de fuego automático para La Portada** se genera como
  `numero_interno + semana_ISO(2) + año(2) + posición`, replicando el
  ejemplo dado (308 / semana 26 / año 26 / posición 1 → `30826261`). El
  mecánico siempre puede editar la sugerencia (por ejemplo si el neumático
  viene trasladado de otro equipo).
- Los **correlativos** (auditoría, cambio, flash, hoja) se leen/incrementan
  en `config_cliente`. Mientras el dispositivo está offline, se compensan
  sumando la cantidad de formularios del mismo tipo que ya están en la cola
  local, para no repetir números antes de sincronizar.
- En **Cambio de Neumáticos**, si un N° de fuego que "entra" no existe en la
  tabla `neumaticos`, se crea automáticamente; si ya existe, se actualiza su
  estado y equipo/posición actual. Los que "salen" quedan sin equipo
  asignado (`equipo_actual = null`) y su estado pasa a `transito` o `baja`
  según el motivo indicado.
- Nada se elimina físicamente: equipos, mecánicos y neumáticos solo se
  activan/desactivan con un toggle.

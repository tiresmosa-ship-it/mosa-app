# .well-known/

Esta carpeta se publica en `https://DOMINIO_PENDIENTE/.well-known/`.

Aca va **`assetlinks.json`** (Digital Asset Links), que Android usa para verificar
que la app de Google Play (Trusted Web Activity) es dueña del dominio. Sin ese
archivo, la app abre con la barra de direcciones de Chrome visible.

**El archivo real NO esta creado todavia.** Se crea despues de generar el paquete
Android con PWABuilder, porque necesita datos que aun no existen:

- `package_name`: el ID de la app (ej. `cl.dominio.mosa`), que se define en PWABuilder.
- `sha256_cert_fingerprints`: la huella SHA-256 del keystore de firma (o, si se usa
  Play App Signing, la huella de Google Play Console > Integridad de la app).

Formato esperado:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "PACKAGE_NAME_PENDIENTE",
    "sha256_cert_fingerprints": ["SHA256_PENDIENTE"]
  }
}]
```

Requisitos de publicacion:

- Debe quedar accesible en `https://DOMINIO_PENDIENTE/.well-known/assetlinks.json`.
- Respuesta `200`, `Content-Type: application/json`, sin redirecciones (el `.htaccess`
  de la raiz ya lo configura).
- Al subir por FTP/Administrador de archivos de Hostinger, verificar que la carpeta
  `.well-known` (empieza con punto) quede dentro de `public_html`.

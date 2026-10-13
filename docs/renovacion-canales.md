# Renovación de ABC, GEN, Trece, Unicanal y Oasis

## Problema y funcionamiento

La grilla contenía direcciones firmadas de reproducciones anteriores. Algunas
dejan de funcionar al vencer la sesión o cuando cambia la IP del espectador.
GEN incluso devolvía un video azul de «Sesión expirada» con respuesta HTTP 200.
Por eso recibir un manifiesto HTTP 200 no demuestra que el canal funcione.

La app mantiene `playerType: hls` y reproduce con `video_player`. Para estos
cinco canales, `webUrl` identifica la página pública del proveedor. El nuevo
`StreamResolver` consulta esa página **desde el dispositivo que va a reproducir**,
descubre el reproductor vigente y obtiene la dirección HLS para esa selección.
No conserva URL firmadas entre espectadores ni usa credenciales privadas.

`streamUrl` continúa siendo la dirección directa para los demás canales. Las
APK anteriores ignoran esta renovación y requieren recompilación para usarla.

## Estructura

- `lib/services/stream_resolver.dart`: páginas permitidas, descubrimiento de
  iframes y HLS, consulta de metadatos públicos y errores del proveedor.
- `lib/widgets/video_panel.dart`: inicialización limitada a 20 segundos,
  protección contra respuestas tardías de un canal anterior, renovación cada
  cinco minutos y hasta dos intentos de recuperación automática.
- `test/stream_resolver_test.dart`: renovación por selección, errores de región
  y autorización, cambios de reproductor, HLS frente a VOD/DASH y proveedor caído.
- `test/playback_renewal_test.dart`: selección durante una petición pendiente,
  renovación sin retirar el video antes de tiempo y límite de reintentos.
- `canales.json`: respaldo integrado. La grilla principal sigue siendo
  `LiderSalinas/tv-paraguay-data/main/canales.json`.

Durante una renovación se prepara el controlador nuevo antes de retirar el
anterior. Los cambios de canal y el cierre de la pantalla cancelan los timers.
Una reproducción estable durante 30 segundos restablece el límite de reintentos.

## Fuentes de resolución

| ID | Canal | Página pública |
| --- | --- | --- |
| 13 | Trece | https://www.trece.com.py/ |
| 14 | Unicanal | https://www.unicanal.com.py/ |
| 15 | GEN TV | https://www.gen.com.py/ |
| 16 | ABC Digital | https://www.abc.com.py/tv/ |
| 20 | Oasis TV | https://tvonline.com.py/oasistv/ |

No se modifica la numeración ni se usa WebView. Las restricciones geográficas
o de autorización del proveedor se conservan; si bloquea la reproducción, se
informa el error y se detienen los reintentos automáticos.

## Validación y uso

Usar Flutter 3.29.3 / Dart 3.7.2, compatible con la base del proyecto:

```powershell
python tools/prepare_branding.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Instalar una APK compilada desde la versión de código que conserva el diseño
actual. Si ese diseño tiene cambios locales, aplicar el commit con merge o
cherry-pick y revisar los conflictos; no reemplazar la interfaz completa con
la copia anterior de GitHub ni descartar cambios locales.

En Android, actualizar la grilla, abrir cada señal, comprobar imagen y sonido,
mantenerla abierta al menos seis minutos y cambiar rápidamente entre dos canales.
La comprobación de Dart y las pruebas de red no sustituyen esta prueba real.

## Estado de las fuentes en esta revisión

- GEN: la página oficial entregó una nueva dirección y una muestra de video
  H.264 de 1280×720 con audio AAC; se verificó la imagen con la marca GEN.
- ABC y Unicanal: el reproductor público entrega metadatos vigentes. Desde este
  entorno la CDN responde 403; la reproducción debe verificarse desde el Android
  en Paraguay con URL obtenida por ese mismo dispositivo.
- Trece: el proveedor devuelve `DM007` (restricción regional) a este entorno
  fuera de Paraguay. No se alteró la región ni se eludió esa restricción.
- Oasis: al comenzar la revisión la URL publicada respondía 404. En otra
  comprobación del 13 de octubre volvió a entregar imagen identificada como
  OASIS TV MISIONES, H.264 de 1280×720 y una pista AAC de dos canales. Los
  primeros tres segundos de audio decodificado estaban en silencio; falta
  comprobar audio y estabilidad en Android. Su disponibilidad es variable.

## Nuevo ícono y APK de prueba

La imagen enviada por el usuario se conserva completa, sin regenerarla ni
cambiar los colores. `branding/tv_paraguay_assets.json` contiene sus bytes
originales y los tamaños de íconos de Android, con SHA-256 por archivo.
`tools/prepare_branding.py` verifica esas huellas antes de restaurar el JPEG
del encabezado y los PNG de Android. Requiere solamente Python 3 estándar.

El ícono adaptable usa fondo negro y deja margen alrededor de la imagen para
las distintas máscaras del launcher. Los íconos antiguos se reemplazan al
preparar los recursos. Ejecutar el script antes de probar o compilar; la
compilación automática también lo ejecuta.

La rama `codex/renovacion-canales-hls` compila como **TV Paraguay Prueba**, con
paquete `com.example.tv_paraguay.prueba`. Se instala como una app separada,
útil para comprobar los canales desde la red del usuario en Paraguay.
La compilación normal conserva `com.example.tv_paraguay`. La base accesible
de GitHub contiene la interfaz anterior; integrar el parche en el proyecto
actual antes de entregar una actualización de esa app. El test APK no es
una validación de la interfaz actual ni de la reproducción real en el teléfono.

La compilación separa las arquitecturas: `app-arm64-v8a-release.apk` para
teléfonos de 64 bits y `app-armeabi-v7a-release.apk` para TV Box de 32 bits.
Para TV Box de 64 bits se utiliza la primera. Se mantienen fullscreen,
grilla remota y reproducción HLS nativa.

## Mantenimiento

Si cambia una página del proveedor, actualizar `webUrl` en la grilla remota y
verificar que el dominio esté permitido en `StreamResolver`. Para cambios en el
formato del HTML o los metadatos, añadir una prueba con una respuesta saneada y
actualizar el parser. No guardar claves privadas, contraseñas o cookies en la
grilla pública. No copiar una URL firmada de un servidor como fuente permanente.

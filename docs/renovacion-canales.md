# Renovación y mantenimiento de canales (1.2.2+6)

## Problema y funcionamiento

La grilla contenía direcciones firmadas de reproducciones anteriores. Algunas
dejan de funcionar al vencer la sesión o cuando cambia la IP del espectador.
GEN incluso devolvía un video azul de «Sesión expirada» con respuesta HTTP 200.
Por eso recibir un manifiesto HTTP 200 no demuestra que el canal funcione.

La app mantiene `playerType: hls` y reproduce con `video_player`. Para SNT, C9N,
GEN, ABC, Trece, Unicanal y Oasis, `webUrl` identifica la página pública del proveedor. El
`StreamResolver` consulta esa página **desde el dispositivo que va a reproducir**,
descubre el reproductor vigente y obtiene la dirección HLS para esa selección.
No conserva URL firmadas entre espectadores ni usa credenciales privadas.

`streamUrl` continúa siendo la dirección directa para los demás canales. Las
APK anteriores a la incorporación de cada proveedor requieren una actualización
para resolverlo desde su página. Los enlaces directos nuevos de SNT y C9N también
pueden recibirse en las versiones anteriores mediante **Actualizar canales**.

## Estructura

- `lib/services/stream_resolver.dart`: páginas permitidas, descubrimiento de
  iframes y HLS, consulta de metadatos públicos y errores del proveedor.
- `lib/widgets/video_panel.dart`: inicialización limitada a 20 segundos,
  protección contra respuestas tardías de un canal anterior, renovación cada
  cinco minutos, dos reintentos rápidos separados por tres segundos y, si la
  falla transitoria continúa, un reintento por minuto.
- `test/stream_resolver_test.dart`: renovación por selección, errores de región
  y autorización, cambios de reproductor, HLS frente a VOD/DASH y proveedor caído.
- `test/playback_renewal_test.dart`: selección durante una petición pendiente,
  renovación sin retirar el video antes de tiempo, espera entre reintentos,
  cancelación al cerrar y ausencia de reintentos ante restricciones regionales.
- `test/broadcast_resolver_test.dart`: JSON escapado de SNT/C9N, descubrimiento
  renovado, selección de rutas publicadas, respaldo ante fallas de transporte y
  rechazo de listas terminadas o respuestas de autorización.
- `canales.json`: respaldo integrado. La grilla principal sigue siendo
  `LiderSalinas/tv-paraguay-data/main/canales.json`.

Durante una renovación se prepara el controlador nuevo antes de retirar el
anterior. Si la URL y los encabezados siguen iguales y el controlador funciona,
se conserva ese controlador y se programa la siguiente revisión sin interrumpirlo.
Los cambios de canal y el cierre de la pantalla cancelan los timers.
Una reproducción estable durante 30 segundos restablece los dos reintentos rápidos.

## Fuentes de resolución

| ID | Canal | Página pública |
| --- | --- | --- |
| 3 | SNT | https://www.snt.com.py/envivo/ |
| 5 | C9N | https://www.c9n.com.py/envivo/ |
| 13 | Trece | https://www.trece.com.py/ |
| 14 | Unicanal | https://www.unicanal.com.py/ |
| 15 | GEN TV | https://gentv.desdepylabs.com/External/gentv |
| 16 | ABC Digital | https://www.abc.com.py/tv/ |
| 20 | Oasis TV | https://tvonline.com.py/oasistv/ |

No se modifica la numeración ni se usa WebView. Las restricciones geográficas
o de autorización del proveedor se conservan; si bloquea la reproducción, se
informa el error y se detienen los reintentos automáticos.

SNT y C9N publican su configuración HLS dentro de JSON escapado dos veces. El
resolvedor admite esa codificación y limita el descubrimiento de CloudFront a
las páginas de esos dos canales. Si el manifiesto utiliza HLS Content Steering,
selecciona una variante de hasta 720p de la ruta predeterminada publicada por el
proveedor. Ante un fallo de transporte puede probar otra ruta declarada en ese
mismo manifiesto, hasta tres en total; una respuesta 401/403 detiene ese flujo.
Los manifiestos sin Content Steering conservan la adaptación nativa del reproductor.

GEN usa directamente el iframe público que publica su web oficial, para evitar
descargar la portada completa en cada renovación. Su parámetro `exp` no se trata
como una fecha límite: la señal comprobada siguió funcionando más de cinco
minutos después de ese valor. La app obtiene la sesión en el dispositivo al
seleccionar el canal y la renueva cada cinco minutos mientras está abierto.

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

## Estado comprobado el 17 de octubre de 2026

- SNT y C9N: las direcciones antiguas respondían 502. Sus páginas oficiales
  publicaron un manifiesto nuevo con dos rutas; la ruta predeterminada entregó
  video H.264 de 1280×720 y audio AAC. Se decodificó un segmento reciente de
  cada canal y se identificaron sus marcas en la imagen, alrededor de las
  08:34 de Paraguay. Se actualizaron únicamente sus fuentes y encabezados
  necesarios en la grilla remota y el respaldo integrado.
- GEN: la fuente anterior respondía 404. El iframe público entregó una nueva
  sesión HLS y un segmento H.264 de 640×360 con audio AAC; se verificó una
  entrevista con la marca GEN. Se actualizó su `webUrl` en la grilla; no se
  publicó una sesión temporal como enlace permanente compartido.
- ABC y Unicanal: el reproductor público entrega metadatos vigentes. Desde este
  entorno la CDN responde 403; la reproducción debe verificarse desde el Android
  en Paraguay con URL obtenida por ese mismo dispositivo.
- Trece: el proveedor devuelve `DM007` (restricción regional) a este entorno
  fuera de Paraguay. No se alteró la región ni se eludió esa restricción.
- Oasis conserva su resolvedor y configuración previa; no fue parte de la
  comprobación de señales del 17 de octubre.

Estas muestras confirman contenido en ese momento; falta comprobar reproducción,
audio sostenido y renovación durante varios minutos en Android/TV Box en Paraguay.
ABC, Unicanal y Trece no se consideran recuperados por esta revisión.

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
La compilación normal conserva `com.example.tv_paraguay`. La versión 1.2.2+6
conserva la interfaz, el logo original y el escalado corregido en 1.2.1. La
compilación y las pruebas simuladas no validan la reproducción real en el teléfono.

La compilación separa las arquitecturas: `app-arm64-v8a-release.apk` para
teléfonos de 64 bits y `app-armeabi-v7a-release.apk` para TV Box de 32 bits.
Para TV Box de 64 bits se utiliza la primera. Se mantienen fullscreen,
grilla remota y reproducción HLS nativa.

## Mantenimiento

La tarea **Renovar canales TV** está configurada cada hora desde el 17 de octubre
de 2026 para revisar los ID 3, 5, 13, 14, 15 y 16. Antes de cambiar la grilla,
debe leer su versión vigente y comprobar manifiesto, segmento y contenido cuando
sea posible. Preserva todos los demás canales, incluidos Ñandutí 720p y Play Deportes.
Solo informa reparaciones verificadas o bloqueos nuevos relevantes.

La revisión remota y la renovación del reproductor tienen funciones diferentes:
la primera mantiene la grilla compartida; la segunda obtiene sesiones válidas
para cada espectador. La app descarga la grilla al iniciar, al volver del segundo
plano y mediante **Actualizar canales**. No consulta el catálogo cada hora por sí
sola. Una sesión ligada a IP o dispositivo no debe copiarse desde el servidor
de mantenimiento a la grilla pública.

Ninguna frecuencia garantiza que un proveedor nunca corte su señal. Si una
página restringe la región o requiere autorización, conservar la fuente y registrar
el bloqueo; no cambiar de país, usar proxies ni publicar credenciales.

Si cambia una página del proveedor, actualizar `webUrl` en la grilla remota y
verificar que el dominio esté permitido en `StreamResolver`. Para cambios en el
formato del HTML o los metadatos, añadir una prueba con una respuesta saneada y
actualizar el parser. No guardar claves privadas, contraseñas o cookies en la
grilla pública. No copiar una URL firmada de un servidor como fuente permanente.

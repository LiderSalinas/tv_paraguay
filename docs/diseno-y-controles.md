# TV Paraguay: diseño y controles (1.2.1+5)

## Funcionamiento

El video es el elemento principal. En teléfono vertical permanece arriba mientras
se desplaza la grilla. En pantallas amplias la grilla está a la izquierda. La
pantalla completa utiliza el mismo reproductor y muestra los canales sobre el
video; abrir la lista, girar o ampliar no crea otro controlador.

El fondo es azul marino, la selección lleva una franja roja y el foco del control
remoto tiene un contorno azul claro. Selección y foco son estados diferentes:
recorrer la lista con flechas no cambia la señal hasta confirmar con OK. El texto
“En reproducción” depende del estado real del controlador; la conexión o el
buffer muestran “Cargando…”.

## Estructura

- `lib/theme/app_theme.dart`: colores, Manrope y estilo compartido de controles.
- `lib/models/playback_status.dart`: estados y textos del reproductor.
- `lib/screens/home_screen.dart`: distribución, selección, foco, pantalla completa,
  panel superpuesto, interacción, números, botón Atrás y temporizadores.
- `lib/widgets/channel_list.dart`: números, logos, nombres de hasta dos líneas,
  selección, foco y altura que responde al tamaño de texto de Android.
- `lib/widgets/video_panel.dart`: controlador HLS, información del canal y estados.
  Conserva resolución, renovación cada cinco minutos y recuperación limitada.
- `assets/fonts/Manrope-Regular.ttf`, `Manrope-SemiBold.ttf` y
  `Manrope-Bold.ttf`: pesos 400, 600 y 700 locales, sin solicitudes de red.
  Se generaron como instancias estáticas de la fuente variable oficial.
- `assets/fonts/OFL.txt`: licencia de la fuente.
- `branding/tv_paraguay_assets.json`: imagen original, iconos y tipografía con hash.
- `tools/prepare_branding.py`: verifica y materializa los recursos antes del build.

El `VideoPanel` ocupa siempre la misma posición con clave dentro del `Stack`.
Solamente cambia su rectángulo. Su ciclo de reproducción se reinicia cuando
cambia el canal o su configuración; la renovación de sesiones continúa usando
el flujo existente, que prepara un candidato antes de reemplazar el anterior.
El panel y la grilla principal usan controladores de desplazamiento separados.

## Uso en teléfono

1. Tocá un canal para reproducirlo.
2. Tocá el video para mostrar el botón de pantalla completa.
3. En pantalla completa, tocá el video para abrir la grilla lateral.
4. Elegí otro canal: se cierra la lista y seguís en pantalla completa.
5. Tocá el video fuera del panel para cerrar la lista sin pausar.
6. Usá las acciones de canal anterior, siguiente o salir de pantalla completa.

La lista está disponible durante la carga o un error de señal. Los controles se
ocultan tras cuatro segundos sin actividad. Un dedo apoyado, un desplazamiento
activo o el uso de teclas suspenden/reinician el conteo correspondiente.

## Uso en TV Box

| Acción | Resultado |
|---|---|
| Flechas arriba/abajo | Mover el foco por los canales |
| OK, fuera de pantalla completa | Reproducir el canal enfocado |
| Flecha derecha | Entrar en pantalla completa |
| OK, pantalla completa sin lista | Abrir los canales en la selección actual |
| OK, con lista abierta | Reproducir el canal enfocado y cerrar la lista |
| CH+ / CH− | Cambiar directamente al siguiente/anterior |
| Números | Elegir el ID del canal; OK confirma o esperar 900 ms |
| Atrás | Cerrar primero panel/controles; después salir de pantalla completa |

Cuando no hay elementos superpuestos ni pantalla completa, Atrás conserva el
comportamiento normal de Android. El botón físico y la navegación del sistema
se gestionan mediante `PopScope`; las teclas del mando usan el mismo flujo.

## Preparación y compilación

```sh
python tools/prepare_branding.py
flutter pub get
flutter analyze
flutter test
```

Para los APK separados de prueba en Bash:

```sh
TV_PARAGUAY_TEST_APK=1 flutter build apk --release --split-per-abi
```

En PowerShell:

```powershell
$env:TV_PARAGUAY_TEST_APK = '1'
flutter build apk --release --split-per-abi
Remove-Item Env:TV_PARAGUAY_TEST_APK
```

La prueba conserva el paquete `com.example.tv_paraguay.prueba` y el nombre
“TV Paraguay Prueba”. Los artefactos arm64 corresponden al teléfono/TV Box de
64 bits; armeabi-v7a al TV Box de 32 bits. La instalación puede pedir desinstalar
una prueba previa si Android detecta una firma diferente entre compilaciones.
La aplicación principal utiliza un paquete distinto.

## Pruebas

- `video_sizing_test.dart`: señales 360p ampliadas a TV/TV Box y teléfono
  horizontal, reducción de 1080p a un panel pequeño, proporciones 4:3 y vertical,
  y conservación del controlador al cambiar tamaño o pantalla completa.
  Mide los límites de la imagen pintada después de sus transformaciones.
- `fullscreen_ux_test.dart`: toque, selección sin salir, controlador persistente,
  foco/OK, CH+, números, Atrás de Android/mando, actividad y carga pendiente.
- `layout_accessibility_test.dart`: 320×568, 390×844, 740×360 y 1280×720, con texto
  a escala 1, 1.6 y 2. Verifica ambas distribuciones y el panel de pantalla completa.
  Produce imágenes de la UI real en `build/ux-previews`, usando fuente local y
  señales de prueba; el rectángulo negro corresponde al video simulado.
- `playback_renewal_test.dart` y `stream_resolver_test.dart`: siguen verificando
  respuestas tardías, renovación, reintentos y fuentes públicas de los canales.

Las pruebas automatizadas usan un reproductor simulado. No certifican la señal
actual de un proveedor, el comportamiento de un mando concreto o el rendimiento
de un TV Box físico. En los dispositivos reales comprobar toque, orientación,
foco, Atrás, reproducción y legibilidad desde la distancia habitual.

## Mantenimiento

### Tamaño de imagen y Ñandutí

La versión 1.2.1 corrige el vídeo pequeño centrado: `SizedBox.expand` impone el
tamaño disponible al `FittedBox`. `BoxFit.contain` amplía o reduce la imagen y
conserva sus proporciones. No colocar un `Center` alrededor del `FittedBox`,
porque afloja las restricciones y deja señales pequeñas a su tamaño nativo.
Se mantiene el mismo controlador y no se recorta el vídeo para llenar la pantalla.
Una señal de 16:9 llena una pantalla de 16:9; en otros formatos quedan solamente
los márgenes necesarios para conservar la imagen completa.

El 16 de octubre de 2026 se verificó que Ñandutí ofrecía HLS oficial de 720p en
`https://nanduti.b-cdn.net/720p.m3u8`, descubierto desde
`https://nanduti.com.py/nanduti-tv` y su reproductor público
`https://argentina-streaming.com/GRadio/nanduti.html`.
Se comprobaron dos segmentos con H.264 de 1280×720, audio AAC e imagen Ñandutí.
La grilla y el respaldo integrado reemplazan únicamente el enlace de Ñandutí;
se conservan su ID 9, logo, nombre y encabezados. La señal anterior era de 640×360.

Para recibir el enlace nuevo basta con **Actualizar canales** y volver a elegir
Ñandutí. La corrección general del escalado requiere instalar el APK 1.2.1 o
posterior. Aumentar el tamaño de un vídeo de baja calidad no agrega detalle:
el tamaño en pantalla y la resolución de la fuente son cuestiones diferentes.
La prueba real debe confirmar imagen completa, audio, mando y estabilidad en
el TV Box; las pruebas con reproductor simulado no sustituyen ese paso.

### Conservación de interfaz y reproducción

Centralizar cambios de color y tipografía en el tema. Al agregar fuentes o
imágenes, actualizar el manifiesto de recursos y preservar sus licencias.
Mantener el reproductor en la misma posición con clave; moverlo entre ramas de
widgets puede destruirlo y reiniciar la señal. Los cambios visuales deben
conservar las pruebas de renovación y la correspondencia entre ID y canal.
Los cambios de orientación se serializan y descartan solicitudes anteriores;
la interfaz responde de inmediato a una salida rápida durante la rotación.
Los temporizadores se cancelan al cerrar la pantalla y al suspender controles;
no iniciar conteos nuevos desde `build` ni desde cada actualización de posición.

# TV Paraguay - App Flutter

Aplicación móvil desarrollada con Flutter para reproducción de canales de televisión en vivo de Paraguay.

## Características

- Reproducción de streams HLS.
- Grilla remota actualizable sin reinstalar la aplicación.
- Respaldo local automático cuando no hay conexión.
- Indicador visible del origen de la lista: en línea o respaldo.
- Interfaz simple y adaptable.
- Pruebas en Android y TV Box.
- Integración con reproductor multimedia.
- Organización de canales por nombre, categoría y URL de transmisión.

## Tecnologías utilizadas

- Flutter
- Dart
- JSON
- HLS / M3U8
- Android
- Git / GitHub

## Objetivo del proyecto

El objetivo de este proyecto es practicar desarrollo móvil con Flutter, manejo de datos externos y reproducción de contenido multimedia en una aplicación funcional.

## Estado

Proyecto en desarrollo y pruebas.

## Compatibilidad con Android TV y Google TV

La versión 1.1.5+2007 se prepara como APK universal ARM: incluye
`armeabi-v7a` (32 bits) y `arm64-v8a` (64 bits). El APK 1.1.4 anterior
incluía solamente ARM64. La marca, el modelo genérico “2K SMART TV” y la
versión Android TV OS 14 no permiten deducir por sí solos las ABI admitidas.

La configuración Android conserva el acceso desde el inicio de TV mediante
Leanback, el banner y la declaración de que no se necesita pantalla táctil.
Esta compilación mantiene la interfaz, el reproductor y el mecanismo de
actualización remota existentes.

### Generar y comprobar el APK

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

No utilizar `--split-per-abi` para esta entrega universal. El flujo
`.github/workflows/build-android-apk.yml` comprueba las bibliotecas nativas de
ambas ABI, la entrada Leanback, que no se requiera pantalla táctil, la versión
mínima de Android y la firma del APK antes de publicar el artefacto.

### Prueba en el televisor JAM

1. Transferir el APK universal al televisor e instalarlo desde la fuente
   autorizada por el usuario.
2. Comprobar que finaliza la instalación y aparece TV Paraguay en las
   aplicaciones del televisor.
3. Abrir la app, actualizar la grilla remota y reproducir un canal.
4. Probar las flechas, OK, Atrás y pantalla completa con el control remoto.

La comprobación del archivo y las pruebas automatizadas no sustituyen esta
prueba física. Si persiste el rechazo, registrar el APK exacto y el error de
instalación; con ADB autorizado, consultar `ro.product.cpu.abilist` para conocer
las ABI reales y obtener la causa concreta del fallo.

### Mantenimiento

Los enlaces de canales siguen actualizándose desde la grilla remota existente.
No se necesita recompilar la app para cambiar enlaces. Los cambios del
empaquetado sí requieren un nuevo APK. Mantener los APK universales con ambas
ABI y conservar la misma clave de firma para permitir futuras actualizaciones
sobre una instalación existente. Actualmente el proyecto utiliza firma de
depuración: antes de distribuir una versión estable, configurar una clave
persistente y protegida.

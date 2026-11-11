# kOS TV

Cliente de [Jellyfin](https://jellyfin.org) para Android TV, hecho a medida de
una configuración multimedia doméstica concreta. También hay versión para el
móvil y para el navegador (en Docker), y más adelante la habrá para Apple TV, a
partir del mismo código.

## Un proyecto personal

kOS TV es un proyecto personal. Está pensado para las personas que usan mi
configuración multimedia y no para el público en general:

- No se publica en tiendas de aplicaciones.
- Sus funciones y decisiones responden a esa configuración y a quienes la usan,
  no a las necesidades de cualquier servidor Jellyfin.
- No se ofrece soporte ni se aceptan peticiones de funciones o contribuciones.
- Puede cambiar en cualquier momento, sin aviso y sin mantener compatibilidad.

## Código abierto, como referencia

El código fuente es público para quien quiera consultarlo o usarlo como
referencia en sus propios proyectos, respetando la licencia (ver abajo). Úsalo
bajo tu propia responsabilidad.

## Basado en Moonfin

kOS TV parte de [Moonfin Core](https://github.com/Moonfin-Client/Moonfin-Core),
un cliente multimedia de código abierto hecho con Flutter. Este repositorio
conserva el historial completo de Moonfin; desde ahí evoluciona por su cuenta.
Todo el mérito del trabajo de base es de sus autores y colaboradores: gracias.

kOS TV no está afiliado ni respaldado por Moonfin ni por el proyecto Jellyfin.

Lo que se ha cambiado respecto a Moonfin, y lo que queda pendiente, está en
[`KOSTV.md`](KOSTV.md).

## Si usas mi configuración

Instala en la tele el archivo `KosTV_AndroidTV_v….apk` de la
[última versión publicada](https://github.com/kikope97/kos-TV/releases/latest).
A partir de ahí la app avisa sola cuando hay una versión nueva y se actualiza
con el botón **Actualizar ahora**. La primera vez, Android pide permiso para
que kOS TV pueda instalar actualizaciones.

En el móvil, el archivo es `KosTV_Android_v….apk`. Para usarla desde el
navegador, la versión web se instala en el servidor como un contenedor Docker:
ver [`docs/web.md`](docs/web.md).

## Licencia

Como Moonfin, kOS TV se distribuye bajo la
[GNU General Public License, versión 2](LICENSE) o, a tu elección, cualquier
versión posterior. Las modificaciones de este repositorio se publican bajo la
misma licencia.

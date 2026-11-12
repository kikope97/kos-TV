# Revisión semanal del proyecto principal y del complemento

Cada semana se mira qué ha cambiado en:

- **La app de la que partimos:** Moonfin-Core (`upstream` en git,
  `https://github.com/Moonfin-Client/Moonfin-Core`, rama `main`). Se busca lo
  que merece la pena traer a kOS TV: arreglos del reproductor, fallos,
  rendimiento, seguridad y mejoras que encajen con la familia.
- **El complemento del servidor:** desde el 2026-11-12 es nuestro
  (`complemento/`, el complemento «kOS TV»), una copia de Moonbase, el oficial
  (`https://github.com/Moonfin-Client/Plugin`, versiones en su
  [`manifest.json`](https://raw.githubusercontent.com/Moonfin-Client/Plugin/refs/heads/master/manifest.json)
  y en sus etiquetas). Con especial cuidado: qué ha cambiado en el oficial (solo
  Jellyfin), qué hay nuevo que aprovechar y qué podría romper la app (las rutas
  `/Moonfin/...` que usa). Se decide si traerlo a nuestra copia (y publicar
  `X.Y.Z.1`) o esperar; cómo se trae, en `complemento/README.md`.

Cómo se hace y cuándo se pregunta: ver la norma en [`CLAUDE.md`](../CLAUDE.md).

**Cada revisión se apunta aquí, siempre**, aunque no se integre nada o el
usuario decida dejarla para otro día (entonces se apunta que se pospuso). Es el
historial de dónde venimos y de lo que se ha ido haciendo: no se borra ni se
reescribe lo anterior, solo se añade arriba.

## Dónde estamos ahora

Se actualiza al terminar cada revisión. La siguiente empieza justo aquí.

| | |
|---|---|
| Copia original de kOS TV | upstream `3d87996d2` (2026-11-10): Moonfin 3.0.0 más 658 commits posteriores sin publicar |
| Último commit de upstream revisado | ninguno: se parte de `3d87996d2` |
| Última versión del complemento oficial revisada | 3.1.0.0 (2026-11-12, etiqueta `3.1.0`, commit `9e05034`): base del nuestro |
| Nuestro complemento | «kOS TV» 3.1.0.1 (la oficial 3.1.0 con nombre, identificador y textos propios), en `complemento/`. En la rama, sin publicar: sin Seerr ni su calendario, y la página de ajustes en español (será la 3.1.0.2) |
| Complemento instalado en el servidor de casa | el oficial, 3.0.0.0, instalado el 2026-11-11 (Seerr apagado, sin push); se pasa al nuestro, 3.1.0.1, el 2026-11-12 |
| Última revisión | ninguna: punto de partida apuntado el 2026-11-11 |
| Próxima revisión | a partir del 2026-11-18 |

## Cómo apuntar cada revisión

Copiar este bloque arriba del registro y rellenarlo:

```
### AAAA-MM-DD

- **App, revisado:** upstream `<desde>`..`<hasta>` (N commits, fechas).
- **Integrado:** qué se trajo y con qué commit nuestro (o «nada»).
- **Descartado:** qué no aplica y por qué (Plex, Emby, Silo, escritorio,
  Seerr, Firebase, ya lo teníamos…).
- **Dudoso o pendiente:** lo que el usuario decide más adelante.
- **Complemento, revisado:** versiones oficiales `<desde>` → `<hasta>`; qué
  cambia en las rutas `/Moonfin/...` que usa la app; qué hay nuevo; si rompe
  algo.
- **Decisión del complemento:** traerlo a nuestra copia (con qué commit y qué
  versión nuestra se publicó) o esperar, y por qué. Versión instalada en el
  servidor después.
- **Notas:** cualquier otra cosa que convenga recordar.
```

## Registro

### 2026-11-12 · Complemento sin Seerr y en español (sin revisión)

- **App, revisado:** nada; la primera revisión sigue para el 2026-11-18.
- **Complemento:** a petición del usuario, fuera Seerr y lo que dependía de él
  (el calendario de Sonarr/Radarr con sus recordatorios y el aviso de
  descargas atascadas); a las apps se les dice que no hay. La página de
  ajustes, traducida al español con los nombres de la app; lo de Seerr queda
  oculto con la clase `kostvSinSeerr`. **Para las próximas revisiones:** los
  cambios del oficial en Seerr, el calendario o las descargas atascadas no
  aplican, y los textos nuevos de su página de ajustes llegarán en inglés y
  hay que traducirlos. Se publica como 3.1.0.2 cuando el usuario lo diga.

### 2026-11-12 · El complemento pasa a ser nuestro (sin revisión de la app)

- **App, revisado:** nada; la primera revisión de la app sigue para el
  2026-11-18, desde `3d87996d2`.
- **Complemento, revisado:** el oficial 3.0.0.0 → 3.1.0.0 (publicada hoy).
  Trae ver juntos alojado en el servidor, búsqueda inteligente con frases,
  calendario de Radarr/Sonarr con avisos, etiquetas de pósteres, logotipos de
  estudios, valores por defecto por tipo de aparato y seis ajustes más que se
  sincronizan, entre otros arreglos. Rutas: todas las que usa la app siguen
  (solo `ClientLog`, los informes de diagnóstico, no existe en Jellyfin, ni en
  la 3.0). No rompe nada que se haya visto.
- **Decisión del complemento:** el usuario decide tener su propio complemento,
  partiendo de la 3.1.0 oficial, para poder añadirle lo que necesite kOS TV
  (por ejemplo, sincronizar sus ajustes propios). Se trae a `complemento/` con
  `git subtree` (commit de la copia `46cffcaa2`), se queda solo lo de Jellyfin y
  se le da identidad propia: nombre «kOS TV», identificador
  `561f86df-fa00-4fca-aa4d-2fed0e332670`, imagen, textos del panel, tareas en
  español y la invitación de «Ver juntos». Mantiene las rutas `/Moonfin/...` y
  la carpeta de datos del oficial, así que al cambiar se conserva todo
  (probado en un Jellyfin 10.10.7 de prueba: ajustes del administrador, los de
  cada persona y el historial de tareas). Se publica como 3.1.0.1 con su propio
  catálogo; en el servidor se desinstala el oficial y se instala este.
- **Notas:** la web de Moonfin que el paquete oficial lleva dentro
  (`/Moonfin/Web/`) no va en el nuestro; quizá más adelante, la web de kOS TV.
  La página de ajustes del complemento sigue en inglés, como la oficial, salvo
  el nombre.

### 2026-11-11 · Punto de partida (sin revisión)

- **Decisión:** el usuario decide partir de aquí, sin revisar ahora (acabamos
  de salir de esta versión), y hacer la primera revisión en una semana, hacia
  el 2026-11-18.
- **App:** la copia de kOS TV sale de upstream `3d87996d2` (2026-11-10). La
  última versión publicada de Moonfin es la 3.0.0 (2026-10-30) y ya está
  dentro, junto con los 658 commits que hicieron después hasta el 10 de
  noviembre (trabajo aún sin publicar como versión). Desde la copia, en
  upstream `main` hay 23 commits más, también sin publicar, hasta
  `d31a38f8b` (2026-11-11). No son versiones sino cambios sueltos (arreglos,
  traducciones, cosas de Seerr, Silo y Plex…). No están en kOS TV, así que la
  primera revisión empieza en `3d87996d2` y los incluye.
- **Desde la copia, kOS TV ha cambiado mucho** (ver la tabla de `KOSTV.md`):
  marca propia, sin Plex, Emby, escritorio, Seerr ni Firebase, servidor de casa
  integrado, Descubrir (Stremfin), web en Docker, aplicaciones de la tele,
  intro en vídeo… Todo lo que venga de upstream se mira teniendo eso en
  cuenta.
- **Complemento:** el oficial va por la 3.0.0.0 (2026-10-30, Jellyfin 10.10 o
  superior), que es la 2.5.0 renumerada para ir con las apps Moonfin 3.0.0.
  Se decidió usar el oficial y no una copia propia (que lo mantengan ellos; si
  un día rompe algo, se vuelve a una versión anterior o se copia y lo seguimos
  nosotros). El usuario lo instaló el mismo 2026-11-11 desde el catálogo
  (3.0.0.0, la última). Configuración recomendada: Seerr apagado y sin push
  (kOS TV no se apunta a las notificaciones), clave de TMDB (y de MDBList si
  se quiere), recomendaciones y logos de estudios encendidos, anime solo si
  hay anime. «User defaults» sin tocar de momento.
